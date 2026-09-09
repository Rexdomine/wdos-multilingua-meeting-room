-- ============================================================================
-- WDOS Migration 026 — Pan-African Structure v1
-- The five African subregions; the 25 covered countries seeded with their
-- ISO codes and subregions; each country's OFFICIAL local terminology for
-- its administrative levels (displayed instead of "State"/"LGA"); and
-- Nigeria's 36 states + FCT as the first full first-level dataset.
-- Deeper divisions are created by leaders/HQ in the app using each
-- country's own terms. Tree, RLS, and all workflows unchanged.
-- ============================================================================

create table public.subregions (
  id   uuid primary key default gen_random_uuid(),
  code text not null unique
    check (code in ('west','east','central','southern','north')),
  name text not null
);

insert into public.subregions (code, name) values
  ('west', 'West Africa'), ('east', 'East Africa'),
  ('central', 'Central Africa'), ('southern', 'Southern Africa'),
  ('north', 'North Africa')
on conflict (code) do nothing;

alter table public.org_units
  add column if not exists subregion_id uuid references public.subregions(id);

alter table public.subregions enable row level security;
create policy subregions_read on public.subregions
  for select to anon, authenticated using (true);
create policy subregions_manage on public.subregions
  for all to authenticated
  using (public.is_case_hq()) with check (public.is_case_hq());

-- Local terminology per country per level slot.
create table public.country_level_names (
  country_id uuid not null references public.org_units(id) on delete cascade,
  level      public.org_level not null,
  local_name text not null check (char_length(local_name) between 2 and 60),
  primary key (country_id, level)
);

alter table public.country_level_names enable row level security;
create policy level_names_read on public.country_level_names
  for select to anon, authenticated using (true);
create policy level_names_manage on public.country_level_names
  for all to authenticated
  using (public.is_case_hq()) with check (public.is_case_hq());

-- ---------------------------------------------------------------------------
-- Seed the 25 covered countries (idempotent by ISO code)
-- ---------------------------------------------------------------------------
do $$
declare
  hq uuid;
  r record;
  cid uuid;
  sid uuid;
begin
  select id into hq from org_units where level = 'headquarters';

  for r in select * from (values
    ('BJ','Benin','west','Department','Commune'),
    ('BF','Burkina Faso','west','Region','Province'),
    ('BI','Burundi','east','Province','Commune'),
    ('CM','Cameroon','central','Region','Division'),
    ('CF','Central African Republic','central','Prefecture','Sub-prefecture'),
    ('TD','Chad','central','Province','Department'),
    ('CI','Côte d''Ivoire','west','Region','Department'),
    ('CD','Democratic Republic of the Congo','central','Province','Territory'),
    ('CG','Republic of the Congo','central','Department','District'),
    ('GM','The Gambia','west','Region','District'),
    ('GH','Ghana','west','Region','District'),
    ('GN','Guinea','west','Region','Prefecture'),
    ('GW','Guinea-Bissau','west','Region','Sector'),
    ('KE','Kenya','east','County','Subcounty'),
    ('MG','Madagascar','east','Region','District'),
    ('ML','Mali','west','Region','Cercle'),
    ('MA','Morocco','north','Region','Province'),
    ('NE','Niger','west','Region','Department'),
    ('NG','Nigeria','west','State','Local Government Area'),
    ('RW','Rwanda','east','Province','District'),
    ('SN','Senegal','west','Region','Department'),
    ('ZA','South Africa','southern','Province','District Municipality'),
    ('TG','Togo','west','Region','Prefecture'),
    ('TN','Tunisia','north','Governorate','Delegation'),
    ('UG','Uganda','east','Region','District')
  ) as c(iso, cname, sub, lvl1, lvl2)
  loop
    select id into sid from subregions where code = r.sub;

    select id into cid from org_units
      where level = 'country' and country_iso = r.iso;
    if cid is null then
      insert into org_units (parent_id, level, name, country_iso, subregion_id)
      values (hq, 'country', r.cname, r.iso, sid)
      returning id into cid;
    else
      update org_units set subregion_id = sid where id = cid;
    end if;

    insert into country_level_names (country_id, level, local_name) values
      (cid, 'state_region', r.lvl1),
      (cid, 'district_lga', r.lvl2)
    on conflict (country_id, level) do update
      set local_name = excluded.local_name;
  end loop;

  -- Nigeria: all 36 states + FCT (idempotent per name).
  select id into cid from org_units
    where level = 'country' and country_iso = 'NG';
  for r in select * from unnest(array[
    'Abia','Adamawa','Akwa Ibom','Anambra','Bauchi','Bayelsa','Benue',
    'Borno','Cross River','Delta','Ebonyi','Edo','Ekiti','Enugu','Gombe',
    'Imo','Jigawa','Kaduna','Kano','Katsina','Kebbi','Kogi','Kwara',
    'Lagos','Nasarawa','Niger','Ogun','Ondo','Osun','Oyo','Plateau',
    'Rivers','Sokoto','Taraba','Yobe','Zamfara',
    'Federal Capital Territory'
  ]) as s(sname)
  loop
    if not exists (select 1 from org_units
                   where parent_id = cid and level = 'state_region'
                     and name = r.sname) then
      insert into org_units (parent_id, level, name, country_iso)
      values (cid, 'state_region', r.sname, 'NG');
    end if;
  end loop;
end $$;

insert into public.schema_migrations (version, name)
values (26, 'pan_african_structure') on conflict (version) do nothing;
