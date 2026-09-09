# PHASE 135 - Volunteer Leadership Structure (founder's standard)
Build v66.4 · db 106 · 5 Sep 2026

## What the founder asked for, and where it now lives

| Founder's requirement | WDOS |
|---|---|
| One internal hierarchy for both networks: Country → Region/State → District/LGA → Community Cluster/Ward | Already the org_units tree (country, state_region, district_lga, chapter). "chapter" is the Community Cluster / Ward level; its displayed name changes, the internal code does not. |
| Country-sensitive terminology (Nigeria: State / LGA / Ward; Ghana: Region / District / Community) | NEW table level_terms, 20 countries seeded plus a default. Dashboards, the leadership tree and the explorer read the country's own words. HQ can edit the rows in the table. |
| Position Master List of eight, no typed titles | The role_code enum is the list. Two positions were missing and are added in 105: Assistant District/LGA Coordinator, Assistant Community Cluster/Ward Coordinator. position_master records level and rank. The "Volunteer role" field on Accounts is now a dropdown of the eight (a legacy typed title is kept visibly as "typed title, not on the master list" until HQ corrects it). |
| Appointment Status: Appointed / Acting / Pending / Vacant | NEW appointment_status on every seat (vacant = no seat). Set in Accounts → Role / seat, shown on the leader's dashboard, in her tree, on Accounts rows and in the explorer. |
| Activation Status: Passed / In Progress / Not Completed | The activation journey status, shown per holder in the explorer. |
| Reports To / Direct Reports | volunteer_home corrected: a leader reports to the leader of the unit above her seat (principal before deputy, same network), not to a peer at her own unit; Direct Reports = deputies at her unit plus leaders at the units directly below. Both on the dashboard and the Leadership tab. |
| Full context line "Name - WGMN | Nigeria | Imo | Owerri | LGA Coordinator" (the founder's format) | On the welcome band and on every Accounts row. |
| Filter: Network → Country → Region → District → Position → Appointment → Activation, e.g. "WGMN → Nigeria → Imo → All LGAs → LGA Coordinators → Vacant" | NEW page Leadership Structure (#/structure; HQ sidebar, and a leader's menu for her own scope). Seven filters, counts (seats, filled, vacant, acting, pending), every seat listed with holder or VACANT, View as and Fill seat links. |
| Geography and position as two connected dimensions | structure_explorer joins org_units × position_master and finds the holder per network; a seat is vacant for WNNN even when WGMN has filled it. |

## Deploy (browser only, in this order)
1. SQL Editor → run `105_positions_enum.sql` ON ITS OWN (two enum values).
2. SQL Editor → run `106_leadership_structure.sql`.
3. Drag `app` onto both Netlify sites → badge **v66.4 · db 106**.

## Honest limits
- Tenure history: a seat shows since when; ended seats are kept in role_assignments but no tenure timeline page exists.
- Community Cluster/Ward units must exist in the tree to have seats; the explorer lists seats for the units that exist. Seeding wards is data entry (Organisation page), not code.
- Assistant positions can hold the module rights of their unit like the principal (same scope). Finer permissions per rank are not modelled.
