-- ============================================================================
-- WDOS Migration 084 — The OTHER queue (Phase 96b)
--
-- The Gmail alert screenshot named the real gap precisely: "72 membership
-- application(s) have waited more than 7 days for review." That alert
-- (migration 031/042, code 'stale_application') watches the public.applications
-- table — the main WODDI website's own apply form. Every fix so far
-- (048, 074, 076, 083) only ever touched public.volunteer_applications (the
-- Institute's separate form) and its sync into applications. The main
-- site's OWN applicants were never covered by any auto-approve mechanism
-- at all — this queue was always meant to be reviewed by a human via
-- Recruitment, and with nobody keeping pace, 72 real people (very likely
-- including Emmanuel and Anastasia from the screenshots) have simply been
-- waiting, unapproved, invisibly, exactly as the original volunteer queue
-- once did.
--
-- Matching the house policy already set in Phase 90 (instant approval,
-- the 14-day activation is the real judgment) rather than manual
-- gatekeeping: this queue now gets the same treatment. Released rows send
-- the same "Welcome to WODDI — you are approved!" email already proven
-- for the other pipeline, so nobody needs a separate manual follow-up.
-- ============================================================================

create or replace function public.approve_stuck_applications()
returns jsonb language plpgsql
security definer set search_path = public as $$
declare r record; n int := 0; failed jsonb := '[]'::jsonb;
begin
  if auth.uid() is not null and not is_case_hq() then
    raise exception 'HQ only';
  end if;

  for r in select * from applications
            where status in ('submitted', 'under_review')
  loop
    begin
      update applications
         set status = 'approved',
             decision_reason = coalesce(decision_reason,
               'Approved on policy re-assertion — instant approval'),
             decided_at = now()
       where id = r.id;

      perform send_email(r.email, r.first_name,
        'Welcome to WODDI — you are approved!',
        email_wrap('You are approved!',
          'Thank you for registering to serve with WODDI. Your '
          || 'application has been approved.' || e'\n\n'
          || 'Create your login now and begin your activation journey:'
          || e'\n' || 'https://woddicrm.org/#/claim' || e'\n\n'
          || 'Use this same email address when creating your account. '
          || 'We are delighted to have you.'));
      n := n + 1;
    exception when others then
      failed := failed || jsonb_build_object('email', r.email, 'why', sqlerrm);
    end;
  end loop;
  return jsonb_build_object('released', n, 'failed', failed);
end; $$;
revoke execute on function public.approve_stuck_applications() from anon;

-- fold into the SAME 15-minute safety net already built in 083, so this
-- queue can never again silently pile up unreviewed
create or replace function public.scheduled_registration_release()
returns jsonb language plpgsql
security definer set search_path = public as $$
declare vol_result jsonb; app_result jsonb;
begin
  select public.approve_stuck_registrations() into vol_result;
  select public.approve_stuck_applications() into app_result;
  insert into registration_repair_log (released, failed)
  values (
    coalesce((vol_result ->> 'released')::int, 0)
      + coalesce((app_result ->> 'released')::int, 0),
    coalesce(vol_result -> 'failed', '[]'::jsonb)
      || coalesce(app_result -> 'failed', '[]'::jsonb)
  );
  return jsonb_build_object('volunteer_queue', vol_result,
                            'applications_queue', app_result);
end; $$;
revoke execute on function public.scheduled_registration_release() from anon;

-- release the 72-person backlog right now, immediately
select public.scheduled_registration_release();

-- name Emmanuel and Anastasia specifically, so we can see their exact
-- outcome rather than trusting the aggregate count alone
select first_name, last_name, email, status, decided_at
  from applications
 where lower(email) in ('emmanuelawoyemi917@gmail.com',
                        'anastasiaadaobinweke@gmail.com');

insert into public.schema_migrations (version, name)
values (84, 'applications_queue_safety_net') on conflict (version) do nothing;
