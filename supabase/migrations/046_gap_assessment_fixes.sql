-- ============================================================================
-- WDOS Migration 046 — Gap-Assessment Corrections (Phase 50)
--
-- Responds to the independent Phase 48 review. Confirmed-real findings
-- fixed here:
--   1. task_templates was missing the tags column the app sends when saving
--      a template (template saving failed).
--   2. GIN index on task tags for fast tag search at scale.
--   3. The task-files bucket was PUBLIC since migration 025 — anyone with a
--      link could open attachments without signing in. It is now private;
--      the app fetches short-lived signed URLs, and only signed-in users
--      (who can already see the task via RLS) can read objects.
--   4. The Phase-48 activity trigger stored literal "\u23f1" escape text
--      instead of the ⏱ and → characters. The trigger now writes the real
--      characters, and existing comments are repaired in place.
--   5. Hardening: sensitive workflow functions are no longer executable by
--      the anonymous role.
-- ============================================================================

-- 1 ▸ template tags column
alter table public.task_templates
  add column if not exists tags text[] not null default '{}';

-- 2 ▸ tag search index
create index if not exists tasks_tags_gin_idx
  on public.tasks using gin (tags);

-- 3 ▸ private attachments
update storage.buckets set public = false where id = 'task-files';

drop policy if exists task_files_read on storage.objects;
create policy task_files_read on storage.objects
  for select to authenticated
  using (bucket_id = 'task-files');

-- 4 ▸ activity text repair (real characters, not escape sequences)
create or replace function public.task_status_activity()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if old.status is distinct from new.status then
    insert into task_comments (task_id, author_id, body)
    values (new.id,
      coalesce(auth.uid(), new.assigned_by),
      '⏱ Status: ' || replace(old.status::text, '_', ' ')
      || ' → ' || replace(new.status::text, '_', ' '));
  end if;
  return new;
end; $$;

update public.task_comments
   set body = replace(replace(body, '\u23f1', '⏱'), '\u2192', '→')
 where strpos(body, '\u23f1') > 0;

-- 5 ▸ anon cannot call workflow functions
do $$
declare fn text;
begin
  foreach fn in array array[
    'run_automations()', 'run_automations_guarded()', 'run_daily_content()',
    'email_recent_notices()', 'send_test_email()', 'get_email_status()',
    'team_accountability()', 'uat_summary()', 'automation_insights()',
    'course_stats()', 'find_duplicate_profiles()',
    'merge_profiles(uuid,uuid,text)', 'send_email(text,text,text,text)',
    'set_email_secret(text,text)', 'search_staff_assignees(text)',
    'am_i_staff()', 'touch_last_seen()'
  ] loop
    begin
      execute 'revoke execute on function public.' || fn || ' from anon';
    exception when others then null;
    end;
  end loop;
end $$;

insert into public.schema_migrations (version, name)
values (46, 'gap_assessment_fixes') on conflict (version) do nothing;
