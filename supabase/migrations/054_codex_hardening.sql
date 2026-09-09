-- ============================================================================
-- WDOS Migration 054 — Codex audit hardening (Phase 66)
-- Tighten execute grants on the analytics helper functions so nothing is
-- callable by anonymous visitors. (The HQ-only checks inside the main
-- RPCs already guard data; this closes the perimeter fully.)
-- ============================================================================
revoke execute on function public.unit_in_country(uuid, char) from public, anon;
revoke execute on function public.unit_country_name(uuid) from public, anon;
grant execute on function public.unit_in_country(uuid, char) to authenticated;
grant execute on function public.unit_country_name(uuid) to authenticated;

insert into public.schema_migrations (version, name)
values (54, 'codex_hardening') on conflict (version) do nothing;
