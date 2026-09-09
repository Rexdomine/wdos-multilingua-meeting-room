-- ============================================================================
-- WDOS Migration 088 — Weighted Activation Scoring & Hierarchy-Aware
-- Leadership Matching (Phase 100)
--
-- Azeez's directive, restated so the build matches it exactly:
--   1. Passing the 14-day activation makes someone a REVIEWED CANDIDATE,
--      never an automatic leader — HQ reviews the score and approves.
--   2. The master dashboard must show, per candidate: pass/fail, a
--      percentage score, and a breakdown that penalises missed or late
--      days rather than only "eventually done."
--   3. The score = assessment/assignment results + participation,
--      communication and responsiveness + administrator observations
--      (Days 8 and 11) + hard-gate flags (Days 6 and 13) that OVERRIDE
--      the score and force leadership review regardless of the number.
--   4. Once approved, WDOS matches the candidate to a VACANT seat at
--      their applied role and location — country, state, and (once real
--      data exists) LGA and chapter — never displacing an existing
--      holder, exactly as the 43/68 established leaders are protected.
--
-- HONEST GAP, not silently worked around: the exact percentage weights
-- for each component were not supplied in what Azeez sent — only the
-- STRUCTURE (which components feed the score) was. This migration uses
-- clearly-labelled, reasonable default weights, stored in org_settings
-- so HQ can retune them WITHOUT another migration. Defaults:
--   50% assessment/assignment results · 20% timeliness (on-time days)
--   15% participation/communication/responsiveness · 15% administrator
--   observations (Days 8 & 11, or any day HQ records one)
-- Advancement thresholds (also retunable, also undocumented in what was
-- sent): >=70 recommended · 50-69 conditional/needs review · <50 not
-- yet ready. A failed hard gate (Day 6 or Day 13) overrides ALL of this
-- and routes straight to "requires leadership review," matching the
-- instruction exactly.
-- ============================================================================

-- 1 ▸ administrator observations (Days 8 & 11, or any day HQ chooses) -------
create table public.activation_observations (
  id           uuid primary key default gen_random_uuid(),
  journey_id   uuid not null references activation_journeys(id) on delete cascade,
  day_no       int not null check (day_no between 1 and 14),
  observer_id  uuid not null references profiles(id),
  score        int not null check (score between 1 and 5),
  note         text not null default '',
  created_at   timestamptz not null default now()
);
alter table public.activation_observations enable row level security;
create policy activation_obs_hq on public.activation_observations
  for all to authenticated using (public.is_case_hq())
  with check (public.is_case_hq());

create or replace function public.record_activation_observation(
  p_journey uuid, p_day int, p_score int, p_note text default '')
returns void language plpgsql
security definer set search_path = public as $$
begin
  if auth.uid() is not null and not is_case_hq() then
    raise exception 'HQ only';
  end if;
  if p_score not between 1 and 5 then
    raise exception 'Observation score must be between 1 and 5';
  end if;
  insert into activation_observations
    (journey_id, day_no, observer_id, score, note)
  values (p_journey, p_day, coalesce(auth.uid(), hq_inbox_target()),
          p_score, btrim(coalesce(p_note, '')));
end;
$$;
revoke execute on function public.record_activation_observation(
  uuid, int, int, text) from anon;

-- 2 ▸ configurable weights and thresholds — retunable without a migration --
insert into public.org_settings (key, value) values
  ('activation_score_weights',
   '{"assessment":50,"timeliness":20,"participation":15,"observations":15}'::jsonb)
on conflict (key) do nothing;
insert into public.org_settings (key, value) values
  ('activation_advancement_thresholds',
   '{"recommended":70,"conditional":50}'::jsonb)
on conflict (key) do nothing;

-- 3 ▸ the weighted score engine ---------------------------------------------
create or replace function public.activation_weighted_score(jid uuid)
returns jsonb language plpgsql stable
security definer set search_path = public as $$
declare
  j activation_journeys;
  gates record;
  weights jsonb;
  thresholds jsonb;
  assessment_pct numeric := 0;
  timeliness_pct numeric := 1;
  participation_pct numeric := 0;
  observations_pct numeric := 0.6;   -- neutral default when none recorded
  possible int; earned int;
  required_days int; on_time_days int;
  sig jsonb;
  signal_hits int;
  obs_avg numeric;
  total numeric;
  verdict text;
begin
  select * into j from activation_journeys where id = jid;
  if j.id is null then
    return jsonb_build_object('error', 'journey not found');
  end if;

  select * into gates from eval_activation(jid);

  select value into weights from org_settings
   where key = 'activation_score_weights';
  select value into thresholds from org_settings
   where key = 'activation_advancement_thresholds';

  -- assessment/assignment component ----------------------------------------
  select coalesce(sum(points), 0) into possible
    from activation_items where kind in ('mcq','tf','checklist') and points > 0;
  select coalesce(sum(r.score), 0) into earned
    from activation_item_responses r
    join activation_items i on i.id = r.item_id
   where r.journey_id = jid and i.kind in ('mcq','tf','checklist');
  if possible > 0 then assessment_pct := earned::numeric / possible; end if;

  -- timeliness component: was each day's required work done within that
  -- day's own window, or did it slip to a later day? --------------------
  select count(distinct i.day) into required_days
    from activation_items i where i.is_required;

  select count(*) into on_time_days from (
    select i.day
      from activation_items i
      join activation_item_responses r
        on r.item_id = i.id and r.journey_id = jid
     where i.is_required
     group by i.day
    having bool_and(r.submitted_at <= j.started_at + make_interval(days => i.day))
       and count(*) = (select count(*) from activation_items i2
                        where i2.day = i.day and i2.is_required)
  ) done_on_time;

  if required_days > 0 then
    timeliness_pct := on_time_days::numeric / required_days;
  end if;

  -- participation/communication/responsiveness, from the signals already
  -- tracked since Phase 89 (message to HQ, engagement with the app) ------
  begin
    sig := (select public.journey_signals()) ;
  exception when others then sig := '{}'::jsonb; end;
  signal_hits := 0;
  if coalesce((sig->>'msg_hq')::boolean, false) then signal_hits := signal_hits + 1; end if;
  if coalesce((sig->>'tasks')::boolean, false) then signal_hits := signal_hits + 1; end if;
  if coalesce((sig->>'ask')::boolean, false) then signal_hits := signal_hits + 1; end if;
  if coalesce((sig->>'announcement')::boolean, false) then signal_hits := signal_hits + 1; end if;
  participation_pct := signal_hits::numeric / 4;

  -- administrator observations (Days 8 & 11 by design, any day accepted) --
  select avg(score) into obs_avg from activation_observations
   where journey_id = jid;
  if obs_avg is not null then
    observations_pct := (obs_avg - 1) / 4.0;   -- 1..5 scale to 0..1
  end if;

  total := round(
      assessment_pct    * (weights->>'assessment')::numeric
    + timeliness_pct     * (weights->>'timeliness')::numeric
    + participation_pct  * (weights->>'participation')::numeric
    + observations_pct   * (weights->>'observations')::numeric
  );

  if not (gates.gate6 and gates.gate13) then
    verdict := 'requires_leadership_review';
  elsif total >= (thresholds->>'recommended')::numeric then
    verdict := 'recommended';
  elsif total >= (thresholds->>'conditional')::numeric then
    verdict := 'conditional';
  else
    verdict := 'not_yet_ready';
  end if;

  return jsonb_build_object(
    'score', total,
    'gate6', gates.gate6, 'gate13', gates.gate13,
    'hard_gate_failed', not (gates.gate6 and gates.gate13),
    'verdict', verdict,
    'breakdown', jsonb_build_object(
      'assessment_pct', round(assessment_pct * 100),
      'timeliness_pct', round(timeliness_pct * 100),
      'participation_pct', round(participation_pct * 100),
      'observations_pct', round(observations_pct * 100),
      'on_time_days', on_time_days, 'required_days', required_days
    )
  );
end;
$$;

-- 4 ▸ the master dashboard report, now carrying the weighted score ---------
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
        'weighted_score', (ws->>'score')::int,
        'weighted_verdict', ws->>'verdict',
        'score_breakdown', ws->'breakdown',
        'verdict', case
          when j.id is null then 'not_started'
          when j.status = 'completed' then 'passed'
          when j.status in ('incomplete', 'deferred') then 'failed'
          when now() > coalesce(j.extended_until, j.due_at) then 'failed'
          else 'in_progress' end,
        'has_cv', exists (select 1 from member_cvs c
                           where c.profile_id = p.id),
        'last_seen', p.last_seen_at
      ) as row
      from profiles p
      left join activation_journeys j on j.profile_id = p.id
      left join lateral (
        select case when j.id is not null
               then activation_weighted_score(j.id) else '{}'::jsonb end
      ) ws(ws) on true
      where p.merged_into is null
        and not exists (select 1 from staff st
                         where st.profile_id = p.id and st.is_active)
        and (j.id is not null
             or p.status in ('applicant', 'under_review', 'approved'))
    ) sub);
end; $$;
revoke execute on function public.activation_report() from anon;

-- 5 ▸ hierarchy-aware vacant-seat matching: extend org_chart_country to
--     LGA and chapter levels too — this activates automatically the
--     moment real org_units exist at those levels; nothing is fabricated
--     here, and the 43/68 established leaders remain untouchable ---------
create or replace function public.org_chart_country(iso text)
returns jsonb language plpgsql stable
security definer set search_path = public as $$
declare country_row org_units; result jsonb;
begin
  if not is_case_hq() then raise exception 'HQ only'; end if;
  select * into country_row from org_units
   where level = 'country' and country_iso = upper(iso) limit 1;
  if country_row.id is null then return jsonb_build_object('seats', '[]'); end if;

  select jsonb_build_object(
    'country', country_row.name,
    'iso', country_row.country_iso,
    'seats', coalesce((
      select jsonb_agg(jsonb_build_object(
        'org_unit_id', ou.id,
        'level', ou.level,
        'location', ou.name,
        'role', ra_role.role,
        'holder_id', ra_role.profile_id,
        'holder_name', hp.first_name || ' ' || hp.last_name,
        'vacant', ra_role.profile_id is null
      ) order by ou.level, ou.name, ra_role.role)
      from (
        select country_row.id as ou_id, country_row.name as ou_name,
               'country'::public.org_level as ou_level,
               unnest(array['country_rep','deputy_country_rep'])
                 as want_role
        union all
        select su.id, su.name, 'state_region', 'state_coordinator'
          from org_units su
         where su.parent_id = country_row.id and su.level = 'state_region'
        union all
        select lg.id, lg.name, 'district_lga', 'district_coordinator'
          from org_units lg
         where lg.level = 'district_lga'
           and lg.parent_id in (select id from org_units
                                  where parent_id = country_row.id
                                    and level = 'state_region'
                                 union all select country_row.id)
        union all
        select ch.id, ch.name, 'chapter', 'chapter_lead'
          from org_units ch
         where ch.level = 'chapter'
           and ch.parent_id in (select id from org_units
                                  where level = 'district_lga')
      ) seats(ou_id, ou_name, ou_lvl, want_role)
      join org_units ou on ou.id = seats.ou_id
      left join lateral (
        select r.profile_id, r.role from role_assignments r
         where r.org_unit_id = seats.ou_id
           and r.role::text = seats.want_role
           and r.ends_at is null
         limit 1
      ) ra_role on true
      left join profiles hp on hp.id = ra_role.profile_id
    ), '[]'::jsonb)
  ) into result;
  return result;
end; $$;
revoke execute on function public.org_chart_country(text) from anon;

-- 6 ▸ the ONE best-match vacant seat for a specific candidate, so HQ sees
--     the obvious match first instead of browsing a long list ------------
create or replace function public.best_seat_match(p_candidate uuid)
returns jsonb language plpgsql stable
security definer set search_path = public as $$
declare cand profiles; iso text; seats jsonb; wanted text; best jsonb;
begin
  if not is_case_hq() then raise exception 'HQ only'; end if;
  select * into cand from profiles where id = p_candidate;
  if cand.id is null then return null; end if;

  select country_iso into iso from org_units
   where level = 'country' and name = cand.country limit 1;
  if iso is null then return null; end if;

  seats := (select public.org_chart_country(iso)) -> 'seats';
  wanted := case
    when cand.role_applied ilike '%deputy%' then 'deputy_country_rep'
    when cand.role_applied ilike '%assistant state%' then 'assistant_state_coordinator'
    when cand.role_applied ilike '%state%' then 'state_coordinator'
    when cand.role_applied ilike '%chapter%' then 'chapter_lead'
    when cand.role_applied ilike '%lga%' or cand.role_applied ilike '%district%'
      then 'district_coordinator'
    else 'country_rep' end;

  select s into best from jsonb_array_elements(seats) s
   where (s->>'vacant')::boolean = true
     and s->>'role' = wanted
     and (cand.state_region is null or s->>'location' = cand.state_region
          or s->>'location' = cand.country)
   order by (s->>'location' = cand.state_region) desc
   limit 1;

  return best;
end; $$;
revoke execute on function public.best_seat_match(uuid) from anon;

insert into public.schema_migrations (version, name)
values (88, 'weighted_activation_scoring') on conflict (version) do nothing;
