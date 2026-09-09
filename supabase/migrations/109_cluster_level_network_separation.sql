-- ============================================================================
-- WDOS Migration 109 — Community Cluster level, network separation, report fix
-- Requires 108 (run separately, before this file).
--   1. position_master: the ten positions of the approved hierarchy
--      (CR, DCR, State Coordinator, Assistant State Coordinator, LGA
--      Coordinator, Assistant LGA Coordinator, Community Cluster Coordinator,
--      Assistant Community Cluster Coordinator, Chapter Lead, Assistant
--      Chapter Lead) with level, rank and order.
--   2. level_terms gains the Community Cluster term per country.
--   3. administered_units / administered_units_of / hq_set_role / report_unit_for
--      read the position master list, so new positions never need code.
--   4. volunteer_home (redefined): the leadership tree, reports-to and direct
--      reports are filtered by the member's NETWORK: a WGMN leader never sees
--      a WNNN seat holder and vice versa. -- redefines volunteer_home
--   5. report_open: an explicit null on_date now means today (the bug seen
--      6 Sep: "null value in column period_start"). -- redefines report_open
-- ============================================================================

insert into public.position_master (role, level, rank, seq) values
  ('country_rep', 'country', 1, 1),
  ('deputy_country_rep', 'country', 2, 2),
  ('state_coordinator', 'state_region', 1, 3),
  ('assistant_state_coordinator', 'state_region', 2, 4),
  ('district_coordinator', 'district_lga', 1, 5),
  ('assistant_district_coordinator', 'district_lga', 2, 6),
  ('cluster_coordinator', 'community_cluster', 1, 7),
  ('assistant_cluster_coordinator', 'community_cluster', 2, 8),
  ('chapter_lead', 'chapter', 1, 9),
  ('assistant_chapter_lead', 'chapter', 2, 10)
on conflict (role) do update set level = excluded.level, rank = excluded.rank, seq = excluded.seq;

alter table public.level_terms add column if not exists term_cluster text not null default 'Community Cluster';
update public.level_terms set term_chapter = 'Chapter' where term_chapter in ('Community Cluster / Ward', 'Ward / Community Cluster');
update public.level_terms set term_cluster = 'Community Cluster / Ward' where country_iso = 'NG';

-- redefines level_terms_for
create or replace function public.level_terms_for(iso text)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'country', t.term_country, 'state_region', t.term_state,
    'district_lga', t.term_district, 'community_cluster', t.term_cluster,
    'chapter', t.term_chapter,
    'country_iso', coalesce(nullif(t.country_iso, ''), null))
  from (
    select * from level_terms
     where country_iso in (upper(coalesce(iso, '')), '')
     order by (country_iso <> '') desc
     limit 1) t;
$$;

-- redefines administered_units
create or replace function public.administered_units()
returns setof uuid
language sql stable security definer set search_path = public as $$
  select distinct s.id
  from role_assignments ra
  cross join lateral org_unit_subtree(ra.org_unit_id) as s(id)
  where ra.profile_id = auth.uid()
    and ra.ends_at is null
    and (ra.role in ('super_admin','executive_director','hq_team')
         or ra.role in (select role from position_master));
$$;

-- redefines administered_units_of
create or replace function public.administered_units_of(pid uuid)
returns setof uuid
language sql stable security definer set search_path = public as $$
  select distinct s.id
  from role_assignments ra
  cross join lateral org_unit_subtree(ra.org_unit_id) as s(id)
  where ra.profile_id = pid
    and ra.ends_at is null
    and (ra.role in ('super_admin', 'executive_director', 'hq_team')
         or ra.role in (select role from position_master));
$$;

-- redefines coordinator_line
create or replace function public.coordinator_line(a uuid, b uuid)
returns boolean language sql stable
security definer set search_path = public as $$
  select exists (
    select 1 from profiles pa
    join unit_chain(pa.org_unit_id) c on true
    join role_assignments rb on rb.org_unit_id = c.id and rb.ends_at is null
     and rb.role in (select role from position_master)
    join profiles pb on pb.id = rb.profile_id and pb.network = pa.network
    where pa.id = a and rb.profile_id = b and a <> b)
  or exists (
    select 1 from profiles pb
    join unit_chain(pb.org_unit_id) c on true
    join role_assignments ra on ra.org_unit_id = c.id and ra.ends_at is null
     and ra.role in (select role from position_master)
    join profiles pa on pa.id = ra.profile_id and pa.network = pb.network
    where pb.id = b and ra.profile_id = a and a <> b);
$$;

-- redefines report_open
create or replace function public.report_open(tpl text, on_date date default null,
                                              p_meeting uuid default null, p_event uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  d date := coalesce(on_date, current_date);
  ru record; pr record; r report_instances%rowtype; net public.network_code;
  t report_templates%rowtype;
begin
  if me is null then raise exception 'Not signed in'; end if;
  select * into t from report_templates where code = tpl and active;
  if not found then raise exception 'Unknown report template'; end if;
  select * into ru from report_unit_for(me);
  if ru.org_unit_id is null then raise exception 'You do not hold a leadership seat; reports belong to a leadership unit'; end if;
  select network into net from profiles where id = me;
  select * into pr from report_period(tpl, d);
  if pr.period_start is null then raise exception 'Could not compute the reporting period'; end if;

  if t.cadence in ('monthly', 'weekly') then
    select * into r from report_instances
     where template = tpl and org_unit_id = ru.org_unit_id and network = net
       and period_start = pr.period_start and is_current limit 1;
  end if;
  if r.id is null then
    insert into report_instances (template, org_unit_id, owner_id, network, period_start, period_end, due_on,
                                  linked_meeting, linked_event)
    values (tpl, ru.org_unit_id,
            coalesce((select r2.profile_id from role_assignments r2 join position_master p2 on p2.role = r2.role
                       join profiles hp2 on hp2.id = r2.profile_id and hp2.network = net
                       where r2.org_unit_id = ru.org_unit_id and r2.ends_at is null and p2.rank = 1
                       order by r2.starts_at limit 1), me),
            net, pr.period_start, pr.period_end, pr.due_on, p_meeting, p_event)
    returning * into r;
  end if;
  if r.status in ('draft', 'returned') then
    update report_instances set snapshot = report_snapshot(r.org_unit_id, r.period_start, r.period_end, r.network)
     where id = r.id returning * into r;
  end if;
  return to_jsonb(r) || jsonb_build_object(
    'template_def', to_jsonb(t),
    'can_submit', (ru.can_submit and r.status in ('draft', 'returned')),
    'my_role', ru.role,
    'contributions', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'name', p.first_name || ' ' || p.last_name,
                        'note', c.note, 'evidence', c.evidence, 'at', c.at) order by c.at), '[]'::jsonb)
                       from report_contributions c join profiles p on p.id = c.profile_id where c.report_id = r.id),
    'reviews', (select coalesce(jsonb_agg(jsonb_build_object('action', v.action, 'note', v.note, 'version', v.version, 'at', v.at,
                        'by', p.first_name || ' ' || p.last_name) order by v.at), '[]'::jsonb)
                 from report_reviews v join profiles p on p.id = v.actor_id where v.report_id = r.id));
end; $$;
revoke execute on function public.report_open(text, date, uuid, uuid) from anon;

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
     and ra.role in (select role from position_master)
   order by (select seq from position_master pm2 where pm2.role = ra.role)
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
     and ra.role in (select role from position_master)
    join profiles hp on hp.id = ra.profile_id
   where ra.profile_id <> target
     and (hp.network = p.network or hp.network is null)
   order by c.depth asc, (select rank from position_master pm1 where pm1.role = ra.role)
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
       and ra.role in (select role from position_master where role <> 'country_rep')
       and not (ou.id = v_seat_unit and (select rank from position_master pm3 where pm3.role = ra.role) = 1);
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
         and ra.role in (select role from position_master)
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
           join profiles hq0 on hq0.id = r.profile_id and hq0.network = p.network
           where r.org_unit_id = ou.id and r.ends_at is null
             and r.role in (select role from position_master)
           order by (select rank from position_master pm0 where pm0.role = r.role), r.starts_at
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

insert into public.schema_migrations (version, name)
values (109, 'cluster_level_network_separation') on conflict (version) do nothing;
