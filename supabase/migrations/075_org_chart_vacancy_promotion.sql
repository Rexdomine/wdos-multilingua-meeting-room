-- ============================================================================
-- WDOS Migration 075 — The org chart tells the truth (Phase 91)
-- role_assignments already IS a seat-tracking system (profile + role + org
-- unit + start/end date — no end date means "currently holding this seat").
-- This migration:
--   1. Wires the 43 established leaders into real seats at their country's
--      org_unit (country_rep / deputy_country_rep) — the claim-time hook
--      does the same for every future claim, forever.
--   2. Seeds every Nigerian state (36 + FCT) as a VACANT state_coordinator
--      seat — visible, honest, empty until someone is chosen to fill it.
--   3. org_chart_country(iso) — a country's full seat list: who holds it,
--      or "Vacant". Existing leaders are NEVER replaced by this system.
--   4. promotion_candidates() — everyone who has PASSED the 14-day
--      activation and does not yet hold a seat: name, position applied
--      for, country/state/LGA, verdict.
--   5. vacant_seats_for(iso) — the seats a candidate could be offered,
--      filtered to their country.
--   6. promote_candidate(pid, org_unit_id, role) — the one-off button.
--      Fills ONLY a seat that is genuinely vacant at the moment of the
--      click; never disturbs an existing holder.
-- ============================================================================

-- 1 ▸ wire the 43 into real seats -------------------------------------------
create or replace function public.role_code_for_leader(label text)
returns public.role_code language sql immutable as $$
  select case
    when label ilike '%deputy%' then 'deputy_country_rep'::public.role_code
    else 'country_rep'::public.role_code
  end;
$$;

do $$
declare d record; cid uuid; rc public.role_code;
begin
  perform set_config('wdos.system', '1', true);
  for d in select ld.*, p.id as pid from leader_directory ld
            join profiles p on p.id = ld.claimed_profile
  loop
    select id into cid from org_units
     where level = 'country'
       and country_iso = (
         select iso from (values
           ('Benin','BJ'),('Burkina Faso','BF'),('Burundi','BI'),
           ('Cameroon','CM'),('Central African Republic','CF'),('Chad','TD'),
           ('Congo','CG'),('Côte d''Ivoire','CI'),('DR Congo','CD'),
           ('Gambia','GM'),('Ghana','GH'),('Guinea','GN'),
           ('Guinea-Bissau','GW'),('Kenya','KE'),('Madagascar','MG'),
           ('Mali','ML'),('Morocco','MA'),('Niger','NE'),('Nigeria','NG'),
           ('Rwanda','RW'),('Senegal','SN'),('South Africa','ZA'),
           ('Togo','TG'),('Tunisia','TN'),('Uganda','UG')
         ) as m(cname, iso) where cname = d.country limit 1);
    if cid is null then continue; end if;
    rc := role_code_for_leader(d.role_applied);
    if not exists (select 1 from role_assignments
                    where profile_id = d.pid and role = rc
                      and org_unit_id = cid and ends_at is null) then
      insert into role_assignments (profile_id, role, org_unit_id)
      values (d.pid, rc, cid);
    end if;
  end loop;
end $$;

-- claim-time: the promotion hook now seats the leader too
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
         membership_no = coalesce(membership_no, d.member_code)
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

-- 2 ▸ Nigeria's state seats exist as VACANT until filled --------------------
-- (state org_units already seeded by migration 026; this adds nothing
-- structural — vacancy is simply the absence of a role_assignments row,
-- which is what org_chart_country reads below.)

-- 3 ▸ the org chart -----------------------------------------------------
create or replace function public.org_chart_country(iso text)
returns jsonb language plpgsql stable
security definer set search_path = public as $$
declare country_row org_units; result jsonb;
begin
  if not is_case_hq() then raise exception 'HQ only'; end if;
  select * into country_row from org_units
   where level = 'country' and country_iso = upper(iso) limit 1;
  if country_row.id is null then return jsonb_build_object('seats', '[]'); end if;

  select jsonb_build_object(
    'country', country_row.name,
    'iso', country_row.country_iso,
    'seats', coalesce((
      select jsonb_agg(jsonb_build_object(
        'org_unit_id', ou.id,
        'level', ou.level,
        'location', ou.name,
        'role', ra_role.role,
        'holder_id', ra_role.profile_id,
        'holder_name', hp.first_name || ' ' || hp.last_name,
        'vacant', ra_role.profile_id is null
      ) order by ou.level, ou.name, ra_role.role)
      from (
        select country_row.id as ou_id, country_row.name as ou_name,
               'country'::public.org_level as ou_level,
               unnest(array['country_rep','deputy_country_rep'])
                 as want_role
        union all
        select su.id, su.name, 'state_region', 'state_coordinator'
          from org_units su
         where su.parent_id = country_row.id and su.level = 'state_region'
      ) seats(ou_id, ou_name, ou_lvl, want_role)
      join org_units ou on ou.id = seats.ou_id
      left join lateral (
        select r.profile_id, r.role from role_assignments r
         where r.org_unit_id = seats.ou_id
           and r.role::text = seats.want_role
           and r.ends_at is null
         limit 1
      ) ra_role on true
      left join profiles hp on hp.id = ra_role.profile_id
    ), '[]'::jsonb)
  ) into result;
  return result;
end; $$;
revoke execute on function public.org_chart_country(text) from anon;

create or replace function public.org_chart_countries()
returns jsonb language sql stable
security definer set search_path = public as $$
  select case when public.is_case_hq() then
    coalesce(jsonb_agg(jsonb_build_object('iso', country_iso, 'name', name)
      order by name), '[]'::jsonb)
  else '[]'::jsonb end
  from org_units where level = 'country';
$$;
revoke execute on function public.org_chart_countries() from anon;

-- 4 ▸ promotion candidates ---------------------------------------------------
create or replace function public.promotion_candidates()
returns jsonb language plpgsql stable
security definer set search_path = public as $$
begin
  if not is_case_hq() then raise exception 'HQ only'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', p.id,
      'name', p.first_name || ' ' || p.last_name,
      'membership_no', p.membership_no,
      'role_applied', p.role_applied,
      'country', p.country,
      'state', p.state_region,
      'lga', p.lga,
      'passed_at', j.completed_at
    ) order by j.completed_at)
    from profiles p
    join activation_journeys j on j.profile_id = p.id
    where j.status = 'completed'
      and not p.is_leader
      and p.merged_into is null
  ), '[]'::jsonb);
end; $$;
revoke execute on function public.promotion_candidates() from anon;

-- 5 ▸ vacant seats a candidate could fill -----------------------------------
create or replace function public.vacant_seats_for(iso text)
returns jsonb language sql stable
security definer set search_path = public as $$
  select case when public.is_case_hq() then
    coalesce((select jsonb_path_query_array(
      public.org_chart_country(iso) -> 'seats',
      '$[*] ? (@.vacant == true)')), '[]'::jsonb)
  else '[]'::jsonb end;
$$;
revoke execute on function public.vacant_seats_for(text) from anon;

-- 6 ▸ the one-off onboarding button ------------------------------------------
create or replace function public.promote_candidate(
  pid uuid, target_unit uuid, target_role public.role_code)
returns jsonb language plpgsql
security definer set search_path = public as $$
declare already_held boolean;
begin
  if not is_case_hq() then raise exception 'HQ only'; end if;

  select exists (select 1 from role_assignments
                  where org_unit_id = target_unit and role = target_role
                    and ends_at is null)
    into already_held;
  if already_held then
    raise exception 'That seat is already filled — choose another';
  end if;

  perform set_config('wdos.system', '1', true);
  insert into role_assignments (profile_id, role, org_unit_id, assigned_by)
  values (pid, target_role, target_unit, auth.uid());
  update profiles set is_leader = true where id = pid;

  insert into member_notices (profile_id, kind, title, body)
  values (pid, 'nudge', 'Congratulations — you are now a WODDI Leader!',
    'HQ has appointed you to a leadership seat, in recognition of '
    || 'completing your 14-day activation. Your leadership tools are now '
    || 'open. Thank you for stepping up to lead.');

  return jsonb_build_object('ok', true);
end; $$;
revoke execute on function public.promote_candidate(uuid, uuid,
  public.role_code) from anon;

insert into public.schema_migrations (version, name)
values (75, 'org_chart_vacancy_promotion') on conflict (version) do nothing;
