-- ============================================================================
-- WDOS: Regina Okoro as Country Representative (no HQ access)
-- Run in the Supabase SQL Editor. Safe to re-run.
--
-- Reverses the earlier HQ-team provisioning and seats her as a
-- COUNTRY REPRESENTATIVE. Choose her seat below:
--   'ALL'      = country rep over EVERY country (the "Super Country
--                Representative": country-rep powers, organisation-wide
--                scope, no HQ screens)         <- default
--   'Nigeria'  = country rep for Nigeria only (or any country name
--                exactly as it appears in the organisation tree)
-- ============================================================================

do $$
declare
  v_email text := 'uchechukwuokori81@gmail.com';
  v_seat  text := 'ALL';           -- change to 'Nigeria' for one country
  v_uid   uuid;
  v_hq    uuid;
  v_unit  uuid;
  v_cur   public.member_status;
  v_step  public.member_status;
begin
  select id into v_uid from auth.users where lower(email) = lower(v_email);
  if v_uid is null then
    raise exception 'No login found for %', v_email;
  end if;

  select id into v_hq from public.org_units
   where level = 'headquarters' order by created_at limit 1;

  if v_seat = 'ALL' then
    v_unit := v_hq;                -- subtree of HQ = every country
  else
    select id into v_unit from public.org_units
     where level = 'country' and name = v_seat limit 1;
    if v_unit is null then
      raise exception 'Country "%" not found in the organisation tree', v_seat;
    end if;
  end if;

  -- 1. remove HQ-level access from the earlier run
  update public.role_assignments
     set ends_at = now()
   where profile_id = v_uid and ends_at is null
     and role in ('hq_team','super_admin','executive_director');
  update public.staff set is_active = false where profile_id = v_uid;

  -- 2. profile: names, seat, membership number; walk status to active
  update public.profiles
     set first_name    = 'Regina',
         last_name     = 'Okoro',
         org_unit_id   = v_unit,
         membership_no = coalesce(membership_no, public.next_membership_no())
   where id = v_uid;
  foreach v_step in array array['under_review','approved','activated','active']::public.member_status[] loop
    select status into v_cur from public.profiles where id = v_uid;
    exit when v_cur = 'active';
    if public.valid_status_transition(v_cur, v_step) then
      update public.profiles set status = v_step where id = v_uid;
    end if;
  end loop;

  -- 3. the country representative role at her seat
  update public.role_assignments
     set ends_at = now()
   where profile_id = v_uid and ends_at is null
     and role = 'country_rep' and org_unit_id <> v_unit;
  if not exists (select 1 from public.role_assignments
                  where profile_id = v_uid and role = 'country_rep'
                    and org_unit_id = v_unit and ends_at is null) then
    insert into public.role_assignments (profile_id, role, org_unit_id)
    values (v_uid, 'country_rep', v_unit);
  end if;

  raise notice 'Regina Okoro: country_rep seated at % (status %).',
    (select name from public.org_units where id = v_unit), v_cur;
end $$;

-- 4. Undo the Reports grant that was added for the HQ-team version
--    (restores the earlier policy: Reports stays with HQ leadership).
delete from public.module_access where role = 'hq_team' and module = 'reports';

-- Check: her current roles and seat
select p.first_name, p.last_name, p.email, p.status, ra.role,
       ou.name as seat, ou.level, u.last_sign_in_at
  from public.profiles p
  join public.role_assignments ra on ra.profile_id = p.id and ra.ends_at is null
  join public.org_units ou on ou.id = ra.org_unit_id
  join auth.users u on u.id = p.id
 where lower(p.email) = 'uchechukwuokori81@gmail.com';
