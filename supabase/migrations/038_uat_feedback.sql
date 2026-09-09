-- ============================================================================
-- WDOS Migration 038 — UAT Feedback & Issue Register (Phase 43)
--
-- The testing brief's feedback format, built into WDOS itself. Every tester
-- records observations in-app (where, role tested, device, exact steps, the
-- precise error wording, what was expected, severity, result) with optional
-- screenshot evidence. HQ gets a live Issue Register with triage status and
-- notes. BLOCKER submissions immediately message HQ executives through the
-- normal inbox (bell + sound + browser + email if enabled) — the brief's
-- "report critical issues immediately" rule, automated.
-- ============================================================================

create table public.uat_feedback (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles(id) default auth.uid(),
  track text not null default 'A',           -- A..G per the brief
  location_text text not null,               -- exact page / module / section
  role_tested text not null default '',
  device_browser text not null default '',
  steps text not null,                        -- what you did
  observed text not null,                     -- what happened (exact error words)
  expected text not null default '',          -- what you expected
  severity text not null default 'medium'
    check (severity in ('blocker','high','medium','low','suggestion')),
  result text not null default 'failed'
    check (result in ('passed','failed','partial','not_available',
                      'unable','needs_clarification')),
  evidence_note text not null default '',
  triage_status text not null default 'new'
    check (triage_status in ('new','accepted','in_progress','fixed',
                             'retest','closed','duplicate','deferred')),
  hq_notes text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index uat_feedback_triage_idx
  on public.uat_feedback (triage_status, severity, created_at desc);
create index uat_feedback_reporter_idx
  on public.uat_feedback (reporter_id, created_at desc);

create trigger uat_feedback_touch before update on public.uat_feedback
  for each row execute function public.touch_updated_at();
create trigger uat_feedback_audit after insert or update or delete
  on public.uat_feedback for each row execute function public.audit_row();

alter table public.uat_feedback enable row level security;
create policy uat_insert_own on public.uat_feedback
  for insert to authenticated with check (reporter_id = auth.uid());
create policy uat_read on public.uat_feedback
  for select to authenticated
  using (reporter_id = auth.uid() or public.is_case_hq());
create policy uat_edit_own_new on public.uat_feedback
  for update to authenticated
  using (reporter_id = auth.uid() and triage_status = 'new')
  with check (reporter_id = auth.uid());
create policy uat_hq_manage on public.uat_feedback
  for update to authenticated
  using (public.is_case_hq()) with check (public.is_case_hq());

-- ---------------------------------------------------------------------------
-- Evidence bucket — screenshots, private. Objects live under the uploader's
-- own id: <auth.uid()>/<filename>. Readable by the uploader and HQ.
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('uat-evidence', 'uat-evidence', false)
on conflict (id) do nothing;

drop policy if exists uat_ev_insert on storage.objects;
create policy uat_ev_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'uat-evidence'
    and split_part(name, '/', 1) = auth.uid()::text);

drop policy if exists uat_ev_select on storage.objects;
create policy uat_ev_select on storage.objects
  for select to authenticated
  using (bucket_id = 'uat-evidence'
    and (split_part(name, '/', 1) = auth.uid()::text or public.is_case_hq()));

-- ---------------------------------------------------------------------------
-- BLOCKER alert — the "report immediately" rule, automated.
-- ---------------------------------------------------------------------------
create or replace function public.uat_blocker_alert()
returns trigger
language plpgsql security definer set search_path = public as $$
declare hq uuid[]; sys uuid; nm text;
begin
  if new.severity <> 'blocker' then return new; end if;
  select array_agg(distinct ra.profile_id) into hq
    from role_assignments ra
   where ra.role in ('super_admin','executive_director','hq_team');
  if hq is null then return new; end if;
  sys := hq[1];
  select first_name || ' ' || last_name into nm
    from profiles where id = new.reporter_id;
  insert into staff_messages (sender_id, recipient_id, body)
  select sys, p,
    '[UAT BLOCKER] ' || coalesce(nm,'A tester') || ' reports at "'
    || new.location_text || '": ' || left(new.observed, 500)
    || ' — open Test Feedback to triage.'
    from unnest(hq) as p where p <> sys;
  return new;
end; $$;

create trigger uat_blocker_notify after insert on public.uat_feedback
  for each row execute function public.uat_blocker_alert();

-- ---------------------------------------------------------------------------
-- Register summary for HQ
-- ---------------------------------------------------------------------------
create or replace function public.uat_summary()
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not is_case_hq() then raise exception 'HQ only'; end if;
  return jsonb_build_object(
    'total', (select count(*) from uat_feedback),
    'open_blockers', (select count(*) from uat_feedback
       where severity = 'blocker' and triage_status not in ('closed','duplicate')),
    'by_severity', (select coalesce(jsonb_object_agg(s.severity, s.n), '{}'::jsonb)
       from (select severity, count(*) n from uat_feedback group by severity) s),
    'by_status', (select coalesce(jsonb_object_agg(s.triage_status, s.n), '{}'::jsonb)
       from (select triage_status, count(*) n from uat_feedback group by triage_status) s),
    'by_track', (select coalesce(jsonb_object_agg(s.track, s.n), '{}'::jsonb)
       from (select track, count(*) n from uat_feedback group by track) s));
end; $$;

insert into public.schema_migrations (version, name)
values (38, 'uat_feedback') on conflict (version) do nothing;
