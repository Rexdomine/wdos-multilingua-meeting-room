-- ============================================================================
-- WDOS Migration 099 — the Founder's extension to 31 August (Phase 113)
--
-- Directive: everyone who did NOT pass the 14-day activation gets until
-- 31 August 2026 to finish. All days open, no gating, because a person
-- on day 3 can realistically still make it if nothing holds them back.
-- People who already passed are untouched and receive NO email.
--
-- Mechanics, verified against the live code first:
--   * extended_until has existed since migration 024 and the expiry
--     sweep honours coalesce(extended_until, due_at) — so stamping the
--     new deadline is all the database needs.
--   * "Failed" journeys are status='incomplete'; reviving them to
--     'in_progress' puts them back inside every existing flow
--     (reminders, finalisation, reports) with zero special cases.
--   * Day gating is enforced in the app, not the database, so the app
--     side of this release opens every day whenever a journey carries
--     a future extension — which scopes the ungating to exactly this
--     cohort and nobody else.
--   * Leaders (status='deferred') and the completed are structurally
--     excluded: neither status is touched below.
-- ============================================================================

alter table public.activation_journeys
  add column if not exists extension_notified_at timestamptz;

-- ---- the act itself: revive and extend the didn't-finish cohort ---------
update public.activation_journeys j
   set status = 'in_progress',
       extended_until = timestamptz '2026-08-31 23:59:59+01'
  from public.profiles p
 where p.id = j.profile_id
   and not coalesce(p.is_leader, false)
   and j.status in ('in_progress', 'incomplete')
   and coalesce(j.extended_until, j.due_at)
       < timestamptz '2026-08-31 23:59:59+01';

-- ---- the announcement, batched to respect email daily limits ------------
-- Call: select send_extension_emails(120);  repeat until remaining = 0.
-- Every person also gets an in-app notice immediately, so even someone
-- whose email bounces sees the news at next login. The completed are
-- never selected: their status is 'completed', not 'in_progress'.
create or replace function public.send_extension_emails(p_limit int default 120)
returns jsonb language plpgsql
security definer set search_path = public as $$
declare r record; n_sent int := 0; n_left int;
begin
  if auth.uid() is not null and not is_case_hq() then
    raise exception 'HQ only';
  end if;

  for r in
    select j.id as jid, p.id as pid, p.email,
           coalesce(nullif(p.first_name, ''), 'Volunteer') as fname
      from activation_journeys j
      join profiles p on p.id = j.profile_id
     where j.status = 'in_progress'
       and j.extended_until = timestamptz '2026-08-31 23:59:59+01'
       and not coalesce(p.is_leader, false)
       and j.extension_notified_at is null
     order by j.due_at asc
     limit greatest(p_limit, 1)
  loop
    insert into member_notices (profile_id, kind, title, body, meta)
    values (r.pid, 'journey_day',
      r.fname || ', your activation journey has been extended to 31 August',
      'Good news, ' || r.fname || '. WODDI has extended the 14-Day '
      || 'Activation Journey for everyone still on the road: you now have '
      || 'until 31 August 2026 to finish, and every day of the journey is '
      || 'open to you right now, no waiting between days. Wherever you '
      || 'stopped, you can pick up today and complete at your own pace. '
      || 'Your progress so far is saved. We believe in you. Finish '
      || 'strong.',
      jsonb_build_object('extension', '2026-08-31'));

    if r.email is not null then
      perform send_email(r.email, r.fname,
        r.fname || ', your WODDI activation has been extended to 31 August',
        email_wrap('You have more time, and every day is open',
          'Good news, ' || r.fname || '.' || e'\n\n'
          || 'WODDI has extended the 14-Day Activation Journey for '
          || 'everyone who has not yet finished. You now have until '
          || '31 August 2026, and every day of the journey is open to '
          || 'you immediately, no waiting between days. Wherever you '
          || 'stopped, whether day 2 or day 12, you can continue today '
          || 'and finish at your own pace before the end of the month.'
          || e'\n\n'
          || 'Everything you have already completed is saved. Sign in '
          || 'and continue here:' || e'\n'
          || 'https://woddicrm.org' || e'\n\n'
          || 'We believe in you. Finish strong.'));
    end if;

    update activation_journeys
       set extension_notified_at = now()
     where id = r.jid;
    n_sent := n_sent + 1;
  end loop;

  select count(*) into n_left
    from activation_journeys j
    join profiles p on p.id = j.profile_id
   where j.status = 'in_progress'
     and j.extended_until = timestamptz '2026-08-31 23:59:59+01'
     and not coalesce(p.is_leader, false)
     and j.extension_notified_at is null;

  return jsonb_build_object('sent', n_sent, 'remaining', n_left);
end; $$;
revoke execute on function public.send_extension_emails(int) from anon;

insert into public.schema_migrations (version, name)
values (99, 'founder_extension_31aug') on conflict (version) do nothing;
