-- ============================================================================
-- WDOS Migration 021 — Task Comments & Mentions
-- Conversation on tasks. Visibility mirrors the task itself: assignee,
-- assigner, leaders over the task's unit, and HQ. Mentions notify the
-- mentioned person through the in-app bell (Realtime).
-- ============================================================================

create or replace function public.can_access_task(tid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from tasks x
    where x.id = tid
      and (x.assigned_to = auth.uid()
        or x.assigned_by = auth.uid()
        or x.org_unit_id in (select administered_units())
        or has_role(array['super_admin','executive_director','hq_team']::public.role_code[]))
  );
$$;

create table public.task_comments (
  id         uuid primary key default gen_random_uuid(),
  task_id    uuid not null references public.tasks(id) on delete cascade,
  author_id  uuid not null references public.profiles(id) default auth.uid(),
  body       text not null check (char_length(body) between 1 and 2000),
  created_at timestamptz not null default now()
);

create index task_comments_idx on public.task_comments (task_id, created_at);

create table public.task_comment_mentions (
  comment_id uuid not null references public.task_comments(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (comment_id, profile_id)
);

alter table public.task_comments         enable row level security;
alter table public.task_comment_mentions enable row level security;

create policy task_comments_read on public.task_comments
  for select to authenticated
  using (public.can_access_task(task_id));

create policy task_comments_write on public.task_comments
  for insert to authenticated
  with check (author_id = auth.uid() and public.can_access_task(task_id));

create policy mentions_read on public.task_comment_mentions
  for select to authenticated
  using (
    profile_id = auth.uid()
    or exists (select 1 from public.task_comments c
               where c.id = comment_id
                 and public.can_access_task(c.task_id))
  );

create policy mentions_write on public.task_comment_mentions
  for insert to authenticated
  with check (
    exists (select 1 from public.task_comments c
            where c.id = comment_id
              and c.author_id = auth.uid())
  );

insert into public.schema_migrations (version, name)
values (21, 'task_comments') on conflict (version) do nothing;
