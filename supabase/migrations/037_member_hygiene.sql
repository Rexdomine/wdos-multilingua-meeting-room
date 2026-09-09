-- ============================================================================
-- WDOS Migration 037 — Member Hygiene & Activity (Phase 41)
--
-- Two decision-independent items from the v3.0 guideline list:
--   1. ACTIVITY TRACKING — profiles.last_seen_at, updated cheaply when a
--      person opens the app (at most once per 6 hours). Powers a new
--      automation rule: HQ is alerted when active-family members haven't
--      opened WDOS in N days (default 30). The foundation the future
--      engagement/inactivity policy will stand on.
--   2. DUPLICATE DETECTION & MERGE — find profiles sharing an email, phone
--      or full name; HQ merges them. The kept profile inherits the dropped
--      one's roles, tasks, journeys, enrollments, notices and messages; the
--      dropped profile is marked merged (merged_into) and leaves all member
--      views. Every merge is fully audited.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1 ▸ activity tracking
-- ---------------------------------------------------------------------------
alter table public.profiles add column if not exists last_seen_at timestamptz;
alter table public.profiles add column if not exists merged_into uuid
  references public.profiles(id);

create or replace function public.touch_last_seen()
returns void language sql security definer set search_path = public as $$
  update profiles set last_seen_at = now()
   where id = auth.uid()
     and (last_seen_at is null or last_seen_at < now() - interval '6 hours');
$$;
grant execute on function public.touch_last_seen() to authenticated;

insert into public.automation_rules (code, threshold_days)
values ('inactive_member', 30)
on conflict (code) do nothing;

-- ---------------------------------------------------------------------------
-- 2 ▸ the wall + views also exclude merged profiles
-- ---------------------------------------------------------------------------
create or replace view public.field_members
with (security_invoker = true) as
  select * from public.profiles p
  where p.merged_into is null
    and not exists (select 1 from public.staff s
                    where s.profile_id = p.id and s.is_active);

-- ---------------------------------------------------------------------------
-- 3 ▸ duplicate detection (HQ)
-- ---------------------------------------------------------------------------
create or replace function public.find_duplicate_profiles()
returns jsonb language plpgsql security definer set search_path = public as $$
declare result jsonb;
begin
  if not is_case_hq() then raise exception 'HQ only'; end if;
  with base as (
    select id, first_name, last_name, email, phone, membership_no, status,
           created_at,
           lower(coalesce(email,'')) as em,
           regexp_replace(coalesce(phone,''), '\D', '', 'g') as ph,
           lower(trim(coalesce(first_name,'') || ' ' || coalesce(last_name,''))) as nm
      from profiles where merged_into is null
  ),
  pairs as (
    select a.id as a_id, b.id as b_id, 'email' as reason
      from base a join base b on a.em <> '' and a.em = b.em and a.id < b.id
    union
    select a.id, b.id, 'phone'
      from base a join base b
        on length(a.ph) >= 7 and a.ph = b.ph and a.id < b.id
    union
    select a.id, b.id, 'name'
      from base a join base b
        on length(a.nm) > 5 and a.nm = b.nm and a.id < b.id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'reason', p.reason,
      'a', (select to_jsonb(x) from (select id, first_name, last_name, email,
              phone, membership_no, status, created_at from profiles
              where id = p.a_id) x),
      'b', (select to_jsonb(x) from (select id, first_name, last_name, email,
              phone, membership_no, status, created_at from profiles
              where id = p.b_id) x))), '[]'::jsonb)
    into result from pairs p;
  return result;
end; $$;

-- ---------------------------------------------------------------------------
-- 4 ▸ merge (HQ) — keep one, fold the other into it
-- ---------------------------------------------------------------------------
create or replace function public.merge_profiles(
  keep uuid, drop_id uuid, reason text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not is_case_hq() then raise exception 'HQ only'; end if;
  if keep = drop_id then raise exception 'Cannot merge a profile into itself'; end if;
  if reason is null or char_length(trim(reason)) < 5 then
    raise exception 'A reason is required';
  end if;
  perform set_config('wdos.reason', reason, true);

  -- leadership roles (skip ones the keeper already holds)
  update role_assignments ra set profile_id = keep
   where ra.profile_id = drop_id
     and not exists (select 1 from role_assignments k
        where k.profile_id = keep and k.role = ra.role
          and coalesce(k.org_unit_id, '00000000-0000-0000-0000-000000000000')
            = coalesce(ra.org_unit_id, '00000000-0000-0000-0000-000000000000'));
  delete from role_assignments where profile_id = drop_id;

  -- work
  update tasks set assigned_to = keep where assigned_to = drop_id;
  update tasks set assigned_by = keep where assigned_by = drop_id;

  -- messages & notices
  update staff_messages set sender_id = keep
   where sender_id = drop_id and recipient_id <> keep;
  update staff_messages set recipient_id = keep
   where recipient_id = drop_id and sender_id <> keep;
  delete from staff_messages
   where (sender_id = drop_id or recipient_id = drop_id);
  update member_notices set profile_id = keep where profile_id = drop_id;

  -- announcement reads (keep may already have some)
  insert into announcement_reads (announcement_id, profile_id)
  select announcement_id, keep from announcement_reads
   where profile_id = drop_id
  on conflict do nothing;
  delete from announcement_reads where profile_id = drop_id;

  -- activation journey: keeper's wins; move only if keeper has none
  if not exists (select 1 from activation_journeys where profile_id = keep) then
    update activation_journeys set profile_id = keep where profile_id = drop_id;
  else
    delete from activation_journeys where profile_id = drop_id;
  end if;

  -- course enrollments: move unless the keeper is already enrolled
  update course_enrollments ce set profile_id = keep
   where ce.profile_id = drop_id
     and not exists (select 1 from course_enrollments k
        where k.profile_id = keep and k.course_id = ce.course_id);
  delete from course_enrollments where profile_id = drop_id;

  -- staff placement (rare, but keep it coherent)
  update staff set profile_id = keep
   where profile_id = drop_id
     and not exists (select 1 from staff k where k.profile_id = keep);
  delete from staff where profile_id = drop_id;

  -- fill gaps on the keeper from the dropped record
  update profiles k set
    phone = coalesce(k.phone, d.phone),
    birth_date = coalesce(k.birth_date, d.birth_date),
    network = coalesce(k.network, d.network)
  from profiles d where k.id = keep and d.id = drop_id;

  -- retire the dropped profile
  update profiles set merged_into = keep where id = drop_id;

  return jsonb_build_object('kept', keep, 'merged', drop_id);
end; $$;

insert into public.schema_migrations (version, name)
values (37, 'member_hygiene') on conflict (version) do nothing;

-- ---------------------------------------------------------------------------
-- 5 ▸ fold the inactivity rule into the daily run
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
  mail_on boolean;
  mailed int := 0;
  hq_p record;
begin
  select array_agg(distinct ra.profile_id) into hq
    from role_assignments ra
   where ra.role in ('super_admin','executive_director','hq_team');
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
