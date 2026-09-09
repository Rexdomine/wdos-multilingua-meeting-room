/**
 * Phase 135 — Leadership Structure explorer at #/structure (HQ, and any
 * seated leader for her own scope).
 *
 * Geography and position are two connected dimensions: the org tree and
 * the Position Master List. This page lists every seat the two produce,
 * filled or VACANT, and lets Headquarters answer the founder's questions
 * directly: which LGAs in Imo have no coordinator, which countries have no
 * deputy representative, how many state coordinators are appointed versus
 * acting, and so on. Terminology follows the country (level_terms).
 */
import { el, clear } from '../core/dom.js';
import { t, fmtDate } from '../core/i18n.js';
import { structureExplorer, listOrgUnits, listLevelTerms, POSITIONS } from '../core/db.js';
import { renderShell } from '../components/layout.js';

const LEVELS = ['country', 'state_region', 'district_lga', 'community_cluster', 'chapter'];
const STATUSES = ['all', 'vacant', 'appointed', 'acting', 'pending'];
const ACTIVATIONS = ['all', 'completed', 'in_progress', 'incomplete', 'none'];

export async function render(root, params, ctx) {
  const shell = renderShell(root, { profile: ctx.profile, modules: ctx.modules, titleKey: 'nav.structure' });
  const out = shell.outlet;
  clear(out);

  const state = {
    net: sessionStorage.getItem('wdos.structure.net') || 'WGMN',
    country: params?.country || '', state: '', level: '', role: '', status: 'all', activation: 'all',
  };
  let units = [];
  let terms = new Map();
  try {
    [units, terms] = await Promise.all([
      listOrgUnits(),
      listLevelTerms().then((rows) => new Map(rows.map((r) => [r.country_iso, r]))).catch(() => new Map()),
    ]);
  } catch { units = []; }
  const countries = units.filter((u) => u.level === 'country').sort((a, b) => a.name.localeCompare(b.name));

  const termsFor = (iso) => terms.get(iso || '') || terms.get('') || {};
  const levelLabel = (level, iso) => {
    const tm = termsFor(iso);
    return level === 'country' ? (tm.term_country || t('v.lvl_country'))
      : level === 'state_region' ? (tm.term_state || t('v.lvl_state_region'))
      : level === 'district_lga' ? (tm.term_district || t('v.lvl_district_lga'))
      : level === 'community_cluster' ? (tm.term_cluster || t('v.lvl_community_cluster'))
      : level === 'chapter' ? (tm.term_chapter || t('v.lvl_chapter')) : t('v.lvlUnit');
  };

  /* ---------------- filters ---------------- */
  const netSel = sel(['WGMN', 'WNNN'], state.net, (x) => x);
  netSel.hidden = true;
  const netBtns = el('div', { class: 'st-nets' }, ['WGMN', 'WNNN'].map((n) => el('button', {
    class: `st-net st-net--${n.toLowerCase()} ${state.net === n ? 'is-active' : ''}`,
    onclick: () => { netSel.value = n; netSel.dispatchEvent(new Event('change')); for (const b of netBtns.children) b.classList.toggle('is-active', b.dataset.net === n); },
    'data-net': n }, [el('b', { text: t(`st.net_${n}`) }), el('small', { text: t(`st.netHint_${n}`) })])));
  const countrySel = sel(['', ...countries.map((c) => c.id)], state.country,
    (id) => (id ? countries.find((c) => c.id === id).name : t('st.allCountries')));
  const stateSel = el('select', { class: 'select' });
  const levelSel = sel(['', ...LEVELS], state.level, (x) => (x ? levelLabel(x, isoOf(state.country)) : t('st.allLevels')));
  const roleSel = sel(['', ...POSITIONS], state.role, (x) => (x ? t(`role.${x}`) : t('st.allPositions')));
  const statusSel = sel(STATUSES, state.status, (x) => t(`st.status_${x}`));
  const actSel = sel(ACTIVATIONS, state.activation, (x) => t(`st.act_${x}`));

  function isoOf(countryId) {
    const c = countries.find((x) => x.id === countryId);
    return c ? c.country_iso : '';
  }
  function fillStates() {
    clear(stateSel);
    const iso = isoOf(countrySel.value);
    stateSel.append(el('option', { value: '', text: t('st.allOf', { term: levelLabel('state_region', iso) }) }));
    if (countrySel.value) {
      for (const s of units.filter((u) => u.parent_id === countrySel.value).sort((a, b) => a.name.localeCompare(b.name))) {
        stateSel.append(el('option', { value: s.id, text: s.name }));
      }
    }
    stateSel.disabled = !countrySel.value;
    // level names follow the chosen country
    for (const o of levelSel.options) if (o.value) o.text = levelLabel(o.value, iso);
  }
  fillStates();

  const filters = el('div', { class: 'st-filters' }, [
    fld(t('v.network'), netSel), fld(t('v.country'), countrySel), fld(t('st.region'), stateSel),
    fld(t('st.level'), levelSel), fld(t('st.position'), roleSel),
    fld(t('st.appointment'), statusSel), fld(t('st.activation'), actSel),
  ]);
  const summary = el('div', { class: 'vs-mini' });
  const path = el('p', { class: 'muted' });
  const body = el('div');
  out.append(
    el('p', { class: 'muted mb-2', text: t('st.sub') }),
    netBtns, filters, path, summary, body);

  for (const s of [netSel, countrySel, stateSel, levelSel, roleSel, statusSel, actSel]) {
    s.addEventListener('change', () => {
      if (s === countrySel) { fillStates(); }
      sessionStorage.setItem('wdos.structure.net', netSel.value);
      load();
    });
  }
  await load();
  return shell.teardown;

  /* ---------------- data ---------------- */
  async function load() {
    clear(body); body.append(el('div', { class: 'state' }, [el('div', { class: 'spinner' })]));
    const iso = isoOf(countrySel.value);
    path.textContent = [netSel.value,
      countrySel.value ? countries.find((c) => c.id === countrySel.value).name : t('st.allCountries'),
      stateSel.value ? stateSel.options[stateSel.selectedIndex].text : null,
      levelSel.value ? levelLabel(levelSel.value, iso) : t('st.allLevels'),
      roleSel.value ? t(`role.${roleSel.value}`) : t('st.allPositions'),
      t(`st.status_${statusSel.value}`),
    ].filter(Boolean).join(' \u2192 ');
    let d;
    try {
      d = await structureExplorer({ net: netSel.value, country: countrySel.value || null,
        state: stateSel.value || null, level: levelSel.value || null, role: roleSel.value || null,
        status: statusSel.value, activation: actSel.value });
    } catch (err) {
      clear(body);
      body.append(el('p', { class: 'muted', text: err?.message || t('errors.load') }));
      return;
    }
    clear(summary);
    summary.append(
      mini(t('st.seats'), d.seats), mini(t('v.filled'), d.filled, 'green'),
      mini(t('v.vacant'), d.vacant, d.vacant > 0 ? 'red' : 'green'),
      mini(t('st.acting'), d.acting, d.acting > 0 ? 'amber' : ''), mini(t('st.pending'), d.pending, d.pending > 0 ? 'amber' : ''),
      mini(t('st.shown'), d.shown));
    clear(body);
    const rows = d.rows || [];
    if (!rows.length) { body.append(el('p', { class: 'muted', text: t('st.none') })); return; }
    const tbl = el('table', { class: 'vs-table' }, [
      el('thead', {}, [el('tr', {}, [
        el('th', { text: t('st.unit') }), el('th', { text: t('st.position') }),
        el('th', { text: t('st.holder') }), el('th', { text: t('st.appointment') }),
        el('th', { text: t('st.activation') }), el('th', { text: t('st.since') }), el('th', { text: '' })])]),
      el('tbody', {}, rows.map((r) => el('tr', { class: r.vacant ? 'st-vacant' : '' }, [
        el('td', {}, [el('b', { text: r.unit }),
          el('div', { class: 'muted', text: `${levelLabel(r.level, iso)}${r.parent ? ' \u00B7 ' + r.parent : ''}${r.country && r.level !== 'country' ? ' \u00B7 ' + r.country : ''}` })]),
        el('td', { text: t(`role.${r.role}`) }),
        el('td', {}, r.vacant ? [el('span', { class: 'vs-badge vs-badge--red', text: t('v.seatVacant') })]
          : [el('b', { text: r.holder_name || '' }),
            el('div', { class: 'muted', text: [r.membership_no, r.last_seen ? `${t('v.lastSeen')} ${fmtDate(r.last_seen)}` : t('v.neverSignedIn')].filter(Boolean).join(' \u00B7 ') })]),
        el('td', {}, [r.vacant ? null : apptBadge(r.appointment_status)]),
        el('td', { text: r.vacant ? '' : t(`st.act_${r.activation || 'none'}`) }),
        el('td', { text: r.since ? fmtDate(r.since) : '' }),
        el('td', {}, [
          r.holder_id ? el('a', { href: `#/view-as/${r.holder_id}`, class: 'btn btn--quiet', text: t('acc.viewAs') }) : null,
          ctx.modules?.has('hq') ? el('a', { href: r.holder_id ? `#/accounts?q=${encodeURIComponent(r.holder_name || '')}` : '#/accounts',
            class: 'btn btn--quiet', text: r.vacant ? t('st.fillSeat') : t('acc.seat') }) : null,
        ]),
      ]))),
    ]);
    body.append(el('div', { class: 'table-wrap card', style: 'padding:8px 12px;' }, [tbl]));
    if (d.shown > rows.length) body.append(el('p', { class: 'muted', text: t('v.leadTruncated', { shown: rows.length, total: d.shown }) }));
  }

  /* ---------------- helpers (function declarations: hoisted) ---------------- */
  function sel(opts, cur, labelFn) {
    return el('select', { class: 'select' }, opts.map((o) =>
      el('option', { value: o, text: labelFn(o), selected: o === cur || null })));
  }
  function fld(label, node) {
    return el('div', { class: 'field' }, [el('label', { class: 'field__label', text: label }), node]);
  }
  function mini(label, value, tone = '') {
    return el('div', { class: `vs-mini__t ${tone ? 'vs-mini__t--' + tone : ''}` }, [
      el('b', { text: String(value ?? 0) }), el('small', { text: label })]);
  }
}

export function apptBadge(status) {
  const cls = status === 'appointed' ? 'green' : status === 'acting' ? 'amber' : 'blue';
  return el('span', { class: `vs-badge vs-badge--${cls}`, text: t(`st.status_${status || 'appointed'}`) });
}
