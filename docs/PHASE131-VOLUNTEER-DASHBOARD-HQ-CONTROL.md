# PHASE 131 - Volunteer Dashboard, Leader Hierarchy, HQ Account Control
Build v66.0 · db 103 · 5 Sep 2026

## What this phase delivers

1. **The Volunteer Dashboard** (the UI Azeez supplied, built as ONE role-based
   dashboard for WGMN and WNNN). Every member and every volunteer leader
   lands on it at #/ after sign-in. HQ staff and HQ role holders keep the
   central management dashboard. The same shell dresses #/tasks, #/meetings,
   #/announcements, #/messages and #/room for volunteers, so the whole
   experience looks like the mockup.

   Home: welcome band (photo, name, Volunteer ID, status, network, country,
   state/region, LGA/district, chapter where one exists, date joined, network
   quote), eight stat cards (status, learning %, tasks, upcoming meetings,
   participation, impact, announcements, support), then My Learning, My
   Tasks, My Network (line + coordinator + Message Coordinator), Upcoming
   Meetings (View Details / Join Meeting), Latest Announcements, My Impact,
   Quick Actions, My Achievements, and for leaders a My Leadership summary.

   Menu: Home · My Profile · My Network · My Leadership (leaders) · My
   Learning · My Tasks · Meetings & Activities · Meeting Room · Announcements ·
   My Impact · Referrals · Leadership Vacancies (recruitment module) ·
   Reports (module) · My Documents · My Calendar · Messages · Support ·
   Safeguarding · Settings · Log Out.

2. **My Leadership** for anyone holding a seat: seats below her, filled /
   vacant, members in scope, active members, and the live hierarchy tree
   with the founder's colour code (green = seated and seen in 30 days,
   amber = seated but not seen for 30 days, red = vacant). Message any leader
   in her subtree; "Refer a candidate" on vacant seats when she has the
   recruitment module. Scope is the seat's unit and everything below it,
   exactly as RLS already scopes her data.

3. **Referrals**: new table with the HQ-controlled ladder submitted →
   received → assigned → in progress → closed. A volunteer submits (with a
   consent confirmation) and watches the ladder; only HQ or a leader
   administering that unit can move it (set_referral_status). Safeguarding
   is deliberately NOT a referral category: it stays in the confidential
   cases channel, reachable from the permanent Safeguarding page and the
   red quick action.

4. **HQ master control** at #/accounts (HQ menu → Accounts):
   - every leader and member with login state (login active / never signed
     in / suspended / no login yet), last sign-in, last seen, seat, ID;
   - **Create login** for onboarded directory leaders who never claimed a
     login (temporary password shown ONCE, directory record linked, ID,
     role and country carried over), and **Add leader / member** for new
     people, optionally seated in the same step;
   - **View as**: any leader's or member's dashboard, read-only, with a red
     banner; every tab works; safeguarding stays hidden;
   - **Edit details**, **Role / seat** (assign or remove seats; scope
     follows), **Status** (walks only legal transitions, never through
     'removed'), **Reset password** (new temporary password shown once),
     **Change email**, **Suspend / Restore** sign-in, **Delete**.
   - No plaintext passwords are ever stored or displayed after the one
     reveal. HQ can reset at any time. Super admin accounts cannot be
     suspended or deleted from the page.

5. **Fixes riding along**: broadcast meetings (wgmn_all, wnnn_ng, all, hq)
   are now readable on #/meetings by the people they were announced to
   (the read policy had never learned the audience column from 052);
   a member can message the leaders on her own line and they can reply
   (coordinator_line); last_seen_at refreshes on any page open (at most
   every 10 minutes), closing the long-standing "last seen = boot only" gap.

## How every number is counted (nothing is estimated)

- Women Reached = beneficiaries the volunteer recorded herself (programmes).
- Community Referrals = referrals she submitted.
- Meetings Attended = attendance marked present by a leader/HQ, plus meetings
  she joined in the WDOS room (distinct meetings).
- Tasks Completed / Modules Completed = rows marked complete in WDOS.
- Months of Service = from the day her activation journey completed, else
  from account creation.
- Learning % = passed modules over total modules of WDOS courses she is
  enrolled in. WODDI Institute progress is a separate project; not counted.
- Achievements are derived from real events: orientation (journey
  completed), each module pass, each certificate, each leadership
  appointment, 3/6/12/24-month service marks.
- Participation = meetings attended + tasks completed.

## Deploy (browser only, in this order)

1. Supabase → SQL Editor → paste and run `103_volunteer_home_hq_control.sql`.
2. Supabase → Edge Functions → Deploy a new function → name it exactly
   `admin-users` → paste `supabase/functions/admin-users/index.ts` →
   Verify JWT ON → Deploy. No new secret is needed. Without it the Accounts
   page still lists and edits, but Create login / Reset password / Change
   email / Suspend / Delete show a yellow notice.
3. Unzip the package; drag the `app` folder onto BOTH Netlify sites.
4. Hard refresh; badge must read v66.0 · db 103. Phones: close the tab
   completely and reopen.

## Regina, today

Open #/accounts, find Regina, click **Role / seat**, choose Country
Representative and the unit: WODDI HQ for "all countries" (super country
representative) or Nigeria for one country. The old
PROVISION-REGINA-OKORO.sql is no longer needed for seating; it stays in
docs/ for history. Then **View as** her to see exactly what she sees.

## Honest gaps (not built in this phase)

- Community Cluster is not a level in the org tree (HQ → Country → State →
  LGA → Chapter). Adding it means a migration touching org_level and the
  seeded units; not done.
- Founder's leader-dashboard extras still to come: leadership pipeline
  funnel (referred → active), programme request workflow with HQ approval
  ladder, monthly reporting scores per state/LGA, organogram map view,
  role-personalised resource packs. The referrals ladder and the hierarchy
  tree are the foundation for the first two.
- Deleting an account that has tasks, meetings or other records attached is
  refused by the database on purpose (history protection). Suspend instead.
- "Women reached" will show 0 until beneficiaries are recorded under
  programmes; the number is real, not decorative.
- The mobile phone view (#/me) with the 14-day journey is unchanged and
  still linked from the dashboard for candidates.

## Files

- app/js/pages/home.js, app/js/pages/accounts.js,
  app/js/components/vshell.js, app/js/core/homecache.js (new)
- app/js/app.js, app/js/components/layout.js, app/js/core/db.js,
  app/assets/css/wdos.css, app/locales/en.json + fr.json (parity 0), sw.js
- supabase/migrations/103_volunteer_home_hq_control.sql
- supabase/functions/admin-users/index.ts
- Verified: 6-check SQL (paren balance, RAISE, self-compare, alias, HQ guard,
  Python simulation of the status walk), node --check on 65 modules,
  harness sweep 65/65 clean, jsdom render test 41/41 (member home + eleven
  tabs, leader home + hierarchy, HQ view-as, Accounts page).
