-- ============================================================================
-- WDOS Migration 044 — Global-Standard Tasks (Phase 48)
--
-- 1. TAGS on tasks (free labels, e.g. "UAT", "finance", "urgent-friday").
-- 2. ACTIVITY TRAIL: every status change writes an automatic entry into the
--    task's conversation — "⏱ Status: not started → in progress" — so the
--    master CRM and the assignee see the full history of the task without
--    anyone typing it. Works for list buttons, drawer, and kanban drags.
-- ============================================================================

alter table public.tasks
  add column if not exists tags text[] not null default '{}';

create or replace function public.task_status_activity()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if old.status is distinct from new.status then
    insert into task_comments (task_id, author_id, body)
    values (new.id,
      coalesce(auth.uid(), new.assigned_by),
      '\u23f1 Status: ' || replace(old.status::text, '_', ' ')
      || ' \u2192 ' || replace(new.status::text, '_', ' '));
  end if;
  return new;
end; $$;

drop trigger if exists tasks_status_activity on public.tasks;
create trigger tasks_status_activity
  after update on public.tasks
  for each row execute function public.task_status_activity();

insert into public.schema_migrations (version, name)
values (44, 'tasks_global_standard') on conflict (version) do nothing;
