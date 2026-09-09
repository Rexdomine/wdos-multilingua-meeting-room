-- ============================================================================
-- WDOS Migration 071 — Day 1 rebuilt as directed (Phase 89g)
-- Day 1 — Welcome & Digital Onboarding is now SIX clear tasks, one screen
-- each, every one verified and ticked by the system:
--   1. Complete your profile.
--   2. Upload your passport photo.
--   3. Verify your email address.
--   4. Accept the Volunteer Agreement.
--   5. Accept the Code of Conduct.
--   6. Open the Leadership Handbook and confirm you have read it.
--   7. Watch the Founder's Welcome Message (kept as the day's finale,
--      with the watch-guard).
-- The old crowded 6-row checklist and the quiz question are removed, with
-- their answers, so every volunteer walks the new Day 1 cleanly.
-- ============================================================================

-- old day-1 checklist + quiz out (answers and answer-keys first)
delete from public.activation_item_responses
 where item_id in (select id from public.activation_items
                    where day = 1 and kind in ('checklist', 'mcq'));
delete from public.activation_keys
 where item_id in (select id from public.activation_items
                    where day = 1 and kind in ('checklist', 'mcq'));
delete from public.activation_items
 where day = 1 and kind in ('checklist', 'mcq');

-- the founder's video closes the day
update public.activation_items
   set seq = 7
 where day = 1 and prompt ilike '%Founder%Welcome%';

-- six tasks, individually system-verified
insert into public.activation_items
  (day, seq, kind, prompt, options, points, is_required)
values
  (1, 1, 'ack', 'Complete your profile.',            '[]'::jsonb, 0, true),
  (1, 2, 'ack', 'Upload your passport photo.',       '[]'::jsonb, 0, true),
  (1, 3, 'ack', 'Verify your email address.',        '[]'::jsonb, 0, true),
  (1, 4, 'ack', 'Accept the Volunteer Agreement.',   '[]'::jsonb, 0, true),
  (1, 5, 'ack', 'Accept the Code of Conduct.',       '[]'::jsonb, 0, true),
  (1, 6, 'ack',
   'Open the Leadership Handbook and confirm you have read it.',
   '[]'::jsonb, 0, true);

insert into public.schema_migrations (version, name)
values (71, 'day1_six_tasks') on conflict (version) do nothing;
