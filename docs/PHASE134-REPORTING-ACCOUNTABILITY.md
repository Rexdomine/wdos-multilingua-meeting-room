# PHASE 134 - Reporting & Accountability Module
Build v67.0 · db 107 · 6 Sep 2026
Built to: WGMN WDOS Reporting & Accountability Module, Final Functional Specification v1.0 (6 Sep 2026)

## Where it lives
Leaders: sidebar → Reporting & Accountability (#/reporting). HQ: HQ Operations → Reporting & Accountability.
Tabs: Dashboard · My Reports · Operational Records · Reports I Supervise · Reporting Compliance · Risks & Escalations · Approved & Archive.

## Coverage against the specification

| Spec | Status in v67.0 |
|---|---|
| A. Build brief 1 native reporting, 2 record once, 3 role-based, 4 one unit report, 5 upward aggregation, 6 exception-led, 8 action conversion, 10 auditability, 11 multilingual (en/fr) | Done |
| A. 7 confidential separation | Done: safeguarding stays in the cases channel; routine reports carry a sensitive-wording warning that redirects |
| A. 9 mobile-first, autosave, resumable | Done: drafts autosave every keystroke (debounced), forms stack on phones, evidence under 8 MB or a link |
| A. 12 one data source for every dashboard | Done: report_snapshot() is the only calculator |
| §3 cadence and unit-report principle, §21.1 deputy contributes, acting submits | Done: report_unit_for() gives submit rights to the principal, a formally acting deputy, or the deputy when the principal seat is vacant; deputies add contributions |
| §5 menu | 7 tabs cover 15 of the 22 items; the remaining items (partnership, learning, membership, digital inclusion, finance, exit, analytics) are sections or templates inside them rather than separate pages |
| §6 auto-filled identity, 60 to 70 percent auto-population | Done: identity, leadership, pipeline, membership, tasks, meetings, activities, programmes, learning (WDOS courses), compliance, issues, support are computed |
| §7 Workflow 1 activity record | Done, all 13 categories, follow-up, evidence reference, escalation flag; feeds every snapshot |
| §8 Workflow 2 weekly pulse | Done, with HQ cadence control (levels, countries) in reporting_config |
| §9 Workflow 3 monthly report A to P | Done: 16 sections, conditional finance (M), max five priorities (O), declaration (P) |
| §10 Workflow 4 activity report | Done (evidence required) |
| §11 Workflow 5 meeting actions | Done; approved actions become tasks linked to the report |
| §12 Workflow 6 leadership pipeline | Live view exists as Leadership Structure (#/structure) plus the snapshot pipeline block; the fine-grained appointment sub-stages (letter issued, accepted) are Phase 135b |
| §13 Workflow 7 membership | Snapshot block done; targets versus actual needs a targets table (not built) |
| §14 Workflow 8 learning | WDOS courses only; the Institute pull is a separate project |
| §15 Workflow 9 partnerships | Structured rows inside the monthly report (Section J); a stakeholder table that survives leadership change is Phase 3 of the spec |
| §16 Workflow 10 digital inclusion | Section L plus ticket counts; a dedicated support-case table is Phase 3 |
| §17 Workflow 11 risks and escalations | Done: issues table with ID, category, severity, owner, route, deadline, status; red/critical surface on every dashboard; Section N rows become issues on approval |
| §18 Workflow 12 confidential | Existing cases channel; not mixed with reports |
| §19 Workflow 13 finance | Conditional sections only (M and activity F); no finance table |
| §20 Workflow 14 exit and handover | Template with auto-pulled position and transition fields; the clearance workflow (functional clearances, access transfer) is Phase 4 |
| §22 aggregation rules | Done: hierarchy-aware (subtree), date-aware, status-aware (approved reports count), vacancy-aware (a vacant unit is a gap, not absent) |
| §23 statuses and review rules | Done: draft, submitted, under_review, returned, approved, escalated, closed, superseded; returned reports keep the submitted version; approval locks; corrections create versions |
| §24 reminders | Done: 7/3/0 before, 1/3/7 overdue, supervisor alert at 3, escalation level at 7, all configurable; pg_cron daily 06:30 plus "Run reminders now" |
| §25 dashboards | Personal and supervisor done; Country and HQ use the same compliance view with drill-down; the full Africa dashboard filter set is Phase 5 |
| §26 validation | Done: required sections block, evidence rule, overdue task and non-compliance explanations, red/critical need action and owner, max five priorities, sensitive wording warns and redirects, nil declaration with reason, no-records warning |
| §27 security and audit | Done: RLS by unit scope, append-only review records, audit_log trigger, private evidence bucket keyed to the report |
| §28 multilingual, mobile, low bandwidth | Labels en/fr; original free text preserved; mobile layout; no large uploads required |
| §29 KPIs | Submission, on-time, approval and evidence rates computed; the remaining KPIs need the Phase 3 tables |
| §32 acceptance criteria | 1 to 11, 13, 16 to 21, 22, 23, 25, 26, 29 demonstrable today; 12 partly (membership pulled); 14, 15 partly; 24 done via level_terms; 27, 28, 30 later phases |

## Deploy (browser only)
1. SQL Editor → run `107_reporting_accountability.sql` (one run; 105 and 106 must already be applied).
2. Drag `app` onto both Netlify sites → badge **v67.0 · db 107**.

## Demonstrating it on Monday (five minutes, real data)
1. Leader: Reporting → Operational Records → record one activity.
2. Leader: Dashboard → Start monthly report → sections auto-filled → fill B, tick P → Submit. Show the block if P is not ticked.
3. Supervisor (or HQ): Reports I Supervise → open → Approve → tasks appear on the leader's task list.
4. HQ: Reporting Compliance → the unit shows Approved, on time; a unit with no leader shows as a coverage gap.
5. HQ: Run reminders now → notices issued for units still due.

## Honest limits
- Institute learning status is not pulled (separate project).
- Partnership, digital-support and finance records are rows inside reports, not yet tables of their own.
- Quarterly and annual consolidation pages are not built; the monthly snapshots hold the data for them.
- Export of approved reports is the browser's Print / PDF; a bulk export with restricted-content exclusion is Phase 4.
