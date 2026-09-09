-- ============================================================================
-- WDOS Migration 007 — Meetings & Attendance
-- Leaders schedule for their units; unit members see their meetings;
-- organisers/leaders record minutes and attendance. Audited throughout.
-- Attendance rows are the raw material for attendance-rate KPIs.
-- ============================================================================

create type public.meeting_status as enum ('scheduled', 'completed', 'cancelled');
create type public.meeting_mode   as enum ('in_person', 'virtual', 'hybrid');

create table public.meetings (
  id          uuid primary key default gen_random_uuid(),
  title       text not null check (char_length(title) between 3 and 160),
  agenda      text check (agenda is null or char_length(agenda) <= 4000),
  org_unit_id uuid not null references public.org_units(id) on delete restrict,
  organiser   uuid not null references public.profiles(id) default auth.uid(),
  mode        public.meeting_mode not null default 'in_person',
  location    text check (location is null or char_length(location) <= 300),
  starts_at   timestamptz not null,
  ends_at     timestamptz not null,
  status      public.meeting_status not null default 'scheduled',
  minutes     text check (minutes is null or char_length(minutes) <= 8000),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint meeting_times_valid check (ends_at > starts_at)
);

create index meetings_unit_time_idx on public.meetings (org_unit_id, starts_at);
create index meetings_time_idx on public.meetings (starts_at)
  where status = 'scheduled';

create table public.meeting_attendance (
  id          uuid primary key default gen_random_uuid(),
  meeting_id  uuid not null references public.meetings(id) on delete cascade,
  profile_id  uuid not null references public.profiles(id) on delete cascade,
  present     boolean not null,
  recorded_by uuid not null references public.profiles(id) default auth.uid(),
  recorded_at timestamptz not null default now(),
  unique (meeting_id, profile_id)
);

create index attendance_meeting_idx on public.meeting_attendance (meeting_id);
create index attendance_profile_idx on public.meeting_attendance (profile_id);

create trigger meetings_touch before update on public.meetings
  for each row execute function public.touch_updated_at();
create trigger meetings_audit after insert or update or delete
  on public.meetings for each row execute function public.audit_row();
create trigger attendance_audit after insert or update or delete
  on public.meeting_attendance for each row execute function public.audit_row();

-- ---------------------------------------------------------------------------
-- Authority helper: meeting manager = organiser, leader over the unit, or HQ
-- ---------------------------------------------------------------------------
create or replace function public.is_meeting_manager(m public.meetings)
returns boolean language sql stable security definer set search_path = public as $$
  select m.organiser = auth.uid()
      or m.org_unit_id in (select administered_units())
      or has_role(array['super_admin','executive_director','hq_team']::public.role_code[]);
$$;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
alter table public.meetings           enable row level security;
alter table public.meeting_attendance enable row level security;

-- Read: managers, plus every member whose home unit is the meeting's unit.
create policy meetings_read on public.meetings
  for select to authenticated
  using (
    public.is_meeting_manager(meetings)
    or exists (select 1 from public.profiles p
               where p.id = auth.uid()
                 and p.org_unit_id = meetings.org_unit_id)
  );

create policy meetings_insert on public.meetings
  for insert to authenticated
  with check (
    organiser = auth.uid()
    and status = 'scheduled'
    and (org_unit_id in (select public.administered_units())
         or public.has_role(array['super_admin','executive_director','hq_team']::public.role_code[]))
  );

create policy meetings_update on public.meetings
  for update to authenticated
  using (public.is_meeting_manager(meetings))
  with check (public.is_meeting_manager(meetings));

-- Attendance: visible wherever the meeting is visible; writable by managers.
create policy attendance_read on public.meeting_attendance
  for select to authenticated
  using (exists (select 1 from public.meetings m where m.id = meeting_id));

create policy attendance_write on public.meeting_attendance
  for all to authenticated
  using (exists (select 1 from public.meetings m
                 where m.id = meeting_id and public.is_meeting_manager(m)))
  with check (
    recorded_by = auth.uid()
    and exists (select 1 from public.meetings m
                where m.id = meeting_id and public.is_meeting_manager(m))
  );

-- ---------------------------------------------------------------------------
-- Status transition guard
-- ---------------------------------------------------------------------------
create or replace function public.meetings_guard()
returns trigger language plpgsql as $$
begin
  if new.status is distinct from old.status then
    if not (
      (old.status = 'scheduled' and new.status in ('completed','cancelled'))
      or (old.status = 'cancelled' and new.status = 'scheduled')  -- un-cancel
    ) then
      raise exception 'Invalid meeting transition: % -> %', old.status, new.status;
    end if;
  end if;
  return new;
end; $$;

create trigger meetings_guard_trg before update on public.meetings
  for each row execute function public.meetings_guard();
