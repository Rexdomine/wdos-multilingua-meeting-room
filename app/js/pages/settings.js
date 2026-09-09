import { el, esc, clear } from '../core/dom.js';
import { t, fmtDate, fmtNumber } from '../core/i18n.js';
import { listModuleAccess, setModuleAccess, getSchemaStatus,
  EXPECTED_SCHEMA_VERSION, listAutomationRules, updateAutomationRule,
  listAutomationEvents, runAutomations, getAutomationInsights,
  getOrgSetting, setOrgSetting, getAiToken, setAiToken, setEmailSecret, getEmailStatus,
  sendTestEmail, findDuplicateProfiles, mergeProfiles } from '../core/db.js';
import { renderShell } from '../components/layout.js';
import { aiChat, aiTranslateBatch } from '../core/ai.js';
import { toast, toastError } from '../components/toast.js';

const MODULES = ['members', 'recruitment', 'organisation', 'tasks',
  'meetings', 'reports', 'announcements', 'programmes', 'cases', 'helpdesk', 'hq', 'settings', 'content'];
const ROLES = ['super_admin', 'executive_director', 'hq_team',
  'country_rep', 'deputy_country_rep', 'state_coordinator',
  'assistant_state_coordinator', 'district_coordinator', 'chapter_lead',
  'volunteer', 'member', 'programme_staff', 'institute_admin',
  'donor', 'external_partner'];

export async function render(root, _params, ctx) {
  const shell = renderShell(root, {
    profile: ctx.profile, modules: ctx.modules, titleKey: 'nav.settings',
  });
  const out = shell.outlet;

  out.append(el('div', { class: 'state' }, [
    el('div', { class: 'spinner' }), el('p', { text: t('app.loading') }),
  ]));

  let rows, schema;
  try {
    [rows, schema] = await Promise.all([listModuleAccess(), getSchemaStatus()]);
  } catch {
    clear(out);
    out.append(el('div', { class: 'card state' }, [
      el('h3', { text: t('errors.loadTitle') }),
      el('p', { text: t('errors.loadHint') }),
      el('button', { class: 'btn btn--quiet', text: t('app.retry'),
        onclick: () => render(root, _params, ctx) }),
    ]));
    return shell.teardown;
  }

  const granted = new Set(rows.map((r) => `${r.role}:${r.module}`));

  clear(out);

  /* System health */
  const healthy = schema.known && schema.missing.length === 0;
  const health = el('div', { class: 'card mb-4' }, [
    el('div', { class: 'card__head' }, [
      el('h2', { text: t('set.healthTitle') }),
      el('span', { class: `badge badge--${healthy ? 'active' : 'exited'}`,
        text: healthy ? t('set.healthOk') : t('set.healthBad') }),
    ]),
    el('p', {
      class: healthy ? 'muted' : 'field__error',
      text: healthy
        ? t('set.healthDetail', { n: String(EXPECTED_SCHEMA_VERSION) })
        : t('set.healthMissing', {
            list: schema.missing.map((v) => String(v).padStart(3, '0'))
              .join(', ') }),
    }),
  ]);
  out.append(health);

  out.append(
    el('div', { class: 'card' }, [
      el('div', { class: 'card__head' }, [
        el('h2', { text: t('set.accessTitle') })]),
      el('p', { class: 'muted', text: t('set.accessHint') }),
      buildMatrix(),
    ])
  );

  /* --- Activation window (Phase 38) --- */
  const winCard = el('div', { class: 'card mt-4' });
  out.append(winCard);
  (async () => {
    let cur = 14;
    try { cur = Number(await getOrgSetting('activation_window_days')) || 14; }
    catch { winCard.hidden = true; return; }
    const inp = el('input', { class: 'input', type: 'number',
      min: '7', max: '90', value: String(cur),
      style: 'width:90px;text-align:center;' });
    winCard.append(
      el('div', { class: 'card__head' }, [el('h2', { text: t('set.winTitle') })]),
      el('p', { class: 'muted', text: t('set.winHint') }),
      el('div', { class: 'row', style: 'gap:10px;align-items:center;' }, [
        inp,
        el('span', { class: 'muted', text: t('auto.days') }),
        el('button', { class: 'btn btn--secondary', text: t('set.save'),
          onclick: async (e) => {
            const v = Math.max(7, Math.min(90, Number(inp.value) || 14));
            inp.value = String(v);
            e.target.disabled = true;
            try { await setOrgSetting('activation_window_days', v);
              toast(t('set.saved')); }
            catch { toastError(t('errors.save')); }
            finally { e.target.disabled = false; }
          } }),
      ]));
  })();

  /* --- Data hygiene: duplicates (Phase 41) --- */
  const dupCard = el('div', { class: 'card mt-4' });
  out.append(dupCard);
  paintDupes(null);

  function personLine(p) {
    return `${p.first_name || ''} ${p.last_name || ''} · ${p.email || '—'}`
      + ` · ${t('status.' + p.status)}`;
  }
  async function paintDupes(groups) {
    clear(dupCard);
    dupCard.append(
      el('div', { class: 'card__head' }, [
        el('h2', { text: t('dupe.title') }),
        el('button', { class: 'btn btn--secondary', text: t('dupe.scan'),
          onclick: async (e) => {
            e.target.disabled = true;
            try { paintDupes(await findDuplicateProfiles()); }
            catch { toastError(t('errors.load')); e.target.disabled = false; }
          } }),
      ]),
      el('p', { class: 'muted', text: t('dupe.hint') }));
    if (groups === null) return;
    if (!groups.length) {
      dupCard.append(el('p', { class: 'q-feedback q-feedback--ok',
        text: t('dupe.none') }));
      return;
    }
    for (const g of groups) {
      const row = el('div', { class: 'card',
        style: 'margin-top:10px;background:var(--canvas);' });
      row.append(el('span', { class: 'badge badge--pipeline',
        text: t('dupe.reason.' + g.reason) }));
      const reasonI = el('input', { class: 'input', type: 'text',
        placeholder: t('dupe.reasonPlaceholder'), style: 'margin:8px 0;' });
      const mk = (keepP, dropP, label) => el('button', {
        class: 'btn btn--quiet', text: label,
        onclick: async (e) => {
          if (reasonI.value.trim().length < 5) {
            toastError(t('dupe.needReason')); return;
          }
          e.target.disabled = true;
          try {
            await mergeProfiles(keepP.id, dropP.id, reasonI.value.trim());
            toast(t('dupe.merged'));
            row.remove();
          } catch { toastError(t('errors.save')); e.target.disabled = false; }
        } });
      row.append(
        el('p', { style: 'margin:8px 0 2px;' }, [
          el('strong', { text: 'A: ' }), personLine(g.a)]),
        el('p', { style: 'margin:2px 0 8px;' }, [
          el('strong', { text: 'B: ' }), personLine(g.b)]),
        reasonI,
        el('div', { class: 'row', style: 'gap:8px;flex-wrap:wrap;' }, [
          mk(g.a, g.b, t('dupe.keepA')), mk(g.b, g.a, t('dupe.keepB'))]));
      dupCard.append(row);
    }
  }

  /* --- Email layer (Phase 39) --- */
  const mailCard = el('div', { class: 'card mt-4' });
  out.append(mailCard);

  /* ---------- voice engine (free AI voices for live captions) ---------- */
  const voiceCard = el('div', { class: 'card mb-4' });
  voiceCard.append(el('div', { class: 'card__head' }, [
    el('h2', { text: t('set.voiceTitle') })]));
  voiceCard.append(el('p', { class: 'muted mb-2', text: t('set.voiceHint') }));
  const tokIn = el('input', { class: 'input', type: 'password',
    placeholder: 'hf_…', autocomplete: 'off' });
  const tokSave = el('button', { class: 'btn btn--primary',
    text: t('set.voiceSave') });
  tokSave.addEventListener('click', async () => {
    tokSave.disabled = true;
    try {
      await setAiToken(tokIn.value.trim());
      toast(t('set.voiceSaved'));
    } catch { toastError(t('errors.save')); }
    finally { tokSave.disabled = false; }
  });
  try {
    const cur = await getAiToken();
    if (cur) tokIn.value = String(cur);
  } catch { /* not set yet */ }
  const tokTest = el('button', { class: 'btn btn--secondary',
    text: t('set.voiceTest') });
  const spaceIn = el('input', { class: 'input',
    placeholder: 'mms-meta-mms.hf.space', style: 'max-width:280px;' });
  try {
    const sp0 = await getOrgSetting('tts_space');
    if (sp0) spaceIn.value = String(sp0);
  } catch { /* default */ }
  const spaceSave = el('button', { class: 'btn btn--quiet',
    text: t('app.save'),
    onclick: async (e) => {
      e.target.disabled = true;
      try {
        await setOrgSetting('tts_space', spaceIn.value.trim());
        toast(t('set.callSaved'));
      } catch { toastError(t('errors.save')); }
      finally { e.target.disabled = false; }
    } });
  const diag = el('pre', { class: 'muted mt-2', style:
    'font-size:12px;white-space:pre-wrap;background:var(--canvas);'
    + 'padding:10px;border-radius:10px;display:none;' });
  tokTest.addEventListener('click', async () => {
    tokTest.disabled = true;
    diag.style.display = 'block';
    diag.textContent = '';
    const say = (line) => { diag.textContent += line + '\n'; };
    try {
      const tok = tokIn.value.trim();

      // 1 ▸ TRANSLATION engine (needs the key)
      say('1) Translation AI (chat lane, en\u2192ha)\u2026');
      if (!tok) say('   \u2192 skipped: no key pasted');
      else {
        try {
          const { text: outT, model: mdl } = await aiChat([
            { role: 'system',
              content: 'Translate the user text from English to Hausa. Reply with ONLY the translation.' },
            { role: 'user',
              content: 'Welcome to WODDI. No woman is left out.' },
          ], tok, { temperature: 0, say });
          say('   \u2192 200 \u2713 via ' + mdl + ' \u2014 "'
            + outT.slice(0, 80) + '"');
        } catch (e1) {
          say('   \u2192 all models refused (' + e1.message + ')');
        }
      }

      // 2 ▸ VOICE via the free Space (no key needed)
      let base = spaceIn.value.trim() || 'mms-meta-mms.hf.space';
      if (!base.startsWith('http')) base = 'https://' + base;
      base = base.replace(/\/+$/, '');
      say('2) Voice via free Space ' + base + ' …');
      try {
        const { spaceSpeakTest } = await import('../core/ttsprobe.js');
        const verdict = await spaceSpeakTest(base,
          'Sannu! Barka da zuwa WODDI.', 'hau', say);
        if (verdict) {
          const audio = new Audio(verdict);
          audio.controls = true;
          audio.style.cssText = 'display:block;margin-top:8px;max-width:320px;';
          diag.after(audio);
          try {
            await audio.play();
            say('   \u2192 AUDIO PLAYING \u2713');
          } catch (perr) {
            if (perr && perr.name === 'NotAllowedError') {
              say('   \u2192 audio verified \u2713 \u2014 the browser blocked '
                + 'auto-play; press \u25B6 on the player below to hear it');
            } else {
              say('   \u2192 the player refused the audio ('
                + (perr && perr.name ? perr.name : 'unknown')
                + ') \u2014 screenshot this panel');
            }
          }
          toast(t('set.voiceTestOk'));
          return;
        }
      } catch (e2) { say('   → ' + e2.message); }
      say('VERDICT: if step 1 is 200, captions + interface languages are');
      say('healthy. If step 2 failed, paste a different MMS Space address');
      say('above (huggingface.co → Spaces → search "MMS TTS"), Save, retest.');
      toastError(t('set.voiceTestFail'));
    } finally { tokTest.disabled = false; }
  });
  voiceCard.append(
    el('div', { class: 'row', style: 'gap:8px;flex-wrap:wrap;' },
      [tokIn, tokSave, tokTest]),
    el('p', { class: 'muted mt-2', style: 'font-size:12px;',
      text: t('set.spaceHint') }),
    el('div', { class: 'row', style: 'gap:8px;flex-wrap:wrap;' },
      [spaceIn, spaceSave]),
    diag);
  out.append(voiceCard);

  /* ---------- call engine domain ---------- */
  const callCard = el('div', { class: 'card mb-4' });
  callCard.append(el('div', { class: 'card__head' }, [
    el('h2', { text: t('set.callTitle') })]));
  callCard.append(el('p', { class: 'muted mb-2', text: t('set.callHint') }));
  const domIn = el('input', { class: 'input',
    placeholder: 'meet.ffmuc.net', style: 'max-width:280px;' });
  try {
    const cd = await getOrgSetting('call_domain');
    if (cd) domIn.value = String(cd);
  } catch { /* default */ }
  const domSave = el('button', { class: 'btn btn--primary',
    text: t('app.save'),
    onclick: async (e) => {
      e.target.disabled = true;
      try {
        await setOrgSetting('call_domain', domIn.value.trim());
        toast(t('set.callSaved'));
      } catch { toastError(t('errors.save')); }
      finally { e.target.disabled = false; }
    } });
  callCard.append(el('div', { class: 'row', style: 'gap:8px;flex-wrap:wrap;' },
    [domIn, domSave]));
  out.append(callCard);

  /* ---------- AI interface languages ---------- */
  const langCard = el('div', { class: 'card mb-4' });
  langCard.append(el('div', { class: 'card__head' }, [
    el('h2', { text: t('set.langTitle') })]));
  langCard.append(el('p', { class: 'muted mb-2', text: t('set.langHint') }));
  const LANG_BUILD = [['ha', 'Hausa'], ['yo', 'Yorùbá'], ['ig', 'Igbo'],
    ['sw', 'Kiswahili'], ['ar', 'العربية'], ['pt', 'Português']];
  const prog = el('p', { class: 'muted', style: 'font-size:13px;' });
  const rowB = el('div', { class: 'row', style: 'gap:8px;flex-wrap:wrap;' });
  for (const [code, label] of LANG_BUILD) {
    const b = el('button', { class: 'btn btn--secondary', text: label });
    b.addEventListener('click', async () => {
      const tok = String((await getAiToken().catch(() => '')) || '');
      if (!tok) { toastError(t('set.langNeedsKey')); return; }
      b.disabled = true;
      try {
        const res = await fetch('/locales/en.json', { cache: 'no-cache' });
        const en = await res.json();
        const keys = Object.keys(en);
        const outDict = {};
        const BATCH = 12;
        for (let i = 0; i < keys.length; i += BATCH) {
          const slice = keys.slice(i, i + BATCH);
          try {
            const outs = await aiTranslateBatch(
              slice.map((k) => en[k]), code, tok);
            slice.forEach((k, idx) => { outDict[k] = outs[idx] || en[k]; });
          } catch {
            slice.forEach((k) => { outDict[k] = en[k]; });
          }
          prog.textContent = t('set.langProgress',
            { p: Math.min(100, Math.round(((i + BATCH) / keys.length) * 100)),
              lang: label });
        }
        // completeness pass: retry untranslated keys one by one
        const misses = keys.filter((k) => outDict[k] === en[k]
          && String(en[k]).trim().length > 1);
        let retried = 0;
        for (const k of misses.slice(0, 250)) {
          try {
            const { aiTranslate } = await import('../core/ai.js');
            const one = await aiTranslate(en[k], 'en', code, tok);
            const holders = (String(en[k]).match(/\{\w+\}/g) || []);
            const ok = holders.every((h) => one.includes(h));
            if (one && ok) { outDict[k] = one; retried += 1; }
          } catch { /* keep english for this key */ }
          prog.textContent = t('set.langPolish',
            { done: retried, total: misses.length, lang: label });
        }
        const translated = keys.filter((k) => outDict[k] !== en[k]).length;
        const pctDone = Math.round((translated / keys.length) * 100);
        await setOrgSetting('locale_' + code, outDict);
        prog.textContent = t('set.langCoverage',
          { p: pctDone, lang: label });
        prog.textContent = '';
        toast(t('set.langDone', { lang: label }));
      } catch { toastError(t('set.langFail')); }
      finally { b.disabled = false; }
    });
    rowB.append(b);
  }
  langCard.append(rowB, prog);
  out.append(langCard);
  paintEmail();

  async function paintEmail() {
    clear(mailCard);
    let st;
    try { st = await getEmailStatus(); }
    catch { mailCard.hidden = true; return; }
    mailCard.hidden = false;
    mailCard.append(
      el('div', { class: 'card__head' }, [el('h2', { text: t('mail.title') })]),
      el('p', { class: 'muted', text: t('mail.hint') }));

    const status = el('p', { style: 'margin-bottom:10px;' }, [
      el('span', { class: `badge badge--${st.key_set ? 'active' : 'exited'}`,
        text: st.key_set ? t('mail.keySet') : t('mail.keyMissing') }),
    ]);
    mailCard.append(status);

    const key = el('input', { class: 'input', type: 'password',
      placeholder: t('mail.keyPlaceholder'), autocomplete: 'off' });
    const from = el('input', { class: 'input', type: 'email',
      placeholder: 'noreply@thewoddi.org', value: st.from || '' });
    const fromName = el('input', { class: 'input', type: 'text',
      placeholder: 'WODDI', value: st.from_name || '' });
    mailCard.append(el('div', { class: 'form-grid' }, [
      el('div', { class: 'field' }, [
        el('label', { class: 'field__label', text: t('mail.key') }), key]),
      el('div', { class: 'field' }, [
        el('label', { class: 'field__label', text: t('mail.from') }), from]),
      el('div', { class: 'field' }, [
        el('label', { class: 'field__label', text: t('mail.fromName') }), fromName]),
    ]));

    const digestBox = el('input', { type: 'checkbox', class: 'toggle' });
    digestBox.checked = !!st.enabled;
    digestBox.addEventListener('change', async () => {
      try { await setOrgSetting('email_enabled', digestBox.checked);
        toast(t('set.saved')); }
      catch { digestBox.checked = !digestBox.checked; toastError(t('errors.save')); }
    });
    const noticesBox = el('input', { type: 'checkbox', class: 'toggle' });
    noticesBox.checked = !!st.notices;
    noticesBox.addEventListener('change', async () => {
      try { await setOrgSetting('email_notices_enabled', noticesBox.checked);
        toast(t('set.saved')); }
      catch { noticesBox.checked = !noticesBox.checked; toastError(t('errors.save')); }
    });
    mailCard.append(
      el('div', { class: 'row', style: 'gap:10px;align-items:center;margin:8px 0;' }, [
        digestBox, el('span', { text: t('mail.digests') })]),
      el('div', { class: 'row', style: 'gap:10px;align-items:center;margin:8px 0;' }, [
        noticesBox, el('span', { text: t('mail.notices') })]));

    mailCard.append(el('div', { class: 'row mt-2', style: 'gap:8px;flex-wrap:wrap;' }, [
      el('button', { class: 'btn btn--secondary', text: t('mail.save'),
        onclick: async (e) => {
          e.target.disabled = true;
          try {
            if (key.value.trim()) await setEmailSecret('brevo_api_key', key.value.trim());
            if (from.value.trim()) await setEmailSecret('email_from', from.value.trim());
            if (fromName.value.trim()) await setEmailSecret('email_from_name', fromName.value.trim());
            key.value = '';
            toast(t('set.saved'));
            paintEmail();
          } catch { toastError(t('errors.save')); }
          finally { e.target.disabled = false; }
        } }),
      el('button', { class: 'btn btn--quiet', text: t('mail.test'),
        onclick: async (e) => {
          e.target.disabled = true;
          try {
            const ok = await sendTestEmail();
            ok ? toast(t('mail.testSent')) : toastError(t('mail.testFailed'));
          } catch { toastError(t('mail.testFailed')); }
          finally { e.target.disabled = false; }
        } }),
    ]));
  }

  /* --- Smart automation (Phase 35) --- */
  const autoCard = el('div', { class: 'card mt-4' });
  out.append(autoCard);
  paintAutomation();

  return shell.teardown;

  async function paintAutomation() {
    clear(autoCard);
    autoCard.append(el('div', { class: 'state' }, [el('div', { class: 'spinner' })]));
    let rules, events, ins;
    try {
      [rules, events, ins] = await Promise.all([
        listAutomationRules(), listAutomationEvents(),
        getAutomationInsights(),
      ]);
    } catch {
      clear(autoCard);
      autoCard.append(
        el('div', { class: 'card__head' }, [el('h2', { text: t('auto.title') })]),
        el('p', { class: 'muted', text: t('auto.needsMigration') }));
      return;
    }
    clear(autoCard);

    const runBtn = el('button', { class: 'btn btn--primary',
      text: t('auto.runNow'),
      onclick: async (e) => {
        e.target.disabled = true;
        try {
          await runAutomations();
          toast(t('auto.ran'));
          paintAutomation();
        } catch { toastError(t('errors.save')); e.target.disabled = false; }
      } });
    autoCard.append(el('div', { class: 'card__head' }, [
      el('h2', { text: t('auto.title') }), runBtn]));
    autoCard.append(el('p', { class: 'muted', text: t('auto.hint') }));

    /* Recommendations */
    const recs = (ins.recommendations || []);
    const recWrap = el('div', { class: 'mb-4' });
    recWrap.append(el('h3', { class: 'mb-2', text: t('auto.recsTitle') }));
    for (const r of recs) {
      const ok = r.code === 'all_clear';
      recWrap.append(el('div', { class: 'row', style: 'gap:8px;margin-bottom:6px;align-items:baseline;' }, [
        el('span', { class: `badge badge--${ok ? 'active' : 'pipeline'}`,
          text: ok ? '\u2713' : '!' }),
        el('span', { text: t(`auto.rec.${r.code}`, { n: fmtNumber(r.n) }) }),
      ]));
    }
    autoCard.append(recWrap);

    /* Funnel numbers */
    const j = ins.journeys || {};
    autoCard.append(el('div', { class: 'row', style: 'flex-wrap:wrap;gap:8px;margin-bottom:14px;' }, [
      chip(t('auto.appsWaiting'), ins.apps_waiting),
      chip(t('auto.volWaiting'), ins.volunteers?.waiting),
      chip(t('auto.journeysActive'), j.in_progress),
      chip(t('auto.journeysDone'), j.completed),
      chip(t('auto.journeysOverdue'), j.overdue),
      ins.avg_decision_days != null
        ? chip(t('auto.avgDecision'), ins.avg_decision_days) : null,
      ins.quiz_avg_pct != null
        ? chip(t('auto.quizAvg'), ins.quiz_avg_pct + '%') : null,
    ]));

    /* Rules */
    autoCard.append(el('h3', { class: 'mb-2', text: t('auto.rulesTitle') }));
    for (const r of rules) {
      const days = el('input', { class: 'input', type: 'number',
        min: '1', max: '60', value: String(r.threshold_days),
        style: 'width:74px;text-align:center;',
        onchange: async (e) => {
          const v = Math.max(1, Math.min(60, Number(e.target.value) || 1));
          e.target.value = String(v);
          try { await updateAutomationRule(r.code, { threshold_days: v });
            toast(t('set.saved')); }
          catch { toastError(t('errors.save')); }
        } });
      const box = el('input', { type: 'checkbox', class: 'toggle',
        onchange: async (e) => {
          try { await updateAutomationRule(r.code, { is_active: e.target.checked });
            toast(t('set.saved')); }
          catch { e.target.checked = !e.target.checked; toastError(t('errors.save')); }
        } });
      box.checked = r.is_active;
      autoCard.append(el('div', { class: 'row',
        style: 'gap:12px;align-items:center;margin-bottom:10px;flex-wrap:wrap;' }, [
        box,
        el('div', { style: 'flex:1;min-width:220px;' }, [
          el('strong', { text: t(`auto.rule.${r.code}`) }),
          el('div', { class: 'muted', style: 'font-size:12px;',
            text: r.last_run_at
              ? t('auto.lastRun', { d: fmtDate(r.last_run_at),
                  n: fmtNumber(r.last_matches) })
              : t('auto.neverRun') }),
        ]),
        el('span', { class: 'muted', style: 'font-size:12px;', text: t('auto.days') }),
        days,
      ]));
    }

    /* Recent firings */
    if (events.length) {
      autoCard.append(el('h3', { class: 'mb-2 mt-4', text: t('auto.eventsTitle') }));
      for (const ev of events) {
        autoCard.append(el('div', { class: 'muted',
          style: 'font-size:13px;margin-bottom:4px;',
          text: `${fmtDate(ev.fired_at)} — ${t(`auto.rule.${ev.rule_code}`)}: ` +
            t('auto.eventLine', { m: fmtNumber(ev.matches), s: fmtNumber(ev.notified) }) }));
      }
    }

    function chip(label, value) {
      return el('span', { class: 'chip',
        text: `${label}: ${value ?? 0}` });
    }
  }

  function buildMatrix() {
    const wrap = el('div', { class: 'table-wrap' });
    const tbl = el('table', { class: 'table' });
    tbl.innerHTML = `
      <thead><tr>
        <th>${esc(t('set.roleCol'))}</th>
        ${MODULES.map((m) => `<th>${esc(t(`mod.${m}`))}</th>`).join('')}
      </tr></thead>`;
    const tbody = el('tbody');
    for (const role of ROLES) {
      const tr = el('tr', { style: 'cursor:default;' });
      tr.append(el('td', {}, [el('strong', { text: t(`role.${role}`) })]));
      for (const module of MODULES) {
        const key = `${role}:${module}`;
        const guard = role === 'super_admin' && module === 'settings';
        const box = el('input', {
          type: 'checkbox',
          'aria-label': `${t(`role.${role}`)} — ${t(`mod.${module}`)}`,
          checked: granted.has(key) || null,
          disabled: guard || null,   // HQ can never lock itself out
          onchange: async (e) => {
            const enabled = e.target.checked;
            e.target.disabled = true;
            try {
              await setModuleAccess(role, module, enabled);
              if (enabled) granted.add(key); else granted.delete(key);
              toast(t('set.saved'));
            } catch {
              e.target.checked = !enabled;
              toastError(t('errors.save'));
            } finally {
              if (!guard) e.target.disabled = false;
            }
          },
        });
        tr.append(el('td', {}, [box]));
      }
      tbody.append(tr);
    }
    tbl.append(tbody);
    wrap.append(tbl);
    return wrap;
  }
}
