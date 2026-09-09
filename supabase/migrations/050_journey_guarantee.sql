-- ============================================================================
-- WDOS Migration 050 — Journey Guarantee (Phase 55)
--
-- Craig's case: registered → auto-approved → claimed → logged in… and "No
-- activation yet". The journey only started when the profile's status
-- walked to Approved inside claim_enrich, and any hiccup there was
-- swallowed silently. From now on the claim path creates the journey
-- DIRECTLY (belt and braces), and this migration also repairs anyone
-- already stuck: every claimed profile matching an approved application
-- is walked to Approved and given their 14-day journey on the spot.
-- ============================================================================

-- 1 ▸ claim_enrich v3: status walk + guaranteed journey
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

    -- belt and braces: the journey must exist even if the walk above
    -- was blocked for any reason
    insert into activation_journeys (profile_id)
    values (new.id)
    on conflict (profile_id) do nothing;
  exception when others then
    raise notice 'claim_enrich skipped for %: %', new.email, sqlerrm;
  end;
  return new;
end; $$;

drop trigger if exists claim_enrich_trg on public.profiles;
create trigger claim_enrich_trg
  after insert on public.profiles
  for each row execute function public.claim_enrich();

-- 2 ▸ repair everyone already stuck (idempotent, plain statements)
update public.profiles p set status = 'under_review'
 where p.status = 'applicant'
   and exists (select 1 from public.applications a
                where lower(a.email) = lower(p.email)
                  and a.status = 'approved');

update public.profiles p set status = 'approved'
 where p.status = 'under_review'
   and exists (select 1 from public.applications a
                where lower(a.email) = lower(p.email)
                  and a.status = 'approved');

insert into public.activation_journeys (profile_id)
select p.id from public.profiles p
 where p.status in ('approved')
   and p.merged_into is null
   and exists (select 1 from public.applications a
                where lower(a.email) = lower(p.email)
                  and a.status = 'approved')
   and not exists (select 1 from public.activation_journeys j
                    where j.profile_id = p.id)
   and not exists (select 1 from public.staff s
                    where s.profile_id = p.id and s.is_active)
on conflict (profile_id) do nothing;

-- see who was repaired
select p.first_name, p.last_name, p.status,
       (select count(*) from public.activation_journeys j
         where j.profile_id = p.id) as has_journey
  from public.profiles p
 where p.created_at > now() - interval '3 days'
 order by p.created_at desc;

insert into public.schema_migrations (version, name)
values (50, 'journey_guarantee') on conflict (version) do nothing;
