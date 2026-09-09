-- ============================================================================
-- WDOS Migration 009 — Announcements (Communication Hub v1)
-- Leaders post to a unit; everyone whose home unit is in that unit's
-- subtree can read. Read receipts give posters real reach numbers.
-- ============================================================================

create type public.announcement_priority as enum ('normal', 'important', 'urgent');

create table public.announcements (
  id          uuid primary key default gen_random_uuid(),
  title       text not null check (char_length(title) between 3 and 160),
  body        text not null check (char_length(body) between 1 and 8000),
  org_unit_id uuid not null references public.org_units(id) on delete restrict,
  network     public.network_code,          -- null = both networks
  priority    public.announcement_priority not null default 'normal',
  author_id   uuid not null references public.profiles(id) default auth.uid(),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index announcements_unit_idx on public.announcements (org_unit_id, created_at desc);

create table public.announcement_reads (
  announcement_id uuid not null references public.announcements(id) on delete cascade,
  profile_id      uuid not null references public.profiles(id) on delete cascade,
  read_at         timestamptz not null default now(),
  primary key (announcement_id, profile_id)
);

create trigger announcements_touch before update on public.announcements
  for each row execute function public.touch_updated_at();
create trigger announcements_audit after insert or update or delete
  on public.announcements for each row execute function public.audit_row();

-- ---------------------------------------------------------------------------
-- Visibility helper: does the announcement's unit cover the viewer's home
-- unit (i.e. is the viewer inside its subtree)?
-- ---------------------------------------------------------------------------
create or replace function public.announcement_reaches_me(a public.announcements)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from profiles p
    where p.id = auth.uid()
      and p.org_unit_id in (select org_unit_subtree(a.org_unit_id))
      and (a.network is null or p.network = a.network)
  );
$$;

create or replace function public.is_announcement_manager(a public.announcements)
returns boolean language sql stable security definer set search_path = public as $$
  select a.author_id = auth.uid()
      or a.org_unit_id in (select administered_units())
      or has_role(array['super_admin','executive_director','hq_team']::public.role_code[]);
$$;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
alter table public.announcements     enable row level security;
alter table public.announcement_reads enable row level security;

create policy announcements_read on public.announcements
  for select to authenticated
  using (public.announcement_reaches_me(announcements)
         or public.is_announcement_manager(announcements));

create policy announcements_insert on public.announcements
  for insert to authenticated
  with check (
    author_id = auth.uid()
    and (org_unit_id in (select public.administered_units())
         or public.has_role(array['super_admin','executive_director','hq_team']::public.role_code[]))
  );

create policy announcements_update on public.announcements
  for update to authenticated
  using (public.is_announcement_manager(announcements))
  with check (public.is_announcement_manager(announcements));

-- Reads: I may record and see my own receipt; managers see all receipts
-- for their announcements (for reach counts).
create policy reads_self_insert on public.announcement_reads
  for insert to authenticated
  with check (profile_id = auth.uid());
create policy reads_visible on public.announcement_reads
  for select to authenticated
  using (
    profile_id = auth.uid()
    or exists (select 1 from public.announcements a
               where a.id = announcement_id
                 and public.is_announcement_manager(a))
  );

-- ---------------------------------------------------------------------------
-- Reach counts for managers: audience size + reads per announcement
-- ---------------------------------------------------------------------------
create or replace function public.announcement_reach(ann_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare a public.announcements; result jsonb;
begin
  select * into a from announcements where id = ann_id;
  if a.id is null or not is_announcement_manager(a) then
    raise exception 'Not available';
  end if;
  select jsonb_build_object(
    'audience', (
      select count(*) from profiles p
      where p.org_unit_id in (select org_unit_subtree(a.org_unit_id))
        and (a.network is null or p.network = a.network)
        and p.status in ('activated','in_training','active','reinstated')
    ),
    'reads', (
      select count(*) from announcement_reads r
      where r.announcement_id = ann_id
    )
  ) into result;
  return result;
end; $$;
