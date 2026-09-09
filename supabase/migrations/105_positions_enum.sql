-- ============================================================================
-- WDOS Migration 105 — Position Master List: two missing positions
--
-- The founder's Volunteer Leadership Structure names eight positions.
-- Six already exist as role codes. These two did not:
--   6. Assistant LGA/District/Municipal Coordinator  → assistant_district_coordinator
--   8. Assistant Community Cluster/Ward Coordinator  → assistant_chapter_lead
-- (7. Community Cluster/Ward Coordinator is the existing chapter_lead; only
--  its displayed name changes, in the app locales.)
--
-- RUN THIS FILE ON ITS OWN, then run 106. Postgres will not let a script use
-- an enum value it added in the same run, and 106 uses both values.
-- ============================================================================
alter type public.role_code add value if not exists 'assistant_district_coordinator';
alter type public.role_code add value if not exists 'assistant_chapter_lead';

insert into public.schema_migrations (version, name)
values (105, 'positions_enum') on conflict (version) do nothing;
