-- ============================================================================
-- WDOS Migration 103 — Volunteer Dashboard data bundle, Referrals, HQ
-- account control, meeting reach (Phase 131)
--
-- What this adds, and why:
--   1. referrals — the "Make a Referral" door for every volunteer (category,
--      location, reason, consent) with the HQ-controlled status ladder
--      submitted → received → assigned → in_progress → closed. Safeguarding
--      concerns keep their own confidential channel (the cases module) and
--      are NOT a referral category on purpose.
--   2. meeting_reaches(m, pid) — the meetings table has carried an audience
--      column since 052 (unit / hq / wgmn_ng / wgmn_all / wnnn_ng / wnnn_all /
--      all) and the invite notices honour it, but the read policy still only
--      let a member see meetings of her own unit. Broadcast meetings were
--      invisible on #/meetings. The policy now uses the same audience rule
--      as the notice.
--   3. volunteer_home(pid) — ONE round trip that returns everything the
--      Volunteer Dashboard shows: profile + network chain + coordinator,
--      tasks, meetings, attendance, learning, announcements, impact,
--      support tickets, achievements, journey, leadership subtree (leaders),
--      unread counters. Called with no argument by the member herself;
--      called WITH a profile id by HQ for the read-only "View as" screen
--      (HQ-guarded server-side, so nobody else can look at another
--      member's dashboard).
--   4. HQ account control RPCs (all is_case_hq() guarded): hq_account_list,
--      hq_update_profile, hq_set_status (legal status walk),
--      hq_set_role / hq_end_roles, hq_link_directory. Creating the auth
--      login, resetting a password, suspending or deleting the auth user
--      is done by the admin-users Edge Function (service key never
--      reaches the browser); these RPCs cover the profile/role side.
--
-- Nothing here fabricates data: every number the dashboard shows is a
-- count of rows the system actually captured.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1 ▸ REFERRALS
-- ---------------------------------------------------------------------------
do $$ begin
  if not exists (select 1 from pg_type where typname = 'referral_status') then
    create type public.referral_status as enum
      ('submitted', 'received', 'assigned', 'in_progress', 'closed');
  end if;
end $$;

create sequence if not exists public.referral_no_seq;

create table if not exists public.referrals (
  id           uuid primary key default gen_random_uuid(),
  ref_no       text unique,
  referrer_id  uuid not null references public.profiles(id) on delete cascade
                 default auth.uid(),
  category     text not null check (category in
                 ('welfare', 'health', 'education', 'livelihood',
                  'community_need', 'leadership_candidate', 'other')),
  country      text,
  state_region text,
  lga          text,
  community    text check (community is null or char_length(community) <= 160),
  reason       text not null check (char_length(reason) between 3 and 300),
  details      text check (details is null or char_length(details) <= 3000),
  consent      boolean not null default false,
  status       public.referral_status not null default 'submitted',
  assigned_to  uuid references public.profiles(id) on delete set null,
  hq_notes     text check (hq_notes is null or char_length(hq_notes) <= 2000),
  org_unit_id  uuid references public.org_units(id) on delete set null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create index if not exists referrals_referrer_idx
  on public.referrals (referrer_id, created_at desc);
create index if not exists referrals_status_idx
  on public.referrals (status);

create or replace function public.referrals_assign_no()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.ref_no is null then
    new.ref_no := 'REF-' || to_char(now(), 'YYYY') || '-'
      || lpad(nextval('referral_no_seq')::text, 4, '0');
  end if;
  -- the referral inherits the referrer's home unit so scoped leaders can see it
  if new.org_unit_id is null then
    select org_unit_id into new.org_unit_id from profiles where id = new.referrer_id;
  end if;
  return new;
end; $$;

drop trigger if exists referrals_no on public.referrals;
create trigger referrals_no before insert on public.referrals
  for each row execute function public.referrals_assign_no();

drop trigger if exists referrals_touch on public.referrals;
create trigger referrals_touch before update on public.referrals
  for each row execute function public.touch_updated_at();

alter table public.referrals enable row level security;

drop policy if exists referrals_read on public.referrals;
create policy referrals_read on public.referrals
  for select to authenticated
  using (referrer_id = auth.uid()
         or public.is_case_hq()
         or (org_unit_id is not null
             and org_unit_id in (select public.administered_units())));

drop policy if exists referrals_insert on public.referrals;
create policy referrals_insert on public.referrals
  for insert to authenticated
  with check (referrer_id = auth.uid() and status = 'submitted'
              and assigned_to is null and consent = true);

-- Status changes only through this RPC (HQ, or a leader administering the
-- referral's unit). The referrer sees the ladder move; she cannot move it.
create or replace function public.set_referral_status(
  rid uuid, new_status public.referral_status,
  assignee uuid default null, notes text default null)
returns void language plpgsql security definer set search_path = public as $$
declare r referrals%rowtype;
begin
  select * into r from referrals where id = rid;
  if not found then raise exception 'No such referral'; end if;
  if not (is_case_hq()
          or (r.org_unit_id is not null
              and r.org_unit_id in (select administered_units()))) then
    raise exception 'Not allowed';
  end if;
  update referrals
     set status = new_status,
         assigned_to = coalesce(assignee, assigned_to),
         hq_notes = coalesce(notes, hq_notes)
   where id = rid;
end; $$;
revoke execute on function public.set_referral_status(uuid, public.referral_status, uuid, text) from anon;

-- ---------------------------------------------------------------------------
-- 2 ▸ MEETING REACH (audience-aware read policy)
-- ---------------------------------------------------------------------------
create or replace function public.meeting_reaches(m public.meetings, pid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from profiles p
     where p.id = pid and p.merged_into is null
       and (
         (m.audience = 'unit' and p.org_unit_id = m.org_unit_id)
         or (m.audience = 'hq'
             and exists (select 1 from staff s
                          where s.profile_id = p.id and s.is_active))
         or (m.audience in ('wgmn_ng', 'wgmn_all') and p.network = 'WGMN'
             and p.status in ('approved', 'activated', 'in_training', 'active', 'reinstated')
             and (m.audience = 'wgmn_all' or unit_in_country(p.org_unit_id, 'NG')))
         or (m.audience in ('wnnn_ng', 'wnnn_all') and p.network = 'WNNN'
             and p.status in ('approved', 'activated', 'in_training', 'active', 'reinstated')
             and (m.audience = 'wnnn_all' or unit_in_country(p.org_unit_id, 'NG')))
         or (m.audience = 'all'
             and (p.status in ('approved', 'activated', 'in_training', 'active', 'reinstated')
                  or exists (select 1 from staff s
                              where s.profile_id = p.id and s.is_active)))
       )
  );
$$;

drop policy if exists meetings_read on public.meetings;
create policy meetings_read on public.meetings
  for select to authenticated
  using (public.is_meeting_manager(meetings)
         or public.meeting_reaches(meetings, auth.uid()));

-- ---------------------------------------------------------------------------
-- 3 ▸ HELPERS: administered units OF a given person; unit chain upwards
-- ---------------------------------------------------------------------------
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
                    'district_coordinator', 'chapter_lead');
$$;

-- Own unit first (depth 0), then each parent up to HQ.
create or replace function public.unit_chain(uid uuid)
returns table (id uuid, level public.org_level, name text, depth int)
language sql stable security definer set search_path = public as $$
  with recursive up as (
    select o.id, o.parent_id, o.level, o.name, 0 as depth
      from org_units o where o.id = uid
    union all
    select o.id, o.parent_id, o.level, o.name, up.depth + 1
      from org_units o join up on o.id = up.parent_id
  )
  select up.id, up.level, up.name, up.depth from up;
$$;

-- ---------------------------------------------------------------------------
-- 4 ▸ VOLUNTEER HOME — the whole dashboard in one call
-- ---------------------------------------------------------------------------
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

  -- coordinator: nearest current leader on the chain who is not me
  select jsonb_build_object(
           'id', ra.profile_id,
           'name', hp.first_name || ' ' || hp.last_name,
           'role', ra.role,
           'role_applied', hp.role_applied,
           'unit', c.name, 'level', c.level)
    into v_coord
    from unit_chain(p.org_unit_id) c
    join role_assignments ra on ra.org_unit_id = c.id and ra.ends_at is null
     and ra.role in ('country_rep', 'deputy_country_rep',
                     'state_coordinator', 'assistant_state_coordinator',
                     'district_coordinator', 'chapter_lead')
    join profiles hp on hp.id = ra.profile_id
   where ra.profile_id <> target
   order by c.depth asc,
            case ra.role
              when 'chapter_lead' then 1 when 'district_coordinator' then 2
              when 'state_coordinator' then 3 when 'assistant_state_coordinator' then 4
              when 'country_rep' then 5 else 6 end
   limit 1;

  -- current seats
  select coalesce(jsonb_agg(jsonb_build_object(
           'role', ra.role, 'unit_id', ou.id, 'unit', ou.name,
           'level', ou.level, 'since', ra.starts_at)
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
                         'chapter_lead')
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
             ra.profile_id as holder_id, ra.role,
             hp.first_name || ' ' || hp.last_name as holder_name,
             hp.last_seen_at
        from (select distinct id from my_units) u
        join org_units ou on ou.id = u.id
        left join lateral (
          select r.profile_id, r.role from role_assignments r
           where r.org_unit_id = ou.id and r.ends_at is null
             and r.role in ('country_rep', 'deputy_country_rep', 'state_coordinator',
                            'assistant_state_coordinator', 'district_coordinator',
                            'chapter_lead')
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

-- ---------------------------------------------------------------------------
-- 5 ▸ HQ ACCOUNT CONTROL
-- ---------------------------------------------------------------------------

-- Every account HQ can act on: real profiles with their auth state, plus
-- directory leaders who have no login yet (so HQ can create one).
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
      select jsonb_build_object(
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
                    'role', ra.role, 'unit_id', ou.id, 'unit', ou.name, 'level', ou.level)
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
      union all
      select jsonb_build_object(
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
             or lower(d.role_applied) like '%' || needle || '%')
      limit lim
    ) sub);
end; $$;
revoke execute on function public.hq_account_list(text, int) from anon;

-- Edit a member's details. Only the listed keys are honoured.
create or replace function public.hq_update_profile(pid uuid, patch jsonb)
returns void language plpgsql
security definer set search_path = public as $$
begin
  if not is_case_hq() then raise exception 'HQ only'; end if;
  if not exists (select 1 from profiles where id = pid) then
    raise exception 'No such member';
  end if;
  update profiles set
    first_name = coalesce(nullif(patch->>'first_name', ''), first_name),
    last_name = coalesce(nullif(patch->>'last_name', ''), last_name),
    phone = case when patch ? 'phone' then nullif(patch->>'phone', '') else phone end,
    network = coalesce((nullif(patch->>'network', ''))::public.network_code, network),
    country = case when patch ? 'country' then nullif(patch->>'country', '') else country end,
    state_region = case when patch ? 'state_region' then nullif(patch->>'state_region', '') else state_region end,
    lga = case when patch ? 'lga' then nullif(patch->>'lga', '') else lga end,
    role_applied = case when patch ? 'role_applied' then nullif(patch->>'role_applied', '') else role_applied end,
    is_leader = coalesce((patch->>'is_leader')::boolean, is_leader),
    org_unit_id = case when patch ? 'org_unit_id' then nullif(patch->>'org_unit_id', '')::uuid else org_unit_id end,
    preferred_locale = coalesce(nullif(patch->>'preferred_locale', ''), preferred_locale),
    birth_date = case when patch ? 'birth_date' then nullif(patch->>'birth_date', '')::date else birth_date end,
    membership_no = case when patch ? 'membership_no' then nullif(patch->>'membership_no', '') else membership_no end
  where id = pid;
end; $$;
revoke execute on function public.hq_update_profile(uuid, jsonb) from anon;

-- Move a member to a status by walking only legal transitions (the
-- profiles_check_transition trigger keeps the state machine honest).
create or replace function public.hq_set_status(pid uuid, target_status public.member_status)
returns text language plpgsql
security definer set search_path = public as $$
declare
  cur public.member_status;
  allv public.member_status[] := enum_range(null::public.member_status);
  -- breadth-first search over the enum for a legal path
  frontier public.member_status[];
  visited public.member_status[];
  prev jsonb := '{}'::jsonb;
  s public.member_status; n public.member_status;
  path public.member_status[] := '{}';
  reached boolean := false;
  steps int := 0;
begin
  if not is_case_hq() then raise exception 'HQ only'; end if;
  select status into cur from profiles where id = pid;
  if cur is null then raise exception 'No such member'; end if;
  if cur = target_status then return 'unchanged'; end if;

  frontier := array[cur]; visited := array[cur];
  while array_length(frontier, 1) > 0 and not reached loop
    s := frontier[1];
    frontier := frontier[2:];
    foreach n in array allv loop
      -- exit-type statuses are legal TARGETS but never intermediates, so a
      -- new member walks applicant → under_review → approved → activated →
      -- active and never picks up a false 'removed' step in her history
      if not (n = any(visited)) and valid_status_transition(s, n)
         and (n = target_status
              or n not in ('removed', 'resigned', 'suspended', 'alumni')) then
        visited := visited || n;
        prev := prev || jsonb_build_object(n::text, s::text);
        if n = target_status then reached := true; exit; end if;
        frontier := frontier || n;
      end if;
    end loop;
  end loop;
  if not reached then
    raise exception 'No legal path from % to %', cur, target_status;
  end if;

  -- rebuild the path backwards from the target
  n := target_status;
  while n <> cur loop
    path := n || path;
    n := (prev->>n::text)::public.member_status;
  end loop;

  foreach n in array path loop
    update profiles set status = n where id = pid;
    steps := steps + 1;
  end loop;
  return steps::text || ' step(s)';
end; $$;
revoke execute on function public.hq_set_status(uuid, public.member_status) from anon;

-- Seat a member: ends every current leadership seat, then assigns the new
-- one. HQ roles (super_admin / executive_director / hq_team) are only
-- assignable at the headquarters unit.
create or replace function public.hq_set_role(pid uuid, new_role public.role_code, unit uuid)
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
  insert into role_assignments (profile_id, role, org_unit_id, assigned_by)
  values (pid, new_role, unit, auth.uid());
  if new_role in ('country_rep', 'deputy_country_rep', 'state_coordinator',
                  'assistant_state_coordinator', 'district_coordinator', 'chapter_lead') then
    update profiles set is_leader = true where id = pid;
  end if;
end; $$;
revoke execute on function public.hq_set_role(uuid, public.role_code, uuid) from anon;

create or replace function public.hq_end_roles(pid uuid)
returns int language plpgsql
security definer set search_path = public as $$
declare n int;
begin
  if not is_case_hq() then raise exception 'HQ only'; end if;
  if pid = auth.uid() then raise exception 'You cannot remove your own seat'; end if;
  update role_assignments set ends_at = now()
   where profile_id = pid and ends_at is null;
  get diagnostics n = row_count;
  return n;
end; $$;
revoke execute on function public.hq_end_roles(uuid) from anon;

-- After the admin-users function creates a login for a directory leader:
-- link the directory row, carry her ID, role and country onto the profile.
create or replace function public.hq_link_directory(pid uuid, code text)
returns void language plpgsql
security definer set search_path = public as $$
declare d leader_directory%rowtype;
begin
  if not is_case_hq() then raise exception 'HQ only'; end if;
  select * into d from leader_directory where upper(member_code) = upper(trim(code));
  if not found then raise exception 'No such directory code'; end if;
  update leader_directory set claimed_profile = pid where member_code = d.member_code;
  update profiles set
    membership_no = coalesce(membership_no, d.member_code),
    role_applied = coalesce(role_applied, d.role_applied),
    country = coalesce(country, d.country),
    state_region = coalesce(state_region, d.state),
    phone = coalesce(phone, d.phone),
    is_leader = true
  where id = pid;
end; $$;
revoke execute on function public.hq_link_directory(uuid, text) from anon;


-- ---------------------------------------------------------------------------
-- 5b ▸ MESSAGE COORDINATOR — a member may write to the leaders seated on her
--      own line (her chapter lead, LGA coordinator, state coordinator,
--      country representative), and they may reply. Nothing else changes:
--      members still cannot message other members, and the HQ/staff wall
--      stays as it was.
-- ---------------------------------------------------------------------------
create or replace function public.coordinator_line(a uuid, b uuid)
returns boolean language sql stable
security definer set search_path = public as $$
  -- b leads a unit on a's chain
  select exists (
    select 1 from profiles pa
    join unit_chain(pa.org_unit_id) c on true
    join role_assignments rb on rb.org_unit_id = c.id and rb.ends_at is null
     and rb.role in ('country_rep', 'deputy_country_rep', 'state_coordinator',
                     'assistant_state_coordinator', 'district_coordinator', 'chapter_lead')
    where pa.id = a and rb.profile_id = b and a <> b)
  or exists (
  -- a leads a unit on b's chain (the reply direction)
    select 1 from profiles pb
    join unit_chain(pb.org_unit_id) c on true
    join role_assignments ra on ra.org_unit_id = c.id and ra.ends_at is null
     and ra.role in ('country_rep', 'deputy_country_rep', 'state_coordinator',
                     'assistant_state_coordinator', 'district_coordinator', 'chapter_lead')
    where pb.id = b and ra.profile_id = a and a <> b);
$$;

create or replace function public.may_send_message(sender uuid, recipient uuid)
returns boolean
language sql stable
security definer set search_path = public as $$
  select sender = auth.uid()
     and sender <> recipient
     and (
       public.is_active_staff(sender)
       or public.is_case_hq()
       or public.can_receive_direct(recipient)
       or public.same_leadership_team(sender, recipient)
       or public.coordinator_line(sender, recipient)
     );
$$;

drop policy if exists staff_msg_send on public.staff_messages;
create policy staff_msg_send on public.staff_messages
  for insert to authenticated
  with check (
    sender_id = auth.uid()
    and (
      public.is_active_staff(auth.uid())
      or public.is_case_hq()
      or public.can_receive_direct(recipient_id)
      or public.same_leadership_team(auth.uid(), recipient_id)
      or public.coordinator_line(auth.uid(), recipient_id)
    )
  );

-- ---------------------------------------------------------------------------
-- 6 ▸ bookkeeping
-- ---------------------------------------------------------------------------
insert into public.schema_migrations (version, name)
values (103, 'volunteer_home_hq_control') on conflict (version) do nothing;
