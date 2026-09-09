-- ============================================================================
-- WDOS Migration 082 — Leaders can see and message their own team (Phase 94c)
--
-- Two real gaps in Regina's demo, both genuine misses, not display bugs:
--
-- 1. Nowhere in the app shows a leader's COUNTRY. getMyRoles() only ever
--    returned {role, org_unit_id} \u2014 the org unit's NAME was never fetched,
--    so the Home badge could show "Country Lead" but never "Banana
--    Republic". Fixed by joining the org unit's name into the query.
--
-- 2. The messaging wall built in Phase 88 was deliberate: an ordinary
--    member can message ONLY "WODDI HQ", never another member \u2014 a real
--    safety design, correctly holding for a volunteer base at scale.
--    But Regina and her deputy are colleagues on the SAME team (both hold
--    a role_assignments seat at Banana Republic), and Azeez explicitly
--    asked that she see and message her deputy. That is not the case the
--    wall was built to stop \u2014 it needs one narrow, deliberate door:
--    established leaders sharing an org_unit may message each other.
--    Ordinary members remain exactly as walled off as before.
-- ============================================================================

-- 1 ▸ the narrow door: teammates only, never opened wider ------------------
create or replace function public.same_leadership_team(a uuid, b uuid)
returns boolean language sql stable
security definer set search_path = public as $$
  select exists (
    select 1 from role_assignments ra1
    join role_assignments ra2 on ra2.org_unit_id = ra1.org_unit_id
     where ra1.profile_id = a and ra1.ends_at is null
       and ra2.profile_id = b and ra2.ends_at is null
       and a <> b
  );
$$;

drop policy if exists staff_msg_send on public.staff_messages;
create policy staff_msg_send on public.staff_messages
  for insert to authenticated
  with check (
    sender_id = auth.uid()
    and (
      public.is_active_staff(auth.uid())
      or public.is_case_hq()
      or public.can_receive_direct(recipient_id)
      or public.same_leadership_team(auth.uid(), recipient_id)
    )
  );

-- 2 ▸ who is on my team? (HQ-only style scoping not needed \u2014 every leader
--     may see her own teammates, nobody else's) ----------------------------
create or replace function public.my_team()
returns jsonb language sql stable
security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', p.id, 'name', p.first_name || ' ' || p.last_name,
    'role_applied', p.role_applied, 'unit', ou.name
  ) order by p.first_name), '[]'::jsonb)
  from role_assignments mine
  join role_assignments theirs
    on theirs.org_unit_id = mine.org_unit_id
   and theirs.ends_at is null
   and theirs.profile_id <> auth.uid()
  join profiles p on p.id = theirs.profile_id
  join org_units ou on ou.id = theirs.org_unit_id
  where mine.profile_id = auth.uid() and mine.ends_at is null
    and p.merged_into is null;
$$;
revoke execute on function public.my_team() from anon;

insert into public.schema_migrations (version, name)
values (82, 'leader_team_visibility') on conflict (version) do nothing;
