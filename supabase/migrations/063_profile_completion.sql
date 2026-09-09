-- ============================================================================
-- WDOS Migration 063 — Complete Your Profile, for real (Phase 75)
-- Profiles gain country / state / LGA / volunteer role fields. The cohort's
-- role is backfilled from their ID prefix. The Day-1 "Complete your profile"
-- task verifies against the fuller picture.
-- ============================================================================
alter table public.profiles
  add column if not exists country      text,
  add column if not exists state_region text,
  add column if not exists lga          text,
  add column if not exists role_applied text;

update public.profiles p
   set role_applied = case
     when p.membership_no ~ '^DCR\d'  then 'Deputy Country Representative'
     when p.membership_no ~ '^CR\d'   then 'Country Representative'
     when p.membership_no ~ '^DCL\d'  then 'Deputy Country Lead'
     when p.membership_no ~ '^CL\d'   then 'Country Lead'
     when p.membership_no ~ '^ASRC\d' then 'Assistant State/Regional Coordinator'
     when p.membership_no ~ '^SRC\d'  then 'State/Regional Coordinator'
     when p.membership_no ~ '^ALDC\d' then 'Assistant LGA/District Coordinator'
     when p.membership_no ~ '^LDC\d'  then 'LGA/District Coordinator'
     when p.membership_no ~ '^ACHL\d' then 'Assistant Chapter Lead'
     when p.membership_no ~ '^CHL\d'  then 'Chapter Lead'
     when p.membership_no ~ '^CA\d'   then 'Campus Ambassador'
     when p.membership_no ~ '^PM\d'   then 'Professional Mentor'
     when p.membership_no ~ '^VOL\d'  then 'Volunteer'
   end
 where p.role_applied is null
   and p.membership_no ~ '^(DCR|CR|DCL|CL|ASRC|SRC|ALDC|LDC|ACHL|CHL|CA|PM|VOL)\d';

insert into public.schema_migrations (version, name)
values (63, 'profile_completion') on conflict (version) do nothing;
