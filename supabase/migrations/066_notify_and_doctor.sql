-- ============================================================================
-- WDOS Migration 066 — Honest Doctor & Notification Lanes (Phase 87)
-- 1. may_send_message(): the function the Doctor page always called but
--    never existed (audit §1.1) — now real, mirroring the staff_msg_send
--    RLS policy exactly, so the Doctor's messaging row tells the truth.
-- 2. Realtime lanes for browser notifications: tasks, announcements and
--    staff_messages join the publication (member_notices already there),
--    so the app can raise system notifications the moment rows land.
-- ============================================================================

create or replace function public.may_send_message(sender uuid, recipient uuid)
returns boolean
language sql stable
security definer set search_path = public as $$
  select sender = auth.uid()
     and sender <> recipient
     and (
       public.is_active_staff(sender)
       or public.is_case_hq()
       or public.can_receive_direct(recipient)
     );
$$;
grant execute on function public.may_send_message(uuid, uuid) to authenticated;
revoke execute on function public.may_send_message(uuid, uuid)
  from anon, public;

do $$
begin
  begin
    alter publication supabase_realtime add table public.tasks;
  exception when duplicate_object then null;
  end;
  begin
    alter publication supabase_realtime add table public.announcements;
  exception when duplicate_object then null;
  end;
  begin
    alter publication supabase_realtime add table public.staff_messages;
  exception when duplicate_object then null;
  end;
  begin
    alter publication supabase_realtime add table public.member_notices;
  exception when duplicate_object then null;
  end;
end $$;

insert into public.schema_migrations (version, name)
values (66, 'notify_and_doctor') on conflict (version) do nothing;
