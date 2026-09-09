import { el, clear } from '../core/dom.js';

let overlay = null;

/** Action modal / bottom sheet (mobile). Returns a close function. */
export function openModal(title, contentNode) {
  closeModal();
  const panel = el('div', { class: 'modal__panel', role: 'dialog',
    'aria-modal': 'true', 'aria-label': title });
  panel.append(
    el('div', { class: 'row mb-4' }, [
      el('h2', { class: 'grow', text: title }),
      el('button', { class: 'btn btn--icon btn--quiet',
        'aria-label': 'Close', text: '\u2715',
        onclick: closeModal }),
    ]),
    contentNode);
  overlay = el('div', { class: 'modal', onclick: (e) => {
    if (e.target === overlay) closeModal();
  } }, [panel]);
  document.body.append(overlay);
  document.addEventListener('keydown', escClose);
  return closeModal;
}

function escClose(e) { if (e.key === 'Escape') closeModal(); }

export function closeModal() {
  document.removeEventListener('keydown', escClose);
  overlay?.remove();
  overlay = null;
}
