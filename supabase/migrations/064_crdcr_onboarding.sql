-- ============================================================================
-- WDOS Migration 064 — Country Representatives & Deputies Onboarding (Phase 84)
-- 42 CR/DCR leaders imported with continuing ID sequences
-- (CR118+, DCR104+). Leaders marked RED in the master list are imported
-- with IDs but NOT emailed (unresponsive); flip them later by clearing
-- id_mailed_at and re-running the mail block. Country now rides onto the
-- profile at claim. Idempotent by email.
-- ============================================================================

alter table public.applications
  add column if not exists country text;

-- claim carries country too
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
         preferred_locale, status, membership_no, country)
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
         coalesce(app.member_no, next_membership_no()),
         app.country)
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
  exception when others then
    raise exception 'WDOS claim failed for %: %', new.email, sqlerrm;
  end;
  return new;
end; $$;

do $$
declare
  hq uuid; v record; p_id uuid; p_member text; nextn int; newid text;
  imported int := 0; crowned int := 0; mailed int := 0; skipped int := 0;
begin
  select id into hq from org_units where level = 'headquarters'
   order by created_at limit 1;

  for v in
    select * from (values
    ('Hessou','Aline Félicienne','hessou.aline@gmail.com','+2290162204468','Benin','CR',false),
    ('Yorou','Barkissou','ybarkissou@gmail.com','+229 01 97 18 66 54','Benin','DCR',false),
    ('SANOU','Kouéssésra Esther','estkoue@yahoo.fr','0022670943610/0022674486923','Burkina Faso','CR',true),
    ('Denne','Irène','irene.denne@gmail.com','+226 71598366','Burkina Faso','DCR',true),
    ('Ahishakiye','Berthile','abertila1991@gmail.com','+25779795829','Burundi','CR',true),
    ('Mandunh','Mbohou Awawou','radhiyabintou@gmail.com','+237 671590554','Cameroon','CR',false),
    ('Kwedi','Pyo Lydienne','kwedilydia23@gmail.com','(±237)691034476','Cameroon','DCR',false),
    ('Amina','Bello','aminabello745@gmail.com','+236 75 42 42 69','Central African Republic','CR',false),
    ('Koradjim','Lionel','koradjimlionel72@gmail.com','+236 72999501','Central African Republic','DCR',true),
    ('Tchindebe','Antoinette Fanone','famiel.tchad@gmail.com','+235 62 46 75 13','Chad','CR',false),
    ('Hinberka','Beblere Florice','hinberkaflorice@gmail.com','+23563379637','Chad','DCR',false),
    ('Bizonzi','Prinelly Sergie Bonnel','bizonzi.prinelly@gmail.com','+242066149474','Congo','CR',false),
    ('Soro','Gnimey Cintia Louisette','cintialouisette@yahoo.fr','+2250707602002','Côte d''Ivoire','CR',false),
    ('Attemene','Yannick','attemeneyannick@gmail.com','+225 0777531432','Côte d''Ivoire','DCR',false),
    ('Furaha','Maroy Judith','judithmaroy@gmail.com','+243995519371','DR Congo','CR',false),
    ('Nshembe','Chishungu Eric Nice','ericnshembe@gmail.com','+243993008031','DR Congo','DCR',false),
    ('Haddy','Semega Janneh','haddysemegajanneh@gmail.com','','Gambia','CR',true),
    ('Doreen','Serwaa Ampae','dassyansah55@gmail.com','+233554841456','Ghana','CR',true),
    ('Esther','Takyiwaah Prempeh','prempehesthertakyiwaah@gmail.com','+233244791883','Ghana','DCR',true),
    ('Koulako','Kamissoko','koulako.kamissoko@gmail.com','+224 621097639','Guinea','CR',true),
    ('Bah','Ramata Benny','bahramatabenny@gmail.com','+224622031660','Guinea','DCR',true),
    ('Mariama','Fati','mariamafati065@gmail.com','+245955400841','Guinea-Bissau','CR',true),
    ('Sharon','Amondi','amondisharon54@gmail.com','','Kenya','CR',true),
    ('Ainasoa','Rakotoniera','ainasoarakoto@gmail.com','(+261) 0320784716','Madagascar','CR',true),
    ('Tinarivo','Baby Emmanuel','babyes.emmanuel@gmail.com','+261 34 52 649 33','Madagascar','DCR',true),
    ('Salimata','Coulibaly','salimata.coulibaly.kane@gmail.com','(+223)75999453','Mali','CR',true),
    ('Binta','Coulibaly','binete37@gmail.com','+22390621900','Mali','DCR',true),
    ('Safaa','Hachimi','safaehcm@gmail.com','+212638979304','Morocco','CR',true),
    ('Abdou','Mariama','amariama97@yahoo.fr','+227 99 89 72 30','Niger','CR',true),
    ('Zaleha','Salha Abou','salhaabouz@gmail.com','+22788124816','Niger','DCR',true),
    ('Haruna','Amina','egwola@gmail.com','','Nigeria','CR',false),
    ('Maureen','Nkechi Chukwuemeka','maureenchukwuemeka@gmail.com','+234 8034753667','Nigeria','DCR',false),
    ('Irene','Mukanzayituriki','mukanzayiturikii@gmail.com','+250788647173','Rwanda','CR',true),
    ('Florence','Umutoni','florenceumutoni2000@gmail.com','+250784178086','Rwanda','DCR',true),
    ('Sophie','Dior Diack','sodiordiack@gmail.com','(+221) 76 228 09 80','Senegal','CR',false),
    ('Penda','Kande','dapenkande@gmail.com','+221765846398','Senegal','DCR',true),
    ('Tshegofatso','Gama','molokoane.m.t@gmail.com','+27730386265','South Africa','CR',false),
    ('Pakou','Akouvi Emefa','bonemef84@gmail.com','+228 90 07 68 61','Togo','CR',false),
    ('Soriyath','Lisette Maëlle Bertille Gantua','sgantua@gmail.com','+228 91 54 94 87','Togo','DCR',false),
    ('Nesrine','Ben Saad','bensaadnesrineselima@gmail.com','0021650207255','Tunisia','CR',true),
    ('Nadia','-','nadiathligene@gmail.com','0021655571598','Tunisia','DCR',true),
    ('Zalwango','Grace','zalwangograce46@gmail.com','+256 745 009 128','Uganda','CR',false)
    ) as t(first_name, last_name, email, phone, country, pre, unresponsive)
  loop
    begin
      if exists (select 1 from applications a
                  where lower(a.email) = lower(v.email))
         or exists (select 1 from profiles pr
                     where lower(pr.email) = lower(v.email)
                       and pr.membership_no is not null) then
        skipped := skipped + 1;
        continue;
      end if;

      select coalesce(max(nullif(regexp_replace(x.mn, '\D', '', 'g'),
                                 '')::int), 100) + 1
        into nextn
        from (
          select member_no as mn from applications
           where member_no ~ ('^' || v.pre || '\d+$')
          union all
          select membership_no from profiles
           where membership_no ~ ('^' || v.pre || '\d+$')
        ) x;
      newid := v.pre || nextn::text;

      select id, membership_no into p_id, p_member
        from profiles
       where lower(email) = lower(v.email) and merged_into is null limit 1;

      if p_id is not null then
        if p_member is null then
          update profiles set membership_no = newid,
                 country = coalesce(country, v.country)
           where id = p_id;
        end if;
        crowned := crowned + 1;
      else
        insert into applications
          (first_name, last_name, email, phone, network, org_unit_id,
           motivation, status, decision_reason, decided_at, country,
           member_no, id_mailed_at)
        values
          (v.first_name, v.last_name, v.email, v.phone, 'WGMN', hq,
           'Country leadership — master contact list (Jul 2026)',
           'approved',
           case when v.unresponsive
             then 'CR/DCR master list (unresponsive — not mailed)'
             else 'CR/DCR master list (Jul 2026)' end,
           now(), v.country, newid,
           case when v.unresponsive then now() else null end);
        imported := imported + 1;
      end if;

      if not v.unresponsive then
        perform send_email(v.email,
          coalesce(nullif(v.first_name, ''), 'Leader'),
          'Your WODDI Leadership ID: ' || newid,
          email_wrap('Your WODDI Leadership ID',
            'Dear ' || v.first_name || ','
            || e'\n\nAs WODDI opens its Digital Operating System, your '
            || 'permanent Leadership ID as '
            || case when v.pre = 'CR' then 'Country Representative'
                    else 'Deputy Country Representative' end
            || ' for ' || v.country || ' is:'
            || e'\n\n        ' || newid || e'\n\n'
            || 'No registration needed. Enter your workspace here:'
            || e'\nhttps://woddicrm.org/#/id' || e'\n\n'
            || 'type your ID, confirm your name, choose a password — and '
            || 'you are in. Your 14-day Activation Journey opens on '
            || '3 August 2026.'
            || e'\n\nWith warmth,\nThe WODDI Team'));
        update applications set id_mailed_at = now()
         where lower(email) = lower(v.email);
        mailed := mailed + 1;
      end if;

    exception when others then
      raise notice 'CR/DCR row skipped (%): %', v.email, sqlerrm;
    end;
  end loop;

  raise notice 'CR/DCR: % imported, % crowned, % mailed, % skipped',
    imported, crowned, mailed, skipped;
end $$;

insert into public.schema_migrations (version, name)
values (64, 'crdcr_onboarding') on conflict (version) do nothing;
