-- ============================================================================
-- WDOS Migration 010 — Module Access (controlled from Headquarters)
-- Which modules each role can open is DATA, editable by HQ in Settings —
-- not code. Members with no leadership role get the 'member' baseline.
-- Note: data visibility was always enforced by RLS; this governs which
-- workspaces (modules) each role is given at all.
-- ============================================================================

create table public.module_access (
  role   public.role_code not null,
  module text not null check (module in (
    'members','recruitment','organisation','tasks','meetings',
    'reports','announcements','settings'
  )),
  primary key (role, module)
);

create trigger module_access_audit after insert or update or delete
  on public.module_access for each row execute function public.audit_row();

alter table public.module_access enable row level security;

create policy module_access_read on public.module_access
  for select to authenticated using (true);

create policy module_access_write on public.module_access
  for all to authenticated
  using (public.has_role(array['super_admin','executive_director']::public.role_code[]))
  with check (public.has_role(array['super_admin','executive_director']::public.role_code[]));

-- ---------------------------------------------------------------------------
-- Defaults: HQ = full cockpit; field leadership = the work HQ sends them;
-- volunteers/members = their own tasks, meetings, announcements.
-- All of this is editable in Settings afterwards.
-- ---------------------------------------------------------------------------
insert into public.module_access (role, module)
select r::public.role_code, m from
unnest(array['super_admin','executive_director','hq_team']) as r,
unnest(array['members','recruitment','organisation','tasks',
  'meetings','reports','announcements']) as m
on conflict do nothing;

-- Settings itself: top two roles only by default.
insert into public.module_access (role, module) values
  ('super_admin', 'settings'),
  ('executive_director', 'settings')
on conflict do nothing;

-- Field leadership: tasks, meetings, announcements, recruitment.
insert into public.module_access (role, module)
select r::public.role_code, m from
unnest(array['country_rep','deputy_country_rep','state_coordinator',
  'assistant_state_coordinator','district_coordinator','chapter_lead']) as r,
unnest(array['tasks','meetings','announcements','recruitment']) as m
on conflict do nothing;

-- Volunteers, members, programme staff: personal workspace only.
insert into public.module_access (role, module)
select r::public.role_code, m from
unnest(array['volunteer','member','programme_staff']) as r,
unnest(array['tasks','meetings','announcements']) as m
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- What can the current user open? Union across their active roles;
-- no active role = the 'member' baseline.
-- ---------------------------------------------------------------------------
create or replace function public.my_modules()
returns setof text
language plpgsql stable security definer set search_path = public as $$
declare my_roles public.role_code[];
begin
  select coalesce(array_agg(distinct role), '{}')
    into my_roles
    from role_assignments
   where profile_id = auth.uid() and ends_at is null;
  if coalesce(array_length(my_roles, 1), 0) = 0 then
    my_roles := array['member']::public.role_code[];
  end if;
  return query
    select distinct ma.module from module_access ma
    where ma.role = any(my_roles);
end; $$;
