-- ============================================================================
-- WDOS Migration 115 — referral_overview: applications have no text geography
-- (they carry the chosen unit); location now comes from the unit chain and
-- the position from the link. Fixes "column a.state_region does not exist".
-- -- redefines referral_overview
-- ============================================================================
create or replace function public.referral_overview(p_scope text default 'mine')
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare me uuid := auth.uid(); hq boolean := is_case_hq() and p_scope = 'hq';
begin
  if me is null then raise exception 'Not signed in'; end if;
  return jsonb_build_object(
    'links', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', l.id, 'code', l.code, 'owner_id', l.owner_id,
        'owner', coalesce((select first_name || ' ' || last_name from profiles where id = l.owner_id), 'WODDI HQ'),
        'network', l.network, 'unit', (select name from org_units where id = l.org_unit_id), 'unit_id', l.org_unit_id,
        'role', l.role, 'label', l.label, 'campaign', l.campaign, 'active', l.active, 'created_at', l.created_at,
        'visits', (select count(*) from referral_visits v where v.link_id = l.id),
        'applications', (select count(*) from applications a where a.referral_code = l.code),
        'members', (select count(*) from profiles p where p.referral_code = l.code))
        order by l.created_at desc), '[]'::jsonb)
      from referral_links l
      where hq or l.owner_id = me
         or (not hq and l.org_unit_id is not null and l.org_unit_id in (select administered_units()))),
    'people', (select coalesce(jsonb_agg(x order by x->>'at' desc), '[]'::jsonb) from (
      select jsonb_build_object('kind', 'application', 'name', a.first_name || ' ' || a.last_name, 'email', a.email,
               'network', a.network,
               'location', (select string_agg(c.name, ' / ' order by c.depth desc) from unit_chain(a.org_unit_id) c where c.level <> 'headquarters'),
               'country', coalesce(a.country, (select c.name from unit_chain(a.org_unit_id) c where c.level = 'country' limit 1)),
               'position', (select l2.role::text from referral_links l2 where l2.code = a.referral_code),
               'status', a.status::text, 'at', a.created_at, 'code', a.referral_code,
               'referred_by', coalesce((select first_name || ' ' || last_name from profiles where id = l.owner_id), 'WODDI HQ'),
               'came_from', (select v.referrer_host from referral_visits v where v.id = a.referral_visit_id)) as x
        from applications a join referral_links l on l.code = a.referral_code
       where hq or l.owner_id = me or (l.org_unit_id is not null and l.org_unit_id in (select administered_units()))
      union all
      select jsonb_build_object('kind', 'member', 'name', p.first_name || ' ' || p.last_name, 'email', p.email,
               'network', p.network, 'location', concat_ws(' / ', p.country, p.state_region, p.lga), 'country', p.country,
               'position', p.role_applied, 'status', p.status::text, 'at', p.created_at, 'code', p.referral_code,
               'referred_by', coalesce((select first_name || ' ' || last_name from profiles where id = l.owner_id), 'WODDI HQ'),
               'came_from', null) as x
        from profiles p join referral_links l on l.code = p.referral_code
       where p.merged_into is null
         and (hq or l.owner_id = me or (l.org_unit_id is not null and l.org_unit_id in (select administered_units())))
      ) s),
    'visits_30d', (select count(*) from referral_visits v join referral_links l on l.id = v.link_id
                    where v.visited_at > now() - interval '30 days'
                      and (hq or l.owner_id = me or (l.org_unit_id is not null and l.org_unit_id in (select administered_units())))),
    'generated_at', now());
end; $$;
revoke execute on function public.referral_overview(text) from anon;

insert into public.schema_migrations (version, name)
values (115, 'referral_overview_fix') on conflict (version) do nothing;
