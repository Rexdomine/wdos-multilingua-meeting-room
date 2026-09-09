-- ============================================================================
-- WDOS Migration 114 — register functions runnable from the SQL Editor
-- The editor runs as the database owner with no signed-in user, so the HQ
-- guard refused ("HQ only"). Now: no user (editor) OR an HQ seat passes;
-- anonymous API callers still cannot execute these functions.
-- -- redefines register_reconcile
-- -- redefines register_apply
-- ============================================================================
create or replace function public.register_reconcile()
returns table (id int, full_name text, role public.role_code, country text, state text, result text, matched_name text, matched_code text, has_login boolean, conflict boolean, status text, note text)
language plpgsql security definer set search_path = public as $$
begin
  -- SQL Editor (no user) or a signed-in HQ role; anon has no execute right
  if auth.uid() is not null and not is_case_hq() then raise exception 'HQ only'; end if;
  return query
  with reg as (select * from leader_register),
  m as (
    select r.id,
      (select p.id from profiles p where p.merged_into is null and lower(coalesce(p.country, '')) in (lower(r.country), '') and name_match(r.full_name, p.first_name || ' ' || p.last_name)
        order by (lower(coalesce(p.country, '')) = lower(r.country)) desc limit 1) as pid,
      (select d.member_code from leader_directory d where d.claimed_profile is null and name_match(r.full_name, d.first_name || ' ' || d.last_name) limit 1) as dcode
    from reg r where r.full_name is not null)
  select r.id, r.full_name, r.role, r.country, r.state,
    case when r.full_name is null then 'vacant' when m.pid is not null then 'matched_login' when m.dcode is not null then 'matched_directory' else 'missing' end,
    coalesce((select p.first_name || ' ' || p.last_name from profiles p where p.id = m.pid),
             (select d.first_name || ' ' || d.last_name from leader_directory d where d.member_code = m.dcode)),
    coalesce((select p.membership_no from profiles p where p.id = m.pid), m.dcode),
    m.pid is not null, r.conflict, r.status, r.note
  from reg r left join m on m.id = r.id
  order by r.role, r.country, r.state;
end; $$;
revoke execute on function public.register_reconcile() from anon;

create or replace function public.register_apply()
returns jsonb language plpgsql security definer set search_path = public as $$
declare r record; n int := 0; c text; code text; parts text[];
begin
  -- SQL Editor (no user) or a signed-in HQ role; anon has no execute right
  if auth.uid() is not null and not is_case_hq() then raise exception 'HQ only'; end if;
  for r in select * from register_reconcile() where result = 'missing' and not conflict loop
    parts := string_to_array(r.full_name, ' ');
    code := case r.role when 'country_rep' then 'CR-' when 'deputy_country_rep' then 'DCR-'
                        when 'state_coordinator' then 'SC-' else 'ASC-' end
            || upper(regexp_replace(coalesce(r.state, (select country_iso from leader_register where id = r.id)), '[^A-Za-z]', '', 'g'));
    c := code; n := n;
    while exists (select 1 from leader_directory where member_code = c) loop c := code || '-' || (floor(random() * 90) + 10)::int; end loop;
    insert into leader_directory (member_code, first_name, last_name, country, role_applied, sent_at)
    values (c, parts[1], array_to_string(parts[2:], ' '), r.country,
            case r.role when 'country_rep' then 'Country Representative' when 'deputy_country_rep' then 'Deputy Country Representative'
                        when 'state_coordinator' then 'State Coordinator' else 'Assistant State Coordinator' end, now());
    update leader_directory set state = r.state where member_code = c and r.state is not null;
    update leader_register set applied_code = c, reconciled_at = now() where id = r.id;
    n := n + 1;
  end loop;
  update leader_register lr set matched_profile = x.pid, matched_code = x.mc, reconciled_at = now()
    from (select rr.id, (select p.id from profiles p where p.membership_no = rr.matched_code limit 1) as pid, rr.matched_code as mc
            from register_reconcile() rr where rr.result in ('matched_login', 'matched_directory')) x
   where lr.id = x.id;
  return jsonb_build_object('added_to_directory', n,
    'matched', (select count(*) from register_reconcile() where result like 'matched%'),
    'conflicts_for_hq', (select count(*) from register_reconcile() where result = 'missing' and conflict),
    'vacant_seats', (select count(*) from leader_register where full_name is null));
end; $$;
revoke execute on function public.register_apply() from anon;

insert into public.schema_migrations (version, name)
values (114, 'register_guard_editor') on conflict (version) do nothing;
