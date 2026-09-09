/**
 * WDOS DOM helpers.
 * esc() must wrap every piece of user-originated data that is rendered
 * through innerHTML. el() builds nodes safely without HTML strings.
 */
export function esc(value) {
  const s = String(value ?? '');
  return s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

export function el(tag, attrs = {}, children = []) {
  const node = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k === 'class') node.className = v;
    else if (k === 'text') node.textContent = v;
    else if (k.startsWith('on') && typeof v === 'function') {
      node.addEventListener(k.slice(2), v);
    } else if (v !== null && v !== undefined && v !== false) {
      node.setAttribute(k, v === true ? '' : String(v));
    }
  }
  for (const child of [].concat(children)) {
    if (child == null) continue;
    node.append(child instanceof Node ? child : document.createTextNode(child));
  }
  return node;
}

export function clear(node) {
  while (node.firstChild) node.removeChild(node.firstChild);
}

/** Debounce for search inputs. */
export function debounce(fn, ms = 300) {
  let id;
  return (...args) => { clearTimeout(id); id = setTimeout(() => fn(...args), ms); };
}

/** Minimal safe markup: escape first, then **bold**, *italic*, and
 *  "- " bullet lines. Everything else stays literal. */
export function renderMarkup(text) {
  let h = esc(text);
  h = h.replace(/\*\*([^*\n]+)\*\*/g, '<strong>$1</strong>');
  h = h.replace(/(^|[^*])\*([^*\n]+)\*(?!\*)/g, '$1<em>$2</em>');
  h = h.split('\n').map((line) =>
    line.startsWith('- ')
      ? '<span style="display:block;padding-left:1em;">\u2022 ' +
        line.slice(2) + '</span>'
      : line
  ).join('<br>');
  return h.replaceAll('<br><span', '<span').replaceAll('</span><br>', '</span>');
}

/** Escape, then make URLs clickable (new tab) and keep line breaks.
 *  Used for agendas, minutes, and anywhere pasted links should work. */
export function linkify(text) {
  let h = esc(text);
  h = h.replace(/(https?:\/\/[^\s<]+)/g, (u) => {
    const clean = u.replace(/[).,;:!?]+$/, '');
    const tail = u.slice(clean.length);
    return `<a href="${clean}" target="_blank" rel="noopener noreferrer">${clean}</a>${tail}`;
  });
  return h.replaceAll('\n', '<br>');
}

/** True when the whole string is a single http(s) URL. */
export const isUrl = (s) =>
  typeof s === 'string' && /^https?:\/\/\S+$/.test(s.trim());

/** Person label that tolerates RLS-hidden profiles. */
export const personLabel = (p) =>
  p ? `${p.first_name} ${p.last_name}` : '\u2014';

/** Loading skeleton: n shimmering rows. */
export function skeleton(n = 4) {
  const wrap = el('div', { class: 'card' });
  for (let i = 0; i < n; i += 1) {
    wrap.append(el('div', { class: 'skel',
      style: `width:${85 - (i % 3) * 12}%;` }));
  }
  return wrap;
}
