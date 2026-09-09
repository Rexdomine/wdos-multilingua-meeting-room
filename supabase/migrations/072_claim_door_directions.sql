-- ============================================================================
-- WDOS Migration 072 — The claim door learns to give directions (Phase 89h)
-- Launch-day incident: cohort members onboarded with Volunteer IDs are
-- trying the email "Claim your account" door. The old check answered
-- 'has_account' for anyone with a profile — even people who have never
-- created a login — sending them into a sign-in/reset loop with no exit.
-- Now the check tells the truth in four directions:
--   · has_account      → profile AND a real login exist → go sign in
--   · use_volunteer_id → profile exists but no login yet → the ID door
--   · pending_review   → an application is with the review team
--   · not_found        → nothing on file under this email
-- ============================================================================

create or replace function public.claim_check(em text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare app record;
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

  if exists (select 1 from applications
              where lower(email) = em and status <> 'approved')
     or exists (select 1 from volunteer_applications
                 where lower(email) = em and status = 'submitted') then
    return jsonb_build_object('eligible', false, 'reason', 'pending_review');
  end if;

  return jsonb_build_object('eligible', false, 'reason', 'not_found');
end; $$;

revoke all on function public.claim_check(text) from public;
grant execute on function public.claim_check(text) to anon, authenticated;

insert into public.schema_migrations (version, name)
values (72, 'claim_door_directions') on conflict (version) do nothing;
