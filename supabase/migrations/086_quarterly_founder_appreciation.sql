-- ============================================================================
-- WDOS Migration 086 — Item 8: Quarterly Founder & HQ Appreciation (Phase 98)
--
-- All 12 messages below are reproduced verbatim from the founder's own
-- approved pack (WODDI Item 8, 11 August 2026) — nothing here is newly
-- authored. Her document already carries every email/dashboard/push/SMS
-- variant for the full three-year cycle; this migration brings that
-- already-approved content into WDOS as a working feature rather than
-- inventing anything new.
--
-- Delivery deliberately reuses the Announcements audience+push pipeline
-- built in Phase 92/92b (proven, tested, already live) instead of building
-- a parallel delivery system — a quarterly appreciation broadcast is
-- structurally identical to a "leaders only" announcement.
--
-- The [INSERT VERIFIED QUARTERLY IMPACT HIGHLIGHT] placeholder is
-- deliberate, not a content gap — the founder's pack explicitly forbids
-- pre-writing this figure ("no forecasts, unverified totals"). HQ must
-- supply the real, approved evidence at dispatch time; dispatch_quarterly_
-- appreciation() refuses to send while that placeholder is still present.
-- ============================================================================

insert into public.engagement_content (kind, period, title, focus, body)
values
  ('quarterly', 1, 'We Begin Together', 'Belonging and gratitude at the year''s opening', 'Dear WGMN Volunteer Leaders,

As a new year opens, we at Headquarters pause first to recognise the women whose voluntary service gives WGMN its strength across Africa. You bring different experiences, languages and local realities, yet you meet within one shared purpose: to nurture women, strengthen families and serve communities with dignity. Your willingness to learn, coordinate, mentor and remain accountable is helping build a continental network where every woman can find a place to belong and contribute.

This quarter, we celebrate [INSERT VERIFIED QUARTERLY IMPACT HIGHLIGHT]. This statement must be replaced only with information verified in WDOS or through an authorised Headquarters evidence record. Behind that evidence are people—leaders who offered time, listened carefully, solved problems and kept others connected.

I want every volunteer leader to know that your presence matters, including service that may never be publicly visible. As we enter the next quarter, let us deepen trust, welcome others thoughtfully and keep “No Woman Left Out” alive in our everyday decisions.

With deep gratitude,
The Founder and the WODDI Family.'),
  ('quarterly', 2, 'Roots of Trust', 'Trust built through consistent, dependable service', 'Dear WGMN Volunteer Leaders,

The second quarter reminds us that strong networks are formed through trust practised consistently. We at Headquarters are grateful for the ways you have followed through on responsibilities, communicated across distance, supported fellow leaders and protected the dignity of the women and communities we serve. These choices may look ordinary, but together they create the dependable foundation on which WGMN can grow.

Our verified record for this quarter is [INSERT VERIFIED QUARTERLY IMPACT HIGHLIGHT]. Only an approved, evidence-based statement may replace this placeholder. Whatever the final highlight shows, its meaning rests in your responsible service and in the relationships you have strengthened across countries and communities.

From the Founder''s heart, thank you for carrying this work with care. In the coming quarter, let us continue to earn trust through accuracy, safeguarding, humility and respectful collaboration.

With deep gratitude,
The Founder and the WODDI Family.'),
  ('quarterly', 3, 'Many Places, One Purpose', 'Unity across diverse locations and circumstances', 'Dear WGMN Volunteer Leaders,

Across villages, cities, states and nations, WGMN leaders serve within very different circumstances. This quarter, we honour the unity you create without erasing those differences. We at Headquarters appreciate every leader who translates a shared vision into locally responsible action.

Together, you contributed to [INSERT VERIFIED QUARTERLY IMPACT HIGHLIGHT]. Before dispatch, this placeholder must contain only a verified and approved quarterly result. The evidence is important, but so is the cooperation behind it—meetings attended, guidance shared, colleagues encouraged when progress was difficult.

As the next quarter approaches, let us strengthen our connections, learn across countries and continue serving with compassion, discipline and a common purpose.

With deep gratitude,
The Founder and the WODDI Family.'),
  ('quarterly', 4, 'The Foundation We Built', 'Year-end gratitude for the foundation laid together', 'Dear WGMN Volunteer Leaders,

As the year draws toward its close, we at Headquarters look back with gratitude for the foundation you have built together. The most valuable progress is not only found in completed activities. It is also present in stronger relationships, clearer systems, lessons honestly recorded and women who now know that their voice and service belong within this network.

This quarter''s approved evidence is [INSERT VERIFIED QUARTERLY IMPACT HIGHLIGHT]. We honour the result without reducing anyone to a number, because each achievement was made possible by leaders who gave time, exercised patience and continued to serve through changing circumstances.

As we prepare for a new year, let us preserve what worked, correct what did not and enter the next season ready to learn, welcome and build again—together.

With deep gratitude,
The Founder and the WODDI Family.'),
  ('quarterly', 5, 'Excellence with Heart', 'Disciplined, compassionate standards of service', 'Dear WGMN Volunteer Leaders,

Excellence in WGMN is not perfection, status or competition. It is the disciplined choice to serve women well, keep accurate commitments, learn from feedback and treat people with dignity. At the start of this cycle year, we at Headquarters thank you for pursuing higher standards without losing the compassion at the heart of our mission.

Our verified quarterly highlight is [INSERT VERIFIED QUARTERLY IMPACT HIGHLIGHT]. We celebrate that progress while remembering the countless responsible actions behind it: preparation before meetings, careful follow-up, respectful correction, safeguarding.

May our standard remain clear: service that is accountable, inclusive, humane and worthy of the trust placed in us.

With deep gratitude,
The Founder and the WODDI Family.'),
  ('quarterly', 6, 'Learning that Multiplies', 'Shared knowledge that strengthens the whole network', 'Dear WGMN Volunteer Leaders,

What one leader learns can become strength for many when knowledge is shared generously. During this quarter, we at Headquarters have seen the importance of volunteers who seek guidance, document lessons, explain processes patiently and help colleagues grow in confidence.

This quarter, the verified record is [INSERT VERIFIED QUARTERLY IMPACT HIGHLIGHT]. Its true value includes the skills strengthened, mistakes avoided and local leaders better equipped to act with wisdom and accountability.

In the coming quarter, let us share knowledge more intentionally, mentor with humility and turn every useful lesson into a pathway that another woman can follow.

With deep gratitude,
The Founder and the WODDI Family.'),
  ('quarterly', 7, 'Mentoring Forward', 'Experienced leaders making room for others to grow', 'Dear WGMN Volunteer Leaders,

A network multiplies its influence when experienced women make room for others to learn, contribute and lead. We at Headquarters dedicate this quarter''s appreciation to every volunteer who has explained a task, encouraged a hesitant colleague, offered constructive feedback or opened a responsible pathway for another woman.

Our approved evidence for this period is [INSERT VERIFIED QUARTERLY IMPACT HIGHLIGHT]. Alongside that result, we recognise the human investment that statistics cannot fully express.

As we move toward the final quarter, let us mentor without creating dependence, recognise potential without favouritism and prepare emerging leaders to serve with integrity.

With deep gratitude,
The Founder and the WODDI Family.'),
  ('quarterly', 8, 'Shared Results, Shared Honour', 'Collective achievement across every level of WGMN', 'Dear WGMN Volunteer Leaders,

No meaningful continental result belongs to one person alone. As this year closes, we at Headquarters honour the combined service of leaders who planned, communicated, mobilised, recorded, translated, followed up and supported one another across different levels of WGMN.

The verified highlight for this quarter is [INSERT VERIFIED QUARTERLY IMPACT HIGHLIGHT]. We celebrate it as a collective achievement while remaining careful to acknowledge the countries, teams and often-unseen contributors whose work made it possible.

Shared honour is not diminished when more people receive it; it becomes a truer reflection of how transformation is built.

With deep gratitude,
The Founder and the WODDI Family.'),
  ('quarterly', 9, 'Stewarding What Will Outlast Us', 'Protecting values and standards for the next generation', 'Dear WGMN Volunteer Leaders,

Legacy begins in the standards we protect while we are still serving. At the opening of this cycle year, we at Headquarters thank you for building more than activities: you are helping preserve values, relationships, records and leadership practices that other women can inherit.

This quarter''s verified evidence is [INSERT VERIFIED QUARTERLY IMPACT HIGHLIGHT]. We celebrate the progress and ask an equally important question: what have we learned that should be documented, strengthened or passed forward?

What we steward faithfully can continue to bless women and communities beyond our own tenure.

With deep gratitude,
The Founder and the WODDI Family.'),
  ('quarterly', 10, 'Renewing the Promise', 'Reflection, adaptation, and recommitment to the mission', 'Dear WGMN Volunteer Leaders,

Renewal asks us to remember why we began and to choose the mission again with clearer understanding. Midway through this year, we at Headquarters thank you for continuing to serve even as methods, teams and circumstances change.

The authorised quarterly highlight is [INSERT VERIFIED QUARTERLY IMPACT HIGHLIGHT]. It should also help us identify what needs refreshing so participation becomes more inclusive, support becomes more timely and local action remains accountable.

Let us release habits that no longer serve the mission, restore relationships where possible and welcome responsible new ideas.

With deep gratitude,
The Founder and the WODDI Family.'),
  ('quarterly', 11, 'Opening Doors for the Next Leader', 'Fair, deliberate succession and shared leadership', 'Dear WGMN Volunteer Leaders,

An enduring movement creates space for new leadership before the need becomes urgent. This quarter, we at Headquarters appreciate volunteers who identify potential, share responsibility, explain institutional values and allow others to contribute meaningfully.

Our verified impact statement is [INSERT VERIFIED QUARTERLY IMPACT HIGHLIGHT]. The quarterly result is strengthened when new women are not merely added to a list but are welcomed, equipped, supported and held to responsible standards.

Every responsible door we open helps keep the promise of “No Woman Left Out” alive.

With deep gratitude,
The Founder and the WODDI Family.'),
  ('quarterly', 12, 'Legacy in Motion', 'Closing the three-year cycle with gratitude and renewal', 'Dear WGMN Volunteer Leaders,

We close this three-year appreciation cycle not at an ending, but at a point of renewed responsibility. Across Africa, your service has helped turn WGMN''s vision into relationships, learning, local leadership and community-minded action.

Our final verified quarterly highlight is [INSERT VERIFIED QUARTERLY IMPACT HIGHLIGHT]. We receive that result with gratitude while remembering that legacy is carried through people, trustworthy systems and values practised consistently—not through celebration alone.

As a new cycle approaches, let us review the evidence, refresh the wording, learn from gaps and recommit to service that includes, safeguards and equips.

With deep gratitude,
The Founder and the WODDI Family.')
on conflict (kind, period) do update
  set title = excluded.title, focus = excluded.focus, body = excluded.body;

-- which of the 12 quarters is "current" — Cycle Year 1 begins on the
-- Headquarters-authorised production launch date, per the pack's own rule
insert into public.org_settings (key, value)
values ('quarterly_cycle_start', to_jsonb('2026-08-03'::date))
on conflict (key) do nothing;

create or replace function public.current_quarterly_period()
returns int language plpgsql stable as $$
declare
  start_date date;
  elapsed_months int;
  elapsed_quarters int;
begin
  select (value #>> '{}')::date into start_date
    from org_settings where key = 'quarterly_cycle_start';
  if start_date is null then
    start_date := '2026-08-03'::date;
  end if;
  elapsed_months := (extract(year from now())::int
                     - extract(year from start_date)::int) * 12
                   + (extract(month from now())::int
                     - extract(month from start_date)::int);
  elapsed_quarters := floor(elapsed_months / 3.0)::int;
  return (elapsed_quarters % 12) + 1;
end;
$$;

-- HQ supplies the real evidence; refuses to send the unfilled placeholder
create or replace function public.dispatch_quarterly_appreciation(
  p_evidence text)
returns jsonb language plpgsql
security definer set search_path = public as $$
declare
  target_period int; msg engagement_content; hq_unit uuid; final_body text;
  already boolean;
begin
  if auth.uid() is not null and not is_case_hq() then
    raise exception 'HQ only';
  end if;
  if p_evidence is null or char_length(btrim(p_evidence)) < 10 then
    raise exception 'Please supply this quarter''s verified evidence (at least a short sentence) before dispatching';
  end if;

  target_period := current_quarterly_period();
  select * into msg from engagement_content
   where kind = 'quarterly' and period = target_period;
  if msg.id is null then raise exception 'No quarterly message staged for period %', target_period; end if;

  select exists (select 1 from announcements
                  where title = msg.title and created_at::date = current_date)
    into already;
  if already then
    return jsonb_build_object('sent', false,
      'reason', 'Already dispatched today for this quarter — not sent twice');
  end if;

  final_body := replace(msg.body,
    '[INSERT VERIFIED QUARTERLY IMPACT HIGHLIGHT]', btrim(p_evidence));

  select id into hq_unit from org_units
   where level = 'headquarters' order by created_at limit 1;

  if coalesce(auth.uid(), hq_inbox_target()) is null then
    raise exception 'No HQ identity found to attribute this announcement to \u2014 confirm at least one super_admin, executive_director or active staff record exists';
  end if;

  insert into announcements (org_unit_id, network, audience, priority,
    title, body, author_id)
  values (hq_unit, 'WGMN', 'leaders', 'important', msg.title, final_body,
          coalesce(auth.uid(), hq_inbox_target()));

  return jsonb_build_object('sent', true, 'period', target_period,
                            'title', msg.title);
end; $$;
revoke execute on function public.dispatch_quarterly_appreciation(text)
  from anon;

insert into public.schema_migrations (version, name)
values (86, 'quarterly_founder_appreciation') on conflict (version) do nothing;
