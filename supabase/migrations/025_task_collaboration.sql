-- ============================================================================
-- WDOS Migration 025 — Task Checklists & Files (FRD §P / collaboration)
-- Sub-items with done-states and supporting documents on any task.
-- Access mirrors the task itself (assignee, assigner, leaders over the
-- unit, HQ) via can_access_task(). Files live under unguessable names;
-- the file list is only readable through the task.
-- ============================================================================

create table public.task_checklist_items (
  id         uuid primary key default gen_random_uuid(),
  task_id    uuid not null references public.tasks(id) on delete cascade,
  seq        int not null default 0,
  label      text not null check (char_length(label) between 1 and 200),
  done       boolean not null default false,
  done_by    uuid references public.profiles(id),
  done_at    timestamptz,
  created_by uuid not null references public.profiles(id) default auth.uid(),
  created_at timestamptz not null default now()
);

create index checklist_task_idx on public.task_checklist_items (task_id, seq);

create trigger checklist_audit after insert or update or delete
  on public.task_checklist_items for each row
  execute function public.audit_row();

create table public.task_files (
  id          uuid primary key default gen_random_uuid(),
  task_id     uuid not null references public.tasks(id) on delete cascade,
  path        text not null,
  name        text not null check (char_length(name) between 1 and 200),
  uploaded_by uuid not null references public.profiles(id)
                default auth.uid(),
  created_at  timestamptz not null default now()
);

create index task_files_idx on public.task_files (task_id);

create trigger task_files_audit after insert or update or delete
  on public.task_files for each row execute function public.audit_row();

alter table public.task_checklist_items enable row level security;
alter table public.task_files            enable row level security;

create policy checklist_read on public.task_checklist_items
  for select to authenticated using (public.can_access_task(task_id));
create policy checklist_insert on public.task_checklist_items
  for insert to authenticated
  with check (created_by = auth.uid()
              and public.can_access_task(task_id));
create policy checklist_update on public.task_checklist_items
  for update to authenticated
  using (public.can_access_task(task_id))
  with check (public.can_access_task(task_id));
create policy checklist_delete on public.task_checklist_items
  for delete to authenticated
  using (created_by = auth.uid() or public.is_case_hq());

create policy task_files_read on public.task_files
  for select to authenticated using (public.can_access_task(task_id));
create policy task_files_insert on public.task_files
  for insert to authenticated
  with check (uploaded_by = auth.uid()
              and public.can_access_task(task_id));

insert into storage.buckets (id, name, public)
values ('task-files', 'task-files', true)
on conflict (id) do nothing;

create policy task_files_upload on storage.objects
  for insert to authenticated
  with check (bucket_id = 'task-files');

insert into public.schema_migrations (version, name)
values (25, 'task_collaboration') on conflict (version) do nothing;
