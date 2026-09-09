-- ============================================================================
-- WDOS Migration 079 — State & Assistant State Coordinators (Phase 93)
-- The same architecture as Phase 90/91's Country Reps, extended one level
-- down: 68 established Nigerian state-level leaders (34 states with a
-- State Coordinator, 34 with an Assistant — not always the same 34, so
-- several seats are genuinely vacant, exactly as the source document's own
-- gap notes said: FCT/Ekiti/Ondo/Kwara/Bayelsa/Oyo/Imo each hold only one
-- of the two roles in real life. The org chart shows this honestly —
-- nothing here is invented to fill a gap.
--
-- Every lesson paid for in Phases 90-91 is applied from the first run:
--   · leader_directory extended with a nullable state column (country-level
--     rows keep state = null, exactly as before)
--   · member_no is FORCED, never coalesced (the bug that silently ate
--     South Africa's code)
--   · clean_phone() / safe_motivation() guard every application insert
--   · apply_leader_directory() now seats state-level claimants at their
--     STATE org_unit with state_coordinator / assistant_state_coordinator,
--     and sets profiles.state_region so the Atlas groups them correctly
--   · one leader (Imo's Theresa Ohanuba) has no email on file — seeded
--     with a placeholder like Kenya's Lilian, surfaced in needs_email
-- ============================================================================

-- 1 ▸ the directory grows a state column -------------------------------------
alter table public.leader_directory
  add column if not exists state text;

insert into public.leader_directory
  (member_code, first_name, last_name, email, phone, country, state,
   role_applied)
values
  ('SC-ABIA', 'Ogbonnaya', 'Uwaezuoke Ndukwe', 'uwaezundukwe12@gmail.com', '08033374025', 'Nigeria', 'Abia', 'State Coordinator'),
  ('ASC-ABIA', 'Onyinyechi', 'Anne Nwafor', 'annegift3@gmail.com', '+2347066046870', 'Nigeria', 'Abia', 'Assistant State Coordinator'),
  ('SC-FCT', 'Rahilla', 'Success Daniel', 'rdanielsuccess@gmail.com', '07012689778', 'Nigeria', 'Federal Capital Territory', 'State Coordinator'),
  ('ASC-FCT', 'Mise', 'Oluseyi Olufunke', 'seyimise1@gmail.com', '+2348103473909, +2347011525622', 'Nigeria', 'Federal Capital Territory', 'Assistant State Coordinator'),
  ('SC-ADAMAWA', 'Milcah', 'Gaman', 'milcahgaman41@gmail.com', '+2348104675570', 'Nigeria', 'Adamawa', 'State Coordinator'),
  ('ASC-ADAMAWA', 'Hadiza', 'Umar', 'hajjaumar2013@gmail.com', '08036763689', 'Nigeria', 'Adamawa', 'Assistant State Coordinator'),
  ('SC-AKWAIBOM', 'Ikouwem', 'Oku Isaac', 'isaacikouwem@gmail.com', '09076306540', 'Nigeria', 'Akwa Ibom', 'State Coordinator'),
  ('ASC-AKWAIBOM', 'Essien', 'Iniobong', 'essieniniobong101@gmail.com', '07039571068', 'Nigeria', 'Akwa Ibom', 'Assistant State Coordinator'),
  ('SC-ANAMBRA', 'Chioma', 'Okeoma Okonkwo', 'chommy4life82@gmail.com', '08063594545', 'Nigeria', 'Anambra', 'State Coordinator'),
  ('ASC-ANAMBRA', 'Chidubem', 'Godfrey Nwachinemere', 'chidubemnwachinemere@gmail.com', '+2348160218792', 'Nigeria', 'Anambra', 'Assistant State Coordinator'),
  ('SC-BAUCHI', 'Hajara', 'Umaru', 'hajaraumaru676@gmail.com', '08038194676', 'Nigeria', 'Bauchi', 'State Coordinator'),
  ('ASC-BAUCHI', 'Kubura', 'Rabiu', 'kuburarabiu@gmail.com', '08069250010', 'Nigeria', 'Bauchi', 'Assistant State Coordinator'),
  ('SC-BAYELSA', 'Doris', 'Nurse‑ere Ndoboke', 'nurserendoboke@gmail.com', '07018211753', 'Nigeria', 'Bayelsa', 'State Coordinator'),
  ('SC-BENUE', 'Elizabeth', 'Dooshima Akoh‑Kohol', 'doshliz69@gmail.com', '08034404559', 'Nigeria', 'Benue', 'State Coordinator'),
  ('ASC-BENUE', 'Ogoyi', 'Ochanya Gloria', 'g71876882@gmail.com', '08162562662', 'Nigeria', 'Benue', 'Assistant State Coordinator'),
  ('SC-BORNO', 'Ruqayyah', 'Abba Waziri', 'ruqayyah6050@gmail.com', '+2347032029756', 'Nigeria', 'Borno', 'State Coordinator'),
  ('ASC-BORNO', 'Mary', 'Dona Terry', 'maryezekyel007@gmail.com', '07060982192', 'Nigeria', 'Borno', 'Assistant State Coordinator'),
  ('SC-CROSSRIVER', 'Inya', 'Elemi', 'inyaelemi@yahoo.com', '+2348068942035', 'Nigeria', 'Cross River', 'State Coordinator'),
  ('ASC-CROSSRIVER', 'James', 'Ofem Otu', 'james.otu2025@gmail.com', '08130020924', 'Nigeria', 'Cross River', 'Assistant State Coordinator'),
  ('SC-DELTA', 'Florence', 'Ogonegbu', 'overflowingflorence@gmail.com', '08142743623', 'Nigeria', 'Delta', 'State Coordinator'),
  ('ASC-DELTA', 'Erhuvwu', 'Lisa Tarhe', 'lisrus007@gmail.com', '+2348036172416', 'Nigeria', 'Delta', 'Assistant State Coordinator'),
  ('SC-EBONYI', 'Nwali', 'Esther Ndidi', 'estheronyeka173@gmail.com', '08067478361', 'Nigeria', 'Ebonyi', 'State Coordinator'),
  ('ASC-EBONYI', 'Oreke', 'Chinazor', 'chinazorchinedu@gmail.com', '+2348035118144', 'Nigeria', 'Ebonyi', 'Assistant State Coordinator'),
  ('SC-EDO', 'Christy', 'Okpedo', 'iifychriss@gmail.com', '08039446122', 'Nigeria', 'Edo', 'State Coordinator'),
  ('ASC-EDO', 'Emonvuon', 'Helen', 'helenoboh2020@gmail.com', '08063622180', 'Nigeria', 'Edo', 'Assistant State Coordinator'),
  ('ASC-EKITI', 'Hammed', 'Omolayo Bello', 'bellohammed6@gmail.com', '07064636892', 'Nigeria', 'Ekiti', 'Assistant State Coordinator'),
  ('SC-ENUGU', 'Ruth', 'Obioma Ngoka', 'ngokaruthobioma@gmail.com', '+2348031933103', 'Nigeria', 'Enugu', 'State Coordinator'),
  ('ASC-ENUGU', 'Asika', 'Christiana Ogechi', 'aogechiasika@gmail.com', '+23480639 23944', 'Nigeria', 'Enugu', 'Assistant State Coordinator'),
  ('SC-GOMBE', 'Miriam', 'Monday Umar', 'miriamumar30@gmail.com', '08136597157', 'Nigeria', 'Gombe', 'State Coordinator'),
  ('ASC-GOMBE', 'Elizabeth', 'David Ankama', 'elizabethankama222@gmail.com', '+2348130814198', 'Nigeria', 'Gombe', 'Assistant State Coordinator'),
  ('SC-IMO', 'Theresa', 'Ohanuba', null, '', 'Nigeria', 'Imo', 'State Coordinator'),
  ('SC-JIGAWA', 'Umma', 'Mohammed Lawal', 'uhmmarhhernie@gmail.com', '+2348134063987', 'Nigeria', 'Jigawa', 'State Coordinator'),
  ('ASC-JIGAWA', 'Aisha', 'Muhammad Sabo', 'aishamuhammadsabo2004@gmail.com', '08109021686', 'Nigeria', 'Jigawa', 'Assistant State Coordinator'),
  ('SC-KADUNA', 'Nafisa', 'Shuaibu', 'shuaibunafisa1@gmail.com', '08169198088', 'Nigeria', 'Kaduna', 'State Coordinator'),
  ('ASC-KADUNA', 'Jemimah', 'Adamu Dattijo', 'jemdattijo@gmail.com', '07061807704', 'Nigeria', 'Kaduna', 'Assistant State Coordinator'),
  ('SC-KATSINA', 'Murjanatu', 'Yakubu', 'murjanatuyakubusadauki@gmail.com', '+2348037143766', 'Nigeria', 'Katsina', 'State Coordinator'),
  ('ASC-KATSINA', 'Rahab', 'Sani', 'rahamasanir@gmail.com', '08068384700', 'Nigeria', 'Katsina', 'Assistant State Coordinator'),
  ('SC-KANO', 'Maryam', 'Mshelia', 'maryammshelia001@gmail.com', '07058070502', 'Nigeria', 'Kano', 'State Coordinator'),
  ('ASC-KANO', 'Jennifer', 'Azi', 'azijenifa@gmail.com', '08027913810', 'Nigeria', 'Kano', 'Assistant State Coordinator'),
  ('SC-KEBBI', 'Esther', 'Hindi', 'estherhindi78@gmail.com', '08065289992', 'Nigeria', 'Kebbi', 'State Coordinator'),
  ('ASC-KEBBI', 'Lami', 'Abdullah', 'beckyjatau23@gmail.com', '08025740853', 'Nigeria', 'Kebbi', 'Assistant State Coordinator'),
  ('SC-KOGI', 'Ahmed', 'Safinat Lami', 'ahmed.safinat88@gmail.com', '+2347036127120', 'Nigeria', 'Kogi', 'State Coordinator'),
  ('ASC-KOGI', 'Salimat', 'Mohammed Mamma', 'hellosalima07@gmail.com', '+2348153420491', 'Nigeria', 'Kogi', 'Assistant State Coordinator'),
  ('ASC-KWARA', 'Abdulganeey', 'Abdullateef okubii', 'abdullateefishola15@gmail.com', '+2348064032055', 'Nigeria', 'Kwara', 'Assistant State Coordinator'),
  ('SC-LAGOS', 'Ojo', 'Ayodele Adedoyin', 'ayodeleojo124@gmail.com', '08167632201', 'Nigeria', 'Lagos', 'State Coordinator'),
  ('ASC-LAGOS', 'Ejim', 'Esther Chinonyerem', 'estherejim59@gmail.com', '+234 8134211654', 'Nigeria', 'Lagos', 'Assistant State Coordinator'),
  ('SC-NASARAWA', 'Joy', 'Naveh Joseph', 'navehjoyjoseph@gmail.com', '2348103475574', 'Nigeria', 'Nasarawa', 'State Coordinator'),
  ('ASC-NASARAWA', 'Wubunna', 'Ishaku Gofwen', 'gwubunna@gmail.com', '+234 8038634711', 'Nigeria', 'Nasarawa', 'Assistant State Coordinator'),
  ('SC-NIGER', 'Olagoke', 'Precious Abisola', 'olagokeprecious12@gmail.com', '+2347087583976', 'Nigeria', 'Niger', 'State Coordinator'),
  ('ASC-NIGER', 'Alli', 'Theophilus Umakhe', 'theophilusalli@gmail.com', '+2348085370463', 'Nigeria', 'Niger', 'Assistant State Coordinator'),
  ('SC-OGUN', 'Oni‑Ashamu', 'Funmi', 'mutualimpactcooperative@gmail.com', '07035608804', 'Nigeria', 'Ogun', 'State Coordinator'),
  ('ASC-OGUN', 'Enimehin', 'Temilade Alice', 'fantatemmy@gmail.com', '08164476170', 'Nigeria', 'Ogun', 'Assistant State Coordinator'),
  ('ASC-ONDO', 'Victor', 'Olajide Olorundare', 'olorundarevictor1930@gmail.com', '08062817564', 'Nigeria', 'Ondo', 'Assistant State Coordinator'),
  ('SC-OSUN', 'Odekunle', 'Rolake Gladys', 'nafiugladys@gmail.com', '08033921939', 'Nigeria', 'Osun', 'State Coordinator'),
  ('ASC-OSUN', 'Abioye', 'Omowumi Selimot', 'abioyeselimot3@gmail.com', '07036365239', 'Nigeria', 'Osun', 'Assistant State Coordinator'),
  ('SC-OYO', 'Ishola', 'Iyabode Olajumoke', 'iyaboishola1981@gmail.com', '08034238204', 'Nigeria', 'Oyo', 'State Coordinator'),
  ('SC-PLATEAU', 'Tabitha', 'Solomon', 'tabsy247@gmail.com', '08064338720', 'Nigeria', 'Plateau', 'State Coordinator'),
  ('ASC-PLATEAU', 'Pharm.', 'Mercy Tanko Ndam', 'ndammercytanko@gmail.com', '+2347066957401', 'Nigeria', 'Plateau', 'Assistant State Coordinator'),
  ('SC-RIVERS', 'Kaafor', 'Tombari Elizabeth', 'elizabethkaafortombari@gmail.com', '+234 7034602263', 'Nigeria', 'Rivers', 'State Coordinator'),
  ('ASC-RIVERS', 'Mercy', 'Sor‑aniabari Joshua', 'mercyjoshua211@gmail.com', '+2347039665850', 'Nigeria', 'Rivers', 'Assistant State Coordinator'),
  ('SC-SOKOTO', 'Bernardine', 'Ezeobodo Uche', 'ezeobodouche1975@gmail.com', '08100990052', 'Nigeria', 'Sokoto', 'State Coordinator'),
  ('ASC-SOKOTO', 'Aisha', 'Bello', 'aishaukpe@gmail.com', '08145581612', 'Nigeria', 'Sokoto', 'Assistant State Coordinator'),
  ('SC-TARABA', 'Kaltume', 'Vogadika', 'kvogadika@gmail.com', '+2348131307281', 'Nigeria', 'Taraba', 'State Coordinator'),
  ('ASC-TARABA', 'Gimba', 'John Sule', 'gimbason04@gmail.com', '+2348136836709', 'Nigeria', 'Taraba', 'Assistant State Coordinator'),
  ('SC-YOBE', 'Grace', 'Danladi Bassi', 'gracewudiribaura9@gmail.com', '08053602251 / 07088496239', 'Nigeria', 'Yobe', 'State Coordinator'),
  ('ASC-YOBE', 'Abubakar', 'Dauda Maina', 'abubakardmaina@gmail.com', '+2349036652164', 'Nigeria', 'Yobe', 'Assistant State Coordinator'),
  ('SC-ZAMFARA', 'Asiya', 'Muhammad Bello', 'asiyabello98@gmail.com', '+2348130015022', 'Nigeria', 'Zamfara', 'State Coordinator'),
  ('ASC-ZAMFARA', 'Aishatu', 'Abdu Gusau', 'hifactorinc34@yahoo.com', '08035299181', 'Nigeria', 'Zamfara', 'Assistant State Coordinator')
on conflict (member_code) do update
  set email = coalesce(leader_directory.email, excluded.email),
      phone = coalesce(leader_directory.phone, excluded.phone),
      state = excluded.state;

-- 2 ▸ state-level role mapping ------------------------------------------------
create or replace function public.role_code_for_state_leader(label text)
returns public.role_code language sql immutable as $$
  select case
    when label ilike '%assistant%'
      then 'assistant_state_coordinator'::public.role_code
    else 'state_coordinator'::public.role_code
  end;
$$;

-- 3 ▸ apply_leader_directory: seat state-level claimants correctly ----------
create or replace function public.apply_leader_directory(pid uuid)
returns void language plpgsql
security definer set search_path = public as $$
declare d record; p record; cid uuid; sid uuid; rc public.role_code;
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
         state_region  = coalesce(nullif(state_region, ''), d.state),
         role_applied  = coalesce(nullif(role_applied, ''), d.role_applied),
         phone         = coalesce(nullif(phone, ''), nullif(d.phone, '')),
         membership_no = d.member_code
   where id = pid;
  perform advance_status_on_pass(pid);
  update activation_journeys
     set status = 'deferred'
   where profile_id = pid and status = 'in_progress';
  update leader_directory
     set claimed_profile = pid
   where member_code = d.member_code;

  select ou.id into cid from org_units ou
   where ou.level = 'country' and ou.name = d.country limit 1;
  if cid is null then return; end if;

  if d.state is not null then
    select su.id into sid from org_units su
     where su.parent_id = cid and su.level = 'state_region'
       and su.name = d.state limit 1;
    if sid is not null then
      rc := role_code_for_state_leader(d.role_applied);
      if not exists (select 1 from role_assignments
                      where profile_id = pid and role = rc
                        and org_unit_id = sid and ends_at is null) then
        insert into role_assignments (profile_id, role, org_unit_id)
        values (pid, rc, sid);
      end if;
    end if;
  else
    rc := role_code_for_leader(d.role_applied);
    if not exists (select 1 from role_assignments
                    where profile_id = pid and role = rc
                      and org_unit_id = cid and ends_at is null) then
      insert into role_assignments (profile_id, role, org_unit_id)
      values (pid, rc, cid);
    end if;
  end if;
end $$;

-- 4 ▸ seed the 68: real applications, force-correct codes, and seat --------
do $$
declare d record; hq_unit uuid; app_id uuid; pid uuid;
begin
  perform set_config('wdos.system', '1', true);
  select id into hq_unit from org_units
   where level = 'headquarters' order by created_at limit 1;

  for d in select * from leader_directory where state is not null
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
         set member_no = d.member_code,           -- forced, never coalesced
             status = 'approved',
             decision_reason = coalesce(decision_reason,
               'Established state leader \u2014 State Coordinators Directory'),
             decided_at = coalesce(decided_at, now())
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
        safe_motivation('Established state leader.'),
        'approved', 'Seeded from state coordinators directory', now(),
        d.member_code);
    end if;

    -- already inside WDOS? seat right now, no re-claim needed
    if d.email is not null then
      select id into pid from profiles
       where lower(email) = lower(d.email) and merged_into is null limit 1;
      if pid is not null then
        perform apply_leader_directory(pid);
      end if;
    end if;
  end loop;
end $$;

-- 5 ▸ verification -----------------------------------------------------------
select d.member_code, d.state, d.role_applied,
       d.first_name || ' ' || d.last_name as leader,
       a.member_no as application_code,
       (d.member_code = a.member_no) as matches,
       d.claimed_profile is not null as claimed
  from leader_directory d
  left join applications a on lower(a.email) = lower(d.email)
 where d.state is not null
 order by (d.member_code = a.member_no) asc, d.state;

-- 6 ▸ the Atlas must see unclaimed state seats, not just claimed ones --------
create or replace function public.leaders_atlas()
returns jsonb language plpgsql
security definer set search_path = public as $outer$
declare total_modules int;
begin
  if not is_case_hq() then raise exception 'HQ only'; end if;
  select count(*) into total_modules
    from course_modules cm join courses c on c.id = cm.course_id
   where c.is_active;
  return (
    select coalesce(jsonb_agg(row order by row->>'country',
                              row->>'state', row->>'role_applied',
                              row->>'name'), '[]'::jsonb)
    from (
      select jsonb_build_object(
        'id', p.id, 'name', p.first_name || ' ' || p.last_name,
        'membership_no', p.membership_no, 'role_applied', p.role_applied,
        'country', p.country, 'state', p.state_region, 'lga', p.lga,
        'email', p.email, 'phone', p.phone, 'last_seen', p.last_seen_at,
        'has_login', true,
        'modules_passed', coalesce((
          select count(*) from course_module_passes cmp
            join course_enrollments ce on ce.id = cmp.enrollment_id
           where ce.profile_id = p.id), 0),
        'modules_total', total_modules
      ) as row
      from profiles p where p.is_leader and p.merged_into is null
      union all
      select jsonb_build_object(
        'id', null, 'name', d.first_name || ' ' || d.last_name,
        'membership_no', d.member_code, 'role_applied', d.role_applied,
        'country', d.country, 'state', d.state, 'lga', null,
        'email', d.email, 'phone', d.phone, 'last_seen', null,
        'has_login', false, 'modules_passed', 0,
        'modules_total', total_modules
      ) as row
      from leader_directory d
      where d.claimed_profile is null
        and not exists (select 1 from profiles p2
          where p2.is_leader and p2.merged_into is null
            and upper(p2.membership_no) = upper(d.member_code))
    ) sub);
end; $outer$;
revoke execute on function public.leaders_atlas() from anon;

-- 7 ▸ the code-dispatch email now covers every leader in the directory ----
--     (leader_codes_dispatch() already loops leader_directory generically —
--     these 68 flow through the exact same function with no code change.)

insert into public.schema_migrations (version, name)
values (79, 'state_coordinators') on conflict (version) do nothing;
