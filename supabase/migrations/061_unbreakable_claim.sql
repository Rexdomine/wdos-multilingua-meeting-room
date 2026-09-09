-- ============================================================================
-- WDOS Migration 061 — Unbreakable claim (Phase 73.1)
-- FILE BACKFILL: this SQL was applied live on 2026-07-30 as part of the
-- consolidated "master fix" paste, which inserted version 61 into
-- schema_migrations — but the file itself was never added to the folder,
-- leaving a numbering gap that made fresh rebuilds impossible and was
-- rightly flagged by the Phase-86 audit (§1.2). Idempotent; safe to re-run.
-- ============================================================================
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public as $$
declare app public.applications;
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
      insert into public.profiles (id, first_name, last_name, email, network)
      values (new.id,
        coalesce(new.raw_user_meta_data->>'first_name',''),
        coalesce(new.raw_user_meta_data->>'last_name',''),
        new.email,
        coalesce((new.raw_user_meta_data->>'network')::public.network_code,
          'WGMN'))
      on conflict (id) do nothing;
    end if;
  exception when others then
    raise exception 'WDOS claim failed for %: %', new.email, sqlerrm;
  end;
  return new;
end; $$;

insert into public.schema_migrations (version, name)
values (61, 'unbreakable_claim') on conflict (version) do nothing;
