-- ============================================================================
-- WDOS Migration 030 — Activation Content Automation + Engagement Library
-- (Phase 33)
--
-- The 14-day activation journey (migration 024) gave every approved volunteer
-- a clock and a leader-confirmed milestone checklist. This migration gives the
-- journey its VOICE: the actual day-by-day curriculum from the content team is
-- seeded here, so a volunteer opening her mobile view sees the real Day-1..14
-- programme — messages, quizzes (auto-scored in the database so answers never
-- reach the browser), written tasks, and the two hard gates (Day 6 safeguarding,
-- Day 13 commitment). Day 14 is system-compiled: the database scores what it can
-- and proposes Advance / Advance with mentoring / Hold for a leader to confirm.
--
-- It also seeds the ongoing engagement library (WGMN Engagement Timetable):
-- 52 weekly inspiration themes, 12 monthly messages, 12 masterclass topics —
-- so the mobile "Learn" tab always shows the right item for the current week
-- and month with no cron required (Phase 34 will push them).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. DAY SPINE — the 14 days, HQ-editable
-- ---------------------------------------------------------------------------
create table public.activation_days (
  id        uuid primary key default gen_random_uuid(),
  day       int  not null unique check (day between 1 and 14),
  title     text not null,
  kind      text not null,          -- onboarding|knowledge|written|skills|gate|
                                     -- reflection|cohort|worksample|passive|
                                     -- group|confidence|commitment|evaluation
  intro     text not null default '',
  is_gate   boolean not null default false,
  is_active boolean not null default true
);

alter table public.activation_days enable row level security;
create policy act_days_read on public.activation_days
  for select to authenticated using (true);
create policy act_days_manage on public.activation_days
  for all to authenticated using (public.is_case_hq()) with check (public.is_case_hq());

-- ---------------------------------------------------------------------------
-- 2. ITEMS — questions / tasks. CLIENT-READABLE. No correct answers here.
-- ---------------------------------------------------------------------------
create table public.activation_items (
  id          uuid primary key default gen_random_uuid(),
  day         int  not null references public.activation_days(day) on delete cascade,
  seq         int  not null,
  kind        text not null,        -- mcq|tf|written|checklist|ack
  prompt      text not null,
  options     jsonb not null default '[]'::jsonb,  -- array of option strings
  points      int  not null default 0,
  is_required boolean not null default true,
  unique (day, seq)
);

alter table public.activation_items enable row level security;
create policy act_items_read on public.activation_items
  for select to authenticated using (true);
create policy act_items_manage on public.activation_items
  for all to authenticated using (public.is_case_hq()) with check (public.is_case_hq());

-- ---------------------------------------------------------------------------
-- 3. ANSWER KEYS — HQ-only. The scoring RPC (security definer) reads these;
--    volunteers and leaders can NEVER select them, so quizzes can't be gamed.
-- ---------------------------------------------------------------------------
create table public.activation_keys (
  item_id uuid primary key references public.activation_items(id) on delete cascade,
  correct jsonb not null            -- mcq/tf: "B" / "True"; checklist: "all"
);

alter table public.activation_keys enable row level security;
create policy act_keys_hq on public.activation_keys
  for all to authenticated using (public.is_case_hq()) with check (public.is_case_hq());

-- ---------------------------------------------------------------------------
-- 4. RESPONSES — a volunteer's submissions, auto-scored server-side.
-- ---------------------------------------------------------------------------
create table public.activation_item_responses (
  journey_id   uuid not null references public.activation_journeys(id) on delete cascade,
  item_id      uuid not null references public.activation_items(id)    on delete cascade,
  answer       jsonb not null,
  is_correct   boolean,             -- null for written / ack (human review)
  score        int  not null default 0,
  submitted_at timestamptz not null default now(),
  primary key (journey_id, item_id)
);

alter table public.activation_item_responses enable row level security;
-- can_see_journey() from migration 024: the volunteer herself, her leaders, HQ.
create policy act_resp_read on public.activation_item_responses
  for select to authenticated using (public.can_see_journey(journey_id));
-- All writes flow through submit_activation_item().

-- ---------------------------------------------------------------------------
-- 5. ENGAGEMENT LIBRARY — the ongoing (post-activation) content rhythm.
-- ---------------------------------------------------------------------------
create table public.engagement_content (
  id       uuid primary key default gen_random_uuid(),
  kind     text not null,           -- weekly | monthly | masterclass | briefing
  period   int  not null,           -- weekly: 1..52  · monthly/masterclass: 1..12
  title    text not null,
  focus    text not null default '',
  body     text not null default '',
  is_active boolean not null default true,
  unique (kind, period)
);

alter table public.engagement_content enable row level security;
create policy engagement_read on public.engagement_content
  for select to authenticated using (true);
create policy engagement_manage on public.engagement_content
  for all to authenticated using (public.is_case_hq()) with check (public.is_case_hq());

-- ---------------------------------------------------------------------------
-- 6. SCORING RPC — submit one item, scored in the database.
-- ---------------------------------------------------------------------------
create or replace function public.submit_activation_item(
  jid uuid, iid uuid, ans jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  j public.activation_journeys;
  it public.activation_items;
  k jsonb;
  is_owner boolean;
  is_leader boolean;
  correct boolean;
  earned int;
begin
  select * into j from activation_journeys where id = jid;
  if j.id is null then raise exception 'Journey not found'; end if;

  is_owner := (j.profile_id = auth.uid());
  is_leader := is_case_hq() or exists (
    select 1 from profiles p
    where p.id = j.profile_id
      and p.org_unit_id in (select administered_units()));
  if not (is_owner or is_leader) then
    raise exception 'You cannot submit answers for this journey';
  end if;
  if j.status <> 'in_progress' then
    raise exception 'This journey is no longer in progress';
  end if;

  select * into it from activation_items where id = iid;
  if it.id is null then raise exception 'Item not found'; end if;
  if ans is null then raise exception 'An answer is required'; end if;

  select ak.correct into k from activation_keys ak where ak.item_id = iid;

  if it.kind in ('mcq', 'tf') then
    correct := (ans = k);
    earned  := case when correct then it.points else 0 end;
  elsif it.kind = 'checklist' then
    -- complete when every option is ticked
    correct := (jsonb_typeof(ans) = 'array'
                and jsonb_array_length(ans) >= jsonb_array_length(it.options));
    earned  := case when correct then it.points else 0 end;
  else            -- written / ack: recorded, human-reviewed
    correct := null;
    earned  := 0;
  end if;

  insert into activation_item_responses (journey_id, item_id, answer, is_correct, score)
  values (jid, iid, ans, correct, earned)
  on conflict (journey_id, item_id) do update
    set answer = excluded.answer, is_correct = excluded.is_correct,
        score = excluded.score, submitted_at = now();

  return jsonb_build_object(
    'is_correct', correct,
    'score', earned,
    'reveal', case when it.kind in ('mcq','tf','checklist') then k else null end);
end; $$;

-- ---------------------------------------------------------------------------
-- 7. SUMMARY RPC — Day-14 system-compiled evaluation.
-- ---------------------------------------------------------------------------
create or replace function public.activation_summary(jid uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  possible int; earned int; pct int;
  written_total int; written_done int;
  gate6 boolean; gate13 boolean;
  rec text;
begin
  if not can_see_journey(jid) then
    raise exception 'Not authorised';
  end if;

  select coalesce(sum(points), 0) into possible
    from activation_items where kind in ('mcq','tf','checklist') and points > 0;
  select coalesce(sum(r.score), 0) into earned
    from activation_item_responses r
    join activation_items i on i.id = r.item_id
    where r.journey_id = jid and i.kind in ('mcq','tf','checklist');
  pct := case when possible > 0 then round(earned * 100.0 / possible) else 0 end;

  select count(*) into written_total
    from activation_items where kind in ('written','ack') and is_required;
  select count(*) into written_done
    from activation_item_responses r
    join activation_items i on i.id = r.item_id
    where r.journey_id = jid and i.kind in ('written','ack');

  -- Gate 6: every required item on the safeguarding day submitted, and every
  -- auto-scored one on it correct.
  select bool_and(
      exists (select 1 from activation_item_responses r
              where r.journey_id = jid and r.item_id = i.id
                and (i.kind not in ('mcq','tf','checklist') or r.is_correct))
    ) into gate6
    from activation_items i where i.day = 6 and i.is_required;
  gate6 := coalesce(gate6, false);

  -- Gate 13: the commitment checklist completed.
  select bool_and(coalesce(r.is_correct, false)) into gate13
    from activation_items i
    left join activation_item_responses r
      on r.journey_id = jid and r.item_id = i.id
    where i.day = 13 and i.is_required;
  gate13 := coalesce(gate13, false);

  rec := case
    when not (gate6 and gate13) then 'hold'
    when pct >= 70 then 'advance'
    when pct >= 50 then 'mentoring'
    else 'hold' end;

  return jsonb_build_object(
    'possible', possible, 'earned', earned, 'percent', pct,
    'written_total', written_total, 'written_done', written_done,
    'gate6', gate6, 'gate13', gate13, 'recommendation', rec);
end; $$;

-- ---------------------------------------------------------------------------
-- 8. SEED — the 14 days
-- ---------------------------------------------------------------------------
insert into public.activation_days (day, title, kind, is_gate, intro) values
 (1,  'Welcome & Digital Onboarding', 'onboarding', false,
   'Welcome to WODDI. Over the next 14 days we will help you settle in, learn the vision, and get ready to serve. Let''s start by setting up your account.'),
 (2,  'Understanding WODDI', 'knowledge', false,
   'Today is about the heart of WODDI — who we are, who we serve, and why the work matters.'),
 (3,  'Understanding Your Network', 'knowledge', false,
   'WODDI works through networks. Learn the difference between WGMN and WNNN, and who each one serves.'),
 (4,  'Communication', 'written', false,
   'A good leader communicates with warmth and clarity. Practise the kind of replies you''ll send every week.'),
 (5,  'CRM Digital Skills', 'skills', false,
   'Get comfortable with the tools. Complete each hands-on task inside WDOS.'),
 (6,  'Leadership Ethics & Safeguarding', 'gate', true,
   'This is a required checkpoint. Safeguarding and integrity are non-negotiable for every WODDI leader.'),
 (7,  'Midpoint Reflection', 'reflection', false,
   'You''re halfway. Take a quiet moment to reflect on your journey so far.'),
 (8,  'Teamwork', 'cohort', false,
   'Leadership is never solo. Share an idea with your cohort and build on someone else''s.'),
 (9,  'Leadership Thinking', 'worksample', false,
   'Show us how you think. Submit a short, practical plan for your local area.'),
 (10, 'Responsiveness', 'passive', false,
   'A quick, light day. Just confirm the prompts as they arrive.'),
 (11, 'Group Leadership Challenge', 'group', false,
   'Plan together, then handle a tricky situation on your own.'),
 (12, 'Knowledge Confidence Check', 'confidence', false,
   'A short confidence check to consolidate what you''ve learned.'),
 (13, 'Commitment', 'commitment', true,
   'A required checkpoint. Confirm your commitment to the role and to WODDI''s standards.'),
 (14, 'Final Evaluation', 'evaluation', false,
   'You''ve reached the end. This page compiles your journey and shares a provisional recommendation your leader will confirm.')
on conflict (day) do nothing;

-- ---------------------------------------------------------------------------
-- 9. SEED — items (client-safe) and keys (HQ-only), matched by (day, seq)
-- ---------------------------------------------------------------------------
insert into public.activation_items (day, seq, kind, prompt, options, points, is_required) values
 -- Day 1
 (1,1,'checklist','Complete your digital onboarding',
   '["Complete your profile","Upload your passport photo","Verify your email","Accept the Volunteer Agreement","Accept the Code of Conduct","Open the Leadership Handbook and confirm you have read it"]'::jsonb, 0, true),
 (1,2,'mcq','Which document outlines the standards expected of every WODDI volunteer leader?',
   '["A. Annual Report","B. Code of Conduct","C. Financial Statement","D. Newsletter"]'::jsonb, 1, true),
 -- Day 2
 (2,1,'mcq','What does WODDI stand for?',
   '["A. Women of Divine Destiny Initiative","B. Women''s Development & Dignity Initiative","C. Women of Distinction & Direction Initiative","D. Widows & Orphans Development Initiative"]'::jsonb, 1, true),
 (2,2,'mcq','WODDI''s tagline is "The ___."',
   '["A. Leader","B. Builder","C. Nurturer","D. Achiever"]'::jsonb, 1, true),
 (2,3,'mcq','WODDI primarily exists to serve:',
   '["A. Men and boys","B. Women, mothers, girls and young women","C. Government agencies","D. Corporate businesses"]'::jsonb, 1, true),
 (2,4,'mcq','Which is a WODDI programme?',
   '["A. WGMN (Good Mother Network)","B. NYSC","C. UNICEF","D. Rotary Club"]'::jsonb, 1, true),
 (2,5,'mcq','WODDI operates as a:',
   '["A. Political party","B. Pan-African women''s empowerment NGO","C. Commercial company","D. Religious denomination"]'::jsonb, 1, true),
 (2,6,'tf','WODDI''s networks operate across multiple African countries.',
   '["True","False"]'::jsonb, 1, true),
 -- Day 3
 (3,1,'mcq','WGMN stands for:',
   '["A. Women''s Global Mentorship Network","B. Good Mother Network","C. Growing Mothers Network","D. Women Get More Network"]'::jsonb, 1, true),
 (3,2,'mcq','WNNN stands for:',
   '["A. Nurture NextGen Network","B. New Nation Nurses Network","C. Nigeria National Network","D. Nurturing New Nations Network"]'::jsonb, 1, true),
 (3,3,'mcq','WGMN primarily serves:',
   '["A. Girls and young women","B. Women and mothers","C. Male youth","D. Retirees"]'::jsonb, 1, true),
 (3,4,'mcq','WNNN primarily serves:',
   '["A. Girls and young women","B. Grandmothers","C. Corporate staff","D. Government officials"]'::jsonb, 1, true),
 (3,5,'mcq','A volunteer wants to report an issue. Who should they go to first?',
   '["A. The founder","B. Their state / network coordinator","C. Social media","D. Another volunteer"]'::jsonb, 1, true),
 (3,6,'ack','Review the network pillars — WNNN: Identity · Formation · Leadership & Service · Influence & Impact; WGMN: Identity · Nurture & Formation · Leadership & Service · Influence & Legacy — then confirm you have read them.',
   '[]'::jsonb, 0, true),
 -- Day 4
 (4,1,'written','A new member writes: "I don''t understand how to join." Type your reply exactly as you would send it.',
   '[]'::jsonb, 0, true),
 (4,2,'written','Rewrite this to be warm and professional: "You people never respond. This is why nobody takes this group serious."',
   '[]'::jsonb, 0, true),
 (4,3,'written','In 2–3 sentences, welcome a new volunteer to your network.',
   '[]'::jsonb, 0, true),
 -- Day 5
 (5,1,'checklist','Complete each task inside WDOS to show your digital confidence',
   '["Find & open the latest announcement","Download the handbook","Upload any document","Submit a test report","Update a profile field","Reply to the sample notification","Post one message in the discussion forum"]'::jsonb, 0, true),
 -- Day 6 (gate)
 (6,1,'written','Scenario: You accidentally receive confidential information belonging to another chapter. What do you do?',
   '[]'::jsonb, 0, true),
 (6,2,'mcq','A member says a child may be at risk of harm. What is your first action?',
   '["A. Ignore it","B. Handle it quietly yourself","C. Follow the safeguarding procedure and escalate immediately","D. Post about it online"]'::jsonb, 1, true),
 (6,3,'tf','It is acceptable to share a beneficiary''s personal details publicly if you think it helps.',
   '["True","False"]'::jsonb, 1, true),
 (6,4,'mcq','Someone offers you a gift, then asks you to fast-track their application. You:',
   '["A. Accept and help","B. Decline and disclose it to your coordinator","C. Accept and tell no one","D. Ask for more"]'::jsonb, 1, true),
 -- Day 7
 (7,1,'written','What has been your biggest lesson in the programme so far?', '[]'::jsonb, 0, true),
 (7,2,'written','Describe a challenge you have experienced, and how you handled it.', '[]'::jsonb, 0, true),
 (7,3,'written','Why do you still want to serve with WODDI?', '[]'::jsonb, 0, true),
 -- Day 8
 (8,1,'written','Suggest three practical ways to recruit volunteers in your community. If you can, reply to another leader in the cohort forum and build on their idea.',
   '[]'::jsonb, 0, true),
 -- Day 9
 (9,1,'written','Submit a one-page volunteer mobilisation plan (200–300 words) for your local area. Include: (1) your goal, (2) who you would reach, (3) three concrete steps, (4) how you would run it on a small or zero budget.',
   '[]'::jsonb, 0, true),
 -- Day 10 (passive)
 (10,1,'ack','Confirm you have seen today''s check-in.', '[]'::jsonb, 0, true),
 (10,2,'written','Reply with one word describing your week.', '[]'::jsonb, 0, true),
 (10,3,'ack','Meeting reminder — confirm whether you can attend the next team meeting.', '[]'::jsonb, 0, true),
 (10,4,'ack','Re-confirm that one detail on your profile is still correct.', '[]'::jsonb, 0, true),
 -- Day 11
 (11,1,'written','Group challenge: with your team, agree a theme for a mini community awareness event, who does what, and your first action. Post your agreed plan.',
   '[]'::jsonb, 0, true),
 (11,2,'written','Individual scenario: two volunteers disagree publicly in your group chat and it is heating up. Describe, step by step, what you would do.',
   '[]'::jsonb, 0, true),
 -- Day 12
 (12,1,'tf','WODDI''s tagline is "The Nurturer."', '["True","False"]'::jsonb, 1, true),
 (12,2,'tf','WGMN serves women and mothers.', '["True","False"]'::jsonb, 1, true),
 (12,3,'tf','WNNN serves girls and young women.', '["True","False"]'::jsonb, 1, true),
 (12,4,'mcq','Which document sets volunteer standards?',
   '["A. Newsletter","B. Code of Conduct","C. Budget"]'::jsonb, 1, true),
 (12,5,'mcq','A volunteer reports an issue first to:',
   '["A. The founder","B. Their coordinator","C. Social media"]'::jsonb, 1, true),
 (12,6,'mcq','Confidential information received by mistake should be:',
   '["A. Shared","B. Reported and not shared","C. Ignored"]'::jsonb, 1, true),
 (12,7,'mcq','A conflict of interest should be:',
   '["A. Hidden","B. Disclosed to your coordinator","C. Accepted quietly"]'::jsonb, 1, true),
 -- Day 13 (commitment gate)
 (13,1,'checklist','Confirm your commitment',
   '["I can realistically dedicate the time this role requires.","I understand the responsibilities of this role.","I will uphold WODDI''s Code of Conduct at all times.","I will disclose any conflict of interest."]'::jsonb, 0, true)
on conflict (day, seq) do nothing;

-- keys (HQ-only). Matched to items by (day, seq).
insert into public.activation_keys (item_id, correct)
select i.id, k.correct
from (values
  (1,1,'"all"'::jsonb),
  (1,2,'"B"'::jsonb),
  (2,1,'"A"'::jsonb),(2,2,'"C"'::jsonb),(2,3,'"B"'::jsonb),
  (2,4,'"A"'::jsonb),(2,5,'"B"'::jsonb),(2,6,'"True"'::jsonb),
  (3,1,'"B"'::jsonb),(3,2,'"A"'::jsonb),(3,3,'"B"'::jsonb),
  (3,4,'"A"'::jsonb),(3,5,'"B"'::jsonb),
  (5,1,'"all"'::jsonb),
  (6,2,'"C"'::jsonb),(6,3,'"False"'::jsonb),(6,4,'"B"'::jsonb),
  (12,1,'"True"'::jsonb),(12,2,'"True"'::jsonb),(12,3,'"True"'::jsonb),
  (12,4,'"B"'::jsonb),(12,5,'"B"'::jsonb),(12,6,'"B"'::jsonb),(12,7,'"B"'::jsonb),
  (13,1,'"all"'::jsonb)
) as k(day, seq, correct)
join public.activation_items i on i.day = k.day and i.seq = k.seq
on conflict (item_id) do nothing;

-- ---------------------------------------------------------------------------
-- 10. SEED — engagement library (WGMN Engagement Timetable)
-- ---------------------------------------------------------------------------
-- 52 weekly inspiration themes
insert into public.engagement_content (kind, period, title, focus) values
 ('weekly',1,'You Are Part of Something Bigger Than Yourself',''),
 ('weekly',2,'Leadership Begins With the Heart',''),
 ('weekly',3,'Serving With Purpose, Not Pressure',''),
 ('weekly',4,'The Power of Showing Up Consistently',''),
 ('weekly',5,'Women Who Lift Other Women Build Nations',''),
 ('weekly',6,'Your Voice Can Encourage Another Woman',''),
 ('weekly',7,'Leadership Is Not a Title; It Is a Responsibility',''),
 ('weekly',8,'The Quiet Work of Service Still Matters',''),
 ('weekly',9,'A Good Mother Builds Beyond Her Home',''),
 ('weekly',10,'Mentorship Is One Woman Lighting the Path for Another',''),
 ('weekly',11,'You Do Not Need to Be Perfect to Make Impact',''),
 ('weekly',12,'The Strength of a Woman Is Also in Her Compassion',''),
 ('weekly',13,'Building Influence With Humility',''),
 ('weekly',14,'Small Acts of Service Create Lasting Change',''),
 ('weekly',15,'Your Commitment Gives Others Courage',''),
 ('weekly',16,'Leadership Is Service Before Recognition',''),
 ('weekly',17,'Emotional Strength Is a Leadership Gift',''),
 ('weekly',18,'Stay Connected to the Vision',''),
 ('weekly',19,'The Woman You Are Becoming Matters',''),
 ('weekly',20,'Do Not Despise the Small Beginning',''),
 ('weekly',21,'Every Chapter Begins With One Willing Heart',''),
 ('weekly',22,'Encouragement Is Also a Form of Leadership',''),
 ('weekly',23,'A Woman of Purpose Does Not Serve in Vain',''),
 ('weekly',24,'Your Influence Can Strengthen Families',''),
 ('weekly',25,'Leadership Requires Patience and Grace',''),
 ('weekly',26,'You Are Growing While You Are Serving',''),
 ('weekly',27,'Service Should Build You, Not Break You',''),
 ('weekly',28,'Strong Women Create Safe Spaces for Others',''),
 ('weekly',29,'The Power of Sisterhood Across Africa',''),
 ('weekly',30,'Your Consistency Is Creating Trust',''),
 ('weekly',31,'Digital Leadership Is Still Real Leadership',''),
 ('weekly',32,'A Leader Learns Before She Leads',''),
 ('weekly',33,'The Best Leaders Listen Deeply',''),
 ('weekly',34,'You Are Not Alone in This Assignment',''),
 ('weekly',35,'Women Who Serve With Love Leave Footprints',''),
 ('weekly',36,'Your Leadership Can Heal, Guide and Inspire',''),
 ('weekly',37,'Family Leadership Begins With Values',''),
 ('weekly',38,'Community Transformation Begins With Concern',''),
 ('weekly',39,'Courage Is Needed for Every New Level',''),
 ('weekly',40,'Do Not Lose the Joy of Serving',''),
 ('weekly',41,'A Good Mother Raises, Guides and Restores',''),
 ('weekly',42,'The Power of Positive Influence',''),
 ('weekly',43,'What You Build in People Will Outlive You',''),
 ('weekly',44,'Leadership Is Also Emotional Maturity',''),
 ('weekly',45,'Your Example Is Teaching Someone',''),
 ('weekly',46,'Faith, Courage and Resilience in Leadership',''),
 ('weekly',47,'WGMN Is a Movement of Women Building Women',''),
 ('weekly',48,'A Volunteer With Vision Is Never Small',''),
 ('weekly',49,'Appreciation Keeps the Heart of Service Alive',''),
 ('weekly',50,'Look Back and See How Far You Have Come',''),
 ('weekly',51,'Celebrating Service, Growth and Sisterhood',''),
 ('weekly',52,'Renewing the Vision for a Greater Year Ahead','')
on conflict (kind, period) do nothing;

-- 12 monthly inspirational messages
insert into public.engagement_content (kind, period, title, focus) values
 ('monthly',1,'A New Month and New Year to Serve With Purpose','Begin the year with clarity, commitment and renewed vision'),
 ('monthly',2,'Understanding the Heart of the WGMN Vision','Stay connected to the purpose of WGMN'),
 ('monthly',3,'Why Your Leadership Matters','Your role is meaningful and valuable'),
 ('monthly',4,'Serving With Grace, Not Pressure','Serve without feeling overwhelmed'),
 ('monthly',5,'Growing as a Woman While Serving Other Women','Service should also build you personally'),
 ('monthly',6,'Leading From the Heart','Compassion, humility and emotional connection'),
 ('monthly',7,'Building Africa Through Women','The wider continental impact of women''s leadership'),
 ('monthly',8,'The Power of One Committed Woman','One committed woman can influence many lives'),
 ('monthly',9,'Staying Connected to the WGMN Vision','Renew alignment and prevent disconnection'),
 ('monthly',10,'Strength for the Woman Who Serves','Resilience, emotional strength and consistency'),
 ('monthly',11,'The Beauty of Appreciation and Service','Reflect on the value of service and gratitude'),
 ('monthly',12,'Renewing the Vision for the Year Ahead','Close the year with reflection, gratitude and renewed commitment')
on conflict (kind, period) do nothing;

-- 12 monthly leadership development masterclasses
insert into public.engagement_content (kind, period, title, focus) values
 ('masterclass',1,'Understanding Yourself as a Woman Leader','Identity, self-awareness and purpose'),
 ('masterclass',2,'Emotional Intelligence for Women Leaders','Emotional maturity, self-control and empathy'),
 ('masterclass',3,'Building Healthy Personal Relationships','Communication, respect, boundaries and emotional wisdom'),
 ('masterclass',4,'Leading With Confidence and Humility','Confidence, humility and positive influence'),
 ('masterclass',5,'Personal Effectiveness and Time Management','Discipline, priorities and balance'),
 ('masterclass',6,'Communication Skills for Volunteer Leaders','Speaking clearly, listening well and relating wisely'),
 ('masterclass',7,'Family Leadership and Emotional Balance','Home, family, service and inner stability'),
 ('masterclass',8,'Mentorship as a Tool for Women''s Growth','Guidance, learning and supporting others'),
 ('masterclass',9,'Building Resilience in Difficult Seasons','Courage, patience and strength under pressure'),
 ('masterclass',10,'Digital Leadership and Online Professionalism','Digital conduct, online meetings and virtual influence'),
 ('masterclass',11,'Conflict Management and Emotional Maturity','Handling disagreements with wisdom'),
 ('masterclass',12,'Reflection, Gratitude and Renewed Commitment','Reviewing growth and preparing for a new year')
on conflict (kind, period) do nothing;

insert into public.schema_migrations (version, name)
values (30, 'activation_content') on conflict (version) do nothing;
