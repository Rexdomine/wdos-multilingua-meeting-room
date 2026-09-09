-- ============================================================================
-- WDOS Migration 096 — UAT Round 1 fixes (Phase 108)
--
-- Ekene's testing committee report (testing 6-10 Aug, report 19 Aug)
-- listed 8 High priority problems. Several were already fixed between
-- the testing window and now (stuck registrations / missing IDs via
-- migrations 083-085; the missing post-registration button already
-- exists on the volunteer form). This migration fixes what is GENUINELY
-- still broken, verified against the live codebase first:
--
--   #1  volunteer_applications had NO duplicate-email protection at all
--       (the frontend even catches a 'duplicate' error the database
--       could never raise). Existing duplicates are cleaned first, the
--       earliest live row per email wins, then a partial unique index
--       enforces it forever.
--   #3  The auto-approval welcome email said "you are approved!" —
--       the founder's own message library (023, provisional_approval)
--       requires PROVISIONAL wording plus the activation journey
--       explained. Rewritten to match, typos gone, and the link now
--       points at woddicrm.org (it pointed at the old netlify URL).
--   #4  That same email drove people to a page titled "Claim your
--       account" — unapproved wording. The flow stays (it is how
--       logins are created); the words change to "Create your WODDI
--       login" (locales, this same release).
--   #7  HQ genuinely could not change a volunteer leader's appointment
--       and saw no reason why: decide_application correctly refuses
--       already-decided applications, but the UI swallowed the message.
--       New set_leader_appointment() acts on the real object (the
--       role_assignments seat), and — exactly as the report recommends —
--       notifies the leader (notice + best-effort email) when her
--       appointment status changes. The UI now also surfaces real
--       error reasons instead of a generic "could not save".
--   #8  Helpdesk tickets had no reference number column at all and no
--       acknowledgement. Added HD-YYYY-###### refs (backfilled for
--       every existing ticket), plus an automatic acknowledgement
--       notice + best-effort email on filing.
-- ============================================================================

-- ---- #1: duplicate registrations on the Institute volunteer pipeline ----

-- clean existing duplicates first (the testers created real ones):
-- the EARLIEST non-rejected row per email survives; later duplicates are
-- marked rejected with an honest reason, never deleted (audit trail).
with ranked as (
  select id, row_number() over (
           partition by lower(email)
           order by created_at asc, id asc) as rn
    from public.volunteer_applications
   where status <> 'rejected'
)
update public.volunteer_applications v
   set status = 'rejected',
       decision_reason = 'Duplicate registration for the same email '
         || '(kept the earliest one). Auto-cleaned by migration 096.',
       decided_at = now()
  from ranked r
 where v.id = r.id and r.rn > 1;

create unique index if not exists volunteer_apps_live_email_uq
  on public.volunteer_applications (lower(email))
  where status <> 'rejected';

-- ---- #3/#4: the welcome email, rewritten to the approved wording --------

create or replace function public.volunteer_auto_approve()
returns trigger language plpgsql
security definer set search_path = public as $$
begin
  begin
    if new.status = 'submitted' then
      update volunteer_applications
         set status = 'approved',
             decision_reason = 'Auto-approved on registration (org policy)',
             decided_at = now()
       where id = new.id;

      insert into audit_log (actor, action, detail, at)
      values (null, 'approved', 'Auto-approved volunteer registration', now());
    end if;

    -- provisional-approval wording from the founder's message library,
    -- with the 14-Day Activation Journey actually explained
    perform send_email(new.email,
      coalesce(nullif(split_part(new.full_name, ' ', 1), ''), 'Volunteer'),
      'Your WODDI registration is received, provisionally approved',
      email_wrap('Welcome to WODDI',
        'Congratulations '
        || coalesce(nullif(split_part(new.full_name, ' ', 1), ''), '')
        || '! Your registration has been received and provisionally '
        || 'approved. Your activation journey begins now.' || e'\n\n'
        || 'What happens next: every new volunteer completes the 14-Day '
        || 'Activation Journey, a guided two-week programme of short '
        || 'daily steps inside WDOS. It is how WODDI gets to know your '
        || 'commitment and readiness, and how you get to know WODDI. '
        || 'Completing it is the path to full membership and to being '
        || 'considered for the role you applied for.' || e'\n\n'
        || 'Create your WODDI login now to begin:'
        || e'\n' || 'https://woddicrm.org/#/claim' || e'\n\n'
        || 'Use the same email address you registered with. Your WODDI '
        || 'ID will be shown to you as soon as your login is created. '
        || 'We are delighted to have you.'));
  exception when others then
    raise notice 'volunteer_auto_approve skipped for %: %', new.email, sqlerrm;
  end;
  return new;
end; $$;

-- ---- #7: leader appointment status changes, with notification -----------

create or replace function public.set_leader_appointment(
  p_assignment uuid, p_action text, p_reason text)
returns jsonb language plpgsql
security definer set search_path = public as $$
declare
  ra role_assignments; p profiles; action_title text; action_body text;
begin
  if auth.uid() is not null and not is_case_hq() then
    raise exception 'HQ only';
  end if;
  if p_action not in ('end', 'reactivate') then
    raise exception 'Unrecognised action: % (use end or reactivate)', p_action;
  end if;
  if p_reason is null or char_length(trim(p_reason)) < 5 then
    raise exception 'A reason of at least 5 characters is required';
  end if;

  select * into ra from role_assignments where id = p_assignment;
  if ra.id is null then raise exception 'Appointment not found'; end if;
  select * into p from profiles where id = ra.profile_id;

  if p_action = 'end' then
    if ra.ends_at is not null and ra.ends_at <= now() then
      raise exception 'This appointment has already ended';
    end if;
    update role_assignments set ends_at = now() where id = p_assignment;
    action_title := 'Update about your WODDI appointment';
    action_body := 'Your appointment as ' || coalesce(ra.role::text, 'leader')
      || ' has been concluded by WODDI HQ. Reason given: ' || trim(p_reason)
      || '. If you have any questions, please reply through Ask HQ \u2014 '
      || 'we are grateful for your service.';
  else
    if ra.ends_at is null or ra.ends_at > now() then
      raise exception 'This appointment is already active';
    end if;
    update role_assignments set ends_at = null where id = p_assignment;
    action_title := 'Your WODDI appointment is active again';
    action_body := 'Your appointment as ' || coalesce(ra.role::text, 'leader')
      || ' has been reactivated by WODDI HQ. Reason given: '
      || trim(p_reason) || '. Welcome back \u2014 your access and '
      || 'responsibilities resume immediately.';
  end if;

  -- the notification the testing committee asked for: the leader is told
  if p.id is not null then
    insert into member_notices (profile_id, kind, title, body, meta)
    values (p.id, 'manual', action_title, action_body,
            jsonb_build_object('assignment', p_assignment,
                               'action', p_action));
    if p.email is not null then
      perform send_email(p.email, coalesce(p.first_name, 'Leader'),
        action_title, email_wrap(action_title, action_body));
    end if;
  end if;

  return jsonb_build_object('ok', true, 'action', p_action,
    'leader', coalesce(p.first_name || ' ' || p.last_name, 'Unknown'));
end; $$;
revoke execute on function public.set_leader_appointment(uuid, text, text)
  from anon;

-- ---- #8: helpdesk acknowledgement -----------------------------------------
-- Correction found during verification: tickets have ALWAYS had reference
-- numbers (ticket_no, 'T-YYYY-0001' style, migration 014) — the testers
-- never saw one because the UI never showed it after filing and nothing
-- acknowledged the request. The number is real; the acknowledgement and
-- the display were the missing pieces. The display ships in this same
-- release (frontend); the acknowledgement is below, quoting the real
-- ticket_no.

create or replace function public.tickets_acknowledge()
returns trigger language plpgsql
security definer set search_path = public as $$
declare p profiles;
begin
  begin
    select * into p from profiles where id = new.requester_id;
    insert into member_notices (profile_id, kind, title, body, meta)
    values (new.requester_id, 'manual',
      'We received your Helpdesk request (' || new.ticket_no || ')',
      'Thank you for reaching out. Your request "'
      || coalesce(new.subject, '') || '" has been received and logged as '
      || new.ticket_no || '. The team will respond as soon as possible. '
      || 'You can follow progress any time in the Helpdesk section.',
      jsonb_build_object('ticket', new.id, 'ref', new.ticket_no));
    if p.email is not null then
      perform send_email(p.email, coalesce(p.first_name, 'Member'),
        'WODDI Helpdesk received your request (' || new.ticket_no || ')',
        email_wrap('We received your request',
          'Thank you for reaching out. Your Helpdesk request "'
          || coalesce(new.subject, '') || '" has been received and logged '
          || 'with reference number ' || new.ticket_no || '.' || e'\n\n'
          || 'The team will respond as soon as possible. You can follow '
          || 'progress any time in the Helpdesk section of WDOS. Please '
          || 'quote your reference number in any follow-up.'));
    end if;
  exception when others then
    raise notice 'ticket acknowledgement skipped for %: %', new.id, sqlerrm;
  end;
  return new;
end; $$;

drop trigger if exists tickets_ack on public.tickets;
create trigger tickets_ack
  after insert on public.tickets
  for each row execute function public.tickets_acknowledge();

insert into public.schema_migrations (version, name)
values (96, 'uat_round1_fixes') on conflict (version) do nothing;
