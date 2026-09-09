-- ============================================================================
-- WDOS Migration 027 — Live Events Fix + Documents Module
-- 1) THE NOTIFICATION FIX: the bell/sound never fired because these tables
--    were never added to the Realtime publication. Now they are.
-- 2) Documents: folders (nestable), files, archiving. Folder belongs to an
--    org unit; visible to that unit's members, leaders over it, and HQ.
-- ============================================================================

do $$
declare t text;
begin
  foreach t in array array[
    'staff_messages','tasks','announcements','task_comment_mentions'
  ] loop
    begin
      execute format(
        'alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then null;
    end;
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Documents
-- ---------------------------------------------------------------------------
create table public.doc_folders (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(name) between 1 and 120),
  parent_id   uuid references public.doc_folders(id) on delete cascade,
  org_unit_id uuid not null references public.org_units(id) on delete restrict,
  created_by  uuid not null references public.profiles(id) default auth.uid(),
  created_at  timestamptz not null default now(),
  unique (org_unit_id, parent_id, name)
);

create table public.documents (
  id          uuid primary key default gen_random_uuid(),
  folder_id   uuid not null references public.doc_folders(id) on delete cascade,
  name        text not null check (char_length(name) between 1 and 200),
  path        text not null,
  mime        text,
  archived    boolean not null default false,
  uploaded_by uuid not null references public.profiles(id) default auth.uid(),
  created_at  timestamptz not null default now()
);

create index documents_folder_idx on public.documents (folder_id, archived);

create trigger doc_folders_audit after insert or update or delete
  on public.doc_folders for each row execute function public.audit_row();
create trigger documents_audit after insert or update or delete
  on public.documents for each row execute function public.audit_row();

create or replace function public.can_see_doc_unit(unit uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select is_case_hq()
      or unit in (select administered_units())
      or exists (select 1 from profiles p
                 where p.id = auth.uid() and p.org_unit_id = unit);
$$;

create or replace function public.can_manage_doc_unit(unit uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select is_case_hq()
      or unit in (select administered_units())
      or (exists (select 1 from staff s where s.profile_id = auth.uid()
                    and s.is_active)
          and unit = (select id from org_units
                      where level = 'headquarters'));
$$;

alter table public.doc_folders enable row level security;
alter table public.documents   enable row level security;

create policy folders_read on public.doc_folders
  for select to authenticated using (public.can_see_doc_unit(org_unit_id));
create policy folders_write on public.doc_folders
  for insert to authenticated
  with check (created_by = auth.uid()
              and public.can_manage_doc_unit(org_unit_id));
create policy folders_delete on public.doc_folders
  for delete to authenticated
  using (created_by = auth.uid() or public.is_case_hq());

create policy documents_read on public.documents
  for select to authenticated
  using (exists (select 1 from public.doc_folders f
                 where f.id = folder_id
                   and public.can_see_doc_unit(f.org_unit_id)));
create policy documents_write on public.documents
  for insert to authenticated
  with check (uploaded_by = auth.uid()
    and exists (select 1 from public.doc_folders f
                where f.id = folder_id
                  and public.can_manage_doc_unit(f.org_unit_id)));
create policy documents_archive on public.documents
  for update to authenticated
  using (exists (select 1 from public.doc_folders f
                 where f.id = folder_id
                   and public.can_manage_doc_unit(f.org_unit_id)))
  with check (exists (select 1 from public.doc_folders f
                      where f.id = folder_id
                        and public.can_manage_doc_unit(f.org_unit_id)));

insert into storage.buckets (id, name, public)
values ('documents', 'documents', true)
on conflict (id) do nothing;

create policy documents_upload on storage.objects
  for insert to authenticated
  with check (bucket_id = 'documents');

alter table public.module_access drop constraint module_access_module_check;
alter table public.module_access add constraint module_access_module_check
  check (module in (
    'members','recruitment','organisation','tasks','meetings','reports',
    'announcements','settings','programmes','cases','helpdesk','hq',
    'library','documents'
  ));

insert into public.module_access (role, module)
select r::public.role_code, 'documents' from unnest(array[
  'super_admin','executive_director','hq_team',
  'country_rep','deputy_country_rep','state_coordinator',
  'assistant_state_coordinator','district_coordinator','chapter_lead'
]) as r
on conflict do nothing;

insert into public.schema_migrations (version, name)
values (27, 'realtime_and_documents') on conflict (version) do nothing;
