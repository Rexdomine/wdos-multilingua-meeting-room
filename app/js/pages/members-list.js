import { el, esc, clear, debounce } from '../core/dom.js';
import { t, fmtDate, fmtNumber } from '../core/i18n.js';
import { listMembers } from '../core/db.js';
import { renderShell } from '../components/layout.js';

const PAGE_SIZE = 25;

const STATUS_FAMILY = {
  applicant: 'pipeline', under_review: 'pipeline', approved: 'pipeline',
  activated: 'active', in_training: 'active', active: 'active',
  reinstated: 'active',
  inactive: 'paused', suspended: 'paused',
  resigned: 'exited', removed: 'exited',
  alumni: 'neutral',
};

const STATUSES = Object.keys(STATUS_FAMILY);

export async function render(root, _params, ctx) {
  const shell = renderShell(root, {
    profile: ctx.profile, modules: ctx.modules, titleKey: 'nav.members',
  });
  const out = shell.outlet;

  const state = { search: '', status: '', network: '', page: 0 };

  const search = el('input', {
    class: 'input', type: 'search', placeholder: t('members.search'),
    'aria-label': t('members.search'),
    oninput: debounce((e) => { state.search = e.target.value; state.page = 0; load(); }),
  });
  const statusSel = filterSelect(t('members.anyStatus'),
    STATUSES.map((s) => [s, t(`status.${s}`)]),
    (v) => { state.status = v; state.page = 0; load(); });
  const networkSel = filterSelect(t('members.anyNetwork'),
    [['WGMN', 'WGMN'], ['WNNN', 'WNNN']],
    (v) => { state.network = v; state.page = 0; load(); });

  const listArea = el('div');
  out.append(
    el('div', { class: 'toolbar' }, [search, statusSel, networkSel]),
    listArea
  );
  await load();
  return shell.teardown;

  async function load() {
    clear(listArea);
    listArea.append(el('div', { class: 'state' }, [
      el('div', { class: 'spinner' }),
      el('p', { text: t('app.loading') }),
    ]));
    try {
      const { rows, total } = await listMembers({ ...state, pageSize: PAGE_SIZE });
      clear(listArea);
      if (rows.length === 0) {
        listArea.append(el('div', { class: 'card state' }, [
          el('h3', { text: t('members.emptyTitle') }),
          el('p', { text: state.search || state.status || state.network
            ? t('members.emptyFiltered') : t('members.emptyAll') }),
        ]));
        return;
      }
      listArea.append(table(rows), pager(total));
    } catch {
      clear(listArea);
      listArea.append(el('div', { class: 'card state' }, [
        el('h3', { text: t('errors.loadTitle') }),
        el('p', { text: t('errors.loadHint') }),
        el('button', { class: 'btn btn--quiet', text: t('app.retry'), onclick: load }),
      ]));
    }
  }

  function table(rows) {
    const wrap = el('div', { class: 'card table-wrap' });
    const tbl = el('table', { class: 'table' });
    tbl.innerHTML = `
      <thead><tr>
        <th>${esc(t('members.name'))}</th>
        <th>${esc(t('members.membershipNo'))}</th>
        <th>${esc(t('members.network'))}</th>
        <th>${esc(t('members.status'))}</th>
        <th>${esc(t('members.joined'))}</th>
      </tr></thead>`;
    const tbody = el('tbody');
    for (const r of rows) {
      const tr = el('tr', {
        tabindex: '0', role: 'link',
        onclick: () => { location.hash = `#/members/${r.id}`; },
        onkeydown: (e) => {
          if (e.key === 'Enter') location.hash = `#/members/${r.id}`;
        },
      });
      tr.innerHTML = `
        <td><strong>${esc(r.first_name)} ${esc(r.last_name)}</strong><br>
            <span class="muted">${esc(r.email)}</span></td>
        <td>${esc(r.membership_no ?? '—')}</td>
        <td>${esc(r.network)}</td>
        <td><span class="badge badge--${STATUS_FAMILY[r.status]}">
            ${esc(t(`status.${r.status}`))}</span></td>
        <td>${esc(fmtDate(r.created_at))}</td>`;
      tbody.append(tr);
    }
    tbl.append(tbody);
    wrap.append(tbl);
    return wrap;
  }

  function pager(total) {
    const pages = Math.max(1, Math.ceil(total / PAGE_SIZE));
    return el('div', { class: 'row mt-4' }, [
      el('span', { class: 'muted grow',
        text: t('members.count', { n: fmtNumber(total) }) }),
      el('button', {
        class: 'btn btn--quiet', text: t('app.prev'),
        disabled: state.page === 0 || null,
        onclick: () => { state.page -= 1; load(); },
      }),
      el('span', { class: 'muted',
        text: `${state.page + 1} / ${pages}` }),
      el('button', {
        class: 'btn btn--quiet', text: t('app.next'),
        disabled: state.page >= pages - 1 || null,
        onclick: () => { state.page += 1; load(); },
      }),
    ]);
  }
}

function filterSelect(anyLabel, options, onChange) {
  return el('select', {
    class: 'select', 'aria-label': anyLabel,
    onchange: (e) => onChange(e.target.value),
  }, [
    el('option', { value: '', text: anyLabel }),
    ...options.map(([v, label]) => el('option', { value: v, text: label })),
  ]);
}
