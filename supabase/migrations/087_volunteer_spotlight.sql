-- ============================================================================
-- WDOS Migration 087 — Item 7: Volunteer Spotlight & Leadership Contribution
-- Recognition (Phase 99)
--
-- Built directly from the founder's own complete governance pack (WODDI
-- Item 7, 11 August 2026) — her nomination form, five-criterion scoring
-- rubric, eligibility rules, fairness framework and three-year, 36-month
-- editorial calendar are ALL fully specified. The one thing that can
-- never be pre-written, by her own explicit rule, is the individual
-- story content — because it must follow real, verified evidence about a
-- real person. This migration builds the working ENGINE her document
-- describes; it does not and cannot invent evidence.
--
-- Five categories, seeded verbatim from her message library (placeholders
-- preserved exactly as she wrote them — never pre-filled):
--   SCA  Specific Contribution Appreciation
--   QSR  Quiet Service Recognition (reserved once every quarter, per her
--        non-repetition rule — 12 of the 36 slots)
--   LGR  Leadership Growth Recognition
--   MAR  Mentor Appreciation
--   TCR  Team/Country Achievement
--
-- Workflow (her 11-stage model, condensed to what WDOS enforces):
--   submitted -> screening -> scoring -> consent_pending -> published
--   (or -> held, at any gate, with a recorded reason)
-- Scoring: 5 criteria x 1/3/5, qualifying threshold 18/25 with a minimum
-- of 3 in Mission Alignment AND Character & Collaboration (her exact rule).
-- Eligibility: active established leader, no more than one live
-- nomination at a time, no individual spotlight in the last 12 months.
-- Consent gates PUBLIC use only — her own rule says declining public
-- recognition never removes private appreciation, so WDOS always sends
-- the private message once a nomination clears scoring, regardless of
-- the public-consent answer.
-- ============================================================================

create type public.spotlight_category as enum ('SCA','QSR','LGR','MAR','TCR');
create type public.spotlight_status as enum (
  'submitted','screening','scoring','held','consent_pending','published');

create table public.spotlight_categories (
  code        spotlight_category primary key,
  name        text not null,
  subject     text not null,
  email_body  text not null
);

create table public.spotlight_nominations (
  id                  uuid primary key default gen_random_uuid(),
  category            spotlight_category not null,
  nominee_id          uuid not null references profiles(id),
  nominator_id        uuid not null references profiles(id),
  period_start        date,
  period_end          date,
  verified_contribution text not null
    check (char_length(verified_contribution) between 20 and 2000),
  mission_alignment_note text not null default '',
  evidence_summary    text not null
    check (char_length(evidence_summary) between 10 and 2000),
  other_contributors  text not null default '',
  status              spotlight_status not null default 'submitted',
  held_reason         text,
  score_mission       int check (score_mission in (1,3,5)),
  score_impact        int check (score_impact in (1,3,5)),
  score_consistency   int check (score_consistency in (1,3,5)),
  score_character     int check (score_character in (1,3,5)),
  score_unseen        int check (score_unseen in (1,3,5)),
  score_total         int,
  scored_by           uuid references profiles(id),
  scored_at           timestamptz,
  public_consent      boolean,
  consent_at          timestamptz,
  verified_impact_final text,
  published_at        timestamptz,
  created_at          timestamptz not null default now()
);
alter table public.spotlight_nominations enable row level security;
create policy spotlight_hq_all on public.spotlight_nominations
  for all to authenticated using (public.is_case_hq())
  with check (public.is_case_hq());
create policy spotlight_own_read on public.spotlight_nominations
  for select to authenticated
  using (nominee_id = auth.uid() or nominator_id = auth.uid());

-- the 3-year, 36-month editorial calendar, exactly as her document maps it
create table public.spotlight_calendar (
  cycle_year int not null,
  month_no   int not null check (month_no between 1 and 12),
  category   spotlight_category not null,
  slot_id    text not null,
  primary key (cycle_year, month_no)
);
alter table public.spotlight_calendar enable row level security;
create policy spotlight_calendar_read on public.spotlight_calendar
  for select to authenticated using (true);

insert into public.spotlight_calendar (cycle_year, month_no, category, slot_id)
values
 (1,1,'SCA','SPOT-Y1-JAN-SCA'),(1,2,'LGR','SPOT-Y1-FEB-LGR'),
 (1,3,'QSR','SPOT-Y1-MAR-QSR'),(1,4,'MAR','SPOT-Y1-APR-MAR'),
 (1,5,'TCR','SPOT-Y1-MAY-TCR'),(1,6,'QSR','SPOT-Y1-JUN-QSR'),
 (1,7,'SCA','SPOT-Y1-JUL-SCA'),(1,8,'LGR','SPOT-Y1-AUG-LGR'),
 (1,9,'QSR','SPOT-Y1-SEP-QSR'),(1,10,'MAR','SPOT-Y1-OCT-MAR'),
 (1,11,'TCR','SPOT-Y1-NOV-TCR'),(1,12,'QSR','SPOT-Y1-DEC-QSR'),
 (2,1,'TCR','SPOT-Y2-JAN-TCR'),(2,2,'MAR','SPOT-Y2-FEB-MAR'),
 (2,3,'QSR','SPOT-Y2-MAR-QSR'),(2,4,'LGR','SPOT-Y2-APR-LGR'),
 (2,5,'SCA','SPOT-Y2-MAY-SCA'),(2,6,'QSR','SPOT-Y2-JUN-QSR'),
 (2,7,'TCR','SPOT-Y2-JUL-TCR'),(2,8,'MAR','SPOT-Y2-AUG-MAR'),
 (2,9,'QSR','SPOT-Y2-SEP-QSR'),(2,10,'LGR','SPOT-Y2-OCT-LGR'),
 (2,11,'SCA','SPOT-Y2-NOV-SCA'),(2,12,'QSR','SPOT-Y2-DEC-QSR'),
 (3,1,'LGR','SPOT-Y3-JAN-LGR'),(3,2,'TCR','SPOT-Y3-FEB-TCR'),
 (3,3,'QSR','SPOT-Y3-MAR-QSR'),(3,4,'SCA','SPOT-Y3-APR-SCA'),
 (3,5,'MAR','SPOT-Y3-MAY-MAR'),(3,6,'QSR','SPOT-Y3-JUN-QSR'),
 (3,7,'LGR','SPOT-Y3-JUL-LGR'),(3,8,'TCR','SPOT-Y3-AUG-TCR'),
 (3,9,'QSR','SPOT-Y3-SEP-QSR'),(3,10,'SCA','SPOT-Y3-OCT-SCA'),
 (3,11,'MAR','SPOT-Y3-NOV-MAR'),(3,12,'QSR','SPOT-Y3-DEC-QSR');

-- the five recognition-category message templates, verbatim from her pack
insert into public.spotlight_categories (code, name, subject, email_body) values
('SCA','Specific Contribution Appreciation','Recognising Your Verified Contribution',
'Dear {Preferred_Name}, WODDI is pleased to recognise your verified contribution: [INSERT VERIFIED CONTRIBUTION]. This acknowledgement follows review of the supporting evidence and the required consent. Your service demonstrates how a focused act of leadership can open opportunity for women, strengthen families or support a community with dignity. We celebrate you as a whole person, not only the result, and appreciate the care, learning and collaboration you brought to the work. Where an impact statement is included, it must remain limited to what has been independently confirmed: [INSERT VERIFIED IMPACT]. As you continue serving within the Good Mother Network, please keep documenting honestly, protecting confidential information and inviting others to participate. Your contribution helps turn "No Woman Left Out" into responsible action. Thank you for giving your time and leadership to the shared mission.

With appreciation,
The WODDI Family.'),
('QSR','Quiet Service Recognition','Your Quiet Service Is Seen',
'Dear {Preferred_Name}, some of the service that holds a network together happens quietly, beyond titles, applause or public attention. Today WODDI recognises your verified contribution: [INSERT VERIFIED CONTRIBUTION]. The evidence has been reviewed, and this acknowledgement is shared with your consent. We honour your consistency, care and willingness to support others without making visibility the measure of value. Your service helps WGMN remain human, dependable and inclusive as it empowers women, strengthens families and serves communities. We celebrate the person behind the contribution and recognise that often-unseen effort deserves a fair place in our institutional story. Please continue to protect dignity, work collaboratively and document service accurately so learning can be preserved. Through quiet acts of responsibility, the promise "No Woman Left Out" becomes real. Thank you for the difference your faithful presence makes.

With appreciation,
The WODDI Family.'),
('LGR','Leadership Growth Recognition','Honouring Your Leadership Growth',
'Dear {Preferred_Name}, leadership is not only a position; it is a continuing willingness to learn, reflect and serve others more responsibly. WODDI is pleased to recognise your verified leadership growth: [INSERT VERIFIED CONTRIBUTION]. This recognition is grounded in reviewed evidence and shared with your consent. We appreciate the openness, discipline and humility involved in developing new capacity, applying feedback or helping a team work more effectively. Today we celebrate your progress without suggesting perfection or comparing you with other volunteers. As your journey continues, keep asking questions, using learning opportunities, protecting safeguarding standards and creating room for other women to grow. Thank you for showing that "No Woman Left Out" includes helping every leader become better equipped to serve.

With appreciation,
The WODDI Family.'),
('MAR','Mentor Appreciation','Thank You for Helping Others Grow',
'Dear {Preferred_Name}, WODDI gratefully recognises the verified mentoring contribution you have made: [INSERT VERIFIED CONTRIBUTION]. With the appropriate evidence and consent in place, we honour the way you have helped another woman learn, find confidence or carry responsibility more effectively. Good mentoring does not create dependence or demand recognition; it listens, guides, protects boundaries and makes room for the other person''s voice. Where impact is stated, only confirmed information may be used: [INSERT VERIFIED IMPACT]. Please continue to mentor with humility, safeguard confidentiality and direct people to qualified support whenever an issue exceeds your role. Thank you for extending the principle "No Woman Left Out" through patient and dignified guidance.

With appreciation,
The WODDI Family.'),
('TCR','Team/Country Achievement','Celebrating Your Team''s Verified Achievement',
'Dear {Preferred_Name} and Team, WODDI is pleased to recognise your verified shared contribution: [INSERT VERIFIED CONTRIBUTION]. The supporting evidence has been reviewed, and each person named or pictured must have recorded consent. This spotlight honours collaboration rather than elevating one visible person above the wider team. Any impact statement must remain limited to verified facts: [INSERT VERIFIED IMPACT]. As you celebrate, acknowledge partners accurately, protect beneficiary privacy and capture lessons for the wider network. Thank you for showing that "No Woman Left Out" also means no genuine contributor is left unrecognised.

With appreciation,
The WODDI Family.');

-- which of the 36 monthly slots is current, mirroring current_quarterly_period()
create or replace function public.current_spotlight_slot()
returns table (cycle_year int, month_no int, category spotlight_category,
              slot_id text)
language plpgsql stable as $$
declare
  start_date date;
  elapsed_months int;
  y int; m int;
begin
  select (value #>> '{}')::date into start_date
    from org_settings where key = 'quarterly_cycle_start';
  if start_date is null then start_date := '2026-08-03'::date; end if;
  elapsed_months := (extract(year from now())::int
                     - extract(year from start_date)::int) * 12
                   + (extract(month from now())::int
                     - extract(month from start_date)::int);
  y := (elapsed_months / 12) % 3 + 1;
  m := (elapsed_months % 12) + 1;
  return query select sc.cycle_year, sc.month_no, sc.category, sc.slot_id
    from spotlight_calendar sc where sc.cycle_year = y and sc.month_no = m;
end;
$$;

-- 1 ▸ submit a nomination -----------------------------------------------
create or replace function public.submit_spotlight_nomination(
  p_category spotlight_category, p_nominee uuid,
  p_contribution text, p_evidence text, p_period_start date default null,
  p_period_end date default null, p_other_contributors text default '',
  p_mission_note text default '')
returns uuid language plpgsql
security definer set search_path = public as $$
declare
  nom_id uuid; recent_count int; open_count int;
begin
  if auth.uid() is null then
    raise exception 'Sign in required to submit a nomination';
  end if;
  if not (public.is_established(p_nominee)) then
    raise exception 'Only an active, established volunteer leader can be nominated';
  end if;
  if p_nominee = auth.uid() and not public.is_case_hq() then
    raise exception 'Self-nominations require HQ to record an independent sponsor and verifier first';
  end if;

  select count(*) into open_count from spotlight_nominations
   where nominee_id = p_nominee and status not in ('published','held');
  if open_count > 0 then
    raise exception 'This volunteer already has a live nomination in progress';
  end if;

  select count(*) into recent_count from spotlight_nominations
   where nominee_id = p_nominee and status = 'published'
     and published_at > now() - interval '12 months';
  if recent_count > 0 and not public.is_case_hq() then
    raise exception 'This volunteer received an individual spotlight within the last 12 months';
  end if;

  insert into spotlight_nominations
    (category, nominee_id, nominator_id, verified_contribution,
     evidence_summary, period_start, period_end, other_contributors,
     mission_alignment_note)
  values (p_category, p_nominee, auth.uid(), p_contribution, p_evidence,
          p_period_start, p_period_end, p_other_contributors, p_mission_note)
  returning id into nom_id;

  update spotlight_nominations set status = 'screening' where id = nom_id;
  return nom_id;
end;
$$;
revoke execute on function public.submit_spotlight_nomination(
  spotlight_category, uuid, text, text, date, date, text, text) from anon;

-- 2 ▸ score a nomination (HQ / review panel) ------------------------------
create or replace function public.score_spotlight_nomination(
  p_nomination uuid, p_mission int, p_impact int, p_consistency int,
  p_character int, p_unseen int)
returns jsonb language plpgsql
security definer set search_path = public as $$
declare total int; passes boolean;
begin
  if auth.uid() is not null and not is_case_hq() then
    raise exception 'HQ only';
  end if;
  if p_mission not in (1,3,5) or p_impact not in (1,3,5)
     or p_consistency not in (1,3,5) or p_character not in (1,3,5)
     or p_unseen not in (1,3,5) then
    raise exception 'Each score must be 1, 3 or 5, matching the approved rubric';
  end if;

  total := p_mission + p_impact + p_consistency + p_character + p_unseen;
  passes := total >= 18 and p_mission >= 3 and p_character >= 3;

  update spotlight_nominations
     set score_mission = p_mission, score_impact = p_impact,
         score_consistency = p_consistency, score_character = p_character,
         score_unseen = p_unseen, score_total = total,
         scored_by = auth.uid(), scored_at = now(),
         status = case when passes then 'consent_pending' else 'held' end,
         held_reason = case when passes then null
                       else 'Below the qualifying threshold (18/25, min 3 in Mission Alignment and Character & Collaboration)' end
   where id = p_nomination;

  return jsonb_build_object('total', total, 'qualifies', passes);
end;
$$;
revoke execute on function public.score_spotlight_nomination(
  uuid, int, int, int, int, int) from anon;

-- 3 ▸ record the nominee's consent (public use only — private
--     recognition below never depends on this) -----------------------------
create or replace function public.record_spotlight_consent(
  p_nomination uuid, p_public_consent boolean)
returns void language plpgsql
security definer set search_path = public as $$
begin
  if auth.uid() is not null and not is_case_hq() then
    raise exception 'HQ only';
  end if;
  update spotlight_nominations
     set public_consent = p_public_consent, consent_at = now()
   where id = p_nomination and status = 'consent_pending';
end;
$$;
revoke execute on function public.record_spotlight_consent(uuid, boolean)
  from anon;

-- 4 ▸ publish — sends the private recognition regardless of public
--     consent (her own rule), fills the template from VERIFIED text only --
create or replace function public.publish_spotlight(
  p_nomination uuid, p_verified_impact_final text)
returns jsonb language plpgsql
security definer set search_path = public as $$
declare nom spotlight_nominations; cat spotlight_categories;
  final_body text; final_subject text;
begin
  if auth.uid() is not null and not is_case_hq() then
    raise exception 'HQ only';
  end if;

  select * into nom from spotlight_nominations where id = p_nomination;
  if nom.id is null then raise exception 'Nomination not found'; end if;
  if nom.status <> 'consent_pending' then
    raise exception 'This nomination has not cleared scoring and consent yet';
  end if;
  if p_verified_impact_final is null
     or char_length(btrim(p_verified_impact_final)) < 5 then
    raise exception 'Please supply the final verified impact statement before publishing';
  end if;

  select * into cat from spotlight_categories where code = nom.category;

  final_body := replace(cat.email_body,
    '[INSERT VERIFIED CONTRIBUTION]', nom.verified_contribution);
  final_body := replace(final_body,
    '[INSERT VERIFIED IMPACT]', btrim(p_verified_impact_final));
  final_subject := cat.subject;

  insert into member_notices (profile_id, kind, title, body)
  values (nom.nominee_id, 'nudge', final_subject, final_body);

  update spotlight_nominations
     set status = 'published', published_at = now(),
         verified_impact_final = p_verified_impact_final
   where id = p_nomination;

  return jsonb_build_object('published', true, 'category', nom.category,
                            'nominee', nom.nominee_id);
end;
$$;
revoke execute on function public.publish_spotlight(uuid, text) from anon;

-- 5 ▸ place a nomination on hold with a recorded reason, at any gate -------
create or replace function public.hold_spotlight_nomination(
  p_nomination uuid, p_reason text)
returns void language plpgsql
security definer set search_path = public as $$
begin
  if auth.uid() is not null and not is_case_hq() then
    raise exception 'HQ only';
  end if;
  if p_reason is null or char_length(btrim(p_reason)) < 5 then
    raise exception 'Please record a reason before placing a nomination on hold';
  end if;
  update spotlight_nominations
     set status = 'held', held_reason = btrim(p_reason)
   where id = p_nomination;
end;
$$;
revoke execute on function public.hold_spotlight_nomination(uuid, text)
  from anon;

insert into public.schema_migrations (version, name)
values (87, 'volunteer_spotlight') on conflict (version) do nothing;
