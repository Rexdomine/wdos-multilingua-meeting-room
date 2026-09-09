/**
 * Phase 134 — REPORTING & ACCOUNTABILITY (#/reporting/:tab?/:id?)
 *
 * Built to the Final Functional Specification v1.0. One engine renders any
 * report template from its JSON sections: read-only auto blocks come from
 * the server snapshot (record once), manual fields capture explanation,
 * exceptions, decisions and priorities. Drafts autosave. Submission runs
 * the server validation. Reviewers approve, return with reason or
 * escalate; approval locks the record and turns priorities and meeting
 * actions into tasks. Corrections create versions. The dashboard is
 * exception-led: overdue, awaiting review, returned, red/critical issues,
 * vacancies, overdue actions, evidence gaps.
 *
 * Tabs: dashboard · mine · records · review · compliance · issues · archive
 *       report/:id (editor or read view) · new/:template
 */
import { el, clear, debounce } from '../core/dom.js';
import { t, fmtDate, fmtDateTime, fmtNumber } from '../core/i18n.js';
import {
  reportOpen, reportGet, reportSave, reportSubmit, reportReview, reportNewVersion,
  reportingDashboard, reportingCompliance, reportingList, reportingRemindersRun,
  listReportTemplates, addActivityRecord, listActivityRecords, addIssue, listIssues,
  updateIssue, uploadReportEvidence, reportEvidenceUrl, addReportContribution,
  getReportingConfig, setReportingConfig, listOrgUnits,
} from '../core/db.js';
import { renderShell } from '../components/layout.js';
import { openModal, closeModal } from '../components/modal.js';
import { toast, toastError } from '../components/toast.js';
import { icon } from '../components/icons.js';

const TABS = ['dashboard', 'mine', 'records', 'review', 'compliance', 'issues', 'archive'];
const ACT_CATS = ['member_engagement', 'mobilisation', 'leadership_followup', 'recruitment_support',
  'learning_support', 'meeting', 'programme', 'stakeholder', 'digital_support', 'communication',
  'task_completed', 'issue', 'other'];
const ISSUE_CATS = ['Leadership', 'Membership', 'Programme', 'Learning', 'Technology', 'Communications',
  'Partnership', 'Finance', 'Governance', 'Data', 'Operational', 'Reputation', 'Other'];
const SEV = ['green', 'amber', 'red', 'critical'];
const STATUS_TONE = {
  draft: 'grey', submitted: 'blue', under_review: 'blue', returned: 'amber', approved: 'green',
  escalated: 'red', closed: 'grey', superseded: 'grey', not_started: 'amber', no_leader: 'grey',
};

export async function render(root, params, ctx) {
  const shell = renderShell(root, { profile: ctx.profile, modules: ctx.modules, titleKey: 'nav.reporting' });
  const out = shell.outlet;
  clear(out);
  const tab = params.tab || 'dashboard';
  const isHq = !!ctx.hq;

  // sub-navigation
  const nav = el('nav', { class: 'rp-tabs' }, TABS.map((k) => el('a', {
    href: `#/reporting/${k}`, class: k === tab ? 'is-active' : '', text: t(`rp.tab_${k}`) })));
  const body = el('div');
  out.append(el('h2', { class: 'rp-title', text: t('rp.title') }), nav, body);

  const draw = {
    dashboard, mine, records, review, compliance, issues, archive,
    report: () => reportView(params.id), new: () => newReport(params.id),
  }[tab] || dashboard;
  try { await draw(); }
  catch (err) {
    console.error('[reporting]', err);
    clear(body);
    body.append(el('div', { class: 'card state' }, [el('h3', { text: t('errors.loadTitle') }),
      el('p', { class: 'muted', text: String(err?.message || err).slice(0, 240) }),
      el('button', { class: 'btn btn--quiet', text: t('app.retry'), onclick: () => render(root, params, ctx) })]));
  }
  return shell.teardown;

  /* ================================================================ dashboard (§25) */
  async function dashboard() {
    clear(body);
    const d = await reportingDashboard();
    const me = d.me || {};
    const sup = d.supervisor || {};
    const cards = el('div', { class: 'rp-cards' });
    const card = (label, value, tone, href, sub) => el(href ? 'a' : 'div', { class: `rp-card rp-card--${tone}`, href }, [
      el('b', { text: String(value ?? 0) }), el('span', { text: label }), sub ? el('small', { text: sub }) : null]);

    // personal (§25.1)
    const dueList = me.due || [];
    const overdue = dueList.filter((r) => r.overdue).length;
    cards.append(
      card(t('rp.cDue'), dueList.length, overdue ? 'red' : 'blue', '#/reporting/mine',
        dueList[0] ? t('rp.nearest', { d: fmtDate(dueList[0].due_on) }) : ''),
      card(t('rp.cOverdue'), overdue, overdue ? 'red' : 'green', '#/reporting/mine'),
      card(t('rp.cReturned'), me.returned, me.returned ? 'amber' : 'green', '#/reporting/mine'),
      card(t('rp.cApproved'), me.approved_period, 'green', '#/reporting/archive'),
      card(t('rp.cOnTime'), me.on_time_rate == null ? '\u2014' : `${me.on_time_rate}%`, 'grey'),
      card(t('rp.cOpenIssues'), me.open_issues, me.open_issues ? 'amber' : 'green', '#/reporting/issues'),
      card(t('rp.cTasksOverdue'), me.tasks?.overdue, me.tasks?.overdue ? 'red' : 'green', '#/tasks'),
    );
    body.append(el('section', { class: 'card' }, [
      el('div', { class: 'row' }, [
        el('h3', { class: 'grow', text: me.unit ? t('rp.myUnit', { unit: me.unit, role: t(`role.${me.role}`) }) : t('rp.noUnit') }),
        me.monthly_expected ? el('a', { href: '#/reporting/new/monthly_leadership', class: 'btn btn--primary',
          text: me.monthly_status ? t('rp.openMonthly') : t('rp.startMonthly') }) : null,
        me.weekly_required ? el('a', { href: '#/reporting/new/weekly_pulse', class: 'btn btn--secondary', text: t('rp.openPulse') }) : null,
      ]),
      me.monthly_expected ? el('p', { class: 'muted', text: t('rp.monthlyLine', {
        period: fmtDate(me.monthly_period?.start), due: fmtDate(me.monthly_period?.due),
        status: t(`rp.st_${me.monthly_status || 'not_started'}`) }) }) : el('p', { class: 'muted', text: t('rp.noUnitHint') }),
      cards,
      el('div', { class: 'rp-quick' }, [
        el('a', { href: '#/reporting/records', class: 'btn btn--secondary', text: t('rp.recordActivity') }),
        el('a', { href: '#/reporting/new/activity_report', class: 'btn btn--secondary', text: t('rp.tpl_activity_report') }),
        el('a', { href: '#/reporting/new/meeting_actions', class: 'btn btn--secondary', text: t('rp.tpl_meeting_actions') }),
        el('a', { href: '#/reporting/issues', class: 'btn btn--secondary', text: t('rp.raiseIssue') }),
        el('a', { href: '#/my/safeguarding', class: 'btn btn--quiet', text: t('rp.confidential') }),
      ]),
    ]));

    // supervisor (§25.2): exceptions first
    if ((sup.units || 0) > 0 || isHq) {
      const scards = el('div', { class: 'rp-cards' }, [
        card(t('rp.sUnits'), sup.units, 'grey', '#/reporting/compliance'),
        card(t('rp.sExpected'), sup.expected, 'grey', '#/reporting/compliance'),
        card(t('rp.sAwaiting'), sup.awaiting_review, sup.awaiting_review ? 'blue' : 'green', '#/reporting/review'),
        card(t('rp.sOverdue'), sup.overdue, sup.overdue ? 'red' : 'green', '#/reporting/compliance'),
        card(t('rp.sReturned'), sup.returned, sup.returned ? 'amber' : 'green', '#/reporting/compliance'),
        card(t('rp.sApproved'), sup.approved, 'green', '#/reporting/compliance'),
        card(t('rp.sRed'), (d.red_critical || []).length, (d.red_critical || []).length ? 'red' : 'green', '#/reporting/issues'),
        card(t('rp.sVacancies'), d.vacancies, d.vacancies ? 'amber' : 'green', '#/structure'),
        card(t('rp.sOverdueActions'), d.overdue_actions, d.overdue_actions ? 'red' : 'green', '#/tasks'),
        card(t('rp.sEvidence'), d.evidence_gaps, d.evidence_gaps ? 'amber' : 'green', '#/reporting/review'),
      ]);
      body.append(el('section', { class: 'card' }, [
        el('h3', { text: t('rp.supervisorTitle') }),
        el('p', { class: 'muted', text: t('rp.supervisorHint') }), scards]));
      if ((d.review_queue || []).length) body.append(queueCard(d.review_queue));
      if ((d.red_critical || []).length) body.append(el('section', { class: 'card' }, [
        el('h3', { text: t('rp.sRed') }),
        ...d.red_critical.slice(0, 8).map((i) => el('div', { class: 'rp-row' }, [
          sevBadge(i.severity), el('b', { text: `${i.issue_no} \u00B7 ${i.title}` }),
          el('span', { class: 'muted grow', text: i.unit || '' }),
          el('small', { class: 'muted', text: i.due_on ? `${t('rp.due')} ${fmtDate(i.due_on)}` : fmtDate(i.created_at) })])),
        el('a', { href: '#/reporting/issues', class: 'btn btn--quiet', text: t('v.viewAll') }),
      ]));
    }
  }

  function queueCard(rows) {
    return el('section', { class: 'card' }, [
      el('h3', { text: t('rp.tab_review') }),
      ...rows.map((r) => el('a', { href: `#/reporting/report/${r.id}`, class: 'rp-row' }, [
        statusBadge(r.status), el('b', { text: `${r.report_no} \u00B7 ${t('rp.tpl_' + r.template)}` }),
        el('span', { class: 'muted grow', text: `${r.unit} \u00B7 ${r.owner}` }),
        el('small', { class: 'muted', text: fmtDateTime(r.submitted_at) })])),
    ]);
  }

  /* ================================================================ my reports */
  async function mine() {
    clear(body);
    const tpls = await listReportTemplates();
    body.append(el('div', { class: 'row', style: 'gap:8px;flex-wrap:wrap;margin-bottom:10px;' },
      tpls.map((tp) => el('a', { href: `#/reporting/new/${tp.code}`, class: 'btn btn--secondary', text: t('rp.tpl_' + tp.code) }))));
    const rows = await reportingList('mine');
    body.append(listCard(t('rp.tab_mine'), rows, t('rp.mineNone')));
  }

  function listCard(title, rows, emptyText) {
    const c = el('section', { class: 'card' }, [el('h3', { text: title })]);
    if (!rows.length) { c.append(el('p', { class: 'muted', text: emptyText })); return c; }
    for (const r of rows) c.append(el('a', { href: `#/reporting/report/${r.id}`, class: 'rp-row' }, [
      statusBadge(r.status),
      el('b', { text: `${r.report_no} \u00B7 ${t('rp.tpl_' + r.template)}` }),
      el('span', { class: 'muted grow', text: `${r.unit} \u00B7 ${periodLabel(r)} \u00B7 v${r.version}` }),
      el('small', { class: `muted ${r.status === 'draft' && new Date(r.due_on) < new Date() ? 'rp-late' : ''}`,
        text: `${t('rp.due')} ${fmtDate(r.due_on)}` }),
    ]));
    return c;
  }

  function periodLabel(r) {
    if (r.template === 'monthly_leadership') return new Date(r.period_start).toLocaleDateString(undefined, { month: 'long', year: 'numeric' });
    if (r.template === 'weekly_pulse') return `${fmtDate(r.period_start)} \u2013 ${fmtDate(r.period_end)}`;
    return fmtDate(r.period_start);
  }

  /* ================================================================ new report */
  async function newReport(tpl) {
    clear(body);
    body.append(el('div', { class: 'state' }, [el('div', { class: 'spinner' })]));
    let r;
    try { r = await reportOpen(tpl, null, params.m || null, params.e || null); }
    catch (err) {
      clear(body);
      body.append(el('div', { class: 'card' }, [el('h3', { text: t('rp.tpl_' + tpl) }),
        el('p', { class: 'muted', text: err?.message || t('errors.load') }),
        el('a', { href: '#/reporting/dashboard', class: 'btn btn--quiet', text: t('v.viewingBack') })]));
      return;
    }
    location.replace(`#/reporting/report/${r.id}`);
    await reportView(r.id, r);
  }

  /* ================================================================ report view / editor */
  async function reportView(rid, preloaded) {
    clear(body);
    let r = preloaded || await reportGet(rid);
    const tpl = r.template_def;
    const editable = !!r.can_submit && ['draft', 'returned'].includes(r.status);
    const answers = { ...(r.answers || {}) };
    let evidence = [...(r.evidence || [])];
    const snap = r.snapshot || {};
    const ident = snap.identity || {};

    // header block (§6.1 auto-filled identity)
    const head = el('section', { class: 'card rp-head' }, [
      el('div', { class: 'row' }, [
        el('div', { class: 'grow' }, [
          el('h3', { text: `${t('rp.tpl_' + r.template)} \u00B7 ${r.report_no}` }),
          el('div', { class: 'muted', text: [
            r.unit_name || ident.unit, ident.level ? t(`v.lvl_${ident.level}`) : null,
            r.owner_name, periodLabel(r), `v${r.version}`].filter(Boolean).join(' \u00B7 ') }),
          el('div', { class: 'muted', text: `${t('rp.supervisor')}: ${ident.supervisor || t('rp.supervisorHq')} \u00B7 ${t('rp.due')} ${fmtDate(r.due_on)}` }),
        ]),
        statusBadge(r.status),
      ]),
      r.review_note ? el('div', { class: `rp-note rp-note--${r.status === 'returned' ? 'amber' : 'blue'}` }, [
        el('b', { text: t(`rp.st_${r.status}`) + ': ' }), el('span', { text: r.review_note })]) : null,
    ]);
    body.append(head);

    const form = el('div');
    body.append(form);
    const saveState = el('span', { class: 'muted rp-save' });

    // autosave (§28)
    const save = debounce(async () => {
      if (!editable) return;
      saveState.textContent = t('app.saving');
      try { await reportSave(r.id, answers, evidence, answers.__nil ?? null, answers.__nil_reason ?? null); saveState.textContent = t('rp.saved', { at: new Date().toLocaleTimeString() }); }
      catch (e) { saveState.textContent = e?.message || t('errors.save'); }
    }, 900);

    // nil declaration (§26.2)
    if (editable && r.template === 'monthly_leadership') {
      const nil = el('input', { type: 'checkbox', checked: !!r.is_nil });
      const reason = el('input', { class: 'input', value: r.nil_reason || '', placeholder: t('rp.nilReasonPh'), hidden: !r.is_nil });
      nil.addEventListener('change', () => { answers.__nil = nil.checked; reason.hidden = !nil.checked; save(); });
      reason.addEventListener('input', () => { answers.__nil_reason = reason.value; save(); });
      form.append(el('section', { class: 'card' }, [
        el('label', { class: 'row', style: 'gap:8px;' }, [nil, el('span', { text: t('rp.nilDeclare') })]), reason]));
    }

    // sections
    for (const sec of tpl.sections || []) {
      if (sec.conditional === 'finance' && !answers.has_finance && !editable) continue;
      const card = el('section', { class: 'card rp-sec' });
      card.append(el('h3', { text: `${sec.key}. ${sec.title}` }));
      for (const key of sec.auto || []) card.append(autoBlock(key, snap, r));
      if (sec.conditional === 'finance' && editable) {
        const fin = el('input', { type: 'checkbox', checked: !!answers.has_finance });
        fin.addEventListener('change', () => { answers.has_finance = fin.checked; wrap.hidden = !fin.checked; save(); });
        card.append(el('label', { class: 'row', style: 'gap:8px;margin-bottom:8px;' }, [fin, el('span', { text: t('rp.hasFinance') })]));
      }
      const wrap = el('div', { hidden: sec.conditional === 'finance' && !answers.has_finance });
      for (const f of sec.fields || []) wrap.append(fieldNode(f));
      card.append(wrap);
      form.append(card);
    }

    // evidence (§26.1)
    const evList = el('div');
    const drawEvidence = () => {
      clear(evList);
      if (!evidence.length) evList.append(el('p', { class: 'muted', text: t('rp.evidenceNone') }));
      for (const [i, e] of evidence.entries()) evList.append(el('div', { class: 'rp-row' }, [
        icon(e.path ? 'file' : 'clip', 16),
        e.path ? el('a', { href: '#', text: e.name, onclick: async (ev) => { ev.preventDefault(); try { window.open(await reportEvidenceUrl(e.path), '_blank'); } catch { toastError(t('errors.load')); } } })
          : el('a', { href: e.url, target: '_blank', rel: 'noopener', text: e.name || e.url }),
        el('span', { class: 'muted grow', text: e.note || '' }),
        editable ? el('button', { class: 'btn btn--quiet', text: '\u2715', onclick: () => { evidence.splice(i, 1); drawEvidence(); save(); } }) : null]));
    };
    const evCard = el('section', { class: 'card' }, [el('h3', { text: t('rp.evidence') }),
      el('p', { class: 'muted', text: t('rp.evidenceHint') }), evList]);
    if (editable) {
      const file = el('input', { type: 'file', hidden: true, accept: '.pdf,.jpg,.jpeg,.png,.doc,.docx,.xls,.xlsx,.csv,.txt' });
      file.addEventListener('change', async () => {
        const f = file.files && file.files[0]; if (!f) return;
        if (f.size > 8 * 1024 * 1024) { toastError(t('rp.evidenceSize')); return; }
        try { evidence.push(await uploadReportEvidence(r.id, f)); drawEvidence(); save(); }
        catch (e) { toastError(e?.message || t('errors.save')); }
      });
      const url = el('input', { class: 'input', placeholder: t('rp.evidenceUrlPh') });
      const note = el('input', { class: 'input', placeholder: t('rp.evidenceNotePh') });
      evCard.append(el('div', { class: 'row', style: 'gap:8px;flex-wrap:wrap;margin-top:8px;' }, [
        el('button', { class: 'btn btn--secondary', text: t('rp.evidenceUpload'), onclick: () => file.click() }), file,
        url, note,
        el('button', { class: 'btn btn--quiet', text: t('rp.evidenceAddLink'), onclick: () => {
          if (!/^https?:\/\//.test(url.value.trim())) { toastError(t('rp.evidenceUrlBad')); return; }
          evidence.push({ name: note.value.trim() || url.value.trim(), url: url.value.trim(), note: note.value.trim() });
          url.value = ''; note.value = ''; drawEvidence(); save();
        } }),
      ]));
    }
    drawEvidence();
    form.append(evCard);

    // contributions (§3.2 deputies contribute)
    const contribs = el('section', { class: 'card' }, [el('h3', { text: t('rp.contributions') }),
      ...(r.contributions || []).map((c) => el('div', { class: 'rp-row' }, [
        el('b', { text: c.name }), el('span', { class: 'grow', text: c.note }), el('small', { class: 'muted', text: fmtDateTime(c.at) })])),
      (r.contributions || []).length ? null : el('p', { class: 'muted', text: t('rp.contribNone') })]);
    if (['draft', 'returned'].includes(r.status)) {
      const note = el('textarea', { class: 'input', rows: '2', placeholder: t('rp.contribPh') });
      contribs.append(note, el('div', { class: 'row', style: 'margin-top:6px;' }, [el('span', { class: 'grow' }),
        el('button', { class: 'btn btn--secondary', text: t('rp.contribAdd'), onclick: async () => {
          if (note.value.trim().length < 3) return;
          try { await addReportContribution(r.id, note.value.trim()); toast(t('rp.contribSaved')); note.value = ''; r = await reportGet(r.id); await reportView(r.id, r); }
          catch (e) { toastError(e?.message || t('errors.save')); }
        } })]));
    }
    form.append(contribs);

    // history (§23.1, §27)
    if ((r.reviews || []).length) form.append(el('section', { class: 'card' }, [el('h3', { text: t('rp.history') }),
      ...r.reviews.map((v) => el('div', { class: 'rp-row' }, [
        el('span', { class: `vs-badge vs-badge--${STATUS_TONE[v.action === 'approve' ? 'approved' : v.action === 'return' ? 'returned' : 'submitted'] || 'blue'}`, text: t(`rp.act_${v.action}`) }),
        el('b', { text: v.by }), el('span', { class: 'grow muted', text: `v${v.version}${v.note ? ' \u00B7 ' + v.note : ''}` }),
        el('small', { class: 'muted', text: fmtDateTime(v.at) })]))]));

    // actions
    const actions = el('div', { class: 'row rp-actions' }, [saveState, el('span', { class: 'grow' })]);
    if (editable) {
      actions.append(el('button', { class: 'btn btn--primary', text: r.status === 'returned' ? t('rp.resubmit') : t('rp.submit'), onclick: async (e) => {
        e.target.disabled = true;
        try {
          await reportSave(r.id, answers, evidence, answers.__nil ?? null, answers.__nil_reason ?? null);
          const res = await reportSubmit(r.id);
          if (!res.ok) { showValidation(res); e.target.disabled = false; return; }
          if ((res.warnings || []).length) showValidation(res, true);
          toast(t('rp.submitted', { no: res.report_no }));
          r = await reportGet(r.id); await reportView(r.id, r);
        } catch (err) { toastError(err?.message || t('errors.save')); e.target.disabled = false; }
      } }));
    }
    if (r.can_review) {
      const note = el('textarea', { class: 'input', rows: '2', placeholder: t('rp.reviewNotePh') });
      const decide = async (decision) => {
        if (decision === 'return' && note.value.trim().length < 3) { toastError(t('rp.returnNeedsReason')); return; }
        try {
          const res = await reportReview(r.id, decision, note.value.trim() || null, true);
          toast(decision === 'approve' ? t('rp.approvedToast', { n: res.tasks_created || 0 }) : t(`rp.act_${decision}`));
          r = await reportGet(r.id); await reportView(r.id, r);
        } catch (err) { toastError(err?.message || t('errors.save')); }
      };
      form.append(el('section', { class: 'card rp-review' }, [
        el('h3', { text: t('rp.reviewTitle') }), note,
        el('div', { class: 'row', style: 'gap:8px;margin-top:8px;flex-wrap:wrap;' }, [
          el('button', { class: 'btn btn--primary', text: t('rp.approve'), onclick: () => decide('approve') }),
          el('button', { class: 'btn btn--secondary', text: t('rp.return'), onclick: () => decide('return') }),
          el('button', { class: 'btn btn--quiet', text: t('rp.escalate'), onclick: () => decide('escalate') }),
        ])]));
    }
    if (r.status === 'approved' && (r.can_review || r.owner_id === ctx.profile.id)) {
      actions.append(el('button', { class: 'btn btn--quiet', text: t('rp.newVersion'), onclick: async () => {
        if (!confirm(t('rp.newVersionConfirm'))) return;
        try { const nid = await reportNewVersion(r.id); location.hash = `#/reporting/report/${nid}`; }
        catch (err) { toastError(err?.message || t('errors.save')); }
      } }));
    }
    actions.append(el('button', { class: 'btn btn--quiet', text: t('rp.print'), onclick: () => window.print() }));
    form.append(actions);

    /* ---- helpers inside the editor ---- */
    function fieldNode(f) {
      const label = el('label', { class: 'field__label', text: f.label + (f.required ? ' *' : '') });
      let node;
      if (f.type === 'rows') node = rowsNode(f);
      else if (f.type === 'check') {
        node = el('input', { type: 'checkbox', checked: !!answers[f.key], disabled: !editable || null });
        node.addEventListener('change', () => { answers[f.key] = node.checked; save(); });
        return el('label', { class: 'field rp-check' }, [node, el('span', { text: f.label })]);
      } else if (f.type === 'select') {
        node = el('select', { class: 'select', disabled: !editable || null }, [el('option', { value: '', text: '\u2014' }),
          ...(f.options || []).map((o) => el('option', { value: o, text: o, selected: answers[f.key] === o || null }))]);
        node.addEventListener('change', () => { answers[f.key] = node.value; save(); });
      } else if (f.type === 'textarea') {
        node = el('textarea', { class: 'input', rows: '3', disabled: !editable || null });
        node.value = answers[f.key] || '';
        node.addEventListener('input', () => { answers[f.key] = node.value; save(); });
      } else {
        node = el('input', { class: 'input', type: f.type === 'number' ? 'number' : f.type === 'date' ? 'date' : 'text', disabled: !editable || null });
        node.value = answers[f.key] ?? '';
        node.addEventListener('input', () => { answers[f.key] = node.value; save(); });
      }
      return el('div', { class: 'field', 'data-key': f.key }, [label, node]);
    }

    function rowsNode(f) {
      const rows = Array.isArray(answers[f.key]) ? answers[f.key] : (answers[f.key] = []);
      const box = el('div', { class: 'rp-rows' });
      const drawRows = () => {
        clear(box);
        if (!rows.length) box.append(el('p', { class: 'muted', text: t('rp.rowsNone') }));
        rows.forEach((row, i) => {
          const line = el('div', { class: 'rp-rowline' });
          for (const c of f.cols) {
            let inp;
            if (c.type === 'select') inp = el('select', { class: 'select', disabled: !editable || null }, [el('option', { value: '', text: c.label }),
              ...c.options.map((o) => el('option', { value: o, text: o, selected: row[c.key] === o || null }))]);
            else inp = el('input', { class: 'input', type: c.type === 'date' ? 'date' : 'text', placeholder: c.label, disabled: !editable || null });
            if (c.type !== 'select') inp.value = row[c.key] ?? '';
            inp.addEventListener(c.type === 'select' ? 'change' : 'input', () => { row[c.key] = inp.value; save(); });
            line.append(inp);
          }
          if (editable) line.append(el('button', { class: 'btn btn--quiet', text: '\u2715', onclick: () => { rows.splice(i, 1); drawRows(); save(); } }));
          box.append(line);
        });
        if (editable && rows.length < (f.max || 10)) box.append(el('button', { class: 'btn btn--secondary', text: t('rp.addRow'),
          onclick: () => { rows.push({}); drawRows(); } }));
      };
      drawRows();
      return box;
    }

    function showValidation(res, warnOnly = false) {
      const items = [];
      for (const e of res.errors || []) items.push(el('li', { text: t('rp.err_' + e, { key: e }) === 'rp.err_' + e ? t('rp.errField', { key: labelFor(e) }) : t('rp.err_' + e) }));
      for (const w of res.warnings || []) items.push(el('li', { class: 'muted', text: w.startsWith('sensitive:') ? t('rp.warnSensitive') : t('rp.warn_' + w) }));
      openModal(warnOnly ? t('rp.warnTitle') : t('rp.blockedTitle'), el('div', {}, [
        el('p', { class: 'muted', text: warnOnly ? t('rp.warnHint') : t('rp.blockedHint') }),
        el('ul', { class: 'vs-list' }, items),
        el('div', { class: 'row' }, [el('span', { class: 'grow' }), el('button', { class: 'btn btn--primary', text: t('acc.done'), onclick: closeModal })])]));
      if (!warnOnly) {
        const first = (res.errors || [])[0];
        const node = form.querySelector(`[data-key="${first}"]`);
        if (node && typeof node.scrollIntoView === 'function') node.scrollIntoView({ behavior: 'smooth', block: 'center' });
      }
    }
    function labelFor(key) {
      for (const sec of tpl.sections || []) for (const f of sec.fields || []) if (f.key === key) return f.label;
      return key;
    }
  }

  /* ---- auto blocks from the snapshot (record once, §6.2) ---- */
  function autoBlock(key, snap, r) {
    const d = snap[key];
    const box = el('div', { class: 'rp-auto' });
    if (!d) { box.append(el('p', { class: 'muted', text: t('rp.autoNone') })); return box; }
    const kv = (obj, keys) => el('div', { class: 'rp-kv' }, keys.filter((k) => obj[k] !== undefined).map((k) =>
      el('div', {}, [el('b', { text: fmtNumber(Number(obj[k] || 0)) }), el('small', { text: t(`rp.m_${key}_${k}`) })])));
    if (key === 'identity') {
      box.append(el('div', { class: 'muted', text: [
        (d.chain || []).map((c) => c.name).join(' \u203A '),
        r.network, `${t('rp.period')}: ${fmtDate(r.period_start)} \u2013 ${fmtDate(r.period_end)}`].filter(Boolean).join(' \u00B7 ') }));
      return box;
    }
    if (key === 'issues') {
      box.append(kv(d, ['open', 'red_critical', 'resolved']));
      for (const i of (d.list || [])) box.append(el('div', { class: 'rp-row' }, [sevBadge(i.severity), el('span', { class: 'grow', text: `${i.issue_no} \u00B7 ${i.title}` }), el('small', { class: 'muted', text: t(`rp.ist_${i.status}`) })]));
      return box;
    }
    if (key === 'activities') {
      box.append(kv(d, ['total', 'people_reached', 'follow_ups_open', 'escalations']));
      const bc = d.by_category || {};
      if (Object.keys(bc).length) box.append(el('div', { class: 'muted', text: Object.entries(bc).map(([c, n]) => `${t('rp.cat_' + c)}: ${n}`).join(' \u00B7 ') }));
      return box;
    }
    const KEYS = {
      leadership: ['approved_positions', 'filled', 'vacant', 'active', 'inactive', 'appointments', 'exits'],
      pipeline: ['referrals', 'applications', 'in_activation', 'activation_completed', 'awaiting_assessment', 'awaiting_appointment'],
      membership: ['opening', 'new', 'active', 'inactive', 'exited', 'closing', 'units_active', 'referrals', 'women_reached'],
      tasks: ['completed', 'in_progress', 'not_started', 'awaiting_decision', 'overdue', 'due'],
      meetings: ['held', 'scheduled', 'attendance', 'action_reports'],
      programmes: ['planned', 'implemented', 'approved_reports', 'participants', 'evidence_missing'],
      learning: ['enrolled', 'started', 'completed', 'certified'],
      compliance: ['units', 'expected', 'submitted', 'on_time', 'approved', 'returned', 'overdue', 'not_submitted', 'evidence_complete'],
      support: ['opened', 'resolved', 'open'],
      meeting: [],
    };
    box.append(kv(d, KEYS[key] || Object.keys(d)));
    if (key === 'learning') box.append(el('p', { class: 'muted', text: t('rp.learningSource') }));
    return box;
  }

  /* ================================================================ operational records (§7) */
  async function records() {
    clear(body);
    const formCard = el('section', { class: 'card' }, [el('h3', { text: t('rp.recordActivity') }), el('p', { class: 'muted', text: t('rp.recordHint') })]);
    const cat = el('select', { class: 'select' }, ACT_CATS.map((c) => el('option', { value: c, text: t('rp.cat_' + c) })));
    const when = el('input', { class: 'input', type: 'datetime-local', value: new Date(Date.now() - new Date().getTimezoneOffset() * 60000).toISOString().slice(0, 16) });
    const what = el('textarea', { class: 'input', rows: '2', maxlength: '1000' });
    const people = el('input', { class: 'input', type: 'number', min: '0' });
    const pcat = el('input', { class: 'input', maxlength: '120', placeholder: t('rp.peopleCatPh') });
    const result = el('input', { class: 'input', maxlength: '1000' });
    const fu = el('input', { type: 'checkbox' });
    const fuAction = el('input', { class: 'input', maxlength: '500', placeholder: t('rp.fuActionPh') });
    const fuDue = el('input', { class: 'input', type: 'date' });
    const ev = el('input', { class: 'input', maxlength: '500', placeholder: t('rp.evidenceRefPh') });
    const esc = el('input', { type: 'checkbox' });
    const escCat = el('select', { class: 'select' }, ISSUE_CATS.map((c) => el('option', { value: c, text: c })));
    const err = el('p', { class: 'field__error', role: 'alert', hidden: true });
    const fld = (l, n) => el('div', { class: 'field' }, [el('label', { class: 'field__label', text: l }), n]);
    formCard.append(el('div', { class: 'form-grid' }, [
      fld(t('rp.actCategory'), cat), fld(t('rp.actWhen'), when)]),
      fld(t('rp.actWhat'), what),
      el('div', { class: 'form-grid' }, [fld(t('rp.actPeople'), people), fld(t('rp.actPeopleCat'), pcat)]),
      fld(t('rp.actResult'), result),
      el('label', { class: 'row', style: 'gap:8px;margin:6px 0;' }, [fu, el('span', { text: t('rp.actFollowUp') })]),
      el('div', { class: 'form-grid' }, [fld(t('rp.actFuAction'), fuAction), fld(t('rp.actFuDue'), fuDue)]),
      fld(t('rp.actEvidence'), ev),
      el('label', { class: 'row', style: 'gap:8px;margin:6px 0;' }, [esc, el('span', { text: t('rp.actEscalate') })]),
      fld(t('rp.actEscCat'), escCat), err,
      el('div', { class: 'row' }, [el('span', { class: 'grow' }), el('button', { class: 'btn btn--primary', text: t('rp.actSave'), onclick: async (e) => {
        if (what.value.trim().length < 3 || result.value.trim().length < 1) { err.textContent = t('rp.actNeed'); err.hidden = false; return; }
        err.hidden = true; e.target.disabled = true;
        try {
          await addActivityRecord({
            category: cat.value, occurred_at: new Date(when.value).toISOString(), what: what.value.trim(),
            people_reached: people.value === '' ? null : Number(people.value), people_category: pcat.value.trim() || null,
            result: result.value.trim(), follow_up: fu.checked, follow_up_action: fu.checked ? fuAction.value.trim() || null : null,
            follow_up_due: fu.checked && fuDue.value ? fuDue.value : null, evidence_ref: ev.value.trim() || null,
            escalation: esc.checked, escalation_category: esc.checked ? escCat.value : null,
          });
          toast(t('rp.actSaved')); what.value = ''; result.value = ''; people.value = ''; ev.value = ''; fu.checked = false; esc.checked = false;
          await drawList();
        } catch (ex) { err.textContent = ex?.message || t('errors.save'); err.hidden = false; }
        e.target.disabled = false;
      } })]));
    body.append(formCard);
    const list = el('section', { class: 'card' }, [el('h3', { text: t('rp.recentRecords') })]);
    body.append(list);
    async function drawList() {
      const rows = await listActivityRecords({ limit: 40 });
      clear(list); list.append(el('h3', { text: t('rp.recentRecords') }));
      if (!rows.length) list.append(el('p', { class: 'muted', text: t('rp.recordsNone') }));
      for (const a of rows) list.append(el('div', { class: 'rp-row' }, [
        el('span', { class: 'vs-badge vs-badge--blue', text: t('rp.cat_' + a.category) }),
        el('div', { class: 'grow' }, [el('b', { text: a.what }),
          el('div', { class: 'muted', text: [a.result, a.people_reached != null ? t('rp.reachedN', { n: a.people_reached }) : null,
            a.follow_up ? t('rp.followUpBy', { d: a.follow_up_due ? fmtDate(a.follow_up_due) : '\u2014' }) : null].filter(Boolean).join(' \u00B7 ') })]),
        el('small', { class: 'muted', text: `${a.who ? a.who.first_name + ' ' + a.who.last_name : ''} \u00B7 ${a.unit?.name || ''} \u00B7 ${fmtDateTime(a.occurred_at)}` })]));
    }
    await drawList();
  }

  /* ================================================================ review queue (§25.2) */
  async function review() {
    clear(body);
    const rows = await reportingList('supervise');
    const queue = rows.filter((r) => ['submitted', 'under_review', 'escalated'].includes(r.status));
    const returned = rows.filter((r) => r.status === 'returned');
    body.append(listCard(t('rp.tab_review'), queue, t('rp.reviewNone')));
    body.append(listCard(t('rp.returnedTitle'), returned, t('rp.returnedNone')));
  }

  /* ================================================================ compliance (§9.3, §25.3) */
  async function compliance() {
    clear(body);
    const units = await listOrgUnits().catch(() => []);
    const rootSel = el('select', { class: 'select' });
    const period = el('input', { class: 'input', type: 'month' });
    const netSel = el('select', { class: 'select' }, ['WGMN', 'WNNN'].map((n) => el('option', { value: n, text: n })));
    const fill = (rows) => {
      clear(rootSel);
      rootSel.append(el('option', { value: '', text: isHq ? t('rp.allCountries') : t('rp.myScope') }));
      for (const u of rows.filter((x) => x.level !== 'headquarters' && x.level !== 'chapter').sort((a, b) => a.name.localeCompare(b.name)))
        rootSel.append(el('option', { value: u.id, text: `${u.name} (${t('v.lvl_' + u.level)})` }));
    };
    fill(units);
    const tbl = el('div');
    const summary = el('div', { class: 'vs-mini' });
    const load = async () => {
      clear(tbl); tbl.append(el('div', { class: 'state' }, [el('div', { class: 'spinner' })]));
      let d;
      try { d = await reportingCompliance(rootSel.value || null, period.value ? `${period.value}-01` : null, netSel.value); }
      catch (err) { clear(tbl); tbl.append(el('p', { class: 'muted', text: err?.message || t('errors.load') })); return; }
      clear(summary);
      const pct = (a, b) => (b ? `${Math.round((100 * a) / b)}%` : '\u2014');
      summary.append(mini(t('rp.sExpected'), d.expected), mini(t('rp.sSubmitted'), d.submitted, 'green'),
        mini(t('rp.cOnTime'), pct(d.on_time, d.expected)), mini(t('rp.sApproved'), d.approved, 'green'),
        mini(t('rp.sOverdue'), d.overdue, d.overdue ? 'red' : 'green'),
        mini(t('rp.periodDue'), fmtDate(d.period?.due)));
      clear(tbl);
      const rows = d.rows || [];
      if (!rows.length) { tbl.append(el('p', { class: 'muted', text: t('rp.complianceNone') })); return; }
      tbl.append(el('div', { class: 'table-wrap' }, [el('table', { class: 'vs-table' }, [
        el('thead', {}, [el('tr', {}, [el('th', { text: t('st.unit') }), el('th', { text: t('rp.leader') }), el('th', { text: t('v.thStatus') }),
          el('th', { text: t('rp.submittedAt') }), el('th', { text: t('rp.evidence') }), el('th', { text: '' })])]),
        el('tbody', {}, rows.map((r) => el('tr', { class: r.status === 'not_started' && d.period && new Date(d.period.due) < new Date() ? 'st-vacant' : '' }, [
          el('td', {}, [el('b', { text: r.unit }), el('div', { class: 'muted', text: `${t('v.lvl_' + r.level)}${r.children ? ' \u00B7 ' + t('rp.childUnits', { n: r.children }) : ''}` })]),
          el('td', { text: r.leader || t('rp.noLeader') }),
          el('td', {}, [statusBadge(r.status)]),
          el('td', { text: r.submitted_at ? `${fmtDateTime(r.submitted_at)}${r.on_time ? '' : ' \u00B7 ' + t('rp.late')}` : '' }),
          el('td', { text: r.evidence == null ? '' : String(r.evidence) }),
          el('td', {}, [r.report_id ? el('a', { href: `#/reporting/report/${r.report_id}`, class: 'btn btn--quiet', text: t('v.view') }) : null,
            r.children ? el('button', { class: 'btn btn--quiet', text: t('rp.drill'), onclick: () => { rootSel.value = r.unit_id; load(); } }) : null]),
        ])))])]));
    };
    for (const s of [rootSel, period, netSel]) s.addEventListener('change', load);
    const tools = el('div', { class: 'row', style: 'gap:8px;flex-wrap:wrap;' }, [rootSel, period, isHq ? netSel : null]);
    if (isHq) tools.append(el('button', { class: 'btn btn--secondary', text: t('rp.runReminders'), onclick: async () => {
      try { const res = await reportingRemindersRun(); toast(t('rp.remindersDone', { n: res.notices, e: res.escalated })); }
      catch (err) { toastError(err?.message || t('errors.save')); }
    } }), el('button', { class: 'btn btn--quiet', text: t('rp.configure'), onclick: configModal }));
    body.append(el('section', { class: 'card' }, [el('h3', { text: t('rp.tab_compliance') }), el('p', { class: 'muted', text: t('rp.complianceHint') }), tools, summary, tbl]));
    await load();
  }

  async function configModal() {
    const cfg = await getReportingConfig();
    const f = {};
    const row = (k, label) => { f[k] = el('input', { class: 'input', value: JSON.stringify(cfg[k] ?? null) }); return el('div', { class: 'field' }, [el('label', { class: 'field__label', text: label }), f[k]]); };
    openModal(t('rp.configure'), el('div', {}, [
      el('p', { class: 'muted', text: t('rp.configHint') }),
      row('monthly_due_day', t('rp.cfgDueDay')), row('reminder_days_before', t('rp.cfgBefore')), row('overdue_days', t('rp.cfgOverdue')),
      row('supervisor_alert_overdue_day', t('rp.cfgSupDay')), row('escalate_overdue_day', t('rp.cfgEscDay')),
      row('weekly_pulse_levels', t('rp.cfgPulseLevels')), row('weekly_pulse_countries', t('rp.cfgPulseCountries')),
      el('div', { class: 'row' }, [el('span', { class: 'grow' }), el('button', { class: 'btn btn--primary', text: t('acc.save'), onclick: async () => {
        try { for (const [k, n] of Object.entries(f)) await setReportingConfig(k, JSON.parse(n.value)); closeModal(); toast(t('acc.saved')); }
        catch (err) { toastError(err?.message || t('errors.save')); }
      } })])]));
  }

  /* ================================================================ issues (§17) */
  async function issues() {
    clear(body);
    const title = el('input', { class: 'input', maxlength: '200' });
    const cat = el('select', { class: 'select' }, ISSUE_CATS.map((c) => el('option', { value: c, text: c })));
    const sev = el('select', { class: 'select' }, SEV.map((s) => el('option', { value: s, text: t('rp.sev_' + s), selected: s === 'amber' || null })));
    const impact = el('textarea', { class: 'input', rows: '2', maxlength: '2000' });
    const action = el('textarea', { class: 'input', rows: '2', maxlength: '2000' });
    const decision = el('input', { class: 'input', maxlength: '1000' });
    const route = el('select', { class: 'select' }, ['supervisor', 'country', 'hofco', 'hq', 'management'].map((r) => el('option', { value: r, text: t('rp.route_' + r) })));
    const due = el('input', { class: 'input', type: 'date' });
    const err = el('p', { class: 'field__error', role: 'alert', hidden: true });
    const fld = (l, n) => el('div', { class: 'field' }, [el('label', { class: 'field__label', text: l }), n]);
    body.append(el('section', { class: 'card' }, [el('h3', { text: t('rp.raiseIssue') }),
      el('p', { class: 'muted', text: t('rp.issueHint') }),
      fld(t('rp.issueTitle'), title), el('div', { class: 'form-grid' }, [fld(t('rp.issueCategory'), cat), fld(t('rp.issueSeverity'), sev)]),
      fld(t('rp.issueImpact'), impact), fld(t('rp.issueAction'), action), fld(t('rp.issueDecision'), decision),
      el('div', { class: 'form-grid' }, [fld(t('rp.issueRoute'), route), fld(t('rp.issueDue'), due)]), err,
      el('div', { class: 'row' }, [el('span', { class: 'grow' }), el('button', { class: 'btn btn--primary', text: t('rp.issueSave'), onclick: async (e) => {
        if (title.value.trim().length < 3) { err.textContent = t('rp.issueNeed'); err.hidden = false; return; }
        if (['red', 'critical'].includes(sev.value) && action.value.trim().length < 3) { err.textContent = t('rp.err_risks_red_action_owner'); err.hidden = false; return; }
        err.hidden = true; e.target.disabled = true;
        try {
          const r = await addIssue({ title: title.value.trim(), category: cat.value, severity: sev.value, impact: impact.value.trim() || null,
            action_taken: action.value.trim() || null, decision_required: decision.value.trim() || null, escalated_to: route.value, due_on: due.value || null });
          toast(t('rp.issueSaved', { no: r.issue_no })); title.value = ''; impact.value = ''; action.value = ''; decision.value = '';
          await drawIssues();
        } catch (ex) { err.textContent = ex?.message || t('errors.save'); err.hidden = false; }
        e.target.disabled = false;
      } })])]));
    const list = el('section', { class: 'card' });
    body.append(list);
    async function drawIssues() {
      const rows = await listIssues({ open: false, limit: 100 });
      clear(list); list.append(el('h3', { text: t('rp.issuesTitle') }));
      if (!rows.length) { list.append(el('p', { class: 'muted', text: t('rp.issuesNone') })); return; }
      for (const i of rows) {
        const st = el('select', { class: 'select', style: 'width:auto;' }, ['open', 'in_progress', 'awaiting_decision', 'resolved', 'closed'].map((s) =>
          el('option', { value: s, text: t('rp.ist_' + s), selected: s === i.status || null })));
        st.addEventListener('change', async () => { try { await updateIssue(i.id, { status: st.value }); toast(t('acc.saved')); } catch (ex) { toastError(ex?.message || t('errors.save')); } });
        list.append(el('div', { class: 'rp-row' }, [sevBadge(i.severity),
          el('div', { class: 'grow' }, [el('b', { text: `${i.issue_no} \u00B7 ${i.title}` }),
            el('div', { class: 'muted', text: [i.category, i.unit?.name, i.who ? `${i.who.first_name} ${i.who.last_name}` : null, i.escalated_to ? t('rp.route_' + i.escalated_to) : null,
              i.due_on ? `${t('rp.due')} ${fmtDate(i.due_on)}` : null].filter(Boolean).join(' \u00B7 ') }),
            i.decision_required ? el('div', { class: 'muted', text: `${t('rp.issueDecision')}: ${i.decision_required}` }) : null]),
          st]));
      }
    }
    await drawIssues();
  }

  /* ================================================================ archive (§27) */
  async function archive() {
    clear(body);
    const rows = await reportingList('archive', null, 200);
    body.append(el('p', { class: 'muted', text: t('rp.archiveHint') }));
    body.append(listCard(t('rp.tab_archive'), rows, t('rp.archiveNone')));
  }

  /* ---- small helpers ---- */
  function mini(label, value, tone = '') {
    return el('div', { class: `vs-mini__t ${tone ? 'vs-mini__t--' + tone : ''}` }, [el('b', { text: String(value ?? 0) }), el('small', { text: label })]);
  }
}

export function statusBadge(s) {
  return el('span', { class: `vs-badge vs-badge--${toneClass(STATUS_TONE[s] || 'grey')}`, text: t(`rp.st_${s}`) });
}
export function sevBadge(s) {
  const tone = s === 'critical' || s === 'red' ? 'red' : s === 'amber' ? 'amber' : 'green';
  return el('span', { class: `vs-badge vs-badge--${tone}`, text: t('rp.sev_' + s) });
}
function toneClass(tone) {
  return { green: 'green', blue: 'blue', amber: 'amber', red: 'red', grey: 'violet' }[tone] || 'blue';
}
