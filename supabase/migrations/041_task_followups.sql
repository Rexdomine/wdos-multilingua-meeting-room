-- ============================================================================
-- WDOS Migration 041 — Automatic Task Follow-ups (Phase 45)
--
-- The smart cron takes over follow-ups — free, automatic, no clicks:
-- every morning, each unfinished task past its deadline sends its owner a
-- personal follow-up notice (bell, sound, browser popup, and email when
-- enabled), asking them to update the status or add a note explaining the
-- delay — which the master CRM sees on the task as always. New rule in
-- Settings ('Overdue task follow-ups'): on/off + how many days overdue
-- before the first nudge. Deduped per task per 2 days. 'Run now' triggers
-- it immediately.
-- ============================================================================

insert into public.automation_rules (code, threshold_days)
values ('task_followup', 1)
on conflict (code) do nothing;

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
       and tk.due_at is not null
       and tk.due_at < now() - make_interval(days => grace - 1)
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

insert into public.schema_migrations (version, name)
values (41, 'task_followups') on conflict (version) do nothing;
