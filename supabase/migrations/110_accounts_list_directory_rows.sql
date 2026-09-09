-- ============================================================================
-- WDOS Migration 110 — Accounts list: directory leaders (no login yet) are
-- always listed. The 103 version applied its row cap to the whole union, so
-- with more than the cap of members every "No login" row disappeared
-- ("400 shown · 0 without login" on 6 Sep). The cap now applies to members
-- with logins only; leaders waiting for a login are never cut off.
-- -- redefines hq_account_list
-- ============================================================================
create or replace function public.hq_account_list(q text default '', lim int default 300)
returns jsonb language plpgsql stable
security definer set search_path = public as $$
declare needle text := lower(coalesce(q, ''));
begin
  if not is_case_hq() then raise exception 'HQ only'; end if;
  return (
    select coalesce(jsonb_agg(rw order by
             (rw->>'has_login') desc, (rw->>'is_leader') desc, rw->>'name'), '[]'::jsonb)
    from (
      (select jsonb_build_object(
        'id', p.id, 'name', p.first_name || ' ' || p.last_name,
        'first_name', p.first_name, 'last_name', p.last_name,
        'email', p.email, 'phone', p.phone, 'membership_no', p.membership_no,
        'network', p.network, 'status', p.status, 'role_applied', p.role_applied,
        'country', p.country, 'state_region', p.state_region, 'lga', p.lga,
        'is_leader', p.is_leader,
        'is_staff', exists (select 1 from staff s where s.profile_id = p.id and s.is_active),
        'last_seen_at', p.last_seen_at,
        'last_sign_in_at', u.last_sign_in_at,
        'email_confirmed', u.email_confirmed_at is not null,
        'banned', (u.banned_until is not null and u.banned_until > now()),
        'created_at', p.created_at,
        'has_login', true,
        'roles', (select coalesce(jsonb_agg(jsonb_build_object(
                    'role', ra.role, 'unit_id', ou.id, 'unit', ou.name, 'level', ou.level)
                    order by ra.starts_at), '[]'::jsonb)
                   from role_assignments ra join org_units ou on ou.id = ra.org_unit_id
                  where ra.profile_id = p.id and ra.ends_at is null)
      ) as rw
      from profiles p
      left join auth.users u on u.id = p.id
      where p.merged_into is null
        and (needle = '' or lower(p.first_name || ' ' || p.last_name) like '%' || needle || '%'
             or lower(p.email) like '%' || needle || '%'
             or lower(coalesce(p.membership_no, '')) like '%' || needle || '%'
             or lower(coalesce(p.country, '')) like '%' || needle || '%'
             or lower(coalesce(p.role_applied, '')) like '%' || needle || '%')
      order by p.is_leader desc, p.last_name, p.first_name
      limit lim)
      union all
      (select jsonb_build_object(
        'id', null, 'name', d.first_name || ' ' || d.last_name,
        'first_name', d.first_name, 'last_name', d.last_name,
        'email', d.email, 'phone', d.phone, 'membership_no', d.member_code,
        'network', case when d.member_code ~ '^(CL|DCL|CA|PM)' then 'WNNN' else 'WGMN' end,
        'status', null, 'role_applied', d.role_applied,
        'country', d.country, 'state_region', d.state, 'lga', null,
        'is_leader', true, 'is_staff', false,
        'last_seen_at', null, 'last_sign_in_at', null,
        'email_confirmed', false, 'banned', false,
        'created_at', d.sent_at, 'has_login', false, 'roles', '[]'::jsonb
      ) as rw
      from leader_directory d
      where d.claimed_profile is null
        and not exists (select 1 from profiles p2
                         where p2.merged_into is null
                           and (upper(p2.membership_no) = upper(d.member_code)
                                or (d.email is not null and lower(p2.email) = lower(d.email))))
        and (needle = '' or lower(d.first_name || ' ' || d.last_name) like '%' || needle || '%'
             or lower(coalesce(d.email, '')) like '%' || needle || '%'
             or lower(d.member_code) like '%' || needle || '%'
             or lower(d.country) like '%' || needle || '%'
             or lower(d.role_applied) like '%' || needle || '%'))
    ) sub);
end; $$;
revoke execute on function public.hq_account_list(text, int) from anon;

insert into public.schema_migrations (version, name)
values (110, 'accounts_list_directory_rows') on conflict (version) do nothing;
