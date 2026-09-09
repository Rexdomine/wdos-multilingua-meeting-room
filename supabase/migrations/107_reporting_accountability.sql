-- ============================================================================
-- WDOS Migration 107 — REPORTING & ACCOUNTABILITY MODULE (Phase 134)
-- Built to the "WGMN WDOS Reporting & Accountability Module, Final Functional
-- Specification v1.0, 6 Sep 2026". This file is the spec's Phase 1
-- (foundation) plus the core of Phase 2 and the reminder engine of Phase 5:
--
--   §6   auto-filled identity block, record-once rule       → report_snapshot()
--   §7   Workflow 1 operational activity record             → activity_records
--   §8   Workflow 2 weekly pulse (HQ-configurable cadence)  → template weekly_pulse
--   §9   Workflow 3 monthly report, sections A–P            → template monthly_leadership
--   §10/11 activity + meeting reports                       → templates
--   §17  Workflow 11 risk / issue / escalation              → issues
--   §20  Workflow 14 exit & handover (auto-pulled)          → template exit_handover
--   §22  aggregation: one record, hierarchy-aware, vacancy-aware
--   §23  statuses, review rules, approval lock, versions    → report_instances,
--                                                              report_reviews
--   §24  reminders 7/3/0 before, 1/3/7 overdue, configurable → reporting_config,
--                                                              reporting_reminders_run()
--   §25  personal / supervisor / country dashboards          → reporting_dashboard(),
--                                                              reporting_compliance()
--   §26  submission validation                               → report_submit()
--   §27  audit (append-only reviews + audit_log trigger), evidence bucket
--   §3.2/21.1 one unit report, deputy contributes, acting submits
--
-- Not in this file (spec Phases 3–4, listed in docs/PHASE134): partnership,
-- digital-inclusion and finance as their own tables (they are structured
-- rows inside the monthly report for now), Institute learning pull
-- (separate project), annual/quarterly consolidation pages, bulk export.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 0 ▸ enums
-- ---------------------------------------------------------------------------
do $$ begin
  if not exists (select 1 from pg_type where typname = 'report_status') then
    create type public.report_status as enum
      ('draft', 'submitted', 'under_review', 'returned', 'approved',
       'escalated', 'closed', 'superseded');
  end if;
  if not exists (select 1 from pg_type where typname = 'issue_severity') then
    create type public.issue_severity as enum ('green', 'amber', 'red', 'critical');
  end if;
  if not exists (select 1 from pg_type where typname = 'issue_status') then
    create type public.issue_status as enum
      ('open', 'in_progress', 'awaiting_decision', 'resolved', 'closed');
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 1 ▸ CONFIGURATION (§24: intervals and deadlines are configuration)
-- ---------------------------------------------------------------------------
create table if not exists public.reporting_config (
  key        text primary key,
  value      jsonb not null,
  updated_at timestamptz not null default now()
);
alter table public.reporting_config enable row level security;
drop policy if exists reporting_config_read on public.reporting_config;
create policy reporting_config_read on public.reporting_config for select to authenticated using (true);
drop policy if exists reporting_config_write on public.reporting_config;
create policy reporting_config_write on public.reporting_config for all to authenticated
  using (public.is_case_hq()) with check (public.is_case_hq());
insert into public.reporting_config (key, value) values
  ('monthly_due_day', '7'),                       -- day of the following month
  ('reminder_days_before', '[7, 3, 0]'),
  ('overdue_days', '[1, 3, 7]'),
  ('supervisor_alert_overdue_day', '3'),
  ('escalate_overdue_day', '7'),
  ('weekly_pulse_levels', '["country"]'),         -- mandatory levels
  ('weekly_pulse_countries', '[]'),               -- ISO codes forced on
  ('weekly_pulse_until', 'null'),                 -- campaign period end (date) or null
  ('event_report_days', '5'),
  ('meeting_report_days', '2')
on conflict (key) do nothing;

create or replace function public.rcfg(k text) returns jsonb
language sql stable security definer set search_path = public as $$
  select value from reporting_config where key = k;
$$;

-- ---------------------------------------------------------------------------
-- 2 ▸ TEMPLATES (§30 Report Template: sections, fields, cadence, validations)
--     Sections are data: the app renders any template from this JSON.
--     field types: text | textarea | number | date | select | check | rows
--     "auto" lists snapshot metric keys the section displays read-only.
-- ---------------------------------------------------------------------------
create table if not exists public.report_templates (
  code        text primary key,
  title       text not null,
  cadence     text not null check (cadence in ('monthly', 'weekly', 'event', 'transition')),
  levels      public.org_level[] not null default array['country','state_region','district_lga','chapter']::public.org_level[],
  sections    jsonb not null,
  evidence_required boolean not null default false,
  active      boolean not null default true,
  version     int not null default 1,
  updated_at  timestamptz not null default now()
);
alter table public.report_templates enable row level security;
drop policy if exists report_templates_read on public.report_templates;
create policy report_templates_read on public.report_templates for select to authenticated using (true);
drop policy if exists report_templates_write on public.report_templates;
create policy report_templates_write on public.report_templates for all to authenticated
  using (public.is_case_hq()) with check (public.is_case_hq());

insert into public.report_templates (code, title, cadence, sections, evidence_required) values
('monthly_leadership', 'Monthly Leadership & Performance Report', 'monthly', $J$[
 {"key":"A","title":"Identity & reporting period","auto":["identity"],"fields":[]},
 {"key":"B","title":"Executive leadership commentary","fields":[
   {"key":"improved","label":"What materially improved this month?","type":"textarea","required":true},
   {"key":"declined","label":"What materially declined or remains unresolved?","type":"textarea","required":true},
   {"key":"decision","label":"What decision or support is required from the next reporting level?","type":"textarea","required":true}]},
 {"key":"C","title":"Leadership structure & coverage","auto":["leadership","pipeline"],"fields":[
   {"key":"leadership_issues","label":"Leadership issues requiring intervention","type":"textarea"},
   {"key":"recruitment_priorities","label":"Areas requiring recruitment or strengthening","type":"textarea"}]},
 {"key":"D","title":"Reporting compliance under my leadership","auto":["compliance"],"fields":[
   {"key":"noncompliance","label":"Explain significant non-compliance","type":"textarea","requiredWhen":"compliance.overdue>0"}]},
 {"key":"E","title":"Membership, mobilisation & retention","auto":["membership","activities"],"fields":[
   {"key":"women_reached","label":"Women newly reached (not already recorded)","type":"number"},
   {"key":"new_areas","label":"New geographical areas reached","type":"textarea"},
   {"key":"retention","label":"Retention concerns and underserved areas","type":"textarea"}]},
 {"key":"F","title":"Learning & WODDI Institute","auto":["learning"],"fields":[
   {"key":"learning_barriers","label":"Learning barriers identified and action taken","type":"textarea"}]},
 {"key":"G","title":"Programmes & activities","auto":["programmes"],"fields":[
   {"key":"outcomes","label":"Major outcomes and lessons (only what the activity records do not say)","type":"textarea"}]},
 {"key":"H","title":"Meetings, decisions & actions","auto":["meetings"],"fields":[
   {"key":"decisions","label":"Major decisions and outstanding actions requiring escalation","type":"textarea"}]},
 {"key":"I","title":"Tasks & deliverables","auto":["tasks"],"fields":[
   {"key":"overdue_note","label":"Explanation for overdue, blocked or decision-dependent items","type":"textarea","requiredWhen":"tasks.overdue>0"}]},
 {"key":"J","title":"Partnerships & stakeholder engagement","fields":[
   {"key":"stakeholders","label":"Engagements this month","type":"rows","max":10,"cols":[
     {"key":"stakeholder","label":"Stakeholder / organisation"},{"key":"category","label":"Category","type":"select","options":["Women's organisation","Professional body","Institution","Public body","Private sector","Media","Development partner","Community organisation","Other"]},
     {"key":"purpose","label":"Purpose"},{"key":"date","label":"Date","type":"date"},{"key":"outcome","label":"Outcome"},{"key":"commitment","label":"Commitment made"},{"key":"next","label":"Next action"},{"key":"deadline","label":"Deadline","type":"date"}]}]},
 {"key":"K","title":"Communications & visibility","fields":[
   {"key":"comms_ack","label":"Official communications acknowledged","type":"number"},
   {"key":"comms_distributed","label":"Network information distributed","type":"number"},
   {"key":"campaigns","label":"Campaigns supported","type":"number"},
   {"key":"visibility","label":"Local media or visibility activities","type":"number"},
   {"key":"comms_issues","label":"Communication issues","type":"textarea"}]},
 {"key":"L","title":"Digital access & inclusion","auto":["support"],"fields":[
   {"key":"wdos_assist","label":"Members requiring WDOS assistance","type":"number"},
   {"key":"institute_cases","label":"Institute access support cases","type":"number"},
   {"key":"barriers","label":"Connectivity, language or accessibility barriers","type":"textarea"},
   {"key":"group_support","label":"Supported group or viewing arrangements","type":"textarea"}]},
 {"key":"M","title":"Financial / resource accountability","conditional":"finance","fields":[
   {"key":"budget_ref","label":"Approval / budget reference","type":"text"},
   {"key":"approved_amount","label":"Approved amount","type":"number"},
   {"key":"received","label":"Amount received","type":"number"},
   {"key":"spent","label":"Actual expenditure","type":"number"},
   {"key":"commitments","label":"Outstanding commitments","type":"textarea"},
   {"key":"variance","label":"Explanation of variance","type":"textarea"}]},
 {"key":"N","title":"Risks, issues & escalations","auto":["issues"],"fields":[
   {"key":"risks","label":"New non-confidential issues (confidential matters go through the Confidential Reporting channel)","type":"rows","max":10,"cols":[
     {"key":"category","label":"Category","type":"select","options":["Leadership","Membership","Programme","Learning","Technology","Communications","Partnership","Finance","Governance","Data","Operational","Reputation","Other"]},
     {"key":"severity","label":"Severity","type":"select","options":["green","amber","red","critical"]},
     {"key":"issue","label":"Issue"},{"key":"action","label":"Action already taken"},{"key":"owner","label":"Owner"},{"key":"support","label":"Support or decision required"},{"key":"deadline","label":"Deadline","type":"date"}]}]},
 {"key":"O","title":"Top priorities for next month","fields":[
   {"key":"priorities","label":"Maximum five; approved priorities become tasks","type":"rows","max":5,"cols":[
     {"key":"priority","label":"Priority"},{"key":"deliverable","label":"Deliverable"},{"key":"owner","label":"Owner"},{"key":"deadline","label":"Deadline","type":"date"},{"key":"support","label":"Support needed"}]}]},
 {"key":"P","title":"Leader declaration","fields":[
   {"key":"declaration","label":"I confirm that this report is accurate to the best of my knowledge, that supporting evidence has been appropriately recorded or referenced, and that confidential matters have been reported only through the authorised confidential channel.","type":"check","required":true}]}
]$J$, false),
('weekly_pulse', 'Weekly Accountability Pulse', 'weekly', $J$[
 {"key":"A","title":"This week (system-generated)","auto":["identity","tasks","activities","meetings","compliance","issues"],"fields":[]},
 {"key":"B","title":"Leader input","fields":[
   {"key":"achievement","label":"Major achievement this week","type":"textarea","required":true},
   {"key":"blocker","label":"Major blocker or risk","type":"textarea"},
   {"key":"decision","label":"Decision or support required","type":"textarea"},
   {"key":"priorities","label":"Top priorities for next week (maximum five)","type":"rows","max":5,"cols":[
     {"key":"priority","label":"Priority"},{"key":"owner","label":"Owner"},{"key":"deadline","label":"Deadline","type":"date"}]}]}
]$J$, false),
('activity_report', 'Programme / Activity Report', 'event', $J$[
 {"key":"A","title":"Activity identity","auto":["identity"],"fields":[
   {"key":"title","label":"Activity title","type":"text","required":true},
   {"key":"date","label":"Date","type":"date","required":true},
   {"key":"format","label":"Format","type":"select","options":["In person","Virtual","Hybrid"],"required":true},
   {"key":"programme","label":"Programme","type":"text"}]},
 {"key":"B","title":"Approval","fields":[
   {"key":"approval_ref","label":"Approval reference","type":"text"},{"key":"approved_by","label":"Approving authority","type":"text"},{"key":"approval_date","label":"Approval date","type":"date"}]},
 {"key":"C","title":"Objective and delivery","fields":[
   {"key":"objective","label":"What the activity was intended to achieve","type":"textarea","required":true},
   {"key":"delivery","label":"What was actually delivered","type":"textarea","required":true}]},
 {"key":"D","title":"Participation and reach","fields":[
   {"key":"registered","label":"Registered","type":"number"},{"key":"attended","label":"Attended","type":"number","required":true},
   {"key":"categories","label":"Participant categories reached","type":"text"},{"key":"communities","label":"Communities reached","type":"number"}]},
 {"key":"E","title":"Outputs, outcomes and referrals","fields":[
   {"key":"outputs","label":"Immediate deliverables produced","type":"textarea"},
   {"key":"outcomes","label":"What changed or was achieved","type":"textarea","required":true},
   {"key":"referrals","label":"Referrals generated (membership, leadership, learning, support)","type":"number"}]},
 {"key":"F","title":"Financial / resource","conditional":"finance","fields":[
   {"key":"approved_amount","label":"Approved amount","type":"number"},{"key":"spent","label":"Actual expenditure","type":"number"},{"key":"variance","label":"Explanation of variance","type":"textarea"}]},
 {"key":"G","title":"Issues, lessons and follow-up","fields":[
   {"key":"issues","label":"Operational issues (non-confidential)","type":"textarea"},
   {"key":"lessons","label":"Lessons and recommendations","type":"textarea"},
   {"key":"followups","label":"Follow-up actions","type":"rows","max":5,"cols":[{"key":"action","label":"Action"},{"key":"owner","label":"Owner"},{"key":"deadline","label":"Deadline","type":"date"}]}]},
 {"key":"P","title":"Declaration","fields":[{"key":"declaration","label":"I confirm this report is accurate and evidence has been referenced.","type":"check","required":true}]}
]$J$, true),
('meeting_actions', 'Meeting Decisions & Action Report', 'event', $J$[
 {"key":"A","title":"Meeting","auto":["identity","meeting"],"fields":[
   {"key":"meeting_type","label":"Meeting type","type":"select","options":["Leadership check-in","Coordination","Chapter meeting","Programme","Stakeholder","Other"],"required":true},
   {"key":"title","label":"Title","type":"text","required":true},{"key":"date","label":"Date","type":"date","required":true},
   {"key":"chair","label":"Chair","type":"text","required":true},{"key":"secretary","label":"Secretary","type":"text"},
   {"key":"attendance","label":"Attendance (number)","type":"number"}]},
 {"key":"B","title":"Agenda and discussion","fields":[
   {"key":"agenda","label":"Agenda points","type":"textarea","required":true},{"key":"summary","label":"Key discussion summary (concise)","type":"textarea"}]},
 {"key":"C","title":"Decisions and actions","fields":[
   {"key":"actions","label":"One decision per row; approved actions become tasks","type":"rows","max":15,"required":true,"cols":[
     {"key":"decision","label":"Decision"},{"key":"action","label":"Action"},{"key":"owner","label":"Owner"},{"key":"deadline","label":"Deadline","type":"date"}]},
   {"key":"next_meeting","label":"Next meeting","type":"date"}]},
 {"key":"P","title":"Declaration","fields":[{"key":"declaration","label":"I confirm this record is accurate.","type":"check","required":true}]}
]$J$, false),
('exit_handover', 'Exit, Transition & Handover', 'transition', $J$[
 {"key":"A","title":"Auto-pulled handover position","auto":["identity","leadership","tasks","compliance","meetings","issues"],"fields":[]},
 {"key":"B","title":"Transition","fields":[
   {"key":"successor","label":"Successor or receiving authority (where known)","type":"text"},
   {"key":"effective","label":"Effective date","type":"date","required":true},
   {"key":"open_reports","label":"Open or returned reports: complete, transfer or authorised exception","type":"textarea"},
   {"key":"open_tasks","label":"Open tasks and overdue actions: owner, deadline, transition note","type":"textarea","required":true},
   {"key":"programmes","label":"Active programmes: transfer of responsibility and evidence","type":"textarea"},
   {"key":"stakeholders","label":"Stakeholder engagements and commitments transferred","type":"textarea"},
   {"key":"records","label":"Documents, evidence and records: official storage confirmed","type":"textarea"},
   {"key":"assets","label":"Assets or resources returned or transferred","type":"textarea"},
   {"key":"access","label":"Official access and accounts to disable or transfer","type":"textarea"}]},
 {"key":"P","title":"Declaration","fields":[{"key":"declaration","label":"I confirm the handover information is complete; confidential matters were transferred only through the restricted channel.","type":"check","required":true}]}
]$J$, false)
on conflict (code) do update set title = excluded.title, cadence = excluded.cadence,
  sections = excluded.sections, evidence_required = excluded.evidence_required,
  version = report_templates.version + 1, updated_at = now();

-- ---------------------------------------------------------------------------
-- 3 ▸ OPERATIONAL ACTIVITY RECORDS (§7 Workflow 1)
-- ---------------------------------------------------------------------------
create table if not exists public.activity_records (
  id            uuid primary key default gen_random_uuid(),
  profile_id    uuid not null references public.profiles(id) on delete cascade default auth.uid(),
  org_unit_id   uuid references public.org_units(id) on delete set null,
  occurred_at   timestamptz not null default now(),
  category      text not null check (category in
    ('member_engagement', 'mobilisation', 'leadership_followup', 'recruitment_support',
     'learning_support', 'meeting', 'programme', 'stakeholder', 'digital_support',
     'communication', 'task_completed', 'issue', 'other')),
  what          text not null check (char_length(what) between 3 and 1000),
  people_reached int check (people_reached is null or people_reached >= 0),
  people_category text check (people_category is null or char_length(people_category) <= 120),
  result        text not null check (char_length(result) between 1 and 1000),
  follow_up     boolean not null default false,
  follow_up_action text check (follow_up_action is null or char_length(follow_up_action) <= 500),
  follow_up_owner uuid references public.profiles(id) on delete set null,
  follow_up_due date,
  evidence_ref  text check (evidence_ref is null or char_length(evidence_ref) <= 500),
  related_task  uuid references public.tasks(id) on delete set null,
  related_meeting uuid references public.meetings(id) on delete set null,
  related_event uuid references public.programme_events(id) on delete set null,
  escalation    boolean not null default false,
  escalation_category text,
  created_at    timestamptz not null default now()
);
create index if not exists activity_records_unit_idx on public.activity_records (org_unit_id, occurred_at desc);
create index if not exists activity_records_profile_idx on public.activity_records (profile_id, occurred_at desc);

create or replace function public.activity_records_defaults()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.org_unit_id is null then
    select coalesce(
      (select ra.org_unit_id from role_assignments ra
        where ra.profile_id = new.profile_id and ra.ends_at is null
          and ra.role in (select role from position_master)
        order by ra.starts_at desc limit 1),
      (select org_unit_id from profiles where id = new.profile_id))
      into new.org_unit_id;
  end if;
  return new;
end; $$;
drop trigger if exists activity_records_defaults on public.activity_records;
create trigger activity_records_defaults before insert on public.activity_records
  for each row execute function public.activity_records_defaults();

alter table public.activity_records enable row level security;
drop policy if exists activity_read on public.activity_records;
create policy activity_read on public.activity_records for select to authenticated
  using (profile_id = auth.uid() or public.is_case_hq()
         or org_unit_id in (select public.administered_units()));
drop policy if exists activity_insert on public.activity_records;
create policy activity_insert on public.activity_records for insert to authenticated
  with check (profile_id = auth.uid());
drop policy if exists activity_update on public.activity_records;
create policy activity_update on public.activity_records for update to authenticated
  using (profile_id = auth.uid() and created_at > now() - interval '48 hours');

-- ---------------------------------------------------------------------------
-- 4 ▸ ISSUES / ESCALATIONS (§17 Workflow 11)
-- ---------------------------------------------------------------------------
create sequence if not exists public.issue_no_seq;
create table if not exists public.issues (
  id            uuid primary key default gen_random_uuid(),
  issue_no      text unique,
  profile_id    uuid not null references public.profiles(id) on delete cascade default auth.uid(),
  org_unit_id   uuid references public.org_units(id) on delete set null,
  category      text not null,
  severity      public.issue_severity not null default 'amber',
  title         text not null check (char_length(title) between 3 and 200),
  impact        text check (impact is null or char_length(impact) <= 2000),
  action_taken  text check (action_taken is null or char_length(action_taken) <= 2000),
  owner_id      uuid references public.profiles(id) on delete set null,
  decision_required text check (decision_required is null or char_length(decision_required) <= 1000),
  escalated_to  text,                       -- supervisor | country | hofco | hq | management
  due_on        date,
  status        public.issue_status not null default 'open',
  resolution    text check (resolution is null or char_length(resolution) <= 2000),
  report_id     uuid,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create or replace function public.issues_defaults()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.issue_no is null then
    new.issue_no := 'ISS-' || to_char(now(), 'YYYY') || '-' || lpad(nextval('issue_no_seq')::text, 4, '0');
  end if;
  if new.org_unit_id is null then
    select coalesce(
      (select ra.org_unit_id from role_assignments ra
        where ra.profile_id = new.profile_id and ra.ends_at is null
          and ra.role in (select role from position_master)
        order by ra.starts_at desc limit 1),
      (select org_unit_id from profiles where id = new.profile_id)) into new.org_unit_id;
  end if;
  return new;
end; $$;
drop trigger if exists issues_defaults on public.issues;
create trigger issues_defaults before insert on public.issues
  for each row execute function public.issues_defaults();
drop trigger if exists issues_touch on public.issues;
create trigger issues_touch before update on public.issues
  for each row execute function public.touch_updated_at();
alter table public.issues enable row level security;
drop policy if exists issues_read on public.issues;
create policy issues_read on public.issues for select to authenticated
  using (profile_id = auth.uid() or owner_id = auth.uid() or public.is_case_hq()
         or org_unit_id in (select public.administered_units()));
drop policy if exists issues_insert on public.issues;
create policy issues_insert on public.issues for insert to authenticated
  with check (profile_id = auth.uid());
drop policy if exists issues_update on public.issues;
create policy issues_update on public.issues for update to authenticated
  using (profile_id = auth.uid() or owner_id = auth.uid() or public.is_case_hq()
         or org_unit_id in (select public.administered_units()));

-- ---------------------------------------------------------------------------
-- 5 ▸ REPORT INSTANCES, REVIEWS, CONTRIBUTIONS (§23, §27, §30)
-- ---------------------------------------------------------------------------
create sequence if not exists public.report_no_seq;
create table if not exists public.report_instances (
  id             uuid primary key default gen_random_uuid(),
  report_no      text unique,
  template       text not null references public.report_templates(code),
  org_unit_id    uuid not null references public.org_units(id) on delete restrict,
  owner_id       uuid not null references public.profiles(id) on delete restrict,
  network        public.network_code not null default 'WGMN',
  period_start   date not null,
  period_end     date not null,
  due_on         date not null,
  status         public.report_status not null default 'draft',
  version        int not null default 1,
  supersedes     uuid references public.report_instances(id) on delete set null,
  is_current     boolean not null default true,
  snapshot       jsonb not null default '{}'::jsonb,   -- frozen at submit
  answers        jsonb not null default '{}'::jsonb,   -- original free text preserved
  evidence       jsonb not null default '[]'::jsonb,   -- [{name, path|url, note}]
  is_nil         boolean not null default false,
  nil_reason     text,
  linked_meeting uuid references public.meetings(id) on delete set null,
  linked_event   uuid references public.programme_events(id) on delete set null,
  submitted_at   timestamptz,
  submitted_by   uuid references public.profiles(id) on delete set null,
  first_submitted_at timestamptz,
  reviewer_id    uuid references public.profiles(id) on delete set null,
  reviewed_at    timestamptz,
  review_note    text,
  escalated_to   text,
  escalation_level int not null default 0,         -- reminder engine (§24)
  reminders_sent jsonb not null default '[]'::jsonb,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create unique index if not exists report_instances_one_current
  on public.report_instances (template, org_unit_id, network, period_start)
  where is_current and template in ('monthly_leadership', 'weekly_pulse');
create index if not exists report_instances_unit_idx on public.report_instances (org_unit_id, period_start desc);
create index if not exists report_instances_owner_idx on public.report_instances (owner_id, status);

create or replace function public.report_instances_defaults()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.report_no is null then
    new.report_no := 'RPT-' || to_char(now(), 'YYYY') || '-' || lpad(nextval('report_no_seq')::text, 5, '0');
  end if;
  return new;
end; $$;
drop trigger if exists report_instances_defaults on public.report_instances;
create trigger report_instances_defaults before insert on public.report_instances
  for each row execute function public.report_instances_defaults();
drop trigger if exists report_instances_touch on public.report_instances;
create trigger report_instances_touch before update on public.report_instances
  for each row execute function public.touch_updated_at();
drop trigger if exists report_instances_audit on public.report_instances;
create trigger report_instances_audit after insert or update or delete on public.report_instances
  for each row execute function public.audit_row();

create table if not exists public.report_reviews (
  id         uuid primary key default gen_random_uuid(),
  report_id  uuid not null references public.report_instances(id) on delete cascade,
  actor_id   uuid not null references public.profiles(id) default auth.uid(),
  action     text not null check (action in ('submit', 'resubmit', 'return', 'approve', 'escalate', 'close', 'version')),
  note       text,
  version    int not null,
  answers    jsonb,                                  -- the submitted version, preserved (§23.1)
  snapshot   jsonb,
  at         timestamptz not null default now()
);
create index if not exists report_reviews_report_idx on public.report_reviews (report_id, at);
drop trigger if exists report_reviews_no_update on public.report_reviews;
create trigger report_reviews_no_update before update or delete on public.report_reviews
  for each row execute function public.audit_block_change();

create table if not exists public.report_contributions (
  id         uuid primary key default gen_random_uuid(),
  report_id  uuid not null references public.report_instances(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) default auth.uid(),
  note       text not null check (char_length(note) between 1 and 3000),
  evidence   jsonb not null default '[]'::jsonb,
  at         timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- 6 ▸ SCOPE HELPERS (§3.2, §4, §21.1)
-- ---------------------------------------------------------------------------
-- The unit a person reports FOR: her principal seat, or her deputy seat when
-- she is formally acting or the principal seat is vacant.
create or replace function public.report_unit_for(pid uuid)
returns table (org_unit_id uuid, role public.role_code, can_submit boolean)
language sql stable security definer set search_path = public as $$
  select ra.org_unit_id, ra.role,
         (pm.rank = 1
          or ra.appointment_status = 'acting'
          or not exists (select 1 from role_assignments r2 join position_master p2 on p2.role = r2.role
                          where r2.org_unit_id = ra.org_unit_id and r2.ends_at is null
                            and p2.level = pm.level and p2.rank = 1 and r2.profile_id <> pid)) as can_submit
  from role_assignments ra
  join position_master pm on pm.role = ra.role
  where ra.profile_id = pid and ra.ends_at is null
  order by pm.rank, ra.starts_at desc
  limit 1;
$$;

-- Supervisor of a unit: principal (then deputy) at the parent unit, same network.
create or replace function public.report_supervisor(unit uuid, net public.network_code)
returns uuid language sql stable security definer set search_path = public as $$
  select ra.profile_id
  from org_units u
  join role_assignments ra on ra.org_unit_id = u.parent_id and ra.ends_at is null
  join position_master pm on pm.role = ra.role
  join profiles p on p.id = ra.profile_id and p.network = net
  where u.id = unit
  order by pm.rank, ra.starts_at
  limit 1;
$$;

create or replace function public.rp_can_review(rid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from report_instances r
     where r.id = rid
       and (is_case_hq()
            or (r.org_unit_id in (select administered_units())
                and r.org_unit_id not in (select org_unit_id from role_assignments
                                            where profile_id = auth.uid() and ends_at is null))));
$$;

create or replace function public.rp_can_see(rid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from report_instances r
     where r.id = rid
       and (r.owner_id = auth.uid() or is_case_hq()
            or r.org_unit_id in (select administered_units())
            or r.org_unit_id = (select org_unit_id from report_unit_for(auth.uid()))));
$$;

alter table public.report_instances enable row level security;
drop policy if exists reports_read on public.report_instances;
create policy reports_read on public.report_instances for select to authenticated
  using (public.rp_can_see(id));
alter table public.report_reviews enable row level security;
drop policy if exists report_reviews_read on public.report_reviews;
create policy report_reviews_read on public.report_reviews for select to authenticated
  using (public.rp_can_see(report_id));
alter table public.report_contributions enable row level security;
drop policy if exists contrib_read on public.report_contributions;
create policy contrib_read on public.report_contributions for select to authenticated
  using (public.rp_can_see(report_id));
drop policy if exists contrib_insert on public.report_contributions;
create policy contrib_insert on public.report_contributions for insert to authenticated
  with check (profile_id = auth.uid() and public.rp_can_see(report_id)
              and exists (select 1 from report_instances r where r.id = report_id
                           and r.status in ('draft', 'returned')));

-- ---------------------------------------------------------------------------
-- 7 ▸ PERIODS (§3, §24, Appendix B)
-- ---------------------------------------------------------------------------
create or replace function public.report_period(tpl text, on_date date default current_date)
returns table (period_start date, period_end date, due_on date)
language plpgsql stable security definer set search_path = public as $$
declare cad text; d int;
begin
  select cadence into cad from report_templates where code = tpl;
  if cad = 'monthly' then
    d := coalesce((rcfg('monthly_due_day'))::int, 7);
    period_start := date_trunc('month', on_date)::date;
    period_end := (period_start + interval '1 month' - interval '1 day')::date;
    due_on := (period_start + interval '1 month')::date + (d - 1);
  elsif cad = 'weekly' then
    period_start := date_trunc('week', on_date)::date;          -- Monday
    period_end := period_start + 6;
    due_on := period_end + 1;                                    -- following Monday
  elsif cad = 'transition' then
    period_start := on_date; period_end := on_date; due_on := on_date + 14;
  else
    period_start := on_date; period_end := on_date;
    due_on := on_date + coalesce((rcfg(case when tpl = 'meeting_actions'
                                       then 'meeting_report_days' else 'event_report_days' end))::int, 5);
  end if;
  return next;
end; $$;

-- Is the weekly pulse switched on for this unit? (§8 cadence control)
create or replace function public.weekly_pulse_required(unit uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select (u.level::text in (select jsonb_array_elements_text(coalesce(rcfg('weekly_pulse_levels'), '[]'::jsonb))))
      or (u.country_iso in (select jsonb_array_elements_text(coalesce(rcfg('weekly_pulse_countries'), '[]'::jsonb))))
      or (exists (select 1 from unit_chain(u.id) c join org_units o on o.id = c.id
                   where o.country_iso in (select jsonb_array_elements_text(coalesce(rcfg('weekly_pulse_countries'), '[]'::jsonb)))))
  from org_units u where u.id = unit;
$$;

-- ---------------------------------------------------------------------------
-- 8 ▸ SNAPSHOT (§6.2, §9, §22): every metric traces to rows in scope
-- ---------------------------------------------------------------------------
create or replace function public.report_snapshot(unit uuid, ps date, pe date, net public.network_code default 'WGMN')
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  scope uuid[];
  v_lead jsonb; v_pipe jsonb; v_mem jsonb; v_tasks jsonb; v_meet jsonb; v_act jsonb;
  v_learn jsonb; v_comp jsonb; v_issues jsonb; v_supp jsonb; v_prog jsonb; v_ident jsonb;
  pe_ts timestamptz := (pe + 1)::timestamptz; ps_ts timestamptz := ps::timestamptz;
  u org_units%rowtype; v_due date;
begin
  select due_on into v_due from report_period('monthly_leadership', ps);
  select * into u from org_units where id = unit;
  select coalesce(array_agg(id), '{}') into scope from org_unit_subtree(unit) as s(id);

  -- identity
  select jsonb_build_object('unit', u.name, 'level', u.level, 'country_iso', u.country_iso,
           'chain', (select coalesce(jsonb_agg(jsonb_build_object('level', c.level, 'name', c.name) order by c.depth desc), '[]'::jsonb)
                      from unit_chain(unit) c),
           'terms', level_terms_for((select o.country_iso from unit_chain(unit) c join org_units o on o.id = c.id where c.level = 'country' limit 1)),
           'supervisor', (select p.first_name || ' ' || p.last_name from profiles p where p.id = report_supervisor(unit, net)),
           'supervisor_id', report_supervisor(unit, net))
    into v_ident;

  -- leadership coverage (§9.2): seats = units in scope × positions of their level; per network
  with seats as (
    select s.id as unit_id, pm.role,
           (select r.profile_id from role_assignments r join profiles hp on hp.id = r.profile_id
             where r.org_unit_id = s.id and r.role = pm.role and r.ends_at is null and hp.network = net
             order by r.starts_at limit 1) as holder
      from org_units s join position_master pm on pm.level = s.level
     where s.id = any(scope) and s.level <> 'headquarters')
  select jsonb_build_object(
    'approved_positions', count(*), 'filled', count(holder), 'vacant', count(*) - count(holder),
    'active', count(*) filter (where holder is not null and (select last_seen_at from profiles where id = holder) >= now() - interval '30 days'),
    'inactive', count(*) filter (where holder is not null and coalesce((select last_seen_at from profiles where id = holder), '2000-01-01') < now() - interval '30 days'),
    'exits', (select count(*) from role_assignments ra join org_units o on o.id = ra.org_unit_id
               where ra.org_unit_id = any(scope) and ra.ends_at >= ps_ts and ra.ends_at < pe_ts),
    'appointments', (select count(*) from role_assignments ra where ra.org_unit_id = any(scope)
                      and ra.starts_at >= ps_ts and ra.starts_at < pe_ts))
    into v_lead from seats;

  -- recruitment / activation pipeline in scope during the period
  select jsonb_build_object(
    'referrals', (select count(*) from referrals r where r.org_unit_id = any(scope) and r.category = 'leadership_candidate'
                   and r.created_at >= ps_ts and r.created_at < pe_ts),
    'applications', (select count(*) from applications a where a.org_unit_id = any(scope)
                      and a.created_at >= ps_ts and a.created_at < pe_ts),
    'in_activation', (select count(*) from activation_journeys j join profiles p on p.id = j.profile_id
                       where p.org_unit_id = any(scope) and j.status = 'in_progress'),
    'activation_completed', (select count(*) from activation_journeys j join profiles p on p.id = j.profile_id
                              where p.org_unit_id = any(scope) and j.completed_at >= ps_ts and j.completed_at < pe_ts),
    'awaiting_assessment', (select count(*) from applications a where a.org_unit_id = any(scope) and a.status in ('submitted', 'under_review')),
    'awaiting_appointment', (select count(*) from applications a where a.org_unit_id = any(scope) and a.status in ('recommended', 'approved')
                              and not exists (select 1 from role_assignments ra where ra.profile_id = a.profile_id and ra.ends_at is null)))
    into v_pipe;

  -- membership (§9.4): opening = in scope before period; new = created in period; closing = now
  select jsonb_build_object(
    'opening', count(*) filter (where p.created_at < ps_ts and p.status not in ('applicant', 'under_review', 'removed', 'resigned')),
    'new', count(*) filter (where p.created_at >= ps_ts and p.created_at < pe_ts),
    'active', count(*) filter (where p.status = 'active'),
    'inactive', count(*) filter (where p.status in ('inactive', 'suspended')),
    'exited', count(*) filter (where p.status in ('resigned', 'removed', 'alumni') and p.updated_at >= ps_ts and p.updated_at < pe_ts),
    'closing', count(*) filter (where p.status not in ('applicant', 'under_review', 'removed', 'resigned')),
    'units_active', (select count(distinct a.org_unit_id) from activity_records a where a.org_unit_id = any(scope) and a.occurred_at >= ps_ts and a.occurred_at < pe_ts),
    'referrals', (select count(*) from referrals r where r.org_unit_id = any(scope) and r.created_at >= ps_ts and r.created_at < pe_ts),
    'women_reached', (select count(*) from beneficiaries b
                       where b.org_unit_id = any(scope) and b.created_at >= ps_ts and b.created_at < pe_ts))
    into v_mem
    from profiles p where p.org_unit_id = any(scope) and p.merged_into is null and p.network = net;

  -- tasks (§9.7)
  select jsonb_build_object(
    'completed', count(*) filter (where t.status = 'completed' and t.completed_at >= ps_ts and t.completed_at < pe_ts),
    'in_progress', count(*) filter (where t.status = 'in_progress'),
    'not_started', count(*) filter (where t.status = 'not_started'),
    'awaiting_decision', count(*) filter (where t.status = 'awaiting_review'),
    'overdue', count(*) filter (where t.status in ('not_started', 'in_progress', 'awaiting_review') and t.due_on < current_date),
    'due', count(*) filter (where t.due_on between ps and pe))
    into v_tasks from tasks t where t.org_unit_id = any(scope);

  -- meetings (§9.7)
  select jsonb_build_object(
    'held', count(*) filter (where m.starts_at >= ps_ts and m.starts_at < pe_ts and m.status in ('scheduled', 'completed')),
    'scheduled', count(*) filter (where m.starts_at >= pe_ts and m.status = 'scheduled'),
    'attendance', (select count(*) from meeting_attendance ma join meetings m2 on m2.id = ma.meeting_id
                    where m2.org_unit_id = any(scope) and ma.present and m2.starts_at >= ps_ts and m2.starts_at < pe_ts),
    'action_reports', (select count(*) from report_instances r where r.org_unit_id = any(scope) and r.template = 'meeting_actions'
                        and r.period_start between ps and pe and r.status in ('submitted', 'approved', 'under_review')))
    into v_meet from meetings m where m.org_unit_id = any(scope);

  -- operational activity records (§7): counted once, by category
  select jsonb_build_object(
    'total', count(*), 'people_reached', coalesce(sum(a.people_reached), 0),
    'by_category', coalesce((select jsonb_object_agg(c, n) from (select category as c, count(*) as n
                              from activity_records where org_unit_id = any(scope) and occurred_at >= ps_ts and occurred_at < pe_ts
                              group by category) q), '{}'::jsonb),
    'follow_ups_open', count(*) filter (where a.follow_up and (a.follow_up_due is null or a.follow_up_due >= current_date)),
    'escalations', count(*) filter (where a.escalation))
    into v_act from activity_records a where a.org_unit_id = any(scope) and a.occurred_at >= ps_ts and a.occurred_at < pe_ts;

  -- programmes (§9.6): events in period + approved activity reports
  select jsonb_build_object(
    'planned', (select count(*) from programme_events e where e.org_unit_id = any(scope) and e.event_date between ps and pe),
    'implemented', (select count(*) from report_instances r where r.org_unit_id = any(scope) and r.template = 'activity_report'
                     and r.period_start between ps and pe and r.status in ('submitted', 'under_review', 'approved')),
    'approved_reports', (select count(*) from report_instances r where r.org_unit_id = any(scope) and r.template = 'activity_report'
                          and r.period_start between ps and pe and r.status = 'approved'),
    'participants', (select coalesce(sum((r.answers->>'attended')::int), 0) from report_instances r
                      where r.org_unit_id = any(scope) and r.template = 'activity_report'
                        and r.period_start between ps and pe and r.status = 'approved' and (r.answers->>'attended') ~ '^[0-9]+$'),
    'evidence_missing', (select count(*) from report_instances r where r.org_unit_id = any(scope) and r.template = 'activity_report'
                          and r.period_start between ps and pe and jsonb_array_length(r.evidence) = 0))
    into v_prog;

  -- learning (WDOS courses only; Institute is the learning source of truth, §14)
  select jsonb_build_object(
    'enrolled', count(*), 'started', count(*) filter (where ce.started_at is not null),
    'completed', count(*) filter (where ce.completed_at is not null),
    'certified', count(*) filter (where ce.cert_no is not null),
    'source', 'wdos_courses')
    into v_learn from course_enrollments ce join profiles p on p.id = ce.profile_id
   where p.org_unit_id = any(scope) and p.network = net;

  -- reporting compliance of direct reporting units (§9.3)
  with direct as (
    select o.id from org_units o where o.parent_id = unit),
  expected as (
    select d.id as unit_id,
           exists (select 1 from role_assignments ra join position_master pm on pm.role = ra.role join profiles hp on hp.id = ra.profile_id
                    where ra.org_unit_id = d.id and ra.ends_at is null and hp.network = net) as has_leader,
           (select r from report_instances r where r.org_unit_id = d.id and r.template = 'monthly_leadership'
              and r.network = net and r.period_start = ps and r.is_current limit 1) as rep
      from direct d)
  select jsonb_build_object(
    'units', count(*), 'expected', count(*) filter (where has_leader),
    'submitted', count(*) filter (where (rep).status in ('submitted', 'under_review', 'approved', 'escalated', 'closed')),
    'on_time', count(*) filter (where (rep).first_submitted_at is not null and (rep).first_submitted_at::date <= (rep).due_on),
    'approved', count(*) filter (where (rep).status = 'approved'),
    'returned', count(*) filter (where (rep).status = 'returned'),
    'overdue', count(*) filter (where has_leader and ((rep).id is null or (rep).status in ('draft', 'returned'))
                                  and v_due < current_date),
    'not_submitted', count(*) filter (where has_leader and ((rep).id is null or (rep).status = 'draft')),
    'evidence_complete', count(*) filter (where (rep).status = 'approved' and jsonb_array_length((rep).evidence) > 0))
    into v_comp from expected;

  -- issues (§17)
  select jsonb_build_object(
    'open', count(*) filter (where i.status in ('open', 'in_progress', 'awaiting_decision')),
    'red_critical', count(*) filter (where i.status in ('open', 'in_progress', 'awaiting_decision') and i.severity in ('red', 'critical')),
    'resolved', count(*) filter (where i.status in ('resolved', 'closed') and i.updated_at >= ps_ts and i.updated_at < pe_ts),
    'list', coalesce((select jsonb_agg(jsonb_build_object('issue_no', x.issue_no, 'title', x.title, 'severity', x.severity, 'status', x.status, 'due_on', x.due_on) order by x.severity desc, x.created_at)
                       from (select * from issues where org_unit_id = any(scope) and status in ('open', 'in_progress', 'awaiting_decision')
                              order by severity desc, created_at limit 20) x), '[]'::jsonb))
    into v_issues from issues i where i.org_unit_id = any(scope);

  -- digital support (non-confidential ticket counts, §16)
  select jsonb_build_object(
    'opened', count(*) filter (where t.created_at >= ps_ts and t.created_at < pe_ts),
    'resolved', count(*) filter (where t.status in ('resolved', 'closed') and t.updated_at >= ps_ts and t.updated_at < pe_ts),
    'open', count(*) filter (where t.status in ('open', 'in_progress', 'waiting_on_user')))
    into v_supp from tickets t join profiles p on p.id = t.requester_id where p.org_unit_id = any(scope);

  return jsonb_build_object(
    'identity', v_ident, 'leadership', v_lead, 'pipeline', v_pipe, 'membership', v_mem,
    'tasks', v_tasks, 'meetings', v_meet, 'activities', v_act, 'programmes', v_prog,
    'learning', v_learn, 'compliance', v_comp, 'issues', v_issues, 'support', v_supp,
    'period', jsonb_build_object('start', ps, 'end', pe), 'generated_at', now());
end; $$;

-- ---------------------------------------------------------------------------
-- 9 ▸ WORKFLOW RPCs (§23)
-- ---------------------------------------------------------------------------
-- Open (get or create) the current instance for my unit; refresh the
-- snapshot while it is still a draft.
create or replace function public.report_open(tpl text, on_date date default current_date,
                                              p_meeting uuid default null, p_event uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  ru record; pr record; r report_instances%rowtype; net public.network_code;
  t report_templates%rowtype;
begin
  if me is null then raise exception 'Not signed in'; end if;
  select * into t from report_templates where code = tpl and active;
  if not found then raise exception 'Unknown report template'; end if;
  select * into ru from report_unit_for(me);
  if ru.org_unit_id is null then raise exception 'You do not hold a leadership seat; reports belong to a leadership unit'; end if;
  select network into net from profiles where id = me;
  select * into pr from report_period(tpl, on_date);

  if t.cadence in ('monthly', 'weekly') then
    select * into r from report_instances
     where template = tpl and org_unit_id = ru.org_unit_id and network = net
       and period_start = pr.period_start and is_current limit 1;
  end if;
  if r.id is null then
    insert into report_instances (template, org_unit_id, owner_id, network, period_start, period_end, due_on,
                                  linked_meeting, linked_event)
    values (tpl, ru.org_unit_id,
            coalesce((select r2.profile_id from role_assignments r2 join position_master p2 on p2.role = r2.role
                       where r2.org_unit_id = ru.org_unit_id and r2.ends_at is null and p2.rank = 1
                       order by r2.starts_at limit 1), me),
            net, pr.period_start, pr.period_end, pr.due_on, p_meeting, p_event)
    returning * into r;
  end if;
  if r.status in ('draft', 'returned') then
    update report_instances set snapshot = report_snapshot(r.org_unit_id, r.period_start, r.period_end, r.network)
     where id = r.id returning * into r;
  end if;
  return to_jsonb(r) || jsonb_build_object(
    'template_def', to_jsonb(t),
    'can_submit', (ru.can_submit and r.status in ('draft', 'returned')),
    'my_role', ru.role,
    'contributions', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'name', p.first_name || ' ' || p.last_name,
                        'note', c.note, 'evidence', c.evidence, 'at', c.at) order by c.at), '[]'::jsonb)
                       from report_contributions c join profiles p on p.id = c.profile_id where c.report_id = r.id),
    'reviews', (select coalesce(jsonb_agg(jsonb_build_object('action', v.action, 'note', v.note, 'version', v.version, 'at', v.at,
                        'by', p.first_name || ' ' || p.last_name) order by v.at), '[]'::jsonb)
                 from report_reviews v join profiles p on p.id = v.actor_id where v.report_id = r.id));
end; $$;
revoke execute on function public.report_open(text, date, uuid, uuid) from anon;

create or replace function public.report_get(rid uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare r report_instances%rowtype; t report_templates%rowtype;
begin
  if not rp_can_see(rid) then raise exception 'Not allowed'; end if;
  select * into r from report_instances where id = rid;
  select * into t from report_templates where code = r.template;
  return to_jsonb(r) || jsonb_build_object(
    'template_def', to_jsonb(t),
    'owner_name', (select first_name || ' ' || last_name from profiles where id = r.owner_id),
    'unit_name', (select name from org_units where id = r.org_unit_id),
    'can_review', rp_can_review(rid) and r.status in ('submitted', 'under_review', 'escalated'),
    'can_submit', (r.owner_id = auth.uid() or (select can_submit from report_unit_for(auth.uid()) where org_unit_id = r.org_unit_id))
                  and r.status in ('draft', 'returned'),
    'contributions', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'name', p.first_name || ' ' || p.last_name,
                        'note', c.note, 'evidence', c.evidence, 'at', c.at) order by c.at), '[]'::jsonb)
                       from report_contributions c join profiles p on p.id = c.profile_id where c.report_id = r.id),
    'reviews', (select coalesce(jsonb_agg(jsonb_build_object('action', v.action, 'note', v.note, 'version', v.version, 'at', v.at,
                        'by', p.first_name || ' ' || p.last_name) order by v.at), '[]'::jsonb)
                 from report_reviews v join profiles p on p.id = v.actor_id where v.report_id = r.id));
end; $$;
revoke execute on function public.report_get(uuid) from anon;

-- Autosave (owner or acting submitter, or a contributor of the same unit)
create or replace function public.report_save(rid uuid, p_answers jsonb, p_evidence jsonb default null,
                                              p_nil boolean default null, p_nil_reason text default null)
returns void language plpgsql security definer set search_path = public as $$
declare r report_instances%rowtype; ru record;
begin
  select * into r from report_instances where id = rid;
  if not found then raise exception 'No such report'; end if;
  select * into ru from report_unit_for(auth.uid());
  if not (r.owner_id = auth.uid() or ru.org_unit_id = r.org_unit_id or is_case_hq()) then
    raise exception 'Not allowed';
  end if;
  if r.status not in ('draft', 'returned') then raise exception 'This report is locked'; end if;
  update report_instances
     set answers = coalesce(p_answers, answers),
         evidence = coalesce(p_evidence, evidence),
         is_nil = coalesce(p_nil, is_nil),
         nil_reason = coalesce(p_nil_reason, nil_reason)
   where id = rid;
end; $$;
revoke execute on function public.report_save(uuid, jsonb, jsonb, boolean, text) from anon;

-- Validation (§26.2) returns {ok, errors[], warnings[]}
create or replace function public.report_validate(rid uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  r report_instances%rowtype; t report_templates%rowtype;
  sec jsonb; f jsonb; errs text[] := '{}'; warns text[] := '{}';
  v text; cond text; sensitive text[] := array['abuse', 'assault', 'harass', 'rape', 'molest', 'violence', 'complaint against', 'disciplinary', 'grievance'];
  w text; all_text text;
begin
  select * into r from report_instances where id = rid;
  select * into t from report_templates where code = r.template;
  if r.is_nil then
    if coalesce(r.nil_reason, '') = '' then errs := errs || 'nil_reason'; end if;
    if not coalesce((r.answers->>'declaration')::boolean, false) then errs := errs || 'declaration'; end if;
    return jsonb_build_object('ok', array_length(errs, 1) is null, 'errors', to_jsonb(errs), 'warnings', '[]'::jsonb);
  end if;
  for sec in select * from jsonb_array_elements(t.sections) loop
    if sec->>'conditional' = 'finance' and not coalesce((r.answers->>'has_finance')::boolean, false) then continue; end if;
    for f in select * from jsonb_array_elements(coalesce(sec->'fields', '[]'::jsonb)) loop
      v := r.answers->>(f->>'key');
      if coalesce((f->>'required')::boolean, false) then
        if f->>'type' = 'check' then
          if not coalesce(v::boolean, false) then errs := errs || (f->>'key'); end if;
        elsif f->>'type' = 'rows' then
          if jsonb_typeof(r.answers->(f->>'key')) <> 'array' or jsonb_array_length(r.answers->(f->>'key')) = 0 then errs := errs || (f->>'key'); end if;
        elsif coalesce(trim(v), '') = '' then errs := errs || (f->>'key'); end if;
      end if;
      cond := f->>'requiredWhen';
      if cond = 'tasks.overdue>0' and coalesce((r.snapshot->'tasks'->>'overdue')::int, 0) > 0 and coalesce(trim(v), '') = '' then
        errs := errs || (f->>'key');
      elsif cond = 'compliance.overdue>0' and coalesce((r.snapshot->'compliance'->>'overdue')::int, 0) > 0 and coalesce(trim(v), '') = '' then
        errs := errs || (f->>'key');
      end if;
    end loop;
  end loop;
  -- red/critical rows need action + owner
  if jsonb_typeof(r.answers->'risks') = 'array' then
    for f in select * from jsonb_array_elements(r.answers->'risks') loop
      if f->>'severity' in ('red', 'critical') and (coalesce(f->>'action', '') = '' or coalesce(f->>'owner', '') = '') then
        errs := errs || 'risks_red_action_owner';
      end if;
    end loop;
  end if;
  -- priorities max five
  if jsonb_typeof(r.answers->'priorities') = 'array' and jsonb_array_length(r.answers->'priorities') > 5 then
    errs := errs || 'priorities_max5';
  end if;
  -- evidence
  if t.evidence_required and jsonb_array_length(r.evidence) = 0 then errs := errs || 'evidence'; end if;
  -- sensitive words → warn and redirect (§26.2)
  all_text := lower(coalesce(r.answers::text, ''));
  foreach w in array sensitive loop
    if position(w in all_text) > 0 then warns := warns || ('sensitive:' || w); exit; end if;
  end loop;
  -- activity claimed without records
  if r.template = 'monthly_leadership' and coalesce((r.snapshot->'activities'->>'total')::int, 0) = 0
     and coalesce(trim(r.answers->>'improved'), '') <> '' then
    warns := warns || 'no_activity_records';
  end if;
  return jsonb_build_object('ok', array_length(errs, 1) is null, 'errors', to_jsonb(errs), 'warnings', to_jsonb(warns));
end; $$;
revoke execute on function public.report_validate(uuid) from anon;

create or replace function public.report_submit(rid uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r report_instances%rowtype; ru record; val jsonb; sup uuid; act text;
begin
  select * into r from report_instances where id = rid;
  if not found then raise exception 'No such report'; end if;
  select * into ru from report_unit_for(auth.uid());
  if not (is_case_hq() or (ru.org_unit_id = r.org_unit_id and ru.can_submit) or r.owner_id = auth.uid()) then
    raise exception 'Only the accountable leader (or a formally acting deputy) submits the unit report';
  end if;
  if r.status not in ('draft', 'returned') then raise exception 'This report is locked'; end if;
  val := report_validate(rid);
  if not (val->>'ok')::boolean then return val; end if;
  act := case when r.status = 'returned' then 'resubmit' else 'submit' end;
  update report_instances
     set snapshot = report_snapshot(org_unit_id, period_start, period_end, network),
         status = 'submitted', submitted_at = now(), submitted_by = auth.uid(),
         first_submitted_at = coalesce(first_submitted_at, now())
   where id = rid returning * into r;
  insert into report_reviews (report_id, actor_id, action, version, answers, snapshot)
  values (rid, auth.uid(), act, r.version, r.answers, r.snapshot);
  -- notify the supervisor (in-app notice; the bell and push follow)
  sup := report_supervisor(r.org_unit_id, r.network);
  if sup is not null then
    insert into member_notices (profile_id, kind, title, body, meta)
    values (sup, 'report',
            'Report submitted for your review: ' || r.report_no,
            (select name from org_units where id = r.org_unit_id) || ' · ' || r.template || ' · ' || to_char(r.period_start, 'Mon YYYY'),
            jsonb_build_object('report_id', r.id, 'href', '#/reporting/review/' || r.id));
  end if;
  return val || jsonb_build_object('status', 'submitted', 'report_no', r.report_no);
end; $$;
revoke execute on function public.report_submit(uuid) from anon;

-- Reviewer: approve (locks; creates tasks from priorities / meeting actions),
-- return with reason, escalate, close.
create or replace function public.report_review(rid uuid, decision text, note text default null,
                                                create_tasks boolean default true)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r report_instances%rowtype; row_j jsonb; n int := 0; due date; owner uuid;
begin
  select * into r from report_instances where id = rid;
  if not found then raise exception 'No such report'; end if;
  if not rp_can_review(rid) then raise exception 'You are not the reviewer of this unit'; end if;
  if r.status not in ('submitted', 'under_review', 'escalated') then raise exception 'Report is not awaiting review'; end if;
  if decision = 'return' then
    if coalesce(trim(note), '') = '' then raise exception 'A reason is required to return a report'; end if;
    update report_instances set status = 'returned', reviewer_id = auth.uid(), reviewed_at = now(), review_note = note where id = rid;
  elsif decision = 'approve' then
    update report_instances set status = 'approved', reviewer_id = auth.uid(), reviewed_at = now(), review_note = note where id = rid;
    if create_tasks then
      for row_j in select * from jsonb_array_elements(coalesce(
                     case when r.template = 'meeting_actions' then r.answers->'actions' else r.answers->'priorities' end, '[]'::jsonb)) loop
        if coalesce(row_j->>'priority', row_j->>'action', '') = '' then continue; end if;
        due := case when (row_j->>'deadline') ~ '^\d{4}-\d{2}-\d{2}$' then (row_j->>'deadline')::date else null end;
        owner := r.owner_id;
        insert into tasks (title, details, org_unit_id, assigned_to, assigned_by, due_on, source_report_id)
        values (left(coalesce(row_j->>'priority', row_j->>'action'), 160),
                left('From ' || r.report_no || coalesce(' · ' || (row_j->>'deliverable'), '') || coalesce(' · ' || (row_j->>'decision'), '')
                     || coalesce(' · owner: ' || (row_j->>'owner'), ''), 4000),
                r.org_unit_id, owner, auth.uid(), due, r.id);
        n := n + 1;
      end loop;
    end if;
    -- new non-confidential issues from Section N become tracked issues (§17)
    if jsonb_typeof(r.answers->'risks') = 'array' then
      for row_j in select * from jsonb_array_elements(r.answers->'risks') loop
        if coalesce(row_j->>'issue', '') = '' then continue; end if;
        insert into issues (profile_id, org_unit_id, category, severity, title, action_taken, decision_required, due_on, report_id)
        values (r.owner_id, r.org_unit_id, coalesce(row_j->>'category', 'Other'),
                coalesce(nullif(row_j->>'severity', ''), 'amber')::public.issue_severity,
                left(row_j->>'issue', 200), row_j->>'action', row_j->>'support',
                case when (row_j->>'deadline') ~ '^\d{4}-\d{2}-\d{2}$' then (row_j->>'deadline')::date else null end, r.id);
      end loop;
    end if;
  elsif decision = 'escalate' then
    update report_instances set status = 'escalated', reviewer_id = auth.uid(), reviewed_at = now(), review_note = note,
           escalated_to = coalesce(note, 'HQ') where id = rid;
  elsif decision = 'close' then
    update report_instances set status = 'closed', reviewed_at = now() where id = rid;
  else
    raise exception 'Unknown decision';
  end if;
  insert into report_reviews (report_id, actor_id, action, version, note)
  values (rid, auth.uid(), decision, r.version, note);
  insert into member_notices (profile_id, kind, title, body, meta)
  values (r.owner_id, 'report', 'Your report ' || r.report_no || ' was ' ||
          case decision when 'approve' then 'approved' when 'return' then 'returned for correction'
                        when 'escalate' then 'escalated' else 'closed' end,
          coalesce(note, ''), jsonb_build_object('report_id', r.id, 'href', '#/reporting/report/' || r.id));
  return jsonb_build_object('status', decision, 'tasks_created', n);
end; $$;
revoke execute on function public.report_review(uuid, text, text, boolean) from anon;

-- Approved report correction → new version; the original stays (§23.1)
create or replace function public.report_new_version(rid uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare r report_instances%rowtype; nid uuid;
begin
  select * into r from report_instances where id = rid;
  if not found then raise exception 'No such report'; end if;
  if r.status <> 'approved' then raise exception 'Only an approved report is versioned'; end if;
  if not (r.owner_id = auth.uid() or rp_can_review(rid)) then raise exception 'Not allowed'; end if;
  update report_instances set is_current = false, status = 'superseded' where id = rid;
  insert into report_instances (template, org_unit_id, owner_id, network, period_start, period_end, due_on,
                                version, supersedes, snapshot, answers, evidence, is_nil, nil_reason, linked_meeting, linked_event,
                                first_submitted_at)
  values (r.template, r.org_unit_id, r.owner_id, r.network, r.period_start, r.period_end, r.due_on,
          r.version + 1, r.id, r.snapshot, r.answers, r.evidence, r.is_nil, r.nil_reason, r.linked_meeting, r.linked_event,
          r.first_submitted_at)
  returning id into nid;
  insert into report_reviews (report_id, actor_id, action, version, note) values (nid, auth.uid(), 'version', r.version + 1, 'Correction of ' || r.report_no);
  return nid;
end; $$;
revoke execute on function public.report_new_version(uuid) from anon;

alter table public.tasks add column if not exists source_report_id uuid references public.report_instances(id) on delete set null;

-- ---------------------------------------------------------------------------
-- 10 ▸ DASHBOARDS (§25)
-- ---------------------------------------------------------------------------
create or replace function public.reporting_dashboard()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare me uuid := auth.uid(); ru record; net public.network_code; pr record; mine jsonb; sup jsonb; lists jsonb;
begin
  select * into ru from report_unit_for(me);
  select network into net from profiles where id = me;
  select * into pr from report_period('monthly_leadership', (current_date - interval '1 month')::date);
  select jsonb_build_object(
    'unit_id', ru.org_unit_id, 'unit', (select name from org_units where id = ru.org_unit_id),
    'role', ru.role, 'can_submit', ru.can_submit,
    'due', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'report_no', r.report_no, 'template', r.template,
              'period_start', r.period_start, 'due_on', r.due_on, 'status', r.status,
              'overdue', r.due_on < current_date and r.status in ('draft', 'returned')) order by r.due_on), '[]'::jsonb)
             from report_instances r where r.org_unit_id = ru.org_unit_id and r.is_current and r.status in ('draft', 'returned')),
    'monthly_expected', ru.org_unit_id is not null,
    'monthly_period', jsonb_build_object('start', pr.period_start, 'end', pr.period_end, 'due', pr.due_on),
    'monthly_status', (select r.status from report_instances r where r.org_unit_id = ru.org_unit_id and r.template = 'monthly_leadership'
                        and r.period_start = pr.period_start and r.is_current limit 1),
    'weekly_required', case when ru.org_unit_id is null then false else weekly_pulse_required(ru.org_unit_id) end,
    'submitted_period', (select count(*) from report_instances r where r.owner_id = me and r.submitted_at >= date_trunc('month', now())),
    'approved_period', (select count(*) from report_instances r where r.owner_id = me and r.status = 'approved' and r.reviewed_at >= date_trunc('month', now())),
    'returned', (select count(*) from report_instances r where r.org_unit_id = ru.org_unit_id and r.status = 'returned' and r.is_current),
    'on_time_rate', (select case when count(*) = 0 then null else round(100.0 * count(*) filter (where first_submitted_at::date <= due_on) / count(*)) end
                      from report_instances r where r.org_unit_id = ru.org_unit_id and r.first_submitted_at is not null and r.template = 'monthly_leadership'),
    'open_issues', (select count(*) from issues i where (i.profile_id = me or i.owner_id = me) and i.status in ('open', 'in_progress', 'awaiting_decision')),
    'tasks', (select jsonb_build_object('open', count(*) filter (where status in ('not_started', 'in_progress', 'awaiting_review')),
                'overdue', count(*) filter (where status in ('not_started', 'in_progress', 'awaiting_review') and due_on < current_date),
                'completed', count(*) filter (where status = 'completed')) from tasks where assigned_to = me))
    into mine;

  -- supervisor view: direct reporting units of my seat (or all countries for HQ)
  with direct as (
    select o.id, o.name, o.level from org_units o
     where (ru.org_unit_id is not null and o.parent_id = ru.org_unit_id)
        or (ru.org_unit_id is null and is_case_hq() and o.level = 'country')),
  st as (
    select d.*, exists (select 1 from role_assignments ra join position_master pm on pm.role = ra.role join profiles hp on hp.id = ra.profile_id
                         where ra.org_unit_id = d.id and ra.ends_at is null and hp.network = net) as has_leader,
           (select r from report_instances r where r.org_unit_id = d.id and r.template = 'monthly_leadership' and r.network = net
              and r.period_start = pr.period_start and r.is_current limit 1) as rep
      from direct d)
  select jsonb_build_object(
    'units', count(*), 'expected', count(*) filter (where has_leader),
    'submitted', count(*) filter (where (rep).status in ('submitted', 'under_review', 'approved', 'escalated', 'closed')),
    'approved', count(*) filter (where (rep).status = 'approved'),
    'awaiting_review', count(*) filter (where (rep).status in ('submitted', 'under_review')),
    'returned', count(*) filter (where (rep).status = 'returned'),
    'overdue', count(*) filter (where has_leader and ((rep).id is null or (rep).status in ('draft', 'returned')) and pr.due_on < current_date),
    'units_list', coalesce(jsonb_agg(jsonb_build_object('unit_id', id, 'unit', name, 'level', level, 'has_leader', has_leader,
                     'status', coalesce((rep).status::text, case when has_leader then 'not_started' else 'no_leader' end),
                     'report_id', (rep).id, 'report_no', (rep).report_no, 'submitted_at', (rep).submitted_at) order by name), '[]'::jsonb))
    into sup from st;

  select jsonb_build_object(
    'review_queue', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'report_no', r.report_no, 'template', r.template,
                        'unit', o.name, 'owner', p.first_name || ' ' || p.last_name, 'submitted_at', r.submitted_at, 'period_start', r.period_start,
                        'status', r.status) order by r.submitted_at), '[]'::jsonb)
                      from report_instances r join org_units o on o.id = r.org_unit_id join profiles p on p.id = r.owner_id
                     where r.status in ('submitted', 'under_review', 'escalated') and r.is_current and rp_can_review(r.id)),
    'red_critical', (select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'issue_no', i.issue_no, 'title', i.title, 'severity', i.severity,
                        'status', i.status, 'unit', o.name, 'due_on', i.due_on, 'created_at', i.created_at) order by i.severity desc, i.created_at), '[]'::jsonb)
                      from issues i left join org_units o on o.id = i.org_unit_id
                     where i.status in ('open', 'in_progress', 'awaiting_decision') and i.severity in ('red', 'critical')
                       and (is_case_hq() or i.org_unit_id in (select administered_units()))),
    'vacancies', (select count(*) from org_units s join position_master pm on pm.level = s.level
                   where s.id in (select administered_units()) and s.level <> 'headquarters' and pm.rank = 1
                     and not exists (select 1 from role_assignments r join profiles hp on hp.id = r.profile_id
                                      where r.org_unit_id = s.id and r.role = pm.role and r.ends_at is null and hp.network = net)),
    'overdue_actions', (select count(*) from tasks t where t.org_unit_id in (select administered_units())
                         and t.status in ('not_started', 'in_progress', 'awaiting_review') and t.due_on < current_date),
    'evidence_gaps', (select count(*) from report_instances r where r.template = 'activity_report' and jsonb_array_length(r.evidence) = 0
                       and r.status in ('submitted', 'under_review') and rp_can_review(r.id)))
    into lists;
  return jsonb_build_object('me', mine, 'supervisor', sup) || lists || jsonb_build_object('generated_at', now());
end; $$;
revoke execute on function public.reporting_dashboard() from anon;

-- Compliance table (§25.3, §29): units under a root, current or given period
create or replace function public.reporting_compliance(p_root uuid default null, p_period date default null, p_net text default 'WGMN')
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare net public.network_code := upper(p_net)::public.network_code; pr record; root uuid := p_root;
begin
  if root is null then select org_unit_id into root from report_unit_for(auth.uid()); end if;
  if root is null and not is_case_hq() then raise exception 'Not allowed'; end if;
  if not (is_case_hq() or root in (select administered_units())) then raise exception 'Not allowed'; end if;
  select * into pr from report_period('monthly_leadership', coalesce(p_period, (current_date - interval '1 month')::date));
  return (
    with units as (
      select o.id, o.name, o.level, o.parent_id from org_units o
       where (root is null and o.level = 'country') or (root is not null and o.parent_id = root)),
    st as (
      select u.*,
        (select p.first_name || ' ' || p.last_name from role_assignments ra join position_master pm on pm.role = ra.role join profiles p on p.id = ra.profile_id
          where ra.org_unit_id = u.id and ra.ends_at is null and p.network = net order by pm.rank limit 1) as leader,
        (select r from report_instances r where r.org_unit_id = u.id and r.template = 'monthly_leadership' and r.network = net
           and r.period_start = pr.period_start and r.is_current limit 1) as rep,
        (select count(*) from org_units c where c.parent_id = u.id) as children
      from units u)
    select jsonb_build_object(
      'period', jsonb_build_object('start', pr.period_start, 'end', pr.period_end, 'due', pr.due_on),
      'expected', count(*) filter (where leader is not null),
      'submitted', count(*) filter (where (rep).status in ('submitted', 'under_review', 'approved', 'escalated', 'closed')),
      'on_time', count(*) filter (where (rep).first_submitted_at is not null and (rep).first_submitted_at::date <= (rep).due_on),
      'approved', count(*) filter (where (rep).status = 'approved'),
      'overdue', count(*) filter (where leader is not null and ((rep).id is null or (rep).status in ('draft', 'returned')) and pr.due_on < current_date),
      'rows', coalesce(jsonb_agg(jsonb_build_object('unit_id', id, 'unit', name, 'level', level, 'leader', leader, 'children', children,
                 'status', coalesce((rep).status::text, case when leader is null then 'no_leader' else 'not_started' end),
                 'report_id', (rep).id, 'report_no', (rep).report_no, 'submitted_at', (rep).first_submitted_at,
                 'on_time', (rep).first_submitted_at is not null and (rep).first_submitted_at::date <= (rep).due_on,
                 'evidence', case when (rep).id is null then null else jsonb_array_length((rep).evidence) end) order by name), '[]'::jsonb))
    from st);
end; $$;
revoke execute on function public.reporting_compliance(uuid, date, text) from anon;

-- My reports / supervised / archive lists
create or replace function public.reporting_list(scope text default 'mine', p_status text default null, p_limit int default 100)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare me uuid := auth.uid(); ru record;
begin
  select * into ru from report_unit_for(me);
  return (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'report_no', r.report_no, 'template', r.template,
            'unit', o.name, 'owner', p.first_name || ' ' || p.last_name, 'period_start', r.period_start, 'period_end', r.period_end,
            'due_on', r.due_on, 'status', r.status, 'version', r.version, 'is_current', r.is_current,
            'submitted_at', r.submitted_at, 'reviewed_at', r.reviewed_at, 'evidence', jsonb_array_length(r.evidence))
            order by r.period_start desc, r.created_at desc), '[]'::jsonb)
    from (select * from report_instances r0
           where (scope = 'mine' and (r0.owner_id = me or r0.org_unit_id = ru.org_unit_id))
              or (scope = 'supervise' and rp_can_review(r0.id) and r0.org_unit_id <> coalesce(ru.org_unit_id, '00000000-0000-0000-0000-000000000000'))
              or (scope = 'archive' and rp_can_see(r0.id) and r0.status in ('approved', 'superseded', 'closed'))
           order by r0.period_start desc, r0.created_at desc limit p_limit) r
    join org_units o on o.id = r.org_unit_id join profiles p on p.id = r.owner_id
   where p_status is null or r.status::text = p_status);
end; $$;
revoke execute on function public.reporting_list(text, text, int) from anon;

-- ---------------------------------------------------------------------------
-- 11 ▸ REMINDERS & ESCALATION (§24) — configurable, idempotent, daily
-- ---------------------------------------------------------------------------
create or replace function public.reporting_reminders_run()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  pr record; d int; sent int := 0; esc int := 0; r record; key text; sup uuid;
  rep report_instances%rowtype;
  before_days int[] := array(select (jsonb_array_elements_text(coalesce(rcfg('reminder_days_before'), '[7,3,0]')))::int);
  over_days int[] := array(select (jsonb_array_elements_text(coalesce(rcfg('overdue_days'), '[1,3,7]')))::int);
  sup_day int := coalesce((rcfg('supervisor_alert_overdue_day'))::int, 3);
  esc_day int := coalesce((rcfg('escalate_overdue_day'))::int, 7);
begin
  select * into pr from report_period('monthly_leadership', (current_date - interval '1 month')::date);
  -- every unit with a seated principal leader is expected to report (§22 vacancy-aware)
  for r in
    select s.id as unit_id, s.name, ra.profile_id as leader, hp.network,
           (select ri from report_instances ri where ri.org_unit_id = s.id and ri.template = 'monthly_leadership'
              and ri.network = hp.network and ri.period_start = pr.period_start and ri.is_current limit 1) as rep
      from org_units s
      join role_assignments ra on ra.org_unit_id = s.id and ra.ends_at is null
      join position_master pm on pm.role = ra.role and pm.rank = 1
      join profiles hp on hp.id = ra.profile_id
     where s.level <> 'headquarters'
  loop
    rep := r.rep;
    if rep.status in ('submitted', 'under_review', 'approved', 'escalated', 'closed') then continue; end if;
    d := pr.due_on - current_date;                     -- days until due (negative = overdue)
    key := null;
    if d >= 0 and d = any(before_days) then key := 'before_' || d;
    elsif d < 0 and (-d) = any(over_days) then key := 'overdue_' || (-d);
    end if;
    if key is null then continue; end if;
    -- ensure the instance exists so reminders and dashboards share one record
    if rep.id is null then
      insert into report_instances (template, org_unit_id, owner_id, network, period_start, period_end, due_on)
      values ('monthly_leadership', r.unit_id, r.leader, r.network, pr.period_start, pr.period_end, pr.due_on)
      on conflict do nothing;
      select ri.* into rep from report_instances ri where ri.org_unit_id = r.unit_id and ri.template = 'monthly_leadership'
        and ri.network = r.network and ri.period_start = pr.period_start and ri.is_current limit 1;
    end if;
    if rep.reminders_sent ? key then continue; end if;   -- idempotent per day-key
    insert into member_notices (profile_id, kind, title, body, meta)
    values (rep.owner_id, 'report_due',
            case when d > 0 then 'Monthly report due in ' || d || ' day(s)'
                 when d = 0 then 'Monthly report due today'
                 else 'Monthly report overdue by ' || (-d) || ' day(s)' end,
            r.name || ' · ' || to_char(pr.period_start, 'Month YYYY') || ' · due ' || to_char(pr.due_on, 'DD Mon'),
            jsonb_build_object('report_id', rep.id, 'href', '#/reporting/report/' || rep.id));
    sent := sent + 1;
    if d < 0 and (-d) >= sup_day then
      sup := report_supervisor(r.unit_id, r.network);
      if sup is not null then
        insert into member_notices (profile_id, kind, title, body, meta)
        values (sup, 'report_overdue', 'Overdue monthly report: ' || r.name,
                'Overdue by ' || (-d) || ' day(s). Leader: ' || (select first_name || ' ' || last_name from profiles where id = rep.owner_id),
                jsonb_build_object('report_id', rep.id, 'href', '#/reporting/compliance'));
      end if;
    end if;
    update report_instances set reminders_sent = reminders_sent || jsonb_build_array(key),
           escalation_level = greatest(escalation_level, case when d < 0 and (-d) >= esc_day then 2 when d < 0 and (-d) >= sup_day then 1 else 0 end)
     where id = rep.id;
    if d < 0 and (-d) >= esc_day then esc := esc + 1; end if;
  end loop;
  return jsonb_build_object('period', pr.period_start, 'due', pr.due_on, 'notices', sent, 'escalated', esc, 'ran_at', now());
end; $$;
revoke execute on function public.reporting_reminders_run() from anon;

do $$
begin
  begin
    create extension if not exists pg_cron;
  exception when others then null;
  end;
  begin
    perform cron.unschedule('wdos-reporting-reminders');
  exception when others then null;
  end;
  begin
    perform cron.schedule('wdos-reporting-reminders', '30 6 * * *', 'select public.reporting_reminders_run()');
  exception when others then
    raise notice 'pg_cron unavailable: run reporting_reminders_run() from Reporting → Compliance → Run reminders';
  end;
end $$;

-- ---------------------------------------------------------------------------
-- 12 ▸ EVIDENCE BUCKET (private; evidence follows the report's security)
-- ---------------------------------------------------------------------------
create or replace function public.safe_uuid(t text) returns uuid
language plpgsql immutable as $$
begin
  return t::uuid;
exception when others then
  return null;
end; $$;
insert into storage.buckets (id, name, public) values ('report-evidence', 'report-evidence', false)
on conflict (id) do nothing;
drop policy if exists report_evidence_read on storage.objects;
create policy report_evidence_read on storage.objects for select to authenticated
  using (bucket_id = 'report-evidence'
         and public.rp_can_see(public.safe_uuid(split_part(name, '/', 1))));
drop policy if exists report_evidence_write on storage.objects;
create policy report_evidence_write on storage.objects for insert to authenticated
  with check (bucket_id = 'report-evidence'
              and public.rp_can_see(public.safe_uuid(split_part(name, '/', 1))));

insert into public.schema_migrations (version, name)
values (107, 'reporting_accountability') on conflict (version) do nothing;
