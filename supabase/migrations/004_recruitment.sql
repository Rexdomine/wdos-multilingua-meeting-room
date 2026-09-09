-- ============================================================================
-- WDOS Migration 004 — Recruitment Pipeline
-- Public applications → review (recommend) → decision (approve/reject),
-- with the initiator/reviewer/approver chain, scoped by RLS, fully audited.
-- Membership numbers are assigned automatically on approval.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. APPLICATION STATUS + TABLE
-- ---------------------------------------------------------------------------

create type public.application_status as enum (
  'submitted', 'under_review', 'recommended', 'approved', 'rejected', 'withdrawn'
);

create table public.applications (
  id              uuid primary key default gen_random_uuid(),
  first_name      text not null check (char_length(first_name) between 1 and 60),
  last_name       text not null check (char_length(last_name) between 1 and 60),
  email           text not null
    check (email ~* '^[^\s@]+@[^\s@]+\.[^\s@]{2,}$' and char_length(email) <= 254),
  phone           text check (phone is null or phone ~ '^\+?[0-9 ()-]{7,20}$'),
  network         public.network_code not null,
  org_unit_id     uuid not null references public.org_units(id) on delete restrict,
  motivation      text not null check (char_length(motivation) between 20 and 2000),
  preferred_locale text not null default 'en'
    check (preferred_locale in ('en','fr','pt','ar','sw','ha','yo','ig')),

  status          public.application_status not null default 'submitted',
  reviewer_id     uuid references public.profiles(id),
  reviewer_notes  text check (reviewer_notes is null or char_length(reviewer_notes) <= 2000),
  recommended_at  timestamptz,
  decided_by      uuid references public.profiles(id),
  decision_reason text check (decision_reason is null or char_length(decision_reason) <= 1000),
  decided_at      timestamptz,
  profile_id      uuid references public.profiles(id),  -- set when account exists

  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create index applications_unit_idx   on public.applications (org_unit_id);
create index applications_status_idx on public.applications (status);

-- One live application per email (duplicate prevention, Gap Analysis §6)
create unique index applications_live_email_uq
  on public.applications (lower(email))
  where status in ('submitted', 'under_review', 'recommended');

create trigger applications_touch before update on public.applications
  for each row execute function public.touch_updated_at();
create trigger applications_audit after insert or update or delete
  on public.applications for each row execute function public.audit_row();

-- An applicant whose email already belongs to a member cannot re-apply.
create or replace function public.applications_block_existing_member()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from profiles where lower(email) = lower(new.email)) then
    raise exception 'A profile with this email already exists';
  end if;
  return new;
end; $$;

create trigger applications_no_existing_member
  before insert on public.applications
  for each row execute function public.applications_block_existing_member();

-- ---------------------------------------------------------------------------
-- 2. RLS — anonymous submission, scoped reading, RPC-only workflow changes
-- ---------------------------------------------------------------------------

alter table public.applications enable row level security;

-- Anyone may submit; only clean 'submitted' rows with no workflow fields.
create policy applications_public_insert on public.applications
  for insert to anon, authenticated
  with check (
    status = 'submitted'
    and reviewer_id is null and reviewer_notes is null
    and recommended_at is null and decided_by is null
    and decision_reason is null and decided_at is null
    and profile_id is null
  );

-- Leaders read applications for units in their administered subtree; HQ all.
create policy applications_leader_read on public.applications
  for select to authenticated
  using (
    org_unit_id in (select public.administered_units())
    or public.has_role(array['super_admin','executive_director','hq_team']::public.role_code[])
  );

-- No UPDATE/DELETE policies: all workflow transitions go through the RPCs
-- below, which enforce role and state checks explicitly.

-- The public application form needs the unit list without a session.
create policy org_units_read_anon on public.org_units
  for select to anon using (is_active = true);

-- ---------------------------------------------------------------------------
-- 3. WORKFLOW PERMISSION HELPERS
-- ---------------------------------------------------------------------------

-- Reviewer: any leadership role over the unit's subtree.
create or replace function public.can_review(unit uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select unit in (select administered_units());
$$;

-- Approver: State Coordinator and above over the unit, or HQ.
create or replace function public.can_approve(unit uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1
    from role_assignments ra
    where ra.profile_id = auth.uid()
      and ra.ends_at is null
      and ra.role in ('super_admin','executive_director','hq_team',
                      'country_rep','deputy_country_rep','state_coordinator')
      and unit in (select org_unit_subtree(ra.org_unit_id))
  );
$$;

-- ---------------------------------------------------------------------------
-- 4. WORKFLOW RPCs (initiator → reviewer → approver chain)
-- ---------------------------------------------------------------------------

-- Reviewer takes an application into screening.
create or replace function public.review_application(app_id uuid, notes text default null)
returns public.applications
language plpgsql security definer set search_path = public as $$
declare a public.applications;
begin
  select * into a from applications where id = app_id for update;
  if a.id is null then raise exception 'Application not found'; end if;
  if not can_review(a.org_unit_id) then
    raise exception 'You are not a reviewer for this unit';
  end if;
  if a.status not in ('submitted','under_review') then
    raise exception 'Application is not open for review (status: %)', a.status;
  end if;
  update applications
     set status = 'under_review',
         reviewer_id = auth.uid(),
         reviewer_notes = coalesce(notes, reviewer_notes)
   where id = app_id
   returning * into a;
  return a;
end; $$;

-- Reviewer recommends the applicant for approval.
create or replace function public.recommend_application(app_id uuid, notes text)
returns public.applications
language plpgsql security definer set search_path = public as $$
declare a public.applications;
begin
  select * into a from applications where id = app_id for update;
  if a.id is null then raise exception 'Application not found'; end if;
  if not can_review(a.org_unit_id) then
    raise exception 'You are not a reviewer for this unit';
  end if;
  if a.status <> 'under_review' then
    raise exception 'Only applications under review can be recommended';
  end if;
  if notes is null or char_length(trim(notes)) < 5 then
    raise exception 'Reviewer notes are required to recommend';
  end if;
  update applications
     set status = 'recommended',
         reviewer_id = auth.uid(),
         reviewer_notes = notes,
         recommended_at = now()
   where id = app_id
   returning * into a;
  return a;
end; $$;

-- Approver decides. Approvers may also decide directly from 'submitted' or
-- 'under_review' (e.g. HQ fast-track), and the audit trail records it.
create or replace function public.decide_application(
  app_id uuid, approve boolean, reason text)
returns public.applications
language plpgsql security definer set search_path = public as $$
declare a public.applications;
begin
  select * into a from applications where id = app_id for update;
  if a.id is null then raise exception 'Application not found'; end if;
  if not can_approve(a.org_unit_id) then
    raise exception 'You are not an approver for this unit';
  end if;
  if a.status not in ('submitted','under_review','recommended') then
    raise exception 'Application has already been decided (status: %)', a.status;
  end if;
  if reason is null or char_length(trim(reason)) < 5 then
    raise exception 'A reason is required for the decision';
  end if;
  perform set_config('wdos.reason', reason, true);
  update applications
     set status = (case when approve then 'approved'
                        else 'rejected' end)::public.application_status,
         decided_by = auth.uid(),
         decision_reason = reason,
         decided_at = now()
   where id = app_id
   returning * into a;
  return a;
end; $$;

-- ---------------------------------------------------------------------------
-- 5. MEMBERSHIP NUMBERS — assigned automatically on approval
-- ---------------------------------------------------------------------------

create sequence if not exists public.membership_no_seq;

create or replace function public.next_membership_no()
returns text language sql volatile security definer set search_path = public as $$
  select 'W-' || to_char(now(), 'YYYY') || '-' ||
         lpad(nextval('membership_no_seq')::text, 6, '0');
$$;

create or replace function public.profiles_assign_membership_no()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.membership_no is null and new.status in
     ('approved','activated','in_training','active') then
    new.membership_no := public.next_membership_no();
  end if;
  return new;
end; $$;

create trigger profiles_membership_no_ins before insert on public.profiles
  for each row execute function public.profiles_assign_membership_no();
create trigger profiles_membership_no_upd before update on public.profiles
  for each row when (old.status is distinct from new.status)
  execute function public.profiles_assign_membership_no();

-- ---------------------------------------------------------------------------
-- 6. ACCOUNT LINK — when an approved applicant's account is created,
--    build her profile from the application (v3 of handle_new_user).
-- ---------------------------------------------------------------------------

create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public as $$
declare app public.applications;
begin
  select * into app
    from applications
   where lower(email) = lower(new.email) and status = 'approved'
   order by decided_at desc limit 1;

  if app.id is not null then
    insert into public.profiles
      (id, first_name, last_name, email, phone, network, org_unit_id,
       preferred_locale, status)
    values
      (new.id, app.first_name, app.last_name, new.email, app.phone,
       app.network, app.org_unit_id, app.preferred_locale, 'approved');
    update applications set profile_id = new.id where id = app.id;
  else
    insert into public.profiles (id, first_name, last_name, email, network)
    values (
      new.id,
      left(coalesce(nullif(new.raw_user_meta_data->>'first_name',''),
                    initcap(split_part(new.email,'@',1))), 60),
      left(coalesce(nullif(new.raw_user_meta_data->>'last_name',''), '-'), 60),
      new.email,
      coalesce((new.raw_user_meta_data->>'network')::public.network_code, 'WGMN')
    );
  end if;
  return new;
end; $$;
