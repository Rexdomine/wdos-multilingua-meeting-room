-- ============================================================================
-- WDOS Migration 017 — The Wall (Staff ≠ Field Members) + Staff Messaging
--
-- Correction of a design fault: HQ staff were appearing in the field
-- Members module as WGMN "applicants". From this migration on:
--   • network is OPTIONAL on a profile — HQ staff belong to no field
--     network unless they genuinely join one;
--   • the Members module (and membership statistics) read from the
--     field_members view, which EXCLUDES everyone on the active staff
--     register — the two ecosystems no longer mix;
--   • staff home unit is Headquarters, so HQ meetings and HQ tasks reach
--     them through the existing machinery;
--   • staff get person-to-person in-app messages (HQ side only).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Network becomes optional; current staff are detached from WGMN and
--    homed at Headquarters.
-- ---------------------------------------------------------------------------
alter table public.profiles alter column network drop not null;

update public.profiles p
   set network = null,
       org_unit_id = (select id from org_units where level = 'headquarters')
 where exists (select 1 from staff s
               where s.profile_id = p.id and s.is_active);

-- New-user bootstrap: no forced network for dashboard-created accounts.
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public as $$
declare app public.applications;
begin
  select * into app
    from applications
   where lower(email) = lower(new.email) and status = 'approved'
   order by decided_at desc limit 1;

  if app.id is not null then
    insert into public.profiles
      (id, first_name, last_name, email, phone, network, org_unit_id,
       preferred_locale, status)
    values
      (new.id, app.first_name, app.last_name, new.email, app.phone,
       app.network, app.org_unit_id, app.preferred_locale, 'approved');
    update applications set profile_id = new.id where id = app.id;
  else
    insert into public.profiles (id, first_name, last_name, email, network)
    values (
      new.id,
      left(coalesce(nullif(new.raw_user_meta_data->>'first_name',''),
                    initcap(split_part(new.email,'@',1))), 60),
      left(coalesce(nullif(new.raw_user_meta_data->>'last_name',''), '-'), 60),
      new.email,
      (new.raw_user_meta_data->>'network')::public.network_code  -- null unless stated
    );
  end if;
  return new;
end; $$;

-- Placing someone on staff homes them at HQ automatically.
create or replace function public.staff_home_at_hq()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update profiles
     set org_unit_id = (select id from org_units where level = 'headquarters')
   where id = new.profile_id and org_unit_id is null;
  return new;
end; $$;

drop trigger if exists staff_home_trg on public.staff;
create trigger staff_home_trg after insert on public.staff
  for each row execute function public.staff_home_at_hq();

-- ---------------------------------------------------------------------------
-- 2. THE WALL: field membership reads exclude active staff.
-- ---------------------------------------------------------------------------
create or replace view public.field_members
with (security_invoker = true) as
  select * from public.profiles p
  where not exists (select 1 from public.staff s
                    where s.profile_id = p.id and s.is_active);

grant select on public.field_members to authenticated;

-- Membership statistics: field members only.
create or replace function public.report_membership()
returns jsonb language plpgsql stable security invoker set search_path = public as $$
declare result jsonb;
begin
  select jsonb_build_object(
    'total', count(*),
    'wgmn',  count(*) filter (where network = 'WGMN'),
    'wnnn',  count(*) filter (where network = 'WNNN'),
    'active_family', count(*) filter (where status in
      ('activated','in_training','active','reinstated')),
    'pipeline', count(*) filter (where status in
      ('applicant','under_review','approved')),
    'by_status', (
      select coalesce(jsonb_object_agg(x.status, x.n), '{}'::jsonb)
      from (select status, count(*) n from field_members group by status) x
    )
  ) into result
  from field_members;
  return result;
end; $$;

create or replace function public.report_monthly_growth(months int default 6)
returns table (month text, joins bigint)
language sql stable security invoker set search_path = public as $$
  with series as (
    select date_trunc('month', now()) - (interval '1 month' * g) as m
    from generate_series(least(greatest(months,1),24) - 1, 0, -1) g
  )
  select to_char(s.m, 'YYYY-MM') as month,
         count(p.id) as joins
  from series s
  left join field_members p on date_trunc('month', p.created_at) = s.m
  group by s.m
  order by s.m;
$$;

-- ---------------------------------------------------------------------------
-- 3. STAFF MESSAGES (HQ side only; both parties must be active staff)
--    Deliberately NOT audited: private correspondence, not a governance
--    action. Sender and recipient alone can read.
-- ---------------------------------------------------------------------------
create table public.staff_messages (
  id           uuid primary key default gen_random_uuid(),
  sender_id    uuid not null references public.profiles(id) default auth.uid(),
  recipient_id uuid not null references public.profiles(id),
  body         text not null check (char_length(body) between 1 and 4000),
  read_at      timestamptz,
  created_at   timestamptz not null default now(),
  constraint no_self_message check (sender_id <> recipient_id)
);

create index staff_messages_inbox_idx
  on public.staff_messages (recipient_id, created_at desc);
create index staff_messages_sent_idx
  on public.staff_messages (sender_id, created_at desc);

create or replace function public.is_active_staff(pid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from staff where profile_id = pid and is_active);
$$;

alter table public.staff_messages enable row level security;

create policy staff_msg_read on public.staff_messages
  for select to authenticated
  using (sender_id = auth.uid() or recipient_id = auth.uid());

create policy staff_msg_send on public.staff_messages
  for insert to authenticated
  with check (
    sender_id = auth.uid()
    and (public.is_active_staff(auth.uid()) or public.is_case_hq())
    and public.is_active_staff(recipient_id)
  );

-- Recipient may mark as read (only read_at may change — guarded below).
create policy staff_msg_mark_read on public.staff_messages
  for update to authenticated
  using (recipient_id = auth.uid())
  with check (recipient_id = auth.uid());

create or replace function public.staff_msg_guard()
returns trigger language plpgsql as $$
begin
  if new.sender_id is distinct from old.sender_id
     or new.recipient_id is distinct from old.recipient_id
     or new.body is distinct from old.body
     or new.created_at is distinct from old.created_at then
    raise exception 'Messages cannot be edited';
  end if;
  return new;
end; $$;

create trigger staff_msg_guard_trg before update on public.staff_messages
  for each row execute function public.staff_msg_guard();

-- ---------------------------------------------------------------------------
-- 4. Logbook
-- ---------------------------------------------------------------------------
insert into public.schema_migrations (version, name)
values (17, 'staff_wall_and_messages') on conflict (version) do nothing;
