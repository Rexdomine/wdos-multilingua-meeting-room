-- ============================================================================
-- WDOS Migration 056 — Founder's Welcome (Phase 68)
-- Adds "Watch the Founder's Welcome Message" as a Day-1 activity. The app
-- detects the Drive link in the prompt and embeds the video player inline;
-- the volunteer marks it done after watching. Idempotent.
-- ============================================================================
insert into public.activation_items (day, seq, kind, prompt, is_required)
select 1,
       coalesce((select max(seq) from public.activation_items where day = 1), 0) + 1,
       'ack',
       'Watch the Founder''s Welcome Message, then mark it as done. '
       || 'https://drive.google.com/file/d/1DUoYOqIO6Lio7oaZN90ASvydiqnGiF_H/view',
       true
where not exists (
  select 1 from public.activation_items
   where day = 1 and prompt ilike '%Founder%Welcome%');

insert into public.schema_migrations (version, name)
values (56, 'founder_message') on conflict (version) do nothing;
