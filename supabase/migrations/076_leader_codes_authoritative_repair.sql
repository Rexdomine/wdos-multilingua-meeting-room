-- ============================================================================
-- WDOS Migration 076 — Leader codes are the truth, not a suggestion
-- (Phase 91 repair)
--
-- Real bug, real damage: South Africa's CR already had an application row
-- in the system (from before Phase 90) with SOME value already sitting in
-- member_no. Migration 074's seeder wrote:
--     member_no = coalesce(member_no, d.member_code)
-- "keep whatever's there, only fill it if empty" — so her genuine leader
-- code CR-ZAF was silently discarded the moment it was minted. Anyone else
-- who already had an application row before Phase 90 has the same wound,
-- invisibly, until they try to sign in.
--
-- This migration FORCES every one of the 43 leader codes onto its rightful
-- row — applications AND (for anyone already claimed) profiles — because
-- the leader directory is now the single source of truth for these codes,
-- overriding whatever was there before. It also fixes the seeding and
-- claim-time functions so this can never happen again.
-- ============================================================================

-- 1 ▸ repair every application row a leader code should own -----------------
update applications a
   set member_no = d.member_code,
       status = 'approved',
       decision_reason = coalesce(decision_reason,
         'Established leader — CR/DCR Contact Directory'),
       decided_at = coalesce(decided_at, now())
  from leader_directory d
 where d.email is not null
   and lower(a.email) = lower(d.email)
   and (a.member_no is distinct from d.member_code);

-- 2 ▸ repair any leader who already claimed, in case membership_no drifted --
update profiles p
   set membership_no = d.member_code
  from leader_directory d
 where p.id = d.claimed_profile
   and (p.membership_no is distinct from d.member_code);

-- 3 ▸ fix the functions so this failure mode can never recur ----------------
create or replace function public.apply_leader_directory(pid uuid)
returns void language plpgsql
security definer set search_path = public as $$
declare d record; p record; cid uuid; rc public.role_code;
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
         role_applied  = coalesce(nullif(role_applied, ''), d.role_applied),
         phone         = coalesce(nullif(phone, ''), nullif(d.phone, '')),
         membership_no = d.member_code            -- authoritative, forced
   where id = pid;
  perform advance_status_on_pass(pid);
  update activation_journeys
     set status = 'deferred'
   where profile_id = pid and status = 'in_progress';
  update leader_directory
     set claimed_profile = pid
   where member_code = d.member_code;

  select ou.id into cid from org_units ou
   where ou.level = 'country' and ou.name = d.country limit 1;
  if cid is not null then
    rc := role_code_for_leader(d.role_applied);
    if not exists (select 1 from role_assignments
                    where profile_id = pid and role = rc
                      and org_unit_id = cid and ends_at is null) then
      insert into role_assignments (profile_id, role, org_unit_id)
      values (pid, rc, cid);
    end if;
  end if;
end $$;

-- 4 ▸ verification: this is what every code should look like now ------------
select d.member_code as expected_code,
       d.first_name || ' ' || d.last_name as leader,
       a.member_no as application_code,
       (d.member_code = a.member_no) as matches,
       d.claimed_profile is not null as claimed
  from leader_directory d
  left join applications a on lower(a.email) = lower(d.email)
 order by (d.member_code = a.member_no) asc, d.country;

insert into public.schema_migrations (version, name)
values (76, 'leader_codes_authoritative_repair') on conflict (version) do nothing;
