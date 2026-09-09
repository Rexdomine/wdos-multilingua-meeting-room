-- ============================================================================
-- WDOS Migration 111 — Appointment acceptance + tracked onboarding (Phase 135b)
--   1. Every leadership seat records whether the leader has ACCEPTED it in
--      WDOS (Acceptance & Commitment Declaration), when, and if declined,
--      why. Seats created before this migration are marked accepted at
--      their start date (those leaders are already serving). New seats
--      start as "acceptance pending" until the leader accepts.
--   2. Onboarding steps are a master list; each leader ticks them; HQ sees
--      done/total per leader and can list who has not finished.
-- ============================================================================

alter table public.role_assignments add column if not exists accepted_at timestamptz;
alter table public.role_assignments add column if not exists declined_at timestamptz;
alter table public.role_assignments add column if not exists decline_reason text;
update public.role_assignments set accepted_at = coalesce(accepted_at, starts_at)
 where ends_at is null and accepted_at is null and declined_at is null
   and starts_at < now() - interval '1 hour';

-- The leader accepts her own current seat(s)
create or replace function public.accept_appointment()
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  update role_assignments
     set accepted_at = now(),
         appointment_status = case when appointment_status = 'pending' then 'appointed' else appointment_status end
   where profile_id = auth.uid() and ends_at is null and accepted_at is null and declined_at is null
     and role in (select role from position_master);
  get diagnostics n = row_count;
  if n > 0 then
    insert into member_notices (profile_id, kind, title, body, meta)
    select ra.profile_id, 'appointment', 'Appointment accepted',
           'You accepted your appointment as ' || ra.role::text || ' at ' || ou.name || '.',
           jsonb_build_object('href', '#/my/leadership')
      from role_assignments ra join org_units ou on ou.id = ra.org_unit_id
     where ra.profile_id = auth.uid() and ra.ends_at is null and ra.accepted_at >= now() - interval '5 seconds';
  end if;
  return n;
end; $$;
revoke execute on function public.accept_appointment() from anon;

-- The leader declines: the seat ends (becomes vacant), HQ is told why
create or replace function public.decline_appointment(reason text)
returns int language plpgsql security definer set search_path = public as $$
declare n int; r record;
begin
  if coalesce(trim(reason), '') = '' then raise exception 'A reason is required'; end if;
  for r in select ra.id, ra.role, ou.name as unit from role_assignments ra join org_units ou on ou.id = ra.org_unit_id
            where ra.profile_id = auth.uid() and ra.ends_at is null and ra.accepted_at is null
              and ra.role in (select role from position_master) loop
    update role_assignments set declined_at = now(), decline_reason = left(reason, 1000), ends_at = now() where id = r.id;
    insert into member_notices (profile_id, kind, title, body, meta)
    select s.profile_id, 'appointment', 'Appointment declined: ' || r.unit,
           (select first_name || ' ' || last_name from profiles where id = auth.uid()) || ' declined ' || r.role::text || ' at ' || r.unit || ': ' || left(reason, 300),
           jsonb_build_object('href', '#/structure')
      from role_assignments s where s.ends_at is null and s.role in ('super_admin', 'executive_director', 'hq_team');
  end loop;
  get diagnostics n = row_count;
  return n;
end; $$;
revoke execute on function public.decline_appointment(text) from anon;

-- ---------------------------------------------------------------------------
-- Onboarding checklist
-- ---------------------------------------------------------------------------
create table if not exists public.onboarding_steps (
  code     text primary key,
  seq      smallint not null,
  title    text not null,
  detail   text,
  href     text,                 -- where the step is done or read in WDOS
  required boolean not null default true,
  active   boolean not null default true
);
alter table public.onboarding_steps enable row level security;
drop policy if exists onboarding_steps_read on public.onboarding_steps;
create policy onboarding_steps_read on public.onboarding_steps for select to authenticated using (true);
drop policy if exists onboarding_steps_write on public.onboarding_steps;
create policy onboarding_steps_write on public.onboarding_steps for all to authenticated
  using (public.is_case_hq()) with check (public.is_case_hq());

insert into public.onboarding_steps (code, seq, title, detail, href) values
  ('role', 1, 'Read my role description and authority limits', 'Leadership Handbook, section for your position', '#/my/documents'),
  ('reporting_line', 2, 'Confirm my reporting line', 'Who I report to and who reports to me', '#/my/network'),
  ('pack', 3, 'Read the Volunteer Leadership Pack', 'Templates & Tools and Documents', '#/my/templates'),
  ('conduct', 4, 'Acknowledge the Code of Conduct', null, '/content/code-of-conduct.html'),
  ('safeguarding', 5, 'Acknowledge the safeguarding requirements', null, '#/my/safeguarding'),
  ('confidentiality', 6, 'Acknowledge the confidentiality requirements', null, '/content/volunteer-agreement.html'),
  ('coi', 7, 'Complete the Conflict-of-Interest Declaration', 'State any conflict or confirm none', '#/my/settings'),
  ('protocol', 8, 'Read the communication protocol', null, '#/my/documents'),
  ('templates', 9, 'Open the reporting templates', null, '#/reporting'),
  ('plan', 10, 'Draft my first 30/60/90-day plan', 'Use the Country Strategy Planning template', '#/my/templates')
on conflict (code) do nothing;

create table if not exists public.onboarding_progress (
  profile_id uuid not null references public.profiles(id) on delete cascade,
  step_code  text not null references public.onboarding_steps(code) on delete cascade,
  done_at    timestamptz not null default now(),
  note       text,
  primary key (profile_id, step_code)
);
alter table public.onboarding_progress enable row level security;
drop policy if exists onboarding_progress_read on public.onboarding_progress;
create policy onboarding_progress_read on public.onboarding_progress for select to authenticated
  using (profile_id = auth.uid() or public.is_case_hq()
         or profile_id in (select p.id from profiles p where p.org_unit_id in (select public.administered_units())));
drop policy if exists onboarding_progress_write on public.onboarding_progress;
create policy onboarding_progress_write on public.onboarding_progress for insert to authenticated
  with check (profile_id = auth.uid());
drop policy if exists onboarding_progress_del on public.onboarding_progress;
create policy onboarding_progress_del on public.onboarding_progress for delete to authenticated
  using (profile_id = auth.uid());

-- done / total for one person (leader herself, HQ or her supervisor)
create or replace function public.onboarding_status(pid uuid default null)
returns jsonb language sql stable security definer set search_path = public as $$
  with target as (select coalesce(pid, auth.uid()) as id),
  steps as (select * from onboarding_steps where active order by seq)
  select jsonb_build_object(
    'total', (select count(*) from steps where required),
    'done', (select count(*) from onboarding_progress op join steps s on s.code = op.step_code
              where op.profile_id = (select id from target) and s.required),
    'steps', (select coalesce(jsonb_agg(jsonb_build_object('code', s.code, 'seq', s.seq, 'title', s.title, 'detail', s.detail,
                'href', s.href, 'required', s.required,
                'done_at', (select op.done_at from onboarding_progress op where op.profile_id = (select id from target) and op.step_code = s.code))
                order by s.seq), '[]'::jsonb) from steps s));
$$;

-- HQ / supervisor overview: every seated leader with done/total
create or replace function public.onboarding_overview()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_object_agg(x.profile_id, jsonb_build_object('done', x.done, 'total', x.total)), '{}'::jsonb)
  from (
    select ra.profile_id,
           (select count(*) from onboarding_steps where active and required) as total,
           (select count(*) from onboarding_progress op join onboarding_steps s on s.code = op.step_code
             where op.profile_id = ra.profile_id and s.required and s.active) as done
      from role_assignments ra
     where ra.ends_at is null and ra.role in (select role from position_master)
       and (is_case_hq() or ra.org_unit_id in (select administered_units()))
     group by ra.profile_id) x;
$$;
revoke execute on function public.onboarding_overview() from anon;

-- redefines volunteer_home (roles carry accepted_at / declined_at)
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
           'appointment_status', ra.appointment_status,
           'accepted_at', ra.accepted_at, 'declined_at', ra.declined_at)
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

-- redefines hq_account_list (roles carry appointment_status / accepted_at / declined_at)
create or replace function public.hq_account_list(q text default '', lim int default 300)
returns jsonb language plpgsql stable
security definer set search_path = public as $$
declare needle text := lower(coalesce(q, ''));
begin
  if not is_case_hq() then raise exception 'HQ only'; end if;
  return (
    select coalesce(jsonb_agg(rw order by
             (rw->>'has_login') desc, (rw->>'is_leader') desc, rw->>'name'), '[]'::jsonb)
    from (
      (select jsonb_build_object(
        'id', p.id, 'name', p.first_name || ' ' || p.last_name,
        'first_name', p.first_name, 'last_name', p.last_name,
        'email', p.email, 'phone', p.phone, 'membership_no', p.membership_no,
        'network', p.network, 'status', p.status, 'role_applied', p.role_applied,
        'country', p.country, 'state_region', p.state_region, 'lga', p.lga,
        'is_leader', p.is_leader,
        'is_staff', exists (select 1 from staff s where s.profile_id = p.id and s.is_active),
        'last_seen_at', p.last_seen_at,
        'last_sign_in_at', u.last_sign_in_at,
        'email_confirmed', u.email_confirmed_at is not null,
        'banned', (u.banned_until is not null and u.banned_until > now()),
        'created_at', p.created_at,
        'has_login', true,
        'roles', (select coalesce(jsonb_agg(jsonb_build_object(
                    'role', ra.role, 'unit_id', ou.id, 'unit', ou.name, 'level', ou.level,
                    'appointment_status', ra.appointment_status,
                    'accepted_at', ra.accepted_at, 'declined_at', ra.declined_at)
                    order by ra.starts_at), '[]'::jsonb)
                   from role_assignments ra join org_units ou on ou.id = ra.org_unit_id
                  where ra.profile_id = p.id and ra.ends_at is null)
      ) as rw
      from profiles p
      left join auth.users u on u.id = p.id
      where p.merged_into is null
        and (needle = '' or lower(p.first_name || ' ' || p.last_name) like '%' || needle || '%'
             or lower(p.email) like '%' || needle || '%'
             or lower(coalesce(p.membership_no, '')) like '%' || needle || '%'
             or lower(coalesce(p.country, '')) like '%' || needle || '%'
             or lower(coalesce(p.role_applied, '')) like '%' || needle || '%')
      order by p.is_leader desc, p.last_name, p.first_name
      limit lim)
      union all
      (select jsonb_build_object(
        'id', null, 'name', d.first_name || ' ' || d.last_name,
        'first_name', d.first_name, 'last_name', d.last_name,
        'email', d.email, 'phone', d.phone, 'membership_no', d.member_code,
        'network', case when d.member_code ~ '^(CL|DCL|CA|PM)' then 'WNNN' else 'WGMN' end,
        'status', null, 'role_applied', d.role_applied,
        'country', d.country, 'state_region', d.state, 'lga', null,
        'is_leader', true, 'is_staff', false,
        'last_seen_at', null, 'last_sign_in_at', null,
        'email_confirmed', false, 'banned', false,
        'created_at', d.sent_at, 'has_login', false, 'roles', '[]'::jsonb
      ) as rw
      from leader_directory d
      where d.claimed_profile is null
        and not exists (select 1 from profiles p2
                         where p2.merged_into is null
                           and (upper(p2.membership_no) = upper(d.member_code)
                                or (d.email is not null and lower(p2.email) = lower(d.email))))
        and (needle = '' or lower(d.first_name || ' ' || d.last_name) like '%' || needle || '%'
             or lower(coalesce(d.email, '')) like '%' || needle || '%'
             or lower(d.member_code) like '%' || needle || '%'
             or lower(d.country) like '%' || needle || '%'
             or lower(d.role_applied) like '%' || needle || '%'))
    ) sub);
end; $$;
revoke execute on function public.hq_account_list(text, int) from anon;

insert into public.schema_migrations (version, name)
values (111, 'appointment_acceptance_onboarding') on conflict (version) do nothing;
