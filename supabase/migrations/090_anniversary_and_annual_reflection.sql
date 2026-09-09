-- ============================================================================
-- WDOS Migration 090 — Items 6 & 9: Service Anniversary and Annual
-- Reflection (Phase 102)
--
-- PART A: Service Anniversary & Milestone Recognition (Item 6). All 17
-- messages below are reproduced verbatim from the founder's approved pack
-- (11 August 2026) — 9 non-milestone annual variants across her 3-year
-- cycle (3 per year) and 8 milestone messages (1/3/5/10 years, each with
-- a Primary and Alternate). Her own document flagged a real inconsistency
-- between "three controlled cycle years" (this pack) and a "five-year
-- non-repetition variant bank" (her status summary) — NOT silently
-- resolved here; built to her 3-year pack as written, flagged for her
-- ruling in the reply. The two supporting ad-hoc templates (verified
-- specific-contribution / team-achievement) are intentionally NOT ported
-- here — they overlap with the Spotlight engine already built in
-- migration 087 and are better triggered from there than duplicated.
--
-- Trigger date = role_assignments.starts_at (the "verified appointment
-- date" her document calls for) for the leader's current, active seat.
-- Eligibility, exactly as her document scopes it: established WGMN
-- leaders only (WNNN excluded — her own document says it "requires a
-- separate age- and network-appropriate adaptation").
--
-- PART B: Annual Reflection, Gratitude & Recommitment (Item 9). Her three
-- complete Founder year-end letters, seeded verbatim with her own
-- placeholders ({Verified_Impact_1}, {Verified_Impact_2},
-- {Representative_Story_1}) preserved exactly as written — HQ supplies
-- the real evidence at dispatch time, same discipline as Quarterly. Her
-- six-stage cycle (Prepare / Reflect / Validate / Appreciate / Recommit /
-- Close and learn) is represented by the dispatch + submission functions
-- below; the volunteer-facing reflection form matches her Appendix A
-- exactly (5 next-cycle choices, private by default, no reminder spam,
-- no auto-conversion of silence into any status — her own explicit rule).
-- ============================================================================

-- 1 ▸ anniversary/milestone templates ----------------------------------------
create table public.anniversary_templates (
  id            uuid primary key default gen_random_uuid(),
  kind          text not null check (kind in ('annual','milestone')),
  cycle_year    int check (cycle_year between 1 and 3),
  milestone_years int check (milestone_years in (1,3,5,10)),
  variant       text not null,
  name          text not null,
  subject       text not null,
  email_body    text not null
);
alter table public.anniversary_templates enable row level security;
create policy anniv_tpl_read on public.anniversary_templates
  for select to authenticated using (true);

insert into public.anniversary_templates
  (kind, cycle_year, milestone_years, variant, name, subject, email_body)
values
  ('annual', 1, null, 'A', 'A Place in the Circle', 'Honouring Your WODDI Service Anniversary', 'Dear {Preferred_Name}, today we honour another verified year of your service within the WODDI Good Mother Network. Your presence strengthens a circle of women who lead with compassion, learn with humility and serve so that no woman is left out. Through your steady commitment, families and communities encounter leadership that listens, protects dignity and creates room for others to grow. This anniversary celebrates you as a valued member of our volunteer family, not only the tasks you have completed. Thank you for giving your time, judgment and care to a shared mission larger than any one role. As you begin another year of service, may you continue to lead responsibly, seek learning, uphold safeguarding standards and encourage the women beside you. We are grateful that your story is part of WODDI''s story. Congratulations on your service anniversary.

With appreciation,
The WODDI Family.'),
  ('annual', 1, null, 'B', 'The Bridge You Help Build', 'Thank You for Another Year', 'Dear {Preferred_Name}, your service anniversary marks another year in which you have helped build bridges between women, opportunity and community. WODDI''s mission advances when volunteer leaders choose to listen carefully, act responsibly and make space for women who might otherwise be overlooked. We recognise the generosity behind that choice. Today is not an assessment of numbers or activity alone; it is a sincere celebration of you, your belonging and your continuing journey as a leader. Thank you for contributing your time and experience while remaining open to learning, collaboration and accountable service. As a new service year begins, may you keep building trust, supporting fellow leaders and serving with wisdom. We are proud to walk this path with you. Happy service anniversary.

With appreciation,
The WODDI Family.'),
  ('annual', 1, null, 'C', 'A Shared Promise', 'Celebrating Your Shared Promise', 'Dear {Preferred_Name}, an anniversary gives us a meaningful moment to recognise the promise you renew through volunteer leadership. For another verified year, you have stood within a network committed to empowering women, strengthening families and nurturing communities where dignity is protected. Your contribution matters because lasting change depends on people who remain willing to learn, cooperate and serve with care. We celebrate the whole person behind the role: your experience, your growth and the values you bring to the WODDI Good Mother Network. As you enter the next year, we encourage you to keep listening, mentoring, safeguarding and opening pathways for other women to participate. May this anniversary remind you that your presence is seen and valued. Congratulations, and thank you for continuing the journey with us.

With appreciation,
The WODDI Family.'),
  ('annual', 2, null, 'A', 'Stewarding Trust', 'Your Service Has Carried Trust', 'Dear {Preferred_Name}, today WODDI recognises another verified year in which you have carried the trust of volunteer leadership. Trust grows through thoughtful decisions, respectful relationships, reliable service and the courage to keep learning. By continuing in WGMN, you help create an environment where women can participate with dignity, families can be strengthened and communities can benefit from responsible leadership. As this new year of service opens, may you steward your influence carefully, protect those who engage with our programmes and encourage emerging leaders to find their place. Your anniversary is a reminder that the network is built through people who choose commitment again and again. Congratulations on your service anniversary.

With appreciation,
The WODDI Family.'),
  ('annual', 2, null, 'B', 'Light for the Next Step', 'Celebrating the Light You Share', 'Dear {Preferred_Name}, every service anniversary offers a light by which we can see both the distance travelled and the next step ahead. We are grateful for another verified year of your participation in the WODDI Good Mother Network. Your willingness to serve, learn and collaborate helps women recognise their strength, supports healthier families and contributes to more inclusive communities. As you move into another year, may you continue to illuminate possibilities for women who need encouragement, share knowledge with fellow leaders and seek support whenever a responsibility requires it. ''No Woman Left Out'' becomes visible through countless decisions to notice, include and uplift. Happy service anniversary.

With appreciation,
The WODDI Family.'),
  ('annual', 2, null, 'C', 'Woven into the Network', 'You Strengthen Our Shared Fabric', 'Dear {Preferred_Name}, your verified service is one of the threads that gives WGMN its strength, reach and character. On this anniversary, we pause to thank you for another year of standing with women and contributing to a network that values families, communities, learning and dignified leadership. Thank you for collaborating across differences, remaining teachable and helping maintain safe, respectful spaces for participation. In the year ahead, may your leadership continue to connect people, repair gaps and make room for women whose voices need to be heard. Congratulations on another year of service.

With appreciation,
The WODDI Family.'),
  ('annual', 3, null, 'A', 'Seeds of Continuing Impact', 'Honouring Seeds of Continuing Impact', 'Dear {Preferred_Name}, today we celebrate the seeds of care, knowledge and possibility planted through another verified year of your WODDI service. Some results are immediately visible; others grow quietly through a woman who feels included, a family that finds support or a new leader who gains confidence. Thank you for serving within WGMN with openness to learning, collaboration and safeguarding. As another year begins, may you continue to nurture leadership in others, document your work honestly and care for your own wellbeing while serving. Congratulations on your service anniversary.

With appreciation,
The WODDI Family.'),
  ('annual', 3, null, 'B', 'A Compass of Values', 'Your Values Guide Meaningful Service', 'Dear {Preferred_Name}, a volunteer leader''s deepest direction comes from values, and your anniversary invites us to honour another verified year of values-led service. Within the WODDI Good Mother Network, leadership means more than activity: it means respecting dignity, protecting trust, learning continuously and creating pathways for women to participate. As you enter the coming year, let compassion, accountability and inclusion remain your compass. Continue to collaborate with fellow leaders, follow safeguarding standards and seek guidance when the way forward is unclear. Happy service anniversary, and congratulations.

With appreciation,
The WODDI Family.'),
  ('annual', 3, null, 'C', 'A Living Legacy', 'Celebrating Your Living Legacy', 'Dear {Preferred_Name}, service becomes a living legacy when it shapes how people are welcomed, supported and prepared to lead. On your anniversary, WODDI gratefully recognises another verified year of your journey within WGMN. In the service year ahead, may you help preserve what is valuable, improve what needs attention and create space for the next generation of responsible women leaders. Each inclusive action carries forward the conviction ''No Woman Left Out''. Congratulations on another year of service.

With appreciation,
The WODDI Family.'),
  ('milestone', null, 1, 'primary', '1-Year Milestone (Primary)', 'Your First WODDI Service Anniversary', 'Dear {Preferred_Name}, one year ago you formally began this chapter of volunteer leadership with WODDI. Today, after verification of your service record, we celebrate your First Anniversary within the Good Mother Network. Thank you for showing up with a willingness to grow, serve responsibly and stand with women, families and communities. As your second year begins, continue to ask questions, use the support available to you, uphold safeguarding standards and make room for other women to participate. Congratulations on completing your first verified year of service.

With appreciation,
The WODDI Family.'),
  ('milestone', null, 1, 'alternate', '1-Year Milestone (Alternate)', 'One Year of Belonging and Service', 'Dear {Preferred_Name}, your first verified year of WODDI service is a foundation worthy of recognition. Across these twelve months, you have belonged to a network that calls women to lead with compassion, responsibility and a commitment to inclusion. As you enter the next year, strengthen the relationships around you, document your work honestly, protect the dignity of everyone you encounter and seek guidance whenever you need it. Congratulations on reaching your first service anniversary. We are glad you are part of the WODDI family.

With appreciation,
The WODDI Family.'),
  ('milestone', null, 3, 'primary', '3-Year Milestone (Primary)', 'Honouring Three Years of Service', 'Dear {Preferred_Name}, three verified years of volunteer leadership mark an established commitment to WODDI''s shared mission. Today we recognise the roots you have formed through continued belonging, learning and service within the Good Mother Network. As you begin the next stage of your journey, continue to protect trust, follow safeguarding standards, collaborate across roles and make space for voices that may be overlooked. Congratulations on reaching three verified years of service.

With appreciation,
The WODDI Family.'),
  ('milestone', null, 3, 'alternate', '3-Year Milestone (Alternate)', 'Three Years of Steady Leadership', 'Dear {Preferred_Name}, your third service anniversary reflects a steady rhythm of commitment: participating, learning, supporting others and returning to the mission with renewed purpose. In the year ahead, continue to share knowledge without closing the door to new ideas, encourage women to find their place and use WODDI''s support channels when concerns arise. Thank you for three verified years of belonging and contribution. Congratulations on this meaningful milestone.

With appreciation,
The WODDI Family.'),
  ('milestone', null, 5, 'primary', '5-Year Milestone (Primary)', 'Celebrating Five Distinguished Years', 'Dear {Preferred_Name}, five verified years of WODDI service represent a substantial path of commitment, learning and leadership. On this Distinguished Service milestone, we pause to honour your continued place within the Good Mother Network. As you enter the next chapter, continue to mentor responsibly, welcome fresh perspectives and document contributions truthfully so that learning can be shared. Congratulations on five verified years and on reaching this important milestone with us.

With appreciation,
The WODDI Family.'),
  ('milestone', null, 5, 'alternate', '5-Year Milestone (Alternate)', 'Five Years of Enduring Service', 'Dear {Preferred_Name}, today we recognise an enduring light within our volunteer community: your completion of five verified years of service. As the next service year begins, may your experience help other leaders grow while your own learning remains active. Continue to safeguard dignity, use evidence responsibly and seek support when challenges arise. Congratulations, and thank you for continuing this journey with the WODDI family.

With appreciation,
The WODDI Family.'),
  ('milestone', null, 10, 'primary', '10-Year Milestone (Primary)', 'Honouring a Decade of Devotion', 'Dear {Preferred_Name}, ten verified years of volunteer service form an extraordinary chapter in WODDI''s living history. On this Decade of Devotion milestone, we honour your sustained belonging, learning and leadership. As you move forward, we invite you to preserve institutional learning, mentor with humility and create opportunities for emerging women leaders to contribute meaningfully. Congratulations on ten verified years of devotion and service.

With profound appreciation,
The WODDI Family.'),
  ('milestone', null, 10, 'alternate', '10-Year Milestone (Alternate)', 'Ten Years Woven into WODDI', 'Dear {Preferred_Name}, across ten verified years, your service has become woven into the wider story of the WODDI Good Mother Network. In the years ahead, help newer leaders understand the mission, uphold safeguarding standards and learn from both progress and difficulty. Thank you for ten verified years of belonging and service. WODDI celebrates this exceptional milestone with deep respect and gratitude.

With profound appreciation,
The WODDI Family.');

-- 2 ▸ dispatch tracking — enforces "not the same wording two years running"
create table public.anniversary_dispatch_log (
  id            uuid primary key default gen_random_uuid(),
  profile_id    uuid not null references profiles(id) on delete cascade,
  template_id   uuid not null references anniversary_templates(id),
  service_year  int not null,
  sent_at       timestamptz not null default now(),
  unique (profile_id, service_year)
);
alter table public.anniversary_dispatch_log enable row level security;
create policy anniv_log_hq on public.anniversary_dispatch_log
  for select to authenticated using (public.is_case_hq());

-- 3 ▸ the daily sweep ---------------------------------------------------------
create or replace function public.anniversary_daily_sweep()
returns jsonb language plpgsql
security definer set search_path = public as $$
declare
  r record; start_date date; svc_years int; cyc_year int;
  tpl anniversary_templates; already boolean;
  seed bigint; n int := 0;
begin
  for r in
    select p.id as pid, p.first_name, p.email,
           ra.starts_at
      from profiles p
      join role_assignments ra on ra.profile_id = p.id and ra.ends_at is null
     where p.is_leader and coalesce(p.network::text, 'WGMN') = 'WGMN'
       and p.merged_into is null
     order by p.id, ra.starts_at asc
  loop
    start_date := r.starts_at::date;
    if start_date is null then continue; end if;
    if extract(month from start_date) <> extract(month from now())
       or extract(day from start_date) <> extract(day from now()) then
      continue;
    end if;

    svc_years := extract(year from now())::int - extract(year from start_date)::int;
    if svc_years < 1 then continue; end if;

    select exists (select 1 from anniversary_dispatch_log
                    where profile_id = r.pid and service_year = svc_years)
      into already;
    if already then continue; end if;

    seed := abs(hashtext(r.pid::text || ':' || svc_years::text)::bigint);

    if svc_years in (1,3,5,10) then
      select * into tpl from anniversary_templates
       where kind = 'milestone' and milestone_years = svc_years
         and variant = case when seed % 2 = 0 then 'primary' else 'alternate' end
       limit 1;
    else
      cyc_year := ((svc_years - 1) % 3) + 1;
      select * into tpl from anniversary_templates
       where kind = 'annual' and cycle_year = cyc_year
         and variant = (array['A','B','C'])[(seed % 3) + 1]
       limit 1;
    end if;

    if tpl.id is null then continue; end if;

    insert into member_notices (profile_id, kind, title, body)
    values (r.pid, 'nudge', tpl.subject,
      replace(tpl.email_body, '{Preferred_Name}', r.first_name));

    insert into anniversary_dispatch_log (profile_id, template_id, service_year)
    values (r.pid, tpl.id, svc_years);
    n := n + 1;
  end loop;
  return jsonb_build_object('sent', n);
end;
$$;
revoke execute on function public.anniversary_daily_sweep() from anon;

do $$
begin
  begin
    if exists (select 1 from pg_extension where extname = 'pg_cron') then
      begin
        perform cron.unschedule('wdos-anniversary-sweep');
      exception when others then null;
      end;
      perform cron.schedule('wdos-anniversary-sweep', '30 6 * * *',
        $cron$select public.anniversary_daily_sweep()$cron$);
    end if;
  exception when others then
    raise notice 'pg_cron unavailable — run anniversary_daily_sweep() manually';
  end;
end $$;

-- ============================================================================
-- PART B — Annual Reflection, Gratitude & Recommitment (Item 9)
-- ============================================================================

create table public.annual_founder_letters (
  cycle_year int primary key check (cycle_year between 1 and 3),
  theme      text not null,
  body       text not null
);
alter table public.annual_founder_letters enable row level security;
create policy annual_letter_hq on public.annual_founder_letters
  for select to authenticated using (public.is_case_hq());

insert into public.annual_founder_letters (cycle_year, theme, body) values
  (1, 'Rooted in Purpose', 'Dear WODDI Volunteer Leader, as this service year closes, I pause with deep gratitude for the time, wisdom and care you have offered through the WODDI Good Mother Network. Across countries, communities and different levels of responsibility, you have helped keep our shared purpose alive: empowering women, strengthening families and ensuring that no woman is left out. This year, {Verified_Impact_1}. We also saw {Verified_Impact_2}. Behind every verified result are women who listened, organised, encouraged, reported, mentored, solved problems and continued serving even when their work was not publicly visible. {Representative_Story_1}. This is one example of a much wider circle of service, and we honour every contribution without ranking one role above another. We have made progress, and we have also learned where we must communicate more clearly, support leaders more consistently and strengthen accountable, safe service. I invite you to reflect honestly on what rooted your service, what you learned and what support you may need. When the recommitment window opens, please choose the next step that truthfully reflects your capacity. Your response will be received with dignity. Thank you for being part of WODDI''s story and for helping purpose take root in the lives of women, families and communities.

With gratitude and confidence in our shared purpose,
The Founder
On behalf of WODDI Headquarters'),
  (2, 'Growing Through Service', 'Dear WODDI Volunteer Leader, at the close of this service year, I thank you for the growth you have made possible through the WODDI Good Mother Network. Growth is not only measured by expansion or activity. It is also seen when a leader listens more carefully, collaborates more openly, applies learning, protects dignity and helps another woman find confidence and opportunity. This year, {Verified_Impact_1}. Together, we also achieved {Verified_Impact_2}. {Representative_Story_1}. That story represents one part of a larger collective effort shaped by leaders in every approved role, including those whose contribution happens quietly, remotely or behind the scenes. We celebrate verified progress without overlooking the lessons still before us. As you consider the next cycle, I invite you to recognise how service has changed you, whose growth you have encouraged and what conditions will help you contribute sustainably. Choose your next step honestly when the recommitment window opens. Whether you are ready to continue, need support, require a pause or wish to discuss transition, your response deserves respect. Thank you for growing with us and for helping the promise ''No Woman Left Out'' reach wider circles.

With gratitude and confidence in our shared purpose,
The Founder
On behalf of WODDI Headquarters'),
  (3, 'Legacy in Motion', 'Dear WODDI Volunteer Leader, as we complete the third year of this engagement cycle, I honour the living legacy created through your service. Legacy is not a title, a single event or a story about one person. It is the value that continues because women chose to act with purpose, pass on learning, protect dignity and prepare others to lead. Across this cycle, {Verified_Impact_1}. In this service year, {Verified_Impact_2}. {Representative_Story_1}. We share that example with consent and humility, knowing that many equally meaningful contributions remain private or unseen. Thank you to every leader who organised, encouraged, mentored, documented, solved problems, upheld standards or made space for another woman. We also acknowledge the lessons and unfinished work that call us to improve. This annual reflection asks what we must preserve, what we must change and what we should hand forward with care. As Headquarters prepares the renewed engagement cycle, please record the next step that truthfully reflects your capacity. Continuing, continuing with support, pausing or transitioning responsibly can each be an act of stewardship. Whatever your role or visibility, your contribution to this shared mission matters. Thank you for carrying WODDI''s purpose forward and for helping build a legacy in which no woman is left out.

With gratitude and confidence in our shared purpose,
The Founder
On behalf of WODDI Headquarters');

create type public.reflection_choice as enum (
  'continue','continue_with_support','pause','transition','not_ready');

create table public.annual_reflection_responses (
  id              uuid primary key default gen_random_uuid(),
  profile_id      uuid not null references profiles(id) on delete cascade,
  cycle_year      int not null check (cycle_year between 1 and 3),
  next_choice     reflection_choice not null,
  support_note    text not null default '',
  privacy_ack     boolean not null default false,
  submitted_at    timestamptz not null default now(),
  unique (profile_id, cycle_year)
);
alter table public.annual_reflection_responses enable row level security;
create policy annual_resp_own on public.annual_reflection_responses
  for select to authenticated
  using (profile_id = auth.uid() or public.is_case_hq());
create policy annual_resp_hq_all on public.annual_reflection_responses
  for all to authenticated using (public.is_case_hq())
  with check (public.is_case_hq());

-- HQ dispatch: substitutes real evidence into the correct year's letter,
-- sends privately (her rule 10.1/9.1), never auto-repeats within a year
create or replace function public.dispatch_annual_reflection(
  p_cycle_year int, p_impact_1 text, p_impact_2 text, p_story_1 text)
returns jsonb language plpgsql
security definer set search_path = public as $$
declare
  letter annual_founder_letters; r record; final_body text;
  title_line text; n int := 0; skipped int := 0;
begin
  if auth.uid() is not null and not is_case_hq() then
    raise exception 'HQ only';
  end if;
  if p_impact_1 is null or char_length(btrim(p_impact_1)) < 5
     or p_impact_2 is null or char_length(btrim(p_impact_2)) < 5
     or p_story_1 is null or char_length(btrim(p_story_1)) < 5 then
    raise exception 'Please supply verified impact and story text before dispatching';
  end if;

  select * into letter from annual_founder_letters where cycle_year = p_cycle_year;
  if letter.cycle_year is null then
    raise exception 'No founder letter staged for cycle year %', p_cycle_year;
  end if;
  title_line := 'Year-End Reflection & Gratitude — ' || letter.theme;

  for r in select p.id, p.first_name from profiles p
            where p.is_leader and coalesce(p.network::text, 'WGMN') = 'WGMN'
              and p.merged_into is null
  loop
    if exists (select 1 from member_notices
                where profile_id = r.id and title = title_line) then
      skipped := skipped + 1; continue;
    end if;

    final_body := replace(letter.body, '{Verified_Impact_1}', btrim(p_impact_1));
    final_body := replace(final_body, '{Verified_Impact_2}', btrim(p_impact_2));
    final_body := replace(final_body, '{Representative_Story_1}', btrim(p_story_1));

    insert into member_notices (profile_id, kind, title, body)
    values (r.id, 'nudge', title_line, final_body);
    n := n + 1;
  end loop;
  return jsonb_build_object('sent', n, 'already_sent', skipped,
                            'cycle_year', p_cycle_year, 'theme', letter.theme);
end;
$$;
revoke execute on function public.dispatch_annual_reflection(int, text, text, text)
  from anon;

-- volunteer-facing submission — private, one per cycle year, never implies
-- a status change on its own (her explicit rule 9.2)
create or replace function public.submit_annual_reflection(
  p_cycle_year int, p_choice reflection_choice, p_support_note text default '',
  p_privacy_ack boolean default false)
returns void language plpgsql
security definer set search_path = public as $$
begin
  if auth.uid() is null then
    raise exception 'Sign in required to record a reflection';
  end if;
  if not p_privacy_ack then
    raise exception 'Please confirm the privacy acknowledgement before submitting';
  end if;
  insert into annual_reflection_responses
    (profile_id, cycle_year, next_choice, support_note, privacy_ack)
  values (auth.uid(), p_cycle_year, p_choice, btrim(coalesce(p_support_note, '')),
          p_privacy_ack)
  on conflict (profile_id, cycle_year) do update
    set next_choice = excluded.next_choice,
        support_note = excluded.support_note,
        submitted_at = now();
end;
$$;
revoke execute on function public.submit_annual_reflection(
  int, reflection_choice, text, boolean) from anon;

-- HQ-only aggregate report — counts only, matching her "aggregate next-cycle
-- intentions" requirement without exposing individual choices in the summary
create or replace function public.annual_reflection_summary(p_cycle_year int)
returns jsonb language sql stable
security definer set search_path = public as $$
  select case when public.is_case_hq() then
    coalesce(jsonb_object_agg(next_choice, n), '{}'::jsonb)
  else '{}'::jsonb end
  from (
    select next_choice, count(*) as n from annual_reflection_responses
     where cycle_year = p_cycle_year group by next_choice
  ) t;
$$;
revoke execute on function public.annual_reflection_summary(int) from anon;

insert into public.schema_migrations (version, name)
values (90, 'anniversary_and_annual_reflection') on conflict (version) do nothing;
