-- ============================================================================
-- WDOS Migration 045 — Two-way Communication & Accountability (Phase 49)
--
-- 1. MESSAGING OPENS BOTH WAYS. Volunteer leaders can now write to HQ
--    (staff and executives) and HQ replies land in their inbox — real
--    conversations, not one-way notices. Members still cannot message each
--    other directly (the wall holds); every member-to-member path goes
--    through HQ.
-- 2. TASKS ARRIVE PROPERLY: assigning a task now creates a personal notice
--    for the assignee — bell, sound, browser popup, AND email (when email
--    is on) with the title and due date. Overdue follow-ups already run
--    daily (Phase 45).
-- 3. MEETINGS ANNOUNCE THEMSELVES: scheduling a meeting notifies every
--    member of that unit — date, time, and the join link — through the
--    same channels.
-- 4. ACCOUNTABILITY BY NAME: team_accountability() returns, per person:
--    open, overdue, and completed(30d) task counts plus when they last
--    opened WDOS — who does what, the timing, the accountability.
-- ============================================================================

-- 1 ▸ messaging both ways ----------------------------------------------------
create or replace function public.can_receive_direct(uid uuid)
returns boolean language sql stable
security definer set search_path = public as $$
  select public.is_active_staff(uid)
      or exists (select 1 from role_assignments ra
                  where ra.profile_id = uid
                    and ra.role in ('super_admin','executive_director','hq_team')
                    and ra.ends_at is null);
$$;

drop policy if exists staff_msg_send on public.staff_messages;
create policy staff_msg_send on public.staff_messages
  for insert to authenticated
  with check (
    sender_id = auth.uid()
    and (
      public.is_active_staff(auth.uid())          -- staff may write to anyone
      or public.is_case_hq()                      -- HQ may write to anyone
      or public.can_receive_direct(recipient_id)  -- members may write to HQ
    )
  );

-- 2 ▸ task assignment notice -------------------------------------------------
create or replace function public.task_assign_notice()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.assigned_to is null or new.assigned_to = new.assigned_by then
    return new;
  end if;
  insert into member_notices (profile_id, kind, title, body, meta)
  values (new.assigned_to, 'task',
    'New task: ' || left(new.title, 90),
    coalesce(nullif(left(coalesce(new.details, ''), 300), ''), 'A new task has been assigned to you.')
      || case when new.due_on is not null
              then e'\nDue: ' || to_char(new.due_on, 'DD Mon YYYY') else '' end
      || e'\nOpen Tasks in WDOS to begin.',
    jsonb_build_object('task', new.id));
  return new;
end; $$;

drop trigger if exists tasks_assign_notice on public.tasks;
create trigger tasks_assign_notice
  after insert on public.tasks
  for each row execute function public.task_assign_notice();

-- 3 ▸ meeting announcement ----------------------------------------------------
create or replace function public.meeting_notice()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into member_notices (profile_id, kind, title, body, meta)
  select p.id, 'meeting',
    'Meeting: ' || left(new.title, 90),
    to_char(new.starts_at, 'Dy DD Mon YYYY, HH24:MI')
      || case when new.location is not null and new.location <> ''
              then e'\n' || new.location else '' end
      || case when new.agenda is not null and new.agenda <> ''
              then e'\nAgenda: ' || left(new.agenda, 240) else '' end,
    jsonb_build_object('meeting', new.id)
    from profiles p
   where p.merged_into is null
     and p.org_unit_id = new.org_unit_id
     and p.id <> new.organiser
   limit 200;
  return new;
end; $$;

drop trigger if exists meetings_notice on public.meetings;
create trigger meetings_notice
  after insert on public.meetings
  for each row execute function public.meeting_notice();

-- 2+3 ▸ let those notices ride the email channel too
create or replace function public.email_recent_notices()
returns int language plpgsql security definer set search_path = public as $$
declare
  enabled boolean; r record; sent int := 0;
begin
  select coalesce((value #>> '{}')::boolean, false) into enabled
    from org_settings where key = 'email_notices_enabled';
  if not enabled then return 0; end if;

  for r in
    select mn.id, mn.title, mn.body, p.email, p.first_name
      from member_notices mn
      join profiles p on p.id = mn.profile_id
     where mn.emailed_at is null
       and mn.kind in ('journey_day','birthday','nudge','task','meeting')
       and mn.created_at > now() - interval '26 hours'
       and p.email is not null
     order by mn.created_at
     limit 100
  loop
    if send_email(r.email, r.first_name, r.title,
                  email_wrap(r.title, coalesce(nullif(r.body,''), r.title))) then
      update member_notices set emailed_at = now() where id = r.id;
      sent := sent + 1;
    end if;
  end loop;
  return sent;
end; $$;

-- 4 ▸ accountability by name --------------------------------------------------
create or replace function public.team_accountability()
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not is_case_hq() then raise exception 'HQ only'; end if;
  return (
    select coalesce(jsonb_agg(x order by x->>'overdue' desc, x->>'open' desc), '[]'::jsonb)
    from (
      select jsonb_build_object(
        'id', p.id,
        'name', p.first_name || ' ' || p.last_name,
        'is_staff', exists (select 1 from staff s
                             where s.profile_id = p.id and s.is_active),
        'open', count(*) filter (where tk.status in ('not_started','in_progress')),
        'overdue', count(*) filter (where tk.status in ('not_started','in_progress')
                     and tk.due_on is not null and tk.due_on < current_date),
        'review', count(*) filter (where tk.status = 'awaiting_review'),
        'done30', count(*) filter (where tk.status = 'completed'
                     and tk.completed_at > now() - interval '30 days'),
        'last_seen', p.last_seen_at
      ) as x
      from tasks tk
      join profiles p on p.id = tk.assigned_to
     where p.merged_into is null
     group by p.id, p.first_name, p.last_name, p.last_seen_at
    ) sub);
end; $$;

-- 5 ▸ the people picker: every signed-in user may look up HQ staff
--     (the send policy still controls who may actually receive)
create or replace function public.search_staff_assignees(s text)
returns table (id uuid, first_name text, last_name text, email text,
               position_title text)
language plpgsql security definer set search_path = public as $$
begin
  return query
  select p.id, p.first_name, p.last_name, p.email, st.position_title
    from staff st join profiles p on p.id = st.profile_id
   where st.is_active and p.merged_into is null
     and (s is null or s = '' or
          p.first_name ilike '%' || s || '%' or
          p.last_name  ilike '%' || s || '%' or
          st.position_title ilike '%' || s || '%')
   order by p.last_name limit 10;
end; $$;

insert into public.schema_migrations (version, name)
values (45, 'two_way_comms') on conflict (version) do nothing;
