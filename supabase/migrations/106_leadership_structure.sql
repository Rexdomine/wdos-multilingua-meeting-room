-- ============================================================================
-- WDOS Migration 106 — Volunteer Leadership Structure (founder's standard)
--
-- Geography and position are two connected dimensions. Geography is the
-- org_units tree (HQ → country → state_region → district_lga → chapter,
-- where "chapter" is the Community Cluster / Ward level). Position is the
-- role_code master list (eight volunteer positions since 105). This
-- migration adds what the standard asks for on top of that:
--   1. appointment_status on every seat: appointed / acting / pending
--      (vacant = no seat), settable by HQ.
--   2. level_terms: country-sensitive display names for the geographic
--      levels (Nigeria: State / LGA / Ward; Ghana: Region / District /
--      Community; ...) with a default row. Internal levels never change.
--   3. position_master: the eight positions with their level and rank, so
--      pages and the explorer never type a title by hand.
--   4. administered_units() extended so the two new assistant positions
--      administer their unit like the other seats.
--   5. volunteer_home: "Reports to" corrected for leaders (the leader of
--      the unit above the seat, principal before deputy, same network),
--      "Direct reports" added, terms + appointment status in the bundle.
--   6. structure_explorer(): Network → Country → Region → District →
--      Level → Position → Appointment status → Activation status, listing
--      every seat in scope, filled or VACANT.
-- Requires 105 (run separately, before this file).
-- ============================================================================

-- 1 ▸ appointment status
do $$ begin
  if not exists (select 1 from pg_type where typname = 'appointment_status') then
    create type public.appointment_status as enum ('appointed', 'acting', 'pending');
  end if;
end $$;
alter table public.role_assignments
  add column if not exists appointment_status public.appointment_status not null default 'appointed';

-- 2 ▸ country-sensitive terminology (internal levels unchanged)
create table if not exists public.level_terms (
  country_iso   text primary key,                -- '' = default
  term_country  text not null default 'Country',
  term_state    text not null default 'Region / State / Province',
  term_district text not null default 'District / LGA / Municipality',
  term_chapter  text not null default 'Community Cluster / Ward',
  updated_at    timestamptz not null default now()
);
alter table public.level_terms enable row level security;
drop policy if exists level_terms_read on public.level_terms;
create policy level_terms_read on public.level_terms for select to authenticated using (true);
drop policy if exists level_terms_write on public.level_terms;
create policy level_terms_write on public.level_terms for all to authenticated
  using (public.is_case_hq()) with check (public.is_case_hq());

insert into public.level_terms (country_iso, term_country, term_state, term_district, term_chapter) values
  ('',   'Country', 'Region / State / Province', 'District / LGA / Municipality', 'Community Cluster / Ward'),
  ('NG', 'Country', 'State', 'LGA', 'Ward / Community Cluster'),
  ('GH', 'Country', 'Region', 'District', 'Community'),
  ('KE', 'Country', 'County', 'Sub-County', 'Ward'),
  ('UG', 'Country', 'Region', 'District', 'Sub-County'),
  ('TZ', 'Country', 'Region', 'District', 'Ward'),
  ('RW', 'Country', 'Province', 'District', 'Sector'),
  ('ZA', 'Country', 'Province', 'District Municipality', 'Ward'),
  ('CM', 'Country', 'Region', 'Department', 'Commune'),
  ('ET', 'Country', 'Region', 'Zone', 'Woreda'),
  ('SN', 'Country', 'Région', 'Département', 'Commune'),
  ('CI', 'Country', 'District', 'Région', 'Commune'),
  ('ZM', 'Country', 'Province', 'District', 'Ward'),
  ('ZW', 'Country', 'Province', 'District', 'Ward'),
  ('MW', 'Country', 'Region', 'District', 'Traditional Authority'),
  ('SL', 'Country', 'Province', 'District', 'Chiefdom'),
  ('LR', 'Country', 'County', 'District', 'Clan / Community'),
  ('GM', 'Country', 'Region', 'District', 'Ward'),
  ('EG', 'Country', 'Governorate', 'Markaz / District', 'Village / Neighbourhood'),
  ('MA', 'Country', 'Region', 'Province / Prefecture', 'Commune')
on conflict (country_iso) do nothing;

create or replace function public.level_terms_for(iso text)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'country', t.term_country, 'state_region', t.term_state,
    'district_lga', t.term_district, 'chapter', t.term_chapter,
    'country_iso', coalesce(nullif(t.country_iso, ''), null))
  from (
    select * from level_terms
     where country_iso in (upper(coalesce(iso, '')), '')
     order by (country_iso <> '') desc
     limit 1) t;
$$;

-- 3 ▸ position master list
create table if not exists public.position_master (
  role  public.role_code primary key,
  level public.org_level not null,
  rank  smallint not null,          -- 1 principal, 2 deputy/assistant
  seq   smallint not null
);
insert into public.position_master (role, level, rank, seq) values
  ('country_rep', 'country', 1, 1),
  ('deputy_country_rep', 'country', 2, 2),
  ('state_coordinator', 'state_region', 1, 3),
  ('assistant_state_coordinator', 'state_region', 2, 4),
  ('district_coordinator', 'district_lga', 1, 5),
  ('assistant_district_coordinator', 'district_lga', 2, 6),
  ('chapter_lead', 'chapter', 1, 7),
  ('assistant_chapter_lead', 'chapter', 2, 8)
on conflict (role) do update set level = excluded.level, rank = excluded.rank, seq = excluded.seq;
alter table public.position_master enable row level security;
drop policy if exists position_master_read on public.position_master;
create policy position_master_read on public.position_master for select to authenticated using (true);

-- 4 ▸ scope: the two new assistant positions administer their unit
create or replace function public.administered_units()
returns setof uuid
language sql stable security definer set search_path = public as $$
  select distinct s.id
  from role_assignments ra
  cross join lateral org_unit_subtree(ra.org_unit_id) as s(id)
  where ra.profile_id = auth.uid()
    and ra.ends_at is null
    and ra.role in ('super_admin','executive_director','hq_team',
                    'country_rep','deputy_country_rep',
                    'state_coordinator','assistant_state_coordinator',
                    'district_coordinator','assistant_district_coordinator',
                    'chapter_lead','assistant_chapter_lead');
$$;

create or replace function public.administered_units_of(pid uuid)
returns setof uuid
language sql stable security definer set search_path = public as $$
  select distinct s.id
  from role_assignments ra
  cross join lateral org_unit_subtree(ra.org_unit_id) as s(id)
  where ra.profile_id = pid
    and ra.ends_at is null
    and ra.role in ('super_admin', 'executive_director', 'hq_team',
                    'country_rep', 'deputy_country_rep',
                    'state_coordinator', 'assistant_state_coordinator',
                    'district_coordinator', 'assistant_district_coordinator',
                    'chapter_lead', 'assistant_chapter_lead');
$$;

-- HQ seating with appointment status (replaces the 3-argument version)
drop function if exists public.hq_set_role(uuid, public.role_code, uuid);
create or replace function public.hq_set_role(
  pid uuid, new_role public.role_code, unit uuid,
  appt public.appointment_status default 'appointed')
returns void language plpgsql
security definer set search_path = public as $$
declare lvl public.org_level;
begin
  if not is_case_hq() then raise exception 'HQ only'; end if;
  if not exists (select 1 from profiles where id = pid) then
    raise exception 'No such member';
  end if;
  select level into lvl from org_units where id = unit;
  if lvl is null then raise exception 'No such unit'; end if;
  if new_role in ('super_admin', 'executive_director', 'hq_team') and lvl <> 'headquarters' then
    raise exception 'HQ roles must be seated at headquarters';
  end if;
  if new_role = 'super_admin' and not has_role(array['super_admin']::public.role_code[]) then
    raise exception 'Only a super admin can grant super admin';
  end if;
  update role_assignments set ends_at = now()
   where profile_id = pid and ends_at is null;
  insert into role_assignments (profile_id, role, org_unit_id, assigned_by, appointment_status)
  values (pid, new_role, unit, auth.uid(), appt);
  if exists (select 1 from position_master where role = new_role) then
    update profiles set is_leader = true where id = pid;
  end if;
end; $$;
revoke execute on function public.hq_set_role(uuid, public.role_code, uuid, public.appointment_status) from anon;

create or replace function public.hq_set_appointment(pid uuid, appt public.appointment_status)
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not is_case_hq() then raise exception 'HQ only'; end if;
  update role_assignments set appointment_status = appt
   where profile_id = pid and ends_at is null;
  get diagnostics n = row_count;
  return n;
end; $$;
revoke execute on function public.hq_set_appointment(uuid, public.appointment_status) from anon;

-- 5 ▸ volunteer_home with reports-to fix, direct reports, terms, appointment status
create or replace function public.volunteer_home(pid uuid default null)
returns jsonb language plpgsql stable
security definer set search_path = public as $$
declare
  target uuid;
  p profiles%rowtype;
  v_today date := current_date;
  v_chain jsonb;
  v_coord jsonb;
  v_roles jsonb;
  v_tasks jsonb;
  v_tcounts jsonb;
  v_meet jsonb;
  v_attended int;
  v_learn jsonb;
  v_ann jsonb;
  v_ann_unread int;
  v_impact jsonb;
  v_tickets jsonb;
  v_ach jsonb;
  v_journey jsonb;
  v_lead jsonb;
  v_months int;
  v_start timestamptz;
  v_is_staff boolean;
  v_notices int;
  v_msgs int;
  v_completion int;
  v_referrals jsonb;
  v_docs jsonb;
  v_seat_unit uuid;
  v_reports jsonb;
  v_terms jsonb;
  v_iso text;
begin
  if pid is null then
    target := auth.uid();
  else
    if not is_case_hq() then raise exception 'HQ only'; end if;
    target := pid;
  end if;
  if target is null then raise exception 'Not signed in'; end if;

  select * into p from profiles where id = target;
  if not found then raise exception 'No such member'; end if;

  -- service start: the day the activation journey completed, else the day
  -- the account was created (never fabricated)
  select coalesce(
           (select completed_at from activation_journeys
             where profile_id = target and completed_at is not null),
           p.created_at)
    into v_start;
  v_months := greatest(0, (extract(year from age(now(), v_start)) * 12
                + extract(month from age(now(), v_start)))::int);

  -- network chain: HQ → country → state → LGA → chapter (root first)
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', c.id, 'level', c.level, 'name', c.name)
           order by c.depth desc), '[]'::jsonb)
    into v_chain
    from unit_chain(p.org_unit_id) c;

  -- "Reports to": for a member, the nearest leader on her own line; for a
  -- leader, the leader of the unit ABOVE her seat (her peers and assistants
  -- at the same unit are not her superiors). Principal before deputy.
  select ra.org_unit_id into v_seat_unit
    from role_assignments ra
   where ra.profile_id = target and ra.ends_at is null
     and ra.role in ('country_rep', 'deputy_country_rep', 'state_coordinator',
                     'assistant_state_coordinator', 'district_coordinator',
                     'assistant_district_coordinator', 'chapter_lead',
                     'assistant_chapter_lead')
   order by case ra.role when 'country_rep' then 1 when 'deputy_country_rep' then 2
            when 'state_coordinator' then 3 when 'assistant_state_coordinator' then 4
            when 'district_coordinator' then 5 when 'assistant_district_coordinator' then 6
            when 'chapter_lead' then 7 else 8 end
   limit 1;

  select jsonb_build_object(
           'id', ra.profile_id,
           'name', hp.first_name || ' ' || hp.last_name,
           'role', ra.role,
           'appointment_status', ra.appointment_status,
           'role_applied', hp.role_applied,
           'unit', c.name, 'level', c.level)
    into v_coord
    from unit_chain(coalesce(
           (select parent_id from org_units where id = v_seat_unit),
           case when v_seat_unit is null then p.org_unit_id else null end)) c
    join role_assignments ra on ra.org_unit_id = c.id and ra.ends_at is null
     and ra.role in ('country_rep', 'deputy_country_rep', 'state_coordinator',
                     'assistant_state_coordinator', 'district_coordinator',
                     'assistant_district_coordinator', 'chapter_lead',
                     'assistant_chapter_lead')
    join profiles hp on hp.id = ra.profile_id
   where ra.profile_id <> target
     and (hp.network = p.network or hp.network is null)
   order by c.depth asc,
            case ra.role
              when 'country_rep' then 1 when 'state_coordinator' then 1
              when 'district_coordinator' then 1 when 'chapter_lead' then 1
              else 2 end
   limit 1;

  -- direct reports (leaders only): deputies/assistants at my own unit and
  -- the leaders seated at the units directly below mine, same network
  if v_seat_unit is not null then
    select coalesce(jsonb_agg(jsonb_build_object(
             'id', ra.profile_id, 'name', hp.first_name || ' ' || hp.last_name,
             'role', ra.role, 'appointment_status', ra.appointment_status,
             'unit', ou.name, 'level', ou.level, 'last_seen', hp.last_seen_at)
             order by ou.level, ou.name, ra.role), '[]'::jsonb)
      into v_reports
      from role_assignments ra
      join org_units ou on ou.id = ra.org_unit_id
      join profiles hp on hp.id = ra.profile_id
     where ra.ends_at is null and ra.profile_id <> target
       and (ou.id = v_seat_unit or ou.parent_id = v_seat_unit)
       and hp.network = p.network
       and ra.role in ('deputy_country_rep', 'state_coordinator',
                       'assistant_state_coordinator', 'district_coordinator',
                       'assistant_district_coordinator', 'chapter_lead',
                       'assistant_chapter_lead')
       and not (ou.id = v_seat_unit and ra.role in ('country_rep', 'state_coordinator',
                                                    'district_coordinator', 'chapter_lead'));
  else
    v_reports := '[]'::jsonb;
  end if;

  -- country-sensitive level terminology
  select ou.country_iso into v_iso
    from unit_chain(p.org_unit_id) c join org_units ou on ou.id = c.id
   where c.level = 'country' limit 1;
  v_terms := level_terms_for(v_iso);

  -- current seats
  select coalesce(jsonb_agg(jsonb_build_object(
           'role', ra.role, 'unit_id', ou.id, 'unit', ou.name,
           'level', ou.level, 'since', ra.starts_at,
           'appointment_status', ra.appointment_status)
           order by ra.starts_at), '[]'::jsonb)
    into v_roles
    from role_assignments ra join org_units ou on ou.id = ra.org_unit_id
   where ra.profile_id = target and ra.ends_at is null;

  -- tasks
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', t.id, 'title', t.title, 'status', t.status,
           'due_on', t.due_on, 'priority', t.priority,
           'overdue', (t.due_on is not null and t.due_on < v_today))
           order by t.due_on nulls last, t.created_at), '[]'::jsonb)
    into v_tasks
    from (select * from tasks
           where assigned_to = target
             and status in ('not_started', 'in_progress', 'awaiting_review')
           order by due_on nulls last, created_at limit 8) t;

  select jsonb_build_object(
           'open', count(*) filter (where status in ('not_started', 'in_progress', 'awaiting_review')),
           'overdue', count(*) filter (where status in ('not_started', 'in_progress', 'awaiting_review')
                                        and due_on is not null and due_on < v_today),
           'due_week', count(*) filter (where status in ('not_started', 'in_progress', 'awaiting_review')
                                         and due_on between v_today and v_today + 7),
           'completed', count(*) filter (where status = 'completed'))
    into v_tcounts
    from tasks where assigned_to = target;

  -- meetings (audience-aware, plus anything I organise or administer)
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', m.id, 'title', m.title, 'starts_at', m.starts_at,
           'ends_at', m.ends_at, 'mode', m.mode, 'platform', m.platform,
           'location', m.location, 'audience', m.audience,
           'unit', ou.name, 'status', m.status)
           order by m.starts_at), '[]'::jsonb)
    into v_meet
    from (select * from meetings m0
           where m0.status = 'scheduled' and m0.ends_at >= now()
             and (meeting_reaches(m0, target) or m0.organiser = target
                  or m0.org_unit_id in (select administered_units_of(target)))
           order by m0.starts_at limit 6) m
    left join org_units ou on ou.id = m.org_unit_id;

  select count(*) into v_attended from (
    select meeting_id from meeting_attendance
     where profile_id = target and present
    union
    select meeting_id from meeting_checkins where profile_id = target) x;

  -- learning: every active course, my enrolment, my module passes
  select coalesce(jsonb_agg(course order by course->>'code'), '[]'::jsonb)
    into v_learn
    from (
      select jsonb_build_object(
        'id', c.id, 'code', c.code, 'title', c.title,
        'description', c.description,
        'enrollment_id', ce.id, 'started_at', ce.started_at,
        'completed_at', ce.completed_at, 'cert_no', ce.cert_no,
        'modules', (
          select coalesce(jsonb_agg(jsonb_build_object(
                   'id', cm.id, 'seq', cm.seq, 'title', cm.title,
                   'passed', coalesce(cp.passed, false),
                   'score', cp.score, 'total', cp.total,
                   'completed_at', cp.completed_at)
                   order by cm.seq), '[]'::jsonb)
            from course_modules cm
            left join course_module_passes cp
              on cp.module_id = cm.id and cp.enrollment_id = ce.id
           where cm.course_id = c.id),
        'modules_total', (select count(*) from course_modules where course_id = c.id),
        'modules_passed', (select count(*) from course_module_passes cp2
                            join course_modules cm2 on cm2.id = cp2.module_id
                           where cp2.enrollment_id = ce.id and cp2.passed
                             and cm2.course_id = c.id)
      ) as course
      from courses c
      left join course_enrollments ce on ce.course_id = c.id and ce.profile_id = target
     where c.is_active) sub;

  -- announcements that reach me (audience targeting from 077)
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', a.id, 'title', a.title, 'priority', a.priority,
           'created_at', a.created_at,
           'read', exists (select 1 from announcement_reads r
                            where r.announcement_id = a.id and r.profile_id = target))
           order by a.created_at desc), '[]'::jsonb),
         count(*) filter (where not exists (
           select 1 from announcement_reads r
            where r.announcement_id = a.id and r.profile_id = target))
    into v_ann, v_ann_unread
    from (select * from announcements a0
           where p.org_unit_id in (select org_unit_subtree(a0.org_unit_id))
             and (a0.network is null or a0.network = p.network)
             and (a0.audience = 'all'
                  or (a0.audience = 'leaders' and is_established(target))
                  or (a0.audience = 'intake' and not is_established(target)))
           order by a0.created_at desc limit 6) a;

  -- impact: only what the system recorded
  select jsonb_build_object(
           'women_reached', (select count(*) from beneficiaries where created_by = target),
           'referrals', (select count(*) from referrals where referrer_id = target),
           'meetings_attended', v_attended,
           'tasks_completed', (select count(*) from tasks
                                where assigned_to = target and status = 'completed'),
           'modules_completed', (select count(*) from course_module_passes cp
                                  join course_enrollments ce on ce.id = cp.enrollment_id
                                 where ce.profile_id = target and cp.passed),
           'months_of_service', v_months,
           'service_since', v_start)
    into v_impact;

  -- my referrals (latest 8, with the ladder position)
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', r.id, 'ref_no', r.ref_no, 'category', r.category,
           'reason', r.reason, 'status', r.status, 'created_at', r.created_at,
           'updated_at', r.updated_at)
           order by r.created_at desc), '[]'::jsonb)
    into v_referrals
    from (select * from referrals where referrer_id = target
           order by created_at desc limit 8) r;

  -- support tickets
  select jsonb_build_object(
           'open', count(*) filter (where status in ('open', 'in_progress', 'waiting_on_user')),
           'resolved', count(*) filter (where status in ('resolved', 'closed')),
           'recent', coalesce((select jsonb_agg(jsonb_build_object(
               'id', x.id, 'ticket_no', x.ticket_no, 'subject', x.subject,
               'status', x.status, 'created_at', x.created_at)
               order by x.created_at desc)
             from (select * from tickets where requester_id = target
                    order by created_at desc limit 4) x), '[]'::jsonb))
    into v_tickets
    from tickets where requester_id = target;

  -- achievements: derived from real events, newest first
  select coalesce(jsonb_agg(a order by (a->>'at') desc nulls last), '[]'::jsonb)
    into v_ach
    from (
      select jsonb_build_object('code', 'orientation', 'at', j.completed_at, 'title', null) as a
        from activation_journeys j
       where j.profile_id = target and j.status = 'completed' and j.completed_at is not null
      union all
      select jsonb_build_object('code', 'module', 'at', cp.completed_at, 'title', cm.title)
        from course_module_passes cp
        join course_enrollments ce on ce.id = cp.enrollment_id
        join course_modules cm on cm.id = cp.module_id
       where ce.profile_id = target and cp.passed
      union all
      select jsonb_build_object('code', 'certificate', 'at', ce.completed_at,
                                'title', c.title, 'cert_no', ce.cert_no)
        from course_enrollments ce join courses c on c.id = ce.course_id
       where ce.profile_id = target and ce.completed_at is not null
      union all
      select jsonb_build_object('code', 'appointed', 'at', ra.starts_at,
                                'title', ra.role::text, 'unit', ou.name)
        from role_assignments ra join org_units ou on ou.id = ra.org_unit_id
       where ra.profile_id = target and ra.ends_at is null
         and ra.role in ('country_rep', 'deputy_country_rep', 'state_coordinator',
                         'assistant_state_coordinator', 'district_coordinator',
                         'assistant_district_coordinator', 'chapter_lead',
                         'assistant_chapter_lead')
      union all
      select jsonb_build_object('code', 'service_' || m.n, 'at', v_start + (m.n || ' months')::interval,
                                'title', null)
        from (values (3), (6), (12), (24)) m(n)
       where v_months >= m.n
    ) s;

  -- activation journey (candidates)
  select jsonb_build_object(
           'status', j.status, 'started_at', j.started_at, 'due_at', j.due_at,
           'extended_until', j.extended_until, 'completed_at', j.completed_at,
           'day', least(14, greatest(1,
             floor(extract(epoch from (now() - j.started_at)) / 86400)::int + 1)))
    into v_journey
    from activation_journeys j where j.profile_id = target;

  -- leadership subtree (leaders only): every seat below mine, holder or vacant
  if jsonb_array_length(v_roles) > 0 then
    with recursive my_units as (
      select org_unit_id as id from role_assignments
       where profile_id = target and ends_at is null
      union all
      select ou.id from org_units ou join my_units mu on ou.parent_id = mu.id
    ),
    nodes as (
      select ou.id, ou.level, ou.name, ou.parent_id,
             ra.profile_id as holder_id, ra.role, ra.appointment_status,
             hp.first_name || ' ' || hp.last_name as holder_name,
             hp.last_seen_at
        from (select distinct id from my_units) u
        join org_units ou on ou.id = u.id
        left join lateral (
          select r.profile_id, r.role, r.appointment_status from role_assignments r
           where r.org_unit_id = ou.id and r.ends_at is null
             and r.role in ('country_rep', 'deputy_country_rep', 'state_coordinator',
                            'assistant_state_coordinator', 'district_coordinator',
                            'assistant_district_coordinator', 'chapter_lead',
                            'assistant_chapter_lead')
           order by case r.role when 'country_rep' then 1 when 'state_coordinator' then 2
                                when 'district_coordinator' then 3 when 'chapter_lead' then 4
                                else 5 end
           limit 1) ra on true
        left join profiles hp on hp.id = ra.profile_id
       where ou.id not in (select org_unit_id from role_assignments
                            where profile_id = target and ends_at is null)
    )
    select jsonb_build_object(
      'seats', (select count(*) from nodes),
      'filled', (select count(*) from nodes where holder_id is not null),
      'vacant', (select count(*) from nodes where holder_id is null),
      'members', (select count(*) from profiles m
                   where m.org_unit_id in (select administered_units_of(target))
                     and m.id <> target and m.merged_into is null
                     and m.status in ('approved', 'activated', 'in_training', 'active', 'reinstated')),
      'members_active', (select count(*) from profiles m
                          where m.org_unit_id in (select administered_units_of(target))
                            and m.id <> target and m.merged_into is null
                            and m.status = 'active'),
      'by_level', (select coalesce(jsonb_object_agg(lv, cnt), '{}'::jsonb)
                    from (select level::text as lv, count(*) as cnt from nodes group by level) q),
      'nodes', (select coalesce(jsonb_agg(jsonb_build_object(
                  'org_unit_id', n.id, 'level', n.level, 'location', n.name,
                  'parent_id', n.parent_id, 'role', n.role,
                  'holder_id', n.holder_id, 'holder_name', n.holder_name,
                  'appointment_status', n.appointment_status,
                  'last_seen', n.last_seen_at, 'vacant', n.holder_id is null)
                  order by n.level, n.name), '[]'::jsonb)
                 from (select * from nodes limit 400) n),
      'nodes_total', (select count(*) from nodes))
      into v_lead;
  else
    v_lead := null;
  end if;

  select exists (select 1 from staff s where s.profile_id = target and s.is_active)
    into v_is_staff;
  select count(*) into v_notices from member_notices
   where profile_id = target and read_at is null;
  select count(*) into v_msgs from staff_messages
   where recipient_id = target and read_at is null;

  v_completion := (
    (case when nullif(p.first_name, '') is not null then 1 else 0 end)
    + (case when nullif(p.last_name, '') is not null then 1 else 0 end)
    + (case when nullif(p.email, '') is not null then 1 else 0 end)
    + (case when nullif(p.phone, '') is not null then 1 else 0 end)
    + (case when nullif(p.country, '') is not null then 1 else 0 end)
    + (case when nullif(p.state_region, '') is not null then 1 else 0 end)
    + (case when nullif(p.lga, '') is not null then 1 else 0 end)
    + (case when nullif(p.role_applied, '') is not null then 1 else 0 end)
    + (case when p.birth_date is not null then 1 else 0 end)
    + (case when p.org_unit_id is not null then 1 else 0 end)
  ) * 10;

  -- documents the member may read (latest 8 in reachable folders)
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', d.id, 'name', d.name, 'path', d.path, 'mime', d.mime,
           'folder', f.name, 'created_at', d.created_at)
           order by d.created_at desc), '[]'::jsonb)
    into v_docs
    from (select d0.* from documents d0
           join doc_folders f0 on f0.id = d0.folder_id
          where not d0.archived
            and (f0.org_unit_id in (select unit_chain.id from unit_chain(p.org_unit_id))
                 or f0.org_unit_id in (select administered_units_of(target)))
          order by d0.created_at desc limit 8) d
    join doc_folders f on f.id = d.folder_id;

  return jsonb_build_object(
    'profile', jsonb_build_object(
      'id', p.id, 'first_name', p.first_name, 'last_name', p.last_name,
      'email', p.email, 'phone', p.phone, 'membership_no', p.membership_no,
      'network', p.network, 'status', p.status, 'country', p.country,
      'state_region', p.state_region, 'lga', p.lga,
      'role_applied', p.role_applied, 'is_leader', p.is_leader,
      'is_staff', v_is_staff, 'org_unit_id', p.org_unit_id,
      'preferred_locale', p.preferred_locale, 'birth_date', p.birth_date,
      'joined_at', p.created_at, 'last_seen_at', p.last_seen_at,
      'completion', v_completion,
      'established', is_established(target)),
    'chain', v_chain,
    'coordinator', v_coord,
    'reports_to', v_coord,
    'direct_reports', v_reports,
    'terms', v_terms,
    'country_iso', v_iso,
    'roles', v_roles,
    'tasks', v_tasks,
    'task_counts', v_tcounts,
    'meetings', v_meet,
    'learning', v_learn,
    'announcements', v_ann,
    'announcements_unread', v_ann_unread,
    'impact', v_impact,
    'referrals', v_referrals,
    'tickets', v_tickets,
    'achievements', v_ach,
    'journey', v_journey,
    'leadership', v_lead,
    'documents', v_docs,
    'notices_unread', v_notices,
    'messages_unread', v_msgs,
    'generated_at', now(),
    'viewing_as', (pid is not null));
end; $$;
revoke execute on function public.volunteer_home(uuid) from anon;

-- 6 ▸ STRUCTURE EXPLORER — every seat in scope, filled or vacant
-- p_net: 'WGMN' | 'WNNN' (required: seats are per network)
-- p_country / p_state: org unit ids to narrow (null = all)
-- p_level: org_level to list (null = all levels below country)
-- p_role: one position (null = every position of the level)
-- p_status: 'all' | 'vacant' | 'appointed' | 'acting' | 'pending'
-- p_activation: 'all' | 'completed' | 'in_progress' | 'incomplete' | 'none'
create or replace function public.structure_explorer(
  p_net text, p_country uuid default null, p_state uuid default null,
  p_level public.org_level default null, p_role public.role_code default null,
  p_status text default 'all', p_activation text default 'all', p_limit int default 600)
returns jsonb language plpgsql stable
security definer set search_path = public as $$
declare
  root_ids uuid[];
  net public.network_code := upper(coalesce(p_net, 'WGMN'))::public.network_code;
  rows_j jsonb; summary jsonb;
begin
  if not (is_case_hq() or exists (select 1 from administered_units())) then
    raise exception 'Not allowed';
  end if;
  -- scope roots: the chosen state, else the chosen country, else every country
  if p_state is not null then root_ids := array[p_state];
  elsif p_country is not null then root_ids := array[p_country];
  else select coalesce(array_agg(id), '{}') into root_ids from org_units where level = 'country';
  end if;

  with recursive units as (
    select ou.id, ou.parent_id, ou.level, ou.name, ou.country_iso
      from org_units ou where ou.id = any(root_ids)
    union all
    select ou.id, ou.parent_id, ou.level, ou.name, ou.country_iso
      from org_units ou join units u on ou.parent_id = u.id
  ),
  scoped as (
    -- non-HQ callers only see what they administer
    select u.* from units u
     where is_case_hq() or u.id in (select administered_units())
  ),
  seats as (
    select s.id as unit_id, s.name as unit, s.level, s.parent_id,
           pm.role, pm.rank, pm.seq,
           ra.profile_id as holder_id, ra.appointment_status, ra.starts_at,
           hp.first_name || ' ' || hp.last_name as holder_name,
           hp.membership_no, hp.last_seen_at,
           (select j.status::text from activation_journeys j where j.profile_id = ra.profile_id
             order by j.started_at desc limit 1) as activation
      from scoped s
      join position_master pm on pm.level = s.level
      left join lateral (
        select r.profile_id, r.appointment_status, r.starts_at
          from role_assignments r join profiles hp0 on hp0.id = r.profile_id
         where r.org_unit_id = s.id and r.role = pm.role and r.ends_at is null
           and hp0.network = net and hp0.merged_into is null
         order by r.starts_at limit 1) ra on true
      left join profiles hp on hp.id = ra.profile_id
     where s.level <> 'headquarters'
       and (p_level is null or s.level = p_level)
       and (p_role is null or pm.role = p_role)
  ),
  filtered as (
    select * from seats
     where (p_status = 'all'
            or (p_status = 'vacant' and holder_id is null)
            or (p_status in ('appointed', 'acting', 'pending')
                and holder_id is not null and appointment_status::text = p_status))
       and (p_activation = 'all'
            or (p_activation = 'none' and holder_id is not null and activation is null)
            or (holder_id is not null and activation = p_activation))
  )
  select jsonb_build_object(
    'seats', (select count(*) from seats),
    'filled', (select count(*) from seats where holder_id is not null),
    'vacant', (select count(*) from seats where holder_id is null),
    'acting', (select count(*) from seats where appointment_status = 'acting'),
    'pending', (select count(*) from seats where appointment_status = 'pending'),
    'shown', (select count(*) from filtered),
    'rows', (select coalesce(jsonb_agg(jsonb_build_object(
        'unit_id', f.unit_id, 'unit', f.unit, 'level', f.level,
        'parent', (select name from org_units where id = f.parent_id),
        'country', (select o.name from unit_chain(f.unit_id) c join org_units o on o.id = c.id
                     where c.level = 'country' limit 1),
        'role', f.role, 'rank', f.rank,
        'holder_id', f.holder_id, 'holder_name', f.holder_name,
        'membership_no', f.membership_no, 'appointment_status', f.appointment_status,
        'since', f.starts_at, 'last_seen', f.last_seen_at, 'activation', f.activation,
        'vacant', f.holder_id is null)
        order by f.level, f.unit, f.seq), '[]'::jsonb)
      from (select * from filtered order by level, unit, seq limit p_limit) f))
    into summary;
  return summary || jsonb_build_object('network', net, 'generated_at', now());
end; $$;
revoke execute on function public.structure_explorer(text, uuid, uuid, public.org_level, public.role_code, text, text, int) from anon;

insert into public.schema_migrations (version, name)
values (106, 'leadership_structure') on conflict (version) do nothing;
