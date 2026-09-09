-- ============================================================================
-- WDOS Migration 032 — Journey Content Engine (Phase 36)
--
-- The automation grows a heart. A new personal notice feed reaches EVERY
-- member (volunteers included — staff messages never could), and the daily
-- engine now walks each person through her journey:
--   • Day-by-day activation messages: each morning an in-progress volunteer
--     receives that day's message from the seeded curriculum.
--   • Gentle nudges when a journey has gone quiet.
--   • Birthday wishes on the person's day (birth_date is self-service).
--   • Weekly inspiration + monthly message from the engagement library.
-- Each stream is a rule in Settings → Automation: HQ can switch any off.
-- All notices are localisable: the app renders known kinds in the reader's
-- language using meta; the stored title/body is the English fallback.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Birthday (self-service; guard trigger already limits sensitive columns)
-- ---------------------------------------------------------------------------
alter table public.profiles add column if not exists birth_date date;

-- ---------------------------------------------------------------------------
-- 2. Personal notices — the member-facing inbox
-- ---------------------------------------------------------------------------
create table public.member_notices (
  id         uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  kind       text not null,   -- journey_day | nudge | birthday | weekly | monthly | manual
  title      text not null,
  body       text not null default '',
  meta       jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  read_at    timestamptz
);

create index member_notices_inbox_idx
  on public.member_notices (profile_id, created_at desc);

alter table public.member_notices enable row level security;
create policy notices_own_read on public.member_notices
  for select to authenticated using (profile_id = auth.uid());
create policy notices_own_mark on public.member_notices
  for update to authenticated
  using (profile_id = auth.uid()) with check (profile_id = auth.uid());
-- inserts come only from the definer engine below

do $$
begin
  alter publication supabase_realtime add table public.member_notices;
exception when others then null;
end $$;

-- ---------------------------------------------------------------------------
-- 3. New content rules (visible + tunable in Settings → Automation)
-- ---------------------------------------------------------------------------
insert into public.automation_rules (code, threshold_days) values
  ('daily_journey',      1),
  ('member_nudge',       3),
  ('birthday_wishes',    1),
  ('weekly_motivation',  1),
  ('monthly_motivation', 1)
on conflict (code) do nothing;

-- ---------------------------------------------------------------------------
-- 4. The content engine
-- ---------------------------------------------------------------------------
create or replace function public.run_daily_content()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  n_day int := 0; n_nudge int := 0; n_bday int := 0;
  n_week int := 0; n_month int := 0;
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

  return jsonb_build_object(
    'journey_day', n_day, 'nudge', n_nudge, 'birthday', n_bday,
    'weekly', n_week, 'monthly', n_month);
end; $$;

-- ---------------------------------------------------------------------------
-- 5. Fold the content engine into the daily run
-- ---------------------------------------------------------------------------
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
begin
  select array_agg(distinct ra.profile_id) into hq
    from role_assignments ra
   where ra.role in ('super_admin','executive_director','hq_team');
  if hq is null or array_length(hq, 1) is null then
    return jsonb_build_object('error', 'no HQ recipients');
  end if;
  sys_sender := hq[1];

  for r in select * from automation_rules
            where is_active
              and code in ('stale_application','stale_volunteer',
                           'quiet_journey','journey_deadline') loop
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
          || r.threshold_days || ' day(s) in the queue. Open Recruitment → Volunteers.';

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
    end if;

    update automation_rules
       set last_run_at = now(), last_matches = n
     where code = r.code;

    results := results || jsonb_build_object(
      'code', r.code, 'matches', n, 'notified', sent);
  end loop;

  content := run_daily_content();

  return jsonb_build_object('ran_at', now(), 'rules', results,
                            'content', content);
end; $$;

insert into public.schema_migrations (version, name)
values (32, 'journey_content_engine') on conflict (version) do nothing;
