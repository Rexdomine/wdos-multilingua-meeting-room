-- ============================================================================
-- WDOS Migration 057 — Task assignment polish (Phase 70, Codex round 3)
-- search_staff_assignees now also matches the email the UI displays.
-- ============================================================================
create or replace function public.search_staff_assignees(s text)
returns table (id uuid, first_name text, last_name text,
               email text, position_title text)
language sql stable
security definer set search_path = public as $$
  select p.id, p.first_name, p.last_name, p.email, st.position_title
    from staff st
    join profiles p on p.id = st.profile_id
   where st.is_active
     and is_case_hq()
     and (coalesce(s, '') = ''
          or p.first_name ilike '%' || s || '%'
          or p.last_name  ilike '%' || s || '%'
          or p.email      ilike '%' || s || '%'
          or st.position_title ilike '%' || s || '%')
   order by p.first_name
   limit 20;
$$;
grant execute on function public.search_staff_assignees(text) to authenticated;
revoke execute on function public.search_staff_assignees(text) from anon, public;

insert into public.schema_migrations (version, name)
values (57, 'tasks_polish') on conflict (version) do nothing;
