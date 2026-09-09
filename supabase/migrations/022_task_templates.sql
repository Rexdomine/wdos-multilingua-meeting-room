-- ============================================================================
-- WDOS Migration 022 — Task Templates
-- Define a task shape once ("Chapter monthly report"), reuse it forever.
-- Templates belong to their creator; HQ can mark templates as shared so
-- every leader sees them. Assignee, unit and due date stay per-use.
-- ============================================================================

create table public.task_templates (
  id                uuid primary key default gen_random_uuid(),
  name              text not null check (char_length(name) between 2 and 80),
  title             text not null check (char_length(title) between 3 and 160),
  details           text check (details is null or char_length(details) <= 4000),
  priority          public.task_priority not null default 'medium',
  requires_approval boolean not null default false,
  is_shared         boolean not null default false,
  created_by        uuid not null references public.profiles(id)
                      default auth.uid(),
  created_at        timestamptz not null default now()
);

create index task_templates_owner_idx on public.task_templates (created_by);

alter table public.task_templates enable row level security;

create policy task_templates_read on public.task_templates
  for select to authenticated
  using (created_by = auth.uid() or is_shared);

create policy task_templates_write on public.task_templates
  for insert to authenticated
  with check (
    created_by = auth.uid()
    and (is_shared = false or public.is_case_hq())
  );

create policy task_templates_manage on public.task_templates
  for update to authenticated
  using (created_by = auth.uid() or public.is_case_hq())
  with check (
    (created_by = auth.uid() or public.is_case_hq())
    and (is_shared = false or public.is_case_hq())
  );

create policy task_templates_delete on public.task_templates
  for delete to authenticated
  using (created_by = auth.uid() or public.is_case_hq());

insert into public.schema_migrations (version, name)
values (22, 'task_templates') on conflict (version) do nothing;
