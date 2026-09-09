/**
 * Toast notifications. One container, auto-dismiss, screen-reader
 * announced via role="status" / role="alert".
 */
import { el } from '../core/dom.js';

function container() {
  let c = document.querySelector('.toasts');
  if (!c) {
    c = el('div', { class: 'toasts' });
    document.body.append(c);
  }
  return c;
}

let lastMsg = ''; let lastAt = 0;

export function toast(message, kind = 'ok', ms = 4500) {
  const now = Date.now();
  if (message === lastMsg && now - lastAt < 2500) return;
  lastMsg = message; lastAt = now;
  const node = el('div', {
    class: `toast toast--${kind}`,
    role: kind === 'error' ? 'alert' : 'status',
  }, [
    el('span', { text: message }),
    el('button', {
      class: 'btn btn--icon', 'aria-label': '×', text: '×',
      style: 'background:transparent;color:#fff;min-height:auto;padding:0 4px;',
      onclick: () => node.remove(),
    }),
  ]);
  container().append(node);
  if (ms > 0) setTimeout(() => node.remove(), ms);
}

export const toastError = (msg) => toast(msg, 'error', 7000);
