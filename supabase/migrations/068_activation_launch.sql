-- ============================================================================
-- WDOS Migration 068 — 14-Day Activation Launch (Phase 89)
-- Launch day: Monday 3 August 2026.
--
-- 1. CONTENT, AS DIRECTED:
--    · Day 1 — the Founder's Welcome now plays the uploaded video from
--      inside WDOS (video:/content/founder-message.mp4), no Drive link.
--    · Day 4 task 2 — rewritten to the warm-and-professional scenario.
--    · Day 5 — "Upload any document" becomes "Upload your CV" (real upload
--      button); the four retired tasks are replaced by: Learn module,
--      dashboard tasks check, message to HQ, explore Ask WODDI.
--    · Day 7 task 1 — "What has been your biggest lesson so far in your
--      journey as a volunteer?"
-- 2. THE SYSTEM TICKS, NOT THE VOLUNTEER. journey_events records page
--    visits; journey_signals() tells the app which tasks the system can
--    already see are done (CV uploaded, module passed, message to HQ sent,
--    pages explored). Day 5 becomes fully system-verified.
-- 3. CV UPLOADS: private member-cvs bucket, one row per member, HQ can read.
-- 4. PASS / FAIL / AUTO-APPROVAL. eval_activation() applies the standing
--    Day-14 rule (both gates + every required item + score ≥ 50%).
--    Passing finalises the journey and advances the profile automatically
--    (approved → activated; applicant/under_review → approved). Past-due
--    journeys are marked incomplete by a daily sweep. Accountability is
--    explicit either way.
-- 5. activation_report() — the master-dashboard table: name, Volunteer ID,
--    position applied, country/state/LGA, day reached, progress, score,
--    gates, verdict, CV, last seen.
-- 6. activation_kickoff() — run once today: aligns every in-progress
--    journey to start TODAY with the full 14 days, then emails and
--    notifies every cohort member that the activation is on.
-- 7. Emails now carry the WODDI logo.
-- ============================================================================

-- 1 ▸ content ---------------------------------------------------------------
-- Day 1: founder video, played locally, system-ticked when watched through.
update public.activation_items
   set prompt = 'Watch the Founder''s Welcome Message. '
             || 'video:/content/founder-message.mp4'
 where day = 1 and prompt ilike '%Founder%Welcome%';

-- Day 4, task 2: the exact scenario, warm and professional.
update public.activation_items
   set prompt = 'Respond in a warm and professional manner to a member who '
             || 'says: "You people never respond. This is why nobody takes '
             || 'this group serious."'
 where day = 4 and seq = 2;

-- Day 5: the new hands-on list (system-verified, see §3).
update public.activation_items
   set options = '["Find & open the latest announcement",
                   "Download the handbook",
                   "Upload your CV",
                   "Go to the Learn section and complete a course module",
                   "Go to your dashboard and check if any tasks are available",
                   "Write a message to the HQ",
                   "Go to Ask WODDI on your homepage and explore"]'::jsonb
 where day = 5 and seq = 1 and kind = 'checklist';

-- Old numeric answers for the day-5 checklist point at retired rows — clear
-- them so nobody carries a tick for a task that no longer exists.
delete from public.activation_item_responses
 where item_id in (select id from public.activation_items
                    where day = 5 and seq = 1 and kind = 'checklist');

-- Day 7, task 1: the reflection question, as directed.
update public.activation_items
   set prompt = 'What has been your biggest lesson so far in your journey '
             || 'as a volunteer?'
 where day = 7 and seq = 1;

-- 2 ▸ journey events: what the system has seen this person do --------------
create table if not exists public.journey_events (
  profile_id uuid not null references public.profiles(id) on delete cascade,
  code       text not null,
  at         timestamptz not null default now(),
  primary key (profile_id, code)
);
alter table public.journey_events enable row level security;
create policy journey_events_own_read on public.journey_events
  for select to authenticated using (profile_id = auth.uid()
                                     or public.is_case_hq());

create or replace function public.log_journey_event(p_code text)
returns void language plpgsql
security definer set search_path = public as $$
begin
  if p_code not in ('announcement_opened', 'handbook_downloaded',
                    'tasks_checked', 'ask_explored') then
    return;                       -- unknown codes are ignored, not stored
  end if;
  if not exists (select 1 from activation_journeys j
                  where j.profile_id = auth.uid()
                    and j.status = 'in_progress') then
    return;                       -- only journeys in progress collect events
  end if;
  insert into journey_events (profile_id, code) values (auth.uid(), p_code)
  on conflict do nothing;
end; $$;
grant execute on function public.log_journey_event(text) to authenticated;
revoke execute on function public.log_journey_event(text) from anon, public;

-- 3 ▸ CV uploads ------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('member-cvs', 'member-cvs', false)
on conflict (id) do nothing;

drop policy if exists member_cvs_own_write on storage.objects;
create policy member_cvs_own_write on storage.objects
  for insert to authenticated
  with check (bucket_id = 'member-cvs'
              and name like auth.uid()::text || '/%');
drop policy if exists member_cvs_read on storage.objects;
create policy member_cvs_read on storage.objects
  for select to authenticated
  using (bucket_id = 'member-cvs'
         and (name like auth.uid()::text || '/%' or public.is_case_hq()));

create table if not exists public.member_cvs (
  profile_id  uuid primary key references public.profiles(id)
                on delete cascade,
  path        text not null,
  name        text not null,
  uploaded_at timestamptz not null default now()
);
alter table public.member_cvs enable row level security;
create policy member_cvs_row_read on public.member_cvs
  for select to authenticated using (profile_id = auth.uid()
                                     or public.is_case_hq());

create or replace function public.record_cv_upload(p_path text, p_name text)
returns void language plpgsql
security definer set search_path = public as $$
begin
  if p_path is null or p_path not like auth.uid()::text || '/%' then
    raise exception 'Invalid CV path';
  end if;
  insert into member_cvs (profile_id, path, name)
  values (auth.uid(), p_path, left(coalesce(p_name, 'cv'), 200))
  on conflict (profile_id) do update
    set path = excluded.path, name = excluded.name, uploaded_at = now();
end; $$;
grant execute on function public.record_cv_upload(text, text) to authenticated;
revoke execute on function public.record_cv_upload(text, text)
  from anon, public;

-- What the system can already verify for the calling member.
create or replace function public.journey_signals()
returns jsonb language sql stable
security definer set search_path = public as $$
  select jsonb_build_object(
    'cv',           exists (select 1 from member_cvs
                             where profile_id = auth.uid()),
    'module',       exists (select 1 from course_module_passes cmp
                             join course_enrollments ce
                               on ce.id = cmp.enrollment_id
                            where ce.profile_id = auth.uid()),
    'msg_hq',       exists (select 1 from staff_messages
                             where sender_id = auth.uid()),
    'announcement', exists (select 1 from journey_events
                             where profile_id = auth.uid()
                               and code = 'announcement_opened'),
    'handbook',     exists (select 1 from journey_events
                             where profile_id = auth.uid()
                               and code = 'handbook_downloaded'),
    'tasks',        exists (select 1 from journey_events
                             where profile_id = auth.uid()
                               and code = 'tasks_checked'),
    'ask',          exists (select 1 from journey_events
                             where profile_id = auth.uid()
                               and code = 'ask_explored'));
$$;
grant execute on function public.journey_signals() to authenticated;
revoke execute on function public.journey_signals() from anon, public;

-- 4 ▸ pass / fail / auto-approval -------------------------------------------
-- The standing Day-14 rule, computable for any journey without an auth
-- context (trigger, sweep, report). Not callable by clients.
create or replace function public.eval_activation(jid uuid)
returns table (all_submitted boolean, pct int,
               gate6 boolean, gate13 boolean, passed boolean)
language plpgsql stable
security definer set search_path = public as $$
declare
  possible int; earned int; v_pct int;
  req_total int; req_done int;
  g6 boolean; g13 boolean;
begin
  select coalesce(sum(points), 0) into possible
    from activation_items where kind in ('mcq','tf','checklist')
     and points > 0;
  select coalesce(sum(r.score), 0) into earned
    from activation_item_responses r
    join activation_items i on i.id = r.item_id
   where r.journey_id = jid and i.kind in ('mcq','tf','checklist');
  v_pct := case when possible > 0
                then round(earned * 100.0 / possible) else 0 end;

  select count(*) into req_total
    from activation_items where is_required;
  select count(*) into req_done
    from activation_item_responses r
    join activation_items i on i.id = r.item_id
   where r.journey_id = jid and i.is_required;

  select bool_and(
      exists (select 1 from activation_item_responses r
              where r.journey_id = jid and r.item_id = i.id
                and (i.kind not in ('mcq','tf','checklist')
                     or r.is_correct)))
    into g6
    from activation_items i where i.day = 6 and i.is_required;
  g6 := coalesce(g6, false);

  select bool_and(coalesce(r.is_correct, false)) into g13
    from activation_items i
    left join activation_item_responses r
      on r.journey_id = jid and r.item_id = i.id
   where i.day = 13 and i.is_required;
  g13 := coalesce(g13, false);

  return query select req_done >= req_total, v_pct, g6, g13,
    (g6 and g13 and req_done >= req_total and v_pct >= 50);
end; $$;
revoke execute on function public.eval_activation(uuid)
  from anon, authenticated, public;

-- Walk a profile's status forward through the legal transitions.
create or replace function public.advance_status_on_pass(pid uuid)
returns void language plpgsql
security definer set search_path = public as $$
declare cur public.member_status;
begin
  select status into cur from profiles where id = pid;
  perform set_config('wdos.reason',
    '14-day activation passed (system evaluation)', true);
  if cur = 'applicant' then
    update profiles set status = 'under_review' where id = pid;
    cur := 'under_review';
  end if;
  if cur = 'under_review' then
    update profiles set status = 'approved' where id = pid;
    cur := 'approved';
  end if;
  if cur = 'approved' then
    update profiles set status = 'activated' where id = pid;
  end if;
end; $$;

-- Finalise a journey the moment it satisfies the rule (idempotent).
create or replace function public.try_finalize_activation(jid uuid)
returns void language plpgsql
security definer set search_path = public as $$
declare j activation_journeys; ev record;
begin
  select * into j from activation_journeys where id = jid for update;
  if j.id is null or j.status <> 'in_progress' then return; end if;
  select * into ev from eval_activation(jid);
  if not ev.passed then return; end if;
  update activation_journeys
     set status = 'completed', completed_at = now()
   where id = jid;
  perform advance_status_on_pass(j.profile_id);
  insert into member_notices (profile_id, kind, title, body, meta)
  values (j.profile_id, 'journey_day',
    'Congratulations — you passed your 14-day activation!',
    'The system has evaluated your journey: passed. Your account has been '
    || 'advanced automatically and your courses are open in the Learn '
    || 'section. Welcome aboard, and thank you for serving.',
    jsonb_build_object('activation', 'passed'));
end; $$;

create or replace function public.activation_response_check()
returns trigger language plpgsql
security definer set search_path = public as $$
begin
  perform try_finalize_activation(new.journey_id);
  return new;
end; $$;

drop trigger if exists activation_finalize_trg
  on public.activation_item_responses;
create trigger activation_finalize_trg
  after insert or update on public.activation_item_responses
  for each row execute function public.activation_response_check();

-- Daily sweep: finalise late passers, mark the expired incomplete.
create or replace function public.activation_daily_sweep()
returns jsonb language plpgsql
security definer set search_path = public as $$
declare r record; n_done int := 0; n_expired int := 0;
begin
  for r in select id from activation_journeys where status = 'in_progress'
  loop
    perform try_finalize_activation(r.id);
  end loop;
  get diagnostics n_done = row_count;

  perform set_config('wdos.reason',
    '14-day activation window elapsed without completion', true);
  update activation_journeys
     set status = 'incomplete'
   where status = 'in_progress'
     and now() > coalesce(extended_until, due_at);
  get diagnostics n_expired = row_count;
  return jsonb_build_object('checked', n_done, 'marked_incomplete', n_expired);
end; $$;

do $$
begin
  begin
    create extension if not exists pg_cron;
    if exists (select 1 from pg_extension where extname = 'pg_cron') then
      begin
        perform cron.unschedule('wdos-activation-sweep');
      exception when others then null;
      end;
      perform cron.schedule('wdos-activation-sweep', '15 6 * * *',
        $cron$select public.activation_daily_sweep()$cron$);
    end if;
  exception when others then
    raise notice 'pg_cron unavailable — run activation_daily_sweep() manually';
  end;
end $$;

-- 5 ▸ the accountability report ---------------------------------------------
create or replace function public.activation_report()
returns jsonb language plpgsql
security definer set search_path = public as $$
begin
  if not is_case_hq() then raise exception 'HQ only'; end if;
  return (
    select coalesce(jsonb_agg(row order by row->>'name'), '[]'::jsonb)
    from (
      select jsonb_build_object(
        'id', p.id,
        'name', p.first_name || ' ' || p.last_name,
        'membership_no', p.membership_no,
        'role_applied', p.role_applied,
        'country', p.country,
        'state', p.state_region,
        'lga', p.lga,
        'profile_status', p.status::text,
        'journey_status', coalesce(j.status::text, 'not_started'),
        'started_at', j.started_at,
        'due_at', coalesce(j.extended_until, j.due_at),
        'day_reached', case when j.id is null then 0
          else least(14, greatest(1, floor(extract(epoch from
            (now() - j.started_at)) / 86400)::int + 1)) end,
        'items_done', coalesce((
          select count(*) from activation_item_responses r
            join activation_items i on i.id = r.item_id
           where r.journey_id = j.id and i.is_required), 0),
        'items_required', (select count(*) from activation_items
                            where is_required),
        'percent', coalesce(ev.pct, 0),
        'gate6', coalesce(ev.gate6, false),
        'gate13', coalesce(ev.gate13, false),
        'verdict', case
          when j.id is null then 'not_started'
          when j.status = 'completed' then 'passed'
          when j.status in ('incomplete', 'deferred') then 'failed'
          when now() > coalesce(j.extended_until, j.due_at) then 'failed'
          else 'in_progress' end,
        'has_cv', exists (select 1 from member_cvs c
                           where c.profile_id = p.id),
        'last_seen', p.last_seen_at
      ) as row
      from profiles p
      left join activation_journeys j on j.profile_id = p.id
      left join lateral (select * from eval_activation(j.id)) ev on true
      where p.merged_into is null
        and not exists (select 1 from staff st
                         where st.profile_id = p.id and st.is_active)
        and (j.id is not null
             or p.status in ('applicant', 'under_review', 'approved'))
    ) sub);
end; $$;
revoke execute on function public.activation_report() from anon;

-- 6 ▸ kickoff: align every journey to TODAY, then tell everyone -------------
create or replace function public.activation_kickoff()
returns jsonb language plpgsql
security definer set search_path = public as $$
declare
  n_reset int := 0; n_notified int := 0; r record;
  kick_title constant text := 'Your 14-Day Activation starts today';
begin
  if auth.uid() is not null and not is_case_hq() then
    raise exception 'HQ only';
  end if;

  -- Everyone still in progress gets the full 14 days from today.
  perform set_config('wdos.reason',
    '14-day activation officially begins 3 Aug 2026 — window aligned', true);
  update activation_journeys
     set started_at = now(), due_at = now() + interval '14 days'
   where status = 'in_progress'
     and started_at::date < current_date;
  get diagnostics n_reset = row_count;

  for r in
    select p.id, p.email, p.first_name
      from profiles p
     where p.merged_into is null
       and p.email is not null
       and not exists (select 1 from staff st
                        where st.profile_id = p.id and st.is_active)
       and (p.status in ('applicant', 'under_review', 'approved')
            or exists (select 1 from activation_journeys j
                        where j.profile_id = p.id
                          and j.status = 'in_progress'))
       and not exists (select 1 from member_notices mn
                        where mn.profile_id = p.id
                          and mn.title = kick_title)
     limit 400
  loop
    insert into member_notices (profile_id, kind, title, body, emailed_at,
                                meta)
    values (r.id, 'nudge', kick_title,
      'Dear ' || coalesce(r.first_name, 'volunteer') || ', your 14-day '
      || 'activation journey begins today, Monday 3 August 2026. Log in at '
      || 'https://woddicrm.org with your Volunteer ID, open My Journey, and '
      || 'complete each day''s tasks — the system now ticks them for you as '
      || 'you do them. Finish and pass within 14 days and WDOS approves you '
      || 'automatically, opening your courses as an approved volunteer. '
      || 'Start with Day 1: the Founder''s Welcome video is waiting for you.',
      now(),  -- we email inline below; stop the nightly engine re-sending
      jsonb_build_object('activation', 'kickoff'));
    perform send_email(r.email, r.first_name, kick_title,
      email_wrap(kick_title,
        'Dear ' || coalesce(r.first_name, 'volunteer') || ',' || e'\n\n'
        || 'Your 14-day activation journey begins today, Monday 3 August '
        || '2026.' || e'\n\n'
        || '1. Log in at https://woddicrm.org with your Volunteer ID.'
        || e'\n' || '2. Open My Journey and start Day 1 — the Founder''s '
        || 'Welcome video is waiting for you.' || e'\n'
        || '3. Complete each day''s tasks. WDOS now verifies and ticks '
        || 'them automatically as you do them.' || e'\n\n'
        || 'Finish and pass within 14 days and the system approves you '
        || 'automatically — your courses open the moment you pass.'
        || e'\n\n' || 'We are glad you are here. Go and nurture.'));
    n_notified := n_notified + 1;
  end loop;

  return jsonb_build_object('journeys_reset', n_reset,
                            'members_notified', n_notified);
end; $$;
revoke execute on function public.activation_kickoff() from anon;

-- 7 ▸ the logo rides every email --------------------------------------------
create or replace function public.email_wrap(title text, body text)
returns text language sql immutable as $$
  select '<div style="font-family:Arial,Helvetica,sans-serif;max-width:560px;'
      || 'margin:0 auto;border:1px solid #eee;border-radius:10px;overflow:hidden">'
      || '<div style="background:#ffffff;padding:16px 22px;'
      || 'border-bottom:3px solid #D4006A;text-align:center">'
      || '<img src="https://woddicrm.org/assets/woddi-logo.png" alt="WODDI — '
      || 'The Nurturer" style="height:52px;max-width:100%">'
      || '</div>'
      || '<div style="padding:22px"><h2 style="margin:0 0 10px;color:#111">'
      || title || '</h2><p style="color:#333;line-height:1.6;white-space:pre-line">'
      || body || '</p><p style="color:#7CB518;font-weight:700;margin-top:18px">'
      || 'The Nurturer &middot; <a href="https://woddicrm.org" '
      || 'style="color:#7CB518;text-decoration:none">woddicrm.org</a>'
      || '</p></div></div>'
$$;

-- 8 ▸ Phase-88 hotfix, folded in: the dashboard SQL editor runs with
--     auth.uid() null — the safe's door must let the building owner through.
create or replace function public.set_push_secret(k text, v text)
returns void language plpgsql
security definer set search_path = public as $$
begin
  if auth.uid() is not null and not is_case_hq() then
    raise exception 'HQ only';
  end if;
  if k not in ('push_fn_url', 'push_fn_key') then
    raise exception 'Unknown push secret %', k;
  end if;
  insert into push_secrets (key, value) values (k, v)
  on conflict (key) do update set value = excluded.value;
end; $$;
grant execute on function public.set_push_secret(text, text) to authenticated;
revoke execute on function public.set_push_secret(text, text)
  from anon, public;

-- 9 ▸ done -------------------------------------------------------------------
insert into public.schema_migrations (version, name)
values (68, 'activation_launch') on conflict (version) do nothing;
