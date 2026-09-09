-- ============================================================================
-- WDOS Migration 102 — signup never fails on a missing name
--
-- Creating a user from the Supabase Auth dashboard (no name metadata)
-- failed with "Database error creating new user": the signup trigger
-- built a profile with EMPTY names and the profiles table requires at
-- least one character. Every other door (forms, Google) sends names, so
-- this path had never been exercised. This is the 101 handler verbatim
-- with ONE change: when no name is available anywhere, the generic branch
-- uses the email's local part as a first name and '-' as a last name, so
-- the account is created and HQ fills in the real names afterwards
-- (as the Regina provisioning script does).
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
            nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
            'Member'),
          coalesce(
            nullif(new.raw_user_meta_data->>'last_name', ''),
            nullif(new.raw_user_meta_data->>'family_name', ''),
            nullif(trim(substr(coalesce(
              new.raw_user_meta_data->>'full_name',
              new.raw_user_meta_data->>'name', ''),
              length(split_part(coalesce(
                new.raw_user_meta_data->>'full_name',
                new.raw_user_meta_data->>'name', ''), ' ', 1)) + 1)), ''),
            '-'),
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
values (102, 'signup_name_fallback') on conflict (version) do nothing;
