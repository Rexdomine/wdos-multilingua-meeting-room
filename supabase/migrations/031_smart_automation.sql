-- ============================================================================
-- WDOS Migration 031 — Smart Automation (Phase 35)
--
-- IF-rules that watch the pipeline so HQ doesn't have to:
--   • applications sitting unreviewed too long
--   • Institute volunteer submissions waiting in the queue
--   • activation journeys gone quiet
--   • journeys approaching their deadline unfinished
--
-- When a rule fires, HQ executives get ONE digest message in their normal
-- staff inbox (so the existing bell, previews, sound, and browser
-- notifications all light up — no new channel to check). Every firing is
-- logged. A daily 06:00 UTC run is scheduled via pg_cron where available;
-- HQ can also press "Run now" in Settings → Automation.
--
-- automation_insights() powers the analytics card: live funnel numbers
-- plus rule-based recommendations (returned as codes + values; the app
-- translates them, so recommendations speak the user's language).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. RULES (HQ-editable thresholds and on/off)
-- ---------------------------------------------------------------------------
create table public.automation_rules (
  code           text primary key,
  threshold_days int  not null check (threshold_days between 1 and 60),
  is_active      boolean not null default true,
  last_run_at    timestamptz,
  last_matches   int not null default 0
);

alter table public.automation_rules enable row level security;
create policy auto_rules_read on public.automation_rules
  for select to authenticated using (public.is_case_hq());
create policy auto_rules_write on public.automation_rules
  for update to authenticated
  using (public.is_case_hq()) with check (public.is_case_hq());

insert into public.automation_rules (code, threshold_days) values
  ('stale_application', 7),
  ('stale_volunteer',   5),
  ('quiet_journey',     4),
  ('journey_deadline',  3)
on conflict (code) do nothing;

-- ---------------------------------------------------------------------------
-- 2. EVENT LOG (every firing, auditable)
-- ---------------------------------------------------------------------------
create table public.automation_events (
  id        uuid primary key default gen_random_uuid(),
  rule_code text not null references public.automation_rules(code),
  fired_at  timestamptz not null default now(),
  matches   int not null,
  notified  int not null default 0
);

create index automation_events_time_idx
  on public.automation_events (fired_at desc);

alter table public.automation_events enable row level security;
create policy auto_events_read on public.automation_events
  for select to authenticated using (public.is_case_hq());

-- ---------------------------------------------------------------------------
-- 3. THE ENGINE
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
begin
  -- HQ executives who receive digests (also used as the "system" sender).
  select array_agg(distinct ra.profile_id) into hq
    from role_assignments ra
   where ra.role in ('super_admin','executive_director','hq_team');
  if hq is null or array_length(hq, 1) is null then
    return jsonb_build_object('error', 'no HQ recipients');
  end if;
  sys_sender := hq[1];

  for r in select * from automation_rules where is_active loop
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

  return jsonb_build_object('ran_at', now(), 'rules', results);
end; $$;

-- HQ can trigger it from the app; the definer body does the privileged work.
revoke all on function public.run_automations() from public;
grant execute on function public.run_automations() to authenticated;

create or replace function public.run_automations_guarded()
returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not is_case_hq() then
    raise exception 'Only HQ can run automations';
  end if;
  return run_automations();
end; $$;

-- ---------------------------------------------------------------------------
-- 4. INSIGHTS + RECOMMENDATIONS (codes; the app translates)
-- ---------------------------------------------------------------------------
create or replace function public.automation_insights()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  apps jsonb; vols jsonb; jn jsonb; recs jsonb := '[]'::jsonb;
  waiting int; vol_waiting int; overdue int; quiet int;
  done int; inprog int; incompl int; avg_days numeric; score_avg numeric;
begin
  if not is_case_hq() then
    raise exception 'Only HQ can view automation insights';
  end if;

  select jsonb_object_agg(status, n) into apps from (
    select status::text, count(*) n from applications group by status) s;

  select count(*) into waiting from applications
   where status in ('submitted','under_review');

  select count(*) into vol_waiting from volunteer_applications
   where decided_at is null;
  vols := jsonb_build_object('waiting', vol_waiting);

  select count(*) filter (where status = 'completed'),
         count(*) filter (where status = 'in_progress'),
         count(*) filter (where status = 'incomplete')
    into done, inprog, incompl
    from activation_journeys;

  select count(*) into overdue from activation_journeys
   where status = 'in_progress'
     and coalesce(extended_until, due_at) < now();

  select count(*) into quiet from activation_journeys j
   where j.status = 'in_progress'
     and coalesce((select max(rr.submitted_at)
                     from activation_item_responses rr
                    where rr.journey_id = j.id), j.started_at)
         < now() - interval '4 days';

  select round(avg(extract(epoch from (decided_at - created_at)) / 86400), 1)
    into avg_days
    from applications where decided_at is not null;

  select round(avg(r.score) * 100.0 / nullif(max(i.points), 0), 0)
    into score_avg
    from activation_item_responses r
    join activation_items i on i.id = r.item_id
   where i.kind in ('mcq','tf');

  jn := jsonb_build_object(
    'in_progress', inprog, 'completed', done, 'incomplete', incompl,
    'overdue', overdue, 'quiet', quiet);

  if waiting > 0 then
    recs := recs || jsonb_build_object('code','review_backlog','n',waiting);
  end if;
  if vol_waiting > 0 then
    recs := recs || jsonb_build_object('code','volunteer_backlog','n',vol_waiting);
  end if;
  if overdue > 0 then
    recs := recs || jsonb_build_object('code','journeys_overdue','n',overdue);
  end if;
  if quiet > 0 then
    recs := recs || jsonb_build_object('code','journeys_quiet','n',quiet);
  end if;
  if avg_days is not null and avg_days > 7 then
    recs := recs || jsonb_build_object('code','slow_decisions','n',avg_days);
  end if;
  if score_avg is not null and score_avg < 60 then
    recs := recs || jsonb_build_object('code','low_quiz_scores','n',score_avg);
  end if;
  if recs = '[]'::jsonb then
    recs := recs || jsonb_build_object('code','all_clear','n',0);
  end if;

  return jsonb_build_object(
    'applications', coalesce(apps, '{}'::jsonb),
    'apps_waiting', waiting,
    'avg_decision_days', avg_days,
    'volunteers', vols,
    'journeys', jn,
    'quiz_avg_pct', score_avg,
    'recommendations', recs);
end; $$;

-- ---------------------------------------------------------------------------
-- 5. DAILY SCHEDULE (pg_cron where available; harmless where not)
-- ---------------------------------------------------------------------------
do $$
begin
  begin
    create extension if not exists pg_cron;
  exception when others then null;
  end;
  begin
    perform cron.unschedule('wdos-automations');
  exception when others then null;
  end;
  begin
    perform cron.schedule('wdos-automations', '0 6 * * *',
                          'select public.run_automations()');
  exception when others then
    raise notice 'pg_cron unavailable — automations run via Settings → Run now';
  end;
end $$;

insert into public.schema_migrations (version, name)
values (31, 'smart_automation') on conflict (version) do nothing;
