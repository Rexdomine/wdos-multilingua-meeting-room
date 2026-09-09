-- ============================================================================
-- WDOS Migration 069 — Founder video: watched means WATCHED (Phase 89b)
-- The app now tracks genuine watching (no skipping, no scrub-to-end, 1×
-- speed, tick at ≥95% truly seen). Any tick earned under the old
-- press-Confirm button is unearned under the new rule — clear them so
-- every volunteer, including test accounts, actually watches.
-- ============================================================================

delete from public.activation_item_responses
 where item_id in (select id from public.activation_items
                    where day = 1 and prompt ilike '%Founder%Welcome%');

insert into public.schema_migrations (version, name)
values (69, 'founder_video_watch_reset') on conflict (version) do nothing;
