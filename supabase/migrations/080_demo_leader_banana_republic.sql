-- ============================================================================
-- WDOS Migration 080 — Demo Leader: Regina Okoro, Banana Republic (Phase 94)
--
-- Regina (Head of Field & Country Operations for WGMN + WNNN) wants to
-- test the ALREADY-ONBOARDED country-leader interface exactly as a real
-- Country Rep/DCR experiences it today — no 14-day activation, only the
-- courses, a badge showing country + position, and her own deputy.
--
-- This reuses 100% of the real leader architecture built in Phases 90/91/93
-- (leader_directory → applications → the claim machinery) rather than
-- inventing anything new — a demo country ("Banana Republic", reserved
-- ISO code XB, which real countries never use) with a Country Lead and a
-- Deputy Country Lead, seated exactly the way the 43 CR/DCRs were.
--
-- The one genuine departure: normally a leader chooses her own password
-- through the ID door. Here HQ needs to HAND OVER working credentials
-- directly, so this migration creates the Supabase Auth login itself
-- (the same technique already proven live in this project by the
-- sovereign password-reset feature, migration 062, which writes
-- extensions.crypt(...) straight into auth.users.encrypted_password).
-- Creating auth.users triggers on_auth_user_created exactly as a real
-- sign-up would — so handle_new_user() and apply_leader_directory() run
-- automatically and seat her for real. Nothing about her experience is
-- faked; only the password-creation step is done by HQ instead of by her.
-- ============================================================================

create extension if not exists pgcrypto with schema extensions;

-- 1 ▸ the demo country --------------------------------------------------
do $$
declare hq uuid;
begin
  select id into hq from org_units
   where level = 'headquarters' order by created_at limit 1;
  if not exists (select 1 from org_units
                  where level = 'country' and country_iso = 'XB') then
    insert into org_units (parent_id, level, name, country_iso)
    values (hq, 'country', 'Banana Republic', 'XB');
  end if;
end $$;

-- 2 ▸ the two demo leaders, seeded exactly like the real 43/68 --------------
insert into public.leader_directory
  (member_code, first_name, last_name, email, phone, country, role_applied)
values
  ('DEMO-CL-BANANA', 'Regina', 'Okoro', 'regina.demo@woddi-demo.invalid',
   '+234-000-000-0001', 'Banana Republic', 'Country Lead'),
  ('DEMO-DCL-BANANA', 'Demo', 'Deputy', 'deputy.demo@woddi-demo.invalid',
   '+234-000-000-0002', 'Banana Republic', 'Deputy Country Lead')
on conflict (member_code) do update
  set email = excluded.email, phone = excluded.phone;

do $$
declare d record; hq_unit uuid; app_id uuid;
begin
  perform set_config('wdos.system', '1', true);
  select id into hq_unit from org_units
   where level = 'headquarters' order by created_at limit 1;

  for d in select * from leader_directory
            where member_code in ('DEMO-CL-BANANA', 'DEMO-DCL-BANANA')
  loop
    select id into app_id from applications
     where lower(email) = lower(d.email) limit 1;
    if app_id is not null then
      update applications
         set member_no = d.member_code, status = 'approved',
             decision_reason = coalesce(decision_reason, 'Demo leader'),
             decided_at = coalesce(decided_at, now())
       where id = app_id;
    else
      insert into applications (first_name, last_name, email, phone,
        network, org_unit_id, motivation, status, decision_reason,
        decided_at, member_no)
      values (d.first_name, d.last_name, d.email, clean_phone(d.phone),
        'WGMN', hq_unit,
        safe_motivation('Demo leader account for interface testing.'),
        'approved', 'Demo leader \u2014 Banana Republic', now(),
        d.member_code);
    end if;
  end loop;
end $$;

-- 3 ▸ create the two logins directly \u2014 HQ hands these over, nobody claims
do $$
declare
  regina_id uuid := gen_random_uuid();
  deputy_id uuid := gen_random_uuid();
begin
  if exists (select 1 from auth.users
              where lower(email) = 'regina.demo@woddi-demo.invalid') then
    raise notice 'Regina demo login already exists \u2014 skipping creation';
  else
    insert into auth.users
      (id, instance_id, aud, role, email, encrypted_password,
       email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
       confirmation_token, recovery_token, email_change,
       email_change_token_new, is_super_admin, created_at, updated_at)
    values
      (regina_id, '00000000-0000-0000-0000-000000000000', 'authenticated',
       'authenticated', 'regina.demo@woddi-demo.invalid',
       extensions.crypt('BananaLead#2026', extensions.gen_salt('bf')),
       now(), '{"provider":"email","providers":["email"]}'::jsonb,
       '{}'::jsonb, '', '', '', '', false, now(), now());
    insert into auth.identities
      (id, provider_id, user_id, identity_data, provider,
       last_sign_in_at, created_at, updated_at)
    values
      (gen_random_uuid(), regina_id::text, regina_id,
       jsonb_build_object('sub', regina_id::text,
         'email', 'regina.demo@woddi-demo.invalid', 'email_verified', true),
       'email', now(), now(), now());
  end if;

  if exists (select 1 from auth.users
              where lower(email) = 'deputy.demo@woddi-demo.invalid') then
    raise notice 'Deputy demo login already exists \u2014 skipping creation';
  else
    insert into auth.users
      (id, instance_id, aud, role, email, encrypted_password,
       email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
       confirmation_token, recovery_token, email_change,
       email_change_token_new, is_super_admin, created_at, updated_at)
    values
      (deputy_id, '00000000-0000-0000-0000-000000000000', 'authenticated',
       'authenticated', 'deputy.demo@woddi-demo.invalid',
       extensions.crypt('BananaDeputy#26', extensions.gen_salt('bf')),
       now(), '{"provider":"email","providers":["email"]}'::jsonb,
       '{}'::jsonb, '', '', '', '', false, now(), now());
    insert into auth.identities
      (id, provider_id, user_id, identity_data, provider,
       last_sign_in_at, created_at, updated_at)
    values
      (gen_random_uuid(), deputy_id::text, deputy_id,
       jsonb_build_object('sub', deputy_id::text,
         'email', 'deputy.demo@woddi-demo.invalid', 'email_verified', true),
       'email', now(), now(), now());
  end if;
end $$;

-- 4 \u25b8 the demo "hurray, today is your birthday" notice --------------------
insert into member_notices (profile_id, kind, title, body)
select p.id, 'birthday', 'Happy birthday, Regina! \u{1F389}',
  'The whole WODDI family celebrates you today. Thank you for the light '
  || 'you bring \u2014 may this new year of your life overflow with grace, '
  || 'strength and joy. (Demo message \u2014 shown for interface testing.)'
  from profiles p where lower(p.email) = 'regina.demo@woddi-demo.invalid'
  and not exists (select 1 from member_notices mn
                   where mn.profile_id = p.id and mn.kind = 'birthday');

-- 5 \u25b8 verification \u2014 proof both accounts are real, seated leaders --------
select p.first_name || ' ' || p.last_name as leader,
       p.membership_no, p.role_applied, p.country, p.status,
       p.is_leader, ra.role as seated_as,
       (select count(*) from auth.users u
         where lower(u.email) = lower(p.email)) as has_login
  from profiles p
  left join role_assignments ra
    on ra.profile_id = p.id and ra.ends_at is null
 where p.email in ('regina.demo@woddi-demo.invalid',
                   'deputy.demo@woddi-demo.invalid')
 order by p.role_applied;

insert into public.schema_migrations (version, name)
values (80, 'demo_leader_banana_republic') on conflict (version) do nothing;
