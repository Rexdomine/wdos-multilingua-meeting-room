-- ============================================================================
-- WDOS Migration 023 — Message & Response Library (FRD §K)
-- The configurable library of approved messages. Every template: HQ-edited,
-- per-language, personalisable with tokens, draft until approved, version
-- counted on every change (full history in the audit log). Nothing sends
-- from a draft. Seeded with the complete §K catalogue as DRAFT starters —
-- WODDI's content team supplies the real voice, HQ approves.
-- Tokens: {first_name} {last_name} {role} {chapter} {network} {programme}
--         {reference}
-- ============================================================================

create type public.template_status as enum ('draft', 'approved');

create table public.message_templates (
  id         uuid primary key default gen_random_uuid(),
  code       text not null,
  locale     text not null default 'en'
    check (locale in ('en','fr','pt','ar','sw','ha','yo','ig')),
  category   text not null check (category in (
    'application','activation','membership','service','events','meetings',
    'learning','celebration','engagement','welfare','exit')),
  name       text not null check (char_length(name) between 3 and 120),
  subject    text check (subject is null or char_length(subject) <= 200),
  body       text not null check (char_length(body) between 3 and 4000),
  status     public.template_status not null default 'draft',
  version    int not null default 1,
  updated_by uuid references public.profiles(id) default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (code, locale)
);

create trigger message_templates_touch before update on public.message_templates
  for each row execute function public.touch_updated_at();
create trigger message_templates_audit after insert or update or delete
  on public.message_templates for each row execute function public.audit_row();

-- Any change to the words resets approval and counts a version.
create or replace function public.template_version_guard()
returns trigger language plpgsql as $$
begin
  if new.body is distinct from old.body
     or new.subject is distinct from old.subject
     or new.name is distinct from old.name then
    new.version := old.version + 1;
    new.status := 'draft';
  end if;
  return new;
end; $$;

create trigger message_templates_version before update
  on public.message_templates
  for each row execute function public.template_version_guard();

alter table public.message_templates enable row level security;

create policy templates_hq on public.message_templates
  for all to authenticated
  using (public.is_case_hq())
  with check (public.is_case_hq());

-- ---------------------------------------------------------------------------
-- Seed: the complete §K catalogue (English, DRAFT starters)
-- ---------------------------------------------------------------------------
insert into public.message_templates (code, category, name, subject, body) values
 ('application_received','application','Application received','We received your application','Dear {first_name}, thank you for applying to WODDI. Your application ({reference}) has been received and will be reviewed.'),
 ('application_incomplete','application','Incomplete application','Complete your WODDI application','Dear {first_name}, your application is not yet complete. Please finish the remaining details so we can review it.'),
 ('additional_info_required','application','Additional information required','A little more information needed','Dear {first_name}, to continue reviewing your application ({reference}) we need some additional information from you.'),
 ('application_under_review','application','Application under review','Your application is under review','Dear {first_name}, your application ({reference}) is now under review. We will contact you with the outcome.'),
 ('interview_invitation','application','Interview invitation','Invitation to interview','Dear {first_name}, we would like to invite you to an interview as part of your WODDI application.'),
 ('provisional_approval','application','Provisional approval','Welcome — provisional approval','Congratulations {first_name}! Your application has been provisionally approved. Your activation journey begins now.'),
 ('application_unsuccessful','application','Application unsuccessful','About your WODDI application','Dear {first_name}, thank you for your interest in WODDI. On this occasion your application was not successful. We warmly encourage you to stay connected.'),
 ('activation_commenced','activation','Activation commenced','Your activation journey has begun','Dear {first_name}, your 14-day activation journey has commenced. Complete each step to become an active leader.'),
 ('activation_task_assigned','activation','Activation task assigned','A new activation step','Dear {first_name}, a new activation task has been assigned to you: please review and complete it.'),
 ('activation_milestone_completed','activation','Activation milestone completed','Milestone completed — well done','Well done {first_name}! You have completed another activation milestone. Keep going.'),
 ('activation_reminder','activation','Activation reminder','Your activation is waiting','Dear {first_name}, some activation steps are still outstanding. Please complete them to stay on track.'),
 ('activation_extension','activation','Activation extension','Your activation period was extended','Dear {first_name}, your activation period has been extended. Please use the additional time to complete the remaining steps.'),
 ('activation_completed','activation','Activation completed','Activation completed','Congratulations {first_name}! You have completed your activation journey.'),
 ('appointment_confirmed','activation','Appointment confirmed','Your appointment is confirmed','Dear {first_name}, your appointment as {role} is confirmed. Welcome to WODDI leadership.'),
 ('welcome_to_unit','activation','Welcome to a unit or programme','Welcome to {chapter}','Dear {first_name}, welcome to {chapter} in the {network} network. We are glad to have you.'),
 ('supervisor_introduction','activation','Supervisor introduction','Meet your coordinating leader','Dear {first_name}, your coordinating leader will guide your first steps. Please reach out and introduce yourself.'),
 ('membership_activated','membership','Membership activated','Your membership is active','Dear {first_name}, your WODDI membership is now active. Welcome!'),
 ('volunteer_activated','membership','Volunteer activated','You are now an active volunteer','Dear {first_name}, you are now an active WODDI volunteer. Thank you for choosing to serve.'),
 ('welcome_to_woddi','membership','Welcome to WODDI','Welcome to WODDI','Dear {first_name}, welcome to the Women of Divine Destiny Initiative. Together we build, nurture and inspire.'),
 ('assignment_notification','service','Assignment notification','A new assignment for you','Dear {first_name}, a new assignment has been given to you. Please review the details and confirm your acceptance.'),
 ('assignment_accepted','service','Assignment accepted','Assignment accepted','Thank you {first_name}, your acceptance of the assignment has been recorded.'),
 ('assignment_reminder','service','Assignment reminder','Assignment deadline approaching','Dear {first_name}, a friendly reminder that your assignment is due soon.'),
 ('assignment_completed','service','Assignment completed','Assignment completed','Well done {first_name}! Your assignment has been recorded as completed.'),
 ('appreciation_for_service','service','Appreciation for service','Thank you for serving','Dear {first_name}, thank you for your service to WODDI. Your contribution makes a real difference.'),
 ('event_registration_confirmation','events','Event registration confirmation','You are registered','Dear {first_name}, your registration has been confirmed. We look forward to seeing you.'),
 ('event_reminder','events','Event reminder','Event reminder','Dear {first_name}, this is a reminder of your upcoming WODDI event.'),
 ('event_attendance_appreciation','events','Event attendance appreciation','Thank you for attending','Dear {first_name}, thank you for attending. Your presence made the event richer.'),
 ('meeting_invitation','meetings','Meeting invitation','Meeting invitation','Dear {first_name}, you are invited to a meeting. Please review the agenda and confirm your attendance.'),
 ('meeting_reminder','meetings','Meeting reminder','Meeting reminder','Dear {first_name}, a reminder of your upcoming meeting.'),
 ('meeting_attendance_appreciation','meetings','Meeting attendance appreciation','Thank you for participating','Dear {first_name}, thank you for participating in the meeting.'),
 ('course_enrolment','learning','Course enrolment','You are enrolled','Dear {first_name}, you have been enrolled in a course at the WODDI Institute.'),
 ('training_reminder','learning','Training reminder','Your training is waiting','Dear {first_name}, you have outstanding training to complete. Please continue your learning journey.'),
 ('module_completion','learning','Module completion','Module completed','Well done {first_name}! You have completed another module.'),
 ('course_completion','learning','Course completion','Course completed — congratulations','Congratulations {first_name}! You have completed your course.'),
 ('certificate_issued','learning','Certificate issued','Your certificate is ready','Dear {first_name}, your certificate has been issued. Congratulations on this achievement.'),
 ('birthday_greeting','celebration','Birthday greeting','Happy birthday, {first_name}!','Happy birthday {first_name}! The whole WODDI family celebrates you today.'),
 ('anniversary_greeting','celebration','Anniversary greeting','Happy service anniversary','Dear {first_name}, happy anniversary of your service with WODDI. Thank you for every year.'),
 ('service_milestone','celebration','Service milestone','Celebrating your milestone','Dear {first_name}, congratulations on reaching a service milestone with WODDI.'),
 ('volunteer_spotlight','celebration','Volunteer spotlight','Volunteer spotlight','This spotlight celebrates {first_name} for outstanding volunteer service.'),
 ('leadership_recognition','celebration','Leadership recognition','Recognising your leadership','Dear {first_name}, your leadership has been recognised. Thank you for the example you set.'),
 ('weekly_inspiration','engagement','Weekly inspirational message','Your weekly inspiration','Dear {first_name}, here is your weekly word of inspiration from WODDI.'),
 ('monthly_motivation','engagement','Monthly motivational message','Your monthly encouragement','Dear {first_name}, here is your monthly encouragement from the WODDI family.'),
 ('personal_development','engagement','Personal development message','Growing together','Dear {first_name}, this month''s personal development focus is enclosed. Keep growing.'),
 ('leadership_development','engagement','Leadership development message','Leadership growth','Dear {first_name}, here is this period''s leadership development content.'),
 ('founders_message','engagement','Founder''s message','A message from the Founder','Dear {first_name}, a personal message from the Founder of WODDI.'),
 ('executive_update','engagement','Executive update','Executive update','Dear {first_name}, an update from WODDI''s executive leadership.'),
 ('programme_announcement','engagement','Programme announcement','Programme announcement','Dear {first_name}, an announcement regarding the {programme} programme.'),
 ('welfare_acknowledgement','welfare','Welfare acknowledgement','We received your request','Dear {first_name}, your welfare request has been received ({reference}). Someone will follow up with you.'),
 ('prayer_request_acknowledgement','welfare','Prayer request acknowledgement','Your request has been received','Dear {first_name}, your prayer request has been received and is being held with care.'),
 ('complaint_acknowledgement','welfare','Complaint acknowledgement','We received your complaint','Dear {first_name}, your complaint ({reference}) has been received and will be handled confidentially.'),
 ('feedback_acknowledgement','welfare','Feedback acknowledgement','Thank you for your feedback','Dear {first_name}, thank you for your feedback. It has been recorded.'),
 ('support_ticket_update','welfare','Support ticket update','Update on your ticket','Dear {first_name}, there is an update on your support ticket ({reference}).'),
 ('resolution_notification','welfare','Resolution notification','Your matter has been resolved','Dear {first_name}, your matter ({reference}) has been resolved. Please tell us how we did.'),
 ('exit_appreciation','exit','Exit appreciation','Thank you for your service','Dear {first_name}, thank you for the service you have given to WODDI. Our door remains open to you.'),
 ('reactivation_invitation','exit','Reactivation invitation','We would love to have you back','Dear {first_name}, we would be delighted to welcome you back to active service with WODDI.'),
 ('welcome_back','exit','Welcome-back message','Welcome back!','Dear {first_name}, welcome back to WODDI! We are so glad you have returned.')
on conflict (code, locale) do nothing;

-- ---------------------------------------------------------------------------
-- Module registration ('library' — HQ only)
-- ---------------------------------------------------------------------------
alter table public.module_access drop constraint module_access_module_check;
alter table public.module_access add constraint module_access_module_check
  check (module in (
    'members','recruitment','organisation','tasks','meetings','reports',
    'announcements','settings','programmes','cases','helpdesk','hq','library'
  ));

insert into public.module_access (role, module) values
  ('super_admin','library'), ('executive_director','library'),
  ('hq_team','library')
on conflict do nothing;

insert into public.schema_migrations (version, name)
values (23, 'message_library') on conflict (version) do nothing;
