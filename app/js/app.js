/**
 * WDOS bootstrap. Order matters:
 * config → i18n → db → routes → router.
 */
import { loadConfig } from './core/config.js';
import { initI18n, t, registerLocaleLoader } from './core/i18n.js';
import { initDb, getSession, getMyProfile, getMyModules, onAuthChange, authLog, wasUserSignOut } from './core/db.js';
import { registerRoute, setGuard, startRouter } from './core/router.js';
import * as login from './pages/login.js';
import * as reset from './pages/reset.js';
import * as doctor from './pages/doctor.js';
import * as readpage from './pages/read.js';
import * as idstart from './pages/idstart.js';
import * as leadership from './pages/leadership.js';
import { initBrowserNotify } from './core/notifybrowser.js';
import * as dashboard from './pages/dashboard.js';
import * as membersList from './pages/members-list.js';
import * as memberDetail from './pages/member-detail.js';
import * as recruitment from './pages/recruitment.js';
import * as apply from './pages/apply.js';
import * as organisation from './pages/organisation.js';
import * as tasks from './pages/tasks.js';
import * as meetings from './pages/meetings.js';
import * as reports from './pages/reports.js';
import * as announcements from './pages/announcements.js';
import * as settings from './pages/settings.js';
import * as programmes from './pages/programmes.js';
import * as cases from './pages/cases.js';
import * as helpdesk from './pages/helpdesk.js';
import * as library from './pages/library.js';
import * as documents from './pages/documents.js';
import * as hq from './pages/hq.js';
import * as leaders from './pages/leaders.js';
import * as command from './pages/command.js';
import * as spotlight from './pages/spotlight.js';
import * as outreach from './pages/outreach.js';
import * as me from './pages/me.js';
import * as content from './pages/content.js';
import * as uat from './pages/uat.js';
import * as claim from './pages/claim.js';
import * as ask from './pages/ask.js';
import * as messages from './pages/messages.js';
import * as room from './pages/room.js';
import * as volunteer from './pages/volunteer.js';
import * as interpret from './pages/interpret.js';
import * as home from './pages/home.js';
import * as accounts from './pages/accounts.js';
import * as structure from './pages/structure.js';
import * as reporting from './pages/reporting.js';
import * as reflinks from './pages/reflinks.js';
import * as refland from './pages/refland.js';
import { setShellMode } from './components/layout.js';
import { touchLastSeen } from './core/db.js';

const ctx = { profile: null, modules: null };

const ROUTE_MODULES = {
  '#/members': 'members',
  '#/recruitment': 'recruitment',
  '#/organisation': 'organisation',
  '#/tasks': 'tasks',
  '#/meetings': 'meetings',
  '#/reports': 'reports',
  '#/leadership': 'hq',
  '#/announcements': 'announcements',
  '#/settings': 'settings',
  '#/programmes': 'programmes',
  '#/cases': 'cases',
  '#/helpdesk': 'helpdesk',
  '#/library': 'library',
  '#/documents': 'documents',
  '#/hq': 'hq',
  '#/leaders': 'hq',
  '#/command': 'hq',
  '#/spotlight-review': 'hq',
  '#/outreach': 'hq',
  '#/content': 'content',
  '#/accounts': 'hq',
  '#/reflinks': 'hq',
  '#/view-as': 'hq',
};

/* wdos-clean-paste: normalise pasted text everywhere (smart quotes,
   long dashes, zero-width characters, Windows line endings). */
document.addEventListener('paste', (e) => {
  const el2 = e.target;
  const ok = el2 && (el2.tagName === 'TEXTAREA'
    || (el2.tagName === 'INPUT' && (el2.type === 'text' || el2.type === 'search')));
  if (!ok) return;
  const raw = (e.clipboardData || window.clipboardData).getData('text');
  if (!raw) return;
  e.preventDefault();
  const clean = raw
    .replace(/\r\n?/g, '\n')
    .replace(/[\u2018\u2019\u201A]/g, "'")
    .replace(/[\u201C\u201D\u201E]/g, '"')
    .replace(/[\u2013\u2014]/g, '-')
    .replace(/\u00A0/g, ' ')
    .replace(/[\u200B-\u200D\uFEFF]/g, '')
    .replace(/[ \t]+\n/g, '\n');
  const start = el2.selectionStart ?? el2.value.length;
  const end = el2.selectionEnd ?? el2.value.length;
  el2.value = el2.value.slice(0, start) + clean + el2.value.slice(end);
  const pos = start + clean.length;
  el2.setSelectionRange(pos, pos);
  el2.dispatchEvent(new Event('input', { bubbles: true }));
});

async function boot() {
  // Supabase recovery links land with tokens in the hash; the client
  // consumes them, then we route to the reset screen.
  if (location.hash.includes('type=recovery')) {
    setTimeout(() => { location.hash = '#/reset'; }, 400);
  }
  if (localStorage.getItem('wdos.theme') === 'dark') {
    document.documentElement.dataset.theme = 'dark';
  }
  const root = document.getElementById('app');
  try {
    await loadConfig();
    initDb();
    registerLocaleLoader(async (code) => {
      const { getOrgSetting } = await import('./core/db.js');
      const d = await getOrgSetting('locale_' + code);
      return d && typeof d === 'object' ? d : null;
    });
    await initI18n();
  } catch (err) {
    root.innerHTML =
      `<div class="state"><h3>WDOS could not start</h3>` +
      `<p>${String(err?.message ?? err)
        .replaceAll('<', '&lt;').replaceAll('>', '&gt;')}</p></div>`;
    return;
  }

  const authed = (page) => async (outlet, params) => {
    if (!ctx.profile) ctx.profile = await getMyProfile();
    // No profile means no live session (it expired or was dropped between
    // the guard and here): go to the login form instead of rendering a
    // page for nobody.
    if (!ctx.profile) { ctx.hq = undefined; location.hash = '#/login'; return () => {}; }
    try { initBrowserNotify(ctx.profile); } catch { /* optional */ }
    // Phase 131: HQ staff and HQ role holders keep the central dashboard;
    // every member and volunteer leader gets the Volunteer Dashboard shell.
    if (ctx.hq === undefined) {
      try {
        const { amIStaff, getMyRoles } = await import('./core/db.js');
        const [staff, roles] = await Promise.all([amIStaff(), getMyRoles().catch(() => [])]);
        const HQ = new Set(['super_admin', 'executive_director', 'hq_team']);
        ctx.hq = !!staff || (roles || []).some((r) => HQ.has(r.role));
      } catch { ctx.hq = false; }
      setShellMode(ctx.hq ? 'hq' : 'volunteer');
    }
    // Phase 131 (gap 6): last_seen_at follows real activity, not just boot
    if (!ctx.seenAt || Date.now() - ctx.seenAt > 10 * 60 * 1000) {
      ctx.seenAt = Date.now();
      touchLastSeen();
    }
    try {
      const want = ctx.profile?.preferred_locale;
      const { getLocale, setLocale } = await import('./core/i18n.js');
      if (want && want !== getLocale()) await setLocale(want);
    } catch { /* keep current language */ }
    if (!ctx.modules) {
      try { ctx.modules = await getMyModules(); }
      catch { ctx.modules = new Set(['tasks', 'meetings', 'announcements']); }
    }
    return page.render(outlet, params, ctx);
  };

  registerRoute('#/login', (o, p) => login.render(o, p), { isPublic: true });
  registerRoute('#/reset', (o, p) => reset.render(o, p), { isPublic: true });
  registerRoute('#/doctor', authed(doctor.render));
  registerRoute('#/read', authed(readpage.render));
  registerRoute('#/id', (o, p) => idstart.render(o, p), { isPublic: true });
  registerRoute('#/apply', (o, p) => apply.render(o, p), { isPublic: true });
  registerRoute('#/r/:code', (o, p) => refland.render(o, p), { isPublic: true });
  registerRoute('#/claim', (o, p) => claim.render(o, p), { isPublic: true });
  registerRoute('#/volunteer', (o, p) => volunteer.render(o, p), { isPublic: true });
  registerRoute('#/', authed({ render: (o, p, c) =>
    (c.hq ? dashboard.render(o, p, c) : home.render(o, p, c)) }));
  registerRoute('#/my/:tab', authed(home));
  registerRoute('#/view-as/:id', authed(home));
  registerRoute('#/accounts', authed(accounts));
  registerRoute('#/structure', authed(structure));
  registerRoute('#/reflinks', authed(reflinks));
  registerRoute('#/reporting', authed(reporting));
  registerRoute('#/reporting/:tab', authed(reporting));
  registerRoute('#/reporting/:tab/:id', authed(reporting));
  registerRoute('#/me', authed(me));
  registerRoute('#/content', authed(content));
  registerRoute('#/feedback', authed(uat));
  registerRoute('#/ask', authed(ask));
  registerRoute('#/messages', authed(messages));
  registerRoute('#/room', authed(room));
  registerRoute('#/interpret', authed(interpret));
  registerRoute('#/me/:tab', authed(me));
  registerRoute('#/members', authed(membersList));
  registerRoute('#/members/:id', authed(memberDetail));
  registerRoute('#/recruitment', authed(recruitment));
  registerRoute('#/recruitment/:id', authed(recruitment));
  registerRoute('#/organisation', authed(organisation));
  registerRoute('#/tasks', authed(tasks));
  registerRoute('#/meetings', authed(meetings));
  registerRoute('#/reports', authed(reports));
  registerRoute('#/leadership', authed((o, p, c) => leadership.render(o, p, c)));
  registerRoute('#/announcements', authed(announcements));
  registerRoute('#/settings', authed(settings));
  registerRoute('#/programmes', authed(programmes));
  registerRoute('#/cases', authed(cases));
  registerRoute('#/cases/:id', authed(cases));
  registerRoute('#/helpdesk', authed(helpdesk));
  registerRoute('#/helpdesk/:id', authed(helpdesk));
  registerRoute('#/library', authed(library));
  registerRoute('#/documents', authed(documents));
  registerRoute('#/hq', authed(hq));
  registerRoute('#/leaders', authed(leaders));
  registerRoute('#/command', authed(command));
  registerRoute('#/spotlight-review', authed(spotlight));
  registerRoute('#/outreach', authed(outreach));

  setGuard(async (route) => {
    const session = await getSession();
    if (!route.isPublic && !session) return '#/login';
    if (session && location.hash.startsWith('#/login')) return '#/';
    // Module gate: routes are only reachable if HQ granted the module.
    const base = '#/' + (location.hash.split('/')[1] ?? '');
    const needed = ROUTE_MODULES[base];
    if (session && needed) {
      if (!ctx.modules) {
        try { ctx.modules = await getMyModules(); }
        catch { ctx.modules = new Set(['tasks', 'meetings', 'announcements']); }
      }
      if (!ctx.modules.has(needed)) return '#/';
    }
    return null;
  });

  onAuthChange(async (session, event) => {
    authLog(event || (session ? 'session' : 'no_session'), { user: !!session });
    if (session) return;
    if (event === 'INITIAL_SESSION') return;          // no stored session at boot: the guard handles it
    const byUser = wasUserSignOut();
    if (!byUser) {
      // Not the user's click. A stale storage event from another window can
      // announce a sign-out while this window's session is still valid:
      // re-check before evicting anyone.
      await new Promise((r) => setTimeout(r, 800));
      let still = null;
      try { still = await getSession(); } catch { still = null; }
      if (still) { authLog('spurious_signed_out_ignored'); return; }
      authLog('auto_signed_out', { page: location.hash });
      try { localStorage.setItem('wdos.lastAutoSignOut', JSON.stringify({ at: new Date().toISOString(), page: location.hash, build: (await import('./core/db.js')).APP_VERSION })); } catch { /* ok */ }
    }
    ctx.profile = null; ctx.modules = null; ctx.hq = undefined; ctx.seenAt = 0;
    // Cached rows must never survive a sign-out on a shared device.
    if ('caches' in window) caches.delete('wdos-data').catch(() => {});
    location.hash = '#/login';
  });

  // Offline-first: register the service worker (no-op where unsupported).
  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.register('/sw.js').catch(() => {});
  }

  document.title = t('app.title');
  await startRouter();
  if ((document.getElementById('app')?.children?.length ?? 0) > 0) {
    window.__wdosReady = true;
  }
  touchLastSeen();
}

boot();
