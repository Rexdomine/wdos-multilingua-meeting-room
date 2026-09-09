-- ============================================================================
-- WDOS Migration 047 — WODDI Rooms: ring the network (Phase 51)
--
-- Group calls live at #/room (Jitsi Meet embedded inside WDOS — free,
-- open-source, no accounts needed to join). This migration adds the
-- surprise: announce_group_call() lets HQ ring everyone at once — a
-- personal notice lands instantly in the chosen audience's bell (chirp,
-- browser popup, and email when enabled): "Group call starting now."
-- Audiences: 'staff' (HQ operations) or 'all' (staff + active volunteer
-- leadership family).
-- ============================================================================

create or replace function public.announce_group_call(room text, aud text)
returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not is_case_hq() then raise exception 'HQ only'; end if;
  if room is null or length(trim(room)) < 3 then
    raise exception 'Room name required';
  end if;
  if aud not in ('staff','all') then
    raise exception 'Audience must be staff or all';
  end if;

  insert into member_notices (profile_id, kind, title, body, meta)
  select p.id, 'meeting',
    'Group call starting now',
    'WODDI is gathering live. Open Meeting Room in WDOS and join the room: '
      || room || e'\nSee you inside!',
    jsonb_build_object('call', room)
    from profiles p
   where p.merged_into is null
     and p.id <> auth.uid()
     and (
       exists (select 1 from staff s
                where s.profile_id = p.id and s.is_active)
       or (aud = 'all'
           and p.status in ('approved','activated','in_training',
                            'active','reinstated'))
     )
   limit 500;
  get diagnostics n = row_count;
  return n;
end; $$;

revoke execute on function public.announce_group_call(text, text) from anon;

insert into public.schema_migrations (version, name)
values (47, 'woddi_rooms') on conflict (version) do nothing;
