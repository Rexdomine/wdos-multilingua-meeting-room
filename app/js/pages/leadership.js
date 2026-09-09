/**
 * WDOS Volunteer Leadership (Phase 86) — the continental spine on one page.
 * HQ view: Africa map pulsing lemon-green where leadership is live,
 * WGMN Representatives and WNNN Leads side by side, each leader's
 * activation journey captured at a glance.
 */
import { el, clear, esc } from '../core/dom.js';
import { t } from '../core/i18n.js';
import { renderShell } from '../components/layout.js';
import { leadershipOverview } from '../core/db.js';
import { COUNTRY_ISO } from '../core/geo.js';

const ISO_NAME = Object.fromEntries(
  Object.entries(COUNTRY_ISO).map(([n, i]) => [i, n]));

export async function render(root, params, ctx) {
  const shell = renderShell(root, { ...ctx, titleKey: 'nav.leadership' });
  const out = shell.outlet;
  out.append(el('div', { class: 'state' }, [el('div', { class: 'spinner' })]));

  let rows = [];
  try {
    rows = (await leadershipOverview()) || [];
  } catch (e) {
    clear(out);
    out.append(el('div', { class: 'card state' }, [
      el('h3', { text: t('lead.missing') }),
      el('p', { class: 'muted', text: e?.message || t('errors.load') }),
    ]));
    return shell.teardown;
  }
  clear(out);

  const claimedIso = new Set();
  const invitedIso = new Set();
  const byCountry = new Map();
  for (const r of rows) {
    const iso = COUNTRY_ISO[r.country] || null;
    if (iso) {
      (r.source === 'claimed' ? claimedIso : invitedIso).add(iso);
      byCountry.set(iso, (byCountry.get(iso) || 0) + 1);
    }
  }
  for (const iso of claimedIso) invitedIso.delete(iso);

  const claimed = rows.filter((r) => r.source === 'claimed').length;
  const done = rows.filter((r) => r.journey_status === 'completed').length;
  const inJourney = rows.filter((r) => r.journey_status === 'in_progress').length;
  const countries = new Set(rows.map((r) => r.country)
    .filter((c) => c && c !== '—')).size;

  const tile = (label, n, cls) => el('div', { class: `stat ${cls || ''}` }, [
    el('div', { class: 'stat__num', text: String(n) }),
    el('div', { class: 'stat__label', text: label }),
  ]);
  out.append(el('div', { class: 'stats mb-4' }, [
    tile(t('lead.countries'), countries, 'stat--green'),
    tile(t('lead.leaders'), rows.length),
    tile(t('lead.claimed'), claimed, 'stat--green'),
    tile(t('lead.inJourney'), inJourney),
    tile(t('lead.completed'), done, 'stat--green'),
  ]));

  // ── the living map
  const mapCard = el('div', { class: 'card mb-4 map-card' });
  mapCard.append(el('div', { class: 'card__head' }, [
    el('h2', { text: t('lead.mapTitle') }),
    el('span', { class: 'badge badge--active',
      text: t('lead.liveIn', { n: claimedIso.size }) }),
  ]));
  out.append(mapCard);
  paintMap(mapCard, claimedIso, invitedIso, byCountry).catch(() => {});

  // ── two networks, one page
  const grid = el('div', { style:
    'display:grid;grid-template-columns:repeat(auto-fit,minmax(340px,1fr));'
    + 'gap:16px;align-items:start;' });
  out.append(grid);
  grid.append(networkCard('WGMN', t('lead.wgmnTitle'),
    rows.filter((r) => r.network === 'WGMN')));
  grid.append(networkCard('WNNN', t('lead.wnnnTitle'),
    rows.filter((r) => r.network === 'WNNN')));

  return shell.teardown;

  function networkCard(net, title, list) {
    list.sort((a, b) => (a.country || '').localeCompare(b.country || '')
      || (a.member_no || '').localeCompare(b.member_no || ''));
    const card = el('div', { class: 'card' });
    card.append(el('div', { class: 'card__head' }, [
      el('h2', { text: title }),
      el('span', { class: net === 'WGMN'
        ? 'badge badge--pipeline' : 'badge badge--active',
        text: t('lead.count', { n: list.length }) }),
    ]));
    if (!list.length) {
      card.append(el('p', { class: 'muted', text: t('lead.none') }));
      return card;
    }
    const table = el('table', { class: 'table' });
    table.append(el('thead', {}, [el('tr', {}, [
      el('th', { text: t('lead.thCountry') }),
      el('th', { text: t('lead.thLeader') }),
      el('th', { text: t('lead.thJourney') }),
    ])]));
    const tb = el('tbody');
    for (const r of list) {
      const idPill = el('span', { class: 'badge',
        style: 'font-family:monospace;font-size:11px;',
        text: r.member_no || '—' });
      const who = el('div', {}, [
        el('div', { style: 'font-weight:600;', text: r.full_name }),
        el('div', { class: 'muted', style: 'font-size:12px;' }, [
          idPill,
          el('span', { text: ' ' + (r.role_title || '') }),
        ]),
      ]);
      tb.append(el('tr', {}, [
        el('td', { text: r.country || '—' }),
        el('td', {}, [who]),
        el('td', {}, [journeyCell(r)]),
      ]));
    }
    table.append(tb);
    card.append(el('div', { style: 'overflow:auto;' }, [table]));
    return card;
  }

  function journeyCell(r) {
    if (r.source === 'invited') {
      return el('span', { class: 'badge',
        style: 'background:rgba(212,0,106,.08);color:var(--magenta);',
        text: t('lead.invited') });
    }
    if (r.journey_status === 'completed') {
      return el('span', { class: 'badge badge--active',
        text: t('lead.doneBadge') });
    }
    if (r.journey_status === 'not_started') {
      return el('span', { class: 'badge', text: t('lead.claimedNoJourney') });
    }
    const total = r.required_total || 1;
    const pct = Math.min(100, Math.round((r.done_required / total) * 100));
    const overdue = r.due_at && new Date(r.due_at) < new Date();
    const wrap = el('div', { style: 'min-width:150px;' });
    wrap.append(el('div', { class: 'muted',
      style: 'font-size:12px;margin-bottom:3px;',
      text: t('lead.progress',
        { d: r.done_required, n: total }) + (overdue ? ' · ⚠' : '') }));
    const bar = el('div', { style:
      'height:8px;border-radius:999px;background:var(--line,#eee);'
      + 'overflow:hidden;' });
    bar.append(el('div', { style:
      `height:100%;width:${pct}%;border-radius:999px;`
      + `background:${overdue ? 'var(--magenta)' : 'var(--lime,#7CB518)'};` }));
    wrap.append(bar);
    return wrap;
  }
}

async function paintMap(card, activeIso, invitedIso, byCountry) {
  let svgText = null;
  try {
    const res = await fetch('/assets/vendor/africa.svg?v=53',
      { cache: 'no-cache' });
    if (res.ok) svgText = await res.text();
  } catch { /* list-less fallback below */ }
  if (!svgText || !svgText.includes('<svg')) {
    card.append(el('p', { class: 'muted', text: t('lead.noMap') }));
    return;
  }
  const holder = el('div');
  holder.innerHTML = svgText;
  const svg = holder.querySelector('svg');
  svg.removeAttribute('width'); svg.removeAttribute('height');
  const dots = [];
  svg.querySelectorAll('path, polygon, g').forEach((node) => {
    const iso = (node.id || node.getAttribute('class') || '')
      .trim().slice(0, 2).toUpperCase();
    const live = activeIso.has(iso);
    const soon = !live && invitedIso.has(iso);
    node.style.fill = live ? 'rgba(124,181,24,.85)'
      : soon ? 'rgba(212,0,106,.18)' : 'var(--line)';
    node.style.stroke = '#ffffff';
    node.style.strokeWidth = '0.6';
    if (live || soon) {
      const title = document.createElementNS(
        'http://www.w3.org/2000/svg', 'title');
      title.textContent = `${ISO_NAME[iso] || iso} — `
        + t('lead.count', { n: byCountry.get(iso) || 0 });
      node.append(title);
      if (live) dots.push(node);
    }
  });
  svg.style.width = '100%';
  svg.style.height = 'auto';
  svg.style.maxHeight = '520px';
  svg.style.display = 'block';
  const style = document.createElementNS(
    'http://www.w3.org/2000/svg', 'style');
  style.textContent = `@keyframes wdosPulse {
    0% { r: 4; opacity: .95; } 70% { r: 9; opacity: .15; }
    100% { r: 4; opacity: .95; } }
    .wdos-dot { fill: #7CB518; animation: wdosPulse 2.2s ease-out infinite; }
    .wdos-core { fill: #7CB518; }`;
  svg.append(style);
  card.append(svg);
  requestAnimationFrame(() => {
    try {
      if (!svg.getAttribute('viewBox')) {
        const b = svg.getBBox();
        svg.setAttribute('viewBox', b && b.width > 0
          ? `${b.x} ${b.y} ${b.width} ${b.height}` : '0 0 800 850');
      }
      for (const node of dots) {
        const b = node.getBBox();
        if (!b || !b.width) continue;
        const cx = b.x + b.width / 2;
        const cy = b.y + b.height / 2;
        const halo = document.createElementNS(
          'http://www.w3.org/2000/svg', 'circle');
        halo.setAttribute('cx', cx); halo.setAttribute('cy', cy);
        halo.setAttribute('r', 4); halo.setAttribute('class', 'wdos-dot');
        const core = document.createElementNS(
          'http://www.w3.org/2000/svg', 'circle');
        core.setAttribute('cx', cx); core.setAttribute('cy', cy);
        core.setAttribute('r', 3); core.setAttribute('class', 'wdos-core');
        svg.append(halo, core);
      }
    } catch { svg.setAttribute('viewBox', '0 0 800 850'); }
  });
  const legend = el('div', { class: 'map-legend' });
  legend.innerHTML = `
    <span><span class="swatch" style="background:#7CB518"></span>
      ${esc(t('lead.legendLive'))}</span>
    <span><span class="swatch"
      style="background:rgba(212,0,106,.25)"></span>
      ${esc(t('lead.legendInvited'))}</span>
    <span><span class="swatch" style="background:var(--line)"></span>
      ${esc(t('lead.legendNone'))}</span>`;
  card.append(legend);
}
