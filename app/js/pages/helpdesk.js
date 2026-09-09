import { el, esc, clear, debounce } from '../core/dom.js';
import { t, fmtDate, fmtDateTime, fmtNumber } from '../core/i18n.js';
import {
  fileTicket, listTickets, getTicket, listTicketMessages, addTicketMessage,
  assignTicket, setTicketStatus, getMyRoles, searchAppointableMembers,
  getSession,
} from '../core/db.js';
import { renderShell } from '../components/layout.js';
import { toast, toastError } from '../components/toast.js';

const CATEGORIES = ['login', 'app_problem', 'certificate', 'role_access',
  'training_access', 'technical', 'other'];
const STATUSES = ['open', 'in_progress', 'waiting_on_user', 'resolved', 'closed'];
const NEXT = {
  open: ['in_progress', 'waiting_on_user', 'resolved', 'closed'],
  in_progress: ['waiting_on_user', 'resolved', 'closed', 'open'],
  waiting_on_user: ['in_progress', 'resolved', 'closed'],
  resolved: ['closed', 'in_progress'],
  closed: ['open'],
};
const FAMILY = {
  open: 'pipeline', in_progress: 'paused', waiting_on_user: 'neutral',
  resolved: 'active', closed: 'exited',
};
const HQ_ROLES = new Set(['super_admin', 'executive_director', 'hq_team']);

export async function render(root, params, ctx) {
  const shell = renderShell(root, {
    profile: ctx.profile, modules: ctx.modules, titleKey: 'nav.helpdesk',
  });
  const out = shell.outlet;
  const session = await getSession();
  const myId = session.user.id;
  let isHQ = false;
  try {
    isHQ = (await getMyRoles()).some((r) => HQ_ROLES.has(r.role));
  } catch { /* non-HQ */ }

  if (params.id) await renderDetail(out, params.id, { myId, isHQ });
  else await renderList(out);
  return shell.teardown;
}

/* ---------------- list + new ticket ---------------- */
async function renderList(out) {
  const state = { status: '', page: 0 };
  const statusSel = el('select', { class: 'select',
    'aria-label': t('members.anyStatus'),
    onchange: (e) => { state.status = e.target.value; load(); } }, [
    el('option', { value: '', text: t('help.anyStatus') }),
    ...STATUSES.map((s) => el('option', { value: s,
      text: t(`ticketstatus.${s}`) })),
  ]);
  const newBtn = el('button', { class: 'btn btn--primary',
    text: t('help.new'),
    onclick: () => { formCard.hidden = !formCard.hidden; } });

  const formCard = buildForm(() => load());
  formCard.hidden = true;
  const listArea = el('div');
  out.append(
    el('div', { class: 'toolbar' }, [statusSel,
      el('span', { class: 'grow' }), newBtn]),
    formCard, listArea
  );
  await load();

  async function load() {
    clear(listArea);
    listArea.append(el('div', { class: 'state' }, [
      el('div', { class: 'spinner' }), el('p', { text: t('app.loading') }),
    ]));
    try {
      const { rows, total } = await listTickets({ ...state });
      clear(listArea);
      if (rows.length === 0) {
        listArea.append(el('div', { class: 'card state' }, [
          el('h3', { text: t('help.emptyTitle') }),
          el('p', { text: t('help.emptyHint') }),
        ]));
        return;
      }
      const wrap = el('div', { class: 'card table-wrap' });
      const tbl = el('table', { class: 'table' });
      tbl.innerHTML = `
        <thead><tr>
          <th>${esc(t('help.no'))}</th>
          <th>${esc(t('case.category'))}</th>
          <th>${esc(t('case.subject'))}</th>
          <th>${esc(t('tasks.priority'))}</th>
          <th>${esc(t('members.status'))}</th>
        </tr></thead>`;
      const tbody = el('tbody');
      for (const x of rows) {
        const tr = el('tr', {
          tabindex: '0', role: 'link',
          onclick: () => { location.hash = `#/helpdesk/${x.id}`; },
          onkeydown: (e) => {
            if (e.key === 'Enter') location.hash = `#/helpdesk/${x.id}`;
          },
        });
        tr.innerHTML = `
          <td><strong>${esc(x.ticket_no)}</strong><br>
            <span class="muted">${esc(fmtDateTime(x.created_at))}</span></td>
          <td>${esc(t(`ticketcat.${x.category}`))}</td>
          <td>${esc(x.subject)}</td>
          <td>${esc(t(`taskprio.${x.priority}`))}</td>
          <td><span class="badge badge--${FAMILY[x.status]}">
            ${esc(t(`ticketstatus.${x.status}`))}</span></td>`;
        tbody.append(tr);
      }
      tbl.append(tbody);
      wrap.append(tbl);
      listArea.append(wrap, el('p', { class: 'muted mt-4',
        text: t('help.count', { n: fmtNumber(total) }) }));
    } catch {
      clear(listArea);
      listArea.append(el('div', { class: 'card state' }, [
        el('h3', { text: t('errors.loadTitle') }),
        el('button', { class: 'btn btn--quiet', text: t('app.retry'),
          onclick: load }),
      ]));
    }
  }

  function buildForm(onFiled) {
    const cat = el('select', { class: 'select' },
      CATEGORIES.map((c) => el('option', { value: c,
        text: t(`ticketcat.${c}`) })));
    const prio = el('select', { class: 'select' },
      ['low', 'medium', 'high', 'urgent'].map((p) =>
        el('option', { value: p, selected: p === 'medium' || null,
          text: t(`taskprio.${p}`) })));
    const subject = el('input', { class: 'input', maxlength: '160' });
    const details = el('textarea', { class: 'input', rows: '4',
      maxlength: '4000', placeholder: t('help.detailsHint') });
    const err = el('p', { class: 'field__error', role: 'alert', hidden: true });
    const submit = el('button', { class: 'btn btn--primary', type: 'submit',
      text: t('help.submit') });
    const form = el('form', { novalidate: true, onsubmit: async (e) => {
      e.preventDefault();
      if (subject.value.trim().length < 3) {
        err.textContent = t('tasks.errTitle'); err.hidden = false; return;
      }
      if (details.value.trim().length < 5) {
        err.textContent = t('help.errDetails'); err.hidden = false; return;
      }
      err.hidden = true;
      submit.disabled = true;
      try {
        const filed = await fileTicket({
          category: cat.value, priority: prio.value,
          subject: subject.value.trim(), details: details.value.trim(),
        });
        toast(filed?.ticket_no
          ? t('help.filedRef', { ref: filed.ticket_no })
          : t('help.filed'));
        form.reset();
        formCard.hidden = true;
        onFiled();
      } catch { err.textContent = t('errors.save'); err.hidden = false; }
      finally { submit.disabled = false; }
    } }, [
      el('div', { class: 'form-grid' }, [
        wrap(t('case.category'), cat),
        wrap(t('tasks.priority'), prio),
      ]),
      wrap(t('case.subject'), subject),
      wrap(t('help.details'), details),
      err,
      el('div', { class: 'row' }, [el('span', { class: 'grow' }), submit]),
    ]);
    return el('div', { class: 'card mb-4' }, [
      el('div', { class: 'card__head' }, [el('h2', { text: t('help.new') })]),
      form,
    ]);
  }
}

/* ---------------- detail + thread ---------------- */
async function renderDetail(out, id, { myId, isHQ }) {
  out.append(el('div', { class: 'state' }, [
    el('div', { class: 'spinner' }), el('p', { text: t('app.loading') }),
  ]));

  let x, msgs;
  try {
    [x, msgs] = await Promise.all([getTicket(id), listTicketMessages(id)]);
  } catch {
    clear(out);
    out.append(el('div', { class: 'card state' }, [
      el('h3', { text: t('help.notFound') }),
      el('a', { href: '#/helpdesk', class: 'btn btn--quiet',
        text: t('help.back') }),
    ]));
    return;
  }
  draw();

  function draw() {
    clear(out);
    const iAmRequester = x.requester_id === myId;
    const canManage = isHQ || x.assigned_to === myId;

    out.append(el('a', { href: '#/helpdesk', class: 'muted',
      text: `← ${t('help.back')}` }));

    const info = el('div', { class: 'card mt-4' });
    info.innerHTML = `
      <div class="card__head">
        <h2>${esc(x.ticket_no)} · ${esc(t(`ticketcat.${x.category}`))}</h2>
        <span class="badge badge--${FAMILY[x.status]}">
          ${esc(t(`ticketstatus.${x.status}`))}</span>
      </div>
      <h3>${esc(x.subject)}</h3>
      <p style="white-space:pre-wrap;">${esc(x.details)}</p>
      <p class="muted">${esc(t('case.filed'))}: ${esc(fmtDate(x.created_at))}
        · ${esc(t(`taskprio.${x.priority}`))}</p>`;
    out.append(info);

    /* thread */
    const thread = el('div', { class: 'card mt-4' });
    thread.append(el('h3', { class: 'mb-4', text: t('help.thread') }));
    if (msgs.length === 0) {
      thread.append(el('p', { class: 'muted', text: t('help.noMessages') }));
    }
    for (const m of msgs) {
      thread.append(el('p', {}, [
        el('span', { class: 'muted', text: fmtDateTime(m.created_at) + ' — ' }),
        el('span', {
          text: (m.author_id === x.requester_id
            ? t('help.fromRequester') : t('help.fromSupport')) + ': ' }),
        m.body,
      ]));
    }
    if (x.status !== 'closed') {
      const reply = el('textarea', { class: 'input', rows: '3',
        maxlength: '4000', placeholder: t('help.replyHint') });
      thread.append(
        el('div', { class: 'field mt-4' }, [reply]),
        el('div', { class: 'row' }, [
          el('span', { class: 'grow' }),
          el('button', { class: 'btn btn--primary', text: t('help.reply'),
            onclick: async (e) => {
              if (!reply.value.trim()) return;
              e.target.disabled = true;
              try {
                await addTicketMessage(x.id, reply.value.trim());
                msgs = await listTicketMessages(x.id);
                toast(t('help.sent'));
                draw();
              } catch { toastError(t('errors.save'));
                e.target.disabled = false; }
            } }),
        ])
      );
    }
    out.append(thread);

    /* actions */
    const allowed = (NEXT[x.status] ?? []).filter((s) =>
      canManage || (iAmRequester && ['closed', 'open'].includes(s)));
    if (allowed.length === 0 && !isHQ) return;

    const mgmt = el('div', { class: 'card mt-4' });
    mgmt.append(el('h3', { class: 'mb-4', text: t('case.actions') }));

    if (allowed.length > 0) {
      const statusSel = el('select', { class: 'select' }, [
        el('option', { value: '', text: t('case.pickStatus') }),
        ...allowed.map((s) => el('option', { value: s,
          text: t(`ticketstatus.${s}`) })),
      ]);
      mgmt.append(el('div', { class: 'row' }, [
        statusSel,
        el('button', { class: 'btn btn--primary', text: t('case.applyStatus'),
          onclick: async (e) => {
            if (!statusSel.value) { toastError(t('case.errPickStatus')); return; }
            e.target.disabled = true;
            try {
              x = await setTicketStatus(x.id, statusSel.value);
              toast(t('help.updated'));
              draw();
            } catch (err) { toastError(mapError(err));
              e.target.disabled = false; }
          } }),
      ]));
    }

    if (isHQ) {
      const search = el('input', { class: 'input', type: 'search',
        placeholder: t('org.searchMember') });
      const who = el('select', { class: 'select', size: '3' });
      search.addEventListener('input', debounce(async () => {
        try {
          const rows = await searchAppointableMembers(search.value.trim());
          clear(who);
          for (const r of rows) {
            who.append(el('option', { value: r.id,
              text: `${r.first_name} ${r.last_name} — ${r.email}` }));
          }
        } catch { toastError(t('errors.load')); }
      }));
      mgmt.append(
        el('h3', { class: 'mb-4 mt-4', text: t('help.assignTitle') }),
        el('div', { class: 'form-grid' }, [
          wrap(t('org.searchMember'), search, who),
        ]),
        el('div', { class: 'row' }, [
          el('span', { class: 'grow' }),
          el('button', { class: 'btn btn--secondary', text: t('help.assign'),
            onclick: async (e) => {
              if (!who.value) { toastError(t('org.errPickMember')); return; }
              e.target.disabled = true;
              try {
                x = await assignTicket(x.id, who.value);
                toast(t('help.assigned'));
                draw();
              } catch (err) { toastError(mapError(err)); }
              finally { e.target.disabled = false; }
            } }),
        ])
      );
    }
    out.append(mgmt);
  }
}

function wrap(label, ...controls) {
  return el('div', { class: 'field' }, [
    el('label', { class: 'field__label', text: label }), ...controls,
  ]);
}

function mapError(err) {
  const m = String(err?.message ?? '');
  if (m.includes('assigned officer')) return t('help.errManageAuth');
  if (m.includes('Only Headquarters')) return t('help.errAssignAuth');
  if (m.includes('Invalid ticket transition')) return t('help.errTransition');
  return t('errors.save');
}
