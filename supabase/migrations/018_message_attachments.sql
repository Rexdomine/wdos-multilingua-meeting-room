-- ============================================================================
-- WDOS Migration 018 — Message Attachments & Staff Files
-- One attachment per staff message (image or document). Files live in a
-- bucket with unguessable names; write access mirrors message sending.
-- ============================================================================

alter table public.staff_messages
  add column attachment_path text,
  add column attachment_name text
    check (attachment_name is null or char_length(attachment_name) <= 200);

insert into storage.buckets (id, name, public)
values ('staff-files', 'staff-files', true)
on conflict (id) do nothing;

create policy staff_files_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'staff-files'
    and (public.is_active_staff(auth.uid()) or public.is_case_hq())
  );

insert into public.schema_migrations (version, name)
values (18, 'message_attachments') on conflict (version) do nothing;
