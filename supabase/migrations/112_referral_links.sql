-- ============================================================================
-- WDOS Migration 112 — REFERRAL LINKS (Phase 136)
--   Every link is a short code: https://woddicrm.org/#/r/<code>
--   • HQ creates campaign links (any network, country, unit, position).
--   • A volunteer leader gets a link for each VACANT seat under her (by
--     position, location, network) and one general membership link.
--   • Each visit is recorded (when, where the visitor came from, language,
--     time zone, device) and the code is kept on the visitor's device so
--     the application or registration she submits is stamped with it.
--   • The leader sees who came through her links; HQ sees every link, its
--     owner, and who referred whom, with the person's location and status.
--   A referral never appoints anyone: it only records the source.
-- ============================================================================

create table if not exists public.referral_links (
  id          uuid primary key default gen_random_uuid(),
  code        text unique,
  owner_id    uuid references public.profiles(id) on delete set null,   -- null = Headquarters
  created_by  uuid references public.profiles(id) on delete set null default auth.uid(),
  network     public.network_code,
  org_unit_id uuid references public.org_units(id) on delete set null,
  role        public.role_code,                                            -- null = membership / general
  label       text check (label is null or char_length(label) <= 120),
  campaign    text check (campaign is null or char_length(campaign) <= 120),
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);
create index if not exists referral_links_owner_idx on public.referral_links (owner_id);

create or replace function public.referral_links_code()
returns trigger language plpgsql security definer set search_path = public as $$
declare alphabet text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'; c text; i int;
begin
  if new.code is null then
    loop
      c := '';
      for i in 1..8 loop c := c || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1); end loop;
      exit when not exists (select 1 from referral_links where code = c);
    end loop;
    new.code := c;
  end if;
  return new;
end; $$;
drop trigger if exists referral_links_code on public.referral_links;
create trigger referral_links_code before insert on public.referral_links
  for each row execute function public.referral_links_code();

alter table public.referral_links enable row level security;
drop policy if exists referral_links_read on public.referral_links;
create policy referral_links_read on public.referral_links for select to authenticated
  using (owner_id = auth.uid() or public.is_case_hq()
         or (org_unit_id is not null and org_unit_id in (select public.administered_units())));

create table if not exists public.referral_visits (
  id            uuid primary key default gen_random_uuid(),
  link_id       uuid not null references public.referral_links(id) on delete cascade,
  code          text not null,
  visited_at    timestamptz not null default now(),
  referrer_host text,
  user_agent    text,
  lang          text,
  tz            text,
  screen        text
);
create index if not exists referral_visits_link_idx on public.referral_visits (link_id, visited_at desc);
alter table public.referral_visits enable row level security;
drop policy if exists referral_visits_read on public.referral_visits;
create policy referral_visits_read on public.referral_visits for select to authenticated
  using (exists (select 1 from referral_links l where l.id = link_id
                  and (l.owner_id = auth.uid() or public.is_case_hq()
                       or (l.org_unit_id is not null and l.org_unit_id in (select public.administered_units())))));

alter table public.applications add column if not exists referral_code text;
alter table public.applications add column if not exists referral_visit_id uuid references public.referral_visits(id) on delete set null;
alter table public.profiles add column if not exists referral_code text;
create index if not exists applications_referral_idx on public.applications (referral_code);
create index if not exists profiles_referral_idx on public.profiles (referral_code);

-- ---------------------------------------------------------------------------
-- Public: a visitor opens #/r/<code>. Records the visit and returns what the
-- landing page needs (never any personal data of the owner beyond a name).
-- ---------------------------------------------------------------------------
create or replace function public.referral_visit(p_code text, meta jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare l referral_links%rowtype; vid uuid; chain jsonb; owner text;
begin
  select * into l from referral_links where upper(code) = upper(trim(p_code)) and active;
  if not found then return jsonb_build_object('ok', false); end if;
  insert into referral_visits (link_id, code, referrer_host, user_agent, lang, tz, screen)
  values (l.id, l.code, left(meta->>'referrer', 200), left(meta->>'ua', 300), left(meta->>'lang', 20),
          left(meta->>'tz', 60), left(meta->>'screen', 20))
  returning id into vid;
  select coalesce(jsonb_agg(jsonb_build_object('level', c.level, 'name', c.name) order by c.depth desc), '[]'::jsonb)
    into chain from unit_chain(l.org_unit_id) c where c.level <> 'headquarters';
  select first_name || ' ' || last_name into owner from profiles where id = l.owner_id;
  return jsonb_build_object('ok', true, 'visit_id', vid, 'code', l.code, 'network', l.network,
    'role', l.role, 'unit_id', l.org_unit_id, 'chain', chain, 'label', l.label,
    'owner', coalesce(owner, 'WODDI Headquarters'), 'door', case when l.role is null then 'volunteer' else 'apply' end);
end; $$;
grant execute on function public.referral_visit(text, jsonb) to anon, authenticated;

-- Public: after a door submission, stamp the newest record for that email
-- (created in the last 2 hours) with the code the device holds.
create or replace function public.referral_attach(p_code text, p_email text, p_visit uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare l referral_links%rowtype; a int := 0; p int := 0;
begin
  select * into l from referral_links where upper(code) = upper(trim(p_code)) and active;
  if not found then return jsonb_build_object('ok', false); end if;
  update applications set referral_code = l.code, referral_visit_id = coalesce(p_visit, referral_visit_id)
   where lower(email) = lower(trim(p_email)) and referral_code is null
     and created_at > now() - interval '2 hours';
  get diagnostics a = row_count;
  update profiles set referral_code = l.code
   where lower(email) = lower(trim(p_email)) and referral_code is null
     and created_at > now() - interval '2 hours';
  get diagnostics p = row_count;
  return jsonb_build_object('ok', true, 'applications', a, 'profiles', p);
end; $$;
grant execute on function public.referral_attach(text, text, uuid) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Leaders and HQ: get or create a link for a target (leaders only within
-- their administered scope; HQ anywhere). One link per owner+target.
-- ---------------------------------------------------------------------------
create or replace function public.referral_link_ensure(p_network text, p_unit uuid default null,
                                                       p_role public.role_code default null,
                                                       p_label text default null, p_campaign text default null,
                                                       p_hq boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); net public.network_code; owner uuid; l referral_links%rowtype;
begin
  if me is null then raise exception 'Not signed in'; end if;
  net := nullif(upper(coalesce(p_network, '')), '')::public.network_code;
  if p_hq then
    if not is_case_hq() then raise exception 'HQ only'; end if;
    owner := null;
  else
    owner := me;
    if p_unit is not null and not (is_case_hq() or p_unit in (select administered_units())) then
      raise exception 'That unit is outside your leadership scope';
    end if;
    if p_unit is null then select org_unit_id into p_unit from report_unit_for(me); end if;
    if net is null then select network into net from profiles where id = me; end if;
  end if;
  select * into l from referral_links
   where owner_id is not distinct from owner and network is not distinct from net
     and org_unit_id is not distinct from p_unit and role is not distinct from p_role
     and campaign is not distinct from p_campaign and active
   limit 1;
  if not found then
    insert into referral_links (owner_id, network, org_unit_id, role, label, campaign)
    values (owner, net, p_unit, p_role, left(p_label, 120), left(p_campaign, 120)) returning * into l;
  end if;
  return to_jsonb(l);
end; $$;
revoke execute on function public.referral_link_ensure(text, uuid, public.role_code, text, text, boolean) from anon;

-- Overview: my links (or every link for HQ) with counts, plus the people who came
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
               'network', a.network, 'location', concat_ws(' / ', a.country, a.state_region, a.lga,
                 (select name from org_units where id = a.org_unit_id)),
               'position', a.role_applied, 'status', a.status::text, 'at', a.created_at, 'code', a.referral_code,
               'referred_by', coalesce((select first_name || ' ' || last_name from profiles where id = l.owner_id), 'WODDI HQ'),
               'came_from', (select v.referrer_host from referral_visits v where v.id = a.referral_visit_id)) as x
        from applications a join referral_links l on l.code = a.referral_code
       where hq or l.owner_id = me or (l.org_unit_id is not null and l.org_unit_id in (select administered_units()))
      union all
      select jsonb_build_object('kind', 'member', 'name', p.first_name || ' ' || p.last_name, 'email', p.email,
               'network', p.network, 'location', concat_ws(' / ', p.country, p.state_region, p.lga),
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

create or replace function public.referral_link_toggle(p_id uuid, p_active boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  update referral_links set active = p_active
   where id = p_id and (is_case_hq() or owner_id = auth.uid());
end; $$;
revoke execute on function public.referral_link_toggle(uuid, boolean) from anon;

insert into public.schema_migrations (version, name)
values (112, 'referral_links') on conflict (version) do nothing;
