-- ============================================================================
-- WDOS Migration 055 — Codex Round-2 Security (Phase 67)
-- 1. meeting_join now verifies the caller may actually attend (audience/
--    organiser/HQ) instead of accepting any UUID.
-- 2. Check-ins and meeting files readable only by people connected to the
--    meeting (HQ, organiser, attendees) — not the whole org.
-- 3. Secrets vault: the AI key moves out of world-readable org_settings
--    into org_secrets (no direct SELECT); read via definer RPC. Note for
--    the record: client-side AI calls necessarily reveal the key to the
--    browser making them — full secrecy needs a server proxy (roadmap);
--    this closes casual listing/anon exposure.
-- ============================================================================

-- 1 ▸ guarded join
create or replace function public.can_attend_meeting(mid uuid, uid uuid)
returns boolean language sql stable
security definer set search_path = public as $$
  select exists (
    select 1 from meetings m
     where m.id = mid
       and (
         m.organiser = uid
         or is_case_hq()
         or exists (select 1 from staff s
                     where s.profile_id = uid and s.is_active
                       and m.audience in ('hq','all'))
         or exists (select 1 from profiles p
                     where p.id = uid and (
                       (m.audience = 'unit' and p.org_unit_id = m.org_unit_id)
                       or (m.audience in ('wgmn_ng','wgmn_all')
                           and p.network = 'WGMN'
                           and (m.audience = 'wgmn_all'
                                or unit_in_country(p.org_unit_id, 'NG')))
                       or (m.audience in ('wnnn_ng','wnnn_all')
                           and p.network = 'WNNN'
                           and (m.audience = 'wnnn_all'
                                or unit_in_country(p.org_unit_id, 'NG')))
                       or m.audience = 'all'
                     ))
       ));
$$;
revoke execute on function public.can_attend_meeting(uuid, uuid)
  from public, anon;

create or replace function public.meeting_join(mid uuid)
returns void language plpgsql
security definer set search_path = public as $$
begin
  if not can_attend_meeting(mid, auth.uid()) then
    raise exception 'You are not on this meeting''s invitation list.';
  end if;
  insert into meeting_checkins (meeting_id, profile_id)
  values (mid, auth.uid())
  on conflict (meeting_id, profile_id) do nothing;
end; $$;
grant execute on function public.meeting_join(uuid) to authenticated;
revoke execute on function public.meeting_join(uuid) from anon, public;

-- 2 ▸ scoped visibility
drop policy if exists checkins_read on public.meeting_checkins;
create policy checkins_read on public.meeting_checkins
  for select to authenticated
  using ( can_attend_meeting(meeting_id, auth.uid()) );

drop policy if exists meeting_files_read on public.meeting_files;
create policy meeting_files_read on public.meeting_files
  for select to authenticated
  using ( can_attend_meeting(meeting_id, auth.uid()) );

drop policy if exists meeting_files_write on public.meeting_files;
create policy meeting_files_write on public.meeting_files
  for insert to authenticated
  with check ( uploaded_by = auth.uid()
               and can_attend_meeting(meeting_id, auth.uid()) );

-- 3 ▸ secrets vault
create table if not exists public.org_secrets (
  key   text primary key,
  value text not null,
  updated_at timestamptz not null default now()
);
alter table public.org_secrets enable row level security;
-- no select/insert/update policies: only definer RPCs may touch it

create or replace function public.set_ai_token(tok text)
returns void language plpgsql
security definer set search_path = public as $$
begin
  if not is_case_hq() then raise exception 'HQ only'; end if;
  insert into org_secrets (key, value) values ('hf_token', coalesce(tok, ''))
  on conflict (key) do update
    set value = excluded.value, updated_at = now();
end; $$;
grant execute on function public.set_ai_token(text) to authenticated;
revoke execute on function public.set_ai_token(text) from anon, public;

create or replace function public.get_ai_token()
returns text language sql stable
security definer set search_path = public as $$
  select coalesce((select value from org_secrets where key = 'hf_token'),
                  (select value #>> '{}' from org_settings
                    where key = 'hf_tts_token'), '');
$$;
grant execute on function public.get_ai_token() to authenticated;
revoke execute on function public.get_ai_token() from anon, public;

-- migrate any existing key into the vault, then blank the public copy
insert into public.org_secrets (key, value)
select 'hf_token', value #>> '{}'
  from public.org_settings where key = 'hf_tts_token'
    and coalesce(value #>> '{}', '') <> ''
on conflict (key) do nothing;
update public.org_settings set value = '""'::jsonb
 where key = 'hf_tts_token';

insert into public.schema_migrations (version, name)
values (55, 'codex_round2_security') on conflict (version) do nothing;
