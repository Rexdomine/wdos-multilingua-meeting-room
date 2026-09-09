-- ============================================================================
-- WDOS Migration 020 — HQ Officeholder Visibility
-- Staff may see the profiles of HQ officeholders (super admin, executive
-- director, HQ team) even when those officeholders are not on the staff
-- register — so tasks, announcements and meetings created by them show a
-- real name instead of a blank.
-- ============================================================================

create policy profiles_staff_see_hq on public.profiles
  for select to authenticated
  using (
    public.is_active_staff(auth.uid())
    and exists (
      select 1 from role_assignments ra
      where ra.profile_id = profiles.id
        and ra.ends_at is null
        and ra.role in ('super_admin','executive_director','hq_team')
    )
  );

insert into public.schema_migrations (version, name)
values (20, 'hq_officeholder_visibility') on conflict (version) do nothing;
