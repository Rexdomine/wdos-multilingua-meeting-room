-- ============================================================================
-- WDOS Migration 005 — Leadership & Organisation Management
-- Create org units and appoint/end leadership roles from the application,
-- governed by seniority + territory rules, with reasons in the audit trail.
-- Appointments are never deleted: they end (ends_at), preserving history
-- (Gap Analysis §8 — succession with preserved records).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. ROLE SENIORITY (lower rank = more senior)
-- ---------------------------------------------------------------------------

create or replace function public.role_rank(r public.role_code)
returns int language sql immutable as $$
  select case r
    when 'super_admin'                 then 0
    when 'executive_director'          then 1
    when 'hq_team'                     then 2
    when 'country_rep'                 then 3
    when 'deputy_country_rep'          then 4
    when 'state_coordinator'           then 5
    when 'assistant_state_coordinator' then 6
    when 'district_coordinator'        then 7
    when 'chapter_lead'                then 8
    else 99
  end;
$$;

-- Most senior active role the caller holds whose territory covers `unit`.
create or replace function public.my_rank_over(unit uuid)
returns int language sql stable security definer set search_path = public as $$
  select min(role_rank(ra.role))
  from role_assignments ra
  where ra.profile_id = auth.uid()
    and ra.ends_at is null
    and unit in (select org_unit_subtree(ra.org_unit_id));
$$;

-- ---------------------------------------------------------------------------
-- 2. ORG UNIT CREATION (in-app, authority = State Coordinator+ over parent)
-- ---------------------------------------------------------------------------

create or replace function public.child_level(parent public.org_level)
returns public.org_level language sql immutable as $$
  select case parent
    when 'headquarters' then 'country'::public.org_level
    when 'country'      then 'state_region'::public.org_level
    when 'state_region' then 'district_lga'::public.org_level
    when 'district_lga' then 'chapter'::public.org_level
    else null
  end;
$$;

create or replace function public.create_org_unit(
  parent uuid, unit_name text, iso char(2) default null)
returns public.org_units
language plpgsql security definer set search_path = public as $$
declare p public.org_units; u public.org_units;
begin
  select * into p from org_units where id = parent and is_active;
  if p.id is null then raise exception 'Parent unit not found'; end if;
  if child_level(p.level) is null then
    raise exception 'Chapters cannot contain sub-units';
  end if;
  if not can_approve(parent) then
    raise exception 'Creating units requires a State Coordinator role or above over the parent unit';
  end if;
  if unit_name is null or char_length(trim(unit_name)) < 2 then
    raise exception 'Unit name must be at least 2 characters';
  end if;
  insert into org_units (parent_id, level, name, country_iso)
  values (parent, child_level(p.level), trim(unit_name),
          case when child_level(p.level) = 'country' then upper(iso) end)
  returning * into u;
  return u;
end; $$;

-- ---------------------------------------------------------------------------
-- 3. APPOINT A LEADER
-- Rules: (a) caller's rank over the unit must be strictly senior to the role
-- being granted; (b) the appointee must be a member in good standing;
-- (c) reason is mandatory and lands in the audit trail.
-- ---------------------------------------------------------------------------

create or replace function public.appoint_leader(
  target_profile uuid, new_role public.role_code, unit uuid, reason text)
returns public.role_assignments
language plpgsql security definer set search_path = public as $$
declare
  caller_rank int;
  target public.profiles;
  ra public.role_assignments;
begin
  if reason is null or char_length(trim(reason)) < 5 then
    raise exception 'A reason is required for an appointment';
  end if;
  if role_rank(new_role) = 99 then
    raise exception 'This role cannot be appointed through leadership management';
  end if;

  caller_rank := my_rank_over(unit);
  if caller_rank is null or caller_rank >= role_rank(new_role) then
    raise exception 'You can only appoint roles junior to your own, within your territory';
  end if;

  select * into target from profiles where id = target_profile;
  if target.id is null then raise exception 'Member not found'; end if;
  if target.status not in ('activated','in_training','active','reinstated') then
    raise exception 'Only members in good standing can be appointed (current status: %)',
      target.status;
  end if;
  if not exists (select 1 from org_units where id = unit and is_active) then
    raise exception 'Unit not found';
  end if;

  perform set_config('wdos.reason', reason, true);
  insert into role_assignments (profile_id, role, org_unit_id, assigned_by)
  values (target_profile, new_role, unit, auth.uid())
  returning * into ra;
  return ra;
exception
  when unique_violation then
    raise exception 'This member already holds that role at this unit';
end; $$;

-- ---------------------------------------------------------------------------
-- 4. END AN APPOINTMENT (resignation, transfer, removal — history preserved)
-- ---------------------------------------------------------------------------

create or replace function public.end_appointment(assignment_id uuid, reason text)
returns public.role_assignments
language plpgsql security definer set search_path = public as $$
declare ra public.role_assignments; caller_rank int;
begin
  if reason is null or char_length(trim(reason)) < 5 then
    raise exception 'A reason is required to end an appointment';
  end if;
  select * into ra from role_assignments where id = assignment_id for update;
  if ra.id is null then raise exception 'Appointment not found'; end if;
  if ra.ends_at is not null then
    raise exception 'This appointment has already ended';
  end if;

  caller_rank := my_rank_over(ra.org_unit_id);
  -- A person may resign their own role; otherwise strict seniority applies.
  if ra.profile_id <> auth.uid()
     and (caller_rank is null or caller_rank >= role_rank(ra.role)) then
    raise exception 'Ending this appointment requires a more senior role over this unit';
  end if;

  perform set_config('wdos.reason', reason, true);
  update role_assignments set ends_at = now()
   where id = assignment_id
   returning * into ra;
  return ra;
end; $$;
