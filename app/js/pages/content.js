/**
 * WDOS Content Studio — Phase 40. HQ's own editor for everything members
 * read and answer: the 14-day activation curriculum (messages, questions,
 * answer keys), the engagement library (weekly / monthly / masterclass),
 * and the two certification courses (lessons, questions, keys).
 * Content belongs to WODDI's content team — no SQL, no IT.
 */
import { el, esc, clear } from '../core/dom.js';
import { t, fmtNumber } from '../core/i18n.js';
import {
  getActivationDays, getAllActivationItems, getActivationKeys,
  updateActivationDay, updateActivationItem, setActivationKey,
  listEngagement, updateEngagement,
  listCourses, getCourseModules, getModuleQuestions, getCourseKeys,
  updateCourseModule, updateCourseQuestion, setCourseKey,
} from '../core/db.js';
import { renderShell } from '../components/layout.js';
import { toast, toastError } from '../components/toast.js';

export async function render(root, _params, ctx) {
  const shell = renderShell(root, {
    profile: ctx.profile, modules: ctx.modules, titleKey: 'nav.content',
  });
  const out = shell.outlet;
  clear(out);

  out.append(el('p', { class: 'muted mb-4', text: t('studio.hint') }));

  const tabs = el('div', { class: 'row mb-4', style: 'gap:8px;flex-wrap:wrap;' });
  const body = el('div');
  out.append(tabs, body);

  const SECTIONS = [
    ['activation', activation],
    ['engagement', engagement],
    ['courses', courses],
  ];
  const btns = {};
  for (const [id, fn] of SECTIONS) {
    btns[id] = el('button', { class: 'btn btn--secondary',
      text: t(`studio.${id}`), onclick: () => open(id, fn) });
    tabs.append(btns[id]);
  }
  await open('activation', activation);
  return shell.teardown;

  async function open(id, fn) {
    for (const [bid, b] of Object.entries(btns)) {
      b.className = bid === id ? 'btn btn--primary' : 'btn btn--secondary';
    }
    clear(body);
    body.append(el('div', { class: 'state' }, [el('div', { class: 'spinner' })]));
    try { await fn(); }
    catch {
      clear(body);
      body.append(el('p', { class: 'muted', text: t('errors.loadHint') }));
    }
  }

  /* ---------- shared editor helpers ---------- */
  function field(labelKey, input) {
    return el('div', { class: 'field' }, [
      el('label', { class: 'field__label', text: t(labelKey) }), input]);
  }
  function saveBtn(fn) {
    const b = el('button', { class: 'btn btn--secondary', text: t('studio.save') });
    b.addEventListener('click', async () => {
      b.disabled = true;
      try { await fn(); toast(t('studio.saved')); }
      catch { toastError(t('errors.save')); }
      finally { b.disabled = false; }
    });
    return b;
  }
  function ta(value, rows = 3) {
    const x = el('textarea', { class: 'input', rows: String(rows) });
    x.value = value || '';
    return x;
  }
  function inp(value) {
    const x = el('input', { class: 'input', type: 'text' });
    x.value = value || '';
    return x;
  }
  function details(summaryText, cls = '') {
    const d = el('details', { class: 'card ' + cls, style: 'margin-bottom:10px;' });
    d.append(el('summary', { style: 'cursor:pointer;font-weight:700;',
      text: summaryText }));
    return d;
  }

  /* ================= ACTIVATION ================= */
  async function activation() {
    const [days, items, keys] = await Promise.all([
      getActivationDays(), getAllActivationItems(),
      getActivationKeys().catch(() => []),
    ]);
    const keyMap = new Map(keys.map((k) => [k.item_id, k.correct]));
    clear(body);
    body.append(el('p', { class: 'muted mb-2', text: t('studio.actHint') }));

    for (const d of days) {
      const box = details(`${t('me.day')} ${d.day} — ${d.title}`);
      const titleI = inp(d.title);
      const introT = ta(d.intro, 3);
      box.append(
        field('studio.dayTitle', titleI),
        field('studio.dayIntro', introT),
        saveBtn(() => updateActivationDay(d.id,
          { title: titleI.value.trim(), intro: introT.value.trim() })));

      for (const it of items.filter((x) => x.day === d.day)) {
        const ib = el('div', { class: 'card',
          style: 'margin-top:10px;background:var(--canvas);' });
        ib.append(el('div', { class: 'notice__kind',
          text: `${t('studio.item')} ${it.seq} · ${t(`me.kind.${{'mcq':'knowledge','tf':'knowledge','written':'written','checklist':'onboarding','ack':'onboarding'}[it.kind] || 'knowledge'}`)} (${it.kind})` }));
        const promptT = ta(it.prompt, 2);
        const optsT = ta((it.options || []).join('\n'),
          Math.max(2, (it.options || []).length));
        const keyI = inp(typeof keyMap.get(it.id) === 'string'
          ? keyMap.get(it.id) : JSON.stringify(keyMap.get(it.id) ?? ''));
        ib.append(field('studio.prompt', promptT));
        if (['mcq', 'tf', 'checklist'].includes(it.kind)) {
          ib.append(field('studio.options', optsT));
        }
        if (['mcq', 'tf'].includes(it.kind)) {
          ib.append(field('studio.correct', keyI),
            el('p', { class: 'muted', style: 'font-size:12px;',
              text: t('studio.keyHint') }));
        }
        ib.append(saveBtn(async () => {
          const patch = { prompt: promptT.value.trim() };
          if (['mcq', 'tf', 'checklist'].includes(it.kind)) {
            patch.options = optsT.value.split('\n')
              .map((x) => x.trim()).filter(Boolean);
          }
          await updateActivationItem(it.id, patch);
          if (['mcq', 'tf'].includes(it.kind) && keyI.value.trim()) {
            await setActivationKey(it.id, keyI.value.trim());
          }
        }));
        box.append(ib);
      }
      body.append(box);
    }
  }

  /* ================= ENGAGEMENT ================= */
  async function engagement() {
    const [weekly, monthly, mclass] = await Promise.all([
      listEngagement('weekly'), listEngagement('monthly'),
      listEngagement('masterclass'),
    ]);
    clear(body);
    body.append(el('p', { class: 'muted mb-2', text: t('studio.engHint') }));
    const groups = [
      ['studio.weekly', weekly, 'me.week'],
      ['studio.monthly', monthly, 'studio.monthN'],
      ['studio.masterclass', mclass, 'studio.monthN'],
    ];
    for (const [labelKey, rows, perKey] of groups) {
      const box = details(t(labelKey) + ` (${fmtNumber(rows.length)})`);
      for (const r of rows) {
        const rb = el('div', { class: 'card',
          style: 'margin-top:10px;background:var(--canvas);' });
        rb.append(el('div', { class: 'notice__kind',
          text: t(perKey, { n: r.period }) }));
        const titleI = inp(r.title);
        const focusT = ta(r.focus, 2);
        rb.append(field('studio.title', titleI),
          field('studio.focus', focusT),
          saveBtn(() => updateEngagement(r.id,
            { title: titleI.value.trim(), focus: focusT.value.trim() })));
        box.append(rb);
      }
      body.append(box);
    }
  }

  /* ================= COURSES ================= */
  async function courses() {
    const [cs, keys] = await Promise.all([
      listCourses(), getCourseKeys().catch(() => []),
    ]);
    const keyMap = new Map(keys.map((k) => [k.question_id, k.correct]));
    clear(body);
    body.append(el('p', { class: 'muted mb-2', text: t('studio.courseHint') }));

    for (const c of cs) {
      const box = details(`${c.code} — ${c.title}`);
      body.append(box);
      const mods = await getCourseModules(c.id);
      for (const m of mods) {
        const mb = details(`${t('course.moduleN', { n: m.seq })}: ${m.title}`, '');
        mb.style.background = 'var(--canvas)';
        mb.style.marginTop = '10px';
        const titleI = inp(m.title);
        const lessonT = ta(m.lesson, 7);
        mb.append(field('studio.title', titleI),
          field('studio.lesson', lessonT),
          saveBtn(() => updateCourseModule(m.id,
            { title: titleI.value.trim(), lesson: lessonT.value.trim() })));

        const qs = await getModuleQuestions(m.id);
        for (const qq of qs) {
          const qb = el('div', { class: 'card', style: 'margin-top:10px;' });
          qb.append(el('div', { class: 'notice__kind',
            text: `${t('studio.question')} ${qq.seq}` }));
          const promptT = ta(qq.prompt, 2);
          const optsT = ta((qq.options || []).join('\n'), 4);
          const keyI = inp(keyMap.get(qq.id) || '');
          qb.append(field('studio.prompt', promptT),
            field('studio.options', optsT),
            field('studio.correct', keyI),
            el('p', { class: 'muted', style: 'font-size:12px;',
              text: t('studio.keyHint') }),
            saveBtn(async () => {
              await updateCourseQuestion(qq.id, {
                prompt: promptT.value.trim(),
                options: optsT.value.split('\n')
                  .map((x) => x.trim()).filter(Boolean),
              });
              if (keyI.value.trim()) await setCourseKey(qq.id, keyI.value.trim());
            }));
          mb.append(qb);
        }
        box.append(mb);
      }
    }
  }
}
