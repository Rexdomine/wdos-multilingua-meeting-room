-- ============================================================================
-- WDOS Migration 015 — Headquarters Operations v1
-- The second ecosystem: WODDI's internal staff operations, walled off from
-- Leadership Operations. Access comes ONLY from the staff register (or top
-- HQ roles) — never from field leadership rank or territory.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. DEPARTMENTS (HQ-managed)
-- ---------------------------------------------------------------------------
create table public.departments (
  id         uuid primary key default gen_random_uuid(),
  name       text not null unique check (char_length(name) between 2 and 80),
  is_active  boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger departments_touch before update on public.departments
  for each row execute function public.touch_updated_at();
create trigger departments_audit after insert or update or delete
  on public.departments for each row execute function public.audit_row();

insert into public.departments (name) values
  ('Executive Office'), ('Programmes'), ('Administration'),
  ('Technical Delivery'), ('Field & Country Operations'),
  ('Communications & Media'), ('Finance'), ('Support Services')
on conflict (name) do nothing;

-- ---------------------------------------------------------------------------
-- 2. STAFF REGISTER (a person becomes HQ staff by being placed here)
-- ---------------------------------------------------------------------------
create table public.staff (
  profile_id    uuid primary key references public.profiles(id) on delete cascade,
  department_id uuid not null references public.departments(id) on delete restrict,
  position_title text not null check (char_length(position_title) between 2 and 100),
  reports_to    uuid references public.profiles(id),
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index staff_department_idx on public.staff (department_id) where is_active;
create index staff_manager_idx on public.staff (reports_to) where is_active;

create trigger staff_touch before update on public.staff
  for each row execute function public.touch_updated_at();
create trigger staff_audit after insert or update or delete
  on public.staff for each row execute function public.audit_row();

create or replace function public.is_hq_staff()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from staff
                 where profile_id = auth.uid() and is_active);
$$;

-- ---------------------------------------------------------------------------
-- 3. STAFF REPORTS (daily / weekly / monthly, per the reporting template)
-- ---------------------------------------------------------------------------
create type public.report_period as enum ('daily', 'weekly', 'monthly');
create type public.staff_report_status as enum
  ('submitted', 'revision_requested', 'approved');

create table public.staff_reports (
  id               uuid primary key default gen_random_uuid(),
  author_id        uuid not null references public.profiles(id) default auth.uid(),
  report_date      date not null,
  period           public.report_period not null default 'daily',
  tasks_completed  text not null check (char_length(tasks_completed) between 2 and 4000),
  tasks_in_progress text check (tasks_in_progress is null or char_length(tasks_in_progress) <= 4000),
  challenges       text check (challenges is null or char_length(challenges) <= 4000),
  support_required text check (support_required is null or char_length(support_required) <= 4000),
  next_priorities  text check (next_priorities is null or char_length(next_priorities) <= 4000),
  status           public.staff_report_status not null default 'submitted',
  reviewer_id      uuid references public.profiles(id),
  reviewer_note    text check (reviewer_note is null or char_length(reviewer_note) <= 2000),
  reviewed_at      timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (author_id, period, report_date)
);

create index staff_reports_author_idx on public.staff_reports (author_id, report_date desc);
create index staff_reports_status_idx on public.staff_reports (status)
  where status = 'submitted';

create trigger staff_reports_touch before update on public.staff_reports
  for each row execute function public.touch_updated_at();
create trigger staff_reports_audit after insert or update or delete
  on public.staff_reports for each row execute function public.audit_row();

-- Reviewer of a report: the author's manager, or an HQ executive role.
create or replace function public.can_review_report(report_author uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select is_case_hq()
      or exists (select 1 from staff s
                 where s.profile_id = report_author
                   and s.reports_to = auth.uid() and s.is_active);
$$;

-- ---------------------------------------------------------------------------
-- 4. RLS — the wall between the two ecosystems
-- ---------------------------------------------------------------------------
alter table public.departments  enable row level security;
alter table public.staff        enable row level security;
alter table public.staff_reports enable row level security;

-- Departments/staff directory: visible to HQ staff and HQ executives only.
create policy departments_read on public.departments
  for select to authenticated
  using (public.is_hq_staff() or public.is_case_hq());
create policy departments_write on public.departments
  for all to authenticated
  using (public.is_case_hq()) with check (public.is_case_hq());

create policy staff_read on public.staff
  for select to authenticated
  using (public.is_hq_staff() or public.is_case_hq());
create policy staff_write on public.staff
  for all to authenticated
  using (public.is_case_hq()) with check (public.is_case_hq());

-- Reports: author + her manager + HQ executives.
create policy staff_reports_read on public.staff_reports
  for select to authenticated
  using (author_id = auth.uid() or public.can_review_report(author_id));

create policy staff_reports_insert on public.staff_reports
  for insert to authenticated
  with check (
    author_id = auth.uid()
    and public.is_hq_staff()
    and status = 'submitted'
    and reviewer_id is null and reviewer_note is null and reviewed_at is null
  );

-- Authors may edit content while submitted or in revision; the guard
-- trigger below controls exactly what they may touch.
create policy staff_reports_author_update on public.staff_reports
  for update to authenticated
  using (author_id = auth.uid()
         and status in ('submitted', 'revision_requested'))
  with check (author_id = auth.uid());

create or replace function public.staff_reports_guard()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() = old.author_id and not can_review_report(old.author_id) then
    if new.reviewer_id is distinct from old.reviewer_id
       or new.reviewer_note is distinct from old.reviewer_note
       or new.reviewed_at is distinct from old.reviewed_at then
      raise exception 'Reviewer fields belong to the reviewer';
    end if;
    if new.status is distinct from old.status
       and not (old.status = 'revision_requested' and new.status = 'submitted') then
      raise exception 'Authors may only resubmit after a revision request';
    end if;
  end if;
  return new;
end; $$;

create trigger staff_reports_guard_trg before update on public.staff_reports
  for each row execute function public.staff_reports_guard();

-- ---------------------------------------------------------------------------
-- 5. REVIEW RPC (manager decision, audited with reason)
-- ---------------------------------------------------------------------------
create or replace function public.review_staff_report(
  rid uuid, approve boolean, note text default null)
returns public.staff_reports
language plpgsql security definer set search_path = public as $$
declare r public.staff_reports;
begin
  select * into r from staff_reports where id = rid for update;
  if r.id is null then raise exception 'Report not found'; end if;
  if not can_review_report(r.author_id) then
    raise exception 'Only the staff member''s manager or HQ executives can review this report';
  end if;
  if r.status <> 'submitted' then
    raise exception 'Only submitted reports can be reviewed (status: %)', r.status;
  end if;
  if not approve and (note is null or char_length(trim(note)) < 5) then
    raise exception 'A note is required when requesting revision';
  end if;
  perform set_config('wdos.reason', coalesce(note, ''), true);
  update staff_reports
     set status = case when approve then 'approved'
                       else 'revision_requested' end::public.staff_report_status,
         reviewer_id = auth.uid(),
         reviewer_note = note,
         reviewed_at = now()
   where id = rid
   returning * into r;
  return r;
end; $$;

-- ---------------------------------------------------------------------------
-- 6. MODULE — 'hq' granted by staff membership, not field rank
-- ---------------------------------------------------------------------------
alter table public.module_access drop constraint module_access_module_check;
alter table public.module_access add constraint module_access_module_check
  check (module in (
    'members','recruitment','organisation','tasks','meetings',
    'reports','announcements','settings','programmes','cases',
    'helpdesk','hq'
  ));

-- Executives always see HQ Operations; everyone else gains it solely by
-- being on the active staff register (see my_modules below).
insert into public.module_access (role, module) values
  ('super_admin', 'hq'), ('executive_director', 'hq'), ('hq_team', 'hq')
on conflict do nothing;

create or replace function public.my_modules()
returns setof text
language plpgsql stable security definer set search_path = public as $$
declare my_roles public.role_code[];
begin
  select coalesce(array_agg(distinct role), '{}')
    into my_roles
    from role_assignments
   where profile_id = auth.uid() and ends_at is null;
  if coalesce(array_length(my_roles, 1), 0) = 0 then
    my_roles := array['member']::public.role_code[];
  end if;
  return query
    select distinct m from (
      select ma.module as m from module_access ma
      where ma.role = any(my_roles)
      union
      select 'hq' where is_hq_staff()
    ) x;
end; $$;

insert into public.schema_migrations (version, name)
values (15, 'hq_operations') on conflict (version) do nothing;
