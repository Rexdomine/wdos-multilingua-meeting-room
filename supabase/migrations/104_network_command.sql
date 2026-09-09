-- ============================================================================
-- WDOS Migration 104 — Network Command (Phase 133)
--
-- The founder's Monday standard (§6, §8, §10): Headquarters must see, from
-- one authorised screen, per network and consolidated, how many leaders
-- there are, where they are, at what level, which seats are vacant,
-- where each person stands in the leadership journey, who is inactive,
-- what is due or overdue, what support is aging, and what requires
-- management attention — every number drillable to the people behind it.
--
-- Two server pieces:
--   member_stage(pid)       one person's journey stage + next action key
--   network_command(p_net)  the whole bundle for a network ('WGMN',
--                           'WNNN') or all ('all'); HQ only.
-- All figures are real counts from live tables; nothing is estimated.
-- ============================================================================

-- ---- 1. journey stage ----------------------------------------------------
create or replace function public.member_stage(pid uuid)
returns text language sql stable
security definer set search_path = public as $$
  with p as (select * from profiles where id = pid),
       ra as (select 1 from role_assignments r
               where r.profile_id = pid and r.ends_at is null limit 1),
       j as (select status from activation_journeys where profile_id = pid limit 1)
  select case
    when exists (select 1 from ra) then
      case when (select last_seen_at from p) is not null
                and (select last_seen_at from p) < now() - interval '30 days'
           then 'leader_inactive' else 'leader_active' end
    when (select status from j) = 'in_progress' then 'activation'
    when (select status from j) = 'completed'   then 'assessed'
    when (select status from j) = 'incomplete'  then 'activation_lapsed'
    when (select status from p) in ('applicant','under_review') then 'registered'
    when (select status from p) = 'approved' then 'account'
    when (select status from p) in ('suspended','removed','resigned','inactive') then 'exited'
    else 'member' end;
$$;
revoke execute on function public.member_stage(uuid) from anon;

-- ---- 1b. ancestors of a unit (the unit itself, its parent, and so on) -----
create or replace function public.org_unit_ancestors(uid uuid)
returns table (id uuid) language sql stable
security definer set search_path = public as $$
  with recursive up as (
    select ou.id, ou.parent_id from org_units ou where ou.id = uid
    union all
    select ou.id, ou.parent_id from org_units ou join up on ou.id = up.parent_id
  )
  select id from up;
$$;
revoke execute on function public.org_unit_ancestors(uuid) from anon;

-- ---- 2. the bundle ---------------------------------------------------------
create or replace function public.network_command(p_net text default 'all')
returns jsonb language plpgsql stable
security definer set search_path = public as $$
declare
  net text := upper(coalesce(p_net, 'all'));
  all_nets boolean;
  out jsonb;
begin
  if not is_case_hq() then raise exception 'HQ only'; end if;
  all_nets := (net = 'ALL');

  with
  -- people in the chosen network
  ppl as (
    select p.*, (select ou.name from org_units ou where ou.id = p.org_unit_id) as unit_name
      from profiles p
     where all_nets or p.network::text = net
  ),
  -- current leadership seats held, with the country ancestor of each seat
  seats as (
    select r.profile_id, r.role, r.org_unit_id, r.starts_at,
           (select c.id from org_units c
             where c.level = 'country'
               and c.id in (select id from org_unit_ancestors(r.org_unit_id))
             limit 1) as country_id
      from role_assignments r
     where r.ends_at is null
       and r.role in ('country_rep','deputy_country_rep','state_coordinator',
                      'assistant_state_coordinator','district_coordinator',
                      'chapter_lead')
  ),
  lead as (
    select s.*, pp.first_name, pp.last_name, pp.network, pp.last_seen_at,
           pp.email, pp.phone, pp.status as pstatus
      from seats s join ppl pp on pp.id = s.profile_id
  ),
  countries as (
    select c.id, c.name, c.country_iso as iso from org_units c where c.level = 'country'
  ),
  by_country as (
    select c.id, c.name, c.iso,
      (select count(*) from lead l where l.country_id = c.id) as leaders,
      (select count(*) from ppl pp where pp.org_unit_id in
         (select id from org_unit_subtree(c.id))) as members,
      exists (select 1 from lead l where l.country_id = c.id and l.role = 'country_rep') as cr_filled,
      exists (select 1 from lead l where l.country_id = c.id and l.role = 'deputy_country_rep') as dcr_filled,
      (select count(*) from org_units s where s.parent_id = c.id and s.level = 'state_region') as states,
      (select count(distinct l.org_unit_id) from lead l
         join org_units s on s.id = l.org_unit_id
        where s.parent_id = c.id and s.level = 'state_region'
          and l.role = 'state_coordinator') as states_with_coord
      from countries c
  ),
  tasks_open as (
    select tk.id, tk.title, tk.due_on, tk.status, tk.assigned_to,
           pp.first_name || ' ' || pp.last_name as owner
      from tasks tk join ppl pp on pp.id = tk.assigned_to
     where tk.status in ('not_started','in_progress','awaiting_review')
  ),
  meetings_week as (
    select m.id from meetings m
     where m.starts_at between now() and now() + interval '7 days'
  ),
  tickets_open as (
    select tkt.id, tkt.created_at, tkt.status from tickets tkt
     where tkt.status in ('open','in_progress','waiting_on_user')
  ),
  cases_open as (
    select cs.id from cases cs where cs.status in ('submitted','under_review','action_taken')
  ),
  unclaimed as (
    select a.id, a.first_name || ' ' || a.last_name as name, a.email, a.network,
           a.created_at
      from applications a
     where a.status = 'approved' and a.profile_id is null
       and (all_nets or a.network::text = net)
  ),
  journeys as (
    select j.status, j.due_at, j.profile_id, pp.first_name || ' ' || pp.last_name as name,
           pp.network
      from activation_journeys j join ppl pp on pp.id = j.profile_id
  ),
  stages as (
    select member_stage(pp.id) as stage, count(*) as n
      from ppl pp group by 1
  )
  select jsonb_build_object(
    'network', net,
    'totals', jsonb_build_object(
      'members', (select count(*) from ppl),
      'leaders', (select count(*) from lead),
      'active_14d', (select count(*) from ppl where last_seen_at >= now() - interval '14 days'),
      'inactive_30d', (select count(*) from lead where last_seen_at is null
                          or last_seen_at < now() - interval '30 days'),
      'unclaimed', (select count(*) from unclaimed),
      'activation_in_progress', (select count(*) from journeys where status = 'in_progress'),
      'activation_completed', (select count(*) from journeys where status = 'completed'),
      'activation_lapsed', (select count(*) from journeys where status = 'incomplete'),
      'tasks_open', (select count(*) from tasks_open),
      'tasks_overdue', (select count(*) from tasks_open where due_on < current_date),
      'meetings_7d', (select count(*) from meetings_week),
      'tickets_open', (select count(*) from tickets_open),
      'tickets_aging', (select count(*) from tickets_open where created_at < now() - interval '3 days'),
      'cases_open', (select count(*) from cases_open),
      'countries_covered', (select count(*) from by_country where leaders > 0),
      'countries_total', (select count(*) from by_country),
      'vacant_cr', (select count(*) from by_country where not cr_filled),
      'vacant_dcr', (select count(*) from by_country where not dcr_filled)
    ),
    'by_level', (select coalesce(jsonb_agg(jsonb_build_object('role', role, 'n', n)
                     order by n desc), '[]'::jsonb)
                   from (select role, count(*) as n from lead group by role) x),
    'by_country', (select coalesce(jsonb_agg(jsonb_build_object(
                     'id', id, 'name', name, 'iso', iso, 'leaders', leaders,
                     'members', members, 'cr_filled', cr_filled,
                     'dcr_filled', dcr_filled, 'states', states,
                     'states_with_coord', states_with_coord)
                     order by leaders desc, name), '[]'::jsonb) from by_country),
    'stages', (select coalesce(jsonb_agg(jsonb_build_object('stage', stage, 'n', n)
                     order by n desc), '[]'::jsonb) from stages),
    'attention', jsonb_build_object(
      'inactive_leaders', (select coalesce(jsonb_agg(jsonb_build_object(
          'id', profile_id, 'name', first_name || ' ' || last_name, 'role', role,
          'network', network, 'last_seen_at', last_seen_at,
          'country', (select name from org_units where id = country_id))
          order by last_seen_at nulls first), '[]'::jsonb)
        from (select * from lead where last_seen_at is null
                 or last_seen_at < now() - interval '30 days' limit 60) x),
      'vacant_cr', (select coalesce(jsonb_agg(jsonb_build_object(
          'id', id, 'name', name, 'iso', iso, 'cr_filled', cr_filled,
          'dcr_filled', dcr_filled) order by name), '[]'::jsonb)
        from by_country where not cr_filled or not dcr_filled),
      'activation_stalled', (select coalesce(jsonb_agg(jsonb_build_object(
          'id', profile_id, 'name', name, 'network', network, 'due_at', due_at)
          order by due_at), '[]'::jsonb)
        from (select * from journeys where status = 'in_progress'
                 and due_at < now() + interval '3 days' limit 60) x),
      'overdue_tasks', (select coalesce(jsonb_agg(jsonb_build_object(
          'id', id, 'title', title, 'due_on', due_on, 'owner', owner,
          'owner_id', assigned_to) order by due_on), '[]'::jsonb)
        from (select * from tasks_open where due_on < current_date limit 60) x),
      'unclaimed', (select coalesce(jsonb_agg(jsonb_build_object(
          'id', id, 'name', name, 'email', email, 'network', network,
          'created_at', created_at) order by created_at), '[]'::jsonb)
        from (select * from unclaimed order by created_at limit 60) x),
      'missing_info', (select coalesce(jsonb_agg(jsonb_build_object(
          'id', profile_id, 'name', first_name || ' ' || last_name, 'role', role,
          'missing', array_remove(array[
             case when phone is null or phone = '' then 'phone' end,
             case when email is null or email = '' then 'email' end,
             case when country_id is null then 'country' end], null))
          order by last_name), '[]'::jsonb)
        from (select * from lead where phone is null or phone = '' or country_id is null limit 60) x)
    )
  ) into out;
  return out;
end $$;
revoke execute on function public.network_command(text) from anon;

insert into public.schema_migrations (version, name)
values (104, 'network_command') on conflict (version) do nothing;
