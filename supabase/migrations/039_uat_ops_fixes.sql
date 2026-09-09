-- ============================================================================
-- WDOS Migration 039 — UAT Operations Fixes (Phase 44)
--
-- 1. STAFF MODULE ACCESS FIX. Root cause of "staff can't see their tasks":
--    placement in the staff register never granted an access ROLE, and the
--    module matrix keys off roles — so staff without an executive role saw
--    only the dashboard (tasks reached their bell but had no page to live
--    on). Now every active staff member automatically holds the hq_team
--    role at HQ (granted on placement, revoked with deactivation, and
--    backfilled for everyone already placed). Tasks, Documents, Meetings —
--    whatever the matrix grants hq_team — appears for them, including task
--    status changes (not started / in progress / done) and comment notes,
--    all visible to the master CRM as before.
-- 2. DOCUMENTS FOR ALL STAFF: the hq_team grants below make sure the
--    documents & library modules are included.
-- 3. CLAIM-YOUR-ACCOUNT: approved applicants create their own login at
--    #/claim — WDOS verifies an approved application exists for the email,
--    the person chooses a password, and on signup the profile is enriched
--    from the application and walked to approved (which starts the
--    activation journey automatically). No more manual account creation.
-- 4. Feedback form gains the free-text "anything else" box.
-- ============================================================================

-- 1+2 ▸ staff access ---------------------------------------------------------
create or replace function public.staff_sync_access()
returns trigger
language plpgsql security definer set search_path = public as $$
declare hq_unit uuid;
begin
  select id into hq_unit from org_units
   where level = 'headquarters' order by created_at limit 1;
  if hq_unit is null then return coalesce(new, old); end if;

  if (tg_op = 'INSERT' and new.is_active)
     or (tg_op = 'UPDATE' and new.is_active and not old.is_active) then
    insert into role_assignments (profile_id, role, org_unit_id)
    values (new.profile_id, 'hq_team', hq_unit)
    on conflict do nothing;
  elsif tg_op = 'UPDATE' and old.is_active and not new.is_active then
    update role_assignments
       set ends_at = now()
     where profile_id = new.profile_id and role = 'hq_team'
       and ends_at is null;
  end if;
  return coalesce(new, old);
end; $$;

drop trigger if exists staff_access_sync on public.staff;
create trigger staff_access_sync
  after insert or update on public.staff
  for each row execute function public.staff_sync_access();

-- backfill everyone already placed
insert into public.role_assignments (profile_id, role, org_unit_id)
select s.profile_id, 'hq_team',
  (select id from org_units where level = 'headquarters'
    order by created_at limit 1)
  from public.staff s
 where s.is_active
   and not exists (select 1 from role_assignments ra
      where ra.profile_id = s.profile_id and ra.role = 'hq_team'
        and ra.ends_at is null)
on conflict do nothing;

-- make sure hq_team's matrix row covers the working modules
insert into public.module_access (role, module) values
  ('hq_team','tasks'), ('hq_team','meetings'), ('hq_team','documents'),
  ('hq_team','library'), ('hq_team','announcements'), ('hq_team','helpdesk'),
  ('hq_team','reports')
on conflict do nothing;

-- 3 ▸ claim your account -----------------------------------------------------
create or replace function public.claim_check(em text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare app record;
begin
  em := lower(trim(em));
  if em = '' or position('@' in em) = 0 then
    return jsonb_build_object('eligible', false, 'reason', 'invalid');
  end if;
  if exists (select 1 from profiles where lower(email) = em) then
    return jsonb_build_object('eligible', false, 'reason', 'has_account');
  end if;
  select first_name into app from applications
   where lower(email) = em and status = 'approved'
   order by created_at desc limit 1;
  if app is null then
    return jsonb_build_object('eligible', false, 'reason', 'not_found');
  end if;
  return jsonb_build_object('eligible', true, 'first_name', app.first_name);
end; $$;

revoke all on function public.claim_check(text) from public;
grant execute on function public.claim_check(text) to anon, authenticated;

create or replace function public.claim_enrich()
returns trigger
language plpgsql security definer set search_path = public as $$
declare app record;
begin
  select * into app from applications
   where lower(email) = lower(new.email) and status = 'approved'
   order by created_at desc limit 1;
  if app.id is null then return new; end if;

  update profiles set
    first_name = coalesce(nullif(app.first_name, ''), first_name),
    last_name  = coalesce(nullif(app.last_name, ''), last_name),
    phone      = coalesce(phone, app.phone),
    network    = coalesce(network, app.network),
    org_unit_id = coalesce(org_unit_id, app.org_unit_id)
   where id = new.id;

  -- walk the lifecycle to approved; the journey auto-starts on that hop
  update profiles set status = 'under_review'
   where id = new.id and status = 'applicant';
  update profiles set status = 'approved'
   where id = new.id and status = 'under_review';
  return new;
end; $$;

drop trigger if exists profiles_claim_enrich on public.profiles;
create trigger profiles_claim_enrich
  after insert on public.profiles
  for each row execute function public.claim_enrich();

-- 4 ▸ feedback "anything else" ----------------------------------------------
alter table public.uat_feedback
  add column if not exists extra_notes text not null default '';

insert into public.schema_migrations (version, name)
values (39, 'uat_ops_fixes') on conflict (version) do nothing;
