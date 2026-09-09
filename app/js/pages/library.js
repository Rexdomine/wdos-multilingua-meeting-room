import { el, esc, clear } from '../core/dom.js';
import { t, fmtDate } from '../core/i18n.js';
import {
  listMessageTemplates, updateMessageTemplate, approveMessageTemplate,
  createTemplateLocale, fillTemplate,
} from '../core/db.js';
import { renderShell } from '../components/layout.js';
import { toast, toastError } from '../components/toast.js';

const CATEGORIES = ['application', 'activation', 'membership', 'service',
  'events', 'meetings', 'learning', 'celebration', 'engagement',
  'welfare', 'exit'];
const LOCALES = ['en', 'fr', 'pt', 'ar', 'sw', 'ha', 'yo', 'ig'];
const SAMPLE = {
  first_name: 'Adaeze', last_name: 'Okafor', role: 'Chapter Lead',
  chapter: 'Ikeja Chapter 1', network: 'WGMN', programme: 'WIWS',
  reference: 'C-2026-0001',
};

export async function render(root, _params, ctx) {
  const shell = renderShell(root, {
    profile: ctx.profile, modules: ctx.modules, titleKey: 'nav.library',
  });
  const out = shell.outlet;
  const state = { category: '', locale: 'en' };

  const catSel = el('select', { class: 'select',
    onchange: (e) => { state.category = e.target.value; load(); } }, [
    el('option', { value: '', text: t('lib.allCategories') }),
    ...CATEGORIES.map((c) => el('option', { value: c,
      text: t(`libcat.${c}`) })),
  ]);
  const locSel = el('select', { class: 'select',
    onchange: (e) => { state.locale = e.target.value; load(); } },
    LOCALES.map((l) => el('option', { value: l,
      text: t(`locale.${l}`) })));
  const listArea = el('div');
  out.append(
    el('p', { class: 'muted mb-4', text: t('lib.intro') }),
    el('div', { class: 'toolbar' }, [catSel, locSel,
      el('span', { class: 'grow' }),
      el('span', { class: 'muted', text: t('lib.tokens') })]),
    listArea
  );
  await load();
  return shell.teardown;

  async function load() {
    clear(listArea);
    listArea.append(el('div', { class: 'state' }, [
      el('div', { class: 'spinner' }), el('p', { text: t('app.loading') }),
    ]));
    let rows, enRows;
    try {
      [rows, enRows] = await Promise.all([
        listMessageTemplates(state.category, state.locale),
        state.locale === 'en'
          ? Promise.resolve(null)
          : listMessageTemplates(state.category, 'en'),
      ]);
    } catch {
      clear(listArea);
      listArea.append(el('div', { class: 'card state' }, [
        el('h3', { text: t('errors.loadTitle') }),
        el('button', { class: 'btn btn--quiet', text: t('app.retry'),
          onclick: load }),
      ]));
      return;
    }
    clear(listArea);

    /* In a non-English locale, offer translation stubs for anything
       that exists in English but not yet in this language. */
    if (enRows) {
      const have = new Set(rows.map((r) => r.code));
      const missing = enRows.filter((r) => !have.has(r.code));
      if (missing.length > 0) {
        listArea.append(el('div', { class: 'card mb-4' }, [
          el('p', { class: 'muted',
            text: t('lib.missingLocale', { n: String(missing.length) }) }),
          el('div', { class: 'row' }, [
            el('span', { class: 'grow' }),
            el('button', { class: 'btn btn--secondary',
              text: t('lib.createStubs'),
              onclick: async (e) => {
                e.target.disabled = true;
                try {
                  for (const m of missing) {
                    await createTemplateLocale(m, state.locale);
                  }
                  toast(t('lib.stubsCreated'));
                  load();
                } catch { toastError(t('errors.save'));
                  e.target.disabled = false; }
              } }),
          ]),
        ]));
      }
    }

    if (rows.length === 0) {
      listArea.append(el('div', { class: 'card state' }, [
        el('h3', { text: t('lib.emptyTitle') })]));
      return;
    }
    for (const tpl of rows) listArea.append(card(tpl));
  }

  function card(tpl) {
    const box = el('div', { class: 'card mb-4' });
    const badge = el('span', {
      class: `badge badge--${tpl.status === 'approved' ? 'active' : 'paused'}`,
      text: t(`libstatus.${tpl.status}`) });
    box.append(el('div', { class: 'card__head' }, [
      el('div', {}, [
        el('h3', { text: tpl.name }),
        el('span', { class: 'muted',
          text: `${t(`libcat.${tpl.category}`)} · v${tpl.version}` +
            ` · ${fmtDate(tpl.updated_at)}` }),
      ]),
      badge,
    ]));

    const subject = el('input', { class: 'input', maxlength: '200',
      value: tpl.subject ?? '', placeholder: t('lib.subjectHint') });
    const body = el('textarea', { class: 'input', rows: '3',
      maxlength: '4000' });
    body.value = tpl.body;
    const preview = el('p', {
      class: 'muted', hidden: true,
      style: 'border-left:3px solid var(--magenta);padding-left:10px;' });
    box.append(
      el('div', { class: 'field' }, [
        el('label', { class: 'field__label', text: t('lib.subject') }),
        subject]),
      el('div', { class: 'field' }, [
        el('label', { class: 'field__label', text: t('lib.body') }), body]),
      preview,
      el('div', { class: 'row' }, [
        el('button', { class: 'btn btn--quiet', text: t('lib.preview'),
          onclick: () => {
            preview.textContent =
              `${fillTemplate(subject.value, SAMPLE)} — ` +
              fillTemplate(body.value, SAMPLE);
            preview.hidden = false;
          } }),
        el('span', { class: 'grow' }),
        el('button', { class: 'btn btn--secondary', text: t('app.save'),
          onclick: async (e) => {
            if (body.value.trim().length < 3) {
              toastError(t('lib.errBody')); return;
            }
            e.target.disabled = true;
            try {
              const upd = await updateMessageTemplate(tpl.id, {
                subject: subject.value.trim() || null,
                body: body.value.trim(),
              });
              Object.assign(tpl, upd);
              toast(t('lib.saved', { v: String(upd.version) }));
              badge.className = 'badge badge--paused';
              badge.textContent = t('libstatus.draft');
            } catch { toastError(t('errors.save')); }
            finally { e.target.disabled = false; }
          } }),
        el('button', { class: 'btn btn--primary', text: t('lib.approve'),
          disabled: tpl.status === 'approved' || null,
          onclick: async (e) => {
            e.target.disabled = true;
            try {
              const upd = await approveMessageTemplate(tpl.id);
              Object.assign(tpl, upd);
              toast(t('lib.approved'));
              badge.className = 'badge badge--active';
              badge.textContent = t('libstatus.approved');
            } catch { toastError(t('errors.save'));
              e.target.disabled = false; }
          } }),
      ])
    );
    return box;
  }
}
