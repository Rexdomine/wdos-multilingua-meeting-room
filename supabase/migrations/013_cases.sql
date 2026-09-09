-- ============================================================================
-- WDOS Migration 013 — Welfare, Complaints & Safeguarding
-- Confidential case management. DELIBERATE DEPARTURE from the territory
-- model: cases are visible ONLY to the reporter, explicitly assigned
-- handlers, and HQ — never to subtree leaders, because a case may
-- concern a leader. All actions audited; status changes require notes.
-- ============================================================================

create type public.case_category as enum (
  'welfare', 'complaint', 'misconduct', 'harassment',
  'safeguarding', 'whistleblowing', 'appeal'
);

create type public.case_status as enum (
  'submitted', 'under_review', 'action_taken', 'resolved', 'dismissed'
);

-- ---------------------------------------------------------------------------
-- 1. CASES
-- ---------------------------------------------------------------------------
create sequence if not exists public.case_no_seq;

create table public.cases (
  id          uuid primary key default gen_random_uuid(),
  case_no     text unique,
  category    public.case_category not null,
  org_unit_id uuid references public.org_units(id) on delete restrict,
  subject     text not null check (char_length(subject) between 3 and 160),
  details     text not null check (char_length(details) between 10 and 8000),
  reporter_id uuid not null references public.profiles(id) default auth.uid(),
  status      public.case_status not null default 'submitted',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create or replace function public.cases_assign_no()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.case_no is null then
    new.case_no := 'C-' || to_char(now(), 'YYYY') || '-' ||
      lpad(nextval('case_no_seq')::text, 4, '0');
  end if;
  return new;
end; $$;

create trigger cases_no before insert on public.cases
  for each row execute function public.cases_assign_no();
create trigger cases_touch before update on public.cases
  for each row execute function public.touch_updated_at();
create trigger cases_audit after insert or update or delete
  on public.cases for each row execute function public.audit_row();

-- ---------------------------------------------------------------------------
-- 2. HANDLERS (explicit assignment by HQ) and UPDATES (case timeline)
-- ---------------------------------------------------------------------------
create table public.case_handlers (
  case_id     uuid not null references public.cases(id) on delete cascade,
  profile_id  uuid not null references public.profiles(id) on delete cascade,
  assigned_by uuid not null references public.profiles(id) default auth.uid(),
  assigned_at timestamptz not null default now(),
  primary key (case_id, profile_id)
);

create trigger case_handlers_audit after insert or update or delete
  on public.case_handlers for each row execute function public.audit_row();

create table public.case_updates (
  id                  uuid primary key default gen_random_uuid(),
  case_id             uuid not null references public.cases(id) on delete cascade,
  author_id           uuid not null references public.profiles(id) default auth.uid(),
  note                text not null check (char_length(note) between 2 and 4000),
  visible_to_reporter boolean not null default false,
  created_at          timestamptz not null default now()
);

create index case_updates_case_idx on public.case_updates (case_id, created_at);

create trigger case_updates_audit after insert or update or delete
  on public.case_updates for each row execute function public.audit_row();

-- ---------------------------------------------------------------------------
-- 3. ACCESS HELPERS
-- ---------------------------------------------------------------------------
create or replace function public.is_case_hq()
returns boolean language sql stable security definer set search_path = public as $$
  select has_role(array['super_admin','executive_director','hq_team']::public.role_code[]);
$$;

create or replace function public.can_access_case(cid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select is_case_hq()
      or exists (select 1 from cases c
                 where c.id = cid and c.reporter_id = auth.uid())
      or exists (select 1 from case_handlers h
                 where h.case_id = cid and h.profile_id = auth.uid());
$$;

create or replace function public.can_manage_case(cid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select is_case_hq()
      or exists (select 1 from case_handlers h
                 where h.case_id = cid and h.profile_id = auth.uid());
$$;

-- ---------------------------------------------------------------------------
-- 4. RLS — no territory rule here, by design
-- ---------------------------------------------------------------------------
alter table public.cases         enable row level security;
alter table public.case_handlers enable row level security;
alter table public.case_updates  enable row level security;

create policy cases_read on public.cases
  for select to authenticated
  using (public.can_access_case(id));

-- Anyone signed in may file a case about anything.
create policy cases_file on public.cases
  for insert to authenticated
  with check (reporter_id = auth.uid() and status = 'submitted');

-- No direct updates via the API: status changes go through the RPC below.

create policy handlers_read on public.case_handlers
  for select to authenticated
  using (public.can_access_case(case_id));

create policy updates_read on public.case_updates
  for select to authenticated
  using (
    public.can_manage_case(case_id)
    or (visible_to_reporter
        and exists (select 1 from public.cases c
                    where c.id = case_id and c.reporter_id = auth.uid()))
  );

create policy updates_write on public.case_updates
  for insert to authenticated
  with check (author_id = auth.uid() and public.can_manage_case(case_id));

-- ---------------------------------------------------------------------------
-- 5. WORKFLOW RPCs
-- ---------------------------------------------------------------------------
create or replace function public.assign_case_handler(cid uuid, handler uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_case_hq() then
    raise exception 'Only Headquarters can assign case handlers';
  end if;
  if not exists (select 1 from cases where id = cid) then
    raise exception 'Case not found';
  end if;
  if not exists (select 1 from profiles where id = handler) then
    raise exception 'Handler profile not found';
  end if;
  insert into case_handlers (case_id, profile_id, assigned_by)
  values (cid, handler, auth.uid())
  on conflict do nothing;
end; $$;

create or replace function public.valid_case_transition(
  old_s public.case_status, new_s public.case_status)
returns boolean language sql immutable as $$
  select case old_s
    when 'submitted'    then new_s in ('under_review','dismissed')
    when 'under_review' then new_s in ('action_taken','resolved','dismissed')
    when 'action_taken' then new_s in ('resolved','under_review')
    when 'resolved'     then new_s in ('under_review')      -- reopen
    when 'dismissed'    then new_s in ('under_review')      -- reopen
  end;
$$;

create or replace function public.update_case_status(
  cid uuid, new_status public.case_status, note text,
  visible boolean default false)
returns public.cases
language plpgsql security definer set search_path = public as $$
declare c public.cases;
begin
  select * into c from cases where id = cid for update;
  if c.id is null then raise exception 'Case not found'; end if;
  if not can_manage_case(cid) then
    raise exception 'Only Headquarters or an assigned handler can act on this case';
  end if;
  if not valid_case_transition(c.status, new_status) then
    raise exception 'Invalid case transition: % -> %', c.status, new_status;
  end if;
  if note is null or char_length(trim(note)) < 5 then
    raise exception 'A note is required for every status change';
  end if;
  perform set_config('wdos.reason', note, true);
  update cases set status = new_status where id = cid returning * into c;
  insert into case_updates (case_id, author_id, note, visible_to_reporter)
  values (cid, auth.uid(), note, visible);
  return c;
end; $$;

-- ---------------------------------------------------------------------------
-- 6. MODULE REGISTRATION — every role may report; only reporters/handlers/HQ
--    ever see content, so granting the module widely is safe.
-- ---------------------------------------------------------------------------
alter table public.module_access drop constraint module_access_module_check;
alter table public.module_access add constraint module_access_module_check
  check (module in (
    'members','recruitment','organisation','tasks','meetings',
    'reports','announcements','settings','programmes','cases'
  ));

insert into public.module_access (role, module)
select r::public.role_code, 'cases' from unnest(array[
  'super_admin','executive_director','hq_team',
  'country_rep','deputy_country_rep','state_coordinator',
  'assistant_state_coordinator','district_coordinator','chapter_lead',
  'volunteer','member','programme_staff','institute_admin'
]) as r
on conflict do nothing;

insert into public.schema_migrations (version, name)
values (13, 'cases') on conflict (version) do nothing;
