# Phase 89 — 14-Day Activation Launch (v55.1, schema 69)

> **89b addendum — the watch-guard.** The founder video now tracks GENUINE
> watching: seconds only count while they actually play, seeking past the
> watched point snaps back (rewinding to rewatch is allowed), playback is
> locked to 1× speed, and the tick lands only at ≥95% truly seen — with a
> progress bar showing "Watched N%". Partial watches resume where they
> stopped. Migration 069 clears any tick earned under the old Confirm
> button so everyone — test accounts included — really watches.
> Deploy: run 069, then drag the app again → badge **build v55.1 · db 69**.
### Launch day: Monday 3 August 2026

What this ships:

1. **Founder's video inside WDOS.** Day 1 now plays your uploaded video
   directly (converted to a format every phone can play, 313 MB → 54 MB).
   Watching it to the end ticks the task — the volunteer never ticks it.
2. **The system ticks, not the volunteer.** Day 5 is fully
   system-verified: upload your CV (real upload button), complete a Learn
   module, check your dashboard tasks, write to HQ, explore Ask WODDI,
   open the latest announcement, download the handbook — each row ticks
   itself when WDOS *sees* the thing happen. Hand-ticking is disabled on
   those rows; each row has a button that takes them straight to the task.
3. **Content as directed.** Day 4 task 2 (the warm-and-professional
   scenario), Day 7 question ("What has been your biggest lesson so far
   in your journey as a volunteer?"), and a **Go back to dashboard**
   section inside the journey.
4. **Pass / fail / auto-approval.** The standing Day-14 rule decides:
   both checkpoints (Day 6 Safeguarding, Day 13 Commitment) passed +
   every required task submitted + score at least 50%. The moment someone
   satisfies it, WDOS finalises the journey and advances their account
   automatically (approved → activated; applicant → approved). Journeys
   that run past their 14 days are marked **failed** by a daily 06:15
   sweep. Accountability is explicit both ways.
5. **The accountability report** sits at the TOP of the Reports page:
   name, Volunteer ID, position applied, country/state/LGA, day reached,
   progress, score, verdict (in progress / passed / failed / not
   started), CV received, last seen — plus the four count tiles.
6. **Kickoff.** One SQL call aligns every in-progress journey to start
   TODAY with the full 14 days, then emails + notifies every cohort
   member (and thanks to Phase 88, that notice also arrives as a push).
7. **Your logo** now heads the login page, the ID door, the sidebar, the
   member app, and every email WDOS sends.

---

## Deploy — in this order

### 1. Run the migration
Supabase → SQL Editor → paste and run
`supabase/migrations/068_activation_launch.sql`.
✅ System Health / #/doctor will now expect **schema 68**.

### 2. Put the new app on the internet
Drag the `app` folder to **both** Netlify sites (woddicrm + woddiwdos),
then hard-refresh (Ctrl+F5).
✅ Corner badge reads **build v55.1 · db 69**.
(The zip is bigger this time — the founder's video travels inside the
`app/content` folder. The drag works the same; it just takes a little
longer to upload.)

### 3. Fire the starting gun 🏁
Supabase → SQL Editor → run:

```sql
select activation_kickoff();
```

✅ It returns something like
`{"journeys_reset": 41, "members_notified": 134}` — journeys aligned to
today, and every cohort member emailed (and pushed) that the activation
is on. Safe to run twice: nobody is emailed a second time.

### 4. Two-minute test
1. Log in as a member → My Journey → Day 1 → the founder's video plays
   right there. Watch to the end → it ticks itself.
2. Open Day 5 → press "Open" on the Ask WODDI row → come back →
   the row is ticked. Try tapping a row by hand → WDOS politely refuses:
   the system does the ticking now.
3. Master account → **Reports** → the 14-Day Activation table is at the
   top with everyone's name, position, location, day, progress and
   verdict.

## Honest notes
- The video ticks on a **complete** watch-through (that's the point).
  If a device genuinely cannot play video, a manual confirm button
  appears as a fallback.
- Pass evaluation runs the instant any task is submitted, and again
  every morning at 06:15; expiries are marked failed at the same sweep.
- The kickoff email's logo loads from the live site — that's why
  Netlify (step 2) comes before the kickoff (step 3).
