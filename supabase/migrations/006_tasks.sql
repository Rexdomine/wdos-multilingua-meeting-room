-- ============================================================================
-- WDOS Migration 006 — Tasks & Approvals
-- Assignment flows down the hierarchy; completion of approval-gated tasks
-- is reserved for the assigner or a leader over the unit. All audited.
-- ============================================================================

create type public.task_status as enum (
  'not_started', 'in_progress', 'awaiting_review', 'completed', 'cancelled'
);
create type public.task_priority as enum ('low', 'medium', 'high', 'urgent');

create table public.tasks (
  id                uuid primary key default gen_random_uuid(),
  title             text not null check (char_length(title) between 3 and 160),
  details           text check (details is null or char_length(details) <= 4000),
  org_unit_id       uuid not null references public.org_units(id) on delete restrict,
  assigned_to       uuid not null references public.profiles(id) on delete restrict,
  assigned_by       uuid not null references public.profiles(id) default auth.uid(),
  priority          public.task_priority not null default 'medium',
  status            public.task_status not null default 'not_started',
  requires_approval boolean not null default false,
  due_on            date,
  completed_at      timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create index tasks_assignee_idx on public.tasks (assigned_to, status);
create index tasks_assigner_idx on public.tasks (assigned_by, status);
create index tasks_unit_idx     on public.tasks (org_unit_id, status);
create index tasks_due_idx      on public.tasks (due_on) where status in
  ('not_started','in_progress','awaiting_review');

create trigger tasks_touch before update on public.tasks
  for each row execute function public.touch_updated_at();
create trigger tasks_audit after insert or update or delete
  on public.tasks for each row execute function public.audit_row();

-- ---------------------------------------------------------------------------
-- Authority helper: manager of a task = its assigner, a leader over its
-- unit, or HQ.
-- ---------------------------------------------------------------------------
create or replace function public.is_task_manager(t public.tasks)
returns boolean language sql stable security definer set search_path = public as $$
  select t.assigned_by = auth.uid()
      or t.org_unit_id in (select administered_units())
      or has_role(array['super_admin','executive_director','hq_team']::public.role_code[]);
$$;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
alter table public.tasks enable row level security;

create policy tasks_read on public.tasks
  for select to authenticated
  using (assigned_to = auth.uid() or public.is_task_manager(tasks));

-- Create: for yourself anywhere in your unit's scope, or as a leader for
-- anyone within your administered subtree. assigned_by must be you.
create policy tasks_insert on public.tasks
  for insert to authenticated
  with check (
    assigned_by = auth.uid()
    and status = 'not_started'
    and completed_at is null
    and (
      assigned_to = auth.uid()
      or org_unit_id in (select public.administered_units())
      or public.has_role(array['super_admin','executive_director','hq_team']::public.role_code[])
    )
  );

create policy tasks_update on public.tasks
  for update to authenticated
  using (assigned_to = auth.uid() or public.is_task_manager(tasks))
  with check (assigned_to = auth.uid() or public.is_task_manager(tasks));

-- ---------------------------------------------------------------------------
-- Transition + authority guard
-- ---------------------------------------------------------------------------
create or replace function public.valid_task_transition(
  old_s public.task_status, new_s public.task_status)
returns boolean language sql immutable as $$
  select case old_s
    when 'not_started'     then new_s in ('in_progress','completed','cancelled')
    when 'in_progress'     then new_s in ('awaiting_review','completed','cancelled','not_started')
    when 'awaiting_review' then new_s in ('completed','in_progress','cancelled')
    when 'completed'       then new_s in ('in_progress')      -- reopen
    when 'cancelled'       then new_s in ('not_started')      -- reopen
  end;
$$;

create or replace function public.tasks_guard()
returns trigger
language plpgsql security definer set search_path = public as $$
declare manager boolean;
begin
  manager := is_task_manager(old);

  -- Assignees who are not managers may change ONLY the status column.
  if not manager then
    if new.title is distinct from old.title
       or new.details is distinct from old.details
       or new.org_unit_id is distinct from old.org_unit_id
       or new.assigned_to is distinct from old.assigned_to
       or new.assigned_by is distinct from old.assigned_by
       or new.priority is distinct from old.priority
       or new.requires_approval is distinct from old.requires_approval
       or new.due_on is distinct from old.due_on then
      raise exception 'Only the assigner or a leader over this unit can edit task details';
    end if;
  end if;

  if new.status is distinct from old.status then
    if not valid_task_transition(old.status, new.status) then
      raise exception 'Invalid task transition: % -> %', old.status, new.status;
    end if;
    -- Approval gate and manager-only transitions
    if new.status = 'completed' and old.requires_approval and not manager then
      raise exception 'This task requires approval: only the assigner or a leader can complete it';
    end if;
    if new.status = 'cancelled' and not manager then
      raise exception 'Only the assigner or a leader can cancel a task';
    end if;
    if old.status in ('completed','cancelled') and not manager then
      raise exception 'Only the assigner or a leader can reopen a task';
    end if;
    new.completed_at :=
      case when new.status = 'completed' then now() else null end;
  end if;

  return new;
end; $$;

create trigger tasks_guard_trg before update on public.tasks
  for each row execute function public.tasks_guard();
