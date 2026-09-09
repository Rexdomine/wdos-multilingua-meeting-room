-- ============================================================================
-- WDOS Migration 097 — Free-tier relief (Phase 109)
--
-- Members are seeing intermittent "Could not load this view" under load
-- on the free NANO instance. Until the paid tier is approved, this cuts
-- background pressure: the registration safety-net sweep drops from
-- every 15 minutes to every 30 (it is a safety net; a 30-minute
-- worst-case release delay is acceptable, and the bug it guarded
-- against was fixed weeks ago). The app side of this release adds a
-- quiet automatic retry for reads and calms the Reports live poll.
-- ============================================================================

do $$
begin
  if exists (select 1 from cron.job where jobname = 'wdos-registration-safety-net') then
    perform cron.unschedule('wdos-registration-safety-net');
  end if;
  perform cron.schedule('wdos-registration-safety-net', '*/30 * * * *',
    $job$ select scheduled_registration_release(); $job$);
end $$;

insert into public.schema_migrations (version, name)
values (97, 'free_tier_relief') on conflict (version) do nothing;
