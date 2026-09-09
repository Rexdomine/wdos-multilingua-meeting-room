-- ============================================================================
-- WDOS Migration 059 (v2) — Institute Cohort Onboarding + ID Sign-in
-- Per-person and forgiving: emails that already own a WDOS profile are not
-- re-imported — their existing account is CROWNED with the Volunteer ID
-- (membership_no) instead. Fresh people become approved applications. Every
-- person is mailed their ID exactly once. One bad row never sinks the rest.
-- ============================================================================

alter table public.applications
  add column if not exists member_no text unique,
  add column if not exists id_mailed_at timestamptz;

do $$
declare
  hq uuid;
  v record;
  p_id uuid;
  p_member text;
  imported int := 0; crowned int := 0; mailed int := 0; skipped int := 0;
  body text;
begin
  select id into hq from org_units where level = 'headquarters'
   order by created_at limit 1;

  for v in
    select * from (values
    ('Azeez','-','woddingo@gmail.com','+2348071211007','WGMN','to make impact in my community','CR101'),
    ('Samuel','-','woddi.org@gmail.com','2348071211007','WNNN','yes','LDC101'),
    ('Kemfonabasi','Nta','kemfonnta@gmail.com','+2348038530327','WNNN','jkadhjsahjfchelash','SRC101'),
    ('Dorcas','Samuel','samueldorcas037@gmail.com','09078476940','WNNN','I want to represent WODDI in my region because I am passionate about empowering young women to discover their potential, build confidence, and become positive agents of change in their communities. I believe many young women have great ideas and aspirations but lack access to mentorship, leadership opportunities, and the right support system to thrive.  As a Chapter Lead, I want to create a safe a','CHL101'),
    ('Chioma','Okereke','chiomaokereke2024@gmail.com','+2348075577312','WGMN','It is a privileged opportunity to be mentored by women who have gone ahead of and mentor those coming behind','CR102'),
    ('Matanmi','Esther Diamond','estherjoeebitu@gmail.com','2347065493398','WGMN','To be a voice and a leader carrying a vision that impacts generations to come','ASRC101'),
    ('EZEIBE','THERESA OLUCHI','theresa.oluchi5@gmail.com','+2348039388257','WGMN','I am motivated to represent WODDI in my region so as to  contribute and achieve results that align with WODDI''s Vission and Mission.','VOL101'),
    ('Yakubu','Jonathan','jonathanyakubu007@gmail.com','+2348971211007','WGMN','abcd','SRC102'),
    ('Comfort','ojo','official.comfortojo@gmail.com','08139322046','WGMN','To be able to carry out the mandate and values of WODDI to the grassroots at large .','PM101'),
    ('Umoetuk','UduakAbasi Edidiong','pauluduakabasi@gmail.com','+2348134481524','WGMN','I want to represent WODDI because I am passionate about empowering women, strengthening communities, and creating opportunities for growth through leadership, mentorship, and meaningful community engagement.','SRC103'),
    ('Blessing','Ogheneochuko Gabol','bleochuko@gmail.com','+2349034755910','WGMN','I want to represent WODDI because I believe strong women build stronger families, communities, and nations.  I am passionate about empowering women through leadership, mentorship, and community engagement.  As a Country Representative, I want to help grow WODDI''s presence, build partnerships, support women to discover their potential, and create opportunities for positive impact in communities acr','CR103'),
    ('Ajagbe','Aishat Olaitan','ajagbeayshah@yahoo.com','+2348127069324','WNNN','I want to represent WODDI because I am passionate about empowering young people through leadership, mentorship, and community service. I hope to create opportunities for learning, collaboration, and positive social impact while inspiring more young people in my community to become active changemakers.','PM102'),
    ('Deborah','bulus kaka','debbiekaka0000@gmail.com','+2349037373724','WNNN','I want to represent WODDI because I believe in its mission of empowering women, youth, and vulnerable communities. As a registered nurse, I am passionate about serving people, creating positive impact, and using my skills to support community development and inspire meaningful change.','ASRC102'),
    ('Joyce','-','joyceshekwaguakawu@gmail.com','09065069250','WGMN','Because my passion is service. To be a voice, help people and also grow','ACHL101'),
    ('Oluwafemi','-','femiayor@gmail.com','2348071211007','WGMN','yes','LDC102'),
    ('Imi','Ati','imiberta@yahoo.com','+2349076591233','WGMN','To support the initiative and values of the NGO.','VOL102'),
    ('Chidera','Judith Nwachukwu','judithchidera867@gmail.com','07034337783','WNNN','I’m passionate about humanity and woddi will be a perfect opportunity for to serve humanity in every little and possible way','ACHL102'),
    ('Uzoebo','Chinonso O.','prestige4luv@yahoo.com','2348059629784','WGMN','Yes','CR104'),
    ('ARIYO','OLUWAFERANMI','ariyooluwaferanmi6@gmail.com','+2348135040701','WNNN','I want to represent WODDI in my country because I believe leadership is most impactful when it creates opportunities and drives positive change within communities. As a humanitarian, pageant titleholder, and founder of community initiatives, I have worked on projects that promote education, women’s empowerment, health awareness, and social advocacy. These experiences have strengthened my passion f','CL101'),
    ('Elizabeth','James','getlizjay@gmail.com','+2348036331099','WGMN','Our vision alligns and I believe being part of it will help me fulfill purpose','DCR101'),
    ('Sarah','Johnbull Osarumwense','sarahjohnbull5@gmail.com','07062279754','WNNN','I want to represent WODDI because I want to contribute to it''s Mission, support women, and grow through learning and service.','ACHL103'),
    ('Folaranmi','oluwadarasimi','sarahdara935584@gmail.com','+2349024935584','WNNN','I want to represent WODDI because I believe every young woman deserves access to opportunities, mentorship, and a supportive community that helps her thrive. As someone passionate about youth leadership and education, I want to help expand WODDI''s impact in my region by connecting more young women to resources, inspiring them to lead, and building a network of confident changemakers.','SRC104'),
    ('Blessing','Nelson','angelblessnels@gmail.com','+2348035288295','WGMN','I want to represent WODDI because I am passionate about empowering young people and creating positive change in my community. I will actively promote WODDI''s mission, engage local communities, build partnerships, and encourage more people to participate in its programs. I am committed to serving with integrity, dedication, and professionalism to expand WODDI''s impact in my region.','VOL103'),
    ('Quadri','Nofisat Adebimpe','adebimpe4quadri@gmail.com','+2347067605956','WGMN','I want to represent WODDI because I am passionate about supporting women and vulnerable communities. Through my work as a Community Case Manager, I have seen the challenges many women and families face, and I am willing to contribute to positive change through advocacy, awareness, and community engagement. I believe my experience in social work and my commitment to helping others will enable me to','LDC103'),
    ('Dashe','Mary-Ann Naandat','maryannedashe@gmail.com','+2349067721797','WNNN','I believe that given my knowledge and work background alongside skills that I possess I am passionate about giving back to my community and society at large. I am also passionate about mentorship and believe that the younger generation need guidance and mentorship to help them achieve their fullest potential and capabilities towards building sustainable societies.','PM103'),
    ('Ujunwa','Joy Nweke','obianujunweke98@gmail.com','+2347062495286','WGMN','I want to contribute to WODDI''s mission of empowering women and strengthening communities through service, mentorship, and leadership. Having previously volunteered at a WODDI event, I have seen the organization''s impact firsthand. I would like to support community outreach, mobilize women, and help expand WODDI''s programmes within my local community while continuing to develop as a values-driven ','ALDC101'),
    ('Praise','Emmanuel','mbemsiemma@gmail.com','+2347068150678','WGMN','Every woman ( including married women because sometimes we are lost in purpose when we get married) deserves to be seen and heard. I want to be used as that vessel to make it happen.','ASRC103'),
    ('Bola','Florence Adesoye','adebolaadeyemi36@gmail.com','+2348144648973','WGMN','I like be involved in a community where women are valued, empowered and enlightened about life generally.','CR105'),
    ('Mercy','Obot','contactmercyobot@gmail.com','+2348167195535','WGMN','I want to represent WODDI because I am passionate about empowering women and building supportive communities. As a gender justice journalist, I will use my communication and advocacy skills to connect more women to WODDI, promote its mission, and inspire positive change in my country.','VOL104'),
    ('Valerie','Wilson','valewilson2005@gmail.com','+2349154497154','WNNN','I want to represent WODDI in my country because I believe young people have the power to drive meaningful change when they are given the right opportunities and support. As a law student and youth leader, I have actively participated in leadership initiatives, community projects, and advocacy programmes that have strengthened my passion for empowering others.  Representing WODDI would allow me to ','CL102'),
    ('Bolanle','Olufunke SHOTE','Olufunkeshote8@gmail.com','+2347035954700','WGMN','I am passionate about mentoring and coaching young people as they start on their professional journeys in life and being part of WODDI could help me do that in a more structured way','PM104'),
    ('Duyile','Anuoluwapo Treasure','anuoluwapoduyile5@gmail.com','+2347086716459','WNNN','I believe WODDI is another way of creating/making impact in the society and I hope to represent WODDI as a change maker','ACHL104'),
    ('Evelyn','Emeka ogbu','avisfriendly001@gmail.com','08034525784','WGMN','Network  and growth','LDC104'),
    ('Cecilia','Okwosi Udeh','okwosi@yahoo.com','+2347015929898','WGMN','I want to represent WODDI because I am passionate about empowering women, strengthening families, and creating lasting community impact. I am committed to advancing WODDI''s vision by mobilizing, mentoring, and inspiring women to lead with purpose and transform their communities.','SRC105'),
    ('Promise','Gabriel Frankson','promsgabrielfrankson@gmail.com','+23407083026923','WGMN','I want to represent WODDI because its mission resonates deeply with both my personal journey and my life''s work. As a firstborn daughter, I have navigated significant responsibilities while also learning to thrive as a neurodivergent woman. Those experiences taught me resilience, empathy, and the importance of safe, supportive communities. They also ignited a lifelong passion for ensuring that gir','CR106'),
    ('Etim','Daniella Emediong','etimdaniella07@gmail.com','+2348114789742','WNNN','I want to represent WODDI because I love serving my community and connecting people to opportunities that can help them grow. I''d love to help create more awareness, encourage participation, and contribute to making a meaningful impact in my country.','ASRC104'),
    ('Usman','Usman Ajiya','usmanusmanajiya@gmail.com','+2348145100274','WNNN','I want to represent WODDI because I am passionate about empowering young people through entrepreneurship, innovation, and sustainable development. As the founder of UU AJIYA Agrovet Enterprises and a Veterinary Medicine student, I understand the challenges young entrepreneurs face. I want to use this opportunity to connect more young people to WODDI''s programmes, promote innovation, support local ','SRC106'),
    ('Vivian','Yanmekaa','yanmekaavivian@gmail.com','+2348135654031','WGMN','I am excited about WODDI because this phenomena perfectly align with my passion of raising and empowering young women raging from teenagers to young married.','CR107'),
    ('Linda','Uchenna Ugwueze','lindauchenna290@gmail.com','0906 839 6863','WGMN','To enrich my knowledge and experience in my community based work and implement the vision of WODDI.','VOL105'),
    ('Favour','Efe Edonojie','edonojiefavour@gmail.com','08117188467','WNNN','As a physiotherapist and youth advocate, I have developed a deep understanding of the importance of health, inclusion, and community engagement. Through my work and volunteer experiences, I have seen how informed, empowered young people can become catalysts for positive change. I want to represent WODDI in my state because I believe every woman and girl deserves the opportunity to thrive, lead, an','ASRC105'),
    ('Dr','Sherifah Mojisola Mohammed','cherimoh@yahoo.co.uk','08037072917','WGMN','To contribute to development','CR108'),
    ('Amohelang','Chokwe','amochokwe637@gmail.com','+27740632683','WNNN','I want to represent WODDI because I believe in creating safe, empowering spaces for young women to discover their purpose and grow into confident leaders. My experiences in medical education, student advocacy, and tutoring have shown me the transformative power of mentorship and collaboration. Representing WODDI would allow me to amplify these values, connect young women to opportunities, and cont','PM105'),
    ('Ademokun','Dolapo Ibironke','dolapovet@gmail.com','+2348150426113','WGMN','I am passionate about women empowerment/ impacting them and mentoring especially in Nigeria, we still need to stand up for the girl child.','CR109'),
    ('Azeezat','Ilupeju','azeezatopeyemi@gmail.com','7066563899','WGMN','To contribute my own quota to humanity','LDC105'),
    ('adebowale','Yusuff','debowaleyusuff@gmail.com','+2348033465015','WGMN','As a broadcast journalist of over 30 years, I have dedicated my career to human angle stories that give voice to women''s struggles and triumphs in my Country. Representing WODDI in my country would let me extend this advocacy into direct community building, connecting women aged 30 and above to a network where they can learn, grow, connect, and lead with purpose.','LDC106'),
    ('Diane','Onwubiko','mzdizle@gmail.com','+12348031974348','WGMN','Because I am passionate about community development and have hands-on experience in outreach programs, including health sensitization and data collection in local communities. I am organized, dependable, and able to work with diverse groups to achieve shared goals. This role will allow me to contribute meaningfully, strengthen program impact at the grassroots level, and further develop my leadersh','LDC107'),
    ('Aanuoluwapo','Ashade','anuoluwaposimiashade@gmail.com','08136152386','WGMN','I want to represent WODDI in my country because I believe deeply in the power of women to transform communities when they are given the tools to heal, discover their strengths, develop their skills, and deploy their potential. My passion lies in creating safe spaces for growth and empowerment, and I see WODDI as a platform to amplify that vision. By serving as a representative, I aim to connect wo','VOL106'),
    ('Anya','Ugochi Ben','anyaugochi38@gmail.com','+2348143580033','WNNN','I want to represent WODDI because I believe in empowering women through education, leadership, and community engagement. As a student nurse, I am passionate about preventive health and helping people make informed decisions that improve their lives. I would be honored to contribute to WODDIs mission of raising strong women and creating lasting impact in my community.','ACHL105'),
    ('Bilikisu','Lawal','lawalbilikisu039@gmail.com','+2347048867678','WNNN','I want to represent WODDI because I believe young women thrive when they have access to mentorship, leadership opportunities, and supportive networks. Through my experience in community development, youth engagement, and volunteer leadership, I have seen the impact of creating spaces where young people can learn, lead, and support one another. I would be honoured to help grow WODDI''s presence in m','DCL101'),
    ('Robert','Patience Ogechi','patiencerobert08@gmail.com','+2348123826864','WGMN','Because I promise the world will be a better place with women comes together to work','CHL102'),
    ('Blessing','Owunari Dakoru','onargraham@gmail.com','+2349059802537','WNNN','I’ll love to represent WODDI because I believe that change begins with empowering people through leadership, education and community.  I am passionate about mentoring young people and creating opportunities for growth. I see this as an opportunity to impact lives and become a positive contributor to society.  I am excited about building a strong local chapter that connects people with meaningful o','SRC107'),
    ('Pamela','Dodo','pamelladodo23@gmail.com','+27639632129','WNNN','I want to represent WODDI in South Africa because my work in local governance and development has shown me how much untapped potential exists among young women in under-resourced communities like the Eastern Cape. WNNN''s mentorship model aligns with what I''m already committed to building capable, confident leaders and representing WODDI would let me bring that work, and Eastern Cape voices, to a c','SRC108'),
    ('Amina','Alhassan','sheismeena@gmail.com','+2348037434189','WGMN','I want to amplify the voices of the underepresented on society','CR110'),
    ('Nolufefe','Ganjana','fefeganjana@gmail.com','+27833611544','WGMN','To further engage with women,empowering and assisting them in living better lives so that they can be able to help others.','PM106'),
    ('Hibatulwadud','Adeleke','hibatulwadud@gmail.com','+2347014736797','WNNN','I want to represent WODDI to empower young women in my community by creating opportunities for learning, collaboration, and innovation. I believe I can help expand WODDI''s impact while connecting more people in my region to its mission and opportunities.','SRC109'),
    ('zainab','nura','nurazainabsanusi@gmail.com','+2348162990161','WGMN','would be honored to represent WODDI in my country because I am passionate about promoting digital inclusion, innovation, and opportunities for women and young people. As a legal practitioner and educator, I have worked with diverse communities to raise awareness of rights, provide legal support, and mentor young women. I believe these experiences have equipped me to advocate for equitable access t','CR111'),
    ('Rukayyah','Abdulsalam','mamalolo9499@gmail.com','08033670509','WGMN','I want to represent WODDI to empower women, mentor young people, and lead community initiatives that create lasting social impact. My experience in public health, community development, and leadership aligns with WODDI''s mission to transform lives through service and empowerment.','SRC110'),
    ('Adekoya','Munirat Opeyemi','muniratadekoya@gmail.com','+2347072674766','WNNN','I don''t want to represent WODDI just to carry a title—I want to represent a possibility. Every day, I meet young people with ideas that could change their communities, but they don''t know where to start or who believes in them. I want to be the bridge that connects those young people to opportunities, knowledge, and hope. If WODDI gives me the platform, I will use it to build communities where you','ACHL106'),
    ('Ajanah','sakeenah','ajanahsekina728@gmail.com','+2348158640594','WNNN','I want to represent WODDI because I believe in a future where every girl’s voice is heard and valued.  Through my volunteer work with ILSWACI and HCOMDI in Sokoto, I’ve seen how mentorship and empowerment change the lives of girls and vulnerable children. WODDI’s mission to build inclusion and leadership aligns with the work I’m already doing in my community.  As coordinator for the WODDI INSTITUT','SRC111'),
    ('Bilyaminu','Sidi Umar','Sdbilya@gmail.com','08109595562','WNNN','I want to represent WODDI because I am passionate about community development, youth empowerment, and creating positive change. I want to help raise awareness, mobilize volunteers, and support programs that improve the lives of people in my community. I believe WODDI provides a platform to make a meaningful and lasting impact.','CHL103'),
    ('Saidat','hussaini','hussainisaidat772@gmail.com','08108658355','WNNN','I want to represent WODDI in my region because I am passionate about community development, youth empowerment, and advocating for children''s rights, education, and gender equality. Through my experience in community case management, GBV awareness, peacebuilding, and psychosocial support, I have seen the positive impact of working closely with communities. Representing WODDI will give me the opport','ASRC106'),
    ('UGWUMSINACHI','NGOZI CHRISTIANA','ng4ugwum@gmail.com','08039368255','WGMN','The vision of WODDI strongly aline with my personal convictions.','VOL107'),
    ('Esan','Tomilola Rhoda','rhodayuppy@yahoo.com','2347031242422','WGMN','I want to represent WODDI in my country because I am passionate about empowering women and creating positive change in my community. Through my volunteer experience in advocacy against Female Genital Mutilation (FGM), Gender-Based Violence (GBV), and community outreach, I have seen the importance of educating, supporting, and inspiring people to take action.  As a WODDI representative, I will acti','ACHL107'),
    ('Esther','Darlington','darlingtonesther77@gmail.com','+2347051438225','WNNN','I bring strong leadership, public speaking and communication skills, event hosting experience, youth engagement, and a growing network of students and young professionals. I also have experience in advocacy, organizing initiatives, and creating meaningful conversations that inspire action.','CHL104'),
    ('Barisi','Daniela k','kpurugbarabarisi@gmail.com','+23409050743322','WGMN','Because the world is evolving and moving forward to where women needs to speak, come out stand out wherever they are','ALDC102'),
    ('FAREMI','JANET TAYO','janetfaremi@hotmail.com','+2347038946495','WGMN','Am on of the best','CR112'),
    ('maryam','shehu','maryamahshehu@gmail.com','+2348135728213','WNNN','I want to represent WODDI in my region because I am passionate about empowering women through technology, education, and community. As a Human Physiology graduate with a strong interest in health technology, I believe access to opportunities and mentorship can transform lives.','LDC108'),
    ('Esther','Amarachi Amaechi','amarachiamaechi2@yahoo.com','+2347032405172','WNNN','I want to represent WODDI in Nigeria because I''ve already been doing this work quietly, and I''m ready to do it with structure and reach. Through NYSC''s SDG outreach, I coordinated stakeholders across multiple communities; through my customer service role, I''ve seen firsthand how women navigate systems that weren''t built with them in mind. WODDI gives that experience a clear mission and a Pan-Afric','LDC109'),
    ('Lucinda','C Evans','philisa.abafazi@gmail.com','+27734244665','WGMN','There is still so Much work to do with Women and for our Collective freedom','VOL108'),
    ('Samiat','Olanrewaju','olanrewajusamiat14@gmail.com','+2347026720872','WNNN','I chose the Assistant State/Regional Coordinator role because it aligns with my current level of experience while giving me the opportunity to grow as a leader. I enjoy supporting teams, coordinating activities, communicating effectively with members, and contributing to the successful execution of programs. This role will allow me to learn, serve, and develop my leadership skills while making a m','ASRC107'),
    ('Zainab','Umar','zainabumar870@gmail.com','+2348061616689','WGMN','To enlighten mothers, and strengthens families  and empower women','SRC112'),
    ('Zeenatu','-','zkhamees1@gmail.com','+2348138644994','WGMN','Impact + Community Focus: I want to represent WODDI in my country because I believe women here deserve access to the same platforms for empowerment, leadership, and health advocacy that WODDI provides globally.   In my region, many women face challenges with limited access to mentorship, reproductive health education, and economic opportunities. I am passionate about bridging that gap.   As a Nige','SRC113'),
    ('Okoloana','Chiamaka Mirian','okoloanamirian@gmail.com','+2347061883099','WGMN','I will love to represent WODDI in my country and region to bring it closer to people who truely needs it. I believe in serving to gain skills and experience and bring the one I have to help an organization','SRC114'),
    ('Adenose','Favour Oluwakemi','adenosefavour@gmail.com','+2348147624310','WNNN','I want to represent WODDI in my country because I am passionate about creating positive change through community engagement and advocacy. I believe this opportunity will allow me to make a greater impact, inspire others, and contribute meaningfully to my community while growing as a leader.','ACHL108'),
    ('Oluwabunmi','Oyerinde','rndolubunmi@gmail.com','08107209378','WGMN','I believe in the impacts work vof the WODDI','VOL109'),
    ('Ugochi','Gift Anaele','anaeleugochi2018@gmail.com','+2348133489700','WNNN','To create impact','CHL105'),
    ('Aishat','Mohammed','eeshat4mma@gmail.com','+2347036113576','WGMN','I want to represent WODDI in my country because I am passionate about empowering women and promoting inclusive development. I believe I can help expand WODDI''s impact by engaging communities, organizing awareness and capacity-building programs, and creating opportunities for women and young people to thrive. With my experience in community engagement and leadership, I am committed to representing ','CR113'),
    ('Zainab','Ibrahim Jalo','zainab4274@gmail.com','+234 803 559 2947','WNNN','I want to represent WODDI because I am passionate about empowering young people and supporting my community. I want to help individuals gain leadership, entrepreneurship, and digital skills that can improve their lives and create positive change.','ALDC103'),
    ('Zipporah','Ibrahim','noblezeepy@gmail.com','+2348032302136','WGMN','To strengthen my leadership voice and for mentorship , growth and meaningful sisterhood','SRC115'),
    ('Rejoice','Samuel Sule','rejoicesamuel766@gmail.com','07033610132','WGMN','I support the vision of WODDI','SRC116'),
    ('Itohowo','Etim Etim','itohowoetim54@gmail.com','08126004115','WGMN','I want to represent WODDI in my country because I am passionate about empowering young people through education, advocacy, and community engagement. With my background in health education, mental health advocacy, and volunteering, I have seen the impact that informed and motivated youth can make in solving local challenges.','VOL110'),
    ('Goodness','Oluwadara Ogunlade','ogunladegoodness47@gmail.com','+2348147377759','WNNN','I want to contribute to raising confident, purpose-driven young women through mentorship, leadership, and community service. I believe that empowering young women creates stronger families and communities. Serving with WODDI will also allow me to develop as a leader while helping others discover opportunities for growth.','SRC117'),
    ('Aishatu','Abdulkadir','abdulkadiraishatu2023@gmail.com','+2347045943755','WNNN','Develop experience skills','ALDC104'),
    ('ODEZUGO','TOKYO','odezugotokyo@gmail.com','+2349068303234','WNNN','I want to represent WODDI in my country, because I believe in empowering people, most especially women and young girls. I believe they deserve access to opportunities and resources needed to thrive in today’s technology driven society. As a representative, I want to raise awareness about WODDI''s mission, organize impactful programs, and encourage more people to develop digital skills that can impr','ASRC108'),
    ('Vathiswa','-','veemanentsa@gmail.com','ZA','WGMN','To mentor & develop others','LDC110'),
    ('Abdulwaheed','Halima Bukola','halima3451@gmail.com','+2349034180295','WNNN','The initiative aligns with my values','CHL106'),
    ('Alashe','Monsurat Morounmubo','babybliss117@gmail.com','+2349028415864','WNNN','I''m a change agent and I want to influence my nation positively.','PM107'),
    ('Sandra','Atsu','sandratsu7502@gmail.com','+233246507502','WGMN','I want to represent WODDI in Ghana because I care about helping people in my community.   I know the challenges young people and local groups face here, and I want to be a bridge between WODDI and the community.   With my skills in data entry, designing banners and business cards, and basic website development, I can support outreach, communication, and organizing.   I’m committed, willing to lear','VOL111'),
    ('Abigail','Odukuwaa Sackey','abigailsackey115@gmail.com','+233531768835','WNNN','Okay I want to represent your organization in my country because I want to make sure women are heard ,woman get the necessary education then need','ASRC109'),
    ('Patience','Opega','chantelillybrand@gmail.com','+2349113195640','WGMN','I am a Deputy Superintendent of Fire with the Federal Fire Service, Nigeria, and a PhD researcher in Disaster Risk Management. My work focuses on fire prevention, emergency preparedness, disaster risk reduction, and community safety. I am committed to addressing challenges related to public awareness, emergency response, and climate resilience through research, capacity building, and evidence base','CR114'),
    ('Jane','Sharon Akinyemi','bccjaneakinyemi@gmail.com','+2349015937781','WGMN','My combined experience in teaching and career counselling reflects my passion for empowering others through education, mentorship, and lifelong learning.','PM108'),
    ('Usman','Farida Ibrahim','usmanfarida07@gmail.com','+2347033243291','WNNN','I want to represent WODDI because I believe young people can be powerful drivers of sustainable development when they are equipped with the right opportunities and support. In my community, I see gaps in health education, leadership, and youth engagement, especially for women and underserved populations. I want to bridge those gaps by creating awareness, building partnerships, and mobilizing young','SRC118'),
    ('Chukwubusonma','Oboke Angel','sonmaoboke@gmail.com','+234 9024406005','WNNN','I want to represent WODDI in Nigeria because I believe young women are powerful drivers of social change when they are equipped with the right opportunities, knowledge, and networks. Throughout my journey in youth advocacy, policy research, and community leadership, I have worked to expand access to education, civic engagement, and leadership opportunities for young people, particularly girls and ','CL103'),
    ('Chidinma','Mary Nwosu','chidinmamary994@gmail.com','+2347032336204','WGMN','I want to represent WODDI to empower women, strengthen families, and promote values based leadership through community engagement, and sustainable development initiatives in my region.','ASRC110'),
    ('Clara','Dantani','claradantani@gmail.com','+2348058074099','WNNN','To contribute my knowledge, local understanding, and passion for community development while connecting more people to opportunities, resources, and programs that promote positive change.','ASRC111'),
    ('Azeez','Test','craigfunds@gmail.com','08071211007','WGMN','to impact','CR115'),
    ('Philomina','Obijiaku','udephil@gmail.com','+2348064099997','WGMN','I am passionate about serving women and communities through leadership, mentorship, and practical support. Throughout my career in customer experience, business development, and administration, I have learned that meaningful leadership is built on empathy, integrity, and service. I have also volunteered as an HIV/AIDS peer educator, educating young people in schools, churches, and communities on p','ASRC112'),
    ('Justina','Alo','justinaalo222@gmail.com','+2348160818002','WNNN','I derive joy in taking the stage to drive value and impact lives in whatever sphere life positions me.','CA101'),
    ('Chukwuemeka','Vivian','vivianchukwuemeka40@gmail.com','+2348051520339','WNNN','I want to represent Woodi in FCT because I am passionate about youth development and girls education having volunteered and attended the WIWS summit twice I saw Woodi''s impact first hand I want to help expand that work in my region by mobilizing young people for education advocacy and skills program.','ASRC113'),
    ('Eneh','Godwin','enehgrace6@gmail.com','+2349130830880','WGMN','I want to represent WODDI in my country because I am passionate about creating positive change in my community through advocacy, leadership, and community development. Representing WODDI would give me the opportunity to connect with like-minded individuals, promote its mission, and support initiatives that empower young people and women. I am committed to using the knowledge, skills, and network I','ALDC105'),
    ('Onuchukwu','Nwalie','oziomanwalie247@gmail.com','+2348102656099','WNNN','I want to represent WODDI because I believe in empowering young people and creating opportunities for growth. I would love to help connect more people in my community to WODDI''s programs and contribute to making a positive impact in my region.','ASRC114'),
    ('Elizabeth','Peter','elizabethpeter706@gmail.com','+2349067871303','WNNN','Because I believe in learning new things and helping others','ASRC115'),
    ('FAMUBO','JOSEPH','famubojoseph@gmail.com','+2348030618179','WGMN','To contribute to women empowerment','SRC119'),
    ('Cathrine','Phiri','catherinephirizw@gmail.com','+263781629775','WNNN','I have been doing the work WODDI exists to scale, just in isolation. My time in Northern Europe, Latvia, showed me firsthand how much further impact on women''s lives goes when it''s connected to a coordinated network rather than left to run alone. I came back determined to build that bridge for Zimbabwe. Through SheDIRACT, I am already reaching young women here, but I am doing it without the infras','CL104'),
    ('Munezero','Bélyse','belmunezero486@gmail.com','+25771770428','WGMN','Je souhaite représenter WODDI au Burundi afin d''aider davantage de femmes à accéder au mentorat, au développement du leadership et aux opportunités de croissance personnelle.','DCR102'),
    ('Adesanya','Opeyemi Florence','Opeyemiflorenceadesanya@gmail.com','+2349036032626','WGMN','I really want an opportunity to serve others.','VOL112'),
    ('Tarnue','Z. Brown','tarnuezbrown60@gmail.com','+231776464208','WNNN','Well, because I am a young and native of the Liberian soil,had work with both Youth and adult from with the TVET Ariana for over 3 years, and our work is seem across my country Liberia. So if am opportune I will bring on board a lot of experience besides our normal TOR. In my opinion am best for this position, because with my exting connection and experts idea will be higher needed. I also volunte','CL105'),
    ('Isika','Florence Igelle','isikaflorence03@gmail.com','+2348073801947','WNNN','I want to represent WODDI because I understand personally what it means to have potential but not always have access to the guidance, exposure or support needed to grow.  I grew up in a humble, first-generation family where opportunities were not always easy to come by. There were moments when even basic stability felt uncertain and education was tough. I know that many young women are capable, in','SRC120'),
    ('CHRISTINA','EDWARD BALANSO','cbalanso2@gmail.com','+2348108960216','WGMN','Growing up in Northern Nigeria, I saw many talented young women whose dreams were limited by culture, lack of opportunities, and the absence of mentors to guide them. Those experiences shaped the way I see leadership and service. They also made me realize how much difference one supportive community can make in a young woman''s life.  That is why I want to represent WODDI in Nigeria. I want to help','LDC111'),
    ('Jnn','-','hhhhj@gmail.com','5666','WNNN','Hhhhh','CA102'),
    ('Eunice','Favour Eboatu','favoureboatu@gmail.com','08030710596','WGMN','I am a social worker and I know representing WODDI means opportunity to impact more lives and be a voice to the voiceless','VOL113'),
    ('Igwe','Esther','essydiamond688@gmail.com','+2347044210798','WNNN','Ebonyi State is one of the underdeveloped part of Nigeria.Girls and women in this part lacks awareness about what women in leadership and policy making is all about,gender equality and also that female genital mutilation is a harmful practice..I believe that this platform will give me the leverage to reach out to these people in rural areas to educate ana also create awareness about all they need ','SRC121'),
    ('Emeruwa','Winifred Oluchi','blisschambers1@gmail.com','+2347069231854','WGMN','To reach to more woman','CR116'),
    ('nigeria','-','nigeriawoddi@gmail.com','+23480622775','WGMN','i have the qualities','VOL114'),
    ('Uche','Ikezue','uckurue008@gmail.com','+234 806 818 4441','WGMN','To help WODDI grow.','VOL115'),
    ('Edoka','Esther','estheredoka6@gmail.com','+2348135682947','WNNN','I want to represent WODDI in my country because I believe in its mission and would love to help create more awareness, connect people with its opportunities, and make a positive impact in my community while growing personally and professionally.','LDC112'),
    ('Mirembe','Grace','mirembegrace941@gmail.com','+256707650889','WNNN','I want to represent WODDI in my country because I believe young people, especially women and girls, deserve greater access to opportunities, leadership, and platforms where their voices can shape change. As a graduate  and youth advocate, I interact with young people every day and have seen the challenges they face, including gender inequality, limited access to information, and barriers to meanin','ASRC116'),
    ('Victoria','Ekenma Godwin','ekemmaokafor661@gmail.com','+234 9166771819','WGMN','To lead the women and more especially the youth in to the revelational knowledge of Christ, the make the fear of God known to them and which is the biggining of wisdom','LDC113'),
    ('Meyanui','petra','meyanuipetra36@gmail.com','+237675408114','WNNN','I want to represent WODDI because I believe Africa’s greatest resource is its young people, and meaningful change happens when they are equipped to lead. Through my background in Public Health and my involvement in community health promotion and youth-focused initiatives, I have witnessed how informed leadership transforms communities. As a WODDI leader, I want to build platforms that empower youn','DCL102'),
    ('Favour','Ogechukwu Uche','favouruche232@gmail.com','+2348145869208','WNNN','I want to represent WODDI because I really needed mentorship while growing up but I couldn’t afford to pay a mentor as they all had a price tag but I scaled through somehow and I really want to assist females coming up in the best way that I can.','CL106'),
    ('Khairat','Ikharo','ik.khairat@gmail.com','+2347063283967','WGMN','I want to represent WODDI in Port Harcourt because I’ve seen how much women in my community need structured spaces to grow not just encouragement, but real skills, mentorship, and access to opportunity. My own journey navigating a tough job market has shown me how much difference guidance and a strong network can make. I want to bring that same structure and support to women here.','VOL116'),
    ('Comfort','Sadeko','comfortsadeko@gmail.com','+2348166715338','WGMN','I want to make an impact in the lives of women, just as other women have mentored and helped me become who I am today.','VOL117'),
    ('Florence','Shittu','shittuflorence41@gmail.com','+2348141787279','WNNN','The vision of WODDI aligns with my career path. I''m passionate about SDG 5.','CA103'),
    ('Ufedo','MaryCynthia AROME,','aromecindy@gmail.com','+2348165462277','WGMN','Passionate about empowering women and strengthening communities through service, mentorship, and leadership. I want to represent WODDI because its mission aligns with my values of creating positive change, supporting women''s growth, and inspiring families and communities to thrive.','SRC122'),
    ('Aishat','Yakubu','aishayakubufaith@gmail.com','+2348062904637','WGMN','It has been my desire to impact lives and to also see growth in the life of individuals','ALDC106'),
    ('Zainab','Tajudeen Omowumi','daramolaomowunmi62@gmail.com','+2348132737578','WNNN','I want to represent WODDI to contribute my skills, make impact and be the change that i want.','CA104'),
    ('Mary','Abiodun','maryabiodun01@gmail.com','+2348161560814','WGMN','It''s an avenue to reach more women and girls to empower them. That''s one of my personal vision.','DCR103'),
    ('Olanrewaju','Elizabeth Idowu','Hellolanrewajuolakanmi@gmail.com','+2349028348900','WNNN','I want to represent WODDI in my country to empower young people, create meaningful impact in my community, and advance WODDI’s mission through leadership, advocacy, and collaboration.','CL107'),
    ('Bukola','Ayeni','victoriabukolaayeni@gmail.com','234+ 9029886019','WNNN','I''m very passionate about change making and I believe becoming one of WODDI in my country will help me gain experience, hands skills and also help me connect with like-minded individuals.','CL108'),
    ('Abubaida','Uthuman','abubaidacoder@gmail.com','+256772352272','WGMN','To empower women and serve the young people to be respected and valued in the society .They should be given priority in their rights .','CR117'),
    ('Shekinah','Yeye Michael','shekinahmichael52@gmail.com','+2348162725630','WNNN','I want to represent WODDI because I believe empowering women and girls creates lasting change in communities. I am passionate about leadership, education, and sustainable development, and I want to use my experience in coordinating teams and building partnerships to expand WODDI''s impact, mobilise volunteers, and ensure more women and girls have access to opportunities that help them thrive.','SRC123'),
    ('Joseph','rejoice','jrejoice094@gmail.com','08152921247','WNNN','Being a Women to make a difference','CA105'),
    ('Ngozi','Joy Ken-Nwankwo','ngozijoykennwankwo@gmail.com','+2348102741838','WNNN','I want to represent WODDI because I strongly believe in women’s empowerment. Women should be exposed to opportunities that broaden their horizons, unlock their potential, and equip them to make meaningful contributions to their families, communities, and society. I believe lasting change begins with empowered women who are prepared to lead, serve, and inspire others.  Throughout my journey, I have','SRC124'),
    ('Okoko','Ann','reginarhema81@gmail.com','rrr','WNNN','Good Afternoon Everyone.    1. The intro is too fast, one can barely read the writeup. The number of seconds the writeup are left on screen is too short. The intro should calmly explain what the harmony hub is about, the way the writeup are moving in the intro is too fast for someone to read. 2. The name of the presenter and guests were written in 2 colors, red and green, its a contrasting color w','CA106')
    ) as t(first_name, last_name, email, phone, network, why, member_no)
  loop
    begin
      -- idempotency: this ID already placed anywhere → skip person
      if exists (select 1 from applications a where a.member_no = v.member_no)
         or exists (select 1 from profiles pr
                     where pr.membership_no = v.member_no) then
        skipped := skipped + 1;
        continue;
      end if;

      select id, membership_no into p_id, p_member
        from profiles
       where lower(email) = lower(v.email)
         and merged_into is null
       limit 1;

      if p_id is not null then
        -- existing account → crown it with the ID (only if it has none)
        if p_member is null then
          update profiles set membership_no = v.member_no where id = p_id;
        end if;
        crowned := crowned + 1;
        body := 'Dear ' || v.first_name || ','
          || e'\n\nThank you for registering to serve with WODDI. '
          || 'Your permanent Volunteer ID is:'
          || e'\n\n        ' || coalesce(p_member, v.member_no) || e'\n\n'
          || 'You already have a WODDI account with this email — sign in '
          || 'as usual at https://woddicrm.org and your ID now shows on '
          || 'your record. Your 14-day Activation Journey opens on '
          || '3 August 2026.'
          || e'\n\nWith warmth,\nThe WODDI Team';
      else
        -- fresh person → approved application carrying the ID
        insert into applications
          (first_name, last_name, email, phone, network, org_unit_id,
           motivation, status, decision_reason, decided_at,
           member_no, id_mailed_at)
        values
          (v.first_name, v.last_name, v.email, v.phone,
           v.network::public.network_code, hq, v.why, 'approved',
           'Onboarded from WODDI Institute registrations (Jul 2026)',
           now(), v.member_no, now());
        imported := imported + 1;
        body := 'Dear ' || v.first_name || ','
          || e'\n\nThank you for registering to serve with WODDI. '
          || 'You are approved, and this is your permanent Volunteer ID:'
          || e'\n\n        ' || v.member_no || e'\n\n'
          || 'You do NOT need to register again. To enter your WODDI '
          || 'workspace, go to:' || e'\n'
          || 'https://woddicrm.org/#/id' || e'\n\n'
          || 'type your ID Number, confirm your name, choose a password '
          || '— and you are in. Your 14-day Activation Journey opens on '
          || '3 August 2026.'
          || e'\n\nWith warmth,\nThe WODDI Team';
      end if;

      perform send_email(v.email,
        coalesce(nullif(v.first_name, ''), 'Volunteer'),
        'Your WODDI Volunteer ID: ' || v.member_no,
        email_wrap('Your WODDI Volunteer ID', body));
      mailed := mailed + 1;

    exception when others then
      raise notice 'cohort row skipped (%): %', v.email, sqlerrm;
    end;
  end loop;

  raise notice 'cohort: % imported, % crowned, % mailed, % skipped',
    imported, crowned, mailed, skipped;
end $$;

-- profile-claim carries the ID (unchanged from v1)
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public as $$
declare app public.applications;
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
      (new.id, app.first_name, app.last_name, new.email, app.phone,
       app.network, app.org_unit_id,
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
  return new;
end; $$;

create or replace function public.id_lookup(idno text)
returns table (first_name text, last_name text,
               email_hint text, email text, claimed boolean)
language plpgsql stable
security definer set search_path = public as $$
declare a record; p record;
begin
  select * into p from profiles
   where upper(membership_no) = upper(trim(idno))
     and merged_into is null limit 1;
  if p.id is not null then
    return query select p.first_name, p.last_name,
      regexp_replace(p.email, '(^..)[^@]*', '\1***'), p.email, true;
    return;
  end if;
  select * into a from applications
   where upper(member_no) = upper(trim(idno))
     and status = 'approved' limit 1;
  if a.id is not null then
    return query select a.first_name, a.last_name,
      regexp_replace(a.email, '(^..)[^@]*', '\1***'), a.email,
      (a.profile_id is not null);
    return;
  end if;
  return;
end; $$;
grant execute on function public.id_lookup(text) to anon, authenticated;

insert into public.schema_migrations (version, name)
values (59, 'institute_cohort_ids') on conflict (version) do nothing;
