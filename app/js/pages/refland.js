/**
 * Phase 136 — public landing for a referral link: #/r/:code
 * Records the visit (when, where the visitor came from, language, time
 * zone, screen), keeps the code on this device for 30 days, and sends the
 * visitor to the right door with the invitation shown.
 */
import { el, clear } from '../core/dom.js';
import { t } from '../core/i18n.js';
import { referralVisit, REF_KEY } from '../core/db.js';

export async function render(root, params) {
  clear(root);
  const code = String(params.code || '').trim();
  const wrap = el('div', { class: 'auth' });
  const card = el('div', { class: 'card auth__card' }, [el('div', { class: 'spinner' })]);
  wrap.append(el('div', { class: 'auth__brand' }, [el('h1', { text: 'WODDI' }), el('p', { text: t('app.subtitle') })]), card);
  root.append(wrap);
  let info = null;
  try {
    info = await referralVisit(code, {
      referrer: (() => { try { return new URL(document.referrer).host; } catch { return ''; } })(),
      ua: navigator.userAgent, lang: navigator.language,
      tz: Intl.DateTimeFormat().resolvedOptions().timeZone,
      screen: `${(window.screen && window.screen.width) || 0}x${(window.screen && window.screen.height) || 0}`,
    });
  } catch { info = null; }
  clear(card);
  if (!info || !info.ok) {
    card.append(el('h3', { text: t('ref.badTitle') }), el('p', { class: 'muted', text: t('ref.badHint') }),
      el('a', { href: '#/volunteer', class: 'btn btn--primary', text: t('ref.joinMember') }));
    return;
  }
  try { localStorage.setItem(REF_KEY, JSON.stringify({ code: info.code, visit_id: info.visit_id, at: new Date().toISOString(), network: info.network, role: info.role, unit_id: info.unit_id })); } catch { /* ok */ }
  const place = (info.chain || []).map((c) => c.name).join(' \u203A ');
  card.append(
    el('h3', { text: t('ref.title', { owner: info.owner }) }),
    info.role
      ? el('p', { text: t('ref.roleLine', { role: t(`role.${info.role}`), place: place || t('ref.anywhere'), net: info.network || 'WODDI' }) })
      : el('p', { text: t('ref.memberLine', { place: place || t('ref.anywhere'), net: info.network || 'WODDI' }) }),
    info.label ? el('p', { class: 'muted', text: info.label }) : null,
    el('div', { class: 'row', style: 'gap:8px;flex-wrap:wrap;margin-top:12px;' }, [
      info.role ? el('a', { href: '#/apply', class: 'btn btn--primary', text: t('ref.applyBtn') }) : null,
      el('a', { href: '#/volunteer', class: info.role ? 'btn btn--secondary' : 'btn btn--primary', text: t('ref.joinMember') }),
      el('a', { href: '#/login', class: 'btn btn--quiet', text: t('ref.haveLogin') }),
    ]),
    el('p', { class: 'muted', style: 'font-size:12px;margin-top:10px;', text: t('ref.note') }),
  );
}
