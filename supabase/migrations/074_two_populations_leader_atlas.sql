-- ============================================================================
-- WDOS Migration 074 (v3) — Two populations, one system (Phase 90)
-- ARCHITECTURE LESSON HONOURED: in WDOS a profile is only ever born
-- together with a login (profiles.id → auth.users). So the 43 established
-- CR/DCR leaders are seeded the way the 134-cohort was: as APPROVED
-- APPLICATIONS carrying their access codes — the same well the ID door's
-- id_lookup() already reads — plus a leader_directory sidecar holding what
-- applications cannot (country, role, leadership itself). The moment a
-- leader claims through the ID door, handle_new_user births the profile
-- and the enrichment hook promotes it: is_leader, Activated, full access,
-- no 14-day activation. Everything else: intake gates (orientation course
-- only, no birthday/inspiration), the approval-switch cure, the Leader
-- Atlas feed, and the access-code dispatch.
-- ============================================================================

-- 1 ▸ who is an established leader ------------------------------------------
alter table public.profiles
  add column if not exists is_leader boolean not null default false;

update public.profiles
   set is_leader = true
 where membership_no ~ '^(CR|DCR|CL|DCL)';

create or replace function public.is_established(pid uuid)
returns boolean language sql stable
security definer set search_path = public as $$
  select exists (select 1 from profiles p
                  where p.id = pid
                    and (p.is_leader
                         or p.status in ('activated','in_training',
                                         'active','reinstated')))
      or exists (select 1 from staff st
                  where st.profile_id = pid and st.is_active);
$$;

-- 2 ▸ the leader directory (the sidecar of truth) ---------------------------
create table if not exists public.leader_directory (
  member_code     text primary key,
  first_name      text not null,
  last_name       text not null,
  email           text,
  phone           text,
  country         text not null,
  role_applied    text not null,
  sent_at         timestamptz,
  claimed_profile uuid references public.profiles(id) on delete set null
);
alter table public.leader_directory enable row level security;
create policy leader_directory_hq on public.leader_directory
  for select to authenticated using (public.is_case_hq());

insert into public.leader_directory
  (member_code, first_name, last_name, email, phone, country, role_applied)
values
  ('CR-BEN', 'Hessou', 'Aline Félicienne', 'hessou.aline@gmail.com', '+2290162204468', 'Benin', 'Country Representative'),
  ('DCR-BEN', 'Yorou', 'Barkissou', 'ybarkissou@gmail.com', '+229 01 97 18 66 54', 'Benin', 'Deputy Country Representative'),
  ('CR-BFA', 'SANOU', 'Kouéssésra Esther', 'estkoue@yahoo.fr', '0022670943610/0022674486923', 'Burkina Faso', 'Country Representative'),
  ('DCR-BFA', 'Denne', 'Irène', 'irene.denne@gmail.com', '+226 71598366', 'Burkina Faso', 'Deputy Country Representative'),
  ('CR-BDI', 'Ahishakiye', 'Berthile', 'abertila1991@gmail.com', '+25779795829', 'Burundi', 'Country Representative'),
  ('CR-CMR', 'Mandunh', 'Mbohou Awawou', 'radhiyabintou@gmail.com', '+237 671590554', 'Cameroon', 'Country Representative'),
  ('DCR-CMR', 'Kwedi', 'Pyo Lydienne', 'kwedilydia23@gmail.com', '(±237)691034476', 'Cameroon', 'Deputy Country Representative'),
  ('CR-CAF', 'Amina', 'Bello', 'aminabello745@gmail.com', '+236 75 42 42 69', 'Central African Republic', 'Country Representative'),
  ('DCR-CAF', 'Koradjim', 'Lionel', 'koradjimlionel72@gmail.com', '+236 72999501', 'Central African Republic', 'Deputy Country Representative'),
  ('CR-TCD', 'Tchindebe', 'Antoinette Fanone', 'famiel.tchad@gmail.com', '+235 62 46 75 13', 'Chad', 'Country Representative'),
  ('DCR-TCD', 'Hinberka', 'Beblere Florice', 'hinberkaflorice@gmail.com', '+23563379637', 'Chad', 'Deputy Country Representative'),
  ('CR-COG', 'Bizonzi', 'Prinelly Sergie Bonnel', 'bizonzi.prinelly@gmail.com', '+242066149474', 'Congo', 'Country Representative'),
  ('CR-CIV', 'Soro', 'Gnimey Cintia Louisette', 'cintialouisette@yahoo.fr', '+2250707602002', 'Côte d''Ivoire', 'Country Representative'),
  ('DCR-CIV', 'Attemene', 'Yannick', 'attemeneyannick@gmail.com', '+225 0777531432', 'Côte d''Ivoire', 'Deputy Country Representative'),
  ('CR-COD', 'Furaha', 'Maroy Judith', 'judithmaroy@gmail.com', '+243995519371', 'DR Congo', 'Country Representative'),
  ('DCR-COD', 'Nshembe', 'Chishungu Eric Nice', 'ericnshembe@gmail.com', '+243993008031', 'DR Congo', 'Deputy Country Representative'),
  ('CR-GMB', 'Haddy', 'Semega Janneh', 'haddysemegajanneh@gmail.com', '', 'Gambia', 'Country Representative'),
  ('CR-GHA', 'Doreen', 'Serwaa Ampae', 'dassyansah55@gmail.com', '+233554841456', 'Ghana', 'Country Representative'),
  ('DCR-GHA', 'Esther', 'Takyiwaah Prempeh', 'prempehesthertakyiwaah@gmail.com', '+233244791883', 'Ghana', 'Deputy Country Representative'),
  ('CR-GIN', 'Koulako', 'Kamissoko', 'koulako.kamissoko@gmail.com', '+224 621097639', 'Guinea', 'Country Representative'),
  ('DCR-GIN', 'Bah', 'Ramata Benny', 'bahramatabenny@gmail.com', '+224622031660', 'Guinea', 'Deputy Country Representative'),
  ('CR-GNB', 'Mariama', 'Fati', 'mariamafati065@gmail.com', '+245955400841', 'Guinea-Bissau', 'Country Representative'),
  ('CR-KEN', 'Sharon', 'Amondi', 'amondisharon54@gmail.com', '', 'Kenya', 'Country Representative'),
  ('DCR-KEN', 'Lilian', 'Songok', null, '+254 719483885', 'Kenya', 'Deputy Country Representative'),
  ('CR-MDG', 'Ainasoa', 'Rakotoniera', 'ainasoarakoto@gmail.com', '(+261) 0320784716', 'Madagascar', 'Country Representative'),
  ('DCR-MDG', 'Tinarivo', 'Baby Emmanuel', 'babyes.emmanuel@gmail.com', '+261 34 52 649 33', 'Madagascar', 'Deputy Country Representative'),
  ('CR-MLI', 'Salimata', 'Coulibaly', 'salimata.coulibaly.kane@gmail.com', '(+223)75999453', 'Mali', 'Country Representative'),
  ('DCR-MLI', 'Binta', 'Coulibaly', 'binete37@gmail.com', '+22390621900', 'Mali', 'Deputy Country Representative'),
  ('CR-MAR', 'Safaa', 'Hachimi', 'safaehcm@gmail.com', '+212638979304', 'Morocco', 'Country Representative'),
  ('CR-NER', 'Abdou', 'Mariama', 'amariama97@yahoo.fr', '+227 99 89 72 30', 'Niger', 'Country Representative'),
  ('DCR-NER', 'Zaleha', 'Salha Abou', 'salhaabouz@gmail.com', '+22788124816', 'Niger', 'Deputy Country Representative'),
  ('CR-NGA', 'Haruna', 'Amina', 'egwola@gmail.com', '', 'Nigeria', 'Country Representative'),
  ('DCR-NGA', 'Maureen', 'Nkechi Chukwuemeka', 'maureenchukwuemeka@gmail.com', '+234 8034753667', 'Nigeria', 'Deputy Country Representative'),
  ('CR-RWA', 'Irene', 'Mukanzayituriki', 'mukanzayiturikii@gmail.com', '+250788647173', 'Rwanda', 'Country Representative'),
  ('DCR-RWA', 'Florence', 'Umutoni', 'florenceumutoni2000@gmail.com', '+250784178086', 'Rwanda', 'Deputy Country Representative'),
  ('CR-SEN', 'Sophie', 'Dior Diack', 'sodiordiack@gmail.com', '(+221) 76 228 09 80', 'Senegal', 'Country Representative'),
  ('DCR-SEN', 'Penda', 'Kande', 'dapenkande@gmail.com', '+221765846398', 'Senegal', 'Deputy Country Representative'),
  ('CR-ZAF', 'Tshegofatso', 'Gama', 'molokoane.m.t@gmail.com', '+27730386265', 'South Africa', 'Country Representative'),
  ('CR-TGO', 'Pakou', 'Akouvi Emefa', 'bonemef84@gmail.com', '+ 228 90 07 68 61', 'Togo', 'Country Representative'),
  ('DCR-TGO', 'Soriyath', 'Lisette Maëlle Bertille Gantua', 'sgantua@gmail.com', '+228 91 54 94 87', 'Togo', 'Deputy Country Representative'),
  ('CR-TUN', 'Nesrine', 'Ben Saad', 'bensaadnesrineselima@gmail.com', '0021650207255', 'Tunisia', 'Country Representative'),
  ('DCR-TUN', 'Nadia', '-', 'nadiathligene@gmail.com', '0021655571598', 'Tunisia', 'Deputy Country Representative'),
  ('CR-UGA', 'Zalwango', 'Grace', 'zalwangograce46@gmail.com', '+256 745 009 128', 'Uganda', 'Country Representative')
on conflict (member_code) do update
  set email  = coalesce(leader_directory.email, excluded.email),
      phone  = coalesce(leader_directory.phone, excluded.phone);

-- 2b ▸ phone hygiene: applications enforce a strict format; humans do not.
--      The directory keeps every number as written; this cleaner produces
--      the constraint-satisfying copy (first number, allowed chars, or
--      digits-only, or null) for the recruitment pipeline.
create or replace function public.clean_phone(raw text)
returns text language plpgsql immutable as $$
declare p text; d text;
begin
  if raw is null or btrim(raw) = '' then return null; end if;
  p := split_part(split_part(raw, '/', 1), ',', 1);
  p := regexp_replace(p, '[^+0-9 ()\-]', '', 'g');
  p := btrim(regexp_replace(p, '\s+', ' ', 'g'));
  if p ~ '^\+?[0-9 ()-]{7,20}$' then return p; end if;
  d := regexp_replace(p, '\D', '', 'g');
  if length(d) between 7 and 20 then return d; end if;
  if length(d) > 20 then return left(d, 20); end if;
  return null;
end; $$;

-- 2c ▸ motivation hygiene: the form demands 20-2000 characters; humans
--      write "Here to serve". Sincerity is not a constraint violation.
create or replace function public.safe_motivation(raw text)
returns text language sql immutable as $$
  select left(
    case when char_length(coalesce(btrim(raw), '')) >= 20
         then btrim(raw)
         else coalesce(nullif(btrim(raw), ''), 'Volunteer registration')
              || ' — registered via the Serve-with-WODDI volunteer form.'
    end, 2000);
$$;

-- 3 ▸ claim-time enrichment: the door promotes the leader -------------------
create or replace function public.apply_leader_directory(pid uuid)
returns void language plpgsql
security definer set search_path = public as $$
declare d record; p record;
begin
  select * into p from profiles where id = pid;
  if p.id is null then return; end if;
  select * into d from leader_directory
   where upper(member_code) = upper(coalesce(p.membership_no, ''))
      or (email is not null and lower(email) = lower(p.email))
   limit 1;
  if d.member_code is null then return; end if;

  perform set_config('wdos.system', '1', true);
  update profiles
     set is_leader     = true,
         country       = coalesce(nullif(country, ''), d.country),
         role_applied  = coalesce(nullif(role_applied, ''), d.role_applied),
         phone         = coalesce(nullif(phone, ''), nullif(d.phone, '')),
         membership_no = coalesce(membership_no, d.member_code)
   where id = pid;
  perform advance_status_on_pass(pid);
  update activation_journeys
     set status = 'deferred'
   where profile_id = pid and status = 'in_progress';
  update leader_directory
     set claimed_profile = pid
   where member_code = d.member_code;
end; $$;

-- leaders enter as approved applications: the ID door already reads them
do $$
declare d record; hq_unit uuid; app_id uuid;
begin
  select id into hq_unit from org_units
   where level = 'headquarters' order by created_at limit 1;
  for d in select * from leader_directory
  loop
    if d.email is not null then
      select id into app_id from applications
       where lower(email) = lower(d.email)
       order by created_at desc limit 1;
    else
      app_id := null;
    end if;

    if app_id is not null then
      update applications
         set member_no = coalesce(member_no, d.member_code),
             status = 'approved',
             decided_at = coalesce(decided_at, now()),
             decision_reason = coalesce(decision_reason,
               'Established leader — CR/DCR Contact Directory')
       where id = app_id;
    elsif not exists (select 1 from applications
                       where upper(member_no) = upper(d.member_code)) then
      insert into applications (first_name, last_name, email, phone,
        network, org_unit_id, motivation, status, decision_reason,
        decided_at, member_no)
      values (d.first_name, d.last_name,
        coalesce(d.email,
          'pending.' || lower(d.member_code) || '@woddi.invalid'),
        clean_phone(d.phone), 'WGMN', hq_unit,
        'Established leader — CR/DCR Contact Directory',
        'approved', 'Seeded from leadership directory', now(),
        d.member_code);
    end if;

    -- already inside WDOS? promote right now, no re-claim needed
    if d.email is not null then
      perform apply_leader_directory((select id from profiles
        where lower(email) = lower(d.email)
          and merged_into is null limit 1));
    end if;
  end loop;
end $$;

-- handle_new_user (latest, 061) + the leader hook
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public as $$
declare app public.applications;
begin
  begin
    select * into app
      from applications
     where lower(email) = lower(new.email) and status = 'approved'
     order by decided_at desc nulls last limit 1;
    if app.id is not null then
      insert into public.profiles
        (id, first_name, last_name, email, phone, network, org_unit_id,
         preferred_locale, status, membership_no)
      values
        (new.id,
         coalesce(nullif(app.first_name, ''), 'Volunteer'),
         coalesce(nullif(app.last_name, ''), '-'),
         new.email, app.phone,
         coalesce(app.network, 'WGMN'::public.network_code),
         coalesce(app.org_unit_id,
           (select id from org_units where level = 'headquarters'
             order by created_at limit 1)),
         coalesce(app.preferred_locale, 'en'), 'approved',
         coalesce(app.member_no, next_membership_no()))
      on conflict (id) do nothing;
      update applications set profile_id = new.id where id = app.id;
    else
      insert into public.profiles (id, first_name, last_name, email, network)
      values (new.id,
        coalesce(new.raw_user_meta_data->>'first_name',''),
        coalesce(new.raw_user_meta_data->>'last_name',''),
        new.email,
        coalesce((new.raw_user_meta_data->>'network')::public.network_code,
          'WGMN'))
      on conflict (id) do nothing;
    end if;
    perform apply_leader_directory(new.id);
  exception when others then
    raise exception 'WDOS claim failed for %: %', new.email, sqlerrm;
  end;
  return new;
end; $$;

-- 4 ▸ the population gate on celebrations -----------------------------------
create or replace function public.notice_population_gate()
returns trigger language plpgsql
security definer set search_path = public as $$
begin
  if new.kind in ('birthday', 'weekly')
     and not is_established(new.profile_id) then
    return null;                -- intake members earn these by passing
  end if;
  return new;
end; $$;

drop trigger if exists notice_population_gate_trg on public.member_notices;
create trigger notice_population_gate_trg
  before insert on public.member_notices
  for each row execute function public.notice_population_gate();

-- 5 ▸ courses: intake sees only the orientation course ----------------------
insert into public.org_settings (key, value)
select 'orientation_course_code', to_jsonb(min(code)) from public.courses
on conflict (key) do nothing;

create or replace function public.orientation_course_code()
returns text language sql stable
security definer set search_path = public as $$
  select coalesce((select value #>> '{}' from org_settings
                    where key = 'orientation_course_code'),
                  (select min(code) from courses));
$$;

drop policy if exists courses_read on public.courses;
create policy courses_read on public.courses
  for select to authenticated
  using (public.is_established(auth.uid())
         or code = public.orientation_course_code());

-- 6 ▸ the approval switch: back on, and the stuck set free ------------------
update public.org_settings
   set value = 'true'::jsonb
 where key = 'auto_approve_volunteers';

create or replace function public.approve_stuck_registrations()
returns jsonb language plpgsql
security definer set search_path = public as $$
declare r record; hq_unit uuid; n int := 0; failed jsonb := '[]'::jsonb;
begin
  if auth.uid() is not null and not is_case_hq() then
    raise exception 'HQ only';
  end if;
  select id into hq_unit from org_units
   where level = 'headquarters' order by created_at limit 1;
  for r in select * from volunteer_applications where status = 'submitted'
  loop
    begin
      update volunteer_applications
         set status = 'approved',
             decision_reason = 'Approved on policy re-assertion',
             decided_at = now()
       where id = r.id;
      if not exists (select 1 from applications
                      where lower(email) = lower(r.email)) then
        insert into applications (first_name, last_name, email, phone,
          network, org_unit_id, motivation, status, decision_reason,
          decided_at)
        values (
          left(coalesce(nullif(split_part(r.full_name, ' ', 1), ''),
            'Volunteer'), 60),
          left(coalesce(nullif(trim(substr(r.full_name,
            length(split_part(r.full_name, ' ', 1)) + 1)), ''), '-'), 60),
          r.email, clean_phone(r.phone), coalesce(r.network, 'WGMN'),
          hq_unit, safe_motivation(r.payload ->> 'why'),
          'approved', 'Approved on policy re-assertion', now());
      end if;
      n := n + 1;
    exception when others then
      -- one bad row is a report, never an abort
      failed := failed || jsonb_build_object(
        'email', r.email, 'why', sqlerrm);
    end;
  end loop;
  return jsonb_build_object('released', n, 'failed', failed);
end; $$;
revoke execute on function public.approve_stuck_registrations() from anon;

-- the LIVE auto-approve trigger carried the same three landmines since 048:
-- short motivations and odd phone formats silently stranded registrants
-- (failures whispered into a log nobody reads), and the welcome email sent
-- people to the old domain's claim page. All three cured here.
create or replace function public.volunteer_auto_approve()
returns trigger
language plpgsql security definer set search_path = public as $$
declare enabled boolean; hq_unit uuid;
begin
  select coalesce((value #>> '{{}}')::boolean, false) into enabled
    from org_settings where key = 'auto_approve_volunteers';
  if not enabled then return new; end if;
  if new.status is distinct from 'submitted' then return new; end if;

  begin
    select id into hq_unit from org_units
     where level = 'headquarters' order by created_at limit 1;

    update volunteer_applications
       set status = 'approved',
           decision_reason = 'Auto-approved on registration (org policy)',
           decided_at = now()
     where id = new.id;

    if not exists (select 1 from applications
                    where lower(email) = lower(new.email)) then
      insert into applications (first_name, last_name, email, phone, network,
        org_unit_id, motivation, status, decision_reason, decided_at)
      values (
        left(coalesce(nullif(split_part(new.full_name, ' ', 1), ''),
          'Volunteer'), 60),
        left(coalesce(nullif(trim(substr(new.full_name,
          length(split_part(new.full_name, ' ', 1)) + 1)), ''), '-'), 60),
        new.email, clean_phone(new.phone), coalesce(new.network, 'WGMN'),
        hq_unit, safe_motivation(new.payload ->> 'why'),
        'approved', 'Auto-approved volunteer registration', now());
    end if;

    perform send_email(new.email,
      coalesce(nullif(split_part(new.full_name, ' ', 1), ''), 'Volunteer'),
      'Welcome to WODDI — you are approved!',
      email_wrap('You are approved!',
        'Thank you for registering to serve with WODDI. Your application '
        || 'has been approved.' || e'\n\n'
        || 'Create your login now and begin your activation journey:'
        || e'\n' || 'https://woddicrm.org/#/claim' || e'\n\n'
        || 'Use this same email address when creating your account. '
        || 'We are delighted to have you.'));
  exception when others then
    raise notice 'volunteer_auto_approve skipped for %: %', new.email, sqlerrm;
  end;
  return new;
end; $$;

select public.approve_stuck_registrations();

-- 7 ▸ the Leader Atlas feed (claimed + awaiting, HQ only) -------------------
create or replace function public.leaders_atlas()
returns jsonb language plpgsql
security definer set search_path = public as $$
declare total_modules int;
begin
  if not is_case_hq() then raise exception 'HQ only'; end if;
  select count(*) into total_modules
    from course_modules cm join courses c on c.id = cm.course_id
   where c.is_active;
  return (
    select coalesce(jsonb_agg(row order by row->>'country',
                              row->>'role_applied', row->>'name'),
                    '[]'::jsonb)
    from (
      select jsonb_build_object(
        'id', p.id,
        'name', p.first_name || ' ' || p.last_name,
        'membership_no', p.membership_no,
        'role_applied', p.role_applied,
        'country', p.country,
        'state', p.state_region,
        'lga', p.lga,
        'email', p.email,
        'phone', p.phone,
        'last_seen', p.last_seen_at,
        'has_login', true,
        'modules_passed', coalesce((
          select count(*) from course_module_passes cmp
            join course_enrollments ce on ce.id = cmp.enrollment_id
           where ce.profile_id = p.id), 0),
        'modules_total', total_modules
      ) as row
      from profiles p
      where p.is_leader and p.merged_into is null
      union all
      select jsonb_build_object(
        'id', null,
        'name', d.first_name || ' ' || d.last_name,
        'membership_no', d.member_code,
        'role_applied', d.role_applied,
        'country', d.country,
        'state', null, 'lga', null,
        'email', d.email,
        'phone', d.phone,
        'last_seen', null,
        'has_login', false,
        'modules_passed', 0,
        'modules_total', total_modules
      ) as row
      from leader_directory d
      where d.claimed_profile is null
        and not exists (select 1 from profiles p2
          where p2.is_leader and p2.merged_into is null
            and upper(p2.membership_no) = upper(d.member_code))
    ) sub);
end; $$;
revoke execute on function public.leaders_atlas() from anon;

-- 8 ▸ leader access-code dispatch (from the directory) ----------------------
create or replace function public.leader_codes_dispatch()
returns jsonb language plpgsql
security definer set search_path = public as $$
declare d record; n int := 0; skipped int := 0; noemail text := '';
  code_title constant text := 'Your WODDI Leadership Access Code';
begin
  if auth.uid() is not null and not is_case_hq() then
    raise exception 'HQ only';
  end if;
  for d in select * from leader_directory
  loop
    if d.email is null or d.email like '%@woddi.invalid' then
      noemail := noemail || d.first_name || ' ' || d.last_name || ' ('
              || d.country || '); ';
      continue;
    end if;
    if d.sent_at is not null then skipped := skipped + 1; continue; end if;
    perform send_email(d.email, d.first_name, code_title,
      email_wrap(code_title,
        'Dear ' || d.first_name || ',' || e'\n\n'
        || 'Welcome to the WODDI Digital Operating System — the home of '
        || 'our pan-African leadership family.' || e'\n\n'
        || 'Your personal access code: ' || d.member_code || e'\n\n'
        || '1. Go to https://woddicrm.org' || e'\n'
        || '2. Press "I have a Volunteer ID"' || e'\n'
        || '3. Enter your code exactly as written above and choose your '
        || 'password.' || e'\n\n'
        || 'Already set a password before? Simply sign in. Your courses, '
        || 'meetings and messages from HQ are waiting inside. We are glad '
        || 'you lead with us.'));
    update leader_directory set sent_at = now()
     where member_code = d.member_code;
    n := n + 1;
  end loop;
  return jsonb_build_object('emailed', n, 'already_sent', skipped,
                            'needs_email', nullif(noemail, ''));
end; $$;
revoke execute on function public.leader_codes_dispatch() from anon;

insert into public.schema_migrations (version, name)
values (74, 'two_populations_leader_atlas') on conflict (version) do nothing;
