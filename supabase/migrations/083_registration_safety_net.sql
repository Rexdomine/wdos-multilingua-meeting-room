-- ============================================================================
-- WDOS Migration 083 — Registration approval gets a safety net (Phase 96)
--
-- Real, recurring failure mode: volunteer_auto_approve() (the live,
-- instant-approval trigger fired the moment someone registers) wraps its
-- work in an exception handler that, on ANY failure, just logs a Postgres
-- `raise notice` and moves on. That message goes to a server log nobody
-- reads. The registrant is left sitting at status='submitted' \u2014 silently,
-- invisibly, forever \u2014 with nothing on their end but "your application
-- is with the review team" and nothing on HQ's end at all. This is the
-- exact same silent-failure shape Phase 90 found and fixed for the
-- original 134-person batch; today's screenshots show it has quietly
-- recurred for new registrants since.
--
-- The permanent fix is not "run the release command again" \u2014 it's a
-- standing safety net so nobody ever has to remember to:
--   1. A scheduled sweep (every 15 minutes) calls the SAME hardened
--      approve_stuck_registrations() already built in Phase 90 \u2014 it has
--      real per-row exception armour (a bad row is reported, never
--      silently dropped) \u2014 catching anyone the live trigger missed,
--      almost always within 15 minutes of them registering.
--   2. Every sweep's result is written to a durable log table, so a
--      genuine failure (not just a slow one) is visible on a query
--      instead of vanishing into a log nobody reads.
--   3. Anyone stuck RIGHT NOW is released the moment this migration runs.
-- ============================================================================

create table if not exists public.registration_repair_log (
  id         uuid primary key default gen_random_uuid(),
  run_at     timestamptz not null default now(),
  released   int not null default 0,
  failed     jsonb not null default '[]'::jsonb
);
alter table public.registration_repair_log enable row level security;
create policy repair_log_hq_read on public.registration_repair_log
  for select to authenticated using (public.is_case_hq());

create or replace function public.scheduled_registration_release()
returns jsonb language plpgsql
security definer set search_path = public as $$
declare result jsonb;
begin
  select public.approve_stuck_registrations() into result;
  insert into registration_repair_log (released, failed)
  values (coalesce((result ->> 'released')::int, 0),
          coalesce(result -> 'failed', '[]'::jsonb));
  return result;
end; $$;
revoke execute on function public.scheduled_registration_release() from anon;

do $$
begin
  begin
    create extension if not exists pg_cron;
    if exists (select 1 from pg_extension where extname = 'pg_cron') then
      begin
        perform cron.unschedule('wdos-registration-safety-net');
      exception when others then null;
      end;
      perform cron.schedule('wdos-registration-safety-net', '*/15 * * * *',
        $cron$select public.scheduled_registration_release()$cron$);
    end if;
  exception when others then
    raise notice 'pg_cron unavailable \u2014 run scheduled_registration_release() manually every so often';
  end;
end $$;

-- release anyone stuck right now, immediately, and show the result
select public.scheduled_registration_release();

-- confirm the switch that governs instant approval is actually on
select value as auto_approve_volunteers_is
  from org_settings where key = 'auto_approve_volunteers';

insert into public.schema_migrations (version, name)
values (83, 'registration_safety_net') on conflict (version) do nothing;
