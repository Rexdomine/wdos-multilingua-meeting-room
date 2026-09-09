-- ============================================================================
-- WDOS Migration 001 — Identity, Organisational Structure, Roles, Audit
-- WODDI Digital Operating System
-- Requires: Supabase (PostgreSQL 15+, auth schema present)
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. ENUMS
-- ---------------------------------------------------------------------------

create type public.network_code as enum ('WGMN', 'WNNN');

-- Membership lifecycle (Gap Analysis §7)
create type public.member_status as enum (
  'applicant', 'under_review', 'approved', 'activated', 'in_training',
  'active', 'inactive', 'suspended', 'resigned', 'removed', 'alumni',
  'reinstated'
);

-- Organisational levels (Executive Master Prompt: HQ → Chapter)
create type public.org_level as enum (
  'headquarters', 'country', 'state_region', 'district_lga', 'chapter'
);

create type public.role_code as enum (
  'super_admin', 'executive_director', 'hq_team',
  'country_rep', 'deputy_country_rep',
  'state_coordinator', 'assistant_state_coordinator',
  'district_coordinator', 'chapter_lead',
  'volunteer', 'member', 'programme_staff', 'institute_admin',
  'donor', 'external_partner'
);

-- ---------------------------------------------------------------------------
-- 2. ORGANISATIONAL UNITS (single adjacency-list hierarchy, all levels)
-- ---------------------------------------------------------------------------

create table public.org_units (
  id          uuid primary key default gen_random_uuid(),
  parent_id   uuid references public.org_units(id) on delete restrict,
  level       public.org_level not null,
  name        text not null check (char_length(name) between 2 and 120),
  country_iso char(2),                     -- ISO 3166-1 alpha-2, country level+
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  -- HQ is the only unit allowed to have no parent
  constraint org_root_only_hq check (parent_id is not null or level = 'headquarters')
);

create index org_units_parent_idx on public.org_units (parent_id);
create index org_units_level_idx  on public.org_units (level);
create unique index org_units_single_hq
  on public.org_units (level) where level = 'headquarters';

comment on table public.org_units is
  'HQ → Country → State/Region → District/LGA → Chapter hierarchy for all of Africa.';

-- Recursive helper: all descendant unit ids of a unit (inclusive).
create or replace function public.org_unit_subtree(root uuid)
returns setof uuid
language sql stable security definer set search_path = public as $$
  with recursive sub as (
    select id from org_units where id = root
    union all
    select o.id from org_units o join sub s on o.parent_id = s.id
  )
  select id from sub;
$$;

-- ---------------------------------------------------------------------------
-- 3. PROFILES (1:1 with auth.users)
-- ---------------------------------------------------------------------------

create table public.profiles (
  id              uuid primary key references auth.users(id) on delete cascade,
  membership_no   text unique,             -- assigned on approval
  first_name      text not null check (char_length(first_name) between 1 and 60),
  last_name       text not null check (char_length(last_name) between 1 and 60),
  email           text not null unique,
  phone           text,
  network         public.network_code not null,
  status          public.member_status not null default 'applicant',
  org_unit_id     uuid references public.org_units(id) on delete restrict,
  preferred_locale text not null default 'en'
    check (preferred_locale in ('en','fr','pt','ar','sw','ha','yo','ig')),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create index profiles_org_unit_idx on public.profiles (org_unit_id);
create index profiles_status_idx   on public.profiles (status);
create index profiles_network_idx  on public.profiles (network);

-- Duplicate prevention (Gap Analysis §6): case-insensitive email uniqueness,
-- and phone uniqueness where present.
create unique index profiles_email_ci_uq on public.profiles (lower(email));
create unique index profiles_phone_uq on public.profiles (phone)
  where phone is not null;

-- ---------------------------------------------------------------------------
-- 4. ROLE ASSIGNMENTS (a person can hold roles at specific units)
-- ---------------------------------------------------------------------------

create table public.role_assignments (
  id          uuid primary key default gen_random_uuid(),
  profile_id  uuid not null references public.profiles(id) on delete cascade,
  role        public.role_code not null,
  org_unit_id uuid not null references public.org_units(id) on delete restrict,
  assigned_by uuid references public.profiles(id),
  starts_at   timestamptz not null default now(),
  ends_at     timestamptz,                 -- null = current; history preserved
  created_at  timestamptz not null default now(),
  constraint role_period_valid check (ends_at is null or ends_at > starts_at)
);

create index role_assign_profile_idx on public.role_assignments (profile_id)
  where ends_at is null;
create index role_assign_unit_idx on public.role_assignments (org_unit_id)
  where ends_at is null;

-- One person cannot hold the same role twice at the same unit concurrently.
create unique index role_assign_active_uq
  on public.role_assignments (profile_id, role, org_unit_id)
  where ends_at is null;

-- ---------------------------------------------------------------------------
-- 5. AUTHORISATION HELPERS (used by RLS)
-- ---------------------------------------------------------------------------

-- Does the current user hold any of the given roles (anywhere)?
create or replace function public.has_role(roles public.role_code[])
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from role_assignments
    where profile_id = auth.uid() and role = any(roles) and ends_at is null
  );
$$;

-- Units the current user administers: the subtree under every unit where
-- they hold a leadership role.
create or replace function public.administered_units()
returns setof uuid
language sql stable security definer set search_path = public as $$
  select distinct s.id
  from role_assignments ra
  cross join lateral org_unit_subtree(ra.org_unit_id) as s(id)
  where ra.profile_id = auth.uid()
    and ra.ends_at is null
    and ra.role in ('super_admin','executive_director','hq_team',
                    'country_rep','deputy_country_rep',
                    'state_coordinator','assistant_state_coordinator',
                    'district_coordinator','chapter_lead');
$$;

-- ---------------------------------------------------------------------------
-- 6. IMMUTABLE AUDIT LOG (Gap Analysis §4)
-- ---------------------------------------------------------------------------

create table public.audit_log (
  id          bigint generated always as identity primary key,
  occurred_at timestamptz not null default now(),
  actor_id    uuid,                        -- auth.uid(); null = system job
  action      text not null,               -- INSERT | UPDATE | DELETE
  table_name  text not null,
  record_id   text not null,
  old_values  jsonb,
  new_values  jsonb,
  reason      text                         -- set via set_config('wdos.reason')
);

create index audit_log_record_idx on public.audit_log (table_name, record_id);
create index audit_log_actor_idx  on public.audit_log (actor_id, occurred_at);

-- Immutability: nobody, including table owner paths through the API, may
-- modify or remove audit rows.
create or replace function public.audit_block_change()
returns trigger language plpgsql as $$
begin
  raise exception 'audit_log is append-only';
end; $$;

create trigger audit_log_no_update before update on public.audit_log
  for each row execute function public.audit_block_change();
create trigger audit_log_no_delete before delete on public.audit_log
  for each row execute function public.audit_block_change();

-- Generic row-audit trigger.
create or replace function public.audit_row()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  rec_id text;
begin
  rec_id := coalesce(
    case when tg_op = 'DELETE' then (to_jsonb(old)->>'id')
         else (to_jsonb(new)->>'id') end, '?');
  insert into audit_log (actor_id, action, table_name, record_id,
                         old_values, new_values, reason)
  values (
    auth.uid(), tg_op, tg_table_name, rec_id,
    case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) end,
    case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) end,
    nullif(current_setting('wdos.reason', true), '')
  );
  return case when tg_op = 'DELETE' then old else new end;
end; $$;

create trigger org_units_audit after insert or update or delete
  on public.org_units for each row execute function public.audit_row();
create trigger profiles_audit after insert or update or delete
  on public.profiles for each row execute function public.audit_row();
create trigger role_assignments_audit after insert or update or delete
  on public.role_assignments for each row execute function public.audit_row();

-- updated_at maintenance
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end; $$;

create trigger org_units_touch before update on public.org_units
  for each row execute function public.touch_updated_at();
create trigger profiles_touch before update on public.profiles
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- 7. ROW LEVEL SECURITY
-- ---------------------------------------------------------------------------

alter table public.org_units        enable row level security;
alter table public.profiles         enable row level security;
alter table public.role_assignments enable row level security;
alter table public.audit_log        enable row level security;

-- org_units: every authenticated user may read the structure; only HQ writes.
create policy org_units_read on public.org_units
  for select to authenticated using (true);
create policy org_units_write on public.org_units
  for all to authenticated
  using (public.has_role(array['super_admin','executive_director','hq_team']::public.role_code[]))
  with check (public.has_role(array['super_admin','executive_director','hq_team']::public.role_code[]));

-- profiles: self-read, leadership reads own subtree, HQ reads all.
create policy profiles_self_read on public.profiles
  for select to authenticated using (id = auth.uid());
create policy profiles_leader_read on public.profiles
  for select to authenticated
  using (org_unit_id in (select public.administered_units()));
create policy profiles_hq_read on public.profiles
  for select to authenticated
  using (public.has_role(array['super_admin','executive_director','hq_team']::public.role_code[]));

-- profiles: self may update own contact fields only — enforced by a
-- column-guard trigger below; RLS grants the row.
create policy profiles_self_update on public.profiles
  for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());
create policy profiles_leader_write on public.profiles
  for all to authenticated
  using (org_unit_id in (select public.administered_units()))
  with check (org_unit_id in (select public.administered_units()));
create policy profiles_hq_write on public.profiles
  for all to authenticated
  using (public.has_role(array['super_admin','executive_director','hq_team']::public.role_code[]))
  with check (public.has_role(array['super_admin','executive_director','hq_team']::public.role_code[]));

-- Column guard: non-leaders may not change their own status, network,
-- org unit, or membership number.
create or replace function public.profiles_guard_columns()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() = old.id
     and not public.has_role(array['super_admin','executive_director','hq_team']::public.role_code[])
     and old.org_unit_id not in (select public.administered_units())
  then
    if new.status is distinct from old.status
       or new.network is distinct from old.network
       or new.org_unit_id is distinct from old.org_unit_id
       or new.membership_no is distinct from old.membership_no then
      raise exception 'You may only edit your contact details';
    end if;
  end if;
  return new;
end; $$;

create trigger profiles_guard before update on public.profiles
  for each row execute function public.profiles_guard_columns();

-- role_assignments: readable in subtree/self; writable by HQ only in v1.
-- (Delegated appointment workflows arrive with the Workflow module.)
create policy role_assign_read on public.role_assignments
  for select to authenticated
  using (profile_id = auth.uid()
         or org_unit_id in (select public.administered_units())
         or public.has_role(array['super_admin','executive_director','hq_team']::public.role_code[]));
create policy role_assign_write on public.role_assignments
  for all to authenticated
  using (public.has_role(array['super_admin','executive_director','hq_team']::public.role_code[]))
  with check (public.has_role(array['super_admin','executive_director','hq_team']::public.role_code[]));

-- audit_log: HQ read-only; nobody writes via API (triggers only).
create policy audit_read on public.audit_log
  for select to authenticated
  using (public.has_role(array['super_admin','executive_director','hq_team']::public.role_code[]));

-- ---------------------------------------------------------------------------
-- 8. STATUS TRANSITION GUARD (lifecycle integrity, Gap Analysis §7)
-- ---------------------------------------------------------------------------

create or replace function public.valid_status_transition(
  old_s public.member_status, new_s public.member_status)
returns boolean language sql immutable as $$
  select case old_s
    when 'applicant'    then new_s in ('under_review','removed')
    when 'under_review' then new_s in ('approved','removed')
    when 'approved'     then new_s in ('activated','removed')
    when 'activated'    then new_s in ('in_training','active','inactive','suspended','resigned','removed')
    when 'in_training'  then new_s in ('active','inactive','suspended','resigned','removed')
    when 'active'       then new_s in ('inactive','suspended','resigned','removed','alumni')
    when 'inactive'     then new_s in ('active','suspended','resigned','removed','alumni')
    when 'suspended'    then new_s in ('reinstated','removed','resigned')
    when 'resigned'     then new_s in ('reinstated','alumni')
    when 'removed'      then new_s in ('reinstated')
    when 'alumni'       then new_s in ('reinstated')
    when 'reinstated'   then new_s in ('active','in_training','inactive')
  end;
$$;

create or replace function public.profiles_check_transition()
returns trigger language plpgsql as $$
begin
  if new.status is distinct from old.status
     and not public.valid_status_transition(old.status, new.status) then
    raise exception 'Invalid status transition: % -> %', old.status, new.status;
  end if;
  return new;
end; $$;

create trigger profiles_status_transition before update on public.profiles
  for each row execute function public.profiles_check_transition();

-- ---------------------------------------------------------------------------
-- 9. NEW-USER BOOTSTRAP: create a profile row when auth user is created
-- ---------------------------------------------------------------------------

create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, first_name, last_name, email, network)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'first_name',''),
    coalesce(new.raw_user_meta_data->>'last_name',''),
    new.email,
    coalesce((new.raw_user_meta_data->>'network')::public.network_code, 'WGMN')
  );
  return new;
end; $$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();
