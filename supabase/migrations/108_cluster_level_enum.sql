-- ============================================================================
-- WDOS Migration 108 — Community Cluster level and positions (ENUM VALUES ONLY)
-- The leadership hierarchy is ten positions on five geographic levels below
-- country: State/Region → LGA/District → Community Cluster → Chapter.
-- This adds the Community Cluster level BETWEEN district_lga and chapter and
-- the two cluster positions.  RUN THIS FILE ON ITS OWN, then run 109.
-- ============================================================================
alter type public.org_level add value if not exists 'community_cluster' before 'chapter';
alter type public.role_code add value if not exists 'cluster_coordinator';
alter type public.role_code add value if not exists 'assistant_cluster_coordinator';

insert into public.schema_migrations (version, name)
values (108, 'cluster_level_enum') on conflict (version) do nothing;
