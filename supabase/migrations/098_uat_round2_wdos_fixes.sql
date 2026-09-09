-- ============================================================================
-- WDOS Migration 098 — UAT Round 2 fixes, WDOS-side items (Phase 111)
--
-- From the committee's Round 2 report (21 Aug). Institute-app findings
-- (track selection, country community, Start Here hub, Institute welcome
-- message) are out of scope here — they live in the separate Institute
-- system. The WDOS items, verified against code before fixing:
--
--   #2 SCREENING CONTRADICTION (the serious one, confirmed real, two
--      doors): claim_check() recognised approved rows only in the main
--      applications table, so an approved network volunteer was told
--      "pending review" or "not found" by the very door the approval
--      email sent them to. And handle_new_user() built real profiles
--      only from the main table, so an approved volunteer who signed up
--      anyway received a bare, statusless profile. Both fixed: the
--      volunteer pipeline's approvals are now first-class at both doors.
--
--   #1 CONFIRMATION LACKED A REFERENCE AND THE TRACK: network volunteer
--      applications now receive VA-YYYY-#### reference numbers
--      (backfilled for all existing rows), a new submit RPC returns the
--      reference so the success screen can state it plus the network,
--      and the welcome email quotes it. (The quick network form does
--      not ask a position, so the confirmation states the network
--      track applied for, which is what that form captures.)
--
--   #8 COMPLETION MESSAGE NOT PERSONALISED: the 14-day pass
--      congratulations now greets the person by first name.
--
--   #5 (registration email not arriving) is a delivery-side matter:
--      emails leave the database asynchronously, so no SQL change can
--      see or fix non-delivery. Diagnosis checklist provided outside
--      this migration.
-- ============================================================================

-- ---- #1: reference numbers for network volunteer applications -----------

create sequence if not exists public.vol_app_ref_seq;

alter table public.volunteer_applications
  add column if not exists ref_no text unique;

create or replace function public.vol_apps_assign_ref()
returns trigger language plpgsql
security definer set search_path = public as $$
begin
  if new.ref_no is null then
    new.ref_no := 'VA-' || to_char(now(), 'YYYY') || '-'
      || lpad(nextval('vol_app_ref_seq')::text, 4, '0');
  end if;
  return new;
end; $$;

drop trigger if exists vol_apps_ref on public.volunteer_applications;
create trigger vol_apps_ref
  before insert on public.volunteer_applications
  for each row execute function public.vol_apps_assign_ref();

update public.volunteer_applications
   set ref_no = 'VA-' || to_char(created_at, 'YYYY') || '-'
     || lpad(nextval('vol_app_ref_seq')::text, 4, '0')
 where ref_no is null;

-- the submit RPC: does the insert and hands the reference back so the
-- success screen can state it (anon inserts cannot read rows back
-- under row security, so the function carries the answer out).
create or replace function public.submit_volunteer_reg(
  p_full_name text, p_email text, p_phone text,
  p_network text, p_country text, p_about text)
returns jsonb language plpgsql
security definer set search_path = public as $$
declare rid uuid; rref text;
begin
  if coalesce(trim(p_full_name), '') = '' then
    raise exception 'Name is required';
  end if;
  if coalesce(trim(p_email), '') = '' or position('@' in p_email) = 0 then
    raise exception 'A valid email is required';
  end if;
  if p_network not in ('WGMN', 'WNNN') then
    raise exception 'Select your age range so your network can be set';
  end if;

  insert into volunteer_applications
    (full_name, email, phone, network, country, payload)
  values
    (trim(p_full_name), lower(trim(p_email)), nullif(trim(p_phone), ''),
     p_network::public.network_code, nullif(trim(p_country), ''),
     jsonb_build_object('about', coalesce(p_about, '')))
  returning id, ref_no into rid, rref;

  return jsonb_build_object('ok', true, 'ref', rref, 'network', p_network);
end; $$;
revoke all on function public.submit_volunteer_reg(text, text, text, text, text, text) from public;
grant execute on function public.submit_volunteer_reg(text, text, text, text, text, text)
  to anon, authenticated;

-- welcome email now quotes the reference (rewrite of the 096 version;
-- wording unchanged apart from the reference line)
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
      values (null, 'approved', 'Auto-approved volunteer registration '
        || coalesce(new.ref_no, ''), now());
    end if;

    perform send_email(new.email,
      coalesce(nullif(split_part(new.full_name, ' ', 1), ''), 'Volunteer'),
      'Your WODDI registration is received, provisionally approved',
      email_wrap('Welcome to WODDI',
        'Congratulations '
        || coalesce(nullif(split_part(new.full_name, ' ', 1), ''), '')
        || '! Your registration has been received and provisionally '
        || 'approved. Your application reference is '
        || coalesce(new.ref_no, 'being prepared')
        || '. Please keep it for any follow up. '
        || 'Your activation journey begins now.' || e'\n\n'
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

-- ---- #2a: the claim door recognises approved network volunteers ----------

create or replace function public.claim_check(em text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare app record; vol record;
begin
  em := lower(trim(em));
  if em = '' or position('@' in em) = 0 then
    return jsonb_build_object('eligible', false, 'reason', 'invalid');
  end if;

  if exists (select 1 from profiles where lower(email) = em) then
    if exists (select 1 from auth.users where lower(email) = em) then
      return jsonb_build_object('eligible', false, 'reason', 'has_account');
    end if;
    return jsonb_build_object('eligible', false,
                              'reason', 'use_volunteer_id');
  end if;

  select first_name into app from applications
   where lower(email) = em and status = 'approved'
   order by created_at desc limit 1;
  if app is not null then
    return jsonb_build_object('eligible', true, 'first_name', app.first_name);
  end if;

  -- the fix: an approved network volunteer registration is a full
  -- invitation, exactly as the approval email says
  select split_part(full_name, ' ', 1) as first_name into vol
    from volunteer_applications
   where lower(email) = em and status = 'approved'
   order by created_at desc limit 1;
  if vol is not null then
    return jsonb_build_object('eligible', true, 'first_name', vol.first_name);
  end if;

  if exists (select 1 from applications
              where lower(email) = em and status <> 'approved')
     or exists (select 1 from volunteer_applications
                 where lower(email) = em and status = 'submitted') then
    return jsonb_build_object('eligible', false, 'reason', 'pending_review');
  end if;

  return jsonb_build_object('eligible', false, 'reason', 'not_found');
end; $$;

-- ---- #2b: signup builds a real profile from the volunteer pipeline -------
-- Full rewrite of handle_new_user preserving migration 074's behaviour
-- exactly, with one new branch between the main-pipeline check and the
-- generic fallback.

create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public as $$
declare app public.applications; vol public.volunteer_applications;
begin
  begin
    select * into app
      from applications
     where lower(email) = lower(new.email) and status = 'approved'
     order by decided_at desc nulls last limit 1;
    if app.id is not null then
      insert into public.profiles
        (id, first_name, last_name, email, phone, network, org_unit_id,
         preferred_locale, status, membership_no)
      values
        (new.id,
         coalesce(nullif(app.first_name, ''), 'Volunteer'),
         coalesce(nullif(app.last_name, ''), '-'),
         new.email, app.phone,
         coalesce(app.network, 'WGMN'::public.network_code),
         coalesce(app.org_unit_id,
           (select id from org_units where level = 'headquarters'
             order by created_at limit 1)),
         coalesce(app.preferred_locale, 'en'), 'approved',
         coalesce(app.member_no, next_membership_no()))
      on conflict (id) do nothing;
      update applications set profile_id = new.id where id = app.id;
    else
      select * into vol
        from volunteer_applications
       where lower(email) = lower(new.email) and status = 'approved'
       order by decided_at desc nulls last limit 1;
      if vol.id is not null then
        insert into public.profiles
          (id, first_name, last_name, email, phone, network, org_unit_id,
           preferred_locale, status, membership_no)
        values
          (new.id,
           coalesce(nullif(split_part(vol.full_name, ' ', 1), ''), 'Volunteer'),
           coalesce(nullif(trim(substr(vol.full_name,
             length(split_part(vol.full_name, ' ', 1)) + 1)), ''), '-'),
           new.email, vol.phone,
           coalesce(vol.network, 'WGMN'::public.network_code),
           (select id from org_units where level = 'headquarters'
             order by created_at limit 1),
           'en', 'approved', next_membership_no())
        on conflict (id) do nothing;
      else
        insert into public.profiles (id, first_name, last_name, email, network)
        values (new.id,
          coalesce(new.raw_user_meta_data->>'first_name',''),
          coalesce(new.raw_user_meta_data->>'last_name',''),
          new.email,
          coalesce((new.raw_user_meta_data->>'network')::public.network_code,
            'WGMN'))
        on conflict (id) do nothing;
      end if;
    end if;
    perform apply_leader_directory(new.id);
  exception when others then
    raise exception 'WDOS claim failed for %: %', new.email, sqlerrm;
  end;
  return new;
end; $$;

-- ---- #8: the completion congratulations greets the person by name --------
-- Rewrite of try_finalize_activation (068) preserving its logic; only
-- the notice text is personalised.

create or replace function public.try_finalize_activation(jid uuid)
returns void language plpgsql
security definer set search_path = public as $$
declare j activation_journeys; ev record; fname text;
begin
  select * into j from activation_journeys where id = jid for update;
  if j.id is null or j.status <> 'in_progress' then return; end if;
  select * into ev from eval_activation(jid);
  if not ev.passed then return; end if;
  update activation_journeys
     set status = 'completed', completed_at = now()
   where id = jid;
  perform advance_status_on_pass(j.profile_id);
  select coalesce(nullif(first_name, ''), 'Volunteer') into fname
    from profiles where id = j.profile_id;
  insert into member_notices (profile_id, kind, title, body, meta)
  values (j.profile_id, 'journey_day',
    'Congratulations ' || fname
      || ', you passed your 14-day activation!',
    fname || ', the system has evaluated your journey: passed. Your '
    || 'account has been advanced automatically and your courses are '
    || 'open in the Learn section. Welcome aboard, and thank you for '
    || 'serving.',
    jsonb_build_object('activation', 'passed'));
end; $$;

insert into public.schema_migrations (version, name)
values (98, 'uat_round2_wdos_fixes') on conflict (version) do nothing;
