-- ============================================================================
-- WDOS Migration 014 — Helpdesk & Support Centre
-- Tickets with conversation threads. Requester sees her own tickets;
-- assigned officers see theirs; HQ sees all. Every action audited.
-- ============================================================================

create type public.ticket_category as enum (
  'login', 'app_problem', 'certificate', 'role_access',
  'training_access', 'technical', 'other'
);

create type public.ticket_status as enum (
  'open', 'in_progress', 'waiting_on_user', 'resolved', 'closed'
);

create sequence if not exists public.ticket_no_seq;

create table public.tickets (
  id           uuid primary key default gen_random_uuid(),
  ticket_no    text unique,
  category     public.ticket_category not null,
  priority     public.task_priority not null default 'medium',
  subject      text not null check (char_length(subject) between 3 and 160),
  details      text not null check (char_length(details) between 5 and 4000),
  requester_id uuid not null references public.profiles(id) default auth.uid(),
  assigned_to  uuid references public.profiles(id),
  status       public.ticket_status not null default 'open',
  resolved_at  timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create index tickets_requester_idx on public.tickets (requester_id, status);
create index tickets_assignee_idx on public.tickets (assigned_to)
  where status in ('open', 'in_progress', 'waiting_on_user');

create or replace function public.tickets_assign_no()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.ticket_no is null then
    new.ticket_no := 'T-' || to_char(now(), 'YYYY') || '-' ||
      lpad(nextval('ticket_no_seq')::text, 4, '0');
  end if;
  return new;
end; $$;

create trigger tickets_no before insert on public.tickets
  for each row execute function public.tickets_assign_no();
create trigger tickets_touch before update on public.tickets
  for each row execute function public.touch_updated_at();
create trigger tickets_audit after insert or update or delete
  on public.tickets for each row execute function public.audit_row();

create table public.ticket_messages (
  id         uuid primary key default gen_random_uuid(),
  ticket_id  uuid not null references public.tickets(id) on delete cascade,
  author_id  uuid not null references public.profiles(id) default auth.uid(),
  body       text not null check (char_length(body) between 1 and 4000),
  created_at timestamptz not null default now()
);

create index ticket_messages_idx on public.ticket_messages (ticket_id, created_at);

create trigger ticket_messages_audit after insert or update or delete
  on public.ticket_messages for each row execute function public.audit_row();

-- ---------------------------------------------------------------------------
-- Access helpers
-- ---------------------------------------------------------------------------
create or replace function public.can_access_ticket(tid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select is_case_hq()
      or exists (select 1 from tickets x
                 where x.id = tid
                   and (x.requester_id = auth.uid()
                        or x.assigned_to = auth.uid()));
$$;

create or replace function public.can_manage_ticket(tid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select is_case_hq()
      or exists (select 1 from tickets x
                 where x.id = tid and x.assigned_to = auth.uid());
$$;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
alter table public.tickets         enable row level security;
alter table public.ticket_messages enable row level security;

create policy tickets_read on public.tickets
  for select to authenticated using (public.can_access_ticket(id));

create policy tickets_file on public.tickets
  for insert to authenticated
  with check (requester_id = auth.uid() and status = 'open'
              and assigned_to is null and resolved_at is null);

-- Status changes and assignment via RPCs only (no direct update policy).

create policy ticket_messages_read on public.ticket_messages
  for select to authenticated
  using (public.can_access_ticket(ticket_id));

-- Both sides of the conversation may write while the ticket is not closed.
create policy ticket_messages_write on public.ticket_messages
  for insert to authenticated
  with check (
    author_id = auth.uid()
    and public.can_access_ticket(ticket_id)
    and exists (select 1 from public.tickets x
                where x.id = ticket_id and x.status <> 'closed')
  );

-- ---------------------------------------------------------------------------
-- Workflow RPCs
-- ---------------------------------------------------------------------------
create or replace function public.assign_ticket(tid uuid, officer uuid)
returns public.tickets
language plpgsql security definer set search_path = public as $$
declare x public.tickets;
begin
  if not is_case_hq() then
    raise exception 'Only Headquarters can assign tickets';
  end if;
  update tickets
     set assigned_to = officer,
         status = case when status = 'open' then 'in_progress' else status end
   where id = tid
   returning * into x;
  if x.id is null then raise exception 'Ticket not found'; end if;
  return x;
end; $$;

create or replace function public.valid_ticket_transition(
  old_s public.ticket_status, new_s public.ticket_status)
returns boolean language sql immutable as $$
  select case old_s
    when 'open'            then new_s in ('in_progress','waiting_on_user','resolved','closed')
    when 'in_progress'     then new_s in ('waiting_on_user','resolved','closed','open')
    when 'waiting_on_user' then new_s in ('in_progress','resolved','closed')
    when 'resolved'        then new_s in ('closed','in_progress')
    when 'closed'          then new_s in ('open')            -- reopen
  end;
$$;

create or replace function public.set_ticket_status(
  tid uuid, new_status public.ticket_status)
returns public.tickets
language plpgsql security definer set search_path = public as $$
declare x public.tickets; is_requester boolean;
begin
  select * into x from tickets where id = tid for update;
  if x.id is null then raise exception 'Ticket not found'; end if;
  is_requester := (x.requester_id = auth.uid());

  if not can_manage_ticket(tid) then
    -- Requesters may only close their own ticket, or reopen a closed one.
    if not (is_requester and new_status in ('closed', 'open')) then
      raise exception 'Only the assigned officer or Headquarters can change this ticket';
    end if;
  end if;
  if not valid_ticket_transition(x.status, new_status) then
    raise exception 'Invalid ticket transition: % -> %', x.status, new_status;
  end if;

  update tickets
     set status = new_status,
         resolved_at = case when new_status = 'resolved' then now()
                            when new_status in ('open','in_progress') then null
                            else resolved_at end
   where id = tid
   returning * into x;
  return x;
end; $$;

-- ---------------------------------------------------------------------------
-- Module registration + logbook
-- ---------------------------------------------------------------------------
alter table public.module_access drop constraint module_access_module_check;
alter table public.module_access add constraint module_access_module_check
  check (module in (
    'members','recruitment','organisation','tasks','meetings',
    'reports','announcements','settings','programmes','cases','helpdesk'
  ));

insert into public.module_access (role, module)
select r::public.role_code, 'helpdesk' from unnest(array[
  'super_admin','executive_director','hq_team',
  'country_rep','deputy_country_rep','state_coordinator',
  'assistant_state_coordinator','district_coordinator','chapter_lead',
  'volunteer','member','programme_staff','institute_admin'
]) as r
on conflict do nothing;

insert into public.schema_migrations (version, name)
values (14, 'helpdesk') on conflict (version) do nothing;
