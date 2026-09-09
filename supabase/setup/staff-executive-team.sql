-- ============================================================================
-- WDOS — Executive Team staff placement (one-off setup, NOT a migration)
--
-- BEFORE RUNNING:
--   1. Emails are filled in. Create each person's account first:
--      Supabase → Authentication → Add user, using EXACTLY these emails
--      (note the given spellings: aziz@ and oyinye@).
--   2. Run migrations 015 and 016 first.
--
-- Safe to run repeatedly: existing placements are updated, not duplicated.
-- Anyone whose account doesn't exist yet is skipped with a NOTICE — create
-- the account and simply run the script again.
--
-- Reporting lines below are my best reading of the structure — Founder at
-- the top, Executive Director reporting to her, directors and standalone
-- functions reporting to the ED, Admin Support to the Director of Admin,
-- IT Lead to the Director of Technical Delivery. Edit before running if
-- WODDI's actual lines differ.
-- ============================================================================

do $$
declare
  r record;
  v_profile uuid;
  v_dept uuid;
  v_mgr uuid;
begin
  create temp table roster (
    email text, first_name text, last_name text,
    dept text, title text, manager_email text
  ) on commit drop;

  insert into roster values
    ('zinaria@thewoddi.org',
     'Zinaria Nneoma Nkechi Rochas', 'Okorocha',
     'Executive Office', 'Founder & Chairperson', null),
    ('belinda@thewoddi.org',
     'Belinda Ujunwa', 'Ezeofor',
     'Executive Office', 'Executive Director',
     'zinaria@thewoddi.org'),
    ('oyinye@thewoddi.org',
     'Onyinye', 'Nwigwe',
     'Programmes', 'Director of Programmes',
     'belinda@thewoddi.org'),
    ('laurel@thewoddi.org',
     'Amaranjo', 'Laurel',
     'Administration', 'Director of Admin',
     'belinda@thewoddi.org'),
    ('ekene@thewoddi.org',
     'Ekene Peter', 'Okolo',
     'Technical Delivery', 'Director of Technical Delivery',
     'belinda@thewoddi.org'),
    ('prince@thewoddi.org',
     'John', 'Prince',
     'Communications & Media', 'Social Media Manager',
     'belinda@thewoddi.org'),
    ('mfon@thewoddi.org',
     'Mfon', 'Nta',
     'Administration', 'Admin Support',
     'laurel@thewoddi.org'),
    ('aziz@thewoddi.org',
     'Azeez', 'Razak',
     'Technical Delivery', 'IT Lead',
     'ekene@thewoddi.org'),
    ('fashanu@thewoddi.org',
     'Peter', 'Fashanu',
     'Finance', 'Accountant',
     'belinda@thewoddi.org');

  for r in select * from roster loop
    select id into v_profile from profiles
      where lower(email) = lower(r.email);
    if v_profile is null then
      raise notice 'SKIPPED (no account yet): %', r.email;
      continue;
    end if;

    select id into v_dept from departments where name = r.dept;
    if v_dept is null then
      raise notice 'SKIPPED (department missing — run migration 015): %', r.dept;
      continue;
    end if;

    v_mgr := null;
    if r.manager_email is not null then
      select id into v_mgr from profiles
        where lower(email) = lower(r.manager_email);
      if v_mgr is null then
        raise notice 'Manager account not found for % (placing without manager; re-run later)', r.email;
      end if;
    end if;

    -- Set the person's real name on their profile (account creation only
    -- derives a rough name from the email address).
    update profiles
       set first_name = r.first_name, last_name = r.last_name
     where id = v_profile;

    insert into staff (profile_id, department_id, position_title, reports_to)
    values (v_profile, v_dept, r.title, v_mgr)
    on conflict (profile_id) do update
      set department_id = excluded.department_id,
          position_title = excluded.position_title,
          reports_to = excluded.reports_to,
          is_active = true;

    raise notice 'PLACED: % % as % (%)',
      r.first_name, r.last_name, r.title, r.dept;
  end loop;
end $$;

-- Afterwards, verify:
select p.first_name, p.last_name, s.position_title, d.name as department,
       mp.first_name || ' ' || mp.last_name as reports_to
from staff s
join profiles p on p.id = s.profile_id
join departments d on d.id = s.department_id
left join profiles mp on mp.id = s.reports_to
where s.is_active
order by d.name, s.position_title;
