/**
 * Phase 33 — mobile chrome for the leader/volunteer view ( #/me ).
 * A phone-first shell: gradient header with the notification bell, a
 * scrolling body outlet, and a bottom tab bar. Distinct from the desktop
 * sidebar shell so it feels like a native app on a phone.
 */
import { el, esc, clear } from '../core/dom.js';
import { t } from '../core/i18n.js';
import { signOut } from '../core/db.js';
import { icon } from './icons.js';
import { bellButton } from './notify.js';
import { toastError } from './toast.js';

const TABS = [
  { id: 'home',    key: 'me.tabHome',    icon: 'home' },
  { id: 'journey', key: 'me.tabJourney', icon: 'check' },
  { id: 'learn',   key: 'me.tabLearn',   icon: 'book' },
  { id: 'profile', key: 'me.tabProfile', icon: 'sliders' },
];

export function renderMobile(root, { profile, active, onTab, established }) {
  clear(root);
  const tabs = established
    ? TABS.filter((tb) => tb.id !== 'journey')   // graduated leaders: no
    : TABS;                                      // activation door to show

  const themeBtn = el('button', {
    class: 'btn btn--icon btn--quiet', 'aria-label': t('app.theme'),
    style: 'background:#fff;color:#D4006A;border:0;',
    style: 'background:#fff;color:#D4006A;border:0;',
    onclick: () => {
      const dark = document.documentElement.dataset.theme !== 'dark';
      document.documentElement.dataset.theme = dark ? 'dark' : '';
      localStorage.setItem('wdos.theme', dark ? 'dark' : 'light');
      themeBtn.replaceChildren(icon(dark ? 'sun' : 'moon'));
    },
  }, [icon(document.documentElement.dataset.theme === 'dark' ? 'sun' : 'moon')]);

  const top = el('header', { class: 'mob__top' }, [
    el('button', {
      class: 'btn btn--icon btn--quiet',
      style: 'background:#fff;color:#D4006A;border:0;font-size:17px;'
        + 'font-weight:800;',
      'aria-label': t('me.backDashBtn'),
      title: t('me.backDashBtn'),
      onclick: () => { location.hash = '#/'; },
    }, [el('span', { text: '\u2302' })]),
    el('span', { class: 'mob__brand' }, [
      el('img', { src: '/assets/woddi-logo.png', alt: 'WODDI',
        style: 'height:30px;object-fit:contain;background:#fff;'
          + 'border-radius:6px;padding:2px 6px;display:block;' }),
    ]),
    el('span', { class: 'mob__grow' }),
    bellButton(icon('bell')),
    themeBtn,
    el('button', {
      class: 'btn btn--icon btn--quiet', 'aria-label': t('auth.signOut'),
      style: 'background:#fff;color:#D4006A;border:0;',
      onclick: async () => {
        try { await signOut(); location.hash = '#/login'; }
        catch { toastError(t('errors.signOut')); }
      },
    }, [icon('signout')]),
  ]);
  top.firstChild.innerHTML = `WODDI<em>${esc(t('app.subtitle'))}</em>`;

  const body = el('div', { class: 'mob__body' });

  const tabsEl = el('nav', { class: 'mob__tabs', 'aria-label': t('nav.label') });
  const tabButtons = {};
  for (const tab of tabs) {
    const b = el('button', {
      class: 'mob__tab', role: 'tab',
      'aria-selected': String(tab.id === active),
      onclick: () => onTab(tab.id),
    }, [icon(tab.icon), el('span', { text: t(tab.key) })]);
    tabButtons[tab.id] = b;
    tabsEl.append(b);
  }

  root.append(el('div', { class: 'mob' }, [top, body, tabsEl]));

  return {
    body,
    setActive(id) {
      for (const [tid, b] of Object.entries(tabButtons)) {
        b.setAttribute('aria-selected', String(tid === id));
      }
    },
  };
}
