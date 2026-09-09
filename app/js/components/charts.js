/**
 * WDOS charts — Phase 36. Pure SVG, no libraries, brand palette,
 * dark-mode friendly (labels use currentColor / CSS variables).
 * donut(items)  → part-of-whole (membership by status, tasks…)
 * bars(items)   → ranked comparison (recruitment funnel, coverage…)
 * line(points)  → trend over time (monthly growth…)
 * items: [{ label, value }], points: [{ label, value }]
 */
import { el } from '../core/dom.js';

const PALETTE = ['#D4006A', '#7CB518', '#8E3BD6', '#F59E0B',
  '#2563EB', '#0D9488', '#DC2626', '#64748B', '#DB2777', '#4D7C0F'];

const NS = 'http://www.w3.org/2000/svg';
function s(tag, attrs = {}) {
  const n = document.createElementNS(NS, tag);
  for (const [k, v] of Object.entries(attrs)) n.setAttribute(k, String(v));
  return n;
}

function legend(items) {
  const wrap = el('div', { class: 'chart__legend' });
  items.forEach((it, i) => {
    wrap.append(el('span', { class: 'chart__key' }, [
      el('span', { class: 'chart__dot',
        style: `background:${PALETTE[i % PALETTE.length]}` }),
      el('span', { text: `${it.label} (${it.value})` }),
    ]));
  });
  return wrap;
}

export function donut(items) {
  const data = items.filter((d) => d.value > 0);
  const total = data.reduce((a, d) => a + d.value, 0);
  const box = el('div', { class: 'chart' });
  if (!total) { box.append(el('p', { class: 'muted', text: '—' })); return box; }

  const svg = s('svg', { viewBox: '0 0 120 120', class: 'chart__svg chart__svg--donut' });
  const R = 48, C = 2 * Math.PI * R;
  let offset = 0;
  data.forEach((d, i) => {
    const frac = d.value / total;
    const arc = s('circle', {
      cx: 60, cy: 60, r: R, fill: 'none',
      stroke: PALETTE[i % PALETTE.length], 'stroke-width': 20,
      'stroke-dasharray': `${frac * C} ${C - frac * C}`,
      'stroke-dashoffset': String(-offset * C + C / 4),
    });
    svg.append(arc);
    offset += frac;
  });
  const label = s('text', { x: 60, y: 66, 'text-anchor': 'middle',
    class: 'chart__total' });
  label.textContent = String(total);
  svg.append(label);
  box.append(svg, legend(data));
  return box;
}

export function bars(items) {
  const data = items.filter((d) => d.value >= 0);
  const max = Math.max(1, ...data.map((d) => d.value));
  const box = el('div', { class: 'chart chart--bars' });
  data.forEach((d, i) => {
    box.append(el('div', { class: 'chart__bar-row' }, [
      el('span', { class: 'chart__bar-label', text: d.label }),
      el('div', { class: 'chart__bar-track' }, [
        el('div', { class: 'chart__bar-fill', style:
          `width:${Math.round((d.value / max) * 100)}%;` +
          `background:${PALETTE[i % PALETTE.length]};` }),
      ]),
      el('span', { class: 'chart__bar-value', text: String(d.value) }),
    ]));
  });
  if (!data.length) box.append(el('p', { class: 'muted', text: '—' }));
  return box;
}

export function line(points) {
  const box = el('div', { class: 'chart' });
  if (!points.length) { box.append(el('p', { class: 'muted', text: '—' })); return box; }
  const W = 320, H = 130, PADX = 8, PADY = 14;
  const max = Math.max(1, ...points.map((p) => p.value));
  const stepX = points.length > 1 ? (W - PADX * 2) / (points.length - 1) : 0;
  const xy = points.map((p, i) => [
    PADX + i * stepX,
    H - PADY - (p.value / max) * (H - PADY * 2),
  ]);
  const svg = s('svg', { viewBox: `0 0 ${W} ${H + 18}`, class: 'chart__svg chart__svg--line' });

  // area fill
  const area = s('path', {
    d: `M ${xy[0][0]} ${H - PADY} ` +
       xy.map(([x, y]) => `L ${x} ${y}`).join(' ') +
       ` L ${xy[xy.length - 1][0]} ${H - PADY} Z`,
    fill: 'var(--magenta-tint, #FDE7F1)', stroke: 'none',
  });
  // line
  const path = s('path', {
    d: xy.map(([x, y], i) => `${i ? 'L' : 'M'} ${x} ${y}`).join(' '),
    fill: 'none', stroke: '#D4006A', 'stroke-width': 2.5,
    'stroke-linejoin': 'round', 'stroke-linecap': 'round',
  });
  svg.append(area, path);
  xy.forEach(([x, y], i) => {
    svg.append(s('circle', { cx: x, cy: y, r: 3.4, fill: '#D4006A' }));
    const v = s('text', { x, y: y - 7, 'text-anchor': 'middle', class: 'chart__pt' });
    v.textContent = String(points[i].value);
    svg.append(v);
    const lb = s('text', { x, y: H + 12, 'text-anchor': 'middle', class: 'chart__x' });
    lb.textContent = points[i].label;
    svg.append(lb);
  });
  box.append(svg);
  return box;
}
