# PHASE 137 - Leadership Master Register reconciliation + country flags
Build v68.1 · db 113 · 7 Sep 2026

## The register (06 Sep 2026) in WDOS
Migration 113 loads all 124 rows of the WGMN Volunteer Leadership Master Register
into a staging table exactly as written: 25 countries (CR and DCR), 37 Nigeria
states (SC and ASC); 112 named rows, 12 vacant seats, 11 named rows flagged by the
register as source conflicts or name variations. Nothing is guessed: a conflict row
stays a conflict until HQ decides.

Nigeria's Country Representative is Hon. Ngunan Addingi (CR-NGA). The register's
older CR record (Haruna Amina) is superseded and is not added. The older DCR name
(Maureen Nkechi Chukwuemeka) is kept as a note for HQ verification, not as a seat.

## What to run (SQL Editor, after 113)
1. `select * from register_reconcile();`
   One line per named row: matched_login (already has a WDOS login),
   matched_directory (already in the directory awaiting a login), missing, or
   vacant. Matching is by normalised name within the same country (titles such as
   Hon., Dr., Barr., Pharm. ignored; word order ignored; two matching name words
   required).
2. `select register_apply();`
   Adds every MISSING, UNFLAGGED name to the leader directory with a generated
   code (CR-<ISO>, DCR-<ISO>, SC-<STATE>, ASC-<STATE>) and returns the counts.
   They appear on HQ → Accounts (filter "No login yet") with Create login, where
   HQ types the person's email; the register has no emails.
3. Conflicts (result = missing, conflict = true): Bayelsa ASC, Imo ASC, Yobe SC,
   Anambra SC name variation, Ebonyi SC name variation, Oyo and Zamfara rows,
   Burkina Faso, The Gambia, Morocco, Tunisia, Uganda, Nigeria DCR notes. HQ
   resolves each from Accounts → Add leader / member once verified.

## Country flags
Each leader's country flag is bundled as an SVG in /assets/flags (54 African
countries) and shown beside the name on the welcome band, in the header identity
and on every Accounts row. SVGs render on every device, including Windows, where
emoji flags appear as letters. The flag follows the leader's unit chain country,
else the profile's country name.

## Deploy
Run `113_leadership_register_reconcile.sql`; drag `app` to both Netlify sites → badge
v68.1 · db 113. Then the two SELECTs above.
