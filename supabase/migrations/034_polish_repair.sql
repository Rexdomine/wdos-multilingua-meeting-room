-- ============================================================================
-- WDOS Migration 034 — Polish & Repair (Phase 38)
--
-- 1. FIXES the long-standing avatar "Set photo" 403. Root cause: the avatars
--    bucket had insert/update/delete policies but NO select policy — and a
--    replace-upload (upsert) first looks the object up, which failed. One
--    missing policy, now added.
-- 2. org_settings — a small HQ-editable key/value store, starting with
--    activation_window_days (default 14). The founder's 14-vs-30-day
--    decision becomes a dial in Settings, not a rebuild: new journeys get
--    their deadline from this setting. (The 14 content days still unlock
--    one per day; the window only sets how long the journey may take.)
-- ============================================================================

-- 1 ▸ avatar fix
drop policy if exists avatars_select on storage.objects;
create policy avatars_select on storage.objects
  for select to authenticated
  using (bucket_id = 'avatars');

-- 2 ▸ org settings
create table if not exists public.org_settings (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now()
);
alter table public.org_settings enable row level security;
drop policy if exists org_settings_read on public.org_settings;
create policy org_settings_read on public.org_settings
  for select to authenticated using (true);
drop policy if exists org_settings_write on public.org_settings;
create policy org_settings_write on public.org_settings
  for all to authenticated
  using (public.is_case_hq()) with check (public.is_case_hq());

insert into public.org_settings (key, value)
values ('activation_window_days', '14'::jsonb)
on conflict (key) do nothing;

-- 3 ▸ new journeys take their deadline from the setting
create or replace function public.journey_apply_window()
returns trigger
language plpgsql security definer set search_path = public as $$
declare d int;
begin
  select (value #>> '{}')::int into d
    from org_settings where key = 'activation_window_days';
  d := greatest(7, least(90, coalesce(d, 14)));
  new.due_at := coalesce(new.started_at, now()) + make_interval(days => d);
  return new;
end; $$;

drop trigger if exists journey_window on public.activation_journeys;
create trigger journey_window before insert on public.activation_journeys
  for each row execute function public.journey_apply_window();

insert into public.schema_migrations (version, name)
values (34, 'polish_repair') on conflict (version) do nothing;
