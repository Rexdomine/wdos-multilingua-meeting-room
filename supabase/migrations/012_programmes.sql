-- ============================================================================
-- WDOS Migration 012 — Programme & Beneficiary Management
-- Programmes (HQ catalogue) → events (recorded by leaders in their
-- territory) → beneficiaries (restricted records) → services delivered.
-- Privacy by design: beneficiaries carry minimal data (no birth dates);
-- access is leaders-over-the-unit and HQ only.
-- ============================================================================

create type public.age_band as enum ('child', 'youth', 'adult', 'senior');

-- ---------------------------------------------------------------------------
-- 1. PROGRAMMES (HQ-managed catalogue)
-- ---------------------------------------------------------------------------
create table public.programmes (
  id          uuid primary key default gen_random_uuid(),
  code        text not null unique check (char_length(code) between 2 and 30),
  name        text not null check (char_length(name) between 2 and 120),
  description text check (description is null or char_length(description) <= 2000),
  network     public.network_code,          -- null = both networks
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create trigger programmes_touch before update on public.programmes
  for each row execute function public.touch_updated_at();
create trigger programmes_audit after insert or update or delete
  on public.programmes for each row execute function public.audit_row();

-- Known WODDI programmes, seeded by code. HQ sets full names in the app.
insert into public.programmes (code, name) values
  ('WIWS', 'WIWS'), ('SNARP', 'SNARP'), ('WESAP', 'WESAP'),
  ('YES', 'YES'), ('WHI', 'WHI'), ('HARMONY-HUB', 'Harmony Hub'),
  ('TALK-THAT-TALK', 'Talk That Talk'), ('THIRST', 'Thirst')
on conflict (code) do nothing;

-- ---------------------------------------------------------------------------
-- 2. PROGRAMME EVENTS (sessions/activities held by units)
-- ---------------------------------------------------------------------------
create table public.programme_events (
  id           uuid primary key default gen_random_uuid(),
  programme_id uuid not null references public.programmes(id) on delete restrict,
  org_unit_id  uuid not null references public.org_units(id) on delete restrict,
  title        text not null check (char_length(title) between 3 and 160),
  event_date   date not null,
  location     text check (location is null or char_length(location) <= 300),
  notes        text check (notes is null or char_length(notes) <= 4000),
  created_by   uuid not null references public.profiles(id) default auth.uid(),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create index prog_events_prog_idx on public.programme_events (programme_id, event_date desc);
create index prog_events_unit_idx on public.programme_events (org_unit_id);

create trigger prog_events_touch before update on public.programme_events
  for each row execute function public.touch_updated_at();
create trigger prog_events_audit after insert or update or delete
  on public.programme_events for each row execute function public.audit_row();

-- ---------------------------------------------------------------------------
-- 3. BENEFICIARIES (restricted, minimal data)
-- ---------------------------------------------------------------------------
create table public.beneficiaries (
  id          uuid primary key default gen_random_uuid(),
  full_name   text not null check (char_length(full_name) between 2 and 120),
  age_band    public.age_band not null,
  org_unit_id uuid not null references public.org_units(id) on delete restrict,
  notes       text check (notes is null or char_length(notes) <= 2000),
  created_by  uuid not null references public.profiles(id) default auth.uid(),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index beneficiaries_unit_idx on public.beneficiaries (org_unit_id);

create trigger beneficiaries_touch before update on public.beneficiaries
  for each row execute function public.touch_updated_at();
create trigger beneficiaries_audit after insert or update or delete
  on public.beneficiaries for each row execute function public.audit_row();

-- ---------------------------------------------------------------------------
-- 4. SERVICE RECORDS (what was delivered to whom, with outcome)
-- ---------------------------------------------------------------------------
create table public.service_records (
  id             uuid primary key default gen_random_uuid(),
  event_id       uuid not null references public.programme_events(id) on delete cascade,
  beneficiary_id uuid not null references public.beneficiaries(id) on delete restrict,
  service        text not null check (char_length(service) between 2 and 200),
  outcome        text check (outcome is null or char_length(outcome) <= 1000),
  recorded_by    uuid not null references public.profiles(id) default auth.uid(),
  recorded_at    timestamptz not null default now(),
  unique (event_id, beneficiary_id, service)
);

create index services_event_idx on public.service_records (event_id);
create index services_beneficiary_idx on public.service_records (beneficiary_id);

create trigger services_audit after insert or update or delete
  on public.service_records for each row execute function public.audit_row();

-- ---------------------------------------------------------------------------
-- 5. RLS
-- ---------------------------------------------------------------------------
alter table public.programmes       enable row level security;
alter table public.programme_events enable row level security;
alter table public.beneficiaries    enable row level security;
alter table public.service_records  enable row level security;

-- Programmes: everyone signed in may read the catalogue; HQ manages it.
create policy programmes_read on public.programmes
  for select to authenticated using (true);
create policy programmes_write on public.programmes
  for all to authenticated
  using (public.has_role(array['super_admin','executive_director','hq_team']::public.role_code[]))
  with check (public.has_role(array['super_admin','executive_director','hq_team']::public.role_code[]));

-- Events: visible/manageable by leaders over the unit, the creator, HQ.
create or replace function public.is_prog_manager(unit uuid, creator uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select creator = auth.uid()
      or unit in (select administered_units())
      or has_role(array['super_admin','executive_director','hq_team']::public.role_code[]);
$$;

create policy prog_events_read on public.programme_events
  for select to authenticated
  using (public.is_prog_manager(org_unit_id, created_by));
create policy prog_events_insert on public.programme_events
  for insert to authenticated
  with check (
    created_by = auth.uid()
    and (org_unit_id in (select public.administered_units())
         or public.has_role(array['super_admin','executive_director','hq_team']::public.role_code[]))
  );
create policy prog_events_update on public.programme_events
  for update to authenticated
  using (public.is_prog_manager(org_unit_id, created_by))
  with check (public.is_prog_manager(org_unit_id, created_by));

-- Beneficiaries: the strictest scope in the system.
create policy beneficiaries_rw on public.beneficiaries
  for all to authenticated
  using (public.is_prog_manager(org_unit_id, created_by))
  with check (
    created_by = auth.uid() and
    (org_unit_id in (select public.administered_units())
     or public.has_role(array['super_admin','executive_director','hq_team']::public.role_code[]))
  );

-- Service records: follow the event's unit.
create policy services_rw on public.service_records
  for all to authenticated
  using (exists (select 1 from public.programme_events e
                 where e.id = event_id
                   and public.is_prog_manager(e.org_unit_id, e.created_by)))
  with check (
    recorded_by = auth.uid()
    and exists (select 1 from public.programme_events e
                where e.id = event_id
                  and public.is_prog_manager(e.org_unit_id, e.created_by))
  );

-- ---------------------------------------------------------------------------
-- 6. IMPACT REPORTING (RLS-scoped, per programme)
-- ---------------------------------------------------------------------------
create or replace function public.report_programmes()
returns table (code text, name text, events bigint,
               beneficiaries bigint, services bigint)
language sql stable security invoker set search_path = public as $$
  select p.code, p.name,
    count(distinct e.id) as events,
    count(distinct s.beneficiary_id) as beneficiaries,
    count(s.id) as services
  from programmes p
  left join programme_events e on e.programme_id = p.id
  left join service_records s on s.event_id = e.id
  where p.is_active
  group by p.id, p.code, p.name
  order by p.code;
$$;

-- ---------------------------------------------------------------------------
-- 7. MODULE REGISTRATION
-- ---------------------------------------------------------------------------
alter table public.module_access drop constraint module_access_module_check;
alter table public.module_access add constraint module_access_module_check
  check (module in (
    'members','recruitment','organisation','tasks','meetings',
    'reports','announcements','settings','programmes'
  ));

insert into public.module_access (role, module)
select r::public.role_code, 'programmes' from unnest(array[
  'super_admin','executive_director','hq_team',
  'country_rep','deputy_country_rep','state_coordinator',
  'assistant_state_coordinator','district_coordinator','chapter_lead',
  'programme_staff'
]) as r
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- 8. LOGBOOK
-- ---------------------------------------------------------------------------
insert into public.schema_migrations (version, name)
values (12, 'programmes') on conflict (version) do nothing;
