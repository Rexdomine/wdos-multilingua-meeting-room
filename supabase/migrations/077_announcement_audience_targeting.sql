-- ============================================================================
-- WDOS Migration 077 — Announcements reach the right population (Phase 92)
-- Azeez: "mass message/announcement to volunteer leader applicants where
-- they all see it at the same time" — the ones going through the 14-day
-- activation, as a group, separate from the 43 established leaders.
--
-- Announcements were already scoped by org_unit subtree + network; this
-- adds a second, independent axis: WHICH POPULATION. Default 'all' keeps
-- every existing announcement behaving exactly as before.
-- ============================================================================

alter table public.announcements
  add column if not exists audience text not null default 'all'
    check (audience in ('all', 'leaders', 'intake'));

create or replace function public.announcement_reaches_me(a public.announcements)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from profiles p
    where p.id = auth.uid()
      and p.org_unit_id in (select org_unit_subtree(a.org_unit_id))
      and (a.network is null or p.network = a.network)
      and (a.audience = 'all'
           or (a.audience = 'leaders' and is_established(p.id))
           or (a.audience = 'intake' and not is_established(p.id)))
  );
$$;

insert into public.schema_migrations (version, name)
values (77, 'announcement_audience_targeting') on conflict (version) do nothing;
