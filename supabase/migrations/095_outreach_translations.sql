-- ============================================================================
-- WDOS Migration 095 — Outreach letter in French and Arabic (Phase 106b)
--
-- Extends outreach_letter_html() (094) with a language branch, exactly at
-- the place that migration deliberately left marked for this. Both
-- translations are formal-register, matching the English original's
-- tone; the Arabic version renders right-to-left (dir="rtl", text
-- right-aligned) rather than translated text forced into a left-to-right
-- layout, since a mirrored-but-wrong-direction email reads as broken to
-- a native Arabic reader. send_outreach_batch() no longer skips fr/ar —
-- every pending contact, in her own language, in one batch call.
-- ============================================================================

create or replace function public.outreach_letter_html(
  p_leader_name text, p_language text default 'en')
returns text language plpgsql immutable as $$
declare
  title_line text; greet_fallback text; body_html text; btn_label text;
  closing_html text; footer_line text; dir_attr text; align_style text;
begin
  case p_language
    when 'fr' then
      title_line := 'Invitation à nommer un minimum de dix (10) femmes pour l''opportunité d''apprentissage pionnière du WODDI Institute – Septembre 2026';
      greet_fallback := 'Cher/Chère responsable';
      body_html := '<p style="color:#333;line-height:1.7;margin:0 0 14px;text-align:left;">Salutations de la part de la Women of Divine Destiny Initiative (WODDI).</p><p style="color:#333;line-height:1.7;margin:0 0 14px;text-align:left;">Dans le cadre de notre engagement à faire progresser, développer et inclure véritablement les femmes africaines, WODDI est heureuse d''adresser cette invitation spéciale à des organisations africaines œuvrant en faveur des femmes soigneusement sélectionnées.</p><p style="color:#333;line-height:1.7;margin:0 0 14px;text-align:left;">Votre organisation est invitée à nommer un minimum de dix (10) femmes pour participer à la cohorte pionnière d''apprentissage du WODDI Institute, qui débutera en septembre 2026.</p><p style="color:#333;line-height:1.7;margin:0 0 14px;text-align:left;">À propos du WODDI Institute<br>Le WODDI Institute a été créé pour aider les femmes à renforcer leur identité, leur confiance, leur raison d''être, leurs capacités de leadership et leur aptitude à transformer leur potentiel en un impact personnel, organisationnel et sociétal significatif.</p><p style="color:#333;line-height:1.7;margin:0 0 14px;text-align:left;">Au cœur de l''Institute se trouve une conviction simple :<br>Lorsqu''une femme est renforcée, informée, équipée et correctement positionnée, cet impact dépasse sa propre vie pour s''étendre à sa famille, son organisation, sa communauté et sa nation.</p><p style="color:#333;line-height:1.7;margin:0 0 14px;text-align:left;">Le parcours d''apprentissage est structuré de façon progressive autour de trois étapes :<br>ENRACINEMENT → VISION → APPRENTISSAGE SPÉCIALISÉ</p><p style="color:#333;line-height:1.7;margin:0 0 14px;text-align:left;">L''Enracinement bâtit une base solide en matière d''identité, de valeurs, de raison d''être, de responsabilité personnelle et de croissance durable.<br>La Vision aide les participantes à clarifier leur direction et à renforcer leur confiance, leur leadership et leur prise de décision.<br>L''Apprentissage spécialisé offre un renforcement de compétences plus approfondi dans des domaines pertinents de leadership, de service et d''impact.</p><p style="color:#333;line-height:1.7;margin:0 0 14px;text-align:left;">Ce que les participantes en retireront<br>Les femmes participantes auront l''occasion de :<br>- renforcer leur compréhension de leur identité, de leur raison d''être et de leur potentiel ;<br>- développer leur confiance, leur leadership personnel et leur sens des responsabilités ;<br>- améliorer leurs compétences en leadership, communication et prise de décision ;<br>- transformer leurs apprentissages en actions concrètes au sein de leur famille, de leur organisation et de leur communauté ;<br>- accéder à des formations continues et à des opportunités de renforcement de capacités ;<br>- bénéficier d''opportunités de mentorat et de développement sélectionnées au sein de l''écosystème WODDI ;<br>- recevoir des certificats d''achèvement/de participation, sous réserve de satisfaire aux exigences d''apprentissage de l''Institute ; et<br>- être mieux positionnées pour poursuivre leur croissance personnelle, professionnelle et en leadership.</p><p style="color:#333;line-height:1.7;margin:0 0 14px;text-align:left;">Notre objectif est que chaque participante ressorte de cette expérience plus forte, plus claire, plus confiante et mieux équipée pour apporter une contribution significative.</p><p style="color:#333;line-height:1.7;margin:0 0 14px;text-align:left;">Pourquoi cette considération spéciale<br>Alors que le WODDI Institute prépare sa cohorte pionnière de septembre 2026, nous estimons important que cette opportunité s''étende au-delà du réseau immédiat de WODDI.</p><p style="color:#333;line-height:1.7;margin:0 0 14px;text-align:left;">Les organisations africaines œuvrant en faveur des femmes sont déjà en lien avec des femmes au potentiel considérable. Cette considération spéciale vise donc à ouvrir l''accès à un apprentissage et à un développement structurés pour les femmes nommées par ces organisations.</p><p style="color:#333;line-height:1.7;margin:0 0 14px;text-align:left;">Ceci reflète l''engagement de WODDI : Aucune femme laissée pour compte.</p><p style="color:#333;line-height:1.7;margin:0 0 14px;text-align:left;">Notre invitation à votre organisation<br>Nous invitons respectueusement votre organisation à nommer un minimum de dix (10) femmes qui démontrent une réelle volonté d''apprendre, de grandir et de mettre en pratique ce qu''elles apprennent.</p><p style="color:#333;line-height:1.7;margin:0 0 14px;text-align:left;">Les candidates sélectionnées participeront à la cohorte pionnière d''apprentissage du WODDI Institute, sous réserve des exigences d''intégration et de participation de l''Institute.</p><p style="color:#333;line-height:1.7;margin:0 0 14px;text-align:left;">En tant que membres de cette cohorte pionnière, leurs expériences et leurs retours contribueront également à renforcer l''Institute alors qu''il se prépare à servir une communauté de femmes de plus en plus diversifiée à travers l''Afrique et au-delà.</p><p style="color:#333;line-height:1.7;margin:0 0 14px;text-align:left;">De plus amples informations concernant le processus de nomination, l''intégration, le calendrier d''apprentissage et l''accès à l''Institute sont disponibles via le lien ci-dessous.</p>';
      btn_label := 'Visiter le WODDI Institute';
      closing_html := '<p style="color:#333;line-height:1.7;margin:0 0 14px;text-align:left;">Nous nous réjouissons de recevoir vos nominations et d''accueillir les femmes de votre organisation dans cette opportunité d''apprentissage historique.</p><p style="color:#333;line-height:1.7;margin:0 0 14px;text-align:left;">Avec toute notre considération,<br>S.E. Zinaria Nneoma Nkechi Rochas Okorocha, PhD<br>Fondatrice<br>Women of Divine Destiny Initiative (WODDI)<br>Aucune femme laissée pour compte</p>';
      footer_line := 'Si vous préférez ne plus recevoir de correspondance au sujet de cette opportunité, il vous suffit de répondre à ce message pour nous en informer.';
      dir_attr := 'ltr'; align_style := 'left';
    when 'ar' then
      title_line := 'دعوة لترشيح ما لا يقل عن عشر (10) نساء للفرصة التعليمية الرائدة لمعهد WODDI – سبتمبر 2026';
      greet_fallback := 'عزيزتي القائدة';
      body_html := '<p style="color:#333;line-height:1.7;margin:0 0 14px;text-align:right;">تحيات من مبادرة نساء القدر الإلهي (WODDI).</p><p style="color:#333;line-height:1.7;margin:0 0 14px;text-align:right;">كجزء من التزامنا بالنهوض بالمرأة الأفريقية وتطويرها وإشراكها بشكل حقيقي، يسر WODDI أن توجّه دعوة خاصة لمنظمات مختارة تُعنى بالمرأة في مختلف أنحاء أفريقيا.</p><p style="color:#333;line-height:1.7;margin:0 0 14px;text-align:right;">ندعو منظمتكم لترشيح ما لا يقل عن عشر (10) نساء للمشاركة في الدفعة الرائدة من برنامج التعلّم في معهد WODDI، والتي تنطلق في سبتمبر 2026.</p><p style="color:#333;line-height:1.7;margin:0 0 14px;text-align:right;">عن معهد WODDI<br>تأسس معهد WODDI لمساعدة النساء على تعزيز هويتهن، وثقتهن بأنفسهن، وهدفهن، وقدراتهن القيادية، وقدرتهن على تحويل إمكاناتهن إلى أثر شخصي ومؤسسي ومجتمعي ذي معنى.</p><p style="color:#333;line-height:1.7;margin:0 0 14px;text-align:right;">وفي جوهر رسالة المعهد قناعة بسيطة:<br>عندما تتمكّن المرأة وتُزوَّد بالمعرفة والأدوات وتُوضَع في موقعها الصحيح، فإن هذا الأثر يمتد إلى ما هو أبعد من حياتها، ليشمل أسرتها ومنظمتها ومجتمعها وأمتها.</p><p style="color:#333;line-height:1.7;margin:0 0 14px;text-align:right;">تسير رحلة التعلّم بشكل تدريجي عبر ثلاث مراحل:<br>التأصيل ← البلوبرنت (رسم المسار) ← التعلّم التخصصي</p><p style="color:#333;line-height:1.7;margin:0 0 14px;text-align:right;">يبني التأصيل أساسًا متينًا في الهوية والقيم والهدف والمسؤولية الشخصية والنمو المستدام.<br>تساعد مرحلة البلوبرنت المشاركات على توضيح اتجاههن وتعزيز ثقتهن وقيادتهن وقدرتهن على اتخاذ القرار.<br>يوفر التعلّم التخصصي بناءً أعمق للقدرات في مجالات القيادة والخدمة والأثر ذات الصلة.</p><p style="color:#333;line-height:1.7;margin:0 0 14px;text-align:right;">ما ستكتسبه المشاركات<br>ستتاح للمشاركات فرص من أجل:<br>- تعزيز فهمهن لهويتهن وهدفهن وإمكاناتهن؛<br>- بناء الثقة بالنفس والقيادة الذاتية والمسؤولية الشخصية؛<br>- تحسين مهارات القيادة والتواصل واتخاذ القرار؛<br>- تحويل ما تعلّمنه إلى عمل تطبيقي داخل أسرهن ومنظماتهن ومجتمعاتهن؛<br>- الوصول إلى فرص تدريب وبناء قدرات مستمرة؛<br>- الاستفادة من فرص إرشاد وتطوير مختارة ضمن منظومة WODDI؛<br>- الحصول على شهادات إتمام أو مشاركة، شريطة استيفاء متطلبات التعلّم الخاصة بالمعهد؛ و<br>- أن يصبحن في موقع أفضل لمواصلة نموهن الشخصي والمهني والقيادي.</p><p style="color:#333;line-height:1.7;margin:0 0 14px;text-align:right;">هدفنا أن تخرج كل مشاركة من هذه التجربة أقوى وأوضح رؤية وأكثر ثقة وأفضل تجهيزًا لإحداث أثر ذي معنى.</p><p style="color:#333;line-height:1.7;margin:0 0 14px;text-align:right;">لماذا هذا الاعتبار الخاص<br>مع استعداد معهد WODDI لدفعته الرائدة في سبتمبر 2026، نرى من المهم أن تمتد هذه الفرصة إلى ما هو أبعد من شبكة WODDI المباشرة.</p><p style="color:#333;line-height:1.7;margin:0 0 14px;text-align:right;">المنظمات الأفريقية المعنية بالمرأة على تواصل بالفعل مع نساء يمتلكن إمكانات هائلة. ولذلك، يهدف هذا الاعتبار الخاص إلى فتح المجال أمام التعلّم والتطوير المنظم للنساء اللاتي ترشحهن هذه المنظمات.</p><p style="color:#333;line-height:1.7;margin:0 0 14px;text-align:right;">وهذا يعكس التزام WODDI: لا امرأة تُترك خلف الركب.</p><p style="color:#333;line-height:1.7;margin:0 0 14px;text-align:right;">دعوتنا لمنظمتكم<br>ندعو منظمتكم باحترام إلى ترشيح ما لا يقل عن عشر (10) نساء يُظهرن استعدادًا حقيقيًا للتعلّم والنمو وتطبيق ما يتعلمنه.</p><p style="color:#333;line-height:1.7;margin:0 0 14px;text-align:right;">ستشارك المرشحات المختارات في الدفعة الرائدة من برنامج التعلّم في معهد WODDI، وذلك وفقًا لمتطلبات المعهد الخاصة بالانضمام والمشاركة.</p><p style="color:#333;line-height:1.7;margin:0 0 14px;text-align:right;">وبصفتهن عضوات في هذه الدفعة الرائدة، ستسهم تجاربهن وملاحظاتهن أيضًا في تعزيز المعهد وهو يستعد لخدمة مجتمع متنوّع باستمرار من النساء عبر أفريقيا وخارجها.</p><p style="color:#333;line-height:1.7;margin:0 0 14px;text-align:right;">يمكن الاطلاع على مزيد من المعلومات حول عملية الترشيح والانضمام وجدول التعلّم والوصول إلى المعهد عبر الرابط أدناه.</p>';
      btn_label := 'زيارة معهد WODDI';
      closing_html := '<p style="color:#333;line-height:1.7;margin:0 0 14px;text-align:right;">نتطلع إلى استقبال ترشيحاتكم والترحيب بنساء منظمتكم في هذه الفرصة التعليمية التاريخية.</p><p style="color:#333;line-height:1.7;margin:0 0 14px;text-align:right;">مع فائق التقدير،<br>سعادة زيناريا نيوما نكيتشي روشاس أوكوروتشا، دكتوراه<br>المؤسِّسة<br>مبادرة نساء القدر الإلهي (WODDI)<br>لا امرأة تُترك خلف الركب</p>';
      footer_line := 'إذا كنتم تفضلون عدم تلقي مزيد من المراسلات حول هذه الفرصة، يُرجى ببساطة الرد على هذه الرسالة لإعلامنا بذلك.';
      dir_attr := 'rtl'; align_style := 'right';
    else
      title_line := 'Invitation to Nominate a Minimum of Ten (10) Women for the Pioneer WODDI Institute Learning Opportunity – September 2026';
      greet_fallback := 'Esteemed Leader';
      body_html := '<p style="color:#333;line-height:1.7;margin:0 0 14px;text-align:left;">Greetings from the Women of Divine Destiny Initiative (WODDI).</p><p style="color:#333;line-height:1.7;margin:0 0 14px;text-align:left;">As part of our commitment to advancing, developing and meaningfully including African women, WODDI is pleased to extend this Special Consideration Invitation to selected women-focused organisations across Africa.</p><p style="color:#333;line-height:1.7;margin:0 0 14px;text-align:left;">Your organisation is invited to nominate a minimum of ten (10) women to participate in the Pioneer WODDI Institute Learning Cohort, commencing in September 2026.</p><p style="color:#333;line-height:1.7;margin:0 0 14px;text-align:left;">About the WODDI Institute<br>The WODDI Institute was created to help women strengthen their identity, confidence, purpose, leadership capacity and ability to translate their potential into meaningful personal, organisational and societal impact.</p><p style="color:#333;line-height:1.7;margin:0 0 14px;text-align:left;">At the heart of the Institute is a simple conviction:<br>When a woman is strengthened, informed, equipped and properly positioned, the impact extends beyond her life to her family, organisation, community and nation.</p><p style="color:#333;line-height:1.7;margin:0 0 14px;text-align:left;">The learning journey is structured progressively through:<br>ROOTING -> BLUEPRINT -> SPECIALIST LEARNING</p><p style="color:#333;line-height:1.7;margin:0 0 14px;text-align:left;">Rooting builds a strong foundation in identity, values, purpose, personal responsibility and sustainable growth.<br>Blueprint helps participants clarify direction, strengthen confidence, leadership, decision-making and intentional development.<br>Specialist Learning provides deeper capacity building in relevant areas of leadership, service and impact.</p><p style="color:#333;line-height:1.7;margin:0 0 14px;text-align:left;">What Participants Will Gain<br>Participating women will have opportunities to:<br>- strengthen their understanding of identity, purpose and potential;<br>- build confidence, self-leadership and personal responsibility;<br>- improve leadership, communication and decision-making skills;<br>- translate learning into practical action within their families, organisations and communities;<br>- access ongoing training and capacity-building opportunities;<br>- benefit from selected mentorship and development opportunities within the WODDI ecosystem;<br>- receive certificates of completion/participation, subject to meeting the Institute''s learning requirements; and<br>- become better positioned for continued personal, professional and leadership growth.</p><p style="color:#333;line-height:1.7;margin:0 0 14px;text-align:left;">Our goal is for every participant to leave the experience stronger, clearer, more confident and better equipped to make a meaningful difference.</p><p style="color:#333;line-height:1.7;margin:0 0 14px;text-align:left;">Why This Special Consideration<br>As the WODDI Institute prepares for its pioneer cohort in September 2026, we believe it is important that this opportunity extends beyond WODDI''s immediate network.</p><p style="color:#333;line-height:1.7;margin:0 0 14px;text-align:left;">Women-focused organisations across Africa are already connected to women with enormous potential. This special consideration is therefore intended to open access to structured learning and development for women nominated by such organisations.</p><p style="color:#333;line-height:1.7;margin:0 0 14px;text-align:left;">This reflects WODDI''s commitment to: No Woman Left Out.</p><p style="color:#333;line-height:1.7;margin:0 0 14px;text-align:left;">Our Invitation to Your Organisation<br>We respectfully invite your organisation to nominate a minimum of ten (10) women who demonstrate a genuine willingness to learn, grow and apply what they learn.</p><p style="color:#333;line-height:1.7;margin:0 0 14px;text-align:left;">Selected nominees will participate in the Pioneer WODDI Institute Learning Cohort, subject to the Institute''s onboarding and participation requirements.</p><p style="color:#333;line-height:1.7;margin:0 0 14px;text-align:left;">As members of this pioneering cohort, their experiences and feedback will also help strengthen the Institute as it prepares to serve an increasingly diverse community of women across Africa and beyond.</p><p style="color:#333;line-height:1.7;margin:0 0 14px;text-align:left;">Further information regarding the nomination process, onboarding, learning schedule and access to the Institute is provided at the link below.</p>';
      btn_label := 'Visit the WODDI Institute';
      closing_html := '<p style="color:#333;line-height:1.7;margin:0 0 14px;text-align:left;">We look forward to receiving your nominations and welcoming the women of your organisation to this historic learning opportunity.</p><p style="color:#333;line-height:1.7;margin:0 0 14px;text-align:left;">Yours faithfully,<br>H.E. Zinaria Nneoma Nkechi Rochas Okorocha, PhD<br>Founder<br>Women of Divine Destiny Initiative (WODDI)<br>No Woman Left Out</p>';
      footer_line := 'If you would prefer not to receive further correspondence about this opportunity, simply reply to let us know.';
      dir_attr := 'ltr'; align_style := 'left';
  end case;

  return
    '<div dir="' || dir_attr || '" style="font-family:Arial,Helvetica,'
    || 'sans-serif;max-width:600px;margin:0 auto;border:1px solid #eee;'
    || 'border-radius:10px;overflow:hidden;text-align:' || align_style || ';">'
    || '<div style="background:#D4006A;color:#fff;padding:20px 24px;'
    || 'font-size:22px;font-weight:800;text-align:' || align_style || ';">WODDI</div>'
    || '<div style="padding:24px;">'
    || '<p style="color:#111;font-weight:700;font-size:17px;margin:0 0 16px;'
    || 'text-align:' || align_style || ';">' || title_line || '</p>'
    || '<p style="color:#333;line-height:1.7;text-align:' || align_style || ';">'
    || coalesce(nullif(btrim(p_leader_name), ''), greet_fallback) || ',</p>'
    || body_html
    || '<p style="text-align:center;margin:26px 0;">'
    || '<a href="https://woddiinstitute.com/" style="background:#D4006A;'
    || 'color:#fff;padding:14px 28px;border-radius:8px;text-decoration:none;'
    || 'font-weight:700;display:inline-block;">' || btn_label || '</a></p>'
    || closing_html
    || '<p style="color:#7CB518;font-weight:700;margin-top:22px;'
    || 'text-align:' || align_style || ';">The Nurturer \u00b7 woddicrm.org</p>'
    || '<p style="color:#999;font-size:12px;margin-top:18px;border-top:1px '
    || 'solid #eee;padding-top:14px;text-align:' || align_style || ';">'
    || footer_line || '</p>'
    || '</div></div>';
end;
$$;

-- per-language subject line
create or replace function public.outreach_subject(p_language text)
returns text language sql immutable as $$
  select case p_language
    when 'fr' then 'Considération spéciale : Nommez 10 femmes pour la cohorte pionnière du WODDI Institute – Septembre 2026'
    when 'ar' then 'اعتبار خاص: رشّحوا 10 نساء للدفعة الرائدة من معهد WODDI – سبتمبر 2026'
    else 'Special Consideration: Nominate 10 Women for the Pioneer WODDI Institute Cohort – September 2026'
  end;
$$;

-- the batch now covers every pending language, not English only
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
     where status = 'pending'
     order by (country = 'Nigeria') desc, (language = 'en') desc, created_at asc
     limit p_limit
  loop
    attempted := attempted + 1;
    ok := send_email(r.email, coalesce(r.leader_name, r.organisation),
      outreach_subject(r.language),
      outreach_letter_html(r.leader_name, r.language));
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
                           where status = 'pending'));
end;
$$;
revoke execute on function public.send_outreach_batch(int) from anon;

-- single-contact send: also route through the language-aware letter/subject
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
    outreach_subject(r.language),
    outreach_letter_html(r.leader_name, r.language));
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

insert into public.schema_migrations (version, name)
values (95, 'outreach_translations') on conflict (version) do nothing;
