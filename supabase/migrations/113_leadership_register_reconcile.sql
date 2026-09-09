-- ============================================================================
-- WDOS Migration 113 — WGMN Volunteer Leadership Master Register (06 Sep 2026)
-- reconciliation (Phase 137)
--   • leader_register: every row of the register as written (25 countries CR/DCR,
--     37 Nigeria states SC/ASC), vacancies and conflicts preserved, never resolved
--     by code. Rows with no name are vacant seats; rows flagged conflict wait for HQ.
--   • register_reconcile(): matches each named row against people already in
--     WDOS (profiles and leader_directory) by normalised name within the same
--     country: matched_login / matched_directory / missing.
--   • register_apply(): adds the MISSING, UNFLAGGED names to leader_directory with
--     generated codes so they appear on Accounts with Create login (email typed
--     there). Conflicted rows are listed, not added.
--   • Nigeria's Country Representative is Hon. Ngunan Addingi (CR-NGA, already in
--     the directory from ADD-NGUNAN-ADDINGI.sql); the register's older CR record is
--     superseded and is NOT added.
-- ============================================================================

create table if not exists public.leader_register (
  id         serial primary key,
  full_name  text,
  role       public.role_code not null,
  country    text not null,
  country_iso text not null,
  state      text,
  status     text,
  note       text,
  conflict   boolean not null default false,
  matched_profile uuid references public.profiles(id) on delete set null,
  matched_code    text,
  applied_code    text,
  reconciled_at   timestamptz
);
alter table public.leader_register enable row level security;
drop policy if exists leader_register_read on public.leader_register;
create policy leader_register_read on public.leader_register for select to authenticated using (public.is_case_hq());
delete from public.leader_register;
insert into public.leader_register (full_name, role, country, country_iso, state, status, note, conflict) values
  ('Hessou Aline Felicienne', 'country_rep', 'Benin', 'BJ', null, 'Active / complete', null, false),
  ('Yorou Barkissou', 'deputy_country_rep', 'Benin', 'BJ', null, 'Active / complete', null, false),
  ('Denne Irene', 'deputy_country_rep', 'Burkina Faso', 'BF', null, 'CR resigned/vacant; DCR inactive - replacement required', 'CR seat vacant; former CR SANOU Kouessessra Esther', false),
  (null, 'country_rep', 'Burkina Faso', 'BF', null, 'CR resigned/vacant; DCR inactive - replacement required', 'CR seat vacant; former CR SANOU Kouessessra Esther', true),
  ('Alice Orly Museli', 'country_rep', 'Burundi', 'BI', null, 'Current CR welcomed July 2026; deputy still to be appointed', null, false),
  (null, 'deputy_country_rep', 'Burundi', 'BI', null, 'Current CR welcomed July 2026; deputy still to be appointed', null, true),
  ('Mandunh Mbohou Awawou', 'country_rep', 'Cameroon', 'CM', null, 'Active / complete', null, false),
  ('Kwedi Pyo Lydienne', 'deputy_country_rep', 'Cameroon', 'CM', null, 'Active / complete', null, false),
  ('Amina Bello', 'country_rep', 'Central African Republic', 'CF', null, 'Active / complete', null, false),
  ('Koradjim Lionel', 'deputy_country_rep', 'Central African Republic', 'CF', null, 'Active / complete', null, false),
  ('Hinberka Beblere Florice', 'country_rep', 'Chad', 'TD', null, 'Active / complete - deputy name from leadership programme record', null, false),
  ('Fatime Idriss', 'deputy_country_rep', 'Chad', 'TD', null, 'Active / complete - deputy name from leadership programme record', null, false),
  ('Bizonzi Prinelly Sergie Bonnel', 'country_rep', 'Republic of the Congo', 'CG', null, 'CR active; deputy position vacant', null, false),
  (null, 'deputy_country_rep', 'Republic of the Congo', 'CG', null, 'CR active; deputy position vacant', null, true),
  ('Soro Gnimey Cintia Louisette', 'country_rep', 'Cote d''Ivoire', 'CI', null, 'Active / complete', null, false),
  ('Attemene Yannick', 'deputy_country_rep', 'Cote d''Ivoire', 'CI', null, 'Active / complete', null, false),
  ('Furaha Maroy Judith', 'country_rep', 'Democratic Republic of the Congo', 'CD', null, 'Active / complete', null, false),
  ('Nshembe Chishungu Eric Nice', 'deputy_country_rep', 'Democratic Republic of the Congo', 'CD', null, 'Active / complete', null, false),
  ('Haddy Semega Janneh', 'country_rep', 'The Gambia', 'GM', null, 'CR inactive; DCR currently recorded as vacant/to verify', 'Older DCR record: Ebrima Jallow - verify', false),
  (null, 'deputy_country_rep', 'The Gambia', 'GM', null, 'CR inactive; DCR currently recorded as vacant/to verify', 'Older DCR record: Ebrima Jallow - verify', true),
  ('Doreen Serwaa Ampae', 'country_rep', 'Ghana', 'GH', null, 'Active / complete', null, false),
  ('Esther Takyiwaah Prempeh', 'deputy_country_rep', 'Ghana', 'GH', null, 'Active / complete', null, false),
  ('Koulako Kamissoko', 'country_rep', 'Guinea', 'GN', null, 'Active / complete', null, false),
  ('Bah Ramata Benny', 'deputy_country_rep', 'Guinea', 'GN', null, 'Active / complete', null, false),
  ('Mariama Fati', 'country_rep', 'Guinea-Bissau', 'GW', null, 'Active / complete', null, false),
  ('Carlos Embalo', 'deputy_country_rep', 'Guinea-Bissau', 'GW', null, 'Active / complete', null, false),
  ('Sharon Amondi', 'country_rep', 'Kenya', 'KE', null, 'CR requires engagement; deputy recorded active', null, false),
  ('Lilian Songok', 'deputy_country_rep', 'Kenya', 'KE', null, 'CR requires engagement; deputy recorded active', null, false),
  ('Ainasoa Rakotoniera', 'country_rep', 'Madagascar', 'MG', null, 'CR active; DCR unresponsive / requires review', null, false),
  ('Tinarivo Baby Emmanuel', 'deputy_country_rep', 'Madagascar', 'MG', null, 'CR active; DCR unresponsive / requires review', null, false),
  ('Salimata Coulibaly', 'country_rep', 'Mali', 'ML', null, 'Active / complete', null, false),
  ('Binta Coulibaly', 'deputy_country_rep', 'Mali', 'ML', null, 'Active / complete', null, false),
  ('Safaa Hachimi', 'country_rep', 'Morocco', 'MA', null, 'CR unresponsive; DCR vacant', 'Older DCR record Nadia Alaoui not current', false),
  (null, 'deputy_country_rep', 'Morocco', 'MA', null, 'CR unresponsive; DCR vacant', 'Older DCR record Nadia Alaoui not current', true),
  ('Abdou Mariama', 'country_rep', 'Niger', 'NE', null, 'Active / complete', null, false),
  ('Zaleha Salha Abou', 'deputy_country_rep', 'Niger', 'NE', null, 'Active / complete', null, false),
  ('Ngunan Addingi', 'country_rep', 'Nigeria', 'NG', null, 'Current CR confirmed Aug 2026; DCR identity requires WDOS verification', 'Older DCR record: Maureen Nkechi Chukwuemeka - verify; older CR record Haruna Amina superseded', false),
  (null, 'deputy_country_rep', 'Nigeria', 'NG', null, 'Current CR confirmed Aug 2026; DCR identity requires WDOS verification', 'Older DCR record: Maureen Nkechi Chukwuemeka - verify; older CR record Haruna Amina superseded', true),
  ('Irene Mukanzayituriki', 'country_rep', 'Rwanda', 'RW', null, 'Both recorded unresponsive - replacement/re-engagement required', null, false),
  ('Florence Umutoni', 'deputy_country_rep', 'Rwanda', 'RW', null, 'Both recorded unresponsive - replacement/re-engagement required', null, false),
  ('Sophie Dior Diack', 'country_rep', 'Senegal', 'SN', null, 'CR active; DCR unresponsive / requires review', null, false),
  ('Penda Kande', 'deputy_country_rep', 'Senegal', 'SN', null, 'CR active; DCR unresponsive / requires review', null, false),
  ('Tshegofatso Gama', 'country_rep', 'South Africa', 'ZA', null, 'CR active; DCR vacant', null, false),
  (null, 'deputy_country_rep', 'South Africa', 'ZA', null, 'CR active; DCR vacant', null, true),
  ('Pakou Akouvi Emefa Ornela', 'country_rep', 'Togo', 'TG', null, 'Active / complete', null, false),
  ('Soriyath Lisette Maelle Bertille Gantua', 'deputy_country_rep', 'Togo', 'TG', null, 'Active / complete', null, false),
  ('Nesrine Ben Saad', 'country_rep', 'Tunisia', 'TN', null, 'CR inactive / medical absence; DCR vacant', 'Older DCR record Nadia Thligene not current', false),
  (null, 'deputy_country_rep', 'Tunisia', 'TN', null, 'CR inactive / medical absence; DCR vacant', 'Older DCR record Nadia Thligene not current', true),
  ('Zalwango Grace', 'country_rep', 'Uganda', 'UG', null, 'CR active; DCR vacant', 'Older DCR record Grace Namutebi not current', false),
  (null, 'deputy_country_rep', 'Uganda', 'UG', null, 'CR active; DCR vacant', 'Older DCR record Grace Namutebi not current', true),
  ('Ogbonnaya Uwaezuoke Ndukwe', 'state_coordinator', 'Nigeria', 'NG', 'Abia', 'Recorded - verify active status', null, false),
  ('Onyinyechi Anne Nwafor', 'assistant_state_coordinator', 'Nigeria', 'NG', 'Abia', 'Recorded - verify active status', null, false),
  ('Milcah Gaman', 'state_coordinator', 'Nigeria', 'NG', 'Adamawa', 'Recorded - verify active status', null, false),
  ('Hadiza Umar', 'assistant_state_coordinator', 'Nigeria', 'NG', 'Adamawa', 'Recorded - verify active status', null, false),
  ('Ikouwem Oku Isaac', 'state_coordinator', 'Nigeria', 'NG', 'Akwa Ibom', 'Recorded - verify active status', null, false),
  ('Essien Iniobong', 'assistant_state_coordinator', 'Nigeria', 'NG', 'Akwa Ibom', 'Recorded - verify active status', null, false),
  ('Chioma Okeoma Okonkwo', 'state_coordinator', 'Nigeria', 'NG', 'Anambra', 'Source-name variation - WDOS verify', 'SC also recorded as Chioma Nwabiawa', true),
  ('Chidubem Godfrey Nwachinemere', 'assistant_state_coordinator', 'Nigeria', 'NG', 'Anambra', 'Source-name variation - WDOS verify', 'SC also recorded as Chioma Nwabiawa', true),
  ('Hajara Umaru', 'state_coordinator', 'Nigeria', 'NG', 'Bauchi', 'Recorded - verify active status', null, false),
  ('Kubura Rabiu', 'assistant_state_coordinator', 'Nigeria', 'NG', 'Bauchi', 'Recorded - verify active status', null, false),
  ('Doris Nurse-ere Ndoboke', 'state_coordinator', 'Nigeria', 'NG', 'Bayelsa', 'Source conflict - WDOS verify', 'ASC conflict: Ebiere Stella / Preye Alagoa', true),
  (null, 'assistant_state_coordinator', 'Nigeria', 'NG', 'Bayelsa', 'Source conflict - WDOS verify', 'ASC conflict: Ebiere Stella / Preye Alagoa', true),
  ('Elizabeth Dooshima Akoh Kohol', 'state_coordinator', 'Nigeria', 'NG', 'Benue', 'Recorded - verify active status', null, false),
  ('Ogoyi Ochanya Gloria', 'assistant_state_coordinator', 'Nigeria', 'NG', 'Benue', 'Recorded - verify active status', null, false),
  ('Ruqayyah Abba Waziri', 'state_coordinator', 'Nigeria', 'NG', 'Borno', 'Recorded - verify active status', null, false),
  ('Mary Dona Terry', 'assistant_state_coordinator', 'Nigeria', 'NG', 'Borno', 'Recorded - verify active status', null, false),
  ('Inya Elemi', 'state_coordinator', 'Nigeria', 'NG', 'Cross River', 'Recorded - verify active status', null, false),
  ('James Ofem Otu', 'assistant_state_coordinator', 'Nigeria', 'NG', 'Cross River', 'Recorded - verify active status', null, false),
  ('Florence Ogonegbu', 'state_coordinator', 'Nigeria', 'NG', 'Delta', 'Recorded - verify active status', null, false),
  ('Erhuvwu Lisa Tarhe', 'assistant_state_coordinator', 'Nigeria', 'NG', 'Delta', 'Recorded - verify active status', null, false),
  ('Nwali Esther Ndidi', 'state_coordinator', 'Nigeria', 'NG', 'Ebonyi', 'Source-name variation - WDOS verify', 'SC also recorded as Esther Onyeka', true),
  ('Oreke Chinazor', 'assistant_state_coordinator', 'Nigeria', 'NG', 'Ebonyi', 'Source-name variation - WDOS verify', 'SC also recorded as Esther Onyeka', true),
  ('Christy Okpedo', 'state_coordinator', 'Nigeria', 'NG', 'Edo', 'Recorded - verify active status', null, false),
  ('Emonvuon Helen', 'assistant_state_coordinator', 'Nigeria', 'NG', 'Edo', 'Recorded - verify active status', null, false),
  ('Adeniyi Ijeoma Kolawole', 'state_coordinator', 'Nigeria', 'NG', 'Ekiti', 'Recorded / verify against WDOS', null, false),
  ('Hammed Omolayo Bello', 'assistant_state_coordinator', 'Nigeria', 'NG', 'Ekiti', 'Recorded / verify against WDOS', null, false),
  ('Ruth Obioma Ngoka', 'state_coordinator', 'Nigeria', 'NG', 'Enugu', 'Recorded - verify active status', null, false),
  ('Asika Christiana Ogechi', 'assistant_state_coordinator', 'Nigeria', 'NG', 'Enugu', 'Recorded - verify active status', null, false),
  ('Miriam Monday Umar', 'state_coordinator', 'Nigeria', 'NG', 'Gombe', 'Recorded - verify active status', null, false),
  ('Elizabeth David Ankama', 'assistant_state_coordinator', 'Nigeria', 'NG', 'Gombe', 'Recorded - verify active status', null, false),
  ('Theresa Ohanuba', 'state_coordinator', 'Nigeria', 'NG', 'Imo', 'Source conflict - WDOS verify', 'ASC conflict: Barr. Oluchi Joy / Umealor Joy', true),
  (null, 'assistant_state_coordinator', 'Nigeria', 'NG', 'Imo', 'Source conflict - WDOS verify', 'ASC conflict: Barr. Oluchi Joy / Umealor Joy', true),
  ('Umma Mohammed Lawal', 'state_coordinator', 'Nigeria', 'NG', 'Jigawa', 'Recorded - verify active status', null, false),
  ('Aisha Muhammad Sabo', 'assistant_state_coordinator', 'Nigeria', 'NG', 'Jigawa', 'Recorded - verify active status', null, false),
  ('Nafisa Shuaibu', 'state_coordinator', 'Nigeria', 'NG', 'Kaduna', 'Recorded - verify active status', null, false),
  ('Jemimah Adamu Dattijo', 'assistant_state_coordinator', 'Nigeria', 'NG', 'Kaduna', 'Recorded - verify active status', null, false),
  ('Maryam Mshelia', 'state_coordinator', 'Nigeria', 'NG', 'Kano', 'Recorded - verify active status', null, false),
  ('Jennifer Azi', 'assistant_state_coordinator', 'Nigeria', 'NG', 'Kano', 'Recorded - verify active status', null, false),
  ('Murjanatu Yakubu', 'state_coordinator', 'Nigeria', 'NG', 'Katsina', 'Recorded - verify active status', null, false),
  ('Rahab Sani', 'assistant_state_coordinator', 'Nigeria', 'NG', 'Katsina', 'Recorded - verify active status', null, false),
  ('Esther Hindi', 'state_coordinator', 'Nigeria', 'NG', 'Kebbi', 'Recorded - verify active status', null, false),
  ('Lami Abdullah', 'assistant_state_coordinator', 'Nigeria', 'NG', 'Kebbi', 'Recorded - verify active status', null, false),
  ('Ahmed Safinat Lami', 'state_coordinator', 'Nigeria', 'NG', 'Kogi', 'Recorded - verify active status', null, false),
  ('Salimat Mohammed Mamma', 'assistant_state_coordinator', 'Nigeria', 'NG', 'Kogi', 'Recorded - verify active status', null, false),
  ('Ojo Olasunkami Susan', 'state_coordinator', 'Nigeria', 'NG', 'Kwara', 'Recorded - verify active status', null, false),
  ('Abdulganeey Abdullateef Okubii', 'assistant_state_coordinator', 'Nigeria', 'NG', 'Kwara', 'Recorded - verify active status', null, false),
  ('Ojo Ayodele Adedoyin', 'state_coordinator', 'Nigeria', 'NG', 'Lagos', 'Recorded - verify active status', null, false),
  ('Ejim Esther Chinonyerem', 'assistant_state_coordinator', 'Nigeria', 'NG', 'Lagos', 'Recorded - verify active status', null, false),
  ('Joy Naveh', 'state_coordinator', 'Nigeria', 'NG', 'Nasarawa', 'Recorded - verify active status', null, false),
  ('Wubunna Ishaku Gofwen', 'assistant_state_coordinator', 'Nigeria', 'NG', 'Nasarawa', 'Recorded - verify active status', null, false),
  ('Olagoke Precious Abisola', 'state_coordinator', 'Nigeria', 'NG', 'Niger', 'Recorded - verify active status', null, false),
  ('Alli Theophilus Umakhe', 'assistant_state_coordinator', 'Nigeria', 'NG', 'Niger', 'Recorded - verify active status', null, false),
  ('Oni-Ashamu Funmi', 'state_coordinator', 'Nigeria', 'NG', 'Ogun', 'Recorded - verify active status', null, false),
  ('Enimehin Temilade Alice', 'assistant_state_coordinator', 'Nigeria', 'NG', 'Ogun', 'Recorded - verify active status', null, false),
  ('Erefe O. Gbubemi', 'state_coordinator', 'Nigeria', 'NG', 'Ondo', 'Recorded - verify active status', null, false),
  ('Victor Olajide Olorundare', 'assistant_state_coordinator', 'Nigeria', 'NG', 'Ondo', 'Recorded - verify active status', null, false),
  ('Odekunle Rolake Gladys', 'state_coordinator', 'Nigeria', 'NG', 'Osun', 'Recorded - verify active status', null, false),
  ('Abioye Omowumi Selimot', 'assistant_state_coordinator', 'Nigeria', 'NG', 'Osun', 'Recorded - verify active status', null, false),
  ('Ishola Iyabode Olajumoke', 'state_coordinator', 'Nigeria', 'NG', 'Oyo', 'Source conflict - WDOS verify', 'Register marks the row as source conflict', true),
  ('Mojisola Oladipo', 'assistant_state_coordinator', 'Nigeria', 'NG', 'Oyo', 'Source conflict - WDOS verify', 'Register marks the row as source conflict', true),
  ('Tabitha Solomon', 'state_coordinator', 'Nigeria', 'NG', 'Plateau', 'Recorded - verify active status', null, false),
  ('Mercy Tanko Ndam', 'assistant_state_coordinator', 'Nigeria', 'NG', 'Plateau', 'Recorded - verify active status', null, false),
  ('Kaafor Tombari Elizabeth', 'state_coordinator', 'Nigeria', 'NG', 'Rivers', 'Recorded - verify active status', null, false),
  ('Mercy Sor-aniabari Joshua', 'assistant_state_coordinator', 'Nigeria', 'NG', 'Rivers', 'Recorded - verify active status', null, false),
  ('Bernardine Ezeobodo Uche', 'state_coordinator', 'Nigeria', 'NG', 'Sokoto', 'Recorded - verify active status', null, false),
  ('Aisha Bello', 'assistant_state_coordinator', 'Nigeria', 'NG', 'Sokoto', 'Recorded - verify active status', null, false),
  ('Kaltume Vogadika', 'state_coordinator', 'Nigeria', 'NG', 'Taraba', 'Recorded - verify active status', null, false),
  ('Gimba John Sule', 'assistant_state_coordinator', 'Nigeria', 'NG', 'Taraba', 'Recorded - verify active status', null, false),
  (null, 'state_coordinator', 'Nigeria', 'NG', 'Yobe', 'Source conflict - WDOS verify', 'SC conflict: Hadiza Adamu Iyam / Grace Danladi Bassi', true),
  ('Abubakar Dauda Maina', 'assistant_state_coordinator', 'Nigeria', 'NG', 'Yobe', 'Source conflict - WDOS verify', 'SC conflict: Hadiza Adamu Iyam / Grace Danladi Bassi', true),
  ('Asiya Muhammad Bello', 'state_coordinator', 'Nigeria', 'NG', 'Zamfara', 'Source conflict - WDOS verify', 'Register marks the row as source conflict', true),
  ('Aishatu Abdu Gusau', 'assistant_state_coordinator', 'Nigeria', 'NG', 'Zamfara', 'Source conflict - WDOS verify', 'Register marks the row as source conflict', true),
  ('Rahila Success Daniel', 'state_coordinator', 'Nigeria', 'NG', 'FCT', 'Recorded - verify active status', null, false),
  ('Mise Oluseyi Olufunke', 'assistant_state_coordinator', 'Nigeria', 'NG', 'FCT', 'Recorded - verify active status', null, false);

-- names: lower, drop titles and punctuation, order-insensitive token set
create or replace function public.name_tokens(n text) returns text[]
language sql immutable as $$
  select array(select x from unnest(string_to_array(
    regexp_replace(lower(coalesce(n, '')), '\b(hon|rt|dr|barr|pharm|lady|mrs|mr|ms|miss|chief|alhaji|alhaja|engr|prof|rev|sir)\.?\b|[^a-z\s]', ' ', 'g'), ' ')) x
    where x <> '' order by x);
$$;
create or replace function public.name_match(a text, b text) returns boolean
language sql immutable as $$
  select (select count(*) from unnest(name_tokens(a)) t where t = any(name_tokens(b))) >= 2
      or (array_length(name_tokens(a), 1) = 1 and array_length(name_tokens(b), 1) = 1 and name_tokens(a) = name_tokens(b));
$$;

create or replace function public.register_reconcile()
returns table (id int, full_name text, role public.role_code, country text, state text, result text, matched_name text, matched_code text, has_login boolean, conflict boolean, status text, note text)
language plpgsql security definer set search_path = public as $$
begin
  if not is_case_hq() then raise exception 'HQ only'; end if;
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
  if not is_case_hq() then raise exception 'HQ only'; end if;
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
values (113, 'leadership_register_reconcile') on conflict (version) do nothing;
