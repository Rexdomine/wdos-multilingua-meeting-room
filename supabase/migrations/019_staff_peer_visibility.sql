-- ============================================================================
-- WDOS Migration 019 — Staff Peer Visibility
-- Staff on the active register may see each other's profiles (names in the
-- HQ directory, messages, task assignment). Without this, a staff member
-- with no field roles saw only herself, and HQ panels lost their names.
-- ============================================================================

create policy profiles_staff_peers on public.profiles
  for select to authenticated
  using (public.is_active_staff(auth.uid())
     and public.is_active_staff(id));

insert into public.schema_migrations (version, name)
values (19, 'staff_peer_visibility') on conflict (version) do nothing;
