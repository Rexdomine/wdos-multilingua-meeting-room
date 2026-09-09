/**
 * WDOS Network Command — Phase 133 (HQ only).
 *
 * The founder's Monday standard, §6: one authorised screen from which
 * Headquarters sees, per network and consolidated, how many leaders there
 * are, where, at what level, which seats are vacant, where each person
 * stands in the leadership journey, who has gone quiet, what is due, and
 * what needs a management decision — with every number opening to the
 * people behind it. All figures come from one server call
 * (network_command) and are real counts; nothing here is estimated.
 */
import { el, clear } from '../core/dom.js';
import { t, fmtNumber, fmtDate } from '../core/i18n.js';
import { db } from '../core/db.js';
import { renderShell } from '../components/layout.js';
import { icon } from '../components/icons.js';

const NETS = ['all', 'WGMN', 'WNNN'];
const ROLE_ORDER = ['country_rep', 'deputy_country_rep', 'state_coordinator',
  'assistant_state_coordinator', 'district_coordinator', 'chapter_lead'];
const STAGE_ORDER = ['registered', 'account', 'activation', 'activation_lapsed',
  'assessed', 'member', 'leader_active', 'leader_inactive', 'exited'];

export async function render(root, params, ctx) {
  const shell = renderShell(root, {
    profile: ctx.profile, modules: ctx.modules, titleKey: 'nav.command',
  });
  const out = shell.outlet;
  let net = String(params?.net || sessionStorage.getItem('wdos.cmd.net') || 'all');
  if (!NETS.includes(net)) net = 'all';

  const head = el('div', { class: 'row', style: 'align-items:center;gap:12px;flex-wrap:wrap;margin-bottom:12px;' });
  const switcher = el('div', { class: 'row', style: 'gap:6px;' });
  const refresh = el('button', { class: 'btn btn--quiet', text: t('cmd.refresh'),
    onclick: () => load() });
  head.append(switcher, refresh);
  const body = el('div');
  out.append(head, body);

  function paintSwitch() {
    clear(switcher);
    for (const n of NETS) {
      switcher.append(el('button', {
        class: 'btn ' + (n === net ? 'btn--primary' : 'btn--secondary'),
        text: n === 'all' ? t('cmd.allNetworks') : n,
        onclick: () => { net = n; sessionStorage.setItem('wdos.cmd.net', n); load(); },
      }));
    }
  }

  async function load() {
    paintSwitch();
    clear(body);
    body.append(el('div', { class: 'state' }, [
      el('div', { class: 'spinner' }), el('p', { text: t('app.loading') })]));
    try {
      const { data, error } = await db().rpc('network_command', { p_net: net });
      if (error) throw error;
      clear(body);
      paint(data || {});
    } catch (err) {
      clear(body);
      body.append(el('div', { class: 'card state' }, [
        el('h3', { text: t('errors.loadTitle') }),
        el('p', { class: 'muted', text: String(err?.message || err).slice(0, 160) }),
        el('button', { class: 'btn btn--quiet', text: t('app.retry'), onclick: load }),
      ]));
    }
  }

  function paint(d) {
    const tot = d.totals || {};
    const att = d.attention || {};
    const netLabel = net === 'all' ? t('cmd.allNetworks') : net;
    body.append(el('p', { class: 'muted', style: 'margin:0 0 10px;',
      text: t('cmd.scopeNote', { net: netLabel }) }));

    // ---- KPI grid: each card opens its list ----
    const grid = el('div', { class: 'grid grid--kpi',
      style: 'display:grid;grid-template-columns:repeat(auto-fill,minmax(180px,1fr));gap:10px;' });
    const kpi = (label, value, tone, rows, rowKind) => {
      const card = el('button', { class: 'card kpi', type: 'button',
        style: 'text-align:left;cursor:' + (rows ? 'pointer' : 'default') + ';border-left:4px solid ' + tone + ';' }, [
        el('div', { class: 'muted', style: 'font-size:12px;', text: label }),
        el('div', { style: 'font-size:28px;font-weight:700;', text: fmtNumber(value ?? 0) }),
        rows ? el('div', { class: 'muted', style: 'font-size:11px;', text: t('cmd.tapToOpen') }) : null,
      ]);
      if (rows) card.onclick = () => openList(label, rows, rowKind);
      return card;
    };
    const MAG = '#D4006A'; const LEM = '#7CB518'; const AMB = '#E0A100'; const RED = '#C62828'; const GREY = '#999';
    grid.append(
      kpi(t('cmd.leaders'), tot.leaders, MAG, null),
      kpi(t('cmd.members'), tot.members, MAG, null),
      kpi(t('cmd.countriesCovered'), `${tot.countries_covered ?? 0}/${tot.countries_total ?? 0}`, LEM, null),
      kpi(t('cmd.active14'), tot.active_14d, LEM, null),
      kpi(t('cmd.inactiveLeaders'), tot.inactive_30d, RED, att.inactive_leaders, 'person'),
      kpi(t('cmd.vacantCr'), tot.vacant_cr, AMB, att.vacant_cr, 'country'),
      kpi(t('cmd.unclaimed'), tot.unclaimed, AMB, att.unclaimed, 'applicant'),
      kpi(t('cmd.activationInProgress'), tot.activation_in_progress, LEM, null),
      kpi(t('cmd.activationStalled'), (att.activation_stalled || []).length, AMB, att.activation_stalled, 'person'),
      kpi(t('cmd.tasksOpen'), tot.tasks_open, GREY, null),
      kpi(t('cmd.tasksOverdue'), tot.tasks_overdue, RED, att.overdue_tasks, 'task'),
      kpi(t('cmd.meetings7d'), tot.meetings_7d, GREY, null),
      kpi(t('cmd.ticketsAging'), tot.tickets_aging, AMB, null),
      kpi(t('cmd.casesOpen'), tot.cases_open, RED, null),
      kpi(t('cmd.missingInfo'), (att.missing_info || []).length, AMB, att.missing_info, 'person'),
    );
    body.append(el('h3', { text: t('cmd.overview') }), grid);

    // ---- attention queue ----
    const q = el('div', { class: 'card', style: 'margin-top:14px;' });
    q.append(el('h3', { text: t('cmd.attention') }));
    const items = [];
    if ((att.vacant_cr || []).length) items.push([t('cmd.qVacant', { n: att.vacant_cr.length }), att.vacant_cr, 'country']);
    if ((att.inactive_leaders || []).length) items.push([t('cmd.qInactive', { n: att.inactive_leaders.length }), att.inactive_leaders, 'person']);
    if ((att.overdue_tasks || []).length) items.push([t('cmd.qOverdue', { n: att.overdue_tasks.length }), att.overdue_tasks, 'task']);
    if ((att.activation_stalled || []).length) items.push([t('cmd.qStalled', { n: att.activation_stalled.length }), att.activation_stalled, 'person']);
    if ((att.unclaimed || []).length) items.push([t('cmd.qUnclaimed', { n: att.unclaimed.length }), att.unclaimed, 'applicant']);
    if ((att.missing_info || []).length) items.push([t('cmd.qMissing', { n: att.missing_info.length }), att.missing_info, 'person']);
    if (tot.tickets_aging) items.push([t('cmd.qTickets', { n: tot.tickets_aging }), null, 'link:#/helpdesk']);
    if (tot.cases_open) items.push([t('cmd.qCases', { n: tot.cases_open }), null, 'link:#/cases']);
    if (!items.length) q.append(el('p', { class: 'muted', text: t('cmd.allClear') }));
    for (const [label, rows, kind] of items) {
      const row = el('div', { class: 'row', style: 'justify-content:space-between;align-items:center;padding:8px 0;border-bottom:1px solid #eee;' });
      row.append(el('span', { text: label }));
      if (rows) row.append(el('button', { class: 'btn btn--quiet', text: t('cmd.open'),
        onclick: () => openList(label, rows, kind) }));
      else row.append(el('a', { class: 'btn btn--quiet', href: kind.slice(5), text: t('cmd.open') }));
      q.append(row);
    }
    body.append(q);

    // ---- by level + stages ----
    const two = el('div', { style: 'display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:12px;margin-top:14px;' });
    const lv = el('div', { class: 'card' });
    lv.append(el('h3', { text: t('cmd.byLevel') }));
    const byLevel = (d.by_level || []).slice().sort((a, b) => ROLE_ORDER.indexOf(a.role) - ROLE_ORDER.indexOf(b.role));
    if (!byLevel.length) lv.append(el('p', { class: 'muted', text: t('cmd.none') }));
    for (const r of byLevel) lv.append(bar(t(`role.${r.role}`), r.n, tot.leaders || 1));
    const st = el('div', { class: 'card' });
    st.append(el('h3', { text: t('cmd.journey') }));
    const stages = (d.stages || []).slice().sort((a, b) => STAGE_ORDER.indexOf(a.stage) - STAGE_ORDER.indexOf(b.stage));
    for (const s of stages) st.append(bar(t(`stage.${s.stage}`), s.n, tot.members || 1, t(`stageNext.${s.stage}`)));
    two.append(lv, st);
    body.append(two);

    // ---- by country ----
    const bc = el('div', { class: 'card', style: 'margin-top:14px;overflow:auto;' });
    bc.append(el('h3', { text: t('cmd.byCountry') }));
    const table = el('table', { class: 'table', style: 'width:100%;font-size:13px;' });
    table.append(el('thead', {}, [el('tr', {}, [
      th(t('cmd.country')), th(t('cmd.leaders')), th(t('cmd.members')),
      th(t('role.country_rep')), th(t('role.deputy_country_rep')), th(t('cmd.statesCovered'))])]));
    const tb = el('tbody');
    for (const c of d.by_country || []) {
      tb.append(el('tr', {}, [
        el('td', { text: c.name }),
        el('td', { text: fmtNumber(c.leaders) }),
        el('td', { text: fmtNumber(c.members) }),
        el('td', { text: c.cr_filled ? '✓' : '—', style: c.cr_filled ? '' : 'color:#C62828;font-weight:700;' }),
        el('td', { text: c.dcr_filled ? '✓' : '—', style: c.dcr_filled ? '' : 'color:#E0A100;font-weight:700;' }),
        el('td', { text: `${c.states_with_coord}/${c.states}` }),
      ]));
    }
    table.append(tb);
    bc.append(table);
    body.append(bc);
  }

  function th(text) { return el('th', { text, style: 'text-align:left;padding:6px 8px;' }); }
  function bar(label, n, total, note) {
    const pct = Math.max(2, Math.round((n / Math.max(total, 1)) * 100));
    return el('div', { style: 'margin:6px 0;' }, [
      el('div', { class: 'row', style: 'justify-content:space-between;font-size:13px;' }, [
        el('span', { text: label }), el('strong', { text: fmtNumber(n) })]),
      el('div', { style: 'height:6px;background:#f1e3ea;border-radius:3px;overflow:hidden;' }, [
        el('div', { style: `height:6px;width:${pct}%;background:#D4006A;` })]),
      note ? el('div', { class: 'muted', style: 'font-size:11px;', text: note }) : null,
    ]);
  }

  // ---- drill list: the people or records behind a number ----
  function openList(title, rows, kind) {
    const panel = el('div', { class: 'card', style: 'margin-top:14px;border:2px solid #D4006A;' });
    const hd = el('div', { class: 'row', style: 'justify-content:space-between;align-items:center;' }, [
      el('h3', { text: title, style: 'margin:0;' }),
      el('button', { class: 'btn btn--quiet', text: t('app.close'), onclick: () => panel.remove() }),
    ]);
    panel.append(hd);
    if (!rows.length) panel.append(el('p', { class: 'muted', text: t('cmd.none') }));
    for (const r of rows) {
      let line; let href = null;
      if (kind === 'person') {
        line = `${r.name}${r.role ? ' · ' + t(`role.${r.role}`) : ''}${r.country ? ' · ' + r.country : ''}`
          + (r.last_seen_at ? ' · ' + t('cmd.lastSeen', { d: fmtDate(r.last_seen_at) }) : (r.last_seen_at === null ? ' · ' + t('cmd.neverSeen') : ''))
          + (r.due_at ? ' · ' + t('cmd.dueBy', { d: fmtDate(r.due_at) }) : '')
          + (r.missing ? ' · ' + t('cmd.missingList', { list: r.missing.join(', ') }) : '');
        href = `#/members/${r.id}`;
      } else if (kind === 'country') {
        line = `${r.name}: ${!r.cr_filled ? t('role.country_rep') + ' ' + t('cmd.vacant') : ''}${!r.cr_filled && !r.dcr_filled ? ', ' : ''}${!r.dcr_filled ? t('role.deputy_country_rep') + ' ' + t('cmd.vacant') : ''}`;
        href = `#/leaders`;
      } else if (kind === 'task') {
        line = `${r.title} · ${r.owner} · ${t('cmd.dueBy', { d: fmtDate(r.due_on) })}`;
        href = `#/tasks`;
      } else if (kind === 'applicant') {
        line = `${r.name} · ${r.email} · ${r.network} · ${fmtDate(r.created_at)}`;
        href = `#/accounts`;
      } else line = JSON.stringify(r);
      const row = el('div', { class: 'row', style: 'justify-content:space-between;padding:6px 0;border-bottom:1px solid #eee;font-size:13px;' });
      row.append(el('span', { text: line }));
      if (href) row.append(el('a', { class: 'btn btn--quiet', href, text: t('cmd.view') }));
      panel.append(row);
    }
    body.insertBefore(panel, body.children[1] || null);
    panel.scrollIntoView({ behavior: 'smooth', block: 'start' });
  }

  await load();
}
