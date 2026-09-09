-- ============================================================================
-- WDOS Migration 070 — Message attachments for the member era (Phase 89e)
-- The staff-files bucket rules were written when messaging was staff-only
-- (migration 018): INSERT for staff/HQ, and no SELECT policy at all. Since
-- Phase 88, members and HQ exchange messages — so:
--   1. Everyone signed in may READ message attachments (needed for the
--      signed URLs both sides use to play voice notes and open files).
--   2. Members may UPLOAD, but only into their own folder (uid/...).
--      Staff/HQ keep their existing unrestricted upload right.
-- ============================================================================

drop policy if exists staff_files_read on storage.objects;
create policy staff_files_read on storage.objects
  for select to authenticated
  using (bucket_id = 'staff-files');

drop policy if exists staff_files_insert on storage.objects;
create policy staff_files_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'staff-files'
    and (public.is_active_staff(auth.uid())
         or public.is_case_hq()
         or name like auth.uid()::text || '/%')
  );

insert into public.schema_migrations (version, name)
values (70, 'member_message_attachments') on conflict (version) do nothing;
