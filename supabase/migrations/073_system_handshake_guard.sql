-- ============================================================================
-- WDOS Migration 073 — The guard learns the system's handshake (Phase 89i)
-- Launch bug, caught by a test account: when a volunteer PASSES the 14-day
-- activation, WDOS advances their status automatically — but that update
-- runs while the member's own session is the caller, so the 001 column
-- guard ("You may only edit your contact details") mistook the system's
-- auto-approval for a hand-edit and rolled back the volunteer's final
-- task save. Every passer would have hit this at their moment of victory.
--
-- Fix: system routines announce themselves with a transaction-local flag
-- (wdos.system = '1'); the guard honours the flag — and also stands down
-- for auth-less contexts (the SQL editor, scheduled jobs). Members hand-
-- editing their own status remain exactly as forbidden as before.
-- ============================================================================

create or replace function public.profiles_guard_columns()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(current_setting('wdos.system', true), '') = '1'
     or auth.uid() is null then
    return new;                       -- the system's own hand, let it work
  end if;
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

-- The auto-approval walk now announces itself before touching status.
create or replace function public.advance_status_on_pass(pid uuid)
returns void language plpgsql
security definer set search_path = public as $$
declare cur public.member_status;
begin
  select status into cur from profiles where id = pid;
  perform set_config('wdos.system', '1', true);
  perform set_config('wdos.reason',
    '14-day activation passed (system evaluation)', true);
  if cur = 'applicant' then
    update profiles set status = 'under_review' where id = pid;
    cur := 'under_review';
  end if;
  if cur = 'under_review' then
    update profiles set status = 'approved' where id = pid;
    cur := 'approved';
  end if;
  if cur = 'approved' then
    update profiles set status = 'activated' where id = pid;
  end if;
end; $$;

insert into public.schema_migrations (version, name)
values (73, 'system_handshake_guard') on conflict (version) do nothing;
