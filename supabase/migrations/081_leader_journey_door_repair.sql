-- ============================================================================
-- WDOS Migration 081 — Established leaders never see the activation door
-- (Phase 94 repair)
--
-- Two real bugs, both mine:
--   1. A stray activation_journeys row was sitting against Regina's demo
--      profile (however it got there), and the Home screen showed the
--      "Begin your 14-day Activation Journey" card to ANY profile with a
--      journey row, without checking whether that profile is an
--      established leader. Fixed in the app (this migration's partner
--      zip) AND here: apply_leader_directory() now clears every journey
--      row for a freshly-seated leader, not only ones still in progress,
--      so this can never happen to a future promotion either.
--   2. The demo birthday message was written with a JavaScript-style
--      \u{1F389} escape sequence inside a plain SQL string, which
--      Postgres does not interpret \u2014 it stored the literal six
--      characters instead of the emoji. Corrected to the real character.
-- ============================================================================

-- 1 ▸ immediate repair: Regina's own record, right now ----------------------
update activation_journeys
   set status = 'deferred'
 where profile_id = (select id from profiles
                      where lower(email) = 'regina.demo@woddi-demo.invalid')
   and status <> 'deferred';

update member_notices
   set title = 'Happy birthday, Regina! 🎉'
 where profile_id = (select id from profiles
                      where lower(email) = 'regina.demo@woddi-demo.invalid')
   and kind = 'birthday';

-- 2 ▸ the permanent fix: any future leader promotion clears ALL journeys ----
create or replace function public.apply_leader_directory(pid uuid)
returns void language plpgsql
security definer set search_path = public as $$
declare d record; p record; cid uuid; sid uuid; rc public.role_code;
begin
  select * into p from profiles where id = pid;
  if p.id is null then return; end if;
  select * into d from leader_directory
   where upper(member_code) = upper(coalesce(p.membership_no, ''))
      or (email is not null and lower(email) = lower(p.email))
   limit 1;
  if d.member_code is null then return; end if;

  perform set_config('wdos.system', '1', true);
  update profiles
     set is_leader     = true,
         country       = coalesce(nullif(country, ''), d.country),
         state_region  = coalesce(nullif(state_region, ''), d.state),
         role_applied  = coalesce(nullif(role_applied, ''), d.role_applied),
         phone         = coalesce(nullif(phone, ''), nullif(d.phone, '')),
         membership_no = d.member_code
   where id = pid;
  perform advance_status_on_pass(pid);

  -- an established leader never sits the 14-day activation, whatever
  -- state a journey row happens to be in
  update activation_journeys
     set status = 'deferred'
   where profile_id = pid and status <> 'deferred';

  update leader_directory
     set claimed_profile = pid
   where member_code = d.member_code;

  select ou.id into cid from org_units ou
   where ou.level = 'country' and ou.name = d.country limit 1;
  if cid is null then return; end if;

  if d.state is not null then
    select su.id into sid from org_units su
     where su.parent_id = cid and su.level = 'state_region'
       and su.name = d.state limit 1;
    if sid is not null then
      rc := role_code_for_state_leader(d.role_applied);
      if not exists (select 1 from role_assignments
                      where profile_id = pid and role = rc
                        and org_unit_id = sid and ends_at is null) then
        insert into role_assignments (profile_id, role, org_unit_id)
        values (pid, rc, sid);
      end if;
    end if;
  else
    rc := role_code_for_leader(d.role_applied);
    if not exists (select 1 from role_assignments
                    where profile_id = pid and role = rc
                      and org_unit_id = cid and ends_at is null) then
      insert into role_assignments (profile_id, role, org_unit_id)
      values (pid, rc, cid);
    end if;
  end if;
end $$;

insert into public.schema_migrations (version, name)
values (81, 'leader_journey_door_repair') on conflict (version) do nothing;
