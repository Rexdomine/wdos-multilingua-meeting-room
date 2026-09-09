-- ============================================================================
-- WDOS Migration 008 — Reporting
-- All functions are SECURITY INVOKER: they run as the viewer, so Row Level
-- Security scopes every figure automatically. A Chapter Lead's report covers
-- her chapter; HQ's covers the organisation. Same code, different scope.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Membership: counts by status and by network
-- ---------------------------------------------------------------------------
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
      from (select status, count(*) n from profiles group by status) x
    )
  ) into result
  from profiles;
  return result;
end; $$;

-- ---------------------------------------------------------------------------
-- 2. Monthly growth: profiles created per month, last N months
-- ---------------------------------------------------------------------------
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
  left join profiles p on date_trunc('month', p.created_at) = s.m
  group by s.m
  order by s.m;
$$;

-- ---------------------------------------------------------------------------
-- 3. Recruitment funnel
-- ---------------------------------------------------------------------------
create or replace function public.report_recruitment()
returns jsonb language sql stable security invoker set search_path = public as $$
  select jsonb_build_object(
    'total', count(*),
    'open', count(*) filter (where status in
      ('submitted','under_review','recommended')),
    'approved', count(*) filter (where status = 'approved'),
    'rejected', count(*) filter (where status = 'rejected'),
    'by_status', (
      select coalesce(jsonb_object_agg(x.status, x.n), '{}'::jsonb)
      from (select status, count(*) n from applications group by status) x
    )
  )
  from applications;
$$;

-- ---------------------------------------------------------------------------
-- 4. Tasks health (window in days)
-- ---------------------------------------------------------------------------
create or replace function public.report_tasks(days int default 30)
returns jsonb language sql stable security invoker set search_path = public as $$
  select jsonb_build_object(
    'open', count(*) filter (where status in
      ('not_started','in_progress','awaiting_review')),
    'overdue', count(*) filter (where status in
      ('not_started','in_progress','awaiting_review')
      and due_on is not null and due_on < current_date),
    'awaiting_review', count(*) filter (where status = 'awaiting_review'),
    'completed_window', count(*) filter (where status = 'completed'
      and completed_at >= now() - make_interval(days => least(greatest(days,1),365)))
  )
  from tasks;
$$;

-- ---------------------------------------------------------------------------
-- 5. Meetings & attendance (window in days)
-- ---------------------------------------------------------------------------
create or replace function public.report_meetings(days int default 30)
returns jsonb language sql stable security invoker set search_path = public as $$
  with window_meetings as (
    select id from meetings
    where status = 'completed'
      and starts_at >= now() - make_interval(days => least(greatest(days,1),365))
  ),
  marks as (
    select a.present
    from meeting_attendance a
    join window_meetings w on w.id = a.meeting_id
  )
  select jsonb_build_object(
    'held', (select count(*) from window_meetings),
    'scheduled_upcoming', (select count(*) from meetings
      where status = 'scheduled' and starts_at >= now()),
    'marks', (select count(*) from marks),
    'present', (select count(*) filter (where present) from marks)
  );
$$;

-- ---------------------------------------------------------------------------
-- 6. Leadership coverage by level: units with at least one active leader
-- ---------------------------------------------------------------------------
create or replace function public.report_leadership_coverage()
returns table (level public.org_level, units bigint, covered bigint)
language sql stable security invoker set search_path = public as $$
  select o.level,
         count(*) as units,
         count(*) filter (where exists (
           select 1 from role_assignments ra
           where ra.org_unit_id = o.id and ra.ends_at is null
             and role_rank(ra.role) <= 8
         )) as covered
  from org_units o
  where o.is_active and o.level <> 'headquarters'
  group by o.level
  order by case o.level
    when 'country' then 1 when 'state_region' then 2
    when 'district_lga' then 3 when 'chapter' then 4 else 5 end;
$$;
