# Phase 133: Network Command (v66.1 · db 104)

The founder's Monday standard, section 6: one authorised Headquarters
screen showing, per network and consolidated, how many leaders there are,
where, at what level, which seats are vacant, where each person stands in
the leadership journey, who has gone quiet, what is due, and what needs a
management decision, with every number opening to the people behind it.

## Deploy
1. SQL Editor → run migration 104_network_command.sql.
2. Drag the app folder to both Netlify sites → badge v66.1 · db 104.
3. HQ sidebar → Network Command (route #/command, HQ module only).

## What it shows (all live counts, nothing estimated)
- Network switch: Both networks / WGMN / WNNN (WGMN and WNNN figures are
  computed from each person's network; consolidated only for HQ).
- Overview cards: leaders in seat, members, countries with leaders,
  active in last 14 days, leaders quiet 30+ days, countries without a
  Country Representative, approved but login not created, activation in
  progress, activation due within 3 days, open and overdue tasks,
  meetings in the next 7 days, support tickets older than 3 days, open
  safeguarding cases, leaders with missing details.
- Requires management attention: a queue built from the same data, each
  line opening the list behind it.
- Leaders by level; Where everyone stands (journey stage per person with
  the next required action); Coverage by country (leaders, members,
  Country Representative and Deputy filled or vacant, states with a
  coordinator).
- Drill lists link to the member record, the Leader Atlas, Tasks or
  Accounts.

## Journey stage (server function member_stage)
registered → account → activation → assessed → (appointment) →
leader_active / leader_inactive; activation_lapsed and exited are
side states. The stage is derived from live records: role assignments,
activation journey status, member status and last-seen.

## Honest limits for Monday
- "Reports due/overdue" are not shown yet because the leader reporting
  module (templates, submissions, evidence, HQ review) is Phase 134.
- Vacancies are computed for Country Representative, Deputy and State
  Coordinator seats; district and chapter seat expectations are not yet
  modelled.
