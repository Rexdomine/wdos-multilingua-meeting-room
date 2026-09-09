-- ============================================================================
-- WDOS Migration 043 — The Wall v2 + Central-Dashboard Tasks (Phase 47)
--
-- The distinct wall between VOLUNTEER LEADERSHIP and HQ OPERATIONS, made
-- real end-to-end:
--   1. am_i_staff() lets the app know who is HQ staff, so the volunteer
--      mobile world (My WODDI: journey, learning, volunteer profile) is
--      closed to staff — they belong in the central dashboard.
--   2. Staff no longer receive the volunteer weekly/monthly inspiration
--      streams (birthdays and task follow-ups still apply to them).
--   3. hq_team loses the Reports module — leadership analytics stay with
--      executives; staff keep Tasks, Meetings, Documents, Library,
--      Announcements, Helpdesk.
--   4. FIXES central-dashboard task assignment: the assignee search could
--      only see active field members — staff were structurally invisible,
--      so HQ could not assign staff their tasks. search_staff_assignees()
--      adds active staff to the picker (HQ callers only), and the app also
--      now includes newly-approved leaders.
-- ============================================================================

create or replace function public.am_i_staff()
returns boolean language sql security definer set search_path = public as $$
  select public.is_active_staff(auth.uid());
$$;
grant execute on function public.am_i_staff() to authenticated;

delete from public.module_access where role = 'hq_team' and module = 'reports';

create or replace function public.search_staff_assignees(s text)
returns table (id uuid, first_name text, last_name text, email text,
               position_title text)
language plpgsql security definer set search_path = public as $$
begin
  if not is_case_hq() then return; end if;
  return query
  select p.id, p.first_name, p.last_name, p.email, st.position_title
    from staff st join profiles p on p.id = st.profile_id
   where st.is_active and p.merged_into is null
     and (s is null or s = '' or
          p.first_name ilike '%' || s || '%' or
          p.last_name  ilike '%' || s || '%' or
          p.email      ilike '%' || s || '%' or
          st.position_title ilike '%' || s || '%')
   order by p.last_name limit 10;
end; $$;

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
       and not exists (select 1 from staff st
                        where st.profile_id = p.id and st.is_active)
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
       and not exists (select 1 from staff st
                        where st.profile_id = p.id and st.is_active)
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



insert into public.schema_migrations (version, name)
values (43, 'wall_v2_tasks') on conflict (version) do nothing;
