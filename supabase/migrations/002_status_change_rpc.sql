-- ============================================================================
-- WDOS Migration 002 — Status change with audit reason
-- PostgREST wraps each request in its own transaction, so the reason must be
-- set and the update performed inside one call. SECURITY INVOKER: RLS and the
-- transition/column-guard triggers from migration 001 still apply in full.
-- ============================================================================

create or replace function public.update_member_status(
  member_id uuid,
  new_status public.member_status,
  reason text default null
)
returns public.profiles
language plpgsql security invoker set search_path = public as $$
declare
  result public.profiles;
begin
  perform set_config('wdos.reason', coalesce(reason, ''), true); -- tx-local
  update profiles set status = new_status where id = member_id
    returning * into result;
  if result.id is null then
    raise exception 'Member not found or not accessible';
  end if;
  return result;
end; $$;

comment on function public.update_member_status is
  'Changes a member''s lifecycle status and records the operator''s reason in audit_log, atomically.';
