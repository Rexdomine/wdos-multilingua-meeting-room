-- ============================================================================
-- WDOS Migration 093 — Established leaders never belonged on this report
-- at all (Phase 105)
--
-- Confirmed via live diagnostic: 27 of 28 "Failed" rows on the 14-day
-- activation report were established leaders (is_leader = true) — real,
-- active Country Reps and State Coordinators — showing as failures on a
-- test they were never candidates in. Their journey rows sit at
-- status='deferred' because that is exactly what happens the moment
-- someone becomes an established leader (apply_leader_directory parks
-- any leftover journey, going all the way back to Phase 90's original
-- architecture: established leaders skip the 14-day activation
-- entirely). activation_report()'s WHERE clause never excluded them, so
-- every one of the 111+ established leaders with a leftover journey row
-- has been quietly showing up as a "failure" on HQ's own dashboard.
-- Only 1 of the 28 (Femi Ola) was a genuine, correctly-failed candidate —
-- her case stays exactly as it was; nothing about real failures changes.
-- ============================================================================

create or replace function public.activation_report()
returns jsonb language plpgsql
security definer set search_path = public as $$
begin
  if not is_case_hq() then raise exception 'HQ only'; end if;
  return (
    select coalesce(jsonb_agg(row order by row->>'name'), '[]'::jsonb)
    from (
      select jsonb_build_object(
        'id', p.id,
        'journey_id', j.id,
        'name', p.first_name || ' ' || p.last_name,
        'membership_no', p.membership_no,
        'role_applied', p.role_applied,
        'country', p.country,
        'state', p.state_region,
        'lga', p.lga,
        'profile_status', p.status::text,
        'journey_status', coalesce(j.status::text, 'not_started'),
        'started_at', j.started_at,
        'due_at', coalesce(j.extended_until, j.due_at),
        'day_reached', case when j.id is null then 0
          else least(14, greatest(1, floor(extract(epoch from
            (now() - j.started_at)) / 86400)::int + 1)) end,
        'items_done', coalesce((
          select count(*) from activation_item_responses r
            join activation_items i on i.id = r.item_id
           where r.journey_id = j.id and i.is_required), 0),
        'items_required', (select count(*) from activation_items
                            where is_required),
        'verdict', case
          when j.id is null then 'not_started'
          when j.status = 'completed' then 'passed'
          when j.status in ('incomplete', 'deferred') then 'failed'
          when now() > coalesce(j.extended_until, j.due_at) then 'failed'
          else 'in_progress' end,
        'report_ready', j.id is not null and j.status in ('completed','incomplete'),
        'has_cv', exists (select 1 from member_cvs c
                           where c.profile_id = p.id),
        'last_seen', p.last_seen_at
      ) as row
      from profiles p
      left join activation_journeys j on j.profile_id = p.id
      where p.merged_into is null
        and not coalesce(p.is_leader, false)
        and not exists (select 1 from staff st
                         where st.profile_id = p.id and st.is_active)
        and (j.id is not null
             or p.status in ('applicant', 'under_review', 'approved'))
    ) sub);
end; $$;
revoke execute on function public.activation_report() from anon;

insert into public.schema_migrations (version, name)
values (93, 'exclude_leaders_from_activation_report') on conflict (version) do nothing;
