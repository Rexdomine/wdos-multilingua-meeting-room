import { el, esc, clear, debounce } from '../core/dom.js';
import { t, fmtDate, fmtNumber } from '../core/i18n.js';
import {
  fileCase, listCases, getCase, listCaseUpdates, assignCaseHandler,
  updateCaseStatus, listOrgUnits, getMyRoles, searchAppointableMembers,
  getSession,
} from '../core/db.js';
import { renderShell } from '../components/layout.js';
import { toast, toastError } from '../components/toast.js';

const CATEGORIES = ['welfare', 'complaint', 'misconduct', 'harassment',
  'safeguarding', 'whistleblowing', 'appeal'];
const STATUSES = ['submitted', 'under_review', 'action_taken',
  'resolved', 'dismissed'];
const NEXT = {
  submitted: ['under_review', 'dismissed'],
  under_review: ['action_taken', 'resolved', 'dismissed'],
  action_taken: ['resolved', 'under_review'],
  resolved: ['under_review'],
  dismissed: ['under_review'],
};
const FAMILY = {
  submitted: 'pipeline', under_review: 'paused', action_taken: 'pipeline',
  resolved: 'active', dismissed: 'neutral',
};
const HQ_ROLES = new Set(['super_admin', 'executive_director', 'hq_team']);

export async function render(root, params, ctx) {
  const shell = renderShell(root, {
    profile: ctx.profile, modules: ctx.modules, titleKey: 'nav.cases',
  });
  const out = shell.outlet;
  const session = await getSession();
  const myId = session.user.id;
  let isHQ = false;
  try {
    isHQ = (await getMyRoles()).some((r) => HQ_ROLES.has(r.role));
  } catch { /* treated as non-HQ */ }

  if (params.id) {
    await renderDetail(out, params.id, { myId, isHQ });
  } else {
    await renderList(out, { myId, isHQ });
  }
  return shell.teardown;
}

/* ---------------- list + filing ---------------- */
async function renderList(out, { myId, isHQ }) {
  const state = { status: '', page: 0 };

  const fileBtn = el('button', { class: 'btn btn--primary',
    text: t('case.file'),
    onclick: () => { formCard.hidden = !formCard.hidden; } });
  const statusSel = el('select', { class: 'select',
    'aria-label': t('members.anyStatus'),
    onchange: (e) => { state.status = e.target.value; state.page = 0; load(); },
  }, [
    el('option', { value: '', text: t('case.anyStatus') }),
    ...STATUSES.map((s) => el('option', { value: s,
      text: t(`casestatus.${s}`) })),
  ]);

  const formCard = await buildFileForm(() => load());
  formCard.hidden = true;
  const listArea = el('div');
  out.append(
    el('p', { class: 'muted mb-4', text: t('case.confidentialNote') }),
    el('div', { class: 'toolbar' }, [statusSel,
      el('span', { class: 'grow' }), fileBtn]),
    formCard, listArea
  );
  await load();

  async function load() {
    clear(listArea);
    listArea.append(el('div', { class: 'state' }, [
      el('div', { class: 'spinner' }), el('p', { text: t('app.loading') }),
    ]));
    try {
      const { rows, total } = await listCases({ ...state });
      clear(listArea);
      if (rows.length === 0) {
        listArea.append(el('div', { class: 'card state' }, [
          el('h3', { text: t('case.emptyTitle') }),
          el('p', { text: t('case.emptyHint') }),
        ]));
        return;
      }
      const wrap = el('div', { class: 'card table-wrap' });
      const tbl = el('table', { class: 'table' });
      tbl.innerHTML = `
        <thead><tr>
          <th>${esc(t('case.no'))}</th>
          <th>${esc(t('case.category'))}</th>
          <th>${esc(t('case.subject'))}</th>
          <th>${esc(t('case.filed'))}</th>
          <th>${esc(t('members.status'))}</th>
        </tr></thead>`;
      const tbody = el('tbody');
      for (const c of rows) {
        const tr = el('tr', {
          tabindex: '0', role: 'link',
          onclick: () => { location.hash = `#/cases/${c.id}`; },
          onkeydown: (e) => {
            if (e.key === 'Enter') location.hash = `#/cases/${c.id}`;
          },
        });
        tr.innerHTML = `
          <td><strong>${esc(c.case_no)}</strong>
            ${c.reporter_id === myId
              ? `<br><span class="muted">${esc(t('case.mine'))}</span>` : ''}</td>
          <td>${esc(t(`casecat.${c.category}`))}</td>
          <td>${esc(c.subject)}</td>
          <td>${esc(fmtDate(c.created_at))}</td>
          <td><span class="badge badge--${FAMILY[c.status]}">
            ${esc(t(`casestatus.${c.status}`))}</span></td>`;
        tbody.append(tr);
      }
      tbl.append(tbody);
      wrap.append(tbl);
      listArea.append(wrap, el('p', { class: 'muted mt-4',
        text: t('case.count', { n: fmtNumber(total) }) }));
    } catch {
      clear(listArea);
      listArea.append(el('div', { class: 'card state' }, [
        el('h3', { text: t('errors.loadTitle') }),
        el('button', { class: 'btn btn--quiet', text: t('app.retry'),
          onclick: load }),
      ]));
    }
  }

  async function buildFileForm(onFiled) {
    let units = [];
    try { units = await listOrgUnits(); } catch { /* unit optional */ }
    const cat = el('select', { class: 'select' },
      CATEGORIES.map((c) => el('option', { value: c,
        text: t(`casecat.${c}`) })));
    const unitSel = el('select', { class: 'select' }, [
      el('option', { value: '', text: t('case.noUnit') }),
      ...units.map((u) => el('option', { value: u.id,
        text: `${t(`org.${u.level}`)} — ${u.name}` })),
    ]);
    const subject = el('input', { class: 'input', maxlength: '160' });
    const details = el('textarea', { class: 'input', rows: '5',
      maxlength: '8000' });
    const err = el('p', { class: 'field__error', role: 'alert', hidden: true });
    const submit = el('button', { class: 'btn btn--primary', type: 'submit',
      text: t('case.submit') });
    const form = el('form', { novalidate: true, onsubmit: async (e) => {
      e.preventDefault();
      if (subject.value.trim().length < 3) {
        err.textContent = t('tasks.errTitle'); err.hidden = false; return;
      }
      if (details.value.trim().length < 10) {
        err.textContent = t('case.errDetails'); err.hidden = false; return;
      }
      err.hidden = true;
      submit.disabled = true;
      try {
        await fileCase({
          category: cat.value,
          org_unit_id: unitSel.value,
          subject: subject.value.trim(),
          details: details.value.trim(),
        });
        toast(t('case.filed_ok'));
        form.reset();
        formCard.hidden = true;
        onFiled();
      } catch {
        err.textContent = t('errors.save'); err.hidden = false;
      } finally { submit.disabled = false; }
    } }, [
      el('div', { class: 'form-grid' }, [
        wrap(t('case.category'), cat),
        wrap(t('case.unitConcerned'), unitSel),
      ]),
      wrap(t('case.subject'), subject),
      wrap(t('case.details'), details),
      el('p', { class: 'field__hint', text: t('case.whoSees') }),
      err,
      el('div', { class: 'row' }, [el('span', { class: 'grow' }), submit]),
    ]);
    return el('div', { class: 'card mb-4' }, [
      el('div', { class: 'card__head' }, [el('h2', { text: t('case.file') })]),
      form,
    ]);
  }
}

/* ---------------- detail ---------------- */
async function renderDetail(out, id, { myId, isHQ }) {
  out.append(el('div', { class: 'state' }, [
    el('div', { class: 'spinner' }), el('p', { text: t('app.loading') }),
  ]));

  let c, updates;
  try {
    [c, updates] = await Promise.all([getCase(id), listCaseUpdates(id)]);
  } catch {
    clear(out);
    out.append(el('div', { class: 'card state' }, [
      el('h3', { text: t('case.notFound') }),
      el('p', { text: t('members.notFoundHint') }),
      el('a', { href: '#/cases', class: 'btn btn--quiet',
        text: t('case.back') }),
    ]));
    return;
  }
  const iAmReporter = c.reporter_id === myId;
  const canManage = isHQ || (!iAmReporter);  // handlers reach here via RLS
  draw();

  function draw() {
    clear(out);
    out.append(el('a', { href: '#/cases', class: 'muted',
      text: `← ${t('case.back')}` }));

    const info = el('div', { class: 'card mt-4' });
    info.innerHTML = `
      <div class="card__head">
        <h2>${esc(c.case_no)} · ${esc(t(`casecat.${c.category}`))}</h2>
        <span class="badge badge--${FAMILY[c.status]}">
          ${esc(t(`casestatus.${c.status}`))}</span>
      </div>
      <h3>${esc(c.subject)}</h3>
      <p style="white-space:pre-wrap;">${esc(c.details)}</p>
      <p class="muted">${esc(t('case.filed'))}: ${esc(fmtDate(c.created_at))}</p>`;
    out.append(info);

    /* timeline */
    const tl = el('div', { class: 'card mt-4' });
    tl.append(el('h3', { class: 'mb-4', text: t('case.timeline') }));
    if (updates.length === 0) {
      tl.append(el('p', { class: 'muted', text: t('case.noUpdates') }));
    }
    for (const u of updates) {
      tl.append(el('p', {}, [
        el('span', { class: 'muted', text: fmtDate(u.created_at) + ' — ' }),
        u.note,
        u.visible_to_reporter
          ? el('span', { class: 'badge badge--neutral',
              style: 'margin-left:8px;', text: t('case.sharedWithReporter') })
          : null,
      ]));
    }
    out.append(tl);

    if (!canManage) return;

    /* management: status change + handler assignment */
    const mgmt = el('div', { class: 'card mt-4' });
    mgmt.append(el('h3', { class: 'mb-4', text: t('case.actions') }));

    const statusSel = el('select', { class: 'select' }, [
      el('option', { value: '', text: t('case.pickStatus') }),
      ...(NEXT[c.status] ?? []).map((s) => el('option', { value: s,
        text: t(`casestatus.${s}`) })),
    ]);
    const note = el('textarea', { class: 'input', rows: '3',
      maxlength: '4000', placeholder: t('case.notePlaceholder') });
    const visible = el('input', { type: 'checkbox', id: 'case-visible' });
    const actBtn = el('button', { class: 'btn btn--primary',
      text: t('case.applyStatus'),
      onclick: async (e) => {
        if (!statusSel.value) { toastError(t('case.errPickStatus')); return; }
        if (note.value.trim().length < 5) {
          toastError(t('recruit.errReason')); return;
        }
        e.target.disabled = true;
        try {
          c = await updateCaseStatus(c.id, statusSel.value,
            note.value.trim(), visible.checked);
          updates = await listCaseUpdates(c.id);
          toast(t('case.updated'));
          draw();
        } catch (err) {
          toastError(mapError(err));
          e.target.disabled = false;
        }
      } });
    mgmt.append(
      el('div', { class: 'form-grid' }, [
        wrap(t('case.newStatus'), statusSel),
        el('div', { class: 'field' }, [
          el('label', { class: 'field__label', for: 'case-visible',
            text: t('case.visibleLabel') }),
          el('div', { class: 'row' }, [visible,
            el('span', { class: 'muted', text: t('case.visibleHint') })]),
        ]),
      ]),
      wrap(t('case.note'), note),
      el('div', { class: 'row' }, [el('span', { class: 'grow' }), actBtn])
    );

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
        el('h3', { class: 'mb-4 mt-4', text: t('case.assignTitle') }),
        el('p', { class: 'muted', text: t('case.assignHint') }),
        el('div', { class: 'form-grid' }, [
          wrap(t('org.searchMember'), search, who),
        ]),
        el('div', { class: 'row' }, [
          el('span', { class: 'grow' }),
          el('button', { class: 'btn btn--secondary', text: t('case.assign'),
            onclick: async (e) => {
              if (!who.value) { toastError(t('org.errPickMember')); return; }
              e.target.disabled = true;
              try {
                await assignCaseHandler(c.id, who.value);
                toast(t('case.assigned'));
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
  if (m.includes('assigned handler')) return t('case.errManageAuth');
  if (m.includes('Only Headquarters')) return t('case.errAssignAuth');
  if (m.includes('Invalid case transition')) return t('case.errTransition');
  if (m.includes('note is required')) return t('recruit.errReason');
  return t('errors.save');
}
