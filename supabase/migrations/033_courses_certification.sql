-- ============================================================================
-- WDOS Migration 033 — Courses & Certification (Phase 37)
--
-- The engagement document's curricula become real, gated courses:
--   Course VLSE-PD — Volunteer Leadership Strategic Engagement:
--                    Personal Development (12 modules, from the monthly
--                    leadership development masterclass curriculum)
--   Course WGMN-VP — The WGMN Vision & Purpose Series (12 modules, from
--                    the monthly inspirational topics)
-- Each module = a lesson + a 3-question knowledge check. A module must be
-- passed (2 of 3 or better, retakes allowed) before the next unlocks —
-- enforced in the database, not just the screen. Completing all modules
-- issues a numbered certificate (name + course + date) rendered in-app,
-- downloadable as an image or printed to PDF. course_stats() feeds the
-- master CRM dashboard and Reports.
-- ============================================================================

create table public.courses (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  title text not null,
  description text not null default '',
  is_active boolean not null default true
);
create table public.course_modules (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses(id) on delete cascade,
  seq int not null,
  title text not null,
  lesson text not null,
  unique (course_id, seq)
);
create table public.course_questions (
  id uuid primary key default gen_random_uuid(),
  module_id uuid not null references public.course_modules(id) on delete cascade,
  seq int not null,
  prompt text not null,
  options jsonb not null,
  unique (module_id, seq)
);
create table public.course_keys (
  question_id uuid primary key references public.course_questions(id) on delete cascade,
  correct text not null
);
create table public.course_enrollments (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  cert_no text unique,
  unique (course_id, profile_id)
);
create table public.course_module_passes (
  enrollment_id uuid not null references public.course_enrollments(id) on delete cascade,
  module_id uuid not null references public.course_modules(id) on delete cascade,
  score int not null default 0,
  total int not null default 0,
  passed boolean not null default false,
  completed_at timestamptz not null default now(),
  primary key (enrollment_id, module_id)
);
create sequence if not exists public.cert_seq;

alter table public.courses enable row level security;
alter table public.course_modules enable row level security;
alter table public.course_questions enable row level security;
alter table public.course_keys enable row level security;
alter table public.course_enrollments enable row level security;
alter table public.course_module_passes enable row level security;

create policy courses_read on public.courses for select to authenticated using (true);
create policy modules_read on public.course_modules for select to authenticated using (true);
create policy questions_read on public.course_questions for select to authenticated using (true);
create policy keys_hq on public.course_keys for all to authenticated
  using (public.is_case_hq()) with check (public.is_case_hq());
create policy enroll_own_read on public.course_enrollments for select to authenticated
  using (profile_id = auth.uid() or public.is_case_hq());
create policy passes_own_read on public.course_module_passes for select to authenticated
  using (exists (select 1 from public.course_enrollments e
                  where e.id = enrollment_id
                    and (e.profile_id = auth.uid() or public.is_case_hq())));
create policy courses_manage on public.courses for all to authenticated
  using (public.is_case_hq()) with check (public.is_case_hq());
create policy modules_manage on public.course_modules for all to authenticated
  using (public.is_case_hq()) with check (public.is_case_hq());
create policy questions_manage on public.course_questions for all to authenticated
  using (public.is_case_hq()) with check (public.is_case_hq());
-- enrollments/passes are written only by the RPCs below

create or replace function public.enroll_course(cid uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare eid uuid;
begin
  insert into course_enrollments (course_id, profile_id)
  values (cid, auth.uid())
  on conflict (course_id, profile_id) do nothing;
  select id into eid from course_enrollments
   where course_id = cid and profile_id = auth.uid();
  return eid;
end; $$;

create or replace function public.submit_course_module(
  eid uuid, mid uuid, answers jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  e public.course_enrollments;
  m public.course_modules;
  qrec record;
  ans text; sc int := 0; tot int := 0;
  ok boolean;
  reveal jsonb := '{}'::jsonb;
  prev_passed boolean;
  all_passed boolean;
  cert text;
begin
  select * into e from course_enrollments where id = eid;
  if e.id is null or e.profile_id <> auth.uid() then
    raise exception 'Enrollment not found';
  end if;
  select * into m from course_modules where id = mid;
  if m.id is null or m.course_id <> e.course_id then
    raise exception 'Module not found in this course';
  end if;
  if m.seq > 1 then
    select coalesce(p.passed, false) into prev_passed
      from course_modules pm
      left join course_module_passes p
        on p.module_id = pm.id and p.enrollment_id = eid
     where pm.course_id = e.course_id and pm.seq = m.seq - 1;
    if not coalesce(prev_passed, false) then
      raise exception 'Pass the previous module first';
    end if;
  end if;
  if exists (select 1 from course_module_passes
              where enrollment_id = eid and module_id = mid and passed) then
    raise exception 'Module already passed';
  end if;

  for qrec in
    select cq.id, ck.correct from course_questions cq
      join course_keys ck on ck.question_id = cq.id
     where cq.module_id = mid order by cq.seq
  loop
    tot := tot + 1;
    ans := answers->>(qrec.id::text);
    if ans is not null and ans = qrec.correct then sc := sc + 1; end if;
    reveal := reveal || jsonb_build_object(qrec.id::text, qrec.correct);
  end loop;
  if tot = 0 then raise exception 'This module has no questions'; end if;

  ok := sc >= greatest(1, tot - 1);   -- pass = at most one wrong

  insert into course_module_passes (enrollment_id, module_id, score, total, passed)
  values (eid, mid, sc, tot, ok)
  on conflict (enrollment_id, module_id) do update
    set score = excluded.score, total = excluded.total,
        passed = excluded.passed, completed_at = now();

  cert := null;
  if ok then
    select bool_and(coalesce(p.passed, false)) into all_passed
      from course_modules cm
      left join course_module_passes p
        on p.module_id = cm.id and p.enrollment_id = eid
     where cm.course_id = e.course_id;
    if coalesce(all_passed, false) and e.completed_at is null then
      cert := 'WODDI-' || to_char(now(), 'YYYY') || '-'
              || lpad(nextval('cert_seq')::text, 5, '0');
      update course_enrollments
         set completed_at = now(), cert_no = cert
       where id = eid;
    end if;
  end if;

  return jsonb_build_object('score', sc, 'total', tot, 'passed', ok,
    'reveal', reveal, 'cert_no', cert);
end; $$;

create or replace function public.course_stats()
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not is_case_hq() then raise exception 'HQ only'; end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'code', c.code, 'title', c.title,
      'enrolled', (select count(*) from course_enrollments e where e.course_id = c.id),
      'completed', (select count(*) from course_enrollments e
                     where e.course_id = c.id and e.completed_at is not null)
    ) order by c.code), '[]'::jsonb)
    from courses c where c.is_active);
end; $$;
insert into public.courses (code, title, description) values ('VLSE-PD', 'Volunteer Leadership Strategic Engagement: Personal Development', 'The twelve-module personal development masterclass for WODDI volunteer leaders — identity, emotional intelligence, relationships, effectiveness, resilience and renewal.') on conflict (code) do nothing;
insert into public.course_modules (course_id, seq, title, lesson)
select id, 1, 'Understanding Yourself as a Woman Leader', 'Leadership begins inside. Before a woman can guide others, she needs a clear, honest picture of who she is: her values, her strengths, her limits, and the purpose that pulls her forward. Self-awareness is not pride and it is not self-criticism — it is simply telling yourself the truth with kindness. A leader who knows her identity does not need every situation to affirm her; she can serve calmly because her worth is settled. This module invites you to name your core values, notice how you respond under pressure, and write a simple personal purpose statement you can return to whenever the work feels heavy.' from public.courses where code = 'VLSE-PD'
on conflict (course_id, seq) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 1, 'What is the healthiest description of self-awareness?', '["A. Thinking highly of yourself at all times", "B. Telling yourself the truth with kindness", "C. Comparing yourself with other leaders", "D. Hiding your weaknesses from your team"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 1
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'B' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 1 and cq.seq = 1
on conflict (question_id) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 2, 'A leader whose worth is settled…', '["A. Needs every situation to affirm her", "B. Avoids all difficult feedback", "C. Can serve calmly under pressure", "D. Never makes mistakes"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 1
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'C' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 1 and cq.seq = 2
on conflict (question_id) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 3, 'A personal purpose statement is useful because it…', '["A. Impresses other volunteers", "B. Replaces the need for planning", "C. Gives you something to return to when work feels heavy", "D. Is required for promotion"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 1
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'C' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 1 and cq.seq = 3
on conflict (question_id) do nothing;
insert into public.course_modules (course_id, seq, title, lesson)
select id, 2, 'Emotional Intelligence for Women Leaders', 'Emotional intelligence is the ability to notice what you are feeling, manage it wisely, and respond to other people''s feelings with empathy. In volunteer leadership it matters more than talent: one harsh reply in a group chat can undo months of trust. Practise the pause — feel the emotion, name it, then choose your response instead of reacting. Empathy means listening to understand, not to win. And self-control is not suppressing feelings; it is expressing them at the right time, in the right way, to the right person. Leaders who master this create teams where people feel safe, seen and motivated.' from public.courses where code = 'VLSE-PD'
on conflict (course_id, seq) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 1, 'Emotional intelligence starts with…', '["A. Ignoring your feelings", "B. Noticing and naming what you feel", "C. Keeping others at a distance", "D. Winning every argument"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 2
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'B' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 2 and cq.seq = 1
on conflict (question_id) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 2, '''Practising the pause'' means…', '["A. Delaying all decisions for a week", "B. Feeling, naming, then choosing your response", "C. Staying silent permanently", "D. Leaving the group chat"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 2
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'B' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 2 and cq.seq = 2
on conflict (question_id) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 3, 'Empathy is listening…', '["A. To understand", "B. To win", "C. To reply quickly", "D. To judge"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 2
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'A' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 2 and cq.seq = 3
on conflict (question_id) do nothing;
insert into public.course_modules (course_id, seq, title, lesson)
select id, 3, 'Building Healthy Personal Relationships', 'Healthy relationships — at home, in your chapter, and online — are built from the same materials: clear communication, mutual respect, and boundaries. A boundary is not a wall; it is a door with a handle on your side. Saying ''I can help on Saturday, but not tonight'' protects both your service and your family. Respect means honouring people''s time, confidences and differences, even in disagreement. And emotional wisdom means raising concerns early and privately rather than letting resentment grow. Volunteers stay where relationships are safe; this module helps you become someone people feel safe around.' from public.courses where code = 'VLSE-PD'
on conflict (course_id, seq) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 1, 'A boundary is best described as…', '["A. A wall that keeps people away", "B. A door with a handle on your side", "C. A way to avoid responsibility", "D. A punishment for others"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 3
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'B' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 3 and cq.seq = 1
on conflict (question_id) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 2, 'Concerns are best raised…', '["A. Publicly, so everyone learns", "B. Never — keep the peace", "C. Early and privately", "D. Only in writing to HQ"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 3
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'C' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 3 and cq.seq = 2
on conflict (question_id) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 3, 'Respect in a team includes honouring people''s…', '["A. Time, confidences and differences", "B. Mistakes only", "C. Titles only", "D. Social media accounts"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 3
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'A' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 3 and cq.seq = 3
on conflict (question_id) do nothing;
insert into public.course_modules (course_id, seq, title, lesson)
select id, 4, 'Leading With Confidence and Humility', 'Confidence and humility are not opposites — mature leaders carry both. Confidence says ''I can contribute something valuable''; humility says ''I still have much to learn, and so does everyone I serve with.'' Together they create positive influence: people follow leaders who are sure enough to decide and humble enough to listen. Beware the two counterfeits: arrogance, which cannot receive feedback, and false modesty, which refuses responsibility. When you make a mistake, own it plainly and fix it — nothing builds credibility faster. When you succeed, share the credit — nothing builds loyalty faster.' from public.courses where code = 'VLSE-PD'
on conflict (course_id, seq) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 1, 'Confidence and humility together produce…', '["A. Confusion", "B. Positive influence", "C. Slower decisions", "D. Competition"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 4
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'B' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 4 and cq.seq = 1
on conflict (question_id) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 2, 'Arrogance is dangerous because it…', '["A. Cannot receive feedback", "B. Makes leaders too quiet", "C. Shares too much credit", "D. Delegates too often"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 4
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'A' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 4 and cq.seq = 2
on conflict (question_id) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 3, 'When you make a mistake as a leader, you should…', '["A. Explain why it wasn''t your fault", "B. Own it plainly and fix it", "C. Wait for someone to notice", "D. Step down immediately"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 4
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'B' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 4 and cq.seq = 3
on conflict (question_id) do nothing;
insert into public.course_modules (course_id, seq, title, lesson)
select id, 5, 'Personal Effectiveness and Time Management', 'Time is the one resource every volunteer leader has in equal measure — what differs is how we spend it. Effectiveness starts with priorities: decide the two or three things that matter most this week, and protect time for them before smaller tasks flood in. Use simple tools faithfully: a weekly plan, a task list, and honest deadlines. Learn the power of a kind ''no'' and a realistic ''yes''. Balance is part of discipline, not a break from it: rest, family and worship refill the well your service draws from. A tired leader serves no one well; a rested one lifts everyone.' from public.courses where code = 'VLSE-PD'
on conflict (course_id, seq) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 1, 'Effectiveness starts with…', '["A. Answering every message instantly", "B. Deciding and protecting your top priorities", "C. Working longer hours", "D. Avoiding plans"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 5
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'B' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 5 and cq.seq = 1
on conflict (question_id) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 2, 'A realistic ''yes'' and a kind ''no'' help you…', '["A. Avoid all responsibility", "B. Protect what matters most", "C. Impress the coordinator", "D. Fill your calendar"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 5
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'B' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 5 and cq.seq = 2
on conflict (question_id) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 3, 'Rest and family time are…', '["A. Obstacles to service", "B. Rewards for finishing everything", "C. Part of the discipline that sustains service", "D. Optional for leaders"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 5
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'C' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 5 and cq.seq = 3
on conflict (question_id) do nothing;
insert into public.course_modules (course_id, seq, title, lesson)
select id, 6, 'Communication Skills for Volunteer Leaders', 'Most leadership happens through words. Clear communication has three habits: think before you send, keep the message simple, and match the channel to the moment — sensitive matters deserve a call, not a broadcast. Listening is half of communication: give full attention, ask one good question, and repeat back what you heard before responding. In groups, your tone sets the temperature; warmth plus clarity beats either alone. And always close the loop: confirm decisions, thank contributors, and follow up on promises. People forgive imperfect grammar; they rarely forgive feeling ignored.' from public.courses where code = 'VLSE-PD'
on conflict (course_id, seq) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 1, 'Sensitive matters are best handled by…', '["A. A broadcast message", "B. A public post", "C. A personal call or private conversation", "D. Silence"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 6
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'C' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 6 and cq.seq = 1
on conflict (question_id) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 2, 'Good listening includes…', '["A. Preparing your reply while others speak", "B. Repeating back what you heard", "C. Interrupting to save time", "D. Multitasking"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 6
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'B' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 6 and cq.seq = 2
on conflict (question_id) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 3, '''Closing the loop'' means…', '["A. Ending the group chat", "B. Confirming decisions and following up on promises", "C. Muting notifications", "D. Archiving messages"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 6
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'B' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 6 and cq.seq = 3
on conflict (question_id) do nothing;
insert into public.course_modules (course_id, seq, title, lesson)
select id, 7, 'Family Leadership and Emotional Balance', 'Your first network is your home. WODDI never asks a woman to sacrifice her family on the altar of service — a leader whose home is neglected carries that weight into everything else. Family leadership means presence: planned, protected time that phones do not interrupt. It means communicating your volunteer commitments at home so service is shared, not resented. Emotional balance grows from rhythms — rest, reflection, and honest conversations — so pressure at home does not spill into your chapter, and pressure in your chapter does not spill into your home. A stable heart is your greatest leadership tool.' from public.courses where code = 'VLSE-PD'
on conflict (course_id, seq) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 1, 'WODDI''s view of family and service is that…', '["A. Service always comes first", "B. Family should never know about your service", "C. A neglected home weakens everything else", "D. Leaders should avoid family duties"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 7
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'C' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 7 and cq.seq = 1
on conflict (question_id) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 2, 'Protected family time works best when it is…', '["A. Spontaneous and rare", "B. Planned and free of phone interruptions", "C. Only during holidays", "D. Replaced by messages"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 7
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'B' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 7 and cq.seq = 2
on conflict (question_id) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 3, 'Emotional balance grows from…', '["A. Ignoring pressure", "B. Rhythms of rest, reflection and honest conversation", "C. Working faster", "D. Avoiding people"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 7
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'B' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 7 and cq.seq = 3
on conflict (question_id) do nothing;
insert into public.course_modules (course_id, seq, title, lesson)
select id, 8, 'Mentorship as a Tool for Women''s Growth', 'Mentorship is one woman lighting the path for another. You do not need to be perfect to mentor — you need to be one step ahead and willing to walk beside someone. Good mentors ask more than they tell: questions like ''What have you tried?'' and ''What would you do if you weren''t afraid?'' unlock more growth than instructions. Being mentored is equally a skill: come with real questions, act on advice, and report back. In WODDI, every leader should be able to name one woman she is learning from and one woman she is lifting. That chain is how movements grow.' from public.courses where code = 'VLSE-PD'
on conflict (course_id, seq) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 1, 'To mentor someone you must be…', '["A. Perfect", "B. One step ahead and willing to walk beside her", "C. A certified trainer", "D. Older than her"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 8
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'B' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 8 and cq.seq = 1
on conflict (question_id) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 2, 'Good mentors mostly…', '["A. Give instructions", "B. Ask growth-unlocking questions", "C. Solve every problem themselves", "D. Talk about their achievements"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 8
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'B' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 8 and cq.seq = 2
on conflict (question_id) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 3, 'Every WODDI leader should be able to name…', '["A. One woman she learns from and one she lifts", "B. Ten mentees", "C. Her favourite book", "D. All national coordinators"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 8
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'A' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 8 and cq.seq = 3
on conflict (question_id) do nothing;
insert into public.course_modules (course_id, seq, title, lesson)
select id, 9, 'Building Resilience in Difficult Seasons', 'Every volunteer leader meets difficult seasons: low turnout, criticism, personal loss, or simple exhaustion. Resilience is not pretending it doesn''t hurt — it is the practised ability to bend without breaking. Three habits build it. Perspective: ask ''what is this season teaching me?'' rather than ''why me?''. Support: resilient leaders are never alone; they have people who can hear the unpolished truth. Small faithful steps: when you cannot do everything, do the next right thing. Courage is not the absence of fear; it is moving forward with your fear properly named and your hope firmly held.' from public.courses where code = 'VLSE-PD'
on conflict (course_id, seq) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 1, 'Resilience means…', '["A. Pretending nothing hurts", "B. Bending without breaking", "C. Avoiding all difficulty", "D. Working alone"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 9
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'B' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 9 and cq.seq = 1
on conflict (question_id) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 2, 'A resilient leader''s support system exists so she can…', '["A. Delegate everything", "B. Share the unpolished truth safely", "C. Avoid her team", "D. Win arguments"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 9
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'B' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 9 and cq.seq = 2
on conflict (question_id) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 3, 'When you cannot do everything, you should…', '["A. Do nothing until strength returns", "B. Do the next right thing", "C. Resign", "D. Complain publicly"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 9
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'B' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 9 and cq.seq = 3
on conflict (question_id) do nothing;
insert into public.course_modules (course_id, seq, title, lesson)
select id, 10, 'Digital Leadership and Online Professionalism', 'Digital leadership is still real leadership. Your online conduct — in WhatsApp groups, on social media, in WDOS — is your public character. Three standards keep you professional: pause before posting (would you say it face to face?), protect confidentiality (never share member details or screenshots without consent), and be punctual and prepared in online meetings just as you would be in person. Virtual influence is built through consistency: showing up, responding within a reasonable time, and keeping a warm, clear tone. The internet forgets nothing — let everything it remembers about you serve the mission.' from public.courses where code = 'VLSE-PD'
on conflict (course_id, seq) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 1, 'Before posting online, a leader should ask…', '["A. Will this get likes?", "B. Would I say this face to face?", "C. Who will disagree?", "D. Is it long enough?"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 10
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'B' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 10 and cq.seq = 1
on conflict (question_id) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 2, 'Sharing screenshots of member conversations is…', '["A. Fine within the team", "B. Allowed if names are visible", "C. A confidentiality breach without consent", "D. Required for records"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 10
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'C' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 10 and cq.seq = 2
on conflict (question_id) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 3, 'Virtual influence is built mainly through…', '["A. Long messages", "B. Consistency, responsiveness and warm clarity", "C. Frequent forwarding", "D. Being online at midnight"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 10
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'B' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 10 and cq.seq = 3
on conflict (question_id) do nothing;
insert into public.course_modules (course_id, seq, title, lesson)
select id, 11, 'Conflict Management and Emotional Maturity', 'Where people serve together, conflict will visit — the question is whether it leaves the team weaker or wiser. Handle disagreement with the private-first principle: speak directly and kindly with the person before involving anyone else, and escalate to your coordinator only when direct conversation fails or safety is involved. Attack problems, never people: ''the report is late'' can be discussed; ''you are useless'' cannot be taken back. Listen for the interest under the position — people often fight about a task when they actually feel unseen. Emotional maturity is refusing to let one hot moment cancel a long relationship.' from public.courses where code = 'VLSE-PD'
on conflict (course_id, seq) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 1, 'The first step in most conflicts is…', '["A. Posting in the group chat", "B. A direct, kind, private conversation", "C. Reporting to the founder", "D. Ignoring it"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 11
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'B' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 11 and cq.seq = 1
on conflict (question_id) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 2, '''Attack problems, never people'' means…', '["A. Avoiding all criticism", "B. Discussing the issue without insulting the person", "C. Blaming the system", "D. Staying silent"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 11
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'B' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 11 and cq.seq = 2
on conflict (question_id) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 3, 'Underneath many conflicts, people actually feel…', '["A. Unseen or unheard", "B. Bored", "C. Overpaid", "D. Too appreciated"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 11
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'A' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 11 and cq.seq = 3
on conflict (question_id) do nothing;
insert into public.course_modules (course_id, seq, title, lesson)
select id, 12, 'Reflection, Gratitude and Renewed Commitment', 'Growth that is never reviewed is easily lost. Reflection is the leader''s habit of looking back on purpose: What did I learn this season? Where did I grow? Whom should I thank? Gratitude turns service from a duty into a joy — a leader who counts what went right serves with a lighter heart than one who only counts what went wrong. Renewal completes the cycle: name what you will carry forward, what you will lay down, and one commitment for the season ahead. Write it down; revisit it. Movements are renewed one recommitted woman at a time — beginning with you.' from public.courses where code = 'VLSE-PD'
on conflict (course_id, seq) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 1, 'Reflection means…', '["A. Regretting the past", "B. Looking back on purpose to learn", "C. Repeating last year''s plan", "D. Comparing yourself to others"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 12
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'B' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 12 and cq.seq = 1
on conflict (question_id) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 2, 'Gratitude changes service by…', '["A. Reducing the workload", "B. Making it a lighter, joyful duty", "C. Removing all challenges", "D. Earning rewards"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 12
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'B' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 12 and cq.seq = 2
on conflict (question_id) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 3, 'Healthy renewal includes naming what to…', '["A. Carry forward, lay down, and commit to", "B. Complain about", "C. Delegate permanently", "D. Postpone"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 12
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'A' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'VLSE-PD' and m.seq = 12 and cq.seq = 3
on conflict (question_id) do nothing;
insert into public.courses (code, title, description) values ('WGMN-VP', 'The WGMN Vision & Purpose Series', 'Twelve modules on the heart of the Good Mother Network — purpose, vision, grace-filled service, and the power of committed women building Africa.') on conflict (code) do nothing;
insert into public.course_modules (course_id, seq, title, lesson)
select id, 1, 'A New Season to Serve With Purpose', 'Every new season — a new year, a new role, a new chapter — is an invitation to serve on purpose rather than out of habit. Purpose gives service direction: you are not merely busy for WODDI, you are building women, families and communities. Begin each season by asking three questions: What is God and this mission asking of me now? What must I do differently? Who will I do it with? Write your answers where you will see them. A volunteer with clarity outlasts a volunteer with mere enthusiasm, because clarity survives the weeks when feelings run low.' from public.courses where code = 'WGMN-VP'
on conflict (course_id, seq) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 1, 'Purpose turns service from busyness into…', '["A. Obligation", "B. Building people and communities", "C. Routine", "D. Competition"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 1
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'B' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 1 and cq.seq = 1
on conflict (question_id) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 2, 'Clarity outlasts enthusiasm because it…', '["A. Survives low-feeling weeks", "B. Requires no planning", "C. Is louder", "D. Comes with a title"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 1
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'A' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 1 and cq.seq = 2
on conflict (question_id) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 3, 'A good season begins by asking…', '["A. What went viral?", "B. What is being asked of me now?", "C. Who is watching?", "D. When is the next break?"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 1
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'B' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 1 and cq.seq = 3
on conflict (question_id) do nothing;
insert into public.course_modules (course_id, seq, title, lesson)
select id, 2, 'The Heart of the WGMN Vision', 'WGMN — the Good Mother Network — exists because nations rise where mothers are strengthened. Its heart is simple: nurture women, and women will nurture families, and families will renew communities. Every task in WDOS, every meeting, every message traces back to that heartbeat. When the work feels administrative, reconnect to a face: a mother encouraged, a home steadied, a woman who found her voice. Vision leaks under pressure, so refill it deliberately — revisit the concept note, share member stories, and remind your team monthly why the network exists. Leaders who stay connected to the heart keep everyone else''s heart alive.' from public.courses where code = 'WGMN-VP'
on conflict (course_id, seq) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 1, 'WGMN''s core belief is that nations rise when…', '["A. Mothers are strengthened", "B. Offices are opened", "C. Events are frequent", "D. Reports are long"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 2
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'A' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 2 and cq.seq = 1
on conflict (question_id) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 2, 'When work feels administrative, reconnect by…', '["A. Taking a long break", "B. Remembering a real face and story", "C. Adding more forms", "D. Skipping meetings"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 2
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'B' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 2 and cq.seq = 2
on conflict (question_id) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 3, 'Vision ''leaks'', so leaders should…', '["A. Refill it deliberately and share stories", "B. Mention it once a year", "C. Keep it private", "D. Replace it often"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 2
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'A' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 2 and cq.seq = 3
on conflict (question_id) do nothing;
insert into public.course_modules (course_id, seq, title, lesson)
select id, 3, 'Why Your Leadership Matters', 'It is easy to feel small in a continental movement — one volunteer among thousands. But networks are not built from headquarters; they are built from the nearest trusted woman, and in your community that woman is you. Your welcome decides whether a newcomer stays. Your follow-up decides whether a struggling member is found. Your example teaches more than any manual. Leadership in WODDI is measured not by title but by presence: being reachable, reliable and kind, week after week. History rarely records the faithful; heaven and your community always do. Your role matters — lead it fully.' from public.courses where code = 'WGMN-VP'
on conflict (course_id, seq) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 1, 'WODDI''s network is truly built by…', '["A. Headquarters alone", "B. The nearest trusted woman in each community", "C. Annual conferences", "D. Documents"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 3
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'B' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 3 and cq.seq = 1
on conflict (question_id) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 2, 'A newcomer''s decision to stay often depends on…', '["A. The website", "B. Your welcome and follow-up", "C. The weather", "D. Certificates"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 3
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'B' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 3 and cq.seq = 2
on conflict (question_id) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 3, 'WODDI measures leadership mainly by…', '["A. Title", "B. Presence — reachable, reliable, kind", "C. Years of service", "D. Number of posts"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 3
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'B' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 3 and cq.seq = 3
on conflict (question_id) do nothing;
insert into public.course_modules (course_id, seq, title, lesson)
select id, 4, 'Serving With Grace, Not Pressure', 'Grace-filled service flows from love; pressured service leaks from guilt — and guilt always runs dry. If your volunteering has become a weight, pause and rebalance: review your commitments with your coordinator honestly, keep what fits this season of your life, and release what does not. Saying ''this season I can give two hours a week'' is mature leadership, not weakness. Protect the joy: celebrate small wins, rest without apology, and remember you are a member of this family before you are a worker in it. WODDI wants you whole for years, not burnt out by December.' from public.courses where code = 'WGMN-VP'
on conflict (course_id, seq) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 1, 'Pressured service eventually fails because it runs on…', '["A. Love", "B. Guilt", "C. Skill", "D. Habit"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 4
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'B' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 4 and cq.seq = 1
on conflict (question_id) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 2, 'Telling your coordinator ''I can give two hours weekly this season'' is…', '["A. Weakness", "B. Mature, honest leadership", "C. Rebellion", "D. A resignation"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 4
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'B' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 4 and cq.seq = 2
on conflict (question_id) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 3, 'WODDI''s preference is a volunteer who is…', '["A. Burnt out but busy", "B. Whole and serving for years", "C. Always available", "D. Silent about limits"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 4
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'B' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 4 and cq.seq = 3
on conflict (question_id) do nothing;
insert into public.course_modules (course_id, seq, title, lesson)
select id, 5, 'Growing While Serving Other Women', 'Service is a school. Every event you organise teaches planning; every difficult conversation teaches diplomacy; every report teaches clarity. Do not only pour out — also notice what is being poured in, and steward it. Keep a simple growth journal: skills gained, lessons learned, fears outgrown. Ask for stretch assignments that develop you, and take the masterclasses this platform offers. A network of growing women is unstoppable; a network of depleting women is temporary. When you grow while serving, your service deepens — and the woman who finishes the year is stronger than the one who began it.' from public.courses where code = 'WGMN-VP'
on conflict (course_id, seq) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 1, 'Service is described as…', '["A. A drain", "B. A school", "C. A performance", "D. A contest"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 5
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'B' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 5 and cq.seq = 1
on conflict (question_id) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 2, 'A growth journal records…', '["A. Complaints", "B. Skills, lessons and fears outgrown", "C. Other people''s errors", "D. Meeting minutes"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 5
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'B' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 5 and cq.seq = 2
on conflict (question_id) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 3, 'A network of growing women is…', '["A. Unstoppable", "B. Expensive", "C. Rare and unnecessary", "D. Temporary"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 5
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'A' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 5 and cq.seq = 3
on conflict (question_id) do nothing;
insert into public.course_modules (course_id, seq, title, lesson)
select id, 6, 'Leading From the Heart', 'People forget instructions; they remember how you made them feel. Leading from the heart means letting compassion shape your decisions: the late report may hide a sick child; the quiet member may be carrying grief. Ask before judging. It means humility — being quick to say ''I was wrong'' and ''thank you''. And it means genuine connection: knowing names, remembering situations, celebrating birthdays and milestones. Heart-led leadership is not soft on standards; it is soft on people while holding the mission firmly. That combination — warm heart, steady hands — is the signature of a WODDI leader.' from public.courses where code = 'WGMN-VP'
on conflict (course_id, seq) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 1, 'People most remember a leader''s…', '["A. Instructions", "B. How she made them feel", "C. Spreadsheets", "D. Titles"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 6
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'B' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 6 and cq.seq = 1
on conflict (question_id) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 2, 'A late report or quiet member should first prompt…', '["A. Public correction", "B. A caring question", "C. Removal", "D. Silence"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 6
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'B' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 6 and cq.seq = 2
on conflict (question_id) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 3, 'Heart-led leadership holds…', '["A. Soft standards and soft people", "B. Firm mission and warm treatment of people", "C. Neither standards nor warmth", "D. Rules above people"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 6
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'B' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 6 and cq.seq = 3
on conflict (question_id) do nothing;
insert into public.course_modules (course_id, seq, title, lesson)
select id, 7, 'Building Africa Through Women', 'WODDI is a pan-African movement because Africa''s renewal runs through her women. When a mother learns, a household learns; when women lead, communities stabilise; when networks of women connect across borders, a continent begins to heal itself. Your local faithfulness is therefore continental work: the chapter you strengthen in your state is one cell in a body stretching across many nations. Honour the diversity of that body — languages, cultures, churches and customs differ, but the mission is one. Pray for, learn from, and celebrate sister chapters in other countries. You are not just serving a community; you are building Africa.' from public.courses where code = 'WGMN-VP'
on conflict (course_id, seq) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 1, 'WODDI is pan-African because Africa''s renewal runs through…', '["A. Governments", "B. Her women", "C. Cities only", "D. Companies"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 7
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'B' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 7 and cq.seq = 1
on conflict (question_id) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 2, 'Your local chapter work is described as…', '["A. Small and separate", "B. One cell in a continental body", "C. Optional", "D. Purely social"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 7
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'B' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 7 and cq.seq = 2
on conflict (question_id) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 3, 'Diversity across countries should be…', '["A. Eliminated", "B. Honoured while keeping one mission", "C. Ignored", "D. Debated"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 7
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'B' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 7 and cq.seq = 3
on conflict (question_id) do nothing;
insert into public.course_modules (course_id, seq, title, lesson)
select id, 8, 'The Power of One Committed Woman', 'Movements are arithmetic to observers and multiplication to participants. One committed woman welcomes ten, mentors three, and models faithfulness for a whole community — and each of those women can do the same. History''s greatest changes began with individuals who refused to wait for perfect conditions. Commitment is not intensity; it is consistency: the volunteer who shows up every week moves more than the one who blazes for a month and vanishes. Guard your commitment like the treasure it is — feed it with vision, protect it with rest, and renew it in community. You are the one woman this module is about.' from public.courses where code = 'WGMN-VP'
on conflict (course_id, seq) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 1, 'Commitment is best defined as…', '["A. Intensity", "B. Consistency", "C. Popularity", "D. Speed"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 8
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'B' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 8 and cq.seq = 1
on conflict (question_id) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 2, 'One committed woman multiplies by…', '["A. Doing everything herself", "B. Welcoming, mentoring and modelling", "C. Posting daily", "D. Holding titles"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 8
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'B' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 8 and cq.seq = 2
on conflict (question_id) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 3, 'Great changes usually begin with…', '["A. Perfect conditions", "B. Individuals who refused to wait", "C. Large budgets", "D. Committees"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 8
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'B' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 8 and cq.seq = 3
on conflict (question_id) do nothing;
insert into public.course_modules (course_id, seq, title, lesson)
select id, 9, 'Staying Connected to the Vision', 'Disconnection rarely announces itself; it drifts in quietly — meetings missed, messages unread, joy thinning. Guard against drift with rhythms of reconnection: attend your monthly briefing, read the weekly inspiration, and keep one honest relationship in the network where you can say ''I''m struggling''. If you feel distant, act early: tell your coordinator, take a lighter role for a season, but do not disappear — the network would rather adjust with you than lose you. And watch for drift in others: a warm ''we miss you'' message has recovered more volunteers than any policy ever written.' from public.courses where code = 'WGMN-VP'
on conflict (course_id, seq) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 1, 'Disconnection usually arrives…', '["A. Loudly and suddenly", "B. Quietly, as drift", "C. Only after conflict", "D. Never"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 9
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'B' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 9 and cq.seq = 1
on conflict (question_id) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 2, 'If you feel distant from the network you should…', '["A. Disappear quietly", "B. Tell your coordinator early and adjust", "C. Wait a year", "D. Criticise publicly"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 9
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'B' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 9 and cq.seq = 2
on conflict (question_id) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 3, 'A powerful tool for recovering drifting volunteers is…', '["A. A warm ''we miss you'' message", "B. A formal warning", "C. Removal from groups", "D. Silence"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 9
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'A' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 9 and cq.seq = 3
on conflict (question_id) do nothing;
insert into public.course_modules (course_id, seq, title, lesson)
select id, 10, 'Strength for the Woman Who Serves', 'Serving others while carrying your own life takes real strength — and strength has sources. Spiritual roots: prayer, scripture and worship steady the soul that service spends. Physical basics: sleep, food and movement are leadership disciplines, not luxuries. Emotional honesty: strong women cry, ask for help, and see counsellors when needed; pretending is the fastest road to breaking. Community: the network exists for you too — receive encouragement as readily as you give it. Consistency is strength made visible over time; protect its sources and your service will have deep roots and long seasons.' from public.courses where code = 'WGMN-VP'
on conflict (course_id, seq) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 1, 'Sleep, food and movement are described as…', '["A. Luxuries", "B. Leadership disciplines", "C. Distractions", "D. Rewards"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 10
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'B' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 10 and cq.seq = 1
on conflict (question_id) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 2, 'Emotional honesty for strong women includes…', '["A. Pretending to be fine", "B. Asking for help when needed", "C. Hiding struggles", "D. Serving harder"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 10
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'B' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 10 and cq.seq = 2
on conflict (question_id) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 3, 'Consistency is…', '["A. Strength made visible over time", "B. A personality type", "C. Luck", "D. Optional"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 10
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'A' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 10 and cq.seq = 3
on conflict (question_id) do nothing;
insert into public.course_modules (course_id, seq, title, lesson)
select id, 11, 'The Beauty of Appreciation and Service', 'Appreciation keeps the heart of service alive. Volunteers are paid in meaning, and gratitude is its currency: a named thank-you in a meeting, a birthday remembered, a small note after a hard event — these cost minutes and buy years of loyalty. Practise upward and sideways gratitude too: thank your coordinator, celebrate a sister chapter''s win. And learn to receive appreciation gracefully; deflecting every compliment quietly teaches your team that recognition is unwelcome. A culture of honour is built one specific, sincere thank-you at a time — start today with one person who never gets noticed.' from public.courses where code = 'WGMN-VP'
on conflict (course_id, seq) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 1, 'Volunteers are ''paid'' primarily in…', '["A. Money", "B. Meaning, carried by gratitude", "C. Titles", "D. Data"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 11
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'B' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 11 and cq.seq = 1
on conflict (question_id) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 2, 'Effective appreciation is…', '["A. Rare and general", "B. Specific, sincere and timely", "C. Only for leaders", "D. Annual"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 11
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'B' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 11 and cq.seq = 2
on conflict (question_id) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 3, 'Deflecting every compliment teaches the team that…', '["A. You are humble", "B. Recognition is unwelcome", "C. Standards are high", "D. Nothing"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 11
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'B' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 11 and cq.seq = 3
on conflict (question_id) do nothing;
insert into public.course_modules (course_id, seq, title, lesson)
select id, 12, 'Renewing the Vision for the Year Ahead', 'Seasons end so vision can be renewed. Close each year the WODDI way: reflect (what did we learn? whom did we reach?), give thanks (name people and mercies specifically), and recommit (one clear intention for the year ahead — written, shared, and revisited). Do this personally and with your team; a chapter that reviews together renews together. Release what the old year could not finish without shame, and carry forward only what still serves the mission. Then begin again with joy. The Nurturer''s work is never finished — but every year, it can be refreshed.' from public.courses where code = 'WGMN-VP'
on conflict (course_id, seq) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 1, 'The WODDI year-end rhythm is…', '["A. Reflect, give thanks, recommit", "B. Report, resign, restart", "C. Rest only", "D. Celebrate only"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 12
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'A' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 12 and cq.seq = 1
on conflict (question_id) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 2, 'Unfinished goals from the old year should be…', '["A. Carried with shame", "B. Released or carried forward without shame, as the mission needs", "C. Hidden", "D. Blamed on others"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 12
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'B' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 12 and cq.seq = 2
on conflict (question_id) do nothing;
insert into public.course_questions (module_id, seq, prompt, options)
select m.id, 3, 'Renewal works best when done…', '["A. Alone in secret", "B. Personally and together with your team", "C. Only at HQ", "D. Every five years"]'::jsonb
  from public.course_modules m join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 12
on conflict (module_id, seq) do nothing;
insert into public.course_keys (question_id, correct)
select cq.id, 'B' from public.course_questions cq
  join public.course_modules m on m.id = cq.module_id
  join public.courses c on c.id = m.course_id
 where c.code = 'WGMN-VP' and m.seq = 12 and cq.seq = 3
on conflict (question_id) do nothing;

insert into public.schema_migrations (version, name)
values (33, 'courses_certification') on conflict (version) do nothing;
