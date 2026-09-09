/**
 * Phase 131 — the Volunteer Dashboard shell.
 *
 * One shell for every WGMN/WNNN member and volunteer leader: white header
 * (logo, WDOS title, notifications, messages, help, identity), navy sidebar
 * with the fifteen volunteer areas, canvas content. The menu is role-aware:
 * "My Leadership", "Leadership Vacancies" and "Reports" appear only for
 * people who hold a leadership seat / the module. HQ staff never see this
 * shell; they keep the central management dashboard.
 *
 * Every page that calls renderShell() gets this chrome automatically when
 * the signed-in person is not HQ (layout.js delegates here), so #/tasks,
 * #/meetings, #/announcements, #/messages look like the rest of the
 * volunteer experience without any page-level change.
 */
import { el, esc, clear } from '../core/dom.js';
import { t } from '../core/i18n.js';
import { signOut, avatarUrl, APP_VERSION, EXPECTED_SCHEMA_VERSION } from '../core/db.js';
import { getHome } from '../core/homecache.js';
import { countryIso, flagSrc } from '../core/geo.js';
import { icon } from './icons.js';
import { bellButton } from './notify.js';
import { toastError } from './toast.js';

const NETWORK_NAME = { WGMN: 'Good Mother Network', WNNN: 'Nurture NextGen Network' };

const MENU = [
  { hash: '#/',              key: 'v.navHome',        icon: 'home' },
  { hash: '#/my/profile',    key: 'v.navProfile',     icon: 'users' },
  { hash: '#/my/network',    key: 'v.navNetwork',     icon: 'sitemap' },
  { hash: '#/my/leadership', key: 'v.navLeadership',  icon: 'shield', leader: true },
  { hash: '#/structure',     key: 'nav.structure',    icon: 'sitemap', leader: true },
  { hash: '#/reporting',     key: 'nav.reporting',    icon: 'chart', leader: true },
  { hash: '#/my/learning',   key: 'v.navLearning',    icon: 'book' },
  { href: 'https://woddiinstitute.com', key: 'v.navInstitute', icon: 'book', external: true },
  { hash: '#/tasks',         key: 'v.navTasks',       icon: 'tasks', module: 'tasks' },
  { hash: '#/meetings',      key: 'v.navMeetings',    icon: 'calendar', module: 'meetings' },
  { hash: '#/room',          key: 'v.navRoom',        icon: 'support' },
  { hash: '#/announcements', key: 'v.navAnnounce',    icon: 'megaphone', module: 'announcements' },
  { hash: '#/my/impact',     key: 'v.navImpact',      icon: 'chart' },
  { hash: '#/my/referrals',  key: 'v.navReferrals',   icon: 'userplus' },
  { hash: '#/my/reflinks',   key: 'nav.reflinks',     icon: 'userplus', leader: true },
  { hash: '#/recruitment',   key: 'v.navVacancies',   icon: 'briefcase', module: 'recruitment' },
  { hash: '#/reports',       key: 'v.navReports',     icon: 'chart', module: 'reports' },
  { hash: '#/my/documents',  key: 'v.navDocuments',   icon: 'folder' },
  { hash: '#/my/templates',  key: 'v.navTemplates',   icon: 'file' },
  { hash: '#/my/calendar',   key: 'v.navCalendar',    icon: 'calendar' },
  { hash: '#/messages',      key: 'v.navMessages',    icon: 'users' },
  { hash: '#/my/support',    key: 'v.navSupport',     icon: 'support' },
  { hash: '#/my/safeguarding', key: 'v.navSafeguarding', icon: 'shield' },
  { hash: '#/my/settings',   key: 'v.navSettings',    icon: 'sliders' },
];

function isCurrent(hash) {
  const h = (location.hash || '#/').split('?')[0];
  return hash === '#/' ? h === '#/' : h.startsWith(hash);
}

/**
 * @param root      the #app node
 * @param opts      { profile, modules, titleKey, viewingAs?: {id,name} }
 * @returns         { outlet, teardown() }
 */
export function renderVolunteerShell(root, { profile, modules, titleKey, viewingAs }) {
  const allowed = modules ?? new Set();
  clear(root);

  /* ------------------------------------------------------------ sidebar */
  const side = el('aside', { class: 'vs-side', id: 'sidebar' });
  const brand = el('div', { class: 'vs-side__brand' });
  brand.innerHTML = `<img src="/assets/woddi-logo.png" alt="WODDI">`
    + `<em>${esc(t('app.subtitle'))}</em>`;
  const nav = el('nav', { class: 'vs-nav', 'aria-label': t('nav.label') });
  side.append(brand, nav);
  const quote = el('div', { class: 'vs-side__quote' });
  quote.innerHTML = `<span>${esc(t('v.sideQuote'))}</span><small>WODDI</small>`
    + `<div class="vs-side__ver">build v${esc(APP_VERSION)} · db ${esc(String(EXPECTED_SCHEMA_VERSION))}</div>`;
  side.append(quote);

  const drawMenu = (leader) => {
    clear(nav);
    for (const m of MENU) {
      if (m.module && !allowed.has(m.module)) continue;
      if (m.leader && !leader) continue;
      const a = el('a', { href: m.external ? m.href : m.hash, class: 'vs-nav__a',
        target: m.external ? '_blank' : null, rel: m.external ? 'noopener' : null },
        [icon(m.icon, 17), el('span', { text: t(m.key) })]);
      if (!m.external && isCurrent(m.hash)) a.setAttribute('aria-current', 'page');
      a.addEventListener('click', () => toggleSide(false));
      nav.append(a);
    }
    nav.append(el('button', { class: 'vs-nav__a vs-nav__out',
      onclick: async () => {
        try { await signOut(); location.hash = '#/login'; }
        catch { toastError(t('errors.signOut')); }
      } }, [icon('signout', 17), el('span', { text: t('v.navLogout') })]));
  };
  drawMenu(!!profile.is_leader);

  /* ------------------------------------------------------------ header */
  const ava = el('img', { class: 'vs-id__ava', alt: '',
    src: avatarUrl(profile.id, Math.floor(Date.now() / 3600000)),
    onerror: (e) => {
      const initials = ((profile.first_name || '?')[0]
        + (profile.last_name || '')[0]).toUpperCase();
      e.target.replaceWith(el('div', { class: 'vs-id__ava', text: initials }));
    } });
  const idName = el('b', { text: `${profile.first_name} ${profile.last_name}` });
  const idRole = el('small', { text: profile.role_applied || t('v.volunteer') });
  const idBtn = el('button', { class: 'vs-id', 'aria-haspopup': 'true',
    onclick: () => { menu.hidden = !menu.hidden; } },
    [ava, el('span', { class: 'vs-id__txt' }, [idName, idRole]),
      el('span', { class: 'vs-id__caret', text: '\u25BE' })]);
  const menu = el('div', { class: 'vs-menu', hidden: true }, [
    el('a', { href: '#/my/profile', text: t('v.navProfile') }),
    el('a', { href: '#/my/settings', text: t('v.navSettings') }),
    el('a', { href: '#/me', text: t('v.phoneView') }),
    el('button', { text: t('v.navLogout'), onclick: async () => {
      try { await signOut(); location.hash = '#/login'; }
      catch { toastError(t('errors.signOut')); }
    } }),
  ]);
  const onDoc = (e) => { if (!menu.contains(e.target) && !idBtn.contains(e.target)) menu.hidden = true; };
  document.addEventListener('click', onDoc);

  const msgCount = el('span', { class: 'vs-pill', hidden: true });
  const msgBtn = el('a', { href: '#/messages', class: 'vs-hbtn', title: t('v.navMessages') },
    [icon('users', 19), msgCount, el('span', { text: t('v.hMessages') })]);
  const helpBtn = el('a', { href: '#/my/support', class: 'vs-hbtn', title: t('v.navSupport') },
    [icon('support', 19), el('span', { text: t('v.hHelp') })]);
  const bell = bellButton(icon('bell', 19));
  bell.classList.add('vs-hbtn', 'vs-hbtn--bell');
  bell.append(el('span', { text: t('v.hNotifications') }));

  const header = el('header', { class: 'vs-head' }, [
    el('button', { class: 'vs-burger', 'aria-label': t('nav.openMenu'),
      onclick: () => toggleSide(true) }, [icon('menu', 22)]),
    el('div', { class: 'vs-head__title' }, [
      el('h1', { text: t('v.headTitle') }),
      el('p', { text: t('v.headTagline') }),
    ]),
    el('div', { class: 'vs-head__tools' }, [bell, msgBtn, helpBtn, idBtn, menu]),
  ]);

  /* ------------------------------------------------------------ body */
  const banner = viewingAs ? el('div', { class: 'vs-viewas' }, [
    icon('shield', 16),
    el('span', { text: t('v.viewingAs', { name: viewingAs.name }) }),
    el('a', { href: '#/accounts', class: 'btn btn--quiet', text: t('v.viewingBack') }),
  ]) : null;
  const offline = el('div', { class: 'offline-banner', hidden: navigator.onLine,
    text: t('app.offline') });
  const syncBanner = () => { offline.hidden = navigator.onLine; };
  window.addEventListener('online', syncBanner);
  window.addEventListener('offline', syncBanner);

  const outlet = el('div', { class: 'vs-content' });
  const main = el('div', { class: 'vs-main' }, [header, banner, offline, outlet]);
  const scrim = el('div', { class: 'scrim', hidden: true, onclick: () => toggleSide(false) });
  root.append(el('div', { class: 'vs-shell' }, [side, scrim, main]));
  document.title = `${t(titleKey)} · WDOS`;

  function toggleSide(open) {
    side.classList.toggle('open', open);
    scrim.hidden = !open;
  }

  /* counters and leader menu, from the cached dashboard bundle */
  getHome().then((h) => {
    if (!h) return;
    const unreadMsgs = Number(h.messages_unread || 0);
    msgCount.textContent = String(unreadMsgs);
    msgCount.hidden = unreadMsgs === 0;
    const leader = (h.roles || []).length > 0 || !!h.profile?.is_leader;
    if (leader !== !!profile.is_leader) drawMenu(leader);
    if ((h.roles || []).length) idRole.textContent = t(`role.${h.roles[0].role}`);
    else if (h.profile?.role_applied) idRole.textContent = h.profile.role_applied;
    const iso = countryIso(h.profile?.country || (h.chain || []).find((c) => c.level === 'country')?.name, h.country_iso);
    const src = flagSrc(iso);
    if (src && !idName.querySelector('.vs-flag')) {
      idName.append(el('img', { class: 'vs-flag vs-flag--sm', src, alt: iso, width: '20', height: '15', onerror: (e) => e.target.remove() }));
    }
  }).catch(() => { /* counters are cosmetic */ });

  return {
    outlet,
    teardown() {
      window.removeEventListener('online', syncBanner);
      window.removeEventListener('offline', syncBanner);
      document.removeEventListener('click', onDoc);
    },
  };
}

export function networkName(code) {
  return NETWORK_NAME[code] || code || '';
}
