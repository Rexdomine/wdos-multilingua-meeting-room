-- ============================================================================
-- WDOS Migration 067 — HQ ↔ Member Messaging & Web Push (Phase 88)
--
-- 1. HQ CAN MESSAGE ANY MEMBER PERSONALLY. The recipient picker was staff-
--    only (search_staff_assignees, 057); a new search_message_recipients()
--    lets HQ find field members too, while members searching see exactly
--    one recipient: WODDI HQ. The wall holds — no member-to-member paths.
-- 2. ONE VERIFIED VOICE. message_identities() computes display names
--    server-side: to a field member, every HQ-side counterpart appears as
--    "WODDI HQ" with verified = true (the green tick). The tick is decided
--    by the DATABASE from staff/role records — a profile renaming itself
--    "WODDI HQ" earns nothing. Members also no longer need profile-read
--    access to staff rows just to see who wrote to them (the old null-name
--    RLS trap from phases 21b/21c).
-- 3. MEMBERS REPLY FROM #/me. hq_inbox_target() gives a fresh conversation
--    a real HQ recipient (master account first); replies inside a thread
--    go back to whichever HQ person last wrote.
-- 4. TRUE PUSH, BROWSER CLOSED. push_subscriptions (per device) and
--    push_outbox (per pending notification), fed by triggers on
--    staff_messages and member_notices — the same lanes the bell already
--    rides. Delivery: the database kicks the push-send Edge Function over
--    pg_net (exactly the Brevo email pattern from 035); VAPID keys never
--    leave the Edge Function's secrets.
-- 5. people_analytics() FIXED: it referenced activation_milestones.required
--    but the column (024) is is_required — the RPC has errored on every
--    call, and getReports()'s all-or-nothing fetch let it take the whole
--    Reports page down with it. Recreated corrected.
-- ============================================================================

-- 0 ▸ prerequisites -----------------------------------------------------------
create extension if not exists pg_net;

-- 1 ▸ who counts as "HQ-side" (the verified voice) ---------------------------
-- Mirrors can_receive_direct(): active staff, or a live super_admin /
-- executive_director / hq_team role. Named for what it answers here.
create or replace function public.is_hq_identity(pid uuid)
returns boolean language sql stable
security definer set search_path = public as $$
  select public.can_receive_direct(pid);
$$;
grant execute on function public.is_hq_identity(uuid) to authenticated;
revoke execute on function public.is_hq_identity(uuid) from anon, public;

-- 2 ▸ message_identities(): server-computed labels for MY counterparties ----
-- Derives the set of people I share messages with (no fishing for arbitrary
-- profiles), then labels each one:
--   · caller is HQ-side  → real names for everyone (colleagues stay people)
--   · caller is a member → HQ-side counterparts become 'WODDI HQ'
--   · verified = is_hq_identity(counterpart), for every caller
create or replace function public.message_identities()
returns table (profile_id uuid, display_name text, verified boolean)
language sql stable
security definer set search_path = public as $$
  with me as (select public.is_hq_identity(auth.uid()) as hq_caller),
  counterparties as (
    select distinct case when m.sender_id = auth.uid()
                         then m.recipient_id else m.sender_id end as pid
      from staff_messages m
     where m.sender_id = auth.uid() or m.recipient_id = auth.uid()
  )
  select p.id,
         case when (not (select hq_caller from me))
                   and public.is_hq_identity(p.id)
              then 'WODDI HQ'
              else nullif(trim(coalesce(p.first_name, '') || ' '
                            || coalesce(p.last_name, '')), '')
         end as display_name,
         public.is_hq_identity(p.id) as verified
    from counterparties c
    join profiles p on p.id = c.pid;
$$;
grant execute on function public.message_identities() to authenticated;
revoke execute on function public.message_identities() from anon, public;

-- 3 ▸ hq_inbox_target(): who receives a member's fresh message --------------
-- Master account (super_admin) first, then executive director, then any
-- active staff member — so #/me can always open a conversation.
create or replace function public.hq_inbox_target()
returns uuid language sql stable
security definer set search_path = public as $$
  select pid from (
    select ra.profile_id as pid, 1 as pri
      from role_assignments ra
     where ra.role = 'super_admin' and ra.ends_at is null
    union all
    select ra.profile_id, 2
      from role_assignments ra
     where ra.role = 'executive_director' and ra.ends_at is null
    union all
    select st.profile_id, 3 from staff st where st.is_active
  ) t order by pri limit 1;
$$;
grant execute on function public.hq_inbox_target() to authenticated;
revoke execute on function public.hq_inbox_target() from anon, public;

-- 4 ▸ search_message_recipients(): the picker both sides deserve ------------
-- HQ-side callers: active staff PLUS field members (any live profile that
-- isn't staff — HQ writes to applicants and alumni too), searched by name,
-- email, or Volunteer ID. Member callers: exactly one row — WODDI HQ.
create or replace function public.search_message_recipients(s text)
returns table (id uuid, first_name text, last_name text,
               email text, sub text, kind text)
language plpgsql stable
security definer set search_path = public as $$
#variable_conflict use_column
begin
  if public.is_hq_identity(auth.uid()) then
    return query
      select p.id, p.first_name, p.last_name, p.email,
             st.position_title as sub, 'staff'::text as kind
        from staff st join profiles p on p.id = st.profile_id
       where st.is_active and p.id <> auth.uid()
         and (coalesce(s, '') = ''
              or p.first_name ilike '%' || s || '%'
              or p.last_name  ilike '%' || s || '%'
              or p.email      ilike '%' || s || '%'
              or st.position_title ilike '%' || s || '%')
      union all
      select p.id, p.first_name, p.last_name, p.email,
             coalesce(p.membership_no,
                      initcap(replace(p.status::text, '_', ' '))) as sub,
             'member'::text as kind
        from profiles p
       where p.merged_into is null and p.id <> auth.uid()
         and not exists (select 1 from staff st2
                          where st2.profile_id = p.id and st2.is_active)
         and (coalesce(s, '') = ''
              or p.first_name    ilike '%' || s || '%'
              or p.last_name     ilike '%' || s || '%'
              or p.email         ilike '%' || s || '%'
              or p.membership_no ilike '%' || s || '%')
      order by 6, 2   -- kind, then first name (positional: the RETURNS
                      -- TABLE variables shadow these names in plpgsql)
      limit 24;
  else
    return query
      select t.pid, 'WODDI'::text, 'HQ'::text, null::text,
             'Headquarters'::text, 'hq'::text
        from (select public.hq_inbox_target() as pid) t
       where t.pid is not null;
  end if;
end; $$;
grant execute on function public.search_message_recipients(text) to authenticated;
revoke execute on function public.search_message_recipients(text) from anon, public;

-- 5 ▸ push_subscriptions: one row per device --------------------------------
create table if not exists public.push_subscriptions (
  id           uuid primary key default gen_random_uuid(),
  profile_id   uuid not null references public.profiles(id) on delete cascade,
  endpoint     text not null unique,
  p256dh       text not null,
  auth         text not null,
  ua           text,
  created_at   timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);
create index if not exists push_subs_profile_idx
  on public.push_subscriptions (profile_id);

alter table public.push_subscriptions enable row level security;

drop policy if exists push_subs_own on public.push_subscriptions;
create policy push_subs_own on public.push_subscriptions
  for all to authenticated
  using (profile_id = auth.uid())
  with check (profile_id = auth.uid());

-- 6 ▸ push_secrets: where the database learns how to kick the sender --------
-- Same shape as email_secrets (035). Two keys:
--   push_fn_url — https://<project-ref>.supabase.co/functions/v1/push-send
--   push_fn_key — the anon key (the function is JWT-gated; it does its own
--                 work with its service-role env and trusts no input)
create table if not exists public.push_secrets (
  key   text primary key,
  value text not null
);
alter table public.push_secrets enable row level security;

create or replace function public.set_push_secret(k text, v text)
returns void language plpgsql
security definer set search_path = public as $$
begin
  if not is_case_hq() then raise exception 'HQ only'; end if;
  if k not in ('push_fn_url', 'push_fn_key') then
    raise exception 'Unknown push secret %', k;
  end if;
  insert into push_secrets (key, value) values (k, v)
  on conflict (key) do update set value = excluded.value;
end; $$;
grant execute on function public.set_push_secret(text, text) to authenticated;
revoke execute on function public.set_push_secret(text, text) from anon, public;

create or replace function public.push_secret_status()
returns jsonb language sql stable
security definer set search_path = public as $$
  select jsonb_build_object(
    'url_set', exists (select 1 from push_secrets where key = 'push_fn_url'
                          and value <> ''),
    'key_set', exists (select 1 from push_secrets where key = 'push_fn_key'
                          and value <> ''));
$$;
grant execute on function public.push_secret_status() to authenticated;
revoke execute on function public.push_secret_status() from anon, public;

-- 7 ▸ push_outbox + queue_push() --------------------------------------------
create table if not exists public.push_outbox (
  id         uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  title      text not null,
  body       text,
  url        text not null default '#/me',
  created_at timestamptz not null default now(),
  sent_at    timestamptz,
  error      text
);
create index if not exists push_outbox_pending_idx
  on public.push_outbox (created_at) where sent_at is null;

-- RLS on, no client policies: only definer functions and the service role
-- (the Edge Function) touch this table.
alter table public.push_outbox enable row level security;

create or replace function public.queue_push(
  pid uuid, ptitle text, pbody text, purl text)
returns void language plpgsql
security definer set search_path = public as $$
begin
  -- No devices registered → nothing to queue.
  if not exists (select 1 from push_subscriptions where profile_id = pid) then
    return;
  end if;
  insert into push_outbox (profile_id, title, body, url)
  values (pid, left(coalesce(ptitle, 'WDOS'), 120),
          left(coalesce(pbody, ''), 200), coalesce(purl, '#/me'));
end; $$;

-- The kick: every outbox insert pokes the Edge Function, which drains the
-- whole pending queue. Failures are swallowed — a broken push pipeline must
-- never block the message or task that triggered it. If secrets are unset,
-- rows simply wait (the function also drains on its next invocation).
create or replace function public.push_outbox_kick()
returns trigger language plpgsql
security definer set search_path = public as $$
declare
  fn_url text; fn_key text;
begin
  select value into fn_url from push_secrets where key = 'push_fn_url';
  select value into fn_key from push_secrets where key = 'push_fn_key';
  if fn_url is null or fn_key is null then return new; end if;
  begin
    perform net.http_post(
      url := fn_url,
      headers := jsonb_build_object(
        'Authorization', 'Bearer ' || fn_key,
        'apikey', fn_key,
        'Content-Type', 'application/json'),
      body := '{}'::jsonb);
  exception when others then null;
  end;
  return new;
end; $$;

drop trigger if exists push_outbox_kick_trg on public.push_outbox;
create trigger push_outbox_kick_trg
  after insert on public.push_outbox
  for each row execute function public.push_outbox_kick();

-- 8 ▸ feed the outbox from the two personal lanes ---------------------------
-- 8a: direct messages. Members see the verified voice: pushes from HQ-side
--     senders to non-staff recipients are titled 'WODDI HQ'; everything
--     else names the sender. Deep link matches where the reply box lives.
create or replace function public.staff_msg_push()
returns trigger language plpgsql
security definer set search_path = public as $$
declare
  ptitle text; purl text; sname text;
begin
  if public.is_hq_identity(new.sender_id)
     and not public.is_hq_identity(new.recipient_id) then
    ptitle := 'WODDI HQ';
    purl := '#/me';
  else
    select nullif(trim(coalesce(p.first_name, '') || ' '
                    || coalesce(p.last_name, '')), '')
      into sname from profiles p where p.id = new.sender_id;
    ptitle := coalesce(sname, 'New message');
    purl := '#/messages?u=' || new.sender_id::text;
  end if;
  perform public.queue_push(new.recipient_id, ptitle,
                            left(new.body, 160), purl);
  return new;
end; $$;

drop trigger if exists staff_msg_push_trg on public.staff_messages;
create trigger staff_msg_push_trg
  after insert on public.staff_messages
  for each row execute function public.staff_msg_push();

-- 8b: personal notices (task assignments, meetings, journey days, birthdays
--     — everything 045's engines already write). One trigger covers them all.
create or replace function public.member_notice_push()
returns trigger language plpgsql
security definer set search_path = public as $$
begin
  perform public.queue_push(new.profile_id, new.title, new.body,
    case new.kind when 'task' then '#/tasks'
                  when 'meeting' then '#/meetings'
                  else '#/me' end);
  return new;
end; $$;

drop trigger if exists member_notice_push_trg on public.member_notices;
create trigger member_notice_push_trg
  after insert on public.member_notices
  for each row execute function public.member_notice_push();

-- 9 ▸ people_analytics() corrected (053's m.required → m.is_required) -------
create or replace function public.people_analytics()
returns jsonb language plpgsql security definer
set search_path = public as $$
begin
  if not is_case_hq() then raise exception 'HQ only'; end if;
  return (
    select coalesce(jsonb_agg(row order by row->>'name'), '[]'::jsonb)
    from (
      select jsonb_build_object(
        'id', p.id,
        'name', p.first_name || ' ' || p.last_name,
        'role', coalesce(
          (select st.position_title from staff st
            where st.profile_id = p.id and st.is_active limit 1),
          (select initcap(replace(ra.role::text, '_', ' '))
             from role_assignments ra
            where ra.profile_id = p.id and ra.ends_at is null
            order by ra.starts_at limit 1),
          initcap(replace(p.status::text, '_', ' '))),
        'network', p.network,
        'unit', (select name from org_units where id = p.org_unit_id),
        'country', unit_country_name(p.org_unit_id),
        'is_staff', exists (select 1 from staff st
                             where st.profile_id = p.id and st.is_active),
        'journey_status', (select j.status::text from activation_journeys j
                            where j.profile_id = p.id limit 1),
        'journey_done', (select count(*) from activation_item_responses r
                          join activation_journeys j2 on j2.id = r.journey_id
                         where j2.profile_id = p.id and r.done),
        'journey_required', (select count(*) from activation_milestones m
                              where m.is_required),
        'journey_day', (select least(14, greatest(1,
            floor(extract(epoch from (now() - j3.started_at)) / 86400)::int + 1))
          from activation_journeys j3
         where j3.profile_id = p.id and j3.status = 'in_progress' limit 1),
        'courses_enrolled', (select count(*) from course_enrollments ce
                              where ce.profile_id = p.id),
        'courses_done', (select count(*) from course_enrollments ce
                          where ce.profile_id = p.id
                            and ce.completed_at is not null),
        'tasks_open', (select count(*) from tasks tk
                        where tk.assigned_to = p.id
                          and tk.status in ('not_started','in_progress')),
        'tasks_overdue', (select count(*) from tasks tk
                           where tk.assigned_to = p.id
                             and tk.status in ('not_started','in_progress')
                             and tk.due_on is not null
                             and tk.due_on < current_date),
        'last_seen', p.last_seen_at
      ) as row
      from profiles p
      where p.merged_into is null
        and (p.status in ('approved','activated','in_training',
                          'active','reinstated')
             or exists (select 1 from staff st
                         where st.profile_id = p.id and st.is_active))
    ) sub);
end; $$;
revoke execute on function public.people_analytics() from anon;

-- 10 ▸ done ------------------------------------------------------------------
insert into public.schema_migrations (version, name)
values (67, 'hq_member_messaging_push') on conflict (version) do nothing;
