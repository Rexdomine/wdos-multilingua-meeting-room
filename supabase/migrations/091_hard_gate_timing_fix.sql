-- ============================================================================
-- WDOS Migration 091 — Hard gates apply only once the day has actually
-- come (Phase 103)
--
-- Real bug, caught from a screenshot: EVERY candidate on the Reports page
-- showed "Hard gate — needs review," from 13% up to 60%, Day 7 through
-- Day 12. The cause: activation_weighted_score()'s hard-gate check
-- treated a MISSING Day-6/Day-13 response identically to a FAILED one.
-- Someone on Day 7 cannot possibly have passed or failed a Day-13
-- checkpoint — it has not unlocked for her yet — but the old check had
-- no notion of "not yet applicable," only pass/fail, so it silently
-- flagged everyone still mid-journey as a hard-gate failure. Fixed: a
-- gate only counts against someone once her journey has genuinely
-- reached that day (or concluded). Before then, she is correctly
-- "in_progress," not "requires leadership review."
-- ============================================================================

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
  observations_pct numeric := 0.6;
  possible int; earned int;
  required_days int; on_time_days int;
  sig jsonb;
  signal_hits int;
  obs_avg numeric;
  total numeric;
  verdict text;
  day_reached int;
  gate6_applicable boolean;
  gate13_applicable boolean;
  hard_gate_failed boolean;
  journey_concluded boolean;
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

  day_reached := least(14, greatest(1, floor(extract(epoch from
    (now() - j.started_at)) / 86400)::int + 1));
  journey_concluded := j.status in ('completed', 'incomplete');

  -- a checkpoint only counts once its day has genuinely arrived ----------
  gate6_applicable := journey_concluded or day_reached >= 6;
  gate13_applicable := journey_concluded or day_reached >= 13;
  hard_gate_failed := (gate6_applicable and not gates.gate6)
                    or (gate13_applicable and not gates.gate13);

  -- assessment/assignment component ----------------------------------------
  select coalesce(sum(points), 0) into possible
    from activation_items where kind in ('mcq','tf','checklist') and points > 0;
  select coalesce(sum(r.score), 0) into earned
    from activation_item_responses r
    join activation_items i on i.id = r.item_id
   where r.journey_id = jid and i.kind in ('mcq','tf','checklist');
  if possible > 0 then assessment_pct := earned::numeric / possible; end if;

  -- timeliness component ---------------------------------------------------
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

  -- participation/communication/responsiveness -----------------------------
  begin
    sig := (select public.journey_signals());
  exception when others then sig := '{}'::jsonb; end;
  signal_hits := 0;
  if coalesce((sig->>'msg_hq')::boolean, false) then signal_hits := signal_hits + 1; end if;
  if coalesce((sig->>'tasks')::boolean, false) then signal_hits := signal_hits + 1; end if;
  if coalesce((sig->>'ask')::boolean, false) then signal_hits := signal_hits + 1; end if;
  if coalesce((sig->>'announcement')::boolean, false) then signal_hits := signal_hits + 1; end if;
  participation_pct := signal_hits::numeric / 4;

  -- administrator observations ----------------------------------------------
  select avg(score) into obs_avg from activation_observations
   where journey_id = jid;
  if obs_avg is not null then
    observations_pct := (obs_avg - 1) / 4.0;
  end if;

  total := round(
      assessment_pct    * (weights->>'assessment')::numeric
    + timeliness_pct     * (weights->>'timeliness')::numeric
    + participation_pct  * (weights->>'participation')::numeric
    + observations_pct   * (weights->>'observations')::numeric
  );

  if hard_gate_failed then
    verdict := 'requires_leadership_review';
  elsif not journey_concluded and day_reached < 14 then
    verdict := 'in_progress';
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
    'gate6_applicable', gate6_applicable,
    'gate13_applicable', gate13_applicable,
    'hard_gate_failed', hard_gate_failed,
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

insert into public.schema_migrations (version, name)
values (91, 'hard_gate_timing_fix') on conflict (version) do nothing;
