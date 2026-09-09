/**
 * Phase 131 — the Volunteer Dashboard (WGMN / WNNN).
 *
 * Routes: #/ (home, non-HQ), #/my/:tab, #/view-as/:id (HQ, read-only).
 * One RPC (volunteer_home) feeds every card; the shell caches it for a
 * minute. Nothing on this page is estimated or padded: a tile shows a
 * number only when the database recorded the rows behind it.
 *
 * Tabs: home · profile · network · leadership (leaders) · learning ·
 * impact · referrals · documents · calendar · support · safeguarding ·
 * settings. Tasks, Meetings, Announcements and Messages open the existing
 * pages, which wear the same shell for volunteers.
 */
import { el, clear } from '../core/dom.js';
import { t, fmtDate, fmtDateTime, fmtNumber, getLocale, setLocale, supportedLocales } from '../core/i18n.js';
import {
  volunteerHome, updateMyProfile, avatarUrl, uploadAvatar, changePassword,
  fileTicket, fileCase, submitReferral, documentUrl,
  acceptAppointment, declineAppointment, onboardingStatus, setOnboardingStep,
} from '../core/db.js';
import { getHome, invalidateHome } from '../core/homecache.js';
import { renderVolunteerShell, networkName } from '../components/vshell.js';
import { apptBadge } from './structure.js';
import { renderCourses } from '../components/courses.js';
import { icon } from '../components/icons.js';
import { toast, toastError } from '../components/toast.js';
import { openModal, closeModal } from '../components/modal.js';
import { AFRICAN_COUNTRIES, NG_STATES, countryIso, flagSrc } from '../core/geo.js';

const TAB_TITLE = {
  home: 'v.navHome', profile: 'v.navProfile', network: 'v.navNetwork',
  leadership: 'v.navLeadership', learning: 'v.navLearning', impact: 'v.navImpact',
  referrals: 'v.navReferrals', documents: 'v.navDocuments', calendar: 'v.navCalendar',
  support: 'v.navSupport', safeguarding: 'v.navSafeguarding', settings: 'v.navSettings',
  templates: 'v.navTemplates', reflinks: 'nav.reflinks',
};
const LEVEL_KEY = {
  headquarters: 'v.lvlHq', country: 'v.lvlCountry', state_region: 'v.lvlState',
  district_lga: 'v.lvlLga', community_cluster: 'v.lvlCluster', chapter: 'v.lvlChapter',
};
const LOCALE_NAMES = {
  en: 'English', fr: 'Français', pt: 'Português', ar: 'العربية',
  sw: 'Kiswahili', ha: 'Hausa', yo: 'Yorùbá', ig: 'Igbo',
};
const REFERRAL_CATS = ['welfare', 'health', 'education', 'livelihood',
  'community_need', 'leadership_candidate', 'other'];
const REFERRAL_LADDER = ['submitted', 'received', 'assigned', 'in_progress', 'closed'];
const TICKET_CATS = ['login', 'app_problem', 'certificate', 'role_access',
  'training_access', 'technical', 'other'];
const STATIC_DOCS = [
  { key: 'v.docHandbook', href: '/content/leadership-manual.pdf', kind: 'pdf' },
  { key: 'v.docConduct', href: '/content/code-of-conduct.html', kind: 'html' },
  { key: 'v.docAgreement', href: '/content/volunteer-agreement.html', kind: 'html' },
];

export async function render(root, params, ctx) {
  const viewAsId = params.id || null;
  const tab = TAB_TITLE[params.tab] ? params.tab : 'home';
  // The route this render belongs to. If the browser moves on while the
  // bundle is loading (a dropped session sends people to #/login), this
  // render must not touch the page any more: an earlier build drew its
  // error card over the login form in exactly that case.
  const myRoute = location.hash;
  const stale = () => location.hash !== myRoute;
  if (!ctx.profile) { location.hash = '#/login'; return () => {}; }

  let h;
  try {
    h = viewAsId ? await volunteerHome(viewAsId) : await getHome();
  } catch (err) {
    if (stale()) return () => {};
    console.error('[home] bundle failed:', err);
    const notSignedIn = /not signed in|jwt|401/i.test(String(err?.message || err?.code || ''));
    if (notSignedIn) { location.hash = '#/login'; return () => {}; }
    clear(root);
    root.append(el('div', { class: 'vs-shell' }, [el('div', { class: 'vs-main' }, [
      el('div', { class: 'vs-content' }, [errorState(
        () => render(root, params, ctx), err)])])]));
    return () => {};
  }
  if (stale()) return () => {};
  const ro = !!viewAsId;                        // read-only "View as"
  const P = h.profile;
  const shell = renderVolunteerShell(root, {
    profile: P, modules: ctx.modules, titleKey: TAB_TITLE[tab],
    viewingAs: ro ? { id: P.id, name: `${P.first_name} ${P.last_name}` } : null,
  });
  const out = shell.outlet;
  const isLeader = (h.roles || []).length > 0;

  const TABS = {
    home, profile: profileTab, network, leadership, learning, impact,
    referrals, documents, calendar, support, safeguarding, settings, templates, reflinks,
  };
  try { await (TABS[tab] || home)(); }
  catch (err) {
    if (stale()) return shell.teardown;
    console.error('[home] tab failed:', tab, err);
    clear(out); out.append(errorState(() => render(root, params, ctx), err));
  }
  return shell.teardown;

  /* ================================================================== */
  /* HOME                                                               */
  /* ================================================================== */
  async function home() {
    clear(out);
    out.append(welcome());
    out.append(statRow());

    // Candidates: the activation journey door (the 14 days live on #/me)
    if (h.journey && h.journey.status === 'in_progress' && !ro) {
      out.append(el('div', { class: 'vs-card vs-journey' }, [
        el('div', { class: 'grow' }, [
          el('b', { text: t('v.journeyTitle', { day: h.journey.day }) }),
          el('div', { class: 'muted', text: t('v.journeyHint',
            { date: fmtDate(h.journey.extended_until || h.journey.due_at) }) }),
        ]),
        el('a', { href: '#/me/journey', class: 'btn btn--primary', text: t('v.journeyGo') }),
      ]));
    }

    if (isLeader && !ro) {
      const pending = (h.roles || []).filter((r) => !r.accepted_at && !r.declined_at);
      if (pending.length) out.append(acceptanceCard(pending));
      out.append(await onboardingCard());
    }
    const grid = el('div', { class: 'vs-grid' });
    grid.append(learningCard(), tasksCard(), networkCard());
    grid.append(meetingsCard(), announcementsCard());
    if (isLeader && h.leadership) grid.append(leadershipCard());
    grid.append(impactCard(), quickActions(), achievementsCard());
    out.append(grid);
    out.append(footerLine());
  }

  function term(level) {
    const tm = h.terms || {};
    return tm[level] || t(LEVEL_KEY[level] || 'v.lvlUnit');
  }
  function contextLine() {
    const seat = (h.roles || [])[0];
    const parts = [P.network, P.country || unitOf('country'), P.state_region || unitOf('state_region'),
      P.lga || unitOf('district_lga'), unitOf('chapter'),
      seat ? t(`role.${seat.role}`) : (P.role_applied || t('v.volunteer'))].filter(Boolean);
    return `${P.first_name} ${P.last_name} \u2014 ${parts.join(' | ')}`;
  }
  function welcome() {
    const seat = (h.roles || [])[0];
    const designation = seat ? t(`role.${seat.role}`) : (P.role_applied || t('v.volunteer'));
    const quote = P.network === 'WNNN' ? t('v.quoteWnnn') : t('v.quoteWgmn');
    const line = (k, v) => el('div', { class: 'vs-welcome__line' }, [el('small', { text: k }), el('b', { text: v || '\u2014' })]);
    return el('section', { class: 'vs-welcome vs-welcome--simple' }, [
      avatarNode(P, 'vs-welcome__ava'),
      el('div', { class: 'vs-welcome__who' }, [
        el('h2', {}, [el('span', { text: t('v.welcome', { name: P.first_name }) }), flagNode(P, h)]),
        line(t('v.volunteerId'), P.membership_no || t('v.idPending')),
        line(t('v.fullName'), `${P.first_name} ${P.last_name}`),
        line(t('v.network'), P.network || ''),
        line(t('v.country'), (P.country || unitOf('country') || '')),
        line(t('v.designation'), designation),
        statusBadge(P.status, P.is_leader),
      ]),
      el('div', { class: 'vs-welcome__quote' }, [
        el('em', { text: `\u201C${quote}\u201D` }),
        el('small', { text: `\u2014 ${P.network || 'WODDI'}` }),
      ]),
    ]);
  }

  function statRow() {
    const tc = h.task_counts || {};
    const learn = learningSummary();
    const next = (h.meetings || [])[0];
    const im = h.impact || {};
    const participation = Number(im.meetings_attended || 0) + Number(im.tasks_completed || 0);
    const stat = (cls, ic, label, value, sub, href) => {
      const node = el(href ? 'a' : 'div', { class: `vs-stat vs-stat--${cls}`, href }, [
        el('div', { class: 'vs-stat__ic' }, [icon(ic, 20)]),
        el('div', { class: 'vs-stat__body' }, [
          el('div', { class: 'vs-stat__label', text: label }),
          el('div', { class: 'vs-stat__value', text: value }),
          sub ? (sub instanceof Node ? sub : el('div', { class: 'vs-stat__sub', text: sub })) : null,
        ]),
      ]);
      return node;
    };
    const bar = el('div', { class: 'vs-bar vs-bar--sm' }, [
      el('span', { style: `width:${learn.percent}%` })]);
    return el('section', { class: 'vs-stats' }, [
      stat('green', 'check', t('v.sMyStatus'), t(`status.${P.status}`), t('v.sThanks')),
      stat('violet', 'book', t('v.sLearning'), `${learn.percent}%`,
        el('div', {}, [el('div', { class: 'vs-stat__sub',
          text: learn.current ? t('v.sModuleIn', { m: learn.current }) : t('v.sNoCourse') }), bar]),
        '#/my/learning'),
      stat('blue', 'tasks', t('v.sTasks'), fmtNumber(tc.open || 0),
        tc.overdue ? t('v.sOverdue', { n: tc.overdue }) : t('v.sPending'), '#/tasks'),
      stat('pink', 'calendar', t('v.sMeeting'), fmtNumber((h.meetings || []).length),
        next ? t('v.sNext', { d: fmtDateTime(next.starts_at) }) : t('v.sNoMeeting'), '#/meetings'),
      stat('amber', 'users', t('v.sParticipation'), fmtNumber(participation), t('v.sActivities')),
      stat('lime', 'chart', t('v.sImpact'),
        fmtNumber(im.women_reached || 0),
        t('v.sImpactSub', { w: im.women_reached || 0, r: im.referrals || 0 }), '#/my/impact'),
      stat('sky', 'megaphone', t('v.sAnnouncements'), fmtNumber(h.announcements_unread || 0),
        t('v.sNewAnn'), '#/announcements'),
      stat('indigo', 'support', t('v.sSupport'), t('v.sNeedHelp'), t('v.sHere'), '#/my/support'),
    ]);
  }

  /* ---------------- cards ---------------- */
  function cardShell(ic, title, href, body, extraClass = '') {
    return el('div', { class: `vs-card ${extraClass}` }, [
      el('div', { class: 'vs-card__head' }, [
        el('span', { class: 'vs-card__ic' }, [icon(ic, 18)]),
        el('h3', { text: title }),
        href ? el('a', { href, class: 'vs-card__all', text: t('v.viewAll') }) : null,
      ]),
      body,
    ]);
  }

  function learningSummary() {
    const courses = h.learning || [];
    const enrolled = courses.filter((c) => c.enrollment_id);
    const total = enrolled.reduce((a, c) => a + Number(c.modules_total || 0), 0);
    const passed = enrolled.reduce((a, c) => a + Number(c.modules_passed || 0), 0);
    const percent = total ? Math.round((passed / total) * 100) : 0;
    let current = null;
    for (const c of enrolled) {
      const m = (c.modules || []).find((x) => !x.passed);
      if (m) { current = m.title; break; }
    }
    return { courses, enrolled, total, passed, percent, current };
  }

  function learningCard() {
    const L = learningSummary();
    const body = el('div');
    if (!L.courses.length) {
      body.append(el('p', { class: 'muted', text: t('v.learnNone') }));
    } else {
      const c = L.enrolled[0] || L.courses[0];
      const pct = c.modules_total ? Math.round((c.modules_passed / c.modules_total) * 100) : 0;
      body.append(el('div', { class: 'vs-learn__title', text: c.title }),
        el('div', { class: 'row', style: 'gap:10px;' }, [
          el('div', { class: 'vs-bar grow' }, [el('span', { style: `width:${pct}%` })]),
          el('b', { text: `${pct}%` })]));
      const list = el('ul', { class: 'vs-modules' });
      let seenOpen = false;
      for (const m of (c.modules || [])) {
        let st = 'v.modNotStarted', cls = 'todo';
        if (m.passed) { st = 'v.modCompleted'; cls = 'done'; }
        else if (c.enrollment_id && !seenOpen) { st = 'v.modInProgress'; cls = 'now'; seenOpen = true; }
        list.append(el('li', { class: `vs-mod vs-mod--${cls}` }, [
          el('span', { class: 'vs-mod__dot' }, [cls === 'done' ? icon('check', 12) : null]),
          el('span', { class: 'grow', text: `${t('v.module')} ${m.seq} \u2013 ${m.title}` }),
          el('small', { text: t(st) })]));
      }
      list.append(el('li', { class: 'vs-mod vs-mod--todo' }, [
        el('span', { class: 'vs-mod__dot' }),
        el('span', { class: 'grow', text: t('v.certification') }),
        el('small', { text: c.completed_at
          ? (c.cert_no ? `${t('v.certIssued')} ${c.cert_no}` : t('v.certIssued'))
          : t('v.certLocked') })]));
      body.append(list);
      if (!c.enrollment_id) body.append(el('p', { class: 'muted', text: t('v.learnNotEnrolled') }));
    }
    body.append(el('a', { href: '#/my/learning', class: 'btn btn--primary vs-cta',
      text: t('v.continueLearning') }));
    return cardShell('book', t('v.myLearning'), '#/my/learning', body);
  }

  function tasksCard() {
    const rows = h.tasks || [];
    const body = el('div');
    if (!rows.length) body.append(el('p', { class: 'muted', text: t('v.tasksNone') }));
    else {
      const tbl = el('table', { class: 'vs-table' }, [
        el('thead', {}, [el('tr', {}, [
          el('th', { text: t('v.thTask') }), el('th', { text: t('v.thDue') }),
          el('th', { text: t('v.thStatus') })])]),
        el('tbody', {}, rows.slice(0, 5).map((r) => el('tr', {
          onclick: () => { location.hash = '#/tasks'; } }, [
          el('td', { text: r.title }),
          el('td', { text: r.due_on ? fmtDate(r.due_on) : '\u2014' }),
          el('td', {}, [taskBadge(r)])]))),
      ]);
      body.append(el('div', { class: 'table-wrap' }, [tbl]));
    }
    return cardShell('tasks', t('v.myTasks'), '#/tasks', body);
  }

  function taskBadge(r) {
    if (r.overdue) return el('span', { class: 'vs-badge vs-badge--red', text: t('v.overdue') });
    if (r.status === 'in_progress') return el('span', { class: 'vs-badge vs-badge--blue', text: t('v.inProgress') });
    if (r.status === 'awaiting_review') return el('span', { class: 'vs-badge vs-badge--violet', text: t('v.awaitingReview') });
    return el('span', { class: 'vs-badge vs-badge--amber', text: t('v.pending') });
  }

  function networkCard() {
    const body = el('div', { class: 'vs-net' });
    body.append(chainNode());
    body.append(coordinatorNode());
    return cardShell('sitemap', t('v.myNetwork'), '#/my/network', body,
      P.network === 'WNNN' ? 'vs-card--wnnn' : 'vs-card--wgmn');
  }

  function chainNode() {
    const steps = [networkName(P.network), 'Africa'];
    const chain = h.chain || [];
    if (chain.length) {
      for (const c of chain) if (c.level !== 'headquarters') steps.push(c.name);
    } else {
      for (const v of [P.country, P.state_region, P.lga]) if (v) steps.push(v);
    }
    steps.push(t('v.you'));
    return el('ol', { class: 'vs-chain' }, steps.map((s, i) =>
      el('li', { class: i === steps.length - 1 ? 'vs-chain__you' : '' }, [
        el('span', { class: 'vs-chain__dot' }), el('span', { text: s })])));
  }

  function coordinatorNode() {
    const c = h.coordinator;
    const box = el('div', { class: 'vs-coord' }, [el('b', { text: isLeader ? t('v.reportsTo') : t('v.myCoordinator') })]);
    if (!c) {
      box.append(el('p', { class: 'muted', text: t('v.coordNone') }));
      if (!ro) box.append(el('a', { href: '#/messages', class: 'btn btn--secondary',
        text: t('v.messageHq') }));
      return box;
    }
    box.append(el('div', { class: 'vs-coord__who' }, [
      avatarNode({ id: c.id, first_name: c.name.split(' ')[0], last_name: c.name.split(' ')[1] || '' }, 'vs-coord__ava'),
      el('div', {}, [el('b', { text: c.name }),
        el('div', { class: 'muted' }, [el('span', { text: t(`role.${c.role}`) + ' ' }), c.appointment_status ? apptBadge(c.appointment_status) : null]),
        el('div', { class: 'muted', text: c.unit })]),
    ]));
    if (!ro) box.append(el('a', { href: `#/messages?u=${c.id}`, class: 'btn btn--secondary',
      text: t('v.messageCoordinator') }));
    return box;
  }

  function meetingsCard() {
    const rows = h.meetings || [];
    const body = el('div');
    if (!rows.length) body.append(el('p', { class: 'muted', text: t('v.meetNone') }));
    for (const m of rows.slice(0, 3)) {
      const place = m.platform === 'woddi' || m.mode === 'virtual'
        ? t('v.online') : (m.location || t(`v.mode_${m.mode}`));
      body.append(el('div', { class: 'vs-meet' }, [
        el('div', { class: 'vs-meet__ic' }, [icon('calendar', 18)]),
        el('div', { class: 'grow' }, [
          el('b', { text: m.title }),
          el('div', { class: 'muted', text: `${fmtDateTime(m.starts_at)} \u00B7 ${place}` }),
          el('div', { class: 'muted', text: audienceLabel(m) }),
        ]),
        el('div', { class: 'vs-meet__btns' }, [
          el('a', { href: '#/meetings', class: 'btn btn--secondary', text: t('v.viewDetails') }),
          (!ro && m.platform === 'woddi' && String(m.location || '').startsWith('WODDI-'))
            ? el('a', { href: `#/room?r=${encodeURIComponent(m.location)}&m=${m.id}`,
              class: 'btn btn--primary', text: t('v.joinMeeting') }) : null,
        ]),
      ]));
    }
    return cardShell('calendar', t('v.upcomingMeetings'), '#/meetings', body);
  }

  function audienceLabel(m) {
    const a = m.audience || 'unit';
    if (a === 'all') return t('v.audAll');
    if (a === 'hq') return t('v.audHq');
    if (a.startsWith('wgmn') || a.startsWith('wnnn')) {
      const net = a.slice(0, 4).toUpperCase();
      return a.endsWith('_ng') ? t('v.audNetNg', { net }) : t('v.audNetAll', { net });
    }
    return m.unit ? t('v.audUnit', { unit: m.unit }) : '';
  }

  function announcementsCard() {
    const rows = h.announcements || [];
    const body = el('div');
    if (!rows.length) body.append(el('p', { class: 'muted', text: t('v.annNone') }));
    for (const a of rows.slice(0, 4)) {
      body.append(el('a', { href: '#/announcements', class: 'vs-ann' }, [
        el('span', { class: `vs-ann__dot${a.read ? '' : ' vs-ann__dot--new'}` }),
        el('span', { class: 'grow', text: a.title }),
        el('small', { class: 'muted', text: fmtDate(a.created_at) }),
      ]));
    }
    return cardShell('megaphone', t('v.latestAnnouncements'), '#/announcements', body);
  }

  function leadershipCard() {
    const L = h.leadership;
    const seat = h.roles[0];
    const body = el('div');
    body.append(el('p', { class: 'muted', text: t('v.leadScope',
      { role: t(`role.${seat.role}`), unit: seat.unit }) }));
    body.append(el('div', { class: 'vs-mini' }, [
      mini(t('v.seats'), L.seats), mini(t('v.filled'), L.filled, 'green'),
      mini(t('v.vacant'), L.vacant, L.vacant > 0 ? 'red' : 'green'),
      mini(t('v.membersInScope'), L.members), mini(t('v.activeMembers'), L.members_active, 'green'),
    ]));
    body.append(el('a', { href: '#/my/leadership', class: 'btn btn--primary vs-cta',
      text: t('v.openLeadership') }));
    return cardShell('shield', t('v.myLeadership'), '#/my/leadership', body);
  }

  function impactCard() {
    const im = h.impact || {};
    const body = el('div', { class: 'vs-impact' }, [
      tileI('users', im.women_reached, t('v.womenReached'), 'pink'),
      tileI('userplus', im.referrals, t('v.communityReferrals'), 'green'),
      tileI('calendar', im.meetings_attended, t('v.meetingsAttended'), 'amber'),
      tileI('check', im.tasks_completed, t('v.tasksCompleted'), 'lime'),
      tileI('chart', im.months_of_service, t('v.monthsOfService'), 'gold'),
    ]);
    return cardShell('chart', t('v.myImpact'), '#/my/impact', body);
  }

  function quickActions() {
    const body = el('div', { class: 'vs-quick' }, [
      qa('#/my/referrals', 'userplus', t('v.qaReferral')),
      qa('#/my/documents', 'folder', t('v.qaDocuments')),
      qa('#/my/calendar', 'calendar', t('v.qaCalendar')),
      qa('#/my/safeguarding', 'shield', t('v.qaSafeguarding'), 'danger'),
      qa('#/my/support', 'support', t('v.qaSupport')),
      qa('#/ask', 'book', t('v.qaHelpCentre')),
    ]);
    return cardShell('tasks', t('v.quickActions'), null, body);
  }

  function qa(href, ic, label, cls = '') {
    return el('a', { href, class: `vs-qa ${cls ? 'vs-qa--' + cls : ''}` },
      [icon(ic, 18), el('span', { text: label })]);
  }

  function achievementsCard() {
    const rows = h.achievements || [];
    const body = el('div');
    if (!rows.length) body.append(el('p', { class: 'muted', text: t('v.achNone') }));
    for (const a of rows.slice(0, 5)) {
      body.append(el('div', { class: 'vs-ach' }, [
        el('span', { class: 'vs-ach__star', text: a.code === 'module' ? '\u2714' : '\u2605' }),
        el('span', { class: 'grow', text: achLabel(a) }),
        el('small', { class: 'muted', text: a.at ? fmtDate(a.at) : '' }),
      ]));
    }
    return cardShell('chart', t('v.myAchievements'), null, body);
  }

  function achLabel(a) {
    if (a.code === 'orientation') return t('v.achOrientation');
    if (a.code === 'module') return t('v.achModule', { title: a.title });
    if (a.code === 'certificate') return t('v.achCertificate', { title: a.title });
    if (a.code === 'appointed') return t('v.achAppointed', { role: t(`role.${a.title}`), unit: a.unit || '' });
    if (a.code && a.code.startsWith('service_')) return t('v.achService', { n: a.code.split('_')[1] });
    return a.title || a.code;
  }

  function acceptanceCard(pending) {
    const seat = pending[0];
    const reason = el('textarea', { class: 'input', rows: '2', placeholder: t('v.declineReasonPh'), hidden: true });
    const card = el('div', { class: 'vs-card vs-card--danger' }, [
      el('h3', { text: t('v.acceptTitle', { role: t(`role.${seat.role}`), unit: seat.unit }) }),
      el('p', { text: t('v.acceptDeclaration') }),
      reason,
      el('div', { class: 'row', style: 'gap:8px;flex-wrap:wrap;' }, [
        el('button', { class: 'btn btn--primary', text: t('v.acceptBtn'), onclick: async (e) => {
          e.target.disabled = true;
          try { await acceptAppointment(); toast(t('v.accepted')); invalidateHome(); h = await getHome(true); await home(); }
          catch (err) { toastError(err?.message || t('errors.save')); e.target.disabled = false; }
        } }),
        el('button', { class: 'btn btn--quiet', text: t('v.declineBtn'), onclick: async (e) => {
          if (reason.hidden) { reason.hidden = false; reason.focus(); return; }
          if (reason.value.trim().length < 3) { toastError(t('v.declineNeedReason')); return; }
          if (!confirm(t('v.declineConfirm'))) return;
          e.target.disabled = true;
          try { await declineAppointment(reason.value.trim()); toast(t('v.declined')); invalidateHome(); location.reload(); }
          catch (err) { toastError(err?.message || t('errors.save')); e.target.disabled = false; }
        } }),
      ]),
    ]);
    return card;
  }

  async function onboardingCard() {
    let st;
    try { st = await onboardingStatus(ro ? P.id : null); } catch { return el('div'); }
    if (!st) return el('div');
    const done = Number(st.done || 0), total = Number(st.total || 0);
    const pct = total ? Math.round((done / total) * 100) : 0;
    const list = el('ul', { class: 'vs-modules' });
    for (const s of (st.steps || [])) {
      const cb = el('input', { type: 'checkbox', checked: !!s.done_at, disabled: ro || null });
      cb.addEventListener('change', async () => {
        try { await setOnboardingStep(s.code, cb.checked); invalidateHome(); const n = await onboardingStatus(); bar.firstChild.style.width = `${n.total ? Math.round((n.done / n.total) * 100) : 0}%`; pctB.textContent = `${n.done}/${n.total}`; }
        catch (err) { cb.checked = !cb.checked; toastError(err?.message || t('errors.save')); }
      });
      list.append(el('li', { class: `vs-mod vs-mod--${s.done_at ? 'done' : 'todo'}` }, [
        cb, el('span', { class: 'grow' }, [el('span', { text: s.title }), s.detail ? el('div', { class: 'muted', text: s.detail }) : null]),
        s.href ? el('a', { href: s.href, class: 'btn btn--quiet', text: t('v.open'), target: s.href.startsWith('/') ? '_blank' : null }) : null,
        s.done_at ? el('small', { class: 'muted', text: fmtDate(s.done_at) }) : null]));
    }
    const bar = el('div', { class: 'vs-bar grow' }, [el('span', { style: `width:${pct}%` })]);
    const pctB = el('b', { text: `${done}/${total}` });
    return el('div', { class: 'vs-card' }, [
      el('h3', { text: done >= total && total ? t('v.onboardingDone') : t('v.onboardingTitle') }),
      el('div', { class: 'row', style: 'gap:10px;' }, [bar, pctB]),
      el('p', { class: 'muted', text: t('v.onboardingHint') }),
      list]);
  }

  function footerLine() {
    return el('footer', { class: 'vs-foot' }, [
      el('span', { text: t('v.footOrg') }),
      el('span', { text: t('v.footMotto') }),
    ]);
  }

  /* ================================================================== */
  /* PROFILE                                                            */
  /* ================================================================== */
  async function profileTab() {
    clear(out);
    const pct = Number(P.completion || 0);
    const head = el('div', { class: 'vs-card' }, [
      el('div', { class: 'row', style: 'gap:16px;' }, [
        avatarNode(P, 'vs-welcome__ava'),
        el('div', { class: 'grow' }, [
          el('h2', { text: `${P.first_name} ${P.last_name}` }),
          el('div', { class: 'muted', text: `${P.membership_no || t('v.idPending')} \u00B7 ${networkName(P.network)}` }),
          statusBadge(P.status, P.is_leader),
        ]),
        el('div', { style: 'min-width:180px;' }, [
          el('div', { class: 'muted', text: t('v.profileCompletion', { pct }) }),
          el('div', { class: 'vs-bar' }, [el('span', { style: `width:${pct}%` })]),
          pct < 100 ? el('small', { class: 'muted', text: t('v.completeProfile') }) : null,
        ]),
      ]),
    ]);
    if (!ro) {
      const file = el('input', { type: 'file', accept: 'image/*', hidden: true });
      file.addEventListener('change', async () => {
        const f = file.files && file.files[0]; if (!f) return;
        try { await uploadAvatar(P.id, f); toast(t('v.photoSaved')); invalidateHome(); location.reload(); }
        catch { toastError(t('errors.save')); }
      });
      head.append(el('div', { class: 'row', style: 'margin-top:10px;' }, [
        el('button', { class: 'btn btn--secondary', text: t('v.changePhoto'), onclick: () => file.click() }), file]));
    }
    out.append(head);

    const f = fields();
    const form = el('div', { class: 'vs-card' }, [
      el('h3', { text: t('v.profileDetails') }),
      el('div', { class: 'form-grid' }, [
        field(t('v.firstName'), f.first), field(t('v.lastName'), f.last),
        field(t('v.email'), f.email), field(t('v.phone'), f.phone),
        field(t('v.country'), f.country), field(t('v.state'), f.state),
        field(t('v.lga'), f.lga), field(t('v.roleApplied'), f.role),
        field(t('v.birthDate'), f.birth), field(t('v.preferredLanguage'), f.locale),
      ]),
      el('div', { class: 'form-grid' }, [
        readonlyField(t('v.volunteerId'), P.membership_no || t('v.idPending')),
        readonlyField(t('v.network'), networkName(P.network)),
        readonlyField(t('v.dateJoined'), fmtDate(P.joined_at)),
        readonlyField(t('v.sMyStatus'), t(`status.${P.status}`)),
      ]),
    ]);
    if (!ro) {
      form.append(el('div', { class: 'row' }, [el('span', { class: 'grow' }),
        el('button', { class: 'btn btn--primary', text: t('v.saveProfile'), onclick: async (e) => {
          e.target.disabled = true;
          try {
            await updateMyProfile({
              first_name: f.first.value.trim() || P.first_name,
              last_name: f.last.value.trim() || P.last_name,
              phone: f.phone.value.trim() || null,
              country: f.country.value || null,
              state_region: f.state.value.trim() || null,
              lga: f.lga.value.trim() || null,
              role_applied: f.role.value.trim() || null,
              birth_date: f.birth.value || null,
              preferred_locale: f.locale.value,
            });
            toast(t('v.profileSaved')); invalidateHome();
          } catch (err) { toastError(err?.message || t('errors.save')); }
          e.target.disabled = false;
        } })]));
    } else {
      for (const k of Object.keys(f)) f[k].disabled = true;
    }
    out.append(form);
  }

  function fields() {
    const sel = (opts, cur) => el('select', { class: 'select' },
      [el('option', { value: '', text: '\u2014' }), ...opts.map((o) =>
        el('option', { value: o, text: o, selected: o === cur || null }))]);
    const states = (P.country === 'Nigeria' || !P.country) ? NG_STATES : [];
    return {
      first: el('input', { class: 'input', value: P.first_name || '' }),
      last: el('input', { class: 'input', value: P.last_name || '' }),
      email: el('input', { class: 'input', value: P.email || '', disabled: true }),
      phone: el('input', { class: 'input', value: P.phone || '', type: 'tel' }),
      country: sel(AFRICAN_COUNTRIES, P.country),
      state: states.length && (!P.state_region || states.includes(P.state_region))
        ? sel(states, P.state_region) : el('input', { class: 'input', value: P.state_region || '' }),
      lga: el('input', { class: 'input', value: P.lga || '' }),
      role: el('input', { class: 'input', value: P.role_applied || '' }),
      birth: el('input', { class: 'input', type: 'date', value: P.birth_date || '' }),
      locale: el('select', { class: 'select' }, supportedLocales().map((c) =>
        el('option', { value: c, text: LOCALE_NAMES[c] || c, selected: c === P.preferred_locale || null }))),
    };
  }

  /* ================================================================== */
  /* NETWORK                                                            */
  /* ================================================================== */
  async function network() {
    clear(out);
    out.append(el('div', { class: 'vs-card' }, [
      el('h3', { text: t('v.whereISit') }),
      el('p', { class: 'muted', text: t('v.whereHint') }),
      chainNode(),
    ]));
    out.append(el('div', { class: 'vs-card' }, [coordinatorNode()]));
    if ((h.roles || []).length) {
      out.append(el('div', { class: 'vs-card' }, [
        el('h3', { text: t('v.mySeats') }),
        ...h.roles.map((r) => el('div', { class: 'vs-seat' }, [
          el('b', { text: t(`role.${r.role}`) }),
          el('span', { class: 'muted', text: `${term(r.level)} \u00B7 ${r.unit} \u00B7 ${t('v.since')} ${fmtDate(r.since)}` }),
        ])),
        el('a', { href: '#/my/leadership', class: 'btn btn--primary vs-cta', text: t('v.openLeadership') }),
      ]));
    }
  }

  /* ================================================================== */
  /* LEADERSHIP (leaders only)                                          */
  /* ================================================================== */
  async function leadership() {
    clear(out);
    if (!isLeader || !h.leadership) {
      out.append(el('div', { class: 'vs-card' }, [
        el('h3', { text: t('v.myLeadership') }),
        el('p', { class: 'muted', text: t('v.leadNotLeader') })]));
      return;
    }
    const L = h.leadership;
    const seat = h.roles[0];
    out.append(el('div', { class: 'vs-card' }, [
      el('h3', { text: t('v.leadHeading', { role: t(`role.${seat.role}`), unit: seat.unit }) }),
      el('div', { class: 'vs-mini' }, [
        mini(t('v.seats'), L.seats), mini(t('v.filled'), L.filled, 'green'),
        mini(t('v.vacant'), L.vacant, L.vacant > 0 ? 'red' : 'green'),
        mini(t('v.membersInScope'), L.members), mini(t('v.activeMembers'), L.members_active, 'green'),
      ]),
      el('p', { class: 'muted', text: t('v.leadLegend') }),
    ]));

    out.append(await onboardingCard());
    const dr = h.direct_reports || [];
    out.append(el('div', { class: 'vs-card' }, [
      el('h3', { text: t('v.directReports', { n: dr.length }) }),
      dr.length ? el('div', {}, dr.map((d) => el('div', { class: 'vs-tree__row vs-tree__row--green' }, [
        el('span', { class: 'vs-tree__dot' }),
        el('div', { class: 'grow' }, [el('b', { text: d.name }),
          el('div', { class: 'muted' }, [el('span', { text: `${t(`role.${d.role}`)} \u00B7 ${d.unit} ` }), apptBadge(d.appointment_status)])]),
        !ro ? el('a', { href: `#/messages?u=${d.id}`, class: 'btn btn--secondary', text: t('v.message') }) : null,
      ]))) : el('p', { class: 'muted', text: t('v.directReportsNone') }),
    ]));

    // hierarchy tree: seat unit → children, from the flat node list
    const nodes = L.nodes || [];
    const byParent = new Map();
    for (const n of nodes) {
      const k = n.parent_id || 'root';
      if (!byParent.has(k)) byParent.set(k, []);
      byParent.get(k).push(n);
    }
    const nodeIds = new Set(nodes.map((n) => n.org_unit_id));
    const roots = nodes.filter((n) => !nodeIds.has(n.parent_id));
    const tree = el('div', { class: 'vs-tree' });
    const draw = (list, depth) => {
      for (const n of list) {
        const st = n.vacant ? 'red' : (staleSeen(n.last_seen) ? 'amber' : 'green');
        const row = el('div', { class: `vs-tree__row vs-tree__row--${st}`,
          style: `padding-left:${12 + depth * 22}px` }, [
          el('span', { class: 'vs-tree__dot' }),
          el('div', { class: 'grow' }, [
            el('b', { text: n.location }),
            el('span', { class: 'muted', text: ` \u00B7 ${term(n.level)}` }),
            el('div', { class: 'muted' }, n.vacant ? [el('span', { text: t('v.seatVacant') })] : [
              el('span', { text: `${n.holder_name} \u00B7 ${t(`role.${n.role}`)} ` }),
              apptBadge(n.appointment_status),
              el('span', { text: n.last_seen ? ` \u00B7 ${t('v.lastSeen')} ${fmtDate(n.last_seen)}` : ` \u00B7 ${t('v.neverSignedIn')}` })]),
          ]),
          (!ro && !n.vacant && n.holder_id) ? el('a', { href: `#/messages?u=${n.holder_id}`,
            class: 'btn btn--secondary', text: t('v.message') }) : null,
          (!ro && n.vacant && ctx.modules?.has('recruitment')) ? el('a', { href: '#/recruitment',
            class: 'btn btn--quiet', text: t('v.referCandidate') }) : null,
        ]);
        tree.append(row);
        draw(byParent.get(n.org_unit_id) || [], depth + 1);
      }
    };
    draw(roots, 0);
    if (!nodes.length) tree.append(el('p', { class: 'muted', text: t('v.leadNoUnits') }));
    if (L.nodes_total > nodes.length) tree.append(el('p', { class: 'muted',
      text: t('v.leadTruncated', { shown: nodes.length, total: L.nodes_total }) }));
    out.append(el('div', { class: 'vs-card' }, [el('h3', { text: t('v.leadStructure') }), tree]));

    out.append(el('div', { class: 'vs-card' }, [
      el('h3', { text: t('v.leadTools') }),
      el('div', { class: 'vs-quick' }, [
        qa('#/tasks', 'tasks', t('v.navTasks')),
        qa('#/meetings', 'calendar', t('v.navMeetings')),
        qa('#/announcements', 'megaphone', t('v.navAnnounce')),
        ctx.modules?.has('recruitment') ? qa('#/recruitment', 'userplus', t('v.navVacancies')) : null,
        ctx.modules?.has('reports') ? qa('#/reports', 'chart', t('v.navReports')) : null,
        qa('#/me', 'home', t('v.phoneView')),
      ]),
      el('p', { class: 'muted', text: t('v.leadGovernance') }),
    ]));
  }

  function staleSeen(iso) {
    if (!iso) return true;
    return (Date.now() - new Date(iso).getTime()) > 30 * 86400000;
  }

  /* ================================================================== */
  /* LEARNING                                                           */
  /* ================================================================== */
  async function learning() {
    clear(out);
    const L = learningSummary();
    out.append(el('div', { class: 'vs-card' }, [
      el('h3', { text: P.network === 'WNNN' ? t('v.learnProgWnnn') : t('v.learnProgWgmn') }),
      el('div', { class: 'row', style: 'gap:10px;' }, [
        el('div', { class: 'vs-bar grow' }, [el('span', { style: `width:${L.percent}%` })]),
        el('b', { text: `${L.percent}%` })]),
      el('p', { class: 'muted', text: t('v.learnOverall', { p: L.passed, n: L.total }) }),
      el('p', { class: 'muted', text: t('v.learnInstitute') }),
    ]));
    const box = el('div');
    out.append(box);
    if (ro) {
      for (const c of L.courses) {
        box.append(el('div', { class: 'vs-card' }, [
          el('b', { text: c.title }),
          el('div', { class: 'muted', text: c.enrollment_id
            ? t('v.learnOverall', { p: c.modules_passed, n: c.modules_total })
            : t('v.learnNotEnrolled') }),
          ...(c.modules || []).map((m) => el('div', { class: 'muted',
            text: `${t('v.module')} ${m.seq} \u2013 ${m.title}: ${t(m.passed ? 'v.modCompleted' : 'v.modNotStarted')}` })),
        ]));
      }
      return;
    }
    try { await renderCourses(box, ctx.profile, () => invalidateHome()); }
    catch { box.append(el('p', { class: 'muted', text: t('errors.loadHint') })); }
  }

  /* ================================================================== */
  /* IMPACT                                                             */
  /* ================================================================== */
  async function impact() {
    clear(out);
    const im = h.impact || {};
    out.append(el('div', { class: 'vs-card' }, [
      el('h3', { text: t('v.myImpact') }),
      el('p', { class: 'muted', text: t('v.impactHint') }),
      el('div', { class: 'vs-impact vs-impact--wide' }, [
        tileI('users', im.women_reached, t('v.womenReached'), 'pink'),
        tileI('userplus', im.referrals, t('v.communityReferrals'), 'green'),
        tileI('calendar', im.meetings_attended, t('v.meetingsAttended'), 'amber'),
        tileI('check', im.tasks_completed, t('v.tasksCompleted'), 'lime'),
        tileI('book', im.modules_completed, t('v.modulesCompleted'), 'violet'),
        tileI('chart', im.months_of_service, t('v.monthsOfService'), 'gold'),
      ]),
      el('p', { class: 'muted', text: t('v.serviceSince', { d: fmtDate(im.service_since) }) }),
    ]));
    out.append(achievementsCard());
    out.append(el('div', { class: 'vs-card' }, [
      el('h3', { text: t('v.impactHow') }),
      el('ul', { class: 'vs-list' }, [
        el('li', { text: t('v.impactHow1') }), el('li', { text: t('v.impactHow2') }),
        el('li', { text: t('v.impactHow3') }), el('li', { text: t('v.impactHow4') }),
      ]),
    ]));
  }

  /* ================================================================== */
  /* REFERRALS                                                          */
  /* ================================================================== */
  async function referrals() {
    clear(out);
    const list = el('div');
    const drawList = () => {
      clear(list);
      const rows = h.referrals || [];
      if (!rows.length) { list.append(el('p', { class: 'muted', text: t('v.refNone') })); return; }
      for (const r of rows) list.append(referralRow(r));
    };
    out.append(el('div', { class: 'vs-card' }, [
      el('div', { class: 'row' }, [
        el('h3', { class: 'grow', text: t('v.myReferrals') }),
        !ro ? el('button', { class: 'btn btn--primary', text: t('v.newReferral'),
          onclick: () => referralModal(async () => { h = await getHome(true); drawList(); }) }) : null,
      ]),
      el('p', { class: 'muted', text: t('v.refHint') }),
      list,
    ]));
    drawList();
  }

  function referralRow(r) {
    const idx = REFERRAL_LADDER.indexOf(r.status);
    return el('div', { class: 'vs-ref' }, [
      el('div', { class: 'row' }, [
        el('b', { text: `${r.ref_no || ''} \u00B7 ${t('v.refCat_' + r.category)}` }),
        el('span', { class: 'grow' }),
        el('small', { class: 'muted', text: fmtDate(r.created_at) })]),
      el('div', { text: r.reason }),
      el('ol', { class: 'vs-ladder' }, REFERRAL_LADDER.map((s, i) =>
        el('li', { class: i < idx ? 'done' : (i === idx ? 'now' : ''), text: t('v.refSt_' + s) }))),
    ]);
  }

  function referralModal(onDone) {
    const cat = el('select', { class: 'select' }, REFERRAL_CATS.map((c) =>
      el('option', { value: c, text: t('v.refCat_' + c) })));
    const country = el('input', { class: 'input', value: P.country || '' });
    const state = el('input', { class: 'input', value: P.state_region || '' });
    const lga = el('input', { class: 'input', value: P.lga || '' });
    const community = el('input', { class: 'input' });
    const reason = el('input', { class: 'input', maxlength: '300' });
    const details = el('textarea', { class: 'input', rows: '4', maxlength: '3000' });
    const consent = el('input', { type: 'checkbox' });
    const err = el('p', { class: 'field__error', role: 'alert', hidden: true });
    const send = el('button', { class: 'btn btn--primary', text: t('v.submitReferral') });
    send.addEventListener('click', async () => {
      if (reason.value.trim().length < 3) { err.textContent = t('v.refNeedReason'); err.hidden = false; return; }
      if (!consent.checked) { err.textContent = t('v.refNeedConsent'); err.hidden = false; return; }
      err.hidden = true; send.disabled = true;
      try {
        const r = await submitReferral({
          category: cat.value, country: country.value.trim() || null,
          state_region: state.value.trim() || null, lga: lga.value.trim() || null,
          community: community.value.trim() || null, reason: reason.value.trim(),
          details: details.value.trim() || null,
        });
        closeModal(); toast(t('v.refSubmitted', { no: r.ref_no })); invalidateHome();
        if (onDone) await onDone();
      } catch (e) { err.textContent = e?.message || t('errors.save'); err.hidden = false; send.disabled = false; }
    });
    openModal(t('v.newReferral'), el('div', {}, [
      el('p', { class: 'muted', text: t('v.refSafeguardingNote') }),
      field(t('v.refCategory'), cat),
      el('div', { class: 'form-grid' }, [field(t('v.country'), country), field(t('v.state'), state),
        field(t('v.lga'), lga), field(t('v.community'), community)]),
      field(t('v.refReason'), reason), field(t('v.refDetails'), details),
      el('label', { class: 'row', style: 'gap:8px;margin:6px 0 12px;' }, [consent, el('span', { text: t('v.refConsent') })]),
      err, el('div', { class: 'row' }, [el('span', { class: 'grow' }), send]),
    ]));
  }

  /* ================================================================== */
  /* DOCUMENTS                                                          */
  /* ================================================================== */
  async function documents() {
    clear(out);
    out.append(el('div', { class: 'vs-card' }, [
      el('h3', { text: t('v.myDocuments') }),
      el('p', { class: 'muted', text: t('v.docsHint') }),
      ...STATIC_DOCS.map((d) => docRow(t(d.key), d.href, d.kind)),
    ]));
    const rows = h.documents || [];
    out.append(el('div', { class: 'vs-card' }, [
      el('h3', { text: t('v.sharedDocs') }),
      rows.length ? el('div', {}, rows.map((d) => docRow(`${d.folder} \u00B7 ${d.name}`,
        documentUrl(d.path), 'file', fmtDate(d.created_at))))
        : el('p', { class: 'muted', text: t('v.docsNone') }),
      ctx.modules?.has('documents') ? el('a', { href: '#/documents', class: 'btn btn--secondary vs-cta',
        text: t('v.openLibrary') }) : null,
    ]));
    const certs = (h.learning || []).filter((c) => c.cert_no);
    if (certs.length) out.append(el('div', { class: 'vs-card' }, [
      el('h3', { text: t('v.myCertificates') }),
      ...certs.map((c) => el('div', { class: 'vs-doc' }, [icon('check', 18),
        el('span', { class: 'grow', text: `${c.title} \u00B7 ${c.cert_no}` }),
        el('a', { href: '#/my/learning', class: 'btn btn--quiet', text: t('v.view') })])),
    ]));
  }

  function docRow(name, href, kind, when) {
    return el('div', { class: 'vs-doc' }, [
      icon(kind === 'pdf' ? 'file' : 'folder', 18),
      el('span', { class: 'grow', text: name }),
      when ? el('small', { class: 'muted', text: when }) : null,
      el('a', { href, target: '_blank', rel: 'noopener', class: 'btn btn--quiet', text: t('v.view') }),
    ]);
  }

  /* ================================================================== */
  /* TEMPLATES & TOOLS (founder's operational templates)                */
  /* ================================================================== */
  async function templates() {
    clear(out);
    let list = [];
    try { list = await (await fetch('/content/templates/index.json', { cache: 'no-cache' })).json(); }
    catch { list = []; }
    const card = el('div', { class: 'vs-card' }, [el('h3', { text: t('v.navTemplates') }),
      el('p', { class: 'muted', text: t('v.templatesHint') })]);
    if (!list.length) card.append(el('p', { class: 'muted', text: t('v.docsNone') }));
    for (const d of list) {
      card.append(el('div', { class: 'vs-doc' }, [
        icon('file', 18),
        el('div', { class: 'grow' }, [el('b', { text: d.title }), el('div', { class: 'muted', text: d.kind })]),
        d.pdf ? el('a', { href: `/content/templates/${d.pdf}`, target: '_blank', rel: 'noopener', class: 'btn btn--secondary', text: t('v.read') }) : null,
        el('a', { href: `/content/templates/${d.file}`, download: d.file, class: 'btn btn--quiet', text: t('v.download') }),
      ]));
    }
    out.append(card);
  }

  /* ================================================================== */
  /* REFERRAL LINKS (leaders)                                            */
  /* ================================================================== */
  async function reflinks() {
    clear(out);
    if (!isLeader) { out.append(el('div', { class: 'vs-card' }, [el('h3', { text: t('nav.reflinks') }), el('p', { class: 'muted', text: t('v.leadNotLeader') })])); return; }
    const { renderReferralPanel } = await import('./reflinks.js');
    await renderReferralPanel(out, { hq: false, profile: P, net: P.network });
  }

  /* ================================================================== */
  /* CALENDAR                                                           */
  /* ================================================================== */
  async function calendar() {
    clear(out);
    const items = [];
    for (const m of (h.meetings || [])) items.push({ at: m.starts_at, kind: 'meeting', title: m.title, href: '#/meetings' });
    for (const tk of (h.tasks || [])) if (tk.due_on) items.push({ at: tk.due_on, kind: 'task', title: tk.title, href: '#/tasks' });
    if (h.journey && h.journey.status === 'in_progress') {
      items.push({ at: h.journey.extended_until || h.journey.due_at, kind: 'journey', title: t('v.journeyDeadline'), href: '#/me/journey' });
    }
    items.sort((a, b) => new Date(a.at) - new Date(b.at));
    const byMonth = new Map();
    for (const it of items) {
      const d = new Date(it.at);
      const key = d.toLocaleDateString(getLocale(), { month: 'long', year: 'numeric' });
      if (!byMonth.has(key)) byMonth.set(key, []);
      byMonth.get(key).push(it);
    }
    const card = el('div', { class: 'vs-card' }, [el('h3', { text: t('v.myCalendar') }),
      el('p', { class: 'muted', text: t('v.calHint') })]);
    if (!items.length) card.append(el('p', { class: 'muted', text: t('v.calNone') }));
    for (const [month, list] of byMonth) {
      card.append(el('h4', { class: 'vs-cal__month', text: month.toUpperCase() }));
      for (const it of list) {
        const d = new Date(it.at);
        card.append(el('a', { href: it.href, class: `vs-cal vs-cal--${it.kind}` }, [
          el('b', { text: String(d.getDate()).padStart(2, '0') }),
          el('span', { class: 'grow', text: it.title }),
          el('small', { class: 'muted', text: t('v.cal_' + it.kind) }),
        ]));
      }
    }
    out.append(card);
  }

  /* ================================================================== */
  /* SUPPORT                                                            */
  /* ================================================================== */
  async function support() {
    clear(out);
    const tk = h.tickets || {};
    const listBox = el('div');
    const drawTickets = () => {
      clear(listBox);
      const rows = tk.recent || [];
      if (!rows.length) { listBox.append(el('p', { class: 'muted', text: t('v.ticketsNone') })); return; }
      for (const r of rows) listBox.append(el('div', { class: 'vs-ticket' }, [
        el('b', { text: r.ticket_no || '' }), el('span', { class: 'grow', text: r.subject }),
        el('span', { class: `vs-badge vs-badge--${['resolved', 'closed'].includes(r.status) ? 'green' : 'blue'}`,
          text: t('ticketstatus.' + r.status) })]));
    };
    out.append(el('div', { class: 'vs-card' }, [
      el('h3', { text: t('v.needHelp') }),
      el('p', { class: 'muted', text: t('v.supportHint') }),
      el('div', { class: 'vs-quick' }, [
        !ro ? qaBtn('support', t('v.supTech'), () => ticketModal('technical', drawTickets)) : null,
        h.coordinator && !ro ? qa(`#/messages?u=${h.coordinator.id}`, 'users', t('v.supCoordinator')) : null,
        !ro ? qaBtn('book', t('v.supLearning'), () => ticketModal('training_access', drawTickets)) : null,
        qa('#/my/safeguarding', 'shield', t('v.supSafeguarding'), 'danger'),
        !ro ? qaBtn('clip', t('v.supProblem'), () => ticketModal('app_problem', drawTickets)) : null,
        qa('#/ask', 'support', t('v.supFaq')),
        qa('#/messages', 'users', t('v.messageHq')),
      ]),
    ]));
    out.append(el('div', { class: 'vs-card' }, [
      el('div', { class: 'row' }, [el('h3', { class: 'grow', text: t('v.myTickets') }),
        el('span', { class: 'muted', text: t('v.ticketCounts', { o: tk.open || 0, r: tk.resolved || 0 }) })]),
      listBox,
    ]));
    drawTickets();
  }

  function qaBtn(ic, label, onclick) {
    return el('button', { class: 'vs-qa', onclick }, [icon(ic, 18), el('span', { text: label })]);
  }

  function ticketModal(defaultCat, onDone) {
    const cat = el('select', { class: 'select' }, TICKET_CATS.map((c) =>
      el('option', { value: c, text: t('ticketcat.' + c), selected: c === defaultCat || null })));
    const subject = el('input', { class: 'input', maxlength: '160' });
    const details = el('textarea', { class: 'input', rows: '5', maxlength: '4000' });
    const err = el('p', { class: 'field__error', role: 'alert', hidden: true });
    const send = el('button', { class: 'btn btn--primary', text: t('v.sendRequest') });
    send.addEventListener('click', async () => {
      if (subject.value.trim().length < 3 || details.value.trim().length < 5) {
        err.textContent = t('v.ticketNeed'); err.hidden = false; return;
      }
      err.hidden = true; send.disabled = true;
      try {
        const r = await fileTicket({ category: cat.value, priority: 'medium',
          subject: subject.value.trim(), details: details.value.trim() });
        closeModal(); toast(t('v.ticketFiled', { no: r.ticket_no || '' }));
        invalidateHome(); h = await getHome(true); if (onDone) onDone();
      } catch (e) { err.textContent = e?.message || t('errors.save'); err.hidden = false; send.disabled = false; }
    });
    openModal(t('v.newTicket'), el('div', {}, [
      field(t('v.ticketCategory'), cat), field(t('v.ticketSubject'), subject),
      field(t('v.ticketDetails'), details), err,
      el('div', { class: 'row' }, [el('span', { class: 'grow' }), send]),
    ]));
  }

  /* ================================================================== */
  /* SAFEGUARDING                                                       */
  /* ================================================================== */
  async function safeguarding() {
    clear(out);
    const subject = el('input', { class: 'input', maxlength: '160' });
    const details = el('textarea', { class: 'input', rows: '6', maxlength: '8000' });
    const err = el('p', { class: 'field__error', role: 'alert', hidden: true });
    const done = el('div', { hidden: true });
    const send = el('button', { class: 'btn btn--primary', text: t('v.sgSubmit') });
    send.addEventListener('click', async () => {
      if (subject.value.trim().length < 3 || details.value.trim().length < 10) {
        err.textContent = t('v.sgNeed'); err.hidden = false; return;
      }
      err.hidden = true; send.disabled = true;
      try {
        const c = await fileCase({ category: 'safeguarding', org_unit_id: P.org_unit_id || null,
          subject: subject.value.trim(), details: details.value.trim() });
        subject.value = ''; details.value = '';
        done.hidden = false;
        done.replaceChildren(el('div', { class: 'vs-ok' }, [icon('check', 18),
          el('span', { text: t('v.sgFiled', { no: c.case_no || '' }) })]));
        toast(t('v.sgFiledToast'));
      } catch (e) { err.textContent = e?.message || t('errors.save'); err.hidden = false; }
      send.disabled = false;
    });
    out.append(el('div', { class: 'vs-card vs-card--danger' }, [
      el('h3', { text: t('v.sgTitle') }),
      el('p', { text: t('v.sgIntro') }),
      el('ul', { class: 'vs-list' }, [el('li', { text: t('v.sgPoint1') }),
        el('li', { text: t('v.sgPoint2') }), el('li', { text: t('v.sgPoint3') })]),
      ro ? el('p', { class: 'muted', text: t('v.sgReadOnly') }) : el('div', {}, [
        field(t('v.sgSubject'), subject), field(t('v.sgDetails'), details), err, done,
        el('div', { class: 'row' }, [el('span', { class: 'grow' }), send])]),
    ]));
  }

  /* ================================================================== */
  /* SETTINGS                                                           */
  /* ================================================================== */
  async function settings() {
    clear(out);
    const localeSel = el('select', { class: 'select' }, supportedLocales().map((c) =>
      el('option', { value: c, text: LOCALE_NAMES[c] || c, selected: c === getLocale() || null })));
    localeSel.addEventListener('change', async () => {
      try { await setLocale(localeSel.value); await updateMyProfile({ preferred_locale: localeSel.value }); location.reload(); }
      catch { toastError(t('errors.localeLoad')); }
    });
    const dark = document.documentElement.dataset.theme === 'dark';
    const theme = el('button', { class: 'btn btn--secondary', text: dark ? t('v.themeLight') : t('v.themeDark'),
      onclick: () => {
        const d = document.documentElement.dataset.theme !== 'dark';
        document.documentElement.dataset.theme = d ? 'dark' : '';
        localStorage.setItem('wdos.theme', d ? 'dark' : 'light');
        theme.textContent = d ? t('v.themeLight') : t('v.themeDark');
      } });
    out.append(el('div', { class: 'vs-card' }, [
      el('h3', { text: t('v.navSettings') }),
      el('div', { class: 'form-grid' }, [field(t('v.preferredLanguage'), localeSel),
        field(t('v.appearance'), theme)]),
      el('div', { class: 'row', style: 'gap:8px;' }, [
        el('button', { class: 'btn btn--secondary', text: t('bn.enableBtn'), onclick: async (e) => {
          const { enableBrowserNotifications } = await import('../core/notifybrowser.js');
          const st = await enableBrowserNotifications(ctx.profile);
          if (st === 'granted') {
            try { const { enablePush } = await import('../core/push.js'); await enablePush(); } catch { /* optional */ }
          }
          e.target.textContent = st === 'granted' ? t('bn.onShort') : t('bn.enableBtn');
        } }),
        el('a', { href: '#/me', class: 'btn btn--quiet', text: t('v.phoneView') }),
      ]),
    ]));
    if (ro) return;
    const pw1 = el('input', { class: 'input', type: 'password', autocomplete: 'new-password' });
    const pw2 = el('input', { class: 'input', type: 'password', autocomplete: 'new-password' });
    const pwErr = el('p', { class: 'field__error', role: 'alert', hidden: true });
    out.append(el('div', { class: 'vs-card' }, [
      el('h3', { text: t('acct.title') }), el('p', { class: 'muted', text: t('acct.hint') }),
      el('div', { class: 'form-grid' }, [field(t('acct.newPw'), pw1), field(t('acct.confirmPw'), pw2)]),
      pwErr,
      el('div', { class: 'row' }, [el('span', { class: 'grow' }),
        el('button', { class: 'btn btn--secondary', text: t('acct.change'), onclick: async (e) => {
          if (pw1.value.length < 8) { pwErr.textContent = t('acct.errShort'); pwErr.hidden = false; return; }
          if (pw1.value !== pw2.value) { pwErr.textContent = t('acct.errMatch'); pwErr.hidden = false; return; }
          pwErr.hidden = true; e.target.disabled = true;
          try { await changePassword(pw1.value); pw1.value = ''; pw2.value = ''; toast(t('acct.changed')); }
          catch (err) {
            pwErr.textContent = String(err?.message ?? '').includes('different from the old')
              ? t('acct.errSame') : t('errors.save');
            pwErr.hidden = false;
          } finally { e.target.disabled = false; }
        } })]),
    ]));
  }

  /* ================================================================== */
  /* small helpers                                                      */
  /* ================================================================== */
  function unitOf(level) {
    const c = (h.chain || []).find((x) => x.level === level);
    return c ? c.name : null;
  }
  function mini(label, value, tone = '') {
    return el('div', { class: `vs-mini__t ${tone ? 'vs-mini__t--' + tone : ''}` }, [
      el('b', { text: fmtNumber(value || 0) }), el('small', { text: label })]);
  }
  function tileI(ic, value, label, tone) {
    return el('div', { class: `vs-imp vs-imp--${tone}` }, [
      el('div', { class: 'vs-imp__ic' }, [icon(ic, 20)]),
      el('b', { text: fmtNumber(value || 0) }), el('small', { text: label })]);
  }
  function field(label, node) {
    return el('div', { class: 'field' }, [el('label', { class: 'field__label', text: label }), node]);
  }
  function readonlyField(label, value) {
    return field(label, el('input', { class: 'input', value: value || '', disabled: true }));
  }
}

export function flagNode(p, bundle, size = 22) {
  const iso = countryIso(p.country || (bundle?.chain || []).find((c) => c.level === 'country')?.name, bundle?.country_iso);
  const src = flagSrc(iso);
  if (!src) return null;
  return el('img', { class: 'vs-flag', src, alt: iso, title: p.country || iso, width: String(Math.round(size * 4 / 3)), height: String(size),
    onerror: (e) => { e.target.remove(); } });
}

function statusBadge(status, leader) {
  const good = ['active', 'activated', 'in_training', 'reinstated', 'approved'].includes(status);
  return el('span', { class: `vs-status ${good ? 'vs-status--ok' : 'vs-status--warn'}` }, [
    good ? icon('check', 12) : null,
    el('span', { text: leader ? t('v.activeLeader') : t(`v.st_${status}`) }),
  ]);
}

function avatarNode(p, cls) {
  const initials = ((p.first_name || '?')[0] + (p.last_name || '')[0]).toUpperCase();
  return el('img', { class: cls, alt: '',
    src: avatarUrl(p.id, Math.floor(Date.now() / 3600000)),
    onerror: (e) => { e.target.replaceWith(el('div', { class: cls, text: initials })); } });
}

function errorState(retry, err) {
  return el('div', { class: 'card state' }, [
    el('h3', { text: t('errors.loadTitle') }),
    el('p', { text: t('errors.loadHint') }),
    (String(err?.message || err?.code || '') ? el('p', { class: 'muted',
      style: 'font-size:12px;word-break:break-word;',
      text: String(err?.message || err?.code || '').slice(0, 200) }) : null),
    el('button', { class: 'btn btn--quiet', text: t('app.retry'), onclick: retry }),
  ]);
}
