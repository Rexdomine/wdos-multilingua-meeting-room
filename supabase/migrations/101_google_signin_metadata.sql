-- ============================================================================
-- WDOS Migration 101 — Google sign-in support (Phase 119)
--
-- The app now offers "Continue with Google" on the sign-in and claim
-- pages. Google's identity payload names people via given_name,
-- family_name and full_name, while handle_new_user's generic branch
-- only read first_name/last_name (set by our own password signup).
-- This is the 098 handler verbatim with ONE change: the generic branch
-- now understands Google's fields too, so a Google sign-in lands with
-- the person's real name instead of blanks. The approved-application
-- and approved-volunteer branches are untouched: an approved person who
-- taps Google gets exactly the same full profile as before, because
-- matching runs on email, not on how the auth account was created.
-- ============================================================================

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
          coalesce(
            nullif(new.raw_user_meta_data->>'first_name', ''),
            nullif(new.raw_user_meta_data->>'given_name', ''),
            nullif(split_part(coalesce(
              new.raw_user_meta_data->>'full_name',
              new.raw_user_meta_data->>'name', ''), ' ', 1), ''),
            ''),
          coalesce(
            nullif(new.raw_user_meta_data->>'last_name', ''),
            nullif(new.raw_user_meta_data->>'family_name', ''),
            nullif(trim(substr(coalesce(
              new.raw_user_meta_data->>'full_name',
              new.raw_user_meta_data->>'name', ''),
              length(split_part(coalesce(
                new.raw_user_meta_data->>'full_name',
                new.raw_user_meta_data->>'name', ''), ' ', 1)) + 1)), ''),
            ''),
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

insert into public.schema_migrations (version, name)
values (101, 'google_signin_metadata') on conflict (version) do nothing;
