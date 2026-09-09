-- ============================================================================
-- WDOS Migration 042 — Automation Hotfix (Phase 45.1)
--
-- 1. FIXES 'Run now' crashing: the task follow-up rule referenced due_at,
--    but the tasks table's deadline column is due_on (a date). PostgreSQL
--    only checks such references at execution time, so the migration
--    installed fine and the crash waited for the first run.
-- 2. NARROWS alert recipients: since every staff member now holds hq_team
--    (the Phase 44 tasks fix), digests and UAT-blocker alerts aimed at
--    that role would have gone to ALL staff. They now go only to the
--    Super Administrator and Executive Director.
-- ============================================================================

create or replace function public.run_daily_content()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  n_day int := 0; n_nudge int := 0; n_bday int := 0;
  n_week int := 0; n_month int := 0; n_task int := 0;
  grace int := 1;
  wk int; mo int; wk_title text; mo_title text; mo_focus text;
  nudge_days int := 3;
begin
  select threshold_days into nudge_days
    from automation_rules where code = 'member_nudge';
  nudge_days := coalesce(nudge_days, 3);

  -- 4a ▸ today's activation message for every in-progress journey
  if exists (select 1 from automation_rules
              where code = 'daily_journey' and is_active) then
    with cur as (
      select j.id as jid, j.profile_id,
             least(14, greatest(1,
               floor(extract(epoch from (now() - j.started_at)) / 86400)::int + 1))
               as day_no
        from activation_journeys j
       where j.status = 'in_progress'
    )
    insert into member_notices (profile_id, kind, title, body, meta)
    select c.profile_id, 'journey_day',
           'Day ' || c.day_no || ' — ' || d.title,
           d.intro,
           jsonb_build_object('day', c.day_no, 'title', d.title)
      from cur c
      join activation_days d on d.day = c.day_no and d.is_active
     where not exists (
       select 1 from member_notices mn
        where mn.profile_id = c.profile_id
          and mn.kind = 'journey_day'
          and (mn.meta->>'day')::int = c.day_no);
    get diagnostics n_day = row_count;
    update automation_rules set last_run_at = now(), last_matches = n_day
     where code = 'daily_journey';
  end if;

  -- 4b ▸ gentle nudge when a journey has gone quiet
  if exists (select 1 from automation_rules
              where code = 'member_nudge' and is_active) then
    insert into member_notices (profile_id, kind, title, body, meta)
    select j.profile_id, 'nudge',
           'We miss you on your journey',
           'Your activation journey is waiting for you. A few minutes today keeps you on track — your network is cheering for you.',
           jsonb_build_object('journey', j.id)
      from activation_journeys j
     where j.status = 'in_progress'
       and coalesce((select max(r.submitted_at)
                       from activation_item_responses r
                      where r.journey_id = j.id), j.started_at)
           < now() - make_interval(days => nudge_days)
       and not exists (
         select 1 from member_notices mn
          where mn.profile_id = j.profile_id and mn.kind = 'nudge'
            and mn.created_at > now() - make_interval(days => nudge_days));
    get diagnostics n_nudge = row_count;
    update automation_rules set last_run_at = now(), last_matches = n_nudge
     where code = 'member_nudge';
  end if;

  -- 4c ▸ birthday wishes
  if exists (select 1 from automation_rules
              where code = 'birthday_wishes' and is_active) then
    insert into member_notices (profile_id, kind, title, body)
    select p.id, 'birthday',
           'Happy birthday, ' || p.first_name || '!',
           'The whole WODDI family celebrates you today. Thank you for the light you bring — may this new year of your life overflow with grace, strength and joy.'
      from profiles p
     where p.birth_date is not null
       and to_char(p.birth_date, 'MM-DD') = to_char(now(), 'MM-DD')
       and not exists (
         select 1 from member_notices mn
          where mn.profile_id = p.id and mn.kind = 'birthday'
            and mn.created_at > now() - interval '300 days');
    get diagnostics n_bday = row_count;
    update automation_rules set last_run_at = now(), last_matches = n_bday
     where code = 'birthday_wishes';
  end if;

  -- 4d ▸ weekly inspiration (engagement library, current ISO week)
  wk := least(52, greatest(1, extract(week from now())::int));
  select title into wk_title from engagement_content
   where kind = 'weekly' and period = wk and is_active;
  if wk_title is not null and exists (select 1 from automation_rules
              where code = 'weekly_motivation' and is_active) then
    insert into member_notices (profile_id, kind, title, body, meta)
    select p.id, 'weekly', wk_title, '',
           jsonb_build_object('week', wk)
      from profiles p
     where p.status in ('activated','in_training','active','reinstated')
       and not exists (
         select 1 from member_notices mn
          where mn.profile_id = p.id and mn.kind = 'weekly'
            and (mn.meta->>'week')::int = wk
            and mn.created_at > now() - interval '10 days');
    get diagnostics n_week = row_count;
    update automation_rules set last_run_at = now(), last_matches = n_week
     where code = 'weekly_motivation';
  end if;

  -- 4e ▸ monthly message (engagement library, current month)
  mo := extract(month from now())::int;
  select title, focus into mo_title, mo_focus from engagement_content
   where kind = 'monthly' and period = mo and is_active;
  if mo_title is not null and exists (select 1 from automation_rules
              where code = 'monthly_motivation' and is_active) then
    insert into member_notices (profile_id, kind, title, body, meta)
    select p.id, 'monthly', mo_title, coalesce(mo_focus, ''),
           jsonb_build_object('month', mo)
      from profiles p
     where p.status in ('activated','in_training','active','reinstated')
       and not exists (
         select 1 from member_notices mn
          where mn.profile_id = p.id and mn.kind = 'monthly'
            and (mn.meta->>'month')::int = mo
            and mn.created_at > now() - interval '35 days');
    get diagnostics n_month = row_count;
    update automation_rules set last_run_at = now(), last_matches = n_month
     where code = 'monthly_motivation';
  end if;

  -- 4f ▸ overdue-task follow-ups (Phase 45)
  if exists (select 1 from automation_rules
              where code = 'task_followup' and is_active) then
    select threshold_days into grace
      from automation_rules where code = 'task_followup';
    grace := coalesce(grace, 1);
    insert into member_notices (profile_id, kind, title, body, meta)
    select tk.assigned_to, 'nudge',
           'Follow-up: "' || left(tk.title, 80) || '" is overdue',
           'This task passed its deadline and is not yet completed. Please update its status, add a note explaining the delay, or ask for support.',
           jsonb_build_object('task', tk.id)
      from tasks tk
     where tk.status in ('not_started','in_progress')
       and tk.due_on is not null
       and tk.due_on < current_date - (grace - 1)
       and tk.assigned_to is not null
       and not exists (
         select 1 from member_notices mn
          where mn.profile_id = tk.assigned_to and mn.kind = 'nudge'
            and mn.meta->>'task' = tk.id::text
            and mn.created_at > now() - interval '2 days');
    get diagnostics n_task = row_count;
    update automation_rules set last_run_at = now(), last_matches = n_task
     where code = 'task_followup';
  end if;

  return jsonb_build_object(
    'journey_day', n_day, 'nudge', n_nudge, 'birthday', n_bday,
    'weekly', n_week, 'monthly', n_month, 'task_followup', n_task);
end; $$;


create or replace function public.run_automations()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  r public.automation_rules;
  n int;
  msg text;
  sys_sender uuid;
  hq uuid[];
  sent int;
  results jsonb := '[]'::jsonb;
  content jsonb;
  mail_on boolean;
  mailed int := 0;
  hq_p record;
begin
  select array_agg(distinct ra.profile_id) into hq
    from role_assignments ra
   where ra.role in ('super_admin','executive_director');
  if hq is null or array_length(hq, 1) is null then
    return jsonb_build_object('error', 'no HQ recipients');
  end if;
  sys_sender := hq[1];
  select coalesce((value #>> '{}')::boolean, false) into mail_on
    from org_settings where key = 'email_enabled';

  for r in select * from automation_rules
            where is_active
              and code in ('stale_application','stale_volunteer',
                           'quiet_journey','journey_deadline',
                           'inactive_member') loop
    n := 0; msg := null; sent := 0;

    if r.code = 'stale_application' then
      select count(*) into n from applications
       where status in ('submitted','under_review')
         and created_at < now() - make_interval(days => r.threshold_days);
      msg := '[Automation] ' || n || ' membership application(s) have waited more than '
          || r.threshold_days || ' day(s) for review. Open Recruitment to act.';

    elsif r.code = 'stale_volunteer' then
      select count(*) into n from volunteer_applications
       where decided_at is null
         and created_at < now() - make_interval(days => r.threshold_days);
      msg := '[Automation] ' || n || ' Institute volunteer submission(s) have waited more than '
          || r.threshold_days || ' day(s) in the queue. Open Recruitment.';

    elsif r.code = 'quiet_journey' then
      select count(*) into n from activation_journeys j
       where j.status = 'in_progress'
         and coalesce(
               (select max(rr.submitted_at) from activation_item_responses rr
                 where rr.journey_id = j.id),
               j.started_at)
             < now() - make_interval(days => r.threshold_days);
      msg := '[Automation] ' || n || ' activation journey(s) have had no activity for '
          || r.threshold_days || '+ day(s). A friendly check-in may help.';

    elsif r.code = 'inactive_member' then
      select count(*) into n from profiles p
       where p.merged_into is null
         and p.status in ('activated','in_training','active','reinstated')
         and coalesce(p.last_seen_at, p.created_at)
             < now() - make_interval(days => r.threshold_days)
         and not exists (select 1 from staff s
                          where s.profile_id = p.id and s.is_active);
      msg := '[Automation] ' || n || ' active member(s) have not opened WDOS in '
          || r.threshold_days || '+ day(s). Consider a re-engagement message.';

    elsif r.code = 'journey_deadline' then
      select count(*) into n from activation_journeys j
       where j.status = 'in_progress'
         and coalesce(j.extended_until, j.due_at)
             < now() + make_interval(days => r.threshold_days);
      msg := '[Automation] ' || n || ' activation journey(s) reach their deadline within '
          || r.threshold_days || ' day(s) and are not complete.';
    end if;

    if n > 0
       and not exists (select 1 from automation_events e
                        where e.rule_code = r.code
                          and e.fired_at > now() - interval '20 hours') then
      insert into staff_messages (sender_id, recipient_id, body)
      select sys_sender, p, msg from unnest(hq) as p
       where p <> sys_sender;
      get diagnostics sent = row_count;
      insert into automation_events (rule_code, matches, notified)
      values (r.code, n, sent);

      if mail_on then
        for hq_p in select email, first_name from profiles
                     where id = any(hq) and email is not null loop
          perform send_email(hq_p.email, hq_p.first_name,
            'WDOS alert: attention needed', email_wrap('WDOS automation', msg));
        end loop;
      end if;
    end if;

    update automation_rules
       set last_run_at = now(), last_matches = n
     where code = r.code;

    results := results || jsonb_build_object(
      'code', r.code, 'matches', n, 'notified', sent);
  end loop;

  content := run_daily_content();
  mailed := email_recent_notices();

  return jsonb_build_object('ran_at', now(), 'rules', results,
                            'content', content, 'emailed', mailed);
end; $$;

create or replace function public.uat_blocker_alert()
returns trigger
language plpgsql security definer set search_path = public as $$
declare hq uuid[]; sys uuid; nm text;
begin
  if new.severity <> 'blocker' then return new; end if;
  select array_agg(distinct ra.profile_id) into hq
    from role_assignments ra
   where ra.role in ('super_admin','executive_director');
  if hq is null then return new; end if;
  sys := hq[1];
  select first_name || ' ' || last_name into nm
    from profiles where id = new.reporter_id;
  insert into staff_messages (sender_id, recipient_id, body)
  select sys, p,
    '[UAT BLOCKER] ' || coalesce(nm,'A tester') || ' reports at "'
    || new.location_text || '": ' || left(new.observed, 500)
    || ' — open Test Feedback to triage.'
    from unnest(hq) as p where p <> sys;
  return new;
end; $$;


insert into public.schema_migrations (version, name)
values (42, 'automation_hotfix') on conflict (version) do nothing;
