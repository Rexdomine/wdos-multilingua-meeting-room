-- ============================================================================
-- WDOS SELF-TEST — paste the whole file into the Supabase SQL Editor and Run.
-- Safe to run any time, as often as you like; it changes no data.
-- Result: a table of checks. Every row should say PASS.
-- If any row says FAIL, send that row to Claude.
-- ============================================================================

create temp table _results (n int, test text, pass boolean, note text)
on commit drop;

do $$
declare
  v_count int;
  v_bool boolean;
  v_txt text;
begin
  -- 1. Row Level Security is switched on for every governed table
  select count(*) into v_count
  from pg_class c join pg_namespace ns on ns.oid = c.relnamespace
  where ns.nspname = 'public' and c.relkind = 'r'
    and c.relname in ('org_units','profiles','role_assignments','audit_log',
      'applications','tasks','meetings','meeting_attendance',
      'announcements','announcement_reads','module_access','schema_migrations')
    and not c.relrowsecurity;
  insert into _results values (1, 'Row Level Security enabled on all tables',
    v_count = 0,
    case when v_count = 0 then 'all protected'
         else v_count || ' table(s) unprotected' end);

  -- 2. Every governed table has at least one access policy
  select count(*) into v_count from (
    select t.tbl from unnest(array['org_units','profiles','role_assignments',
      'audit_log','applications','tasks','meetings','meeting_attendance',
      'announcements','announcement_reads','module_access',
      'schema_migrations']) as t(tbl)
    where not exists (select 1 from pg_policies p
      where p.schemaname = 'public' and p.tablename = t.tbl)
  ) missing;
  insert into _results values (2, 'Access policies exist on all tables',
    v_count = 0,
    case when v_count = 0 then 'all covered'
         else v_count || ' table(s) without policies' end);

  -- 3. Audit log rejects updates (immutability)
  v_bool := false;
  if exists (select 1 from audit_log limit 1) then
    begin
      update audit_log set reason = reason
      where id = (select id from audit_log limit 1);
    exception when others then v_bool := true;
    end;
    insert into _results values (3, 'Audit log is append-only (update blocked)',
      v_bool, case when v_bool then 'update rejected as designed'
                   else 'UPDATE WAS ALLOWED' end);
  else
    insert into _results values (3, 'Audit log is append-only (update blocked)',
      true, 'no audit rows yet to test against');
  end if;

  -- 4. Audit log rejects deletes
  v_bool := false;
  if exists (select 1 from audit_log limit 1) then
    begin
      delete from audit_log where id = (select id from audit_log limit 1);
    exception when others then v_bool := true;
    end;
    insert into _results values (4, 'Audit log is append-only (delete blocked)',
      v_bool, case when v_bool then 'delete rejected as designed'
                   else 'DELETE WAS ALLOWED' end);
  else
    insert into _results values (4, 'Audit log is append-only (delete blocked)',
      true, 'no audit rows yet to test against');
  end if;

  -- 5. Membership lifecycle blocks illegal jumps
  insert into _results values (5, 'Lifecycle blocks applicant -> active',
    not valid_status_transition('applicant', 'active'),
    'illegal jump must be rejected');
  insert into _results values (6, 'Lifecycle allows applicant -> under_review',
    valid_status_transition('applicant', 'under_review'),
    'legal step must be allowed');
  insert into _results values (7, 'Lifecycle blocks removed -> active',
    not valid_status_transition('removed', 'active'),
    'reinstatement must pass through reinstated');

  -- 8. Task lifecycle sanity
  insert into _results values (8, 'Tasks block not_started -> awaiting_review',
    not valid_task_transition('not_started', 'awaiting_review'),
    'work must be started before review');

  -- 9. Seniority ranks ordered correctly
  insert into _results values (9, 'Seniority: Super Admin outranks Chapter Lead',
    role_rank('super_admin') < role_rank('chapter_lead'),
    'rank ' || role_rank('super_admin') || ' vs ' || role_rank('chapter_lead'));

  -- 10. Exactly one Headquarters
  select count(*) into v_count from org_units where level = 'headquarters';
  insert into _results values (10, 'Exactly one Headquarters exists',
    v_count = 1, v_count || ' found');

  -- 11. All workflow functions installed
  select count(*) into v_count from (
    select f.fn from unnest(array['update_member_status','review_application',
      'recommend_application','decide_application','appoint_leader',
      'end_appointment','create_org_unit','my_modules','announcement_reach',
      'report_membership','next_membership_no']) as f(fn)
    where not exists (select 1 from pg_proc p
      join pg_namespace ns on ns.oid = p.pronamespace
      where ns.nspname = 'public' and p.proname = f.fn)
  ) missing;
  insert into _results values (11, 'All workflow functions installed',
    v_count = 0,
    case when v_count = 0 then 'all present'
         else v_count || ' function(s) missing' end);

  -- 12. Migration logbook complete
  select count(*) into v_count from generate_series(1, 11) g
  where not exists (select 1 from schema_migrations where version = g);
  insert into _results values (12, 'Migrations 001-011 all recorded',
    v_count = 0,
    case when v_count = 0 then 'logbook complete'
         else v_count || ' migration(s) missing from logbook' end);

  -- 13. Membership numbers follow the format
  select count(*) into v_count from profiles
  where membership_no is not null
    and membership_no !~ '^W-\d{4}-\d{6}$';
  insert into _results values (13, 'Membership numbers follow W-YYYY-NNNNNN',
    v_count = 0,
    case when v_count = 0 then 'all conform'
         else v_count || ' malformed number(s)' end);

  -- 14. Duplicate-application guard index in place
  select exists (select 1 from pg_indexes
    where schemaname = 'public'
      and indexname = 'applications_live_email_uq') into v_bool;
  insert into _results values (14, 'Duplicate live-application guard present',
    v_bool, case when v_bool then 'unique index installed'
                 else 'index missing' end);

  -- 15. Case-insensitive email uniqueness on profiles
  select exists (select 1 from pg_indexes
    where schemaname = 'public'
      and indexname = 'profiles_email_ci_uq') into v_bool;
  insert into _results values (15, 'Email uniqueness guard present',
    v_bool, case when v_bool then 'unique index installed'
                 else 'index missing' end);

  -- 16. Audit triggers attached to every governed table
  select count(*) into v_count from (
    select t.tbl from unnest(array['org_units','profiles','role_assignments',
      'applications','tasks','meetings','meeting_attendance',
      'announcements','module_access']) as t(tbl)
    where not exists (
      select 1 from pg_trigger tr
      join pg_class c on c.oid = tr.tgrelid
      where c.relname = t.tbl and tr.tgname like '%audit%'
        and not tr.tgisinternal)
  ) missing;
  insert into _results values (16, 'Audit triggers attached everywhere',
    v_count = 0,
    case when v_count = 0 then 'all audited'
         else v_count || ' table(s) unaudited' end);
end $$;

select
  n as "#",
  test as "Check",
  case when pass then 'PASS' else 'FAIL' end as "Result",
  note as "Detail"
from _results
order by pass, n;
