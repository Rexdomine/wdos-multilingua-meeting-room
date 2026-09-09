-- ============================================================================
-- WDOS Migration 053 — New Home, Programme Calendar, Live Analytics (Phase 64)
--
-- 1. NEW HOME: emails now carry the real address — woddicrm.org — not the
--    old netlify link.
-- 2. PROGRAMME CALENDAR LOCK: the 14-day activation and the volunteer
--    courses open 3 Aug 2026, close 17 Aug, with grace until 24 Aug.
--    Before opening and after grace, marking/enrolment is refused with a
--    clear message (HQ can always act). Dates are org settings — movable
--    without code. In-flight journeys are re-dated to the window.
-- 3. LIVE PEOPLE ANALYTICS: people_analytics() returns, per person:
--    name, role/position, location (unit → country), journey progress
--    (done/required, day), courses (enrolled/completed), open+overdue
--    tasks, last seen. country_member_stats() feeds the Africa map.
-- ============================================================================

-- 1 ▸ the real home in every email
create or replace function public.volunteer_auto_approve()
returns trigger
language plpgsql security definer set search_path = public as $$
declare enabled boolean; hq_unit uuid;
begin
  select coalesce((value #>> '{}')::boolean, false) into enabled
    from org_settings where key = 'auto_approve_volunteers';
  if not enabled then return new; end if;
  if new.status is distinct from 'submitted' then return new; end if;
  begin
    select id into hq_unit from org_units
     where level = 'headquarters' order by created_at limit 1;
    update volunteer_applications
       set status = 'approved',
           decision_reason = 'Auto-approved on registration (org policy)',
           decided_at = now()
     where id = new.id;
    if not exists (select 1 from applications
                    where lower(email) = lower(new.email)) then
      insert into applications (first_name, last_name, email, phone, network,
        org_unit_id, motivation, status, decision_reason, decided_at)
      values (
        coalesce(nullif(split_part(new.full_name, ' ', 1), ''), 'Volunteer'),
        coalesce(nullif(trim(substr(new.full_name,
          length(split_part(new.full_name, ' ', 1)) + 1)), ''), '-'),
        new.email, new.phone, coalesce(new.network, 'WGMN'), hq_unit,
        coalesce(new.payload ->> 'why', ''),
        'approved', 'Auto-approved volunteer registration', now());
    end if;
    perform send_email(new.email,
      coalesce(nullif(split_part(new.full_name, ' ', 1), ''), 'Volunteer'),
      'Welcome to WODDI — you are approved!',
      email_wrap('You are approved!',
        'Thank you for registering to serve with WODDI. Your application '
        || 'has been approved.' || e'\n\n'
        || 'Create your login now and begin your activation journey:'
        || e'\n' || 'https://woddicrm.org/#/claim' || e'\n\n'
        || 'Use this same email address when creating your account. '
        || 'We are delighted to have you.'));
  exception when others then
    raise notice 'volunteer_auto_approve skipped for %: %', new.email, sqlerrm;
  end;
  return new;
end; $$;

create or replace function public.application_decided_mail()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'approved' and old.status is distinct from 'approved' then
    begin
      perform send_email(new.email,
        coalesce(nullif(new.first_name, ''), 'Friend'),
        'Welcome to WODDI — you are approved!',
        email_wrap('You are approved!',
          'Wonderful news, '
          || coalesce(nullif(new.first_name, ''), 'friend')
          || ' — your WODDI application has been approved.'
          || e'\n\nCreate your login now and begin your activation journey:'
          || e'\nhttps://woddicrm.org/#/claim'
          || e'\n\nUse this same email address when creating your account. '
          || 'We are delighted to have you.'));
    exception when others then
      raise notice 'application_decided_mail skipped for %: %',
        new.email, sqlerrm;
    end;
  end if;
  return new;
end; $$;

-- 2 ▸ programme calendar --------------------------------------------------
insert into public.org_settings (key, value) values
  ('programme_open',  '"2026-08-03"'::jsonb),
  ('programme_close', '"2026-08-17"'::jsonb),
  ('programme_grace', '"2026-08-24"'::jsonb)
on conflict (key) do nothing;

create or replace function public.programme_state()
returns text language sql stable
security definer set search_path = public as $$
  select case
    when current_date < coalesce((select (value #>> '{}')::date
      from org_settings where key = 'programme_open'), date '2026-08-03')
      then 'before'
    when current_date <= coalesce((select (value #>> '{}')::date
      from org_settings where key = 'programme_close'), date '2026-08-17')
      then 'open'
    when current_date <= coalesce((select (value #>> '{}')::date
      from org_settings where key = 'programme_grace'), date '2026-08-24')
      then 'grace'
    else 'closed'
  end;
$$;
grant execute on function public.programme_state() to authenticated;

create or replace function public.programme_gate()
returns trigger
language plpgsql security definer set search_path = public as $$
declare st text;
begin
  if is_case_hq() then return new; end if;
  st := programme_state();
  if st = 'before' then
    raise exception 'This programme opens on 3 August 2026 — see you then!';
  elsif st = 'closed' then
    raise exception 'This programme closed on 24 August 2026. Contact HQ if you need help.';
  end if;
  return new;
end; $$;

drop trigger if exists gate_journey_marks on public.activation_item_responses;
create trigger gate_journey_marks
  before insert or update on public.activation_item_responses
  for each row execute function public.programme_gate();

drop trigger if exists gate_course_enrol on public.course_enrollments;
create trigger gate_course_enrol
  before insert on public.course_enrollments
  for each row execute function public.programme_gate();

drop trigger if exists gate_course_passes on public.course_module_passes;
create trigger gate_course_passes
  before insert on public.course_module_passes
  for each row execute function public.programme_gate();

-- re-date journeys that are in flight or created before the window
update public.activation_journeys
   set due_at = timestamptz '2026-08-17 23:59:59+01',
       extended_until = null
 where status = 'in_progress';

-- 3 ▸ live people analytics ------------------------------------------------
create or replace function public.unit_country_name(uid uuid)
returns text language sql stable
security definer set search_path = public as $$
  with recursive up as (
    select id, parent_id, name, level from org_units where id = uid
    union all
    select o.id, o.parent_id, o.name, o.level
      from org_units o join up on o.id = up.parent_id
  )
  select coalesce(
    (select name from up where level = 'country' limit 1),
    (select name from up where level = 'headquarters' limit 1),
    (select name from org_units where id = uid));
$$;

create or replace function public.people_analytics()
returns jsonb language plpgsql security definer
set search_path = public as $$
begin
  if not is_case_hq() then raise exception 'HQ only'; end if;
  return (
    select coalesce(jsonb_agg(row order by row->>'name'), '[]'::jsonb)
    from (
      select jsonb_build_object(
        'id', p.id,
        'name', p.first_name || ' ' || p.last_name,
        'role', coalesce(
          (select st.position_title from staff st
            where st.profile_id = p.id and st.is_active limit 1),
          (select initcap(replace(ra.role::text, '_', ' '))
             from role_assignments ra
            where ra.profile_id = p.id and ra.ends_at is null
            order by ra.starts_at limit 1),
          initcap(replace(p.status::text, '_', ' '))),
        'network', p.network,
        'unit', (select name from org_units where id = p.org_unit_id),
        'country', unit_country_name(p.org_unit_id),
        'is_staff', exists (select 1 from staff st
                             where st.profile_id = p.id and st.is_active),
        'journey_status', (select j.status::text from activation_journeys j
                            where j.profile_id = p.id limit 1),
        'journey_done', (select count(*) from activation_item_responses r
                          join activation_journeys j2 on j2.id = r.journey_id
                         where j2.profile_id = p.id and r.done),
        'journey_required', (select count(*) from activation_milestones m
                              where m.required),
        'journey_day', (select least(14, greatest(1,
            floor(extract(epoch from (now() - j3.started_at)) / 86400)::int + 1))
          from activation_journeys j3
         where j3.profile_id = p.id and j3.status = 'in_progress' limit 1),
        'courses_enrolled', (select count(*) from course_enrollments ce
                              where ce.profile_id = p.id),
        'courses_done', (select count(*) from course_enrollments ce
                          where ce.profile_id = p.id
                            and ce.completed_at is not null),
        'tasks_open', (select count(*) from tasks tk
                        where tk.assigned_to = p.id
                          and tk.status in ('not_started','in_progress')),
        'tasks_overdue', (select count(*) from tasks tk
                           where tk.assigned_to = p.id
                             and tk.status in ('not_started','in_progress')
                             and tk.due_on is not null
                             and tk.due_on < current_date),
        'last_seen', p.last_seen_at
      ) as row
      from profiles p
      where p.merged_into is null
        and (p.status in ('approved','activated','in_training',
                          'active','reinstated')
             or exists (select 1 from staff st
                         where st.profile_id = p.id and st.is_active))
    ) sub);
end; $$;
revoke execute on function public.people_analytics() from anon;

create or replace function public.country_member_stats()
returns jsonb language plpgsql security definer
set search_path = public as $$
begin
  if not is_case_hq() then raise exception 'HQ only'; end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'iso', iso, 'name', name, 'members', n)), '[]'::jsonb)
    from (
      select cu.country_iso as iso, cu.name, count(p.id) as n
        from profiles p
        join lateral (
          with recursive up as (
            select id, parent_id, name, level, country_iso
              from org_units where id = p.org_unit_id
            union all
            select o.id, o.parent_id, o.name, o.level, o.country_iso
              from org_units o join up on o.id = up.parent_id
          )
          select name, country_iso from up
           where level = 'country' limit 1
        ) cu on true
       where p.merged_into is null
         and p.status in ('approved','activated','in_training',
                          'active','reinstated')
       group by cu.country_iso, cu.name
    ) s);
end; $$;
revoke execute on function public.country_member_stats() from anon;

insert into public.schema_migrations (version, name)
values (53, 'new_home_calendar_analytics') on conflict (version) do nothing;
