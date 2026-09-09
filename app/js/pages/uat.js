/**
 * WDOS Test Feedback — Phase 43. The UAT brief's feedback format, in-app:
 * structured observations (where, role, device, steps, exact error words,
 * expected, severity, result) with screenshot evidence. Testers see their
 * own submissions and triage state; HQ sees the live Issue Register with
 * filters, summary counts, triage status and notes. Blocker submissions
 * alert HQ immediately via the staff inbox (trigger in migration 038).
 */
import { el, esc, clear } from '../core/dom.js';
import { t, fmtDateTime, fmtNumber } from '../core/i18n.js';
import {
  submitUatFeedback, listMyUatFeedback, listAllUatFeedback,
  updateUatFeedback, getUatSummary, uploadUatEvidence, uatEvidenceUrl,
} from '../core/db.js';
import { renderShell } from '../components/layout.js';
import { toast, toastError } from '../components/toast.js';

const TRACKS = ['A', 'B', 'C', 'D', 'E', 'F', 'G'];
const SEVERITIES = ['blocker', 'high', 'medium', 'low', 'suggestion'];
const RESULTS = ['passed', 'failed', 'partial', 'not_available',
  'unable', 'needs_clarification'];
const TRIAGE = ['new', 'accepted', 'in_progress', 'fixed', 'retest',
  'closed', 'duplicate', 'deferred'];
const SEV_BADGE = { blocker: 'exited', high: 'exited', medium: 'pipeline',
  low: 'pipeline', suggestion: 'active' };

export async function render(root, _params, ctx) {
  const shell = renderShell(root, {
    profile: ctx.profile, modules: ctx.modules, titleKey: 'nav.uat',
  });
  const out = shell.outlet;
  clear(out);

  out.append(el('p', { class: 'muted mb-4', text: t('uat.hint') }));

  /* -------- the form -------- */
  const form = el('div', { class: 'card mb-4' });
  out.append(form);
  buildForm();

  /* -------- HQ register (renders only if authorised) -------- */
  const hqBox = el('div');
  out.append(hqBox);
  paintRegister().catch(() => { /* not HQ — fine */ });

  /* -------- my submissions -------- */
  const mineBox = el('div');
  out.append(mineBox);
  paintMine();

  return shell.teardown;

  /* ===================== form ===================== */
  function sel(options, labelFn, value) {
    const x = el('select', { class: 'select' },
      options.map((o) => el('option', { value: o, text: labelFn(o),
        selected: o === value || null })));
    return x;
  }
  function fld(labelKey, input, hintKey = null) {
    const w = el('div', { class: 'field' }, [
      el('label', { class: 'field__label', text: t(labelKey) }), input]);
    if (hintKey) w.append(el('p', { class: 'muted',
      style: 'font-size:12px;margin-top:2px;', text: t(hintKey) }));
    return w;
  }

  function buildForm() {
    clear(form);
    form.append(el('div', { class: 'card__head' }, [
      el('h2', { text: t('uat.newTitle') })]));

    const track = sel(TRACKS, (o) => t(`uat.track.${o}`), 'A');
    const where = el('input', { class: 'input',
      placeholder: t('uat.wherePh') });
    const role = el('input', { class: 'input',
      placeholder: t('uat.rolePh') });
    const device = el('input', { class: 'input',
      placeholder: t('uat.devicePh') });
    const steps = el('textarea', { class: 'input', rows: '3',
      placeholder: t('uat.stepsPh') });
    const observed = el('textarea', { class: 'input', rows: '3',
      placeholder: t('uat.observedPh') });
    const expected = el('textarea', { class: 'input', rows: '2',
      placeholder: t('uat.expectedPh') });
    const severity = sel(SEVERITIES, (o) => t(`uat.sev.${o}`), 'medium');
    const result = sel(RESULTS, (o) => t(`uat.res.${o}`), 'failed');
    const file = el('input', { type: 'file', accept: 'image/*', class: 'input' });
    const extra = el('textarea', { class: 'input', rows: '2',
      placeholder: t('uat.extraPh') });

    form.append(
      el('div', { class: 'form-grid' }, [
        fld('uat.trackL', track),
        fld('uat.whereL', where),
        fld('uat.roleL', role),
        fld('uat.deviceL', device),
      ]),
      fld('uat.stepsL', steps),
      fld('uat.observedL', observed, 'uat.observedHint'),
      fld('uat.expectedL', expected),
      el('div', { class: 'form-grid' }, [
        fld('uat.sevL', severity, 'uat.sevHint'),
        fld('uat.resL', result),
      ]),
      fld('uat.evidenceL', file),
      fld('uat.extraL', extra),
    );

    const send = el('button', { class: 'btn btn--primary',
      text: t('uat.submit') });
    send.addEventListener('click', async () => {
      if (!where.value.trim() || !steps.value.trim() || !observed.value.trim()) {
        toastError(t('uat.required')); return;
      }
      send.disabled = true;
      try {
        let evidence = '';
        if (file.files[0]) {
          try { evidence = await uploadUatEvidence(file.files[0]); }
          catch { toastError(t('uat.evidenceFailed')); }
        }
        await submitUatFeedback({
          track: track.value,
          location_text: where.value.trim(),
          role_tested: role.value.trim(),
          device_browser: device.value.trim(),
          steps: steps.value.trim(),
          observed: observed.value.trim(),
          expected: expected.value.trim(),
          severity: severity.value,
          result: result.value,
          evidence_note: evidence,
          extra_notes: extra.value.trim(),
        });
        toast(severity.value === 'blocker'
          ? t('uat.sentBlocker') : t('uat.sent'));
        buildForm();
        paintMine();
        paintRegister().catch(() => {});
      } catch { toastError(t('errors.save')); }
      finally { send.disabled = false; }
    });
    form.append(send);
  }

  /* ===================== my submissions ===================== */
  async function paintMine() {
    clear(mineBox);
    let rows;
    try { rows = await listMyUatFeedback(); } catch { return; }
    if (!rows.length) return;
    mineBox.append(el('h2', { class: 'mb-2', text: t('uat.mine') }));
    for (const r of rows) mineBox.append(rowCard(r, false));
  }

  /* ===================== HQ register ===================== */
  async function paintRegister() {
    const s = await getUatSummary();   // throws for non-HQ
    clear(hqBox);
    hqBox.append(el('h2', { class: 'mb-2', text: t('uat.register') }));

    hqBox.append(el('div', { class: 'row mb-2',
      style: 'gap:8px;flex-wrap:wrap;' }, [
      chip(t('uat.total'), s.total),
      chip(t('uat.openBlockers'), s.open_blockers,
        s.open_blockers > 0 ? 'badge--exited' : 'badge--active'),
      ...SEVERITIES.map((sv) =>
        chip(t(`uat.sev.${sv}`), (s.by_severity || {})[sv] || 0)),
    ]));

    const sevF = sel([''].concat(SEVERITIES),
      (o) => o ? t(`uat.sev.${o}`) : t('uat.allSev'), '');
    const stF = sel([''].concat(TRIAGE),
      (o) => o ? t(`uat.tri.${o}`) : t('uat.allStatus'), '');
    const trF = sel([''].concat(TRACKS),
      (o) => o ? t(`uat.track.${o}`) : t('uat.allTracks'), '');
    const listEl = el('div');
    const load = async () => {
      clear(listEl);
      listEl.append(el('div', { class: 'state' }, [el('div', { class: 'spinner' })]));
      try {
        const rows = await listAllUatFeedback({
          severity: sevF.value, status: stF.value, track: trF.value });
        clear(listEl);
        if (!rows.length) listEl.append(el('p', { class: 'muted', text: t('uat.noneFound') }));
        for (const r of rows) listEl.append(rowCard(r, true, load));
      } catch { clear(listEl); }
    };
    [sevF, stF, trF].forEach((x) => x.addEventListener('change', load));

    const exportRow = el('div', { class: 'row mb-2', style: 'gap:8px;flex-wrap:wrap;' }, [
      el('button', { class: 'btn btn--quiet', text: t('uat.exportJson'),
        onclick: () => doExport('json') }),
      el('button', { class: 'btn btn--quiet', text: t('uat.exportXlsx'),
        onclick: () => doExport('xlsx') }),
      el('button', { class: 'btn btn--quiet', text: t('uat.exportPdf'),
        onclick: () => doExport('pdf') }),
    ]);
    async function doExport(kind) {
      let rows;
      try {
        rows = await listAllUatFeedback({
          severity: sevF.value, status: stF.value, track: trF.value });
      } catch { toastError(t('errors.load')); return; }
      const plain = rows.map((r) => ({
        date: r.created_at, track: r.track, where: r.location_text,
        role_tested: r.role_tested, device_browser: r.device_browser,
        steps: r.steps, observed: r.observed, expected: r.expected,
        severity: r.severity, result: r.result,
        extra_notes: r.extra_notes || '', triage_status: r.triage_status,
        hq_notes: r.hq_notes || '', evidence: r.evidence_note || '',
      }));
      const stamp = new Date().toISOString().slice(0, 10);
      if (kind === 'json') {
        dl(new Blob([JSON.stringify(plain, null, 2)],
          { type: 'application/json' }), `wdos-uat-register-${stamp}.json`);
      } else if (kind === 'xlsx') {
        try {
          await loadXlsxLib();
          const ws = window.XLSX.utils.json_to_sheet(plain);
          const wb = window.XLSX.utils.book_new();
          window.XLSX.utils.book_append_sheet(wb, ws, 'UAT Register');
          window.XLSX.writeFile(wb, `wdos-uat-register-${stamp}.xlsx`);
        } catch { toastError(t('errors.load')); }
      } else {
        const w = window.open('', '_blank');
        if (!w) { toastError(t('course.popupBlocked')); return; }
        const th = ['Date', 'Track', 'Where', 'Role', 'Device', 'Steps',
          'Observed', 'Expected', 'Severity', 'Result', 'Extra',
          'Triage', 'HQ notes'];
        const cells = (r) => [
          fmtDateTime(r.date), r.track, r.where, r.role_tested,
          r.device_browser, r.steps, r.observed, r.expected,
          r.severity, r.result, r.extra_notes, r.triage_status, r.hq_notes];
        w.document.write('<!doctype html><html><head><title>WDOS UAT Register</title>'
          + '<style>@page{size:A4 landscape;margin:10mm}'
          + 'body{font:10px/1.4 Arial,sans-serif;color:#111}'
          + 'h1{color:#D4006A;font-size:16px}'
          + 'table{border-collapse:collapse;width:100%}'
          + 'th,td{border:1px solid #ccc;padding:4px;text-align:left;'
          + 'vertical-align:top;word-break:break-word}'
          + 'th{background:#D4006A;color:#fff}</style></head><body>'
          + `<h1>WODDI — WDOS UAT Issue Register (${esc(stamp)})</h1><table><tr>`
          + th.map((h) => `<th>${esc(h)}</th>`).join('') + '</tr>'
          + plain.map((r) => '<tr>' + cells(r).map((c) =>
              `<td>${esc(String(c ?? ''))}</td>`).join('') + '</tr>').join('')
          + '</table><script>setTimeout(function(){window.print()},300)</'
          + 'script></body></html>');
        w.document.close();
      }
    }
    function dl(blob, name) {
      const a = el('a', { href: URL.createObjectURL(blob), download: name });
      document.body.append(a); a.click(); a.remove();
    }
    function loadXlsxLib() {
      if (window.XLSX) return Promise.resolve();
      return new Promise((res, rej) => {
        const sc = document.createElement('script');
        sc.src = 'assets/vendor/xlsx.full.min.js';
        sc.onload = res; sc.onerror = rej;
        document.head.append(sc);
      });
    }

    hqBox.append(el('div', { class: 'row mb-2', style: 'gap:8px;flex-wrap:wrap;' },
      [sevF, stF, trF]), exportRow, listEl, el('div', { class: 'mb-4' }));
    await load();
  }

  function chip(label, value, cls = 'badge--pipeline') {
    return el('span', { class: `badge ${cls}`, text: `${label}: ${fmtNumber(value)}` });
  }

  /* ===================== shared row card ===================== */
  function rowCard(r, isHq, reload) {
    const card = el('div', { class: 'card', style: 'margin-bottom:10px;' });
    card.append(
      el('div', { class: 'row', style: 'gap:8px;flex-wrap:wrap;align-items:baseline;' }, [
        el('span', { class: `badge badge--${SEV_BADGE[r.severity]}`,
          text: t(`uat.sev.${r.severity}`) }),
        el('span', { class: 'badge badge--pipeline', text: t(`uat.track.${r.track}`) }),
        el('span', { class: 'badge', text: t(`uat.tri.${r.triage_status}`) }),
        el('strong', { style: 'flex:1;min-width:180px;overflow-wrap:anywhere;',
          text: r.location_text }),
        el('span', { class: 'muted', style: 'font-size:12px;',
          text: fmtDateTime(r.created_at) }),
      ]),
      el('p', { class: 'muted', style: 'font-size:13px;margin:6px 0 2px;',
        text: [r.role_tested, r.device_browser].filter(Boolean).join(' · ') }),
      el('p', { style: 'margin:4px 0;white-space:pre-wrap;' }, [
        el('strong', { text: t('uat.stepsL') + ': ' }), r.steps]),
      el('p', { style: 'margin:4px 0;white-space:pre-wrap;' }, [
        el('strong', { text: t('uat.observedL') + ': ' }), r.observed]),
      r.expected ? el('p', { style: 'margin:4px 0;white-space:pre-wrap;' }, [
        el('strong', { text: t('uat.expectedL') + ': ' }), r.expected]) : null,
      el('p', { class: 'muted', style: 'font-size:12px;',
        text: t(`uat.res.${r.result}`) }),
      r.extra_notes ? el('p', { style: 'margin:4px 0;white-space:pre-wrap;' }, [
        el('strong', { text: t('uat.extraL') + ': ' }), r.extra_notes]) : null,
    );
    if (r.evidence_note) {
      const a = el('a', { href: '#', text: t('uat.viewEvidence') });
      a.addEventListener('click', async (e) => {
        e.preventDefault();
        try { window.open(await uatEvidenceUrl(r.evidence_note), '_blank'); }
        catch { toastError(t('errors.load')); }
      });
      card.append(el('p', { style: 'margin:4px 0;' }, [a]));
    }
    if (isHq) {
      const st = el('select', { class: 'select' },
        TRIAGE.map((o) => el('option', { value: o, text: t(`uat.tri.${o}`),
          selected: o === r.triage_status || null })));
      const notes = el('input', { class: 'input',
        placeholder: t('uat.notesPh') });
      notes.value = r.hq_notes || '';
      const save = el('button', { class: 'btn btn--quiet', text: t('studio.save'),
        onclick: async (e) => {
          e.target.disabled = true;
          try {
            await updateUatFeedback(r.id, {
              triage_status: st.value, hq_notes: notes.value.trim() });
            toast(t('studio.saved'));
            if (reload) reload();
          } catch { toastError(t('errors.save')); e.target.disabled = false; }
        } });
      card.append(el('div', { class: 'row mt-2',
        style: 'gap:8px;flex-wrap:wrap;' }, [st, notes, save]));
    } else if (r.hq_notes) {
      card.append(el('p', { class: 'q-feedback q-feedback--ok',
        text: t('uat.hqSays') + ' ' + r.hq_notes }));
    }
    return card;
  }
}
