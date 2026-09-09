-- ============================================================================
-- WDOS Migration 028 — THE Helpdesk & Cases save fix
-- Root cause: their read rules checked visibility by re-querying the same
-- table with a statement-time snapshot — which cannot see a row being
-- inserted in that same statement. Every "save" that returned the new row
-- was therefore refused (42501). Rewritten as direct column checks.
-- ============================================================================

drop policy if exists tickets_read on public.tickets;
create policy tickets_read on public.tickets
  for select to authenticated
  using (
    requester_id = auth.uid()
    or assigned_to = auth.uid()
    or public.is_case_hq()
  );

drop policy if exists cases_read on public.cases;
create policy cases_read on public.cases
  for select to authenticated
  using (
    reporter_id = auth.uid()
    or public.is_case_hq()
    or exists (select 1 from public.case_handlers h
               where h.case_id = id and h.profile_id = auth.uid())
  );

insert into public.schema_migrations (version, name)
values (28, 'fix_ticket_case_saves') on conflict (version) do nothing;
