/**
 * WDOS Reader — Phase 69. Governance documents as native in-app pages
 * (no PDFs, no downloads): the Code of Conduct and the Volunteer
 * Leadership Manual, dressed in WODDI's own styling, ending in a
 * "Mark as read & return" key that ticks the matching Day-1 task.
 */
import { el, clear } from '../core/dom.js';
import { t } from '../core/i18n.js';
import { renderMobile } from '../components/mobileshell.js';
import { toast } from '../components/toast.js';

const DOCS = {
  coc: { file: '/content/code-of-conduct.html',
    titleKey: 'read.cocTitle', tick: 'conduct' },
  manual: { file: '/content/leadership-manual.html',
    titleKey: 'read.manualTitle', tick: 'handbook' },
};

export async function render(root, params, ctx) {
  const docKey = String(params?.d || 'manual');
  const doc = DOCS[docKey] || DOCS.manual;
  const shell = renderMobile(root, {
    profile: ctx.profile, active: 'journey', titleKey: doc.titleKey,
  });

  const article = el('div', { class: 'card',
    style: 'line-height:1.75;font-size:15px;' });
  article.innerHTML = `<div class="state"><div class="spinner"></div></div>`;
  shell.body.append(article);

  const done = el('button', { class: 'btn btn--primary',
    style: 'width:100%;margin:14px 0 24px;',
    text: t('read.markDone') });
  done.addEventListener('click', () => {
    try {
      const cur = JSON.parse(sessionStorage.getItem('wdos.ticks') || '[]');
      if (!cur.includes(doc.tick)) cur.push(doc.tick);
      sessionStorage.setItem('wdos.ticks', JSON.stringify(cur));
    } catch { /* best effort */ }
    toast(t('read.marked'));
    location.hash = '#/me';
  });
  shell.body.append(done);

  try {
    const res = await fetch(doc.file, { cache: 'no-cache' });
    if (!res.ok) throw new Error(String(res.status));
    const htmlText = await res.text();
    clear(article);
    article.innerHTML = htmlText;
  } catch {
    clear(article);
    article.append(el('p', { class: 'muted', text: t('errors.loadHint') }));
  }
  return shell.teardown;
}
