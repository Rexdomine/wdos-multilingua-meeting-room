# WDOS Data Dictionary
**WODDI Digital Operating System — schema reference (v3.0 guideline, technical annex)**
Generated directly from the applied migrations (001–037), so it cannot drift from the real database. Every table lives in the `public` schema with row-level security enabled; write authority follows the module matrix and the HQ/field wall described in the guideline. Answer-key and secret tables are sealed (readable by no API client).

**Tables: 55** · Reference date: 23 July 2026 · Schema version: 37

---

## org_units
The organisational tree: HQ → country → state/region → district/LGA → chapter. Every member and role hangs off a unit.

| Column | Type | Notes |
|---|---|---|
| id | uuid | PK |
| parent_id | uuid | -> org_units |
| level | public | required |
| name | text | required |
| country_iso | char(2) |  |
| is_active | boolean |  |
| created_at | timestamptz |  |
| updated_at | timestamptz |  |
| subregion_id | uuid | added later |

## profiles
One row per person (member, volunteer, or staff). Identity, contact, network, lifecycle status, language, birthday, last activity, and merge marker.

| Column | Type | Notes |
|---|---|---|
| id | uuid | PK, -> auth |
| membership_no | text | unique |
| first_name | text | required |
| last_name | text | required |
| email | text | required, unique |
| phone | text |  |
| network | public | required |
| status | public |  |
| org_unit_id | uuid | -> org_units |
| preferred_locale | text |  |
| created_at | timestamptz |  |
| updated_at | timestamptz |  |
| birth_date | date | added later |
| last_seen_at | timestamptz | added later |
| merged_into | uuid | added later |

## role_assignments
Leadership appointments — who holds which role over which unit, with start/end dates.

| Column | Type | Notes |
|---|---|---|
| id | uuid | PK |
| profile_id | uuid | -> profiles, required |
| role | public | required |
| org_unit_id | uuid | -> org_units, required |
| assigned_by | uuid | -> profiles |
| starts_at | timestamptz |  |
| ends_at | timestamptz |  |
| created_at | timestamptz |  |

## audit_log
Append-only trail of every insert/update/delete on audited tables, with actor, old/new values, and the stated reason.

| Column | Type | Notes |
|---|---|---|
| id | bigint | PK |
| occurred_at | timestamptz |  |
| actor_id | uuid |  |
| action | text | required |
| table_name | text | required |
| record_id | text | required |
| old_values | jsonb |  |
| new_values | jsonb |  |
| reason | text |  |

## applications
Membership applications and their journey through the recruitment pipeline (submitted → decided).

| Column | Type | Notes |
|---|---|---|
| id | uuid | PK |
| first_name | text | required |
| last_name | text | required |
| email | text | required |
| phone | text |  |
| network | public | required |
| org_unit_id | uuid | -> org_units, required |
| motivation | text | required |
| preferred_locale | text |  |
| status | public |  |
| reviewer_id | uuid | -> profiles |
| reviewer_notes | text |  |
| recommended_at | timestamptz |  |
| decided_by | uuid | -> profiles |
| decision_reason | text |  |
| decided_at | timestamptz |  |
| profile_id | uuid | -> profiles |
| created_at | timestamptz |  |
| updated_at | timestamptz |  |

## tasks
Work items: who assigned, who owns, status, due date, review flow.

| Column | Type | Notes |
|---|---|---|
| id | uuid | PK |
| title | text | required |
| details | text |  |
| org_unit_id | uuid | -> org_units, required |
| assigned_to | uuid | -> profiles, required |
| assigned_by | uuid | -> profiles |
| priority | public |  |
| status | public |  |
| requires_approval | boolean |  |
| due_on | date |  |
| completed_at | timestamptz |  |
| created_at | timestamptz |  |
| updated_at | timestamptz |  |

## meetings
Meetings: schedule, mode, location or join-link, agenda, minutes, status.

| Column | Type | Notes |
|---|---|---|
| id | uuid | PK |
| title | text | required |
| agenda | text |  |
| org_unit_id | uuid | -> org_units, required |
| organiser | uuid | -> profiles |
| mode | public |  |
| location | text |  |
| starts_at | timestamptz | required |
| ends_at | timestamptz | required |
| status | public |  |
| minutes | text |  |
| created_at | timestamptz |  |
| updated_at | timestamptz |  |

## meeting_attendance
Per-person attendance marks for each meeting.

| Column | Type | Notes |
|---|---|---|
| id | uuid | PK |
| meeting_id | uuid | -> meetings, required |
| profile_id | uuid | -> profiles, required |
| present | boolean | required |
| recorded_by | uuid | -> profiles |
| recorded_at | timestamptz |  |

## announcements
Broadcasts to the organisation.

| Column | Type | Notes |
|---|---|---|
| id | uuid | PK |
| title | text | required |
| body | text | required |
| org_unit_id | uuid | -> org_units, required |
| network | public |  |
| priority | public |  |
| author_id | uuid | -> profiles |
| created_at | timestamptz |  |
| updated_at | timestamptz |  |

## announcement_reads
Who has read which announcement.

| Column | Type | Notes |
|---|---|---|
| announcement_id | uuid | -> announcements, required |
| profile_id | uuid | -> profiles, required |
| read_at | timestamptz |  |

## module_access
The per-role module matrix HQ edits in Settings — which role sees which module.

| Column | Type | Notes |
|---|---|---|
| role | public | required |
| module | text | required |

## schema_migrations
Which numbered migrations have been applied; powers the Settings health card.

| Column | Type | Notes |
|---|---|---|
| version | int | PK |
| name | text | required |
| applied_at | timestamptz |  |

## programmes
WODDI programmes (WGMN, WNNN…): the umbrella initiatives.

| Column | Type | Notes |
|---|---|---|
| id | uuid | PK |
| code | text | required, unique |
| name | text | required |
| description | text |  |
| network | public |  |
| is_active | boolean |  |
| created_at | timestamptz |  |
| updated_at | timestamptz |  |

## programme_events
Events held under a programme.

| Column | Type | Notes |
|---|---|---|
| id | uuid | PK |
| programme_id | uuid | -> programmes, required |
| org_unit_id | uuid | -> org_units, required |
| title | text | required |
| event_date | date | required |
| location | text |  |
| notes | text |  |
| created_by | uuid | -> profiles |
| created_at | timestamptz |  |
| updated_at | timestamptz |  |

## beneficiaries
People served by WODDI programmes (the beneficiary register).

| Column | Type | Notes |
|---|---|---|
| id | uuid | PK |
| full_name | text | required |
| age_band | public | required |
| org_unit_id | uuid | -> org_units, required |
| notes | text |  |
| created_by | uuid | -> profiles |
| created_at | timestamptz |  |
| updated_at | timestamptz |  |

## service_records
Individual services delivered to beneficiaries (what, when, under which event).

| Column | Type | Notes |
|---|---|---|
| id | uuid | PK |
| event_id | uuid | -> programme_events, required |
| beneficiary_id | uuid | -> beneficiaries, required |
| service | text | required |
| outcome | text |  |
| recorded_by | uuid | -> profiles |
| recorded_at | timestamptz |  |

## cases
Confidential concerns & safeguarding cases (restricted visibility).

| Column | Type | Notes |
|---|---|---|
| id | uuid | PK |
| case_no | text | unique |
| category | public | required |
| org_unit_id | uuid | -> org_units |
| subject | text | required |
| details | text | required |
| reporter_id | uuid | -> profiles |
| status | public |  |
| created_at | timestamptz |  |
| updated_at | timestamptz |  |

## case_handlers
Which staff are assigned to handle which confidential case.

| Column | Type | Notes |
|---|---|---|
| case_id | uuid | -> cases, required |
| profile_id | uuid | -> profiles, required |
| assigned_by | uuid | -> profiles |
| assigned_at | timestamptz |  |

## case_updates
Progress updates logged on a confidential case.

| Column | Type | Notes |
|---|---|---|
| id | uuid | PK |
| case_id | uuid | -> cases, required |
| author_id | uuid | -> profiles |
| note | text | required |
| visible_to_reporter | boolean |  |
| created_at | timestamptz |  |

## tickets
Internal helpdesk tickets from members and staff.

| Column | Type | Notes |
|---|---|---|
| id | uuid | PK |
| ticket_no | text | unique |
| category | public | required |
| priority | public |  |
| subject | text | required |
| details | text | required |
| requester_id | uuid | -> profiles |
| assigned_to | uuid | -> profiles |
| status | public |  |
| resolved_at | timestamptz |  |
| created_at | timestamptz |  |
| updated_at | timestamptz |  |

## ticket_messages
The conversation thread on a helpdesk ticket.

| Column | Type | Notes |
|---|---|---|
| id | uuid | PK |
| ticket_id | uuid | -> tickets, required |
| author_id | uuid | -> profiles |
| body | text | required |
| created_at | timestamptz |  |

## departments
HQ departments (Executive Office, Field & Country Operations…).

| Column | Type | Notes |
|---|---|---|
| id | uuid | PK |
| name | text | required, unique |
| is_active | boolean |  |
| created_at | timestamptz |  |
| updated_at | timestamptz |  |

## staff
The HQ staff register: placement, position title, reporting line. Placement also walls a person off from field-member views.

| Column | Type | Notes |
|---|---|---|
| profile_id | uuid | PK, -> profiles |
| department_id | uuid | -> departments, required |
| position_title | text | required |
| reports_to | uuid | -> profiles |
| is_active | boolean |  |
| created_at | timestamptz |  |
| updated_at | timestamptz |  |

## staff_reports
Staff work reports with manager review.

| Column | Type | Notes |
|---|---|---|
| id | uuid | PK |
| author_id | uuid | -> profiles |
| report_date | date | required |
| period | public |  |
| tasks_completed | text | required |
| tasks_in_progress | text |  |
| challenges | text |  |
| support_required | text |  |
| next_priorities | text |  |
| status | public |  |
| reviewer_id | uuid | -> profiles |
| reviewer_note | text |  |
| reviewed_at | timestamptz |  |
| created_at | timestamptz |  |
| updated_at | timestamptz |  |

## staff_messages
Private one-to-one staff messages (the internal inbox).

| Column | Type | Notes |
|---|---|---|
| id | uuid | PK |
| sender_id | uuid | -> profiles |
| recipient_id | uuid | -> profiles, required |
| body | text | required |
| read_at | timestamptz |  |
| created_at | timestamptz |  |
| attachment_path | text | added later |

## task_comments
Conversation on a task, with @mentions.

| Column | Type | Notes |
|---|---|---|
| id | uuid | PK |
| task_id | uuid | -> tasks, required |
| author_id | uuid | -> profiles |
| body | text | required |
| created_at | timestamptz |  |

## task_comment_mentions
Who was @mentioned in which comment (drives notifications).

| Column | Type | Notes |
|---|---|---|
| comment_id | uuid | -> task_comments, required |
| profile_id | uuid | -> profiles, required |
| created_at | timestamptz |  |

## task_templates
Reusable task blueprints.

| Column | Type | Notes |
|---|---|---|
| id | uuid | PK |
| name | text | required |
| title | text | required |
| details | text |  |
| priority | public |  |
| requires_approval | boolean |  |
| is_shared | boolean |  |
| created_by | uuid | -> profiles, required |
| default | auth |  |
| created_at | timestamptz |  |

## message_templates
The §K Message Library — approved reusable message texts in 8 languages.

| Column | Type | Notes |
|---|---|---|
| id | uuid | PK |
| code | text | required |
| locale | text |  |
| category | text | required |
| name | text | required |
| subject | text |  |
| body | text | required |
| status | public |  |
| version | int |  |
| updated_by | uuid | -> profiles |
| created_at | timestamptz |  |
| updated_at | timestamptz |  |

## activation_milestones
The generic milestone checklist for activation (leader-confirmed).

| Column | Type | Notes |
|---|---|---|
| id | uuid | PK |
| seq | int | required |
| code | text | required, unique |
| name | text | required |
| day_target | int | required |
| is_required | boolean |  |
| self_service | boolean |  |
| is_active | boolean |  |

## activation_journeys
One per new volunteer: the activation clock (start, deadline, status).

| Column | Type | Notes |
|---|---|---|
| id | uuid | PK |
| profile_id | uuid | -> profiles, required, unique |
| on | delete |  |
| status | public |  |
| started_at | timestamptz |  |
| due_at | timestamptz |  |
| extended_until | timestamptz |  |
| completed_at | timestamptz |  |
| created_at | timestamptz |  |
| updated_at | timestamptz |  |

## activation_progress
Which milestones each journey has completed.

| Column | Type | Notes |
|---|---|---|
| journey_id | uuid | -> activation_journeys, required |
| on | delete |  |
| milestone_id | uuid | -> activation_milestones, required |
| on | delete |  |
| completed_at | timestamptz |  |
| completed_by | uuid | -> profiles, required |
| default | auth |  |
| note | text |  |

## task_checklist_items
Sub-steps inside a task.

| Column | Type | Notes |
|---|---|---|
| id | uuid | PK |
| task_id | uuid | -> tasks, required |
| seq | int |  |
| label | text | required |
| done | boolean |  |
| done_by | uuid | -> profiles |
| done_at | timestamptz |  |
| created_by | uuid | -> profiles |
| created_at | timestamptz |  |

## task_files
Files attached to tasks (storage references).

| Column | Type | Notes |
|---|---|---|
| id | uuid | PK |
| task_id | uuid | -> tasks, required |
| path | text | required |
| name | text | required |
| uploaded_by | uuid | -> profiles, required |
| default | auth |  |
| created_at | timestamptz |  |

## subregions
Africa's five sub-regions grouping the country register.

| Column | Type | Notes |
|---|---|---|
| id | uuid | PK |
| code | text | required, unique |
| name | text | required |

## country_level_names
Per-country naming of organisational levels (what a 'state/region' is called locally).

| Column | Type | Notes |
|---|---|---|
| country_id | uuid | -> org_units, required |
| level | public | required |
| local_name | text | required |

## doc_folders
Folder tree for the document library.

| Column | Type | Notes |
|---|---|---|
| id | uuid | PK |
| name | text | required |
| parent_id | uuid | -> doc_folders |
| org_unit_id | uuid | -> org_units, required |
| created_by | uuid | -> profiles |
| created_at | timestamptz |  |

## documents
The document library: uploads, publication state.

| Column | Type | Notes |
|---|---|---|
| id | uuid | PK |
| folder_id | uuid | -> doc_folders, required |
| name | text | required |
| path | text | required |
| mime | text |  |
| archived | boolean |  |
| uploaded_by | uuid | -> profiles |
| created_at | timestamptz |  |

## volunteer_applications
Volunteer submissions bridged in from the Institute website form; approval copies them into the main pipeline.

| Column | Type | Notes |
|---|---|---|
| id | uuid | PK |
| full_name | text |  |
| email | text | required |
| phone | text |  |
| payload | jsonb |  |
| status | public |  |
| decided_by | uuid | -> profiles |
| decision_reason | text |  |
| created_at | timestamptz |  |

## activation_days
The 14 content days of the activation programme (title, message, gate flag). Editable in Content Studio.

| Column | Type | Notes |
|---|---|---|
| id | uuid | PK |
| day | int | required, unique |
| title | text | required |
| kind | text | required |
| intro | text |  |
| is_gate | boolean |  |
| is_active | boolean |  |

## activation_items
Questions and tasks for each activation day (no answers here — client-safe).

| Column | Type | Notes |
|---|---|---|
| id | uuid | PK |
| day | int | -> activation_days, required |
| seq | int | required |
| kind | text | required |
| prompt | text | required |
| options | jsonb |  |
| points | int |  |
| is_required | boolean |  |

## activation_keys
Sealed answer keys for activation quizzes. HQ-only; the browser can never read them.

| Column | Type | Notes |
|---|---|---|
| item_id | uuid | PK, -> activation_items |
| correct | jsonb | required |

## activation_item_responses
Each volunteer's answers, scored server-side.

| Column | Type | Notes |
|---|---|---|
| journey_id | uuid | -> activation_journeys, required |
| item_id | uuid | -> activation_items, required |
| answer | jsonb | required |
| is_correct | boolean |  |
| score | int |  |
| submitted_at | timestamptz |  |

## engagement_content
The ongoing content rhythm: 52 weekly themes, 12 monthly messages, 12 masterclass topics. Editable in Content Studio.

| Column | Type | Notes |
|---|---|---|
| id | uuid | PK |
| kind | text | required |
| period | int | required |
| title | text | required |
| focus | text |  |
| body | text |  |
| is_active | boolean |  |

## automation_rules
The IF-rules of smart automation: code, waiting period, on/off, last run.

| Column | Type | Notes |
|---|---|---|
| code | text | PK |
| threshold_days | int | required |
| is_active | boolean |  |
| last_run_at | timestamptz |  |
| last_matches | int |  |

## automation_events
Log of every automation firing (what, when, how many matches, who was told).

| Column | Type | Notes |
|---|---|---|
| id | uuid | PK |
| rule_code | text | -> automation_rules, required |
| fired_at | timestamptz |  |
| matches | int | required |
| notified | int |  |

## member_notices
The personal 'For you' feed: journey day messages, nudges, birthdays, weekly/monthly inspiration; read and emailed markers.

| Column | Type | Notes |
|---|---|---|
| id | uuid | PK |
| profile_id | uuid | -> profiles, required |
| kind | text | required |
| title | text | required |
| body | text |  |
| meta | jsonb |  |
| created_at | timestamptz |  |
| read_at | timestamptz |  |
| emailed_at | timestamptz | added later |

## courses
Certification courses (VLSE-PD, WGMN-VP…).

| Column | Type | Notes |
|---|---|---|
| id | uuid | PK |
| code | text | required, unique |
| title | text | required |
| description | text |  |
| is_active | boolean |  |

## course_modules
Modules within a course: sequence and lesson text.

| Column | Type | Notes |
|---|---|---|
| id | uuid | PK |
| course_id | uuid | -> courses, required |
| seq | int | required |
| title | text | required |
| lesson | text | required |

## course_questions
Module quiz questions (options only — client-safe).

| Column | Type | Notes |
|---|---|---|
| id | uuid | PK |
| module_id | uuid | -> course_modules, required |
| seq | int | required |
| prompt | text | required |
| options | jsonb | required |

## course_keys
Sealed answer keys for course quizzes. HQ-only.

| Column | Type | Notes |
|---|---|---|
| question_id | uuid | PK, -> course_questions |
| correct | text | required |

## course_enrollments
Who is taking which course; completion date and certificate number.

| Column | Type | Notes |
|---|---|---|
| id | uuid | PK |
| course_id | uuid | -> courses, required |
| profile_id | uuid | -> profiles, required |
| started_at | timestamptz |  |
| completed_at | timestamptz |  |
| cert_no | text | unique |

## course_module_passes
Per-module quiz results and pass state; gates the next module.

| Column | Type | Notes |
|---|---|---|
| enrollment_id | uuid | -> course_enrollments, required |
| module_id | uuid | -> course_modules, required |
| score | int |  |
| total | int |  |
| passed | boolean |  |
| completed_at | timestamptz |  |

## org_settings
Small HQ-editable configuration store (activation window days, email switches…).

| Column | Type | Notes |
|---|---|---|
| key | text | PK |
| value | jsonb | required |
| updated_at | timestamptz |  |

## email_secrets
Sealed vault for the Brevo email credentials. RLS with no read policies — unreadable via the API.

| Column | Type | Notes |
|---|---|---|
| key | text | PK |
| value | text | required |
| updated_at | timestamptz |  |
