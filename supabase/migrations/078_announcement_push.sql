-- ============================================================================
-- WDOS Migration 078 — Announcements now buzz phones too (Phase 92b)
-- The last honest gap from Phase 92: an announcement reached the bell and
-- the feed, but not a closed phone. This wires it into the exact push
-- pipeline built in migration 067 (queue_push → push_outbox → the Edge
-- Function) — same rails messages, tasks, meetings and notices already
-- ride. One new trigger, no new infrastructure.
--
-- The recipient set is computed with the SAME rule as
-- announcement_reaches_me() (org_unit subtree + network + audience), so a
-- push and an in-app read always agree on who the announcement is for.
-- ============================================================================

create or replace function public.announcement_push()
returns trigger language plpgsql
security definer set search_path = public as $$
declare
  r record;
  ptitle text;
  prefix text;
begin
  prefix := case new.priority
              when 'urgent' then '🚨 '
              when 'important' then '⚠️ '
              else '' end;
  ptitle := left(prefix || new.title, 120);

  for r in
    select p.id from profiles p
     where p.merged_into is null
       and p.org_unit_id in (select org_unit_subtree(new.org_unit_id))
       and (new.network is null or p.network = new.network)
       and (new.audience = 'all'
            or (new.audience = 'leaders' and is_established(p.id))
            or (new.audience = 'intake' and not is_established(p.id)))
  loop
    perform public.queue_push(r.id, ptitle, left(new.body, 160),
                              '#/announcements');
  end loop;
  return new;
end; $$;

drop trigger if exists announcement_push_trg on public.announcements;
create trigger announcement_push_trg
  after insert on public.announcements
  for each row execute function public.announcement_push();

insert into public.schema_migrations (version, name)
values (78, 'announcement_push') on conflict (version) do nothing;
