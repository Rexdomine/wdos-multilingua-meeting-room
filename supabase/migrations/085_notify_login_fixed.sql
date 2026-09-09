-- ============================================================================
-- WDOS Migration 085 — Tell everyone, not just the two we could name (Phase 96c)
--
-- Emmanuel and Anastasia were only the two people I could see. Both safety
-- nets (083 for the Institute form, 084 for the main site) release people
-- silently, in the background, with no separate "it's fixed now" message —
-- they were never designed to double as a support follow-up. This closes
-- that gap: everyone the safety net has ever released (marked by the
-- shared 'Approved on policy re-assertion' decision reason both functions
-- write) gets a warm, direct email confirming the issue is fixed and they
-- can sign in right now — distinct from the generic "you are approved"
-- email they already received, and sent to everyone affected, not a
-- hand-picked few.
-- ============================================================================

alter table public.applications
  add column if not exists fixed_notice_sent_at timestamptz;

create or replace function public.notify_login_fixed()
returns jsonb language plpgsql
security definer set search_path = public as $$
declare r record; n int := 0; failed jsonb := '[]'::jsonb;
begin
  if auth.uid() is not null and not is_case_hq() then
    raise exception 'HQ only';
  end if;

  for r in
    select id, first_name, email from applications
     where decision_reason ilike 'Approved on policy re-assertion%'
       and fixed_notice_sent_at is null
  loop
    begin
      perform send_email(r.email, r.first_name,
        'You can sign in now — the issue is fixed',
        email_wrap('You can sign in now',
          'Dear ' || r.first_name || ',' || e'\n\n'
          || 'A number of you told us you were stuck seeing "your '
          || 'application is with the review team" even after '
          || 'registering. We are sorry for the wait, and thank you for '
          || 'telling us.' || e'\n\n'
          || 'We found the reason and it is fixed. Your account is now '
          || 'approved.' || e'\n\n'
          || 'Please go to https://woddicrm.org, press "Claim your '
          || 'account", and enter the same email address you registered '
          || 'with.' || e'\n\n'
          || 'If you still see any trouble, simply reply to this email '
          || 'and we will look into your account personally.'
          || e'\n\n' || 'Thank you for your patience.' || e'\n'
          || 'The WODDI Team'));
      update applications set fixed_notice_sent_at = now() where id = r.id;
      n := n + 1;
    exception when others then
      failed := failed || jsonb_build_object('email', r.email, 'why', sqlerrm);
    end;
  end loop;
  return jsonb_build_object('emailed', n, 'failed', failed);
end; $$;
revoke execute on function public.notify_login_fixed() from anon;

-- send it now, to everyone released so far
select public.notify_login_fixed();

insert into public.schema_migrations (version, name)
values (85, 'notify_login_fixed') on conflict (version) do nothing;
