-- ============================================================================
-- WDOS Migration 094 — Institute Outreach Module (Phase 106)
--
-- Holds the 46-organisation invitation list, sends the founder's letter
-- through the EXISTING email layer (migration 035's send_email(),
-- respecting the email_enabled switch), and tracks each organisation
-- from Sent -> Replied -> Nominations received -> Onboarded.
--
-- Reuses, does not rebuild: send_email(to_email, to_name, subj, html),
-- the email_secrets vault, org_settings.email_enabled, is_case_hq(),
-- and the 'hq' synthetic module already granted via is_hq_staff() in
-- my_modules() (migration 015) — no module_access rows needed, #/outreach
-- is gated exactly like #/leaders and #/spotlight-review already are.
-- ============================================================================

create table public.outreach_contacts (
  id                 uuid primary key default gen_random_uuid(),
  organisation       text not null,
  category           text,
  country            text,
  region             text,
  language           text default 'en',
  email              text not null unique,
  secondary_email    text,
  website            text,
  leader_name        text,
  leader_title       text,
  needs_verification boolean not null default false,
  notes              text,
  status             text not null default 'pending'
    check (status in ('pending','held','sent','bounced','replied',
                      'nominations_received','onboarded')),
  sent_at            timestamptz,
  status_updated_at  timestamptz,
  status_updated_by  uuid references profiles(id),
  created_at         timestamptz not null default now()
);
alter table public.outreach_contacts enable row level security;
create policy outreach_hq_all on public.outreach_contacts
  for all to authenticated using (public.is_case_hq())
  with check (public.is_case_hq());

-- the 46 organisations, seeded verbatim from woddi-outreach-emails.csv
insert into public.outreach_contacts
  (organisation, category, country, region, language, email,
   secondary_email, website, leader_name, leader_title,
   needs_verification, notes, status)
values
  ('WIMBIZ (Women in Management, Business & Public Service)', 'Women''s NGO / network', 'Nigeria', 'West Africa', 'en', 'wimbiz@wimbiz.org', null, 'https://wimbiz.org', 'Omowunmi Akingbohungbe', 'Executive Director', false, null, 'pending'),
  ('FIDA Nigeria (Int''l Federation of Women Lawyers)', 'Professional association', 'Nigeria', 'West Africa', 'en', 'fidanigeria@yahoo.com', 'fidaenugu@fida.org.ng', 'https://fida.org.ng', 'Oyinkansola Badejo-Okusanya SAN', 'National President', true, 'Yahoo address but listed on official site; secondary is Enugu chapter', 'held'),
  ('Women''s Consortium of Nigeria (WOCON)', 'Women''s NGO / network', 'Nigeria', 'West Africa', 'en', 'info@womenconsortiumofnigeria.org', 'wocon95@yahoo.com', 'https://womenconsortiumofnigeria.org', 'Henrietta Morenike Omaiboje', 'Executive Director', true, 'Both addresses on official site; yahoo is older', 'held'),
  ('Women Impacting Nigeria (WIN) Foundation', 'Women''s NGO / network', 'Nigeria', 'West Africa', 'en', 'info@womenimpactingnigeria.org', null, 'https://womenimpactingnigeria.org', null, null, false, null, 'pending'),
  ('Women Empowerment through Education (WomenETE)', 'Women''s NGO / network', 'Nigeria', 'West Africa', 'en', 'admin@womenete.org', null, 'https://womenete.org', null, null, false, 'Enugu-based; education focus', 'pending'),
  ('FOMWAN (Federation of Muslim Women''s Associations in Nigeria)', 'Faith-based', 'Nigeria', 'West Africa', 'en', 'hq@fomwanofficial.org', null, 'https://www.fomwanofficial.org', 'Alhaja Rafiah Idowu Sanni', 'National President (Amirah)', false, '80,000+ members; 36 states + FCT; strong multiplier', 'pending'),
  ('YWCA of Nigeria', 'Faith-based', 'Nigeria', 'West Africa', 'en', 'ywca_nig@yahoo.com', null, 'https://ywcanigeria.org.ng', null, null, true, '20,000 members, 132 branches; verify yahoo address', 'held'),
  ('Medical Women''s Association of Nigeria (MWAN)', 'Professional association', 'Nigeria', 'West Africa', 'en', 'info@mwan.org', null, 'https://www.mwan.org', 'Dr Zainab Kwaru Mohammad-Idris', 'National President', false, '~7,000 female doctors across 34 states', 'pending'),
  ('Women in Technology in Nigeria (WITIN)', 'Professional association', 'Nigeria', 'West Africa', 'en', 'info@witin.org', null, 'https://witin.org', 'Martha Omoekpen Alade', 'Executive Director', false, 'Presence in 36 states + FCT', 'pending'),
  ('National Council of Women''s Societies (NCWS) Nigeria', 'Umbrella network', 'Nigeria', 'West Africa', 'en', 'ncwsnigeria@gmail.com', null, null, null, null, false, 'Umbrella body of women''s societies in Nigeria; strong multiplier; email supplied by Azeez', 'pending'),
  ('WiLDAF Ghana', 'Pan-African umbrella (national chapter)', 'Ghana', 'West Africa', 'en', 'info@wildaf.org', null, 'https://wildaf-ao.org/en/wildaf-ghana-en/', null, null, false, null, 'pending'),
  ('NETRIGHT (Network for Women''s Rights in Ghana)', 'Umbrella network', 'Ghana', 'West Africa', 'en', 'info@netrightghana.org', null, 'https://netrightghana.org', null, null, false, '187 org members + 274 individuals; multiplier', 'pending'),
  ('YWCA Ghana', 'Faith-based', 'Ghana', 'West Africa', 'en', 'ywcaghana@gmail.com', null, null, null, null, true, 'From World YWCA member directory; verify', 'held'),
  ('African Women''s Development Fund (AWDF)', 'Pan-African umbrella', 'Ghana (pan-African)', 'West Africa', 'en', 'awdf@awdf.org', 'grants@awdf.org', 'https://awdf.org', null, null, false, '1,300+ grantee orgs in 43 countries; multiplier', 'pending'),
  ('Moremi Initiative (MILEAD Fellowship)', 'Young women''s leadership', 'Ghana (pan-African)', 'West Africa', 'en', 'info@moremiinitiative.org', 'partners@moremiinitiative.org', 'https://moremiinitiative.org', null, null, false, 'Young women 19-25; alumni in 26+ countries', 'pending'),
  ('50/50 Group of Sierra Leone', 'Young women / leadership', 'Sierra Leone', 'West Africa', 'en', 'fiftyfiftysierraleone@gmail.com', null, 'https://fiftyfiftysierraleone.org', null, null, false, '5,000+ women trained in leadership', 'pending'),
  ('GAMCOTRAP', 'Women''s NGO / network', 'Gambia', 'West Africa', 'en', 'gamcotrap@yahoo.com', null, 'https://gamcotrap.org', 'Dr Isatou Touray', 'Co-founder', true, 'Pre-2020 listing; verify before send', 'held'),
  ('Reseau Siggil Jigeen', 'Umbrella network', 'Senegal', 'West Africa (Francophone)', 'fr', 'reseausiggiljigeensn@gmail.com', null, 'https://siggiljigeen.org', 'Mme Safietou Diop', 'Presidente', false, '16+ member orgs reaching 12,000+ women; send French version', 'pending'),
  ('Association des Juristes Senegalaises (AJS)', 'Professional association', 'Senegal', 'West Africa (Francophone)', 'fr', 'dioufastou9@yahoo.fr', null, 'https://femmesjuristes.org', null, null, true, 'Personal-style address from directory; verify', 'held'),
  ('AFAO / WAWA (West African Women''s Association)', 'Regional umbrella', 'Senegal (ECOWAS region)', 'West Africa (Francophone)', 'fr', 'afaowawa@afaowawa.org', null, 'https://afaowawa.org', 'Khady Fall Tall', 'President', true, 'ECOWAS-wide; multiplier; verify', 'held'),
  ('OFACI (Organisation des Femmes Actives de Cote d''Ivoire)', 'Women''s NGO / network', 'Cote d''Ivoire', 'West Africa (Francophone)', 'fr', 'infos@ofaci.org', null, 'https://ofaci.org', null, null, true, 'Verify before send', 'held'),
  ('AFJCI (Association des Femmes Juristes de Cote d''Ivoire)', 'Professional association', 'Cote d''Ivoire', 'West Africa (Francophone)', 'fr', 'info@afjci.org', null, 'https://afjci.org', null, null, false, null, 'pending'),
  ('WiLDAF West Africa (WiLDAF-AO)', 'Regional umbrella', 'Togo (11 countries)', 'West Africa (Francophone)', 'fr', 'wildaf@wildaf-ao.org', 'wildaf_ao@yahoo.com', 'https://wildaf-ao.org', 'Antoinette Yawavi Mbrou', 'Regional Coordinator', false, '500 orgs / 1,200 individuals in 27 countries via WiLDAF network; multiplier', 'pending'),
  ('Women for a Change Cameroon (WFAC)', 'Women''s NGO / network', 'Cameroon', 'Central Africa', 'en', 'programs.wfac@gmail.com', null, 'https://wfaccameroon.org', 'Zoneziwoh Mbondgulo-Wondieh', 'Founder / Executive Director', false, 'Anglophone Cameroon-based', 'pending'),
  ('SOFEPADI', 'Women''s NGO / network', 'DR Congo', 'Central Africa (Francophone)', 'fr', 'info@sofepadirdc.org', null, 'https://sofepadirdc.org', 'Julienne Lusenge', 'Co-founder / President', false, 'Send French version', 'pending'),
  ('FEMNET (African Women''s Development & Communication Network)', 'Pan-African umbrella', 'Kenya (pan-African)', 'East Africa', 'en', 'director@femnet.or.ke', null, 'https://femnet.org', 'Memory Zonde-Kachambwa', 'Executive Director', true, '800+ members in 49 countries; address from older directory - verify or use femnet.org contact page; top multiplier', 'held'),
  ('FAWE Kenya (Forum for African Women Educationalists)', 'Pan-African umbrella (national chapter)', 'Kenya', 'East Africa', 'en', 'info@fawe.or.ke', null, 'https://fawe.or.ke', null, null, false, 'FAWE has 34 national chapters; ask HQ (fawe.org) to circulate; multiplier', 'pending'),
  ('YWCA Kenya', 'Faith-based', 'Kenya', 'East Africa', 'en', 'info@ywcakenya.org', null, 'https://www.ywcakenya.org', null, null, false, 'Founded 1912', 'pending'),
  ('Uganda Women''s Network (UWONET)', 'Umbrella network', 'Uganda', 'East Africa', 'en', 'info@uwonet.or.ug', null, 'https://www.uwonet.or.ug', 'Rita H. Aciro-Lakor', 'Executive Director', false, 'Umbrella of 23 national women''s orgs; multiplier', 'pending'),
  ('Akina Mama wa Afrika (AMwA)', 'Pan-African umbrella', 'Uganda (pan-African)', 'East Africa', 'en', 'amwa@akinamamawaafrika.org', null, 'https://akinamamawaafrika.org', 'Eunice Musiime', 'Executive Director', false, 'Feminist leadership development since 1985', 'pending'),
  ('WiLDAF Tanzania', 'Pan-African umbrella (national chapter)', 'Tanzania', 'East Africa', 'en', 'info@wildaftanzania.or.tz', 'wildaftanzania@gmail.com', 'https://wildaftanzania.or.tz', null, null, false, null, 'pending'),
  ('YWCA Tanzania', 'Faith-based', 'Tanzania', 'East Africa', 'en', 'info@ywcatz.org', null, null, null, null, true, 'From World YWCA member directory; verify', 'held'),
  ('Ethiopian Women Lawyers Association (EWLA)', 'Professional association', 'Ethiopia', 'East Africa', 'en', 'info@ewla-et.org', null, 'https://ewla-et.org', null, null, false, 'Founded 1995', 'pending'),
  ('Graca Machel Trust', 'Pan-African umbrella', 'South Africa (20 countries)', 'Southern Africa', 'en', 'info@gracamacheltrust.org', null, 'https://gracamacheltrust.org', null, null, false, 'Runs Network for African Business Women; multiplier', 'pending'),
  ('Gender Links', 'Regional network', 'South Africa (SADC region)', 'Southern Africa', 'en', 'samanager@genderlinks.org.za', null, 'https://genderlinks.org.za', null, null, false, 'Southern African gender network', 'pending'),
  ('YWCA Zimbabwe', 'Faith-based', 'Zimbabwe', 'Southern Africa', 'en', 'ywcazim@yahoo.com', null, null, null, null, true, 'From World YWCA member directory; verify', 'held'),
  ('Femmes Africa Solidarite (FAS)', 'Pan-African umbrella', 'Pan-African (Geneva/NY/Dakar)', 'Pan-African', 'fr', 'advocacydirector@fasngo.org', null, 'https://www.fasngo.org', null, null, true, 'Older directory listing; verify', 'held'),
  ('Egyptian Center for Women''s Rights (ECWR)', 'Women''s NGO / network', 'Egypt', 'North Africa', 'ar', 'ecwr@ecwronline.org', null, 'https://ecwronline.org', 'Nehad Aboul Komsan', 'Chairperson', false, 'Arabic/English', 'pending'),
  ('ADFM (Association Democratique des Femmes du Maroc)', 'Women''s NGO / network', 'Morocco', 'North Africa', 'fr', 'adfm.ass@gmail.com', null, 'https://adfm.ma', 'Nabia Haddouche', 'Presidente Nationale', false, 'French/Arabic', 'pending'),
  ('UAF (Union de l''Action Feminine)', 'Women''s NGO / network', 'Morocco', 'North Africa', 'fr', 'uafannajda@gmail.com', null, 'https://uaf.ma', null, null, false, '~32 sections; French/Arabic', 'pending'),
  ('Solidarite Feminine', 'Women''s NGO / network', 'Morocco', 'North Africa', 'fr', 'solfem.m@gmail.com', null, null, null, null, false, 'Support for single mothers', 'pending'),
  ('Jossour Forum des Femmes Marocaines', 'Women''s NGO / network', 'Morocco', 'North Africa', 'fr', 'jossourffm@yahoo.fr', null, null, null, null, true, 'Older listing; verify', 'held'),
  ('FLDDF (Federation de la Ligue Democratique des Droits des Femmes)', 'Women''s NGO / network', 'Morocco', 'North Africa', 'fr', 'federation_lddf@live.fr', null, null, 'Fouzia Asouli', 'Secretary General', true, 'Older listing; verify', 'held'),
  ('AFTURD', 'Women''s NGO / network', 'Tunisia', 'North Africa', 'fr', 'afturd@gmail.com', null, 'https://afturd.org', null, null, false, 'French/Arabic', 'pending'),
  ('ATFD (Association Tunisienne des Femmes Democrates)', 'Women''s NGO / network', 'Tunisia', 'North Africa', 'fr', 'contact@atfd-tunisie.org', null, 'https://atfd-tunisie.org', null, null, true, 'MANUAL REVIEW: reported suspension by authorities in 2025 - confirm status before contacting', 'held'),
  ('Nazra for Feminist Studies', 'Women''s NGO / network', 'Egypt', 'North Africa', 'ar', 'info@nazra.org', null, 'https://nazra.org', 'Mozn Hassan', 'Founder / Executive Director', true, 'MANUAL REVIEW: operating under state restrictions', 'held');

-- the founder's letter, verbatim — greeting personalises to leader_name,
-- falling back to "Esteemed Leader" when none is on file
create or replace function public.outreach_letter_html(p_leader_name text)
returns text language sql immutable as $$
  select
    '<div style="font-family:Arial,Helvetica,sans-serif;max-width:600px;'
    || 'margin:0 auto;border:1px solid #eee;border-radius:10px;overflow:hidden">'
    || '<div style="background:#D4006A;color:#fff;padding:20px 24px;'
    || 'font-size:22px;font-weight:800;">WODDI</div>'
    || '<div style="padding:24px;">'
    || '<p style="color:#111;font-weight:700;font-size:17px;margin:0 0 16px;">'
    || 'Invitation to Nominate a Minimum of Ten (10) Women for the Pioneer '
    || 'WODDI Institute Learning Opportunity \u2013 September 2026</p>'
    || '<p style="color:#333;line-height:1.7;">Dear '
    || coalesce(nullif(btrim(p_leader_name), ''), 'Esteemed Leader') || ',</p>'
    || '<p style="color:#333;line-height:1.7;margin:0 0 14px;">Greetings from the Women of Divine Destiny Initiative (WODDI).</p><p style="color:#333;line-height:1.7;margin:0 0 14px;">As part of our commitment to advancing, developing and meaningfully including African women, WODDI is pleased to extend this Special Consideration Invitation to selected women-focused organisations across Africa.</p><p style="color:#333;line-height:1.7;margin:0 0 14px;">Your organisation is invited to nominate a minimum of ten (10) women to participate in the Pioneer WODDI Institute Learning Cohort, commencing in September 2026.</p><p style="color:#333;line-height:1.7;margin:0 0 14px;">About the WODDI Institute<br>The WODDI Institute was created to help women strengthen their identity, confidence, purpose, leadership capacity and ability to translate their potential into meaningful personal, organisational and societal impact.</p><p style="color:#333;line-height:1.7;margin:0 0 14px;">At the heart of the Institute is a simple conviction:<br>When a woman is strengthened, informed, equipped and properly positioned, the impact extends beyond her life to her family, organisation, community and nation.</p><p style="color:#333;line-height:1.7;margin:0 0 14px;">The learning journey is structured progressively through:<br>ROOTING -> BLUEPRINT -> SPECIALIST LEARNING</p><p style="color:#333;line-height:1.7;margin:0 0 14px;">Rooting builds a strong foundation in identity, values, purpose, personal responsibility and sustainable growth.<br>Blueprint helps participants clarify direction, strengthen confidence, leadership, decision-making and intentional development.<br>Specialist Learning provides deeper capacity building in relevant areas of leadership, service and impact.</p><p style="color:#333;line-height:1.7;margin:0 0 14px;">What Participants Will Gain<br>Participating women will have opportunities to:<br>- strengthen their understanding of identity, purpose and potential;<br>- build confidence, self-leadership and personal responsibility;<br>- improve leadership, communication and decision-making skills;<br>- translate learning into practical action within their families, organisations and communities;<br>- access ongoing training and capacity-building opportunities;<br>- benefit from selected mentorship and development opportunities within the WODDI ecosystem;<br>- receive certificates of completion/participation, subject to meeting the Institute''s learning requirements; and<br>- become better positioned for continued personal, professional and leadership growth.</p><p style="color:#333;line-height:1.7;margin:0 0 14px;">Our goal is for every participant to leave the experience stronger, clearer, more confident and better equipped to make a meaningful difference.</p><p style="color:#333;line-height:1.7;margin:0 0 14px;">Why This Special Consideration<br>As the WODDI Institute prepares for its pioneer cohort in September 2026, we believe it is important that this opportunity extends beyond WODDI''s immediate network.</p><p style="color:#333;line-height:1.7;margin:0 0 14px;">Women-focused organisations across Africa are already connected to women with enormous potential. This special consideration is therefore intended to open access to structured learning and development for women nominated by such organisations.</p><p style="color:#333;line-height:1.7;margin:0 0 14px;">This reflects WODDI''s commitment to: No Woman Left Out.</p><p style="color:#333;line-height:1.7;margin:0 0 14px;">Our Invitation to Your Organisation<br>We respectfully invite your organisation to nominate a minimum of ten (10) women who demonstrate a genuine willingness to learn, grow and apply what they learn.</p><p style="color:#333;line-height:1.7;margin:0 0 14px;">Selected nominees will participate in the Pioneer WODDI Institute Learning Cohort, subject to the Institute''s onboarding and participation requirements.</p><p style="color:#333;line-height:1.7;margin:0 0 14px;">As members of this pioneering cohort, their experiences and feedback will also help strengthen the Institute as it prepares to serve an increasingly diverse community of women across Africa and beyond.</p><p style="color:#333;line-height:1.7;margin:0 0 14px;">Further information regarding the nomination process, onboarding, learning schedule and access to the Institute is provided at the link below.</p>'
    || '<p style="text-align:center;margin:26px 0;">'
    || '<a href="https://woddiinstitute.com/" style="background:#D4006A;'
    || 'color:#fff;padding:14px 28px;border-radius:8px;text-decoration:none;'
    || 'font-weight:700;display:inline-block;">Visit the WODDI Institute</a></p>'
    || '<p style="color:#333;line-height:1.7;margin:0 0 14px;">We look forward to receiving your nominations and welcoming the women of your organisation to this historic learning opportunity.</p><p style="color:#333;line-height:1.7;margin:0 0 14px;">Yours faithfully,<br>H.E. Zinaria Nneoma Nkechi Rochas Okorocha, PhD<br>Founder<br>Women of Divine Destiny Initiative (WODDI)<br>No Woman Left Out</p>'
    || '<p style="color:#7CB518;font-weight:700;margin-top:22px;">'
    || 'The Nurturer \u00b7 woddicrm.org</p>'
    || '<p style="color:#999;font-size:12px;margin-top:18px;border-top:1px '
    || 'solid #eee;padding-top:14px;">If you would prefer not to receive '
    || 'further correspondence about this opportunity, simply reply to let '
    || 'us know.</p>'
    || '</div></div>';
$$;

-- send up to p_limit PENDING English-language contacts, Nigeria first —
-- French/Arabic rows are deliberately skipped here (a translated letter
-- is coming later); held rows are never picked up by the batch
create or replace function public.send_outreach_batch(p_limit int default 20)
returns jsonb language plpgsql
security definer set search_path = public as $$
declare
  r record; email_on boolean; attempted int := 0; sent int := 0; ok boolean;
begin
  if auth.uid() is not null and not is_case_hq() then
    raise exception 'HQ only';
  end if;

  select coalesce((value #>> '{}')::boolean, false) into email_on
    from org_settings where key = 'email_enabled';
  if not email_on then
    return jsonb_build_object('error',
      'Email is switched off in Settings \u2014 turn it on before sending');
  end if;

  for r in
    select * from outreach_contacts
     where status = 'pending' and language = 'en'
     order by (country = 'Nigeria') desc, created_at asc
     limit p_limit
  loop
    attempted := attempted + 1;
    ok := send_email(r.email, coalesce(r.leader_name, r.organisation),
      'Special Consideration: Nominate 10 Women for the Pioneer WODDI '
      || 'Institute Cohort \u2013 September 2026',
      outreach_letter_html(r.leader_name));
    if ok then
      update outreach_contacts
         set status = 'sent', sent_at = now(),
             status_updated_at = now(), status_updated_by = auth.uid()
       where id = r.id;
      sent := sent + 1;
    end if;
  end loop;

  return jsonb_build_object('attempted', attempted, 'sent', sent,
    'remaining_pending', (select count(*) from outreach_contacts
                           where status = 'pending' and language = 'en'));
end;
$$;
revoke execute on function public.send_outreach_batch(int) from anon;

-- send exactly one contact, regardless of held/pending — for after Azeez
-- has verified a held address
create or replace function public.send_outreach_one(p_id uuid)
returns boolean language plpgsql
security definer set search_path = public as $$
declare r outreach_contacts; email_on boolean; ok boolean;
begin
  if auth.uid() is not null and not is_case_hq() then
    raise exception 'HQ only';
  end if;

  select coalesce((value #>> '{}')::boolean, false) into email_on
    from org_settings where key = 'email_enabled';
  if not email_on then
    raise exception 'Email is switched off in Settings \u2014 turn it on before sending';
  end if;

  select * into r from outreach_contacts where id = p_id;
  if r.id is null then raise exception 'Contact not found'; end if;

  ok := send_email(r.email, coalesce(r.leader_name, r.organisation),
    'Special Consideration: Nominate 10 Women for the Pioneer WODDI '
    || 'Institute Cohort \u2013 September 2026',
    outreach_letter_html(r.leader_name));
  if ok then
    update outreach_contacts
       set status = 'sent', sent_at = now(),
           status_updated_at = now(), status_updated_by = auth.uid()
     where id = p_id;
  end if;
  return ok;
end;
$$;
revoke execute on function public.send_outreach_one(uuid) from anon;

-- update a contact's status directly (mark bounced/replied/nominations
-- received/onboarded, or edit a held email and release it back to pending)
create or replace function public.set_outreach_status(
  p_id uuid, p_status text, p_new_email text default null)
returns void language plpgsql
security definer set search_path = public as $$
begin
  if auth.uid() is not null and not is_case_hq() then
    raise exception 'HQ only';
  end if;
  if p_status not in ('pending','held','sent','bounced','replied',
                      'nominations_received','onboarded') then
    raise exception 'Unrecognised status: %', p_status;
  end if;

  update outreach_contacts
     set status = p_status,
         email = coalesce(nullif(btrim(p_new_email), ''), email),
         status_updated_at = now(), status_updated_by = auth.uid()
   where id = p_id;
end;
$$;
revoke execute on function public.set_outreach_status(uuid, text, text)
  from anon;

create or replace function public.outreach_summary()
returns jsonb language sql stable
security definer set search_path = public as $$
  select case when public.is_case_hq() then
    coalesce(jsonb_object_agg(status, n), '{}'::jsonb)
  else '{}'::jsonb end
  from (select status, count(*) as n from outreach_contacts
         group by status) t;
$$;
revoke execute on function public.outreach_summary() from anon;

insert into public.schema_migrations (version, name)
values (94, 'outreach_module') on conflict (version) do nothing;
