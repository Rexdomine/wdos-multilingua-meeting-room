-- ============================================================================
-- WDOS Migration 040 — Claim-flow hotfix (Phase 44.1)
--
-- Account creation must NEVER fail because enrichment hiccuped. The enrich
-- trigger is now fully exception-guarded: if anything in the fill-from-
-- application or status walk fails, the account is still created (the
-- profile simply stays at applicant for HQ to advance manually) and the
-- problem is logged as a notice instead of rolling back the signup.
-- Also links the application to the new profile (applications.profile_id).
-- ============================================================================

create or replace function public.claim_enrich()
returns trigger
language plpgsql security definer set search_path = public as $$
declare app record;
begin
  begin
    select * into app from applications
     where lower(email) = lower(new.email) and status = 'approved'
     order by created_at desc limit 1;
    if app.id is null then return new; end if;

    update profiles set
      first_name = coalesce(nullif(app.first_name, ''), first_name),
      last_name  = coalesce(nullif(app.last_name, ''), last_name),
      phone      = coalesce(phone, app.phone),
      network    = coalesce(network, app.network),
      org_unit_id = coalesce(org_unit_id, app.org_unit_id),
      preferred_locale = coalesce(app.preferred_locale, preferred_locale)
     where id = new.id;

    update applications set profile_id = new.id where id = app.id;

    update profiles set status = 'under_review'
     where id = new.id and status = 'applicant';
    update profiles set status = 'approved'
     where id = new.id and status = 'under_review';
  exception when others then
    raise notice 'claim_enrich skipped for %: %', new.email, sqlerrm;
  end;
  return new;
end; $$;

insert into public.schema_migrations (version, name)
values (40, 'claim_hotfix') on conflict (version) do nothing;
