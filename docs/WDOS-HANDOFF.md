# WDOS HANDOFF (living document) - regenerated 5 Sep 2026

How to use: at the start of any new chat, upload THIS file and the newest
WDOS zip named below. The new chat then has the complete state, not a
summary. Ask for a fresh copy of this file at every milestone ("update the
handoff") so it never goes stale.

## 1. Who and what

- Azeez Olayinka, IT Lead at WODDI (pan-African women's non-profit, HQ
  Nigeria, est. 2008; networks WGMN = Good Mother Network, ages 30+, and
  WNNN = Nurture NextGen Network, ages 18-29). Founder addressed as "Her
  Excellency" (H.E.) in documents.
- WDOS = WODDI Digital Operating System, the organisation's platform.
  Live at woddicrm.org (Netlify sites woddicrm.netlify.app and
  woddiwdos.netlify.app, both must be deployed every time).
- Stack (mandated): HTML5/CSS3/vanilla JS ES modules, NO frameworks, no
  build tools. Supabase (Postgres, Auth, RLS, Edge Functions, Realtime,
  Storage). Netlify hosting. Brevo email (~300/day free cap). Brand:
  magenta #D4006A, lemon #7CB518, motto "No Woman Is Left Out".
- The WODDI Institute app is a SEPARATE Supabase project. Never mix them.

## 2. Current live state (as of this handoff)

- App: v68.3 expected on woddicrm.org (badge "build v68.3 · db 115").
  v68.3 = migration 115: referral_overview no longer reads state_region/lga
  from applications (they carry org_unit_id only); location from the unit
  chain, position from the link. Check 9 added to the harness: every
  a.<col> reference in a migration must exist on that table.
  v68.2 = migration 114: register_reconcile/apply runnable from the SQL
  Editor (guard: no user OR HQ seat). Rule: any function meant to be run
  by IT in the editor must not use a bare is_case_hq() guard.
  v68.1 = Phase 137: WGMN Master Register (06 Sep) loaded as staging
  (leader_register), register_reconcile() name matching within country,
  register_apply() adds missing unflagged names to leader_directory;
  country flags as bundled SVGs (assets/flags) on welcome band, header,
  Accounts rows. See docs/PHASE137-REGISTER-RECONCILE-FLAGS.md.
  v68.0 = Phase 136 Referral Links (migration 112): referral_links,
  referral_visits, referral_code on applications/profiles, public #/r/CODE
  landing, HQ page #/reflinks, leader tab #/my/reflinks (link per vacant
  seat by position/location/network + membership link), doors stamp the
  stored code after submission. See docs/PHASE136-REFERRAL-LINKS.md.
  v67.4 = Phase 135b: appointment acceptance (leader accepts the
  Acceptance & Commitment Declaration or declines with a reason; seat
  becomes vacant on decline; existing seats marked accepted at start) and
  a tracked ten-step onboarding checklist (leader ticks; HQ sees done/total
  on Accounts with filters "Onboarding incomplete" and "Acceptance
  pending"). Migration 111 also redefines volunteer_home and
  hq_account_list so roles carry accepted_at/declined_at.
  docs/WDOS-Functional-Verification-Self-Assessment.pdf = honest 34-section
  PASS/PARTIAL/FAIL sheet against the Admin Secretary guide (17/15/2).
  v67.3 = migration 110: Accounts list cap applied to members with logins
  only, so directory leaders awaiting a login are always shown (the 103
  version hid them once members exceeded the cap); list cap 1000.
  docs/ADD-NGUNAN-ADDINGI.sql adds Hon. Addingi to the directory (CR-NGA,
  Nigeria, WGMN) so Create login is pre-filled.
  v67.2 = Azeez's 6 Sep list: migrations 108 (RUN ALONE: org_level
  community_cluster before chapter; roles cluster_coordinator,
  assistant_cluster_coordinator) + 109 (ten-position master list, cluster
  term, network-filtered leadership tree/reports-to/direct reports,
  report_open null-date fix, position_master-driven scope functions);
  #/claim door fixed (gBtn/gHint were declared inside step2 and used in
  step1; blank card since Google button landed); welcome band = name, ID,
  full name, network, designation; Institute link + Templates & Tools
  (10 HQ templates as PDF to read + originals to download, in
  app/content/templates) in the leader menu; Leadership Structure has
  WGMN / WNNN CTAs; HQ dashboard shows live leaders total, by level, by
  country, coverage, reports, programmes and no longer shows the
  14-day journey card to HQ; labels: State Coordinator, Assistant State
  Coordinator, LGA Coordinator, ... Chapter Lead, Assistant Chapter Lead.
  Ngunan Addingi (beekasinvest@gmail.com) = CR Nigeria: steps in
  docs/ONBOARD-NGUNAN-ADDINGI.md, photo in docs/photos/.
  v67.1 = auth diagnostics: every auth event logged to localStorage
  (wdos.authlog, last 30, shown on #/doctor); a SIGNED_OUT the user did
  not click is re-checked after 800 ms and ignored if the session is
  still live; otherwise the login form shows the time, page and build of
  the automatic sign-out (auth.autoSignedOut). Open symptom 6 Sep: HQ
  account signs in, Home shell renders, then bounces to #/login; cause
  not yet proven, the log will name it.
  v67.0 = Phase 134 Reporting & Accountability (founder's Final Functional
  Specification v1.0): migration 107, page #/reporting, see
  docs/PHASE134-REPORTING-ACCOUNTABILITY.md for the spec coverage table.
  v66.6 = sign-in/Google fixes: getMyProfile() now retries briefly and
  uses maybeSingle so the profile-row race right after sign-in (Google
  most of all) no longer bounces the person to #/login or a dead screen;
  hasProfile() added; the OAuth landing guard waits for the profile row,
  not just the session, and lands on #/login?oauth=failed on provider
  error; Google redirectTo now returns to <origin>/#/ (was bare origin)
  with prompt=select_account; login page shows a Google error message.
  v66.5 = certificate footer prints woddicrm.org (was the Netlify host).
  v66.4 = Phase 135 Volunteer Leadership Structure (founder's standard):
  migrations 105 (two new positions, RUN ALONE) + 106 (appointment_status,
  level_terms per country, position_master, reports-to fix, direct reports,
  structure_explorer); page #/structure; see docs/PHASE135-LEADERSHIP-
  STRUCTURE.md.
  v66.3 = v66.2 + HQ photo control: #/accounts → Photo (upload/remove a
  leader's picture; storage policy from 016 already lets HQ roles write
  any avatar, so no migration) and photos on Leader Atlas rows.
  If the badge is lower, the newest zip was not deployed yet.
  v66.1 = Phase 133 Network Command (#/command, migration 104, see
  docs/PHASE133-NETWORK-COMMAND.md). v66.2 = v66.1 + three fixes:
  (a) accounts.js: needFn was a const declared after render() returned
  (temporal dead zone, same species as the v65.0 CONVENING bug), so
  Create login / Add leader / Reset password / Change email / Suspend /
  Delete threw silently on click; now a hoisted function; (b) home.js:
  a dashboard render finishing after the route moved to #/login no
  longer clears the page (it drew its error card over the login form
  when a session was dropped) and a not-signed-in bundle error goes to
  #/login; (c) app.js authed(): no profile = no session → #/login.
- Database: migrations 001 to 103. 103 (Phase 131) adds referrals,
  volunteer_home(pid) (one-call dashboard bundle + HQ view-as), HQ account
  RPCs (hq_account_list, hq_update_profile, hq_set_status, hq_set_role,
  hq_end_roles, hq_link_directory), audience-aware meetings_read,
  coordinator_line messaging. 104 (Phase 133) adds org_unit_ancestors,
  member_stage, network_command. Both MUST be applied (badge db 104).
- Supabase: org "WODDI Database", project ref vhudbuprjpsyizporkcn.
  Pro plan PAID 31 Aug 2026. Compute should be Micro (verify under
  Project Settings → Compute and Disk / Add-ons / Infrastructure).
- Edge Functions deployed (all must show green in Dashboard → Edge
  Functions): meeting-token, transcribe, speak, translate, push-send,
  admin-users (NEW in Phase 131: HQ creates logins, resets passwords,
  changes email, suspends, deletes; needs no new secret; Verify JWT on).
  Secrets: JAAS_APP_ID, JAAS_KID, JAAS_PRIVATE_KEY (or _B64) for the
  embedded call; GROQ_API_KEY shared by transcribe, speak, translate.
  All functions deployed via the dashboard editor with "Verify JWT" on.
- Google sign-in: Google Cloud OAuth client with redirect
  https://vhudbuprjpsyizporkcn.supabase.co/auth/v1/callback; Supabase
  Providers → Google enabled; URL configuration Site URL woddicrm.org
  plus both Netlify mirrors. The router owns the OAuth landing guard.
- Org settings (table org_settings, jsonb values) that shape behaviour:
  call_mode ('embedded' default, 'tab' = open-in-new-tab call),
  call_raw_voice ('on' lets the speaker's real voice into the call;
  default off = booth mode), tts_space (URL of the Hugging Face voice
  Space, NOT YET SET), call_domain (optional custom Jitsi domain),
  email_enabled.

## 3. Deploy ritual (novice, browser-only)

1. Run any new numbered migration in Supabase → SQL Editor (in order).
2. Unzip the newest package; drag the `app` folder onto BOTH Netlify
   sites (Deploys tab drop area).
3. Hard refresh (Ctrl+Shift+R); confirm the corner badge version.
4. Phones: close the tab completely and reopen (PWA caches cling).
5. New Edge Function? Dashboard → Edge Functions → Deploy new function
   → editor → name EXACTLY as the folder → paste the index.ts → Verify
   JWT on → Deploy.

## 4. Files that matter (keep local copies; sandboxes reset)

- wdos-v68.3-referral-fix.zip = THE authoritative app package
  (cumulative: app + supabase/migrations + supabase/functions + docs).
- woddi-voice-space.zip = Hugging Face Docker Space (app.py, Dockerfile,
  requirements.txt, README.md, test.html) giving free voices for
  fr/pt/ar/sw/ha/yo/ig. NOT yet deployed.
- PROVISION-REGINA-OKORO.sql = Regina's account script (country rep
  version; see section 7).
- 103_volunteer_home_hq_control.sql = migration 103 (applied if the
  badge shows db 103 or higher). 104_network_command.sql = migration 104.
  admin-users/index.ts = the Phase 131 Edge Function (must be deployed
  for Create login / Reset password / Change email / Suspend / Delete).
- docs/ inside the zip: PHASE124-EMBEDDED-CALL.md, PHASE127-CLOUD-EARS.md,
  PHASE128-SENTENCE-FLOW-BOOTH-VOICE.md,
  PHASE131-VOLUNTEER-DASHBOARD-HQ-CONTROL.md, PHASE133-NETWORK-COMMAND.md,
  PHASE135-LEADERSHIP-STRUCTURE.md, PHASE134-REPORTING-ACCOUNTABILITY.md,
  and this handoff.

## 5. The multilingual meeting room (how it works now)

Layers: (a) video = Jitsi as a Service (8x8.vc) embedded INSIDE the room
page via the meeting-token function (no time limit; free to 25 monthly
users, then paid); (b) interpreter lane = the page itself.

Speaking = push-to-talk with sentence flow: tap Speak once, talk
naturally; an AudioContext volume detector cuts a clip at each pause
(≥400 ms speech then ≥700 ms silence), MediaRecorder records each
sentence (works in EVERY browser: Chrome, Edge, Safari, Firefox,
phones), the clip goes to the transcribe function → Groq Whisper
(whisper-large-v3-turbo) → text → broadcast over Supabase Realtime
('cap' events) → each listener's device translates into its own
hear-language (lane order: device translator → translate function via
Groq llama-3.1-8b-instant → org AI key → MyMemory → passthrough) → voice
(device voice → speak function via Groq Orpheus for ar/en → Space voice
for the rest → text only). Booth mode: the speaker's real voice does not
enter the call; listeners hear only the interpreter, including listeners
in the speaker's own language.

Rules for a meeting: every participant sets BOTH pickers ("I speak" and
"Hear in") to their OWN language; HQ = English/English. Solo test needs
speak ≠ hear. Earphones. One person speaks at a time, in sentences. Keep
the WDOS tab in front while speaking. Chrome is no longer required
(cloud ears), but the old browser recogniser remains the fallback when
the transcribe function is unreachable.

On-screen diagnostics (read these before touching code): version badge;
grey "Cloud interpreter ready" line; chip states listening… /
understanding… with a live level bar; grey "Interpreter microphone:
<device>" line; red lines: "microphone heard nothing", "cloud interpreter
could not process", "translation fell back", "no voice for this
language", "embedded call not configured (…)"; in-room version
handshake chips naming any device on an old build.

Known limits: Groq free tier (generous for meetings, not millions);
cloud TTS ~100 requests/day (device voice packs are the unlimited path);
Yoruba/Hausa/Igbo hear-only (Whisper weak for them); the free Space
sleeps and takes ~1 min to wake (the room pings /warmup on open).

Pending in this area:
- Deploy the voice Space and set org setting tts_space (see section 9).
- Laptop microphone: Windows meter moves but the page heard nothing →
  Chrome using a different device or Windows "Let desktop apps access
  microphone" off; v64.7+ shows the device name and level bar.
- Resilience: one failed meeting-token fetch abandons the embedded call
  for the session; retry hardening offered, not yet ordered.
- Azeez's clarification still owed: "video call embedded inside their
  dashboard" = Meeting Room page (already embedded) or home Dashboard
  screen (new build)?
- Founder's seven deliverables (section 8) after the call works on her
  phone.

## 6. Membership, approval, sign-in (state)

- Two registration doors, both instant-approve since migration 100:
  #/volunteer and #/apply. Claim login at #/claim with the same email.
  Google sign-in on login + claim (Google replaces the password only; the
  forms remain the door because they carry the age question that decides
  the network).
- Age rule: WNNN 18-29, WGMN 30+ (forms derive network). Existing members
  were never retroactively reassigned (no age data).
- Activation: 14-Day Activation Journey; 75 passed (62 WGMN / 13 WNNN);
  founder's extension ended 31 Aug; WGMN go-live was 1 Sep.
- Open cosmetic bug: stray "null" above "Welcome to WODDI" on the #/claim
  success screen. Open gap: Google sign-in without prior registration
  lands as a bare profile.

## 7. Regina Okoro (the first real leader account)

- Email uchechukwuokori81@gmail.com (credentials are NOT recorded here;
  HQ can reset via Supabase → Authentication → Users → Send password
  recovery).
- Auth user EXISTS (created after migration 102). Provisioning script
  (country rep version) ends any HQ-team role, deactivates the HQ staff
  row, sets names, walks member status legally to active, and assigns
  role country_rep at a seat: v_seat = 'ALL' (seated on the HQ unit;
  countries are its direct children, so scope = every country = "Super
  Country Representative" with country-rep powers and NO HQ screens) or
  'Nigeria' (one country). Azeez's seat choice is still PENDING.
- Her #/me crashed with "Cannot access 'CONVENING' before initialization"
  (a constant declared inside render() after the page was drawn); fixed
  in v65.0 by hoisting it to module scope. Verify her #/me loads after
  deploy.
- From v66.0 seat her from #/accounts → Role / seat (country_rep at
  WODDI HQ = every country, or at Nigeria = one country); the SQL script
  is no longer needed for seating. Then "View as" shows her dashboard.
- What a country rep can do from v66.0: the Volunteer Dashboard with My
  Leadership (every seat in her subtree, filled/vacant, members in scope,
  message any leader below her, refer candidates for vacant seats),
  Tasks, Meetings, Announcements, Recruitment for her scope. Still not
  hers: the Members list module and the Leader Atlas (HQ-only), task
  assignment aimed at leaders (assignee search is staff-oriented).

## 8. Queued builds

Phase 131 BUILT in v66.0 (see docs/PHASE131-VOLUNTEER-DASHBOARD-HQ-
CONTROL.md): Volunteer Dashboard per Azeez's mockup for members and
leaders; My Leadership hierarchy tree; referrals ladder; HQ #/accounts
(create login, view as, edit, seat, status, reset password, change
email, suspend/restore, delete); last_seen_at refresh on activity.
Position held: no plaintext passwords ever (temporary password shown
once, resettable any time).

Phase 132 (founder's leader-dashboard extras, not yet ordered):
1. Leadership pipeline funnel (referred → registered → activation →
   selected → appointed → onboarding → active) per scope.
2. Programme request workflow (submit → HQ review → approved/modify/
   declined → implementation → evidence → closed).
3. Reporting & performance scores per state/LGA, monthly report due dates.
4. Organogram map view; role-personalised resource packs.
5. Task assignment to leaders in scope (assignee search).
6. Community Cluster as an org level (migration touching org_level).

Founder's Multilingual Virtual Meeting System deliverables (written
spec, 29 Aug): system architecture; one-tap user journey;
language/translation architecture; scalability/capacity plan;
load/stress test report; security/backup/failover plan; HQ operational
dashboard framework; plus an ordinary-user readiness test. Scale target:
hundreds of thousands to millions across 55 countries; leaders create
their own meetings at their level. To be written after the call works
on H.E.'s phone.

Other open items: extension email tail (send_extension_emails(120) until
remaining 0, if not already); "Completed late" verdict label; network +
contact columns in the activation export; enriched query for the 75
passed (role/country/state for the 13 recent); Brevo DKIM (sender is a
gmail address); student feedback forms tally offer; Phase 125 (JaaS
server-side transcription, needs founder's card) scoped, not built.

## 9. Voice Space deployment (browser only)

huggingface.co → New Space → name woddi-voice → SDK Docker → CPU basic
free → Create → Files → Upload the 5 files from woddi-voice-space.zip →
wait for "Running" (5-15 min first build) → open
https://<username>-woddi-voice.hf.space/test and hear each language →
then in SQL Editor:
insert into org_settings (key, value) values ('tts_space',
'"https://<username>-woddi-voice.hf.space"'::jsonb) on conflict (key) do
update set value = excluded.value;

## 10. Working rules (learned the hard way)

- Evidence first. Most "not working" reports were: undeployed build,
  cached phone, Microsoft Edge (before cloud ears), wrong picker config,
  a missing function deployment, or a network blip. Always ask for the
  badge on EVERY device and the on-screen diagnostic line before code.
- Parallel chats: Azeez sometimes runs two chats on the same workspace.
  Before editing, check the tree version and newest zip; converge to ONE
  cumulative zip; keep the established design.
- SQL: a migration that ADDS an enum value must be its own file and run
  alone (105); the next file may then use the value.
- SQL: check 8 = name collisions (harness/namecheck.py): a function, table
  or type name reused from an earlier migration fails unless the file
  marks it '-- redefines <name>'. 107 originally reused
  can_review_report from 015 and Postgres refused the parameter rename.
- SQL: check 7 = parse with the real PostgreSQL grammar (pglast, script
  /home/claude/harness/sqlcheck.py, function bodies included) before any
  migration ships; the 6-check alone missed a misplaced FROM in 106.
- SQL: 6-check verification before any migration (paren balance,
  RAISE+||, self-comparison, bare row, HQ-guard shape, Python simulation
  of the logic). Migrations are numbered; schema_migrations rows;
  EXPECTED_SCHEMA_VERSION in app/js/core/db.js must match.
- JS: node --check parses a .js file as a SCRIPT and misses module-only
  errors (a bracket error passed it in v67.0 and failed the ESM import);
  the harness sweep (real ES module import) is the check that counts.
- JS: node --check at minimum; the harness (shim.mjs + sweep.mjs, 66/66
  modules clean, static import resolution) plus the jsdom render test
  (render-test.mjs + fixtures: member home, eleven tabs, leader tree,
  view-as, Accounts page AND a click on every Accounts action) live at
  /home/claude/harness and must be rebuilt after a sandbox reset.
- Never declare a const/let after a page's return statement if any
  handler uses it: it stays in the temporal dead zone forever (CONVENING
  in v65.0, needFn in v66.1). Use function declarations for helpers.
- Documents to the founder: humanized, NO em dashes, no gendered
  pronouns except the title "Her Excellency", branded reportlab PDFs
  (magenta header band, lemon motto). Never fabricate data the system
  did not capture.
- Deployment instructions: novice level, browser only, no command line.
- Never display or store passwords. Temporary password shown once; reset
  any time.
- Dashboard numbers are counts of real rows only. If the system never
  captured something (e.g. women reached before beneficiaries are
  recorded) it shows 0, not a placeholder.

## 11. Useful SQL

- Regina check: select p.first_name, p.last_name, p.status, ra.role,
  ou.name, u.last_sign_in_at from profiles p join role_assignments ra on
  ra.profile_id = p.id and ra.ends_at is null join org_units ou on ou.id
  = ra.org_unit_id join auth.users u on u.id = p.id where lower(p.email)
  = 'uchechukwuokori81@gmail.com';
- Call mode: insert into org_settings (key, value) values ('call_mode',
  '"embedded"'::jsonb) on conflict (key) do update set value =
  excluded.value;  (use '"tab"' for the open-tab call)
- Raw voice: same shape with key call_raw_voice and value '"on"'.
- Count closed journeys: select count(*) from activation_journeys where
  status = 'incomplete';
- Referrals waiting for HQ: select ref_no, category, reason, status,
  created_at from referrals where status = 'submitted' order by created_at;
- Who has no login yet (directory only): select member_code, first_name,
  last_name, email, country from leader_directory where claimed_profile
  is null;

## 12. People

- Regina Okoro: Head of Field and Country Operations; first real leader
  account (section 7).
- Fred Ogbole: independent QA tester; GO recommendation for 1 Sep launch
  delivered 21 Aug.
- Tobi Ajayi: graphics designer (guide graphics).
- Founder (H.E.): reads reports closely, catches data discrepancies,
  issued the seven-deliverable multilingual spec.

## 13. Sandbox notes for the assistant

Working tree lives at /home/claude/wdos-v64 (or /home/claude/wdos);
restore from the newest zip if the sandbox reset (uploads at
/mnt/user-data/uploads, outputs at /mnt/user-data/outputs). The
persistent memory file /areas/wdos.md holds the full dated history and
is the source of truth if this document and the memory ever disagree
(memory is newer).
