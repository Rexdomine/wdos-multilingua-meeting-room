-- ============================================================================
-- WDOS Migration 058 — The calendar rules every journey (Phase 71)
-- New journeys are born due on the programme close date (grace-aware),
-- and every current in-flight journey is re-dated to 17 Aug 2026.
-- ============================================================================
create or replace function public.journey_calendar_due()
returns trigger
language plpgsql security definer set search_path = public as $$
declare cl date; gr date; st text;
begin
  cl := coalesce((select (value #>> '{}')::date from org_settings
                   where key = 'programme_close'), date '2026-08-17');
  gr := coalesce((select (value #>> '{}')::date from org_settings
                   where key = 'programme_grace'), date '2026-08-24');
  st := programme_state();
  if st in ('before', 'open') then
    new.due_at := (cl + time '23:59:59')::timestamptz;
  elsif st = 'grace' then
    new.due_at := (gr + time '23:59:59')::timestamptz;
  end if;
  return new;
end; $$;

drop trigger if exists journey_calendar_due on public.activation_journeys;
create trigger journey_calendar_due
  before insert on public.activation_journeys
  for each row execute function public.journey_calendar_due();

update public.activation_journeys
   set due_at = timestamptz '2026-08-17 23:59:59+01',
       extended_until = null
 where status = 'in_progress';

insert into public.schema_migrations (version, name)
values (58, 'journey_calendar') on conflict (version) do nothing;
