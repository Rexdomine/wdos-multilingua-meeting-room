-- ============================================================================
-- WDOS Migration 062 — Sovereign Reset & Programme Discipline (Phase 74)
-- 1. Password reset now belongs to WODDI: our token, our Brevo email, our
--    reset screen — zero dependence on the auth server's SMTP.
-- 2. Automated notification emails hold their fire until the programme
--    opens (3 Aug); they flow during the window and grace.
-- 3. Country leaders (CR/DCR/CL/DCL) receive their formal roles.
-- 4. Test entries are swept from the volunteer application lists.
-- ============================================================================

create extension if not exists pgcrypto with schema extensions;

-- 1 ▸ sovereign password reset --------------------------------------------
create table if not exists public.password_resets (
  token      uuid primary key default gen_random_uuid(),
  email      text not null,
  created_at timestamptz not null default now(),
  used_at    timestamptz
);
alter table public.password_resets enable row level security;
-- no policies: only definer functions touch it

create or replace function public.request_password_reset(em text)
returns boolean
language plpgsql security definer set search_path = public as $$
declare tk uuid; nm text;
begin
  select first_name into nm from profiles
   where lower(email) = lower(trim(em)) and merged_into is null limit 1;
  if nm is null then
    select first_name into nm from applications
     where lower(email) = lower(trim(em)) and status = 'approved' limit 1;
  end if;
  if nm is null then
    return true;  -- never reveal whether an email exists
  end if;
  insert into password_resets (email) values (lower(trim(em)))
  returning token into tk;
  perform send_email(lower(trim(em)), coalesce(nullif(nm, ''), 'Friend'),
    'Reset your WODDI password',
    email_wrap('Reset your password',
      'Someone (hopefully you) asked to reset the WODDI password for this '
      || 'address. Set a new one here within 30 minutes:'
      || e'\n\nhttps://woddicrm.org/reset?tk=' || tk::text
      || e'\n\nIf this was not you, simply ignore this email — nothing '
      || 'changes without the link.'));
  return true;
end; $$;
grant execute on function public.request_password_reset(text)
  to anon, authenticated;

create or replace function public.complete_password_reset(tk uuid, newpw text)
returns boolean
language plpgsql security definer set search_path = public as $$
declare r record; uid uuid;
begin
  if length(coalesce(newpw, '')) < 8 then
    raise exception 'Password must be at least 8 characters.';
  end if;
  select * into r from password_resets
   where token = tk and used_at is null
     and created_at > now() - interval '30 minutes';
  if r.token is null then
    raise exception 'This reset link is invalid or has expired — request a new one.';
  end if;
  select id into uid from auth.users
   where lower(email) = lower(r.email) limit 1;
  if uid is null then
    raise exception 'No account exists yet for this email — use your claim link or ID number first.';
  end if;
  update auth.users
     set encrypted_password = extensions.crypt(newpw, extensions.gen_salt('bf')),
         email_confirmed_at = coalesce(email_confirmed_at, now()),
         updated_at = now()
   where id = uid;
  update password_resets set used_at = now() where token = tk;
  return true;
end; $$;
grant execute on function public.complete_password_reset(uuid, text)
  to anon, authenticated;

-- 2 ▸ automated emails wait for the programme ------------------------------
drop function if exists public.run_automations_guarded();
create or replace function public.run_automations_guarded()
returns void
language plpgsql security definer set search_path = public as $$
begin
  if programme_state() = 'before' then
    return;  -- the machine wakes on 3 August 2026
  end if;
  perform run_automations();
exception when others then
  raise notice 'run_automations skipped: %', sqlerrm;
end; $$;

-- 3 ▸ country leaders receive their roles ----------------------------------
insert into public.role_assignments (profile_id, role, org_unit_id, starts_at)
select p.id,
       case
         when p.membership_no ~ '^DCR\d' then 'deputy_country_rep'
         when p.membership_no ~ '^DCL\d' then 'deputy_country_rep'
         when p.membership_no ~ '^CR\d'  then 'country_rep'
         when p.membership_no ~ '^CL\d'  then 'country_rep'
       end::public.role_code,
       p.org_unit_id,
       now()
  from profiles p
 where p.membership_no ~ '^(CR|CL|DCR|DCL)\d'
   and p.merged_into is null
   and not exists (
     select 1 from role_assignments ra
      where ra.profile_id = p.id
        and ra.role in ('country_rep', 'deputy_country_rep')
        and ra.ends_at is null);

-- 4 ▸ sweep the test entries (edit this list freely, then re-run) ----------
do $$
declare test_emails text[] := array[
  'woddingo@gmail.com',
  'woddi.org@gmail.com',
  'femiayor@gmail.com',
  'craigfunds@gmail.com',
  'hhhhj@gmail.com',
  'nigeriawoddi@gmail.com'
];
begin
  delete from volunteer_applications
   where lower(email) = any (test_emails);
  delete from applications
   where lower(email) = any (test_emails)
     and profile_id is null;
  raise notice 'test entries swept';
end $$;

insert into public.schema_migrations (version, name)
values (62, 'sovereign_reset_discipline') on conflict (version) do nothing;
