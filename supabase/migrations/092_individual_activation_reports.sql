-- ============================================================================
-- WDOS Migration 092 — Individual Activation Reports, Not a Running
-- Warning Badge (Phase 104)
--
-- Azeez's directive: no more "Hard gate — needs review" flashing at
-- candidates while they're still mid-journey. Instead: once a candidate
-- FINISHES (passes or fails, journey concluded), HQ gets a proper
-- individual report — a day-by-day picture of what she actually did, and
-- a plain-language recommendation. The hard-gate LOGIC itself (Day 6
-- safeguarding, Day 13 commitment) still matters and still governs the
-- recommendation — it just no longer shows up as an alarming live badge
-- while someone is still on Day 7 with 7 days left to go.
-- ============================================================================

create or replace function public.activation_individual_report(jid uuid)
returns jsonb language plpgsql stable
security definer set search_path = public as $$
declare
  j activation_journeys; p profiles; gates record; ws jsonb;
  days jsonb; recommendation text;
begin
  if not is_case_hq() then raise exception 'HQ only'; end if;

  select * into j from activation_journeys where id = jid;
  if j.id is null then
    return jsonb_build_object('error', 'journey not found');
  end if;
  select * into p from profiles where id = j.profile_id;
  select * into gates from eval_activation(jid);
  ws := activation_weighted_score(jid);

  -- day-by-day picture: on time / late / missed / not yet reached --------
  select coalesce(jsonb_agg(jsonb_build_object(
      'day', d.day_no,
      'required_items', d.req_count,
      'completed_items', coalesce(d.done_count, 0),
      'status', case
        when d.req_count = 0 then 'no_required_work'
        when d.done_count is null or d.done_count = 0 then
          case when j.status in ('completed','incomplete')
                 or d.day_no < extract(epoch from (now() - j.started_at))/86400 + 1
               then 'missed' else 'not_yet_reached' end
        when d.done_count < d.req_count then 'partially_done'
        when d.on_time then 'completed_on_time'
        else 'completed_late'
      end
    ) order by d.day_no), '[]'::jsonb)
    into days
  from (
    select gs.day_no,
           (select count(*) from activation_items i
             where i.day = gs.day_no and i.is_required) as req_count,
           (select count(*) from activation_items i
             join activation_item_responses r
               on r.item_id = i.id and r.journey_id = jid
            where i.day = gs.day_no and i.is_required) as done_count,
           (select bool_and(r.submitted_at <= j.started_at
                            + make_interval(days => gs.day_no))
              from activation_items i
              join activation_item_responses r
                on r.item_id = i.id and r.journey_id = jid
             where i.day = gs.day_no and i.is_required) as on_time
      from generate_series(1, 14) as gs(day_no)
  ) d;

  -- the recommendation, in plain language ---------------------------------
  if not gates.gate6 then
    recommendation := 'Recommend HQ review before any decision. The Day 6 '
      || 'safeguarding checkpoint was not completed. This is a safety '
      || 'matter, so it is not decided by score alone \u2014 a person at '
      || 'WODDI should look at this one directly.';
  elsif not gates.gate13 then
    recommendation := 'Recommend HQ review before any decision. The Day 13 '
      || 'commitment checkpoint was not completed. This is not decided by '
      || 'score alone \u2014 a person at WODDI should look at this one directly.';
  elsif (ws->>'verdict') = 'recommended' then
    recommendation := coalesce(p.first_name, 'This candidate')
      || ' completed the safeguarding and commitment checkpoints and '
      || 'scored ' || (ws->>'score') || '/100 overall. Recommended for the '
      || 'position applied for'
      || case when p.role_applied is not null
              then ' (' || p.role_applied || ')' else '' end
      || case when p.country is not null
              then ' in ' || p.country
                || coalesce(', ' || p.state_region, '') else '' end || '.';
  elsif (ws->>'verdict') = 'conditional' then
    recommendation := coalesce(p.first_name, 'This candidate')
      || ' completed the safeguarding and commitment checkpoints and '
      || 'scored ' || (ws->>'score') || '/100 \u2014 a workable but not '
      || 'strong result. Worth a short conversation before deciding, '
      || 'rather than an automatic yes or no.';
  else
    recommendation := coalesce(p.first_name, 'This candidate')
      || ' completed the safeguarding and commitment checkpoints, but the '
      || 'overall activity level was low (' || (ws->>'score')
      || '/100). Not recommended for advancement this cycle \u2014 she is '
      || 'welcome to apply again in a future intake.';
  end if;

  return jsonb_build_object(
    'name', coalesce(p.first_name || ' ' || p.last_name, 'Unknown'),
    'membership_no', p.membership_no,
    'role_applied', p.role_applied,
    'country', p.country, 'state', p.state_region, 'lga', p.lga,
    'started_at', j.started_at,
    'concluded_at', coalesce(j.completed_at,
      case when j.status = 'incomplete'
           then coalesce(j.extended_until, j.due_at) end),
    'journey_status', j.status,
    'score', (ws->>'score')::int,
    'gate6_met', gates.gate6, 'gate13_met', gates.gate13,
    'days', days,
    'recommendation', recommendation
  );
end;
$$;
revoke execute on function public.activation_individual_report(uuid) from anon;

-- the master report no longer carries a live verdict/hard-gate badge —
-- only real progress while in flight; a report is available once concluded
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
        and not exists (select 1 from staff st
                         where st.profile_id = p.id and st.is_active)
        and (j.id is not null
             or p.status in ('applicant', 'under_review', 'approved'))
    ) sub);
end; $$;
revoke execute on function public.activation_report() from anon;

insert into public.schema_migrations (version, name)
values (92, 'individual_activation_reports') on conflict (version) do nothing;
