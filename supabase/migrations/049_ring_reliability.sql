-- ============================================================================
-- WDOS Migration 049 — Ring Reliability (Phase 54)
--
-- "Ring them in" inserts personal notices; the bells only chirp if the
-- member_notices table is actually in the realtime publication. The
-- original attempt (migration 032) swallowed any failure silently — this
-- one makes certain, and tells you either way.
-- ============================================================================

do $$
begin
  alter publication supabase_realtime add table public.member_notices;
  raise notice 'member_notices ADDED to realtime — rings will now chirp live';
exception
  when duplicate_object then
    raise notice 'member_notices already in realtime — good';
  when others then
    raise notice 'Could not add member_notices to realtime: %', sqlerrm;
end $$;

-- verify at a glance
select tablename,
       'in realtime publication' as status
  from pg_publication_tables
 where pubname = 'supabase_realtime'
   and tablename in ('member_notices', 'staff_messages');

insert into public.schema_migrations (version, name)
values (49, 'ring_reliability') on conflict (version) do nothing;
