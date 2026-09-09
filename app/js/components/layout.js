/**
 * Authenticated app shell: black sidebar, topbar, content outlet,
 * offline banner, language switcher. Pages render into the returned
 * outlet node.
 */
import { el, esc, clear } from '../core/dom.js';
import { t, getLocale, setLocale, supportedLocales } from '../core/i18n.js';
import { signOut, getSchemaStatus } from '../core/db.js';
import { APP_VERSION, EXPECTED_SCHEMA_VERSION } from '../core/db.js';
import { toastError } from './toast.js';
import { icon } from './icons.js';
import { bellButton } from './notify.js';
import { openSearch } from './search.js';
import { renderVolunteerShell } from './vshell.js';

/* Phase 131: 'hq' = this black sidebar; 'volunteer' = the Volunteer
   Dashboard shell. Set once per session by app.js after sign-in. */
let shellMode = 'hq';
export function setShellMode(mode) { shellMode = mode; }
export function getShellMode() { return shellMode; }

const NAV = [
  { hash: '#/',        key: 'nav.dashboard', module: null, icon: 'home' },
  { hash: '#/members', key: 'nav.members', module: 'members', icon: 'users' },
  { hash: '#/recruitment', key: 'nav.recruitment', module: 'recruitment', icon: 'userplus' },
  { hash: '#/organisation', key: 'nav.organisation', module: 'organisation', icon: 'sitemap' },
  { hash: '#/tasks', key: 'nav.tasks', module: 'tasks', icon: 'tasks' },
  { hash: '#/meetings', key: 'nav.meetings', module: 'meetings', icon: 'calendar' },
  { hash: '#/reports', key: 'nav.reports', module: 'reports', icon: 'chart' },
  { hash: '#/leadership', key: 'nav.leadership', module: 'hq', icon: 'shield' },
  { hash: '#/announcements', key: 'nav.announcements', module: 'announcements', icon: 'megaphone' },
  { hash: '#/messages', key: 'nav.messages', module: null, icon: 'users' },
  { hash: '#/room', key: 'nav.room', module: null, icon: 'calendar' },
  { hash: '#/ask', key: 'nav.ask', module: null, icon: 'support' },
  { hash: '#/feedback', key: 'nav.uat', module: null, icon: 'clip' },
  { hash: '#/doctor', key: 'nav.doctor', module: null, icon: 'clip' },
  { hash: '#/programmes', key: 'nav.programmes', module: 'programmes', icon: 'heart' },
  { hash: '#/cases', key: 'nav.cases', module: 'cases', icon: 'shield' },
  { hash: '#/helpdesk', key: 'nav.helpdesk', module: 'helpdesk', icon: 'support' },
  { hash: '#/documents', key: 'nav.documents', module: 'documents', icon: 'folder' },
  { hash: '#/library', key: 'nav.library', module: 'library', icon: 'book' },
  { hash: '#/command', key: 'nav.command', module: 'hq', icon: 'chart' },
  { hash: '#/hq', key: 'nav.hq', module: 'hq', icon: 'briefcase' },
  { hash: '#/leaders', key: 'nav.leaders', module: 'hq', icon: 'users' },
  { hash: '#/accounts', key: 'nav.accounts', module: 'hq', icon: 'shield' },
  { hash: '#/structure', key: 'nav.structure', module: 'hq', icon: 'sitemap' },
  { hash: '#/reporting', key: 'nav.reporting', module: 'hq', icon: 'chart' },
  { hash: '#/reflinks', key: 'nav.reflinks', module: 'hq', icon: 'userplus' },
  { hash: '#/spotlight-review', key: 'nav.spotlightReview', module: 'hq', icon: 'chart' },
  { hash: '#/outreach', key: 'nav.outreach', module: 'hq', icon: 'megaphone' },
  { hash: '#/content', key: 'nav.content', module: 'content', icon: 'book' },
  { hash: '#/settings', key: 'nav.settings', module: 'settings', icon: 'sliders' },
];

const LOCALE_NAMES = {
  en: 'English', fr: 'Français', pt: 'Português', ar: 'العربية',
  sw: 'Kiswahili', ha: 'Hausa', yo: 'Yorùbá', ig: 'Igbo',
};

export function renderShell(root, { profile, titleKey, modules }) {
  if (shellMode === 'volunteer') {
    return renderVolunteerShell(root, { profile, titleKey, modules });
  }
  const allowed = modules ?? new Set();
  clear(root);

  const sidebar = el('aside', { class: 'sidebar', id: 'sidebar' });
  const brand = el('div', { class: 'sidebar__brand' });
  brand.innerHTML = `<img src="/assets/woddi-logo.png" alt="WODDI" `
    + `style="height:46px;max-width:100%;object-fit:contain;display:block;`
    + `margin:0 auto 2px;background:#fff;border-radius:8px;padding:3px 8px;">`
    + `<em>${esc(t('app.subtitle'))}</em>`;
  const navEl = el('nav', { class: 'nav', 'aria-label': t('nav.label') });
  const HQ_MODULES = new Set(['hq', 'content', 'settings']);
  let hqLabelDone = false;
  for (const n of NAV.filter((x) => x.module === null || allowed.has(x.module))) {
    const isHq = HQ_MODULES.has(n.module);
    if (isHq && !hqLabelDone) {
      navEl.append(el('div', { class: 'nav__section', text: t('nav.hqSection') }));
      hqLabelDone = true;
    }
    const a = el('a', { href: n.hash }, [icon(n.icon), t(n.key)]);
    if (isHq) a.classList.add('nav__hq');
    if (isCurrent(n.hash)) a.setAttribute('aria-current', 'page');
    navEl.append(a);
  }
  const foot = el('div', { class: 'sidebar__foot' });
  foot.innerHTML = `${esc(profile.first_name)} ${esc(profile.last_name)}<br>${esc(profile.email)}<br><span style="opacity:.55;
  foot.append(el('button', { class: 'btn btn--quiet',
    style: 'margin-top:8px;font-size:11px;padding:4px 10px;',
    text: t('bn.enableBtn'),
    onclick: async (e) => {
      const { enableBrowserNotifications } =
        await import('../core/notifybrowser.js');
      const st = await enableBrowserNotifications(profile);
      if (st === 'granted') {
        try {
          const { enablePush } = await import('../core/push.js');
          await enablePush();
        } catch { /* device push optional; in-tab notify already on */ }
      }
      e.target.textContent = st === 'granted'
        ? t('bn.onShort') : t('bn.enableBtn');
    } }));font-size:11px;">build v${esc(APP_VERSION)} · db ${esc(String(EXPECTED_SCHEMA_VERSION))}</span>`;
  sidebar.append(brand, navEl, foot);

  const scrim = el('div', { class: 'scrim', hidden: true,
    onclick: () => toggleSidebar(false) });

  const localeSelect = el('select', {
    class: 'select', 'aria-label': t('app.language'), style: 'width:auto;',
    onchange: async (e) => {
      try {
        const code = e.target.value;
        if (code !== 'en' && code !== 'fr') {
          try {
            const { getOrgSetting } = await import('../core/db.js');
            const dict = await getOrgSetting('locale_' + code)
              .catch(() => null);
            if (!dict) toastError(t('lang.notBuiltToast',
              { lang: LOCALE_NAMES[code] }));
          } catch { /* proceed */ }
        }
        await setLocale(code);
        try {
          const { updateMyProfile } = await import('../core/db.js');
          await updateMyProfile({ preferred_locale: code });
        } catch { /* account save best-effort */ }
        location.reload();
      } catch { toastError(t('errors.localeLoad')); }
    },
  }, supportedLocales().map((code) =>
    el('option', { value: code, selected: code === getLocale() || null,
      text: LOCALE_NAMES[code] })
  ));
  // truth-in-menu: mark languages whose dictionary isn't built yet
  (async () => {
    try {
      const { getOrgSetting } = await import('../core/db.js');
      for (const opt of localeSelect.options) {
        const code = opt.value;
        if (code === 'en' || code === 'fr') continue;
        const dict = await getOrgSetting('locale_' + code).catch(() => null);
        if (!dict) opt.text = LOCALE_NAMES[code] + ' — ' + t('lang.needsBuild');
      }
    } catch { /* menu stays plain */ }
  })();

  const themeBtn = el('button', {
    class: 'btn btn--icon btn--quiet', 'aria-label': t('app.theme'),
    onclick: () => {
      const dark = document.documentElement.dataset.theme !== 'dark';
      document.documentElement.dataset.theme = dark ? 'dark' : '';
      localStorage.setItem('wdos.theme', dark ? 'dark' : 'light');
      themeBtn.replaceChildren(icon(dark ? 'sun' : 'moon'));
    },
  }, [icon(document.documentElement.dataset.theme === 'dark' ? 'sun' : 'moon')]);

  const topbar = el('header', { class: 'topbar' }, [
    el('button', {
      class: 'btn btn--icon btn--quiet', 'aria-label': t('nav.openMenu'),
      onclick: () => toggleSidebar(true), text: '☰',
    }),
    el('h1', { class: 'topbar__title', text: t(titleKey) }),
    el('button', { class: 'btn btn--icon btn--quiet',
      'aria-label': t('search.label'),
      onclick: openSearch }, [icon('search')]),
    bellButton(icon('bell')),
    themeBtn,
    localeSelect,
    el('button', {
      class: 'btn btn--quiet', text: t('auth.signOut'),
      onclick: async () => {
        try { await signOut(); location.hash = '#/login'; }
        catch { toastError(t('errors.signOut')); }
      },
    }),
  ]);

  const offline = el('div', {
    class: 'offline-banner', hidden: navigator.onLine,
    text: t('app.offline'),
  });
  const schemaBanner = el('div', {
    class: 'offline-banner', hidden: true,
    style: 'background:var(--danger-tint);color:var(--danger);',
  });
  if (allowed.has('settings')) {
    getSchemaStatus().then((sst) => {
      if (!sst.known || sst.missing.length > 0) {
        schemaBanner.textContent = t('app.schemaBehind', {
          list: sst.missing.map((v) => String(v).padStart(3, '0')).join(', '),
        });
        schemaBanner.hidden = false;
      }
    }).catch(() => {});
  }
  const syncBanner = () => { offline.hidden = navigator.onLine; };
  window.addEventListener('online', syncBanner);
  window.addEventListener('offline', syncBanner);

  const outlet = el('div', { class: 'content' });
  const main = el('div', { class: 'main' }, [topbar, schemaBanner, offline, outlet]);
  root.append(el('div', { class: 'shell' }, [sidebar, scrim, main]));

  function toggleSidebar(open) {
    sidebar.classList.toggle('open', open);
    scrim.hidden = !open;
  }
  // Mobile: close the drawer after navigating
  sidebar.querySelectorAll('a').forEach((a) =>
    a.addEventListener('click', () => toggleSidebar(false)));

  return {
    outlet,
    teardown() {
      window.removeEventListener('online', syncBanner);
      window.removeEventListener('offline', syncBanner);
    },
  };
}

function isCurrent(hash) {
  const h = location.hash || '#/';
  return hash === '#/' ? h === '#/' : h.startsWith(hash);
}
