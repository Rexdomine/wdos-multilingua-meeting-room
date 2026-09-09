-- ============================================================================
-- WDOS Migration 035 — Email Layer (Phase 39)
--
-- WDOS learns to send email — the WODDI way: no command line, no servers.
-- The database itself calls Brevo's API (via the pg_net extension) whenever
-- the daily automation runs:
--   • HQ digest alerts → also delivered to executives' email inboxes
--   • journey day messages, nudges and birthday wishes → also emailed to
--     the volunteer (weekly/monthly bulk stays in-app to respect Brevo's
--     free-tier daily limit; a per-run cap of 100 emails protects it too)
--
-- The Brevo API key lives in a sealed vault table no API client can read —
-- only the sending function (and HQ via a masked write-only box in
-- Settings) touches it. Nothing sends until HQ turns the switch on.
-- ============================================================================

create extension if not exists pg_net;

-- ---------------------------------------------------------------------------
-- 1. SEALED SECRETS — RLS enabled, NO policies: unreadable via the API.
-- ---------------------------------------------------------------------------
create table if not exists public.email_secrets (
  key text primary key,
  value text not null,
  updated_at timestamptz not null default now()
);
alter table public.email_secrets enable row level security;

create or replace function public.set_email_secret(k text, v text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_case_hq() then raise exception 'HQ only'; end if;
  if k not in ('brevo_api_key','email_from','email_from_name') then
    raise exception 'Unknown email setting';
  end if;
  insert into email_secrets (key, value) values (k, v)
  on conflict (key) do update set value = excluded.value, updated_at = now();
end; $$;

create or replace function public.get_email_status()
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not is_case_hq() then raise exception 'HQ only'; end if;
  return jsonb_build_object(
    'key_set',  exists (select 1 from email_secrets where key = 'brevo_api_key'
                          and length(value) > 10),
    'from',     (select value from email_secrets where key = 'email_from'),
    'from_name',(select value from email_secrets where key = 'email_from_name'),
    'enabled',  coalesce((select (value #>> '{}')::boolean from org_settings
                           where key = 'email_enabled'), false),
    'notices',  coalesce((select (value #>> '{}')::boolean from org_settings
                           where key = 'email_notices_enabled'), false));
end; $$;

insert into public.org_settings (key, value) values
  ('email_enabled', 'false'::jsonb),
  ('email_notices_enabled', 'false'::jsonb)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------
-- 2. THE SENDER — fire-and-forget HTTP to Brevo from inside Postgres.
-- ---------------------------------------------------------------------------
create or replace function public.send_email(
  to_email text, to_name text, subj text, html text)
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  api text; frm text; frm_name text;
begin
  if to_email is null or position('@' in to_email) = 0 then return false; end if;
  select value into api from email_secrets where key = 'brevo_api_key';
  if api is null then return false; end if;
  select value into frm from email_secrets where key = 'email_from';
  if frm is null then return false; end if;
  select value into frm_name from email_secrets where key = 'email_from_name';

  perform net.http_post(
    url := 'https://api.brevo.com/v3/smtp/email',
    headers := jsonb_build_object(
      'api-key', api, 'Content-Type', 'application/json',
      'accept', 'application/json'),
    body := jsonb_build_object(
      'sender', jsonb_build_object('email', frm,
        'name', coalesce(frm_name, 'WODDI')),
      'to', jsonb_build_array(jsonb_build_object(
        'email', to_email, 'name', coalesce(to_name, to_email))),
      'subject', subj,
      'htmlContent', html));
  return true;
exception when others then
  return false;   -- email is best-effort garnish; never break the caller
end; $$;

create or replace function public.email_wrap(title text, body text)
returns text language sql immutable as $$
  select '<div style="font-family:Arial,Helvetica,sans-serif;max-width:560px;'
      || 'margin:0 auto;border:1px solid #eee;border-radius:10px;overflow:hidden">'
      || '<div style="background:#D4006A;color:#fff;padding:18px 22px;'
      || 'font-size:20px;font-weight:800">WODDI</div>'
      || '<div style="padding:22px"><h2 style="margin:0 0 10px;color:#111">'
      || title || '</h2><p style="color:#333;line-height:1.6;white-space:pre-line">'
      || body || '</p><p style="color:#7CB518;font-weight:700;margin-top:18px">'
      || 'The Nurturer \u00b7 woddiwdos.netlify.app</p></div></div>'
$$;

create or replace function public.send_test_email()
returns boolean language plpgsql security definer set search_path = public as $$
declare me record;
begin
  if not is_case_hq() then raise exception 'HQ only'; end if;
  select email, first_name into me from profiles where id = auth.uid();
  return send_email(me.email, me.first_name, 'WDOS test email',
    email_wrap('It works!',
      'This is a test email from your WODDI Digital Operating System. '
      || 'The email layer is configured correctly.'));
end; $$;

-- ---------------------------------------------------------------------------
-- 3. EMAIL RECENT NOTICES — capped, deduped, opt-in.
-- ---------------------------------------------------------------------------
alter table public.member_notices
  add column if not exists emailed_at timestamptz;

create or replace function public.email_recent_notices()
returns int language plpgsql security definer set search_path = public as $$
declare
  enabled boolean; r record; sent int := 0;
begin
  select coalesce((value #>> '{}')::boolean, false) into enabled
    from org_settings where key = 'email_notices_enabled';
  if not enabled then return 0; end if;

  for r in
    select mn.id, mn.title, mn.body, p.email, p.first_name
      from member_notices mn
      join profiles p on p.id = mn.profile_id
     where mn.emailed_at is null
       and mn.kind in ('journey_day','birthday','nudge')
       and mn.created_at > now() - interval '26 hours'
       and p.email is not null
     order by mn.created_at
     limit 100
  loop
    if send_email(r.email, r.first_name, r.title,
                  email_wrap(r.title, coalesce(nullif(r.body,''), r.title))) then
      update member_notices set emailed_at = now() where id = r.id;
      sent := sent + 1;
    end if;
  end loop;
  return sent;
end; $$;

-- ---------------------------------------------------------------------------
-- 4. FOLD INTO THE DAILY RUN — HQ digests get emailed too.
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

insert into public.schema_migrations (version, name)
values (35, 'email_layer') on conflict (version) do nothing;
