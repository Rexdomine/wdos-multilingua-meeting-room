-- ============================================================================
-- WDOS Migration 065 — Volunteer Leadership overview (Phase 86)
-- One HQ view of the continental spine: every CR/DCR (WGMN) and CL/DCL
-- (WNNN), claimed or still invited, with country, journey progress and
-- last activity — feeding the Volunteer Leadership page and its live map.
-- ============================================================================
create or replace function public.leadership_overview()
returns table (
  source        text,
  network       text,
  country       text,
  member_no     text,
  full_name     text,
  email         text,
  role_title    text,
  journey_status text,
  done_required int,
  required_total int,
  due_at        timestamptz,
  last_active   timestamptz
)
language sql stable
security definer set search_path = public as $$
  with req as (
    select count(*)::int as n from activation_milestones where is_required
  ),
  claimed as (
    select 'claimed'::text as source,
           case when p.membership_no ~ '^(CR|DCR)\d' then 'WGMN'
                else 'WNNN' end as network,
           coalesce(p.country, a.country, '—') as country,
           p.membership_no as member_no,
           (p.first_name || ' ' || p.last_name) as full_name,
           p.email,
           case
             when p.membership_no ~ '^DCR\d' then 'Deputy Country Representative'
             when p.membership_no ~ '^CR\d'  then 'Country Representative'
             when p.membership_no ~ '^DCL\d' then 'Deputy Country Lead'
             else 'Country Lead' end as role_title,
           coalesce(j.status::text, 'not_started') as journey_status,
           coalesce((select count(*)::int from activation_progress g
                      join activation_milestones m on m.id = g.milestone_id
                     where g.journey_id = j.id and m.is_required), 0)
             as done_required,
           (select n from req) as required_total,
           coalesce(j.extended_until, j.due_at) as due_at,
           greatest(
             coalesce((select max(r.submitted_at)
                         from activation_item_responses r
                        where r.journey_id = j.id), 'epoch'),
             coalesce(j.started_at, 'epoch')
           ) as last_active
      from profiles p
      left join applications a on a.profile_id = p.id
      left join activation_journeys j
             on j.profile_id = p.id
     where p.membership_no ~ '^(CR|DCR|CL|DCL)\d'
       and p.merged_into is null
  ),
  invited as (
    select 'invited'::text,
           case when ap.member_no ~ '^(CR|DCR)\d' then 'WGMN'
                else 'WNNN' end,
           coalesce(ap.country, '—'),
           ap.member_no,
           (ap.first_name || ' ' || ap.last_name),
           ap.email,
           case
             when ap.member_no ~ '^DCR\d' then 'Deputy Country Representative'
             when ap.member_no ~ '^CR\d'  then 'Country Representative'
             when ap.member_no ~ '^DCL\d' then 'Deputy Country Lead'
             else 'Country Lead' end,
           'invited', 0, (select n from req), null::timestamptz,
           ap.decided_at
      from applications ap
     where ap.member_no ~ '^(CR|DCR|CL|DCL)\d'
       and ap.profile_id is null
       and ap.status = 'approved'
  )
  select * from (
    select * from claimed
    union all
    select * from invited
  ) z
  where is_case_hq()
$$;
grant execute on function public.leadership_overview() to authenticated;
revoke execute on function public.leadership_overview() from anon, public;

insert into public.schema_migrations (version, name)
values (65, 'leadership_overview') on conflict (version) do nothing;
