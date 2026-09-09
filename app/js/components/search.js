import { el, clear, debounce } from '../core/dom.js';
import { t } from '../core/i18n.js';
import { globalSearch } from '../core/db.js';
import { openModal } from './modal.js';

export function openSearch() {
  const input = el('input', { class: 'input', type: 'search',
    placeholder: t('search.hint'), autofocus: true });
  const results = el('div', { class: 'mt-4' });
  input.addEventListener('input', debounce(async () => {
    const q = input.value.trim();
    clear(results);
    if (q.length < 2) return;
    results.append(el('div', { class: 'spinner' }));
    try {
      const r = await globalSearch(q);
      clear(results);
      section(t('search.members'), r.members.map((m) => [
        `${m.first_name} ${m.last_name}` +
          (m.membership_no ? ` · ${m.membership_no}` : ''),
        `#/members/${m.id}`]));
      section(t('search.tasks'), r.tasks.map((x) =>
        [x.title, '#/tasks']));
      section(t('search.tickets'), r.tickets.map((x) =>
        [`${x.ticket_no} · ${x.subject}`, `#/helpdesk/${x.id}`]));
      if (!results.childElementCount) {
        results.append(el('p', { class: 'muted', text: t('search.none') }));
      }
    } catch {
      clear(results);
      results.append(el('p', { class: 'field__error',
        text: t('errors.load') }));
    }
  }, 250));
  function section(label, rows) {
    if (rows.length === 0) return;
    results.append(el('p', { class: 'muted', text: label }));
    for (const [text, href] of rows) {
      results.append(el('a', { class: 'search__row', href, text,
        onclick: () => document.querySelector('.modal')?.remove() }));
    }
  }
  openModal(t('search.title'), el('div', {}, [input, results]));
  setTimeout(() => input.focus(), 30);
}
