import { el, esc, clear } from '../core/dom.js';
import { t, fmtNumber, fmtDate } from '../core/i18n.js';
import { getReports, listOrgUnits, getProgrammeImpact, activationReport,
  leadersAtlas,
  activationIndividualReport,
  getAutomationInsights, getCourseStats, teamAccountability,
  peopleAnalytics, countryMemberStats } from '../core/db.js';
import { openModal } from '../components/modal.js';
import { donut, bars, line } from '../components/charts.js';
import { renderShell } from '../components/layout.js';
import { icon } from '../components/icons.js';

export async function render(root, _params, ctx) {
  const shell = renderShell(root, {
    profile: ctx.profile, modules: ctx.modules, titleKey: 'nav.reports',
  });
  const out = shell.outlet;

  out.append(el('div', { class: 'state' }, [
    el('div', { class: 'spinner' }), el('p', { text: t('app.loading') }),
  ]));

  let r, units = [];
  try {
    [r, units] = await Promise.all([getReports(), listOrgUnits()]);
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

  clear(out);
  out.append(el('p', { class: 'muted mb-4', text: t('rep.scopeNote') }));

  /* ---- 14-day activation accountability (Phase 89) ---- */
  out.append(section(t('rep.actTitle')));
  const actBox = el('div', { class: 'mb-4' });
  out.append(actBox);
  actBox.append(el('div', { class: 'state' }, [el('div', { class: 'spinner' })]));
  async function openIndividualReport(journeyId, name) {
    const box = el('div');
    box.append(el('div', { class: 'state' }, [el('div', { class: 'spinner' })]));
    openModal(t('rep.reportModalTitle', { name }), box);
    try {
      const r = await activationIndividualReport(journeyId);
      clear(box);
      if (r.error) {
        box.append(el('p', { class: 'muted', text: t('errors.load') }));
        return;
      }
      const meta = el('p', { class: 'muted', style: 'font-size:13px;' });
      meta.innerHTML = `${esc(r.role_applied || '—')}
        ${[r.country, r.state, r.lga].filter(Boolean).length
          ? '· ' + esc([r.country, r.state, r.lga].filter(Boolean).join(' · ')) : ''}
        <br>${esc(t('rep.reportStarted'))}: ${r.started_at ? esc(fmtDate(r.started_at)) : '—'}
        · ${esc(t('rep.reportConcluded'))}: ${r.concluded_at ? esc(fmtDate(r.concluded_at)) : '—'}`;
      box.append(meta);

      const recCard = el('div', { class: 'card', style:
        'background:rgba(124,181,24,.10);border:1px solid #7CB518;margin:10px 0;' });
      recCard.innerHTML = `<b>${esc(t('rep.reportRecommendation'))}</b>
        <p style="margin:6px 0 0;font-size:14px;">${esc(r.recommendation)}</p>`;
      box.append(recCard);

      const scoreLine = el('p', { style: 'font-size:14px;' });
      scoreLine.innerHTML = `<b>${esc(t('rep.reportScore'))}:</b> ${esc(String(r.score ?? '—'))}/100
        &nbsp;·&nbsp; ${r.gate6_met ? '✓' : '✗'} ${esc(t('rep.reportGate6'))}
        &nbsp;·&nbsp; ${r.gate13_met ? '✓' : '✗'} ${esc(t('rep.reportGate13'))}`;
      box.append(scoreLine);

      const dayLabel = {
        completed_on_time: t('rep.dayOnTime'), completed_late: t('rep.dayLate'),
        partially_done: t('rep.dayPartial'), missed: t('rep.dayMissed'),
        not_yet_reached: t('rep.dayFuture'), no_required_work: '',
      };
      const daysTable = el('div', { style: 'overflow-x:auto;margin-top:10px;' });
      daysTable.innerHTML = `<table class="table" style="font-size:12px;">
        <thead><tr><th>${esc(t('rep.reportDay'))}</th>
          <th>${esc(t('rep.reportDayStatus'))}</th></tr></thead>
        <tbody>${(r.days || []).filter((d) => d.status !== 'no_required_work')
          .map((d) => `<tr><td>${esc(String(d.day))}</td>
            <td>${esc(dayLabel[d.status] || d.status)}</td></tr>`).join('')}
        </tbody></table>`;
      box.append(daysTable);
    } catch {
      clear(box);
      box.append(el('p', { class: 'muted', text: t('errors.load') }));
    }
  }

  activationReport().then((rows) => {
    clear(actBox);
    rows = rows || [];
    const by = (v) => rows.filter((x) => x.verdict === v).length;
    actBox.append(el('div', { class: 'stats' }, [
      tile(t('rep.actInProgress'), by('in_progress'), '', 'chart'),
      tile(t('rep.actPassed'), by('passed'), 'stat--green', 'check'),
      tile(t('rep.actFailed'), by('failed'), '', 'chart'),
      tile(t('rep.actNotStarted'), by('not_started'), '', 'userplus'),
    ]));
    const dlRow = el('div', { class: 'row mb-3',
      style: 'gap:10px;flex-wrap:wrap;align-items:center;' });
    // Established leaders (CR/SC/deputies) never take the 14-day journey,
    // so the exports fetch them separately for their own section. If the
    // fetch fails the exports still work, applicants only.
    const leadersPromise = leadersAtlas().catch(() => []);
    const mkDl = (labelKey, fn) => {
      const b = el('button', { class: 'btn btn--secondary',
        text: t(labelKey) });
      b.addEventListener('click', async () => {
        b.disabled = true;
        const original = b.textContent;
        b.textContent = t('rep.dlWorking');
        try {
          const mod = await import('../core/activationexport.js');
          const leaders = (await leadersPromise) || [];
          await fn(mod, leaders);
        } catch {
          b.textContent = t('rep.dlFailed');
          setTimeout(() => { b.textContent = original; }, 2500);
          b.disabled = false;
          return;
        }
        b.textContent = original;
        b.disabled = false;
      });
      return b;
    };
    dlRow.append(
      mkDl('rep.dlExcel', (m, l) => m.downloadActivationExcel(rows, l)),
      mkDl('rep.dlPdf', (m, l) => m.downloadActivationPdf(rows, l)),
      el('span', { class: 'muted', style: 'font-size:11px;',
        text: t('rep.dlHint') }));
    actBox.append(dlRow);
    if (!rows.length) {
      actBox.append(el('p', { class: 'muted', text: t('rep.actNone') }));
      return;
    }
    const vb = (v, day) => {
      const cls = v === 'passed' ? 'active'
        : v === 'failed' ? 'exited'
        : v === 'in_progress' ? 'pipeline' : 'inactive';
      const txt = v === 'in_progress'
        ? t('rep.actDayN', { n: day }) : t(`rep.act.${v}`);
      return `<span class="badge badge--${cls}">${esc(txt)}</span>`;
    };
    const card = el('div', { class: 'card',
      style: 'overflow-x:auto;' });
    const rowsHtml = rows.map((x) => `<tr>
      <td><b>${esc(x.name || '')}</b><br>
        <span class="muted" style="font-size:11px;">${esc(x.membership_no || '')}</span></td>
      <td>${esc(x.role_applied || '—')}</td>
      <td>${esc([x.country, x.state, x.lga].filter(Boolean).join(' · ') || '—')}</td>
      <td style="text-align:center;">${x.verdict === 'not_started' ? '—' : esc(String(x.day_reached))}</td>
      <td>${esc(String(x.items_done))}/${esc(String(x.items_required))}</td>
      <td>${vb(x.verdict, x.day_reached)}</td>
      <td style="text-align:center;">
        ${x.report_ready
          ? `<button class="btn btn--secondary" data-journey="${esc(x.journey_id)}" data-name="${esc(x.name)}">${esc(t('rep.viewReport'))}</button>`
          : `<span class="muted" style="font-size:11px;">${esc(t('rep.reportNotYet'))}</span>`}
      </td>
      <td style="text-align:center;">${x.has_cv ? '✓' : ''}</td>
      <td class="muted" style="font-size:12px;">${x.last_seen
        ? esc(fmtDate(x.last_seen)) : esc(t('rep.accNever'))}</td>
    </tr>`).join('');
    card.innerHTML = `<table class="table">
      <thead><tr>
        <th>${esc(t('rep.actName'))}</th>
        <th>${esc(t('rep.actRole'))}</th>
        <th>${esc(t('rep.actWhere'))}</th>
        <th>${esc(t('rep.actDay'))}</th>
        <th>${esc(t('rep.actProgress'))}</th>
        <th>${esc(t('rep.actVerdict'))}</th>
        <th>${esc(t('rep.actReport'))}</th>
        <th>CV</th>
        <th>${esc(t('rep.actSeen'))}</th>
      </tr></thead><tbody>${rowsHtml}</tbody></table>`;
    card.querySelectorAll('button[data-journey]').forEach((btn) => {
      btn.addEventListener('click', () => openIndividualReport(
        btn.dataset.journey, btn.dataset.name));
    });
    actBox.append(card);
  }).catch(() => {
    clear(actBox);
    actBox.append(el('p', { class: 'muted', text: t('rep.actNeeds68') }));
  });

  /* ---- membership ---- */
  const m = r.membership || {};
  out.append(
    section(t('rep.membership')),
    el('div', { class: 'stats' }, [
      tile(t('rep.people'), m?.total ?? 0, '', 'users'),
      tile(t('rep.activeFamily'), m.active_family, 'stat--green', 'users'),
      tile(t('rep.pipeline'), m.pipeline, '', 'userplus'),
      tile('WGMN', m.wgmn, '', 'users'),
      tile('WNNN', m.wnnn, 'stat--green', 'users'),
    ]),
    el('div', { class: 'grid-2 mb-4' }, [
      el('div', { class: 'card' }, [
        el('div', { class: 'card__head' }, [
          el('h2', { text: t('rep.byStatus') })]),
        donut(Object.entries(m.by_status || {}).map(([k, v]) =>
          ({ label: t(`status.${k}`), value: v }))),
      ]),
      el('div', { class: 'card' }, [
        el('div', { class: 'card__head' }, [
          el('h2', { text: t('rep.growthTitle') })]),
        line((r.growth || []).map((g) =>
          ({ label: g.month.slice(5), value: Number(g.joins) }))),
      ]),
    ])
  );

  /* ---- recruitment ---- */
  const rec = r.recruitment || {};
  const decided = (rec.approved ?? 0) + (rec.rejected ?? 0);
  out.append(
    section(t('rep.recruitment')),
    el('div', { class: 'stats' }, [
      tile(t('rep.applications'), rec?.total ?? 0, '', 'userplus'),
      tile(t('rep.openApps'), rec.open, '', 'file'),
      tile(t('rep.approvedApps'), rec.approved, 'stat--green', 'check'),
      tile(t('rep.approvalRate'),
        decided ? Math.round((rec.approved / decided) * 100) + '%' : '—',
        'stat--green'),
    ]),
    el('div', { class: 'card mb-4' }, [
      el('div', { class: 'card__head' }, [
        el('h2', { text: t('rep.funnel') })]),
      bars(['submitted', 'under_review', 'recommended', 'approved', 'rejected']
        .map((k) => ({ label: t(`appstatus.${k}`),
          value: (rec.by_status || {})[k] || 0 }))),
    ])
  );

  /* ---- tasks ---- */
  const tk = r.tasks;
  out.append(
    section(t('rep.tasks')),
    el('div', { class: 'stats' }, [
      tile(t('rep.openTasks'), tk.open, '', 'tasks'),
      tile(t('rep.overdueTasks'), tk.overdue,
        tk.overdue > 0 ? '' : 'stat--green', 'tasks'),
      tile(t('rep.awaitingReview'), tk.awaiting_review, '', 'tasks'),
      tile(t('rep.completed30'), tk.completed_window, 'stat--green', 'check'),
    ]),
    el('div', { class: 'card mb-4' }, [
      el('div', { class: 'card__head' }, [
        el('h2', { text: t('rep.taskMix') })]),
      donut([
        { label: t('rep.openTasks'), value: tk.open || 0 },
        { label: t('rep.overdueTasks'), value: tk.overdue || 0 },
        { label: t('rep.awaitingReview'), value: tk.awaiting_review || 0 },
        { label: t('rep.completed30'), value: tk.completed_window || 0 },
      ]),
    ])
  );

  /* ---- meetings & attendance ---- */
  const mt = r.meetings;
  const attRate = mt.marks > 0 ? Math.round((mt.present / mt.marks) * 100) : null;
  out.append(
    section(t('rep.meetings')),
    el('div', { class: 'stats' }, [
      tile(t('rep.held30'), mt.held, '', 'calendar'),
      tile(t('rep.upcoming'), mt.scheduled_upcoming, '', 'calendar'),
      tile(t('rep.attendanceRate'), attRate === null ? '—' : attRate + '%',
        'stat--green', 'check'),
    ])
  );
  if (attRate !== null) {
    out.append(el('div', { class: 'card mb-4' }, [
      bar(t('rep.attendanceRate'), attRate,
        t('rep.attendanceDetail', { p: fmtNumber(mt.present),
          n: fmtNumber(mt.marks) })),
    ]));
  }

  /* ---- leadership coverage ---- */
  out.append(section(t('rep.coverage')));
  const covCard = el('div', { class: 'card mb-4' });
  if (r.coverage.length === 0) {
    covCard.append(el('p', { class: 'muted', text: t('rep.noUnits') }));
  }
  for (const row of r.coverage) {
    const pct = row.units > 0
      ? Math.round((row.covered / row.units) * 100) : 0;
    covCard.append(bar(
      t(`org.${row.level}`), pct,
      t('rep.coverageDetail', { c: fmtNumber(row.covered),
        n: fmtNumber(row.units) })));
  }
  out.append(covCard);

  /* ---- programme impact ---- */
  try {
    const impact = await getProgrammeImpact();
    if (impact.length > 0) {
      out.append(section(t('rep.programmes')));
      const wrap = el('div', { class: 'card mb-4 table-wrap' });
      const tblEl = el('table', { class: 'table' });
      tblEl.innerHTML = `
        <thead><tr>
          <th>${esc(t('rep.progName'))}</th>
          <th>${esc(t('rep.progEvents'))}</th>
          <th>${esc(t('rep.progBeneficiaries'))}</th>
          <th>${esc(t('rep.progServices'))}</th>
        </tr></thead>
        <tbody>${impact.map((row) => `
          <tr style="cursor:default;">
            <td><strong>${esc(row.name === row.code ? row.code
              : row.code + ' — ' + row.name)}</strong></td>
            <td>${esc(fmtNumber(row.events))}</td>
            <td>${esc(fmtNumber(row.beneficiaries))}</td>
            <td>${esc(fmtNumber(row.services))}</td>
          </tr>`).join('')}</tbody>`;
      wrap.append(tblEl);
      out.append(wrap);
    }
  } catch { /* programmes module may not be migrated yet */ }

  /* ---- LIVE OPERATIONS (HQ): who, what, where — refreshed every 20s ---- */
  try {
    await peopleAnalytics();  // permission probe; throws for non-HQ
    out.append(section(t('rep.liveOps')));
    const liveCard = el('div', { class: 'card mb-4' });
    liveCard.append(el('p', { class: 'muted mb-2', text: t('rep.liveHint') }));
    const mapBox = el('div', { class: 'mb-4', style: 'max-width:640px;' });
    const filterRow = el('div', { class: 'row mb-2',
      style: 'gap:8px;flex-wrap:wrap;align-items:center;' });
    const countrySel = el('select', { class: 'select' });
    const liveStamp = el('span', { class: 'muted',
      style: 'font-size:12px;' });
    filterRow.append(countrySel, el('span', { class: 'grow' }), liveStamp);
    const tableBox = el('div', { style: 'overflow-x:auto;' });
    liveCard.append(mapBox, filterRow, tableBox);
    out.append(liveCard);

    let people = [];
    let countries = [];
    async function refreshLive() {
      try {
        [people, countries] = await Promise.all([
          peopleAnalytics(), countryMemberStats()]);
      } catch { return; }
      liveStamp.textContent = t('rep.liveAt',
        { t: new Date().toLocaleTimeString() });
      // country filter options
      const cur = countrySel.value;
      clear(countrySel);
      countrySel.append(el('option', { value: '', text: t('rep.allCountries') }));
      for (const c of [...new Set(people.map((x) => x.country).filter(Boolean))]
        .sort()) {
        countrySel.append(el('option', { value: c, text: c }));
      }
      countrySel.value = cur;
      paintTable();
      paintMap();
    }
    function paintTable() {
      const flt = countrySel.value;
      const rows = people.filter((x) => !flt || x.country === flt);
      clear(tableBox);
      const tb = el('table', { class: 'table' });
      tb.innerHTML = `<thead><tr>
        <th>${esc(t('rep.colName'))}</th><th>${esc(t('rep.colRole'))}</th>
        <th>${esc(t('rep.colWhere'))}</th><th>${esc(t('rep.colJourney'))}</th>
        <th>${esc(t('rep.colCourses'))}</th><th>${esc(t('rep.colTasks'))}</th>
        <th>${esc(t('rep.colSeen'))}</th></tr></thead>`;
      const body = el('tbody');
      for (const x of rows.slice(0, 300)) {
        const tr = el('tr');
        const j = x.journey_status
          ? `${x.journey_done}/${x.journey_required}`
            + (x.journey_day ? ` · ${t('rep.day')} ${x.journey_day}` : '')
            + ` (${x.journey_status})`
          : '—';
        tr.innerHTML = `
          <td><strong>${esc(x.name)}</strong>${x.is_staff
            ? ` <span class="badge badge--pipeline">${esc(t('rep.staffTag'))}</span>` : ''}</td>
          <td>${esc(x.role || '—')}</td>
          <td>${esc([x.unit, x.country].filter(Boolean).join(' · ') || '—')}</td>
          <td>${esc(j)}</td>
          <td>${esc(String(x.courses_done))}/${esc(String(x.courses_enrolled))}</td>
          <td>${esc(String(x.tasks_open))}${Number(x.tasks_overdue) > 0
            ? ` <span class="badge badge--exited">${esc(String(x.tasks_overdue))} ${esc(t('rep.late'))}</span>` : ''}</td>
          <td class="muted">${x.last_seen
            ? esc(fmtDate(x.last_seen)) : esc(t('rep.accNever'))}</td>`;
        body.append(tr);
      }
      tb.append(body);
      tableBox.append(tb);
    }
    async function paintMap() {
      try {
        const res = await fetch('/assets/vendor/africa.svg?v=48',
          { cache: 'no-cache' });
        const svgText = await res.text();
        mapBox.innerHTML = svgText;
        const svg = mapBox.querySelector('svg');
        if (!svg) return;
        if (!svg.getAttribute('viewBox')) {
          const bb = svg.getBBox();
          svg.setAttribute('viewBox',
            `${bb.x} ${bb.y} ${bb.width} ${bb.height}`);
        }
        svg.style.width = '100%'; svg.style.height = 'auto';
        const max = Math.max(1, ...countries.map((c) => Number(c.members)));
        for (const c of countries) {
          const elx = svg.querySelector('#' + CSS.escape(c.iso))
            || svg.querySelector('#' + CSS.escape(String(c.iso).toLowerCase()));
          if (!elx) continue;
          const k = Number(c.members) / max;
          elx.style.fill = `rgba(212, 0, 106, ${0.25 + 0.65 * k})`;
          const tt = document.createElementNS(
            'http://www.w3.org/2000/svg', 'title');
          tt.textContent = `${c.name}: ${c.members}`;
          elx.append(tt);
        }
      } catch { /* map optional */ }
    }
    countrySel.addEventListener('change', paintTable);
    await refreshLive();
    const liveTimer = setInterval(refreshLive, 90000);
    root.addEventListener('wdos:teardown',
      () => clearInterval(liveTimer), { once: true });
  } catch (eLive) {
    const msg = String(eLive?.message || '');
    if (/programme_state|people_analytics|country_member_stats|function|schema/i
      .test(msg)) {
      out.append(el('div', { class: 'card mb-4' }, [
        el('h3', { text: t('rep.liveOps') }),
        el('p', { class: 'muted', text:
          'Live Operations needs one database update: run '
          + '053_new_home_calendar_analytics.sql in the Supabase SQL editor '
          + '(in the deploy zip, folder 2-database). This card becomes the '
          + 'live table + Africa map the moment it runs.' }),
      ]));
    }
    /* non-HQ: stay silent */
  }

  /* ---- accountability by name (HQ) ---- */
  try {
    const team = await teamAccountability();
    if (team && team.length) {
      out.append(section(t('rep.accountability')));
      const card = el('div', { class: 'card mb-4' });
      card.append(el('p', { class: 'muted mb-2', text: t('rep.accHint') }));
      for (const m2 of team.slice(0, 25)) {
        card.append(el('div', { class: 'row',
          style: 'gap:8px;flex-wrap:wrap;align-items:baseline;padding:6px 0;border-bottom:1px solid var(--line);' }, [
          el('strong', { style: 'flex:1;min-width:160px;', text: m2.name
            + (m2.is_staff ? ' · ' + t('rep.staffTag') : '') }),
          el('span', { class: 'badge badge--pipeline',
            text: t('rep.accOpen', { n: m2.open }) }),
          el('span', { class: `badge badge--${Number(m2.overdue) > 0 ? 'exited' : 'active'}`,
            text: t('rep.accOverdue', { n: m2.overdue }) }),
          el('span', { class: 'badge', text: t('rep.accReview', { n: m2.review }) }),
          el('span', { class: 'badge badge--active', text: t('rep.accDone', { n: m2.done30 }) }),
          el('span', { class: 'muted', style: 'font-size:12px;',
            text: m2.last_seen ? t('rep.accSeen', { d: fmtDate(m2.last_seen) })
                               : t('rep.accNever') }),
        ]));
      }
      out.append(card);
    }
  } catch { /* HQ-only */ }

  /* ---- learning & certification (HQ) ---- */
  try {
    const cs = await getCourseStats();
    if (cs && cs.length) {
      out.append(section(t('rep.learning')));
      out.append(el('div', { class: 'card mb-4' }, [
        el('div', { class: 'card__head' }, [
          el('h2', { text: t('course.hqTitle') })]),
        bars(cs.flatMap((c) => [
          { label: c.code + ' — ' + t('course.enrolled'), value: c.enrolled },
          { label: c.code + ' — ' + t('course.certified'), value: c.completed },
        ])),
      ]));
    }
  } catch { /* HQ-only */ }

  /* ---- activation journeys (HQ) ---- */
  try {
    const ins = await getAutomationInsights();
    const j = ins.journeys || {};
    out.append(section(t('rep.journeys')));
    out.append(el('div', { class: 'grid-2 mb-4' }, [
      el('div', { class: 'card' }, [
        el('div', { class: 'card__head' }, [
          el('h2', { text: t('rep.journeyMix') })]),
        donut([
          { label: t('journey.in_progress'), value: j.in_progress || 0 },
          { label: t('journey.completed'), value: j.completed || 0 },
          { label: t('journey.incomplete'), value: j.incomplete || 0 },
        ]),
      ]),
      el('div', { class: 'card' }, [
        el('div', { class: 'card__head' }, [
          el('h2', { text: t('rep.journeyHealth') })]),
        bars([
          { label: t('auto.journeysOverdue'), value: j.overdue || 0 },
          { label: t('rep.journeysQuiet'), value: j.quiet || 0 },
        ]),
        ins.quiz_avg_pct != null
          ? el('p', { class: 'muted mt-2',
              text: t('auto.quizAvg') + ': ' + ins.quiz_avg_pct + '%' })
          : null,
      ]),
    ]));
  } catch { /* HQ-only; others simply don't see it */ }

  /* ---- Africa coverage map ---- */
  out.append(section(t('rep.mapTitle')));
  out.append(await africaCard(units));

  return shell.teardown;
}

/**
 * Africa coverage map. Expects /assets/vendor/africa.svg — a public-domain
 * map whose country shapes carry ISO 3166-1 alpha-2 ids (see SETUP.md §5).
 * Countries where WODDI has active units are filled magenta. Falls back to
 * a country list when the map file is absent.
 */
async function africaCard(units) {
  const present = new Set(units
    .filter((u) => u.level === 'country' && u.country_iso)
    .map((u) => u.country_iso.toUpperCase()));
  const card = el('div', { class: 'card mb-4 map-card' });
  card.append(el('div', { class: 'card__head' }, [
    el('h2', { text: t('rep.mapTitle') }),
    el('span', { class: 'badge badge--active',
      text: t('rep.countriesReached', { n: fmtNumber(present.size) }) }),
  ]));

  let svgText = null;
  try {
    const res = await fetch('/assets/vendor/africa.svg?v=30', { cache: 'no-cache' });
    if (res.ok) svgText = await res.text();
  } catch { /* fall through to list */ }

  if (svgText && svgText.includes('<svg')) {
    const holder = el('div');
    holder.innerHTML = svgText;
    const svg = holder.querySelector('svg');
    svg.removeAttribute('width'); svg.removeAttribute('height');
    svg.querySelectorAll('path, polygon, g').forEach((node) => {
      const iso = (node.id || node.getAttribute('class') || '')
        .trim().slice(0, 2).toUpperCase();
      const hit = iso.length === 2 && present.has(iso);
      node.style.fill = hit ? 'var(--magenta)' : 'var(--line)';
      node.style.stroke = '#ffffff';
      node.style.strokeWidth = '0.6';
      if (hit) {
        const title = document.createElementNS(
          'http://www.w3.org/2000/svg', 'title');
        title.textContent = iso;
        node.append(title);
      }
    });
    svg.style.width = '100%';
    svg.style.height = 'auto';
    svg.style.maxHeight = '540px';
    svg.style.display = 'block';
    card.append(svg);
    // amCharts ships this file with no viewBox and no dimensions; without
    // one it renders at zero size. Measure once mounted, then set it.
    requestAnimationFrame(() => {
      try {
        if (!svg.getAttribute('viewBox')) {
          const b = svg.getBBox();
          if (b && b.width > 0) {
            svg.setAttribute('viewBox',
              `${b.x} ${b.y} ${b.width} ${b.height}`);
          } else {
            svg.setAttribute('viewBox', '0 0 800 850');
          }
        }
      } catch {
        svg.setAttribute('viewBox', '0 0 800 850');
      }
    });
    const legend = el('div', { class: 'map-legend' });
    legend.innerHTML = `
      <span><span class="swatch" style="background:var(--magenta)"></span>
        ${esc(t('rep.legendPresent'))}</span>
      <span><span class="swatch" style="background:var(--line)"></span>
        ${esc(t('rep.legendAbsent'))}</span>`;
    card.append(legend);
  } else {
    // Map asset not installed yet: same information as text.
    card.append(el('p', { class: 'muted', text: t('rep.mapMissing') }));
    if (present.size > 0) {
      card.append(el('p', {
        text: units.filter((u) => u.level === 'country').map((u) => u.name)
          .sort().join(' · ') }));
    }
  }
  return card;
}

function section(text) {
  return el('h2', { class: 'mb-4 mt-4', text });
}

function tile(label, value, extra = '', iconName = 'chart') {
  return el('div', { class: `card stat ${extra}` }, [
    el('div', { class: 'stat__icon' }, [icon(iconName, 22)]),
    el('div', { class: 'stat__body' }, [
      el('div', { class: 'stat__label', text: label }),
      el('div', { class: 'stat__value',
        text: typeof value === 'number' ? fmtNumber(value) : String(value ?? '—') }),
    ]),
  ]);
}

/** Horizontal progress bar with label and detail. */
function bar(label, pct, detail) {
  const wrap = el('div', { class: 'mb-4' });
  wrap.innerHTML = `
    <div class="row" style="justify-content:space-between;">
      <strong>${esc(label)}</strong>
      <span>${esc(String(pct))}%</span>
    </div>
    <div style="background:var(--canvas);border:1px solid var(--line);
                border-radius:99px;height:12px;overflow:hidden;"
         role="img" aria-label="${esc(label)}: ${esc(String(pct))}%">
      <div style="width:${Math.max(0, Math.min(100, pct))}%;height:100%;
                  background:${pct >= 70 ? 'var(--green)' : 'var(--magenta)'};">
      </div>
    </div>
    <span class="muted">${esc(detail)}</span>`;
  return wrap;
}

/** Minimal dependency-free SVG bar chart for monthly joins. */
function growthChart(rows) {
  if (!rows || rows.length === 0) {
    return el('p', { class: 'muted', text: t('rep.noData') });
  }
  const W = 640, H = 220, PAD = 32, BASE = H - 36;
  const max = Math.max(1, ...rows.map((r) => Number(r.joins)));
  const bw = (W - PAD * 2) / rows.length;
  let bars = '';
  rows.forEach((row, i) => {
    const v = Number(row.joins);
    const h = Math.round((v / max) * (BASE - 24));
    const x = PAD + i * bw + bw * 0.15;
    const y = BASE - h;
    bars += `
      <rect x="${x}" y="${y}" width="${bw * 0.7}" height="${h}"
            rx="4" fill="var(--magenta)"></rect>
      <text x="${x + bw * 0.35}" y="${y - 6}" text-anchor="middle"
            font-size="12" fill="var(--ink-2)">${v}</text>
      <text x="${x + bw * 0.35}" y="${BASE + 18}" text-anchor="middle"
            font-size="11" fill="var(--ink-3)">${esc(row.month)}</text>`;
  });
  const svg = el('div');
  svg.innerHTML = `
    <svg viewBox="0 0 ${W} ${H}" role="img"
         aria-label="${esc(t('rep.growthTitle'))}"
         style="width:100%;height:auto;">
      <line x1="${PAD}" y1="${BASE}" x2="${W - PAD}" y2="${BASE}"
            stroke="var(--line)" stroke-width="2"></line>
      ${bars}
    </svg>`;
  return svg;
}
