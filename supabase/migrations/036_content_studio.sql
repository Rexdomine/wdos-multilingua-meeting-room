-- ============================================================================
-- WDOS Migration 036 — Content Studio module (Phase 40)
--
-- Registers the 'content' module so HQ can grant it in the Settings matrix.
-- The Studio itself is pure app: HQ manage-policies on activation_days/items/
-- keys (030), engagement_content (030) and courses/modules/questions/keys
-- (033) already authorise every edit it makes. This delivers the governance
-- principle from the UAT review: curriculum content and scoring belong to
-- WODDI's content team, not to IT.
-- ============================================================================

alter table public.module_access drop constraint module_access_module_check;
alter table public.module_access add constraint module_access_module_check
  check (module in (
    'members','recruitment','organisation','tasks','meetings','reports',
    'announcements','settings','programmes','cases','helpdesk','hq',
    'library','documents','content'
  ));

insert into public.module_access (role, module) values
  ('super_admin','content'),
  ('executive_director','content'),
  ('hq_team','content')
on conflict do nothing;

insert into public.schema_migrations (version, name)
values (36, 'content_studio') on conflict (version) do nothing;
