-- ============================================================================
-- WDOS Migration 029 — Institute Volunteer Bridge (Phase 32)
-- The Institute form keeps its own database untouched; it ALSO posts here.
-- Full submission preserved in payload; approval copies into the main
-- applications pipeline so accounts + 14-day journeys fire as usual.
-- ============================================================================
create table public.volunteer_applications (
  id uuid primary key default gen_random_uuid(),
  full_name text not null default '',
  email text not null,
  phone text, network public.network_code, country text,
  payload jsonb not null default '{}'::jsonb,
  status public.application_status not null default 'submitted',
  decided_by uuid references public.profiles(id),
  decision_reason text, decided_at timestamptz,
  created_at timestamptz not null default now()
);
create index vol_apps_status_idx on public.volunteer_applications (status, created_at desc);
create trigger vol_apps_audit after insert or update or delete
  on public.volunteer_applications for each row execute function public.audit_row();
alter table public.volunteer_applications enable row level security;
create policy vol_apps_insert on public.volunteer_applications
  for insert to anon, authenticated
  with check (status = 'submitted' and decided_by is null);
create policy vol_apps_read on public.volunteer_applications
  for select to authenticated using (public.is_case_hq()
    or public.my_rank_over_any() );
-- helper: any leadership rank at all
create or replace function public.my_rank_over_any()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from role_assignments
    where profile_id = auth.uid() and ends_at is null
      and role in ('country_rep','deputy_country_rep','state_coordinator',
        'assistant_state_coordinator','district_coordinator','chapter_lead'));
$$;
create or replace function public.decide_volunteer(
  vid uuid, approve boolean, unit uuid, reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v public.volunteer_applications;
begin
  if not (is_case_hq() or exists (select 1 from role_assignments
     where profile_id = auth.uid() and ends_at is null
       and role in ('super_admin','executive_director','hq_team',
         'country_rep','state_coordinator'))) then
    raise exception 'Not authorised to decide volunteer applications';
  end if;
  select * into v from volunteer_applications where id = vid for update;
  if v.id is null then raise exception 'Not found'; end if;
  if v.status not in ('submitted','under_review') then
    raise exception 'Already decided';
  end if;
  if reason is null or char_length(trim(reason)) < 5 then
    raise exception 'A reason is required';
  end if;
  update volunteer_applications
     set status = case when approve then 'approved' else 'rejected' end,
         decided_by = auth.uid(), decision_reason = reason,
         decided_at = now()
   where id = vid;
  if approve then
    insert into applications (first_name, last_name, email, phone, network,
      org_unit_id, motivation, status, decided_by, decision_reason, decided_at)
    values (
      coalesce(nullif(split_part(v.full_name,' ',1),''),'Volunteer'),
      coalesce(nullif(trim(substr(v.full_name, length(split_part(v.full_name,' ',1))+1)),''),'-'),
      v.email, v.phone, coalesce(v.network,'WGMN'), unit,
      coalesce(v.payload->>'why','Volunteer application (Institute)'),
      'approved', auth.uid(), reason, now());
  end if;
end; $$;
insert into public.schema_migrations (version, name)
values (29,'volunteer_bridge') on conflict (version) do nothing;
