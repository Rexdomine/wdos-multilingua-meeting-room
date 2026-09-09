-- ============================================================================
-- WDOS Migration 052 — Meetings v2 & Comms Hardening (Phase 59)
--
-- 1. PLATFORM CHOICE on every meeting: built-in WODDI Room, Zoom, Google
--    Meet, or another link — stored and shown.
-- 2. AUDIENCES: HQ team · WGMN Nigeria · WGMN Africa · WNNN Nigeria ·
--    WNNN Africa · everyone · or just the unit — the announcement trigger
--    now invites exactly that audience (bell, popup, email).
-- 3. LIVE ATTENDANCE: meeting_checkins records every join the second it
--    happens (realtime), powering names-as-they-arrive and region stats.
-- 4. MEETING DOCUMENTS: attach files to a meeting (private bucket,
--    signed links).
-- 5. MESSAGE FILES GO PRIVATE: the staff-files bucket (public since 018)
--    is now private, and any signed-in member may attach — matching the
--    two-way messaging opened in Phase 49.
-- ============================================================================

-- 1 ▸ platform + audience columns
alter table public.meetings
  add column if not exists platform text not null default 'woddi'
    check (platform in ('woddi', 'zoom', 'meet', 'other')),
  add column if not exists audience text not null default 'unit'
    check (audience in ('unit', 'hq', 'wgmn_ng', 'wgmn_all',
                        'wnnn_ng', 'wnnn_all', 'all'));

-- helper: is a unit inside a given country (walk up the tree)?
create or replace function public.unit_in_country(uid uuid, iso char(2))
returns boolean language sql stable
security definer set search_path = public as $$
  with recursive up as (
    select id, parent_id, country_iso from org_units where id = uid
    union all
    select o.id, o.parent_id, o.country_iso
      from org_units o join up on o.id = up.parent_id
  )
  select exists (select 1 from up where country_iso = upper(iso));
$$;

-- 2 ▸ audience-aware meeting announcements
create or replace function public.meeting_notice()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into member_notices (profile_id, kind, title, body, meta)
  select p.id, 'meeting',
    'Meeting: ' || left(new.title, 90),
    to_char(new.starts_at, 'Dy DD Mon YYYY, HH24:MI')
      || case when new.location is not null and new.location <> ''
              then e'\n' || new.location else '' end
      || case when new.agenda is not null and new.agenda <> ''
              then e'\nAgenda: ' || left(new.agenda, 240) else '' end,
    jsonb_build_object('meeting', new.id)
    from profiles p
   where p.merged_into is null
     and p.id <> new.organiser
     and (
       (new.audience = 'unit' and p.org_unit_id = new.org_unit_id)
       or (new.audience = 'hq'
           and exists (select 1 from staff s
                        where s.profile_id = p.id and s.is_active))
       or (new.audience in ('wgmn_ng','wgmn_all') and p.network = 'WGMN'
           and p.status in ('approved','activated','in_training','active','reinstated')
           and (new.audience = 'wgmn_all'
                or unit_in_country(p.org_unit_id, 'NG')))
       or (new.audience in ('wnnn_ng','wnnn_all') and p.network = 'WNNN'
           and p.status in ('approved','activated','in_training','active','reinstated')
           and (new.audience = 'wnnn_all'
                or unit_in_country(p.org_unit_id, 'NG')))
       or (new.audience = 'all'
           and (p.status in ('approved','activated','in_training','active','reinstated')
                or exists (select 1 from staff s
                            where s.profile_id = p.id and s.is_active)))
     )
   limit 1000;
  return new;
end; $$;

drop trigger if exists meetings_notice on public.meetings;
create trigger meetings_notice
  after insert on public.meetings
  for each row execute function public.meeting_notice();

-- 3 ▸ live check-ins
create table if not exists public.meeting_checkins (
  meeting_id uuid not null references public.meetings(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  joined_at  timestamptz not null default now(),
  primary key (meeting_id, profile_id)
);
alter table public.meeting_checkins enable row level security;

drop policy if exists checkins_read on public.meeting_checkins;
create policy checkins_read on public.meeting_checkins
  for select to authenticated using (true);

drop policy if exists checkins_self on public.meeting_checkins;
create policy checkins_self on public.meeting_checkins
  for insert to authenticated with check (profile_id = auth.uid());

create or replace function public.meeting_join(mid uuid)
returns void language sql security definer set search_path = public as $$
  insert into meeting_checkins (meeting_id, profile_id)
  values (mid, auth.uid())
  on conflict (meeting_id, profile_id) do nothing;
$$;
grant execute on function public.meeting_join(uuid) to authenticated;
revoke execute on function public.meeting_join(uuid) from anon;

do $$
begin
  alter publication supabase_realtime add table public.meeting_checkins;
  raise notice 'meeting_checkins added to realtime';
exception when duplicate_object then
  raise notice 'meeting_checkins already realtime';
when others then
  raise notice 'realtime add failed: %', sqlerrm;
end $$;

-- 4 ▸ meeting documents (private)
create table if not exists public.meeting_files (
  id         uuid primary key default gen_random_uuid(),
  meeting_id uuid not null references public.meetings(id) on delete cascade,
  name       text not null check (char_length(name) <= 200),
  path       text not null,
  uploaded_by uuid not null references public.profiles(id) default auth.uid(),
  created_at timestamptz not null default now()
);
alter table public.meeting_files enable row level security;

drop policy if exists meeting_files_read on public.meeting_files;
create policy meeting_files_read on public.meeting_files
  for select to authenticated using (true);

drop policy if exists meeting_files_write on public.meeting_files;
create policy meeting_files_write on public.meeting_files
  for insert to authenticated
  with check (uploaded_by = auth.uid());

insert into storage.buckets (id, name, public)
values ('meeting-files', 'meeting-files', false)
on conflict (id) do update set public = false;

drop policy if exists meeting_files_obj_read on storage.objects;
create policy meeting_files_obj_read on storage.objects
  for select to authenticated using (bucket_id = 'meeting-files');

drop policy if exists meeting_files_obj_insert on storage.objects;
create policy meeting_files_obj_insert on storage.objects
  for insert to authenticated with check (bucket_id = 'meeting-files');

-- 5 ▸ message files: private bucket, any signed-in sender may attach
update storage.buckets set public = false where id = 'staff-files';

drop policy if exists staff_files_insert on storage.objects;
create policy staff_files_insert on storage.objects
  for insert to authenticated with check (bucket_id = 'staff-files');

drop policy if exists staff_files_read on storage.objects;
create policy staff_files_read on storage.objects
  for select to authenticated using (bucket_id = 'staff-files');

insert into public.schema_migrations (version, name)
values (52, 'meetings_v2_comms') on conflict (version) do nothing;
