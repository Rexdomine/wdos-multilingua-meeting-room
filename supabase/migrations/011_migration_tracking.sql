-- ============================================================================
-- WDOS Migration 011 — Migration Tracking
-- The database now keeps a record of which migrations have been applied.
-- The application reads this and warns Headquarters, on screen, the moment
-- its code expects a migration the database doesn't have. Skipped
-- migrations stop being silent.
--
-- RULE FROM NOW ON: every future migration file ends by inserting its own
-- number into schema_migrations.
-- ============================================================================

create table public.schema_migrations (
  version    int primary key,
  name       text not null,
  applied_at timestamptz not null default now()
);

alter table public.schema_migrations enable row level security;

-- Everyone signed in may read (the app's health check needs it);
-- nobody writes through the API — rows are inserted only by migration
-- scripts run in the SQL editor.
create policy schema_migrations_read on public.schema_migrations
  for select to authenticated using (true);

-- Record everything applied so far. Inserts are idempotent.
insert into public.schema_migrations (version, name) values
  (1,  'identity_structure_audit'),
  (2,  'status_change_rpc'),
  (3,  'fix_new_user_names'),
  (4,  'recruitment'),
  (5,  'leadership'),
  (6,  'tasks'),
  (7,  'meetings'),
  (8,  'reports'),
  (9,  'announcements'),
  (10, 'module_access'),
  (11, 'migration_tracking')
on conflict (version) do nothing;
