-- ============================================================================
-- WDOS Migration 024 — 14-Day Leadership Activation Journey (FRD §B)
-- When a person reaches Approved, her journey starts automatically:
-- a 14-day clock and a milestone checklist. Some milestones she confirms
-- herself; the rest her leaders confirm. When every required milestone is
-- done, the system itself advances her to Activated (reason recorded).
-- Extensions are a leadership decision with a written reason.
-- ============================================================================

create type public.journey_status as enum
  ('in_progress', 'completed', 'incomplete', 'deferred');

-- ---------------------------------------------------------------------------
-- 1. MILESTONE CATALOGUE (HQ-editable)
-- ---------------------------------------------------------------------------
create table public.activation_milestones (
  id           uuid primary key default gen_random_uuid(),
  seq          int not null,
  code         text not null unique,
  name         text not null check (char_length(name) between 3 and 160),
  day_target   int not null check (day_target between 1 and 14),
  is_required  boolean not null default true,
  self_service boolean not null default false,   -- the person herself confirms
  is_active    boolean not null default true
);

alter table public.activation_milestones enable row level security;
create policy milestones_read on public.activation_milestones
  for select to authenticated using (true);
create policy milestones_manage on public.activation_milestones
  for all to authenticated
  using (public.is_case_hq()) with check (public.is_case_hq());

insert into public.activation_milestones
  (seq, code, name, day_target, is_required, self_service) values
 (1, 'willingness_confirmed',
    'Willingness and availability to serve confirmed', 2, true, true),
 (2, 'details_verified',
    'Personal, professional and geographic details verified', 3, true, false),
 (3, 'code_of_conduct_accepted',
    'WODDI values, policies and code of conduct accepted', 3, true, true),
 (4, 'placement_confirmed',
    'Assigned to network, unit and role', 4, true, false),
 (5, 'supervisor_introduced',
    'Introduced to the immediate supervisor', 5, true, false),
 (6, 'orientation_completed',
    'Orientation on vision, mission, values and structure completed',
    7, true, false),
 (7, 'orientation_meeting_attended',
    'Orientation or team meeting attended', 10, false, false),
 (8, 'training_completed',
    'Mandatory introductory training completed', 12, true, false)
on conflict (code) do nothing;

-- ---------------------------------------------------------------------------
-- 2. JOURNEYS & PROGRESS
-- ---------------------------------------------------------------------------
create table public.activation_journeys (
  id             uuid primary key default gen_random_uuid(),
  profile_id     uuid not null unique references public.profiles(id)
                   on delete cascade,
  status         public.journey_status not null default 'in_progress',
  started_at     timestamptz not null default now(),
  due_at         timestamptz not null default now() + interval '14 days',
  extended_until timestamptz,
  completed_at   timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create trigger journeys_touch before update on public.activation_journeys
  for each row execute function public.touch_updated_at();
create trigger journeys_audit after insert or update or delete
  on public.activation_journeys for each row
  execute function public.audit_row();

create table public.activation_progress (
  journey_id   uuid not null references public.activation_journeys(id)
                 on delete cascade,
  milestone_id uuid not null references public.activation_milestones(id)
                 on delete restrict,
  completed_at timestamptz not null default now(),
  completed_by uuid not null references public.profiles(id)
                 default auth.uid(),
  note         text check (note is null or char_length(note) <= 1000),
  primary key (journey_id, milestone_id)
);

create trigger progress_audit after insert or update or delete
  on public.activation_progress for each row
  execute function public.audit_row();

-- ---------------------------------------------------------------------------
-- 3. ACCESS: the person herself, leaders over her unit, HQ
-- ---------------------------------------------------------------------------
create or replace function public.can_see_journey(jid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from activation_journeys j
    join profiles p on p.id = j.profile_id
    where j.id = jid
      and (j.profile_id = auth.uid()
        or p.org_unit_id in (select administered_units())
        or is_case_hq())
  );
$$;

alter table public.activation_journeys enable row level security;
alter table public.activation_progress  enable row level security;

create policy journeys_read on public.activation_journeys
  for select to authenticated using (public.can_see_journey(id));
create policy progress_read on public.activation_progress
  for select to authenticated using (public.can_see_journey(journey_id));
-- All writes flow through the RPCs below.

-- ---------------------------------------------------------------------------
-- 4. AUTOMATIC START on reaching Approved (+ manual start for backfill)
-- ---------------------------------------------------------------------------
create or replace function public.journey_autostart()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'approved' and old.status is distinct from 'approved' then
    insert into activation_journeys (profile_id)
    values (new.id)
    on conflict (profile_id) do nothing;
  end if;
  return new;
end; $$;

drop trigger if exists journey_autostart_trg on public.profiles;
create trigger journey_autostart_trg after update of status on public.profiles
  for each row execute function public.journey_autostart();

create or replace function public.start_activation(pid uuid)
returns public.activation_journeys
language plpgsql security definer set search_path = public as $$
declare j public.activation_journeys; unit uuid;
begin
  select org_unit_id into unit from profiles where id = pid;
  if unit is null and not is_case_hq() then
    raise exception 'Profile not found or not placed in a unit';
  end if;
  if not (is_case_hq() or unit in (select administered_units())) then
    raise exception 'Only leaders over the member''s unit can start activation';
  end if;
  insert into activation_journeys (profile_id) values (pid)
  on conflict (profile_id) do nothing;
  select * into j from activation_journeys where profile_id = pid;
  return j;
end; $$;

-- ---------------------------------------------------------------------------
-- 5. WORKFLOW RPCs
-- ---------------------------------------------------------------------------
create or replace function public.complete_milestone(
  jid uuid, mid uuid, p_note text default null)
returns void
language plpgsql security definer set search_path = public as $$
declare
  j public.activation_journeys;
  m public.activation_milestones;
  is_owner boolean;
  is_leader boolean;
  remaining int;
begin
  select * into j from activation_journeys where id = jid for update;
  if j.id is null then raise exception 'Journey not found'; end if;
  if j.status <> 'in_progress' then
    raise exception 'This journey is no longer in progress';
  end if;
  select * into m from activation_milestones where id = mid and is_active;
  if m.id is null then raise exception 'Milestone not found'; end if;

  is_owner := (j.profile_id = auth.uid());
  is_leader := is_case_hq() or exists (
    select 1 from profiles p
    where p.id = j.profile_id
      and p.org_unit_id in (select administered_units()));

  if not (is_leader or (is_owner and m.self_service)) then
    raise exception 'You do not have authority to confirm this milestone';
  end if;

  insert into activation_progress (journey_id, milestone_id, completed_by, note)
  values (jid, mid, auth.uid(), p_note)
  on conflict do nothing;

  -- All required milestones done → journey completes → person Activated.
  select count(*) into remaining
  from activation_milestones am
  where am.is_required and am.is_active
    and not exists (select 1 from activation_progress ap
                    where ap.journey_id = jid
                      and ap.milestone_id = am.id);
  if remaining = 0 then
    update activation_journeys
       set status = 'completed', completed_at = now()
     where id = jid;
    perform set_config('wdos.reason',
      'Activation journey completed (all required milestones)', true);
    update profiles set status = 'activated'
     where id = j.profile_id and status = 'approved';
  end if;
end; $$;

create or replace function public.extend_activation(
  jid uuid, until timestamptz, reason text)
returns public.activation_journeys
language plpgsql security definer set search_path = public as $$
declare j public.activation_journeys;
begin
  select * into j from activation_journeys where id = jid for update;
  if j.id is null then raise exception 'Journey not found'; end if;
  if not (is_case_hq() or exists (
      select 1 from profiles p
      where p.id = j.profile_id
        and p.org_unit_id in (select administered_units()))) then
    raise exception 'Only leaders over the member''s unit can extend activation';
  end if;
  if reason is null or char_length(trim(reason)) < 5 then
    raise exception 'A reason is required for an extension';
  end if;
  if until <= coalesce(j.extended_until, j.due_at) then
    raise exception 'The new deadline must be later than the current one';
  end if;
  perform set_config('wdos.reason', reason, true);
  update activation_journeys
     set extended_until = until
   where id = jid returning * into j;
  return j;
end; $$;

create or replace function public.close_journey(
  jid uuid, outcome public.journey_status, reason text)
returns void
language plpgsql security definer set search_path = public as $$
declare j public.activation_journeys;
begin
  if outcome not in ('incomplete', 'deferred') then
    raise exception 'Outcome must be incomplete or deferred';
  end if;
  select * into j from activation_journeys where id = jid for update;
  if j.id is null then raise exception 'Journey not found'; end if;
  if not (is_case_hq() or exists (
      select 1 from profiles p
      where p.id = j.profile_id
        and p.org_unit_id in (select administered_units()))) then
    raise exception 'Only leaders over the member''s unit can close a journey';
  end if;
  if reason is null or char_length(trim(reason)) < 5 then
    raise exception 'A reason is required';
  end if;
  perform set_config('wdos.reason', reason, true);
  update activation_journeys set status = outcome where id = jid;
end; $$;

insert into public.schema_migrations (version, name)
values (24, 'activation_journey') on conflict (version) do nothing;
