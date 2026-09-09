import { el, esc, clear } from '../core/dom.js';
import { t, fmtDate, fmtNumber } from '../core/i18n.js';
import {
  listApplications, getApplication, reviewApplication,
  recommendApplication, decideApplication, getMyRoles, isApprover, listOrgUnits,
  listVolunteerApps, decideVolunteer } from '../core/db.js';
import { renderShell } from '../components/layout.js';
import { toast, toastError } from '../components/toast.js';

const PAGE_SIZE = 25;
const FAMILY = {
  submitted: 'pipeline', under_review: 'pipeline', recommended: 'pipeline',
  approved: 'active', rejected: 'exited', withdrawn: 'neutral',
};

export async function render(root, params, ctx) {
  const shell = renderShell(root, {
    profile: ctx.profile, modules: ctx.modules, titleKey: 'nav.recruitment',
  });
  const out = shell.outlet;

  if (params.id) {
    await renderDetail(out, params.id, ctx);
  } else {
    await renderList(out);
  }
  /* ---- Institute volunteer bridge queue ---- */
  try {
    const vols = await listVolunteerApps();
    if (vols.length > 0) {
      const units = await listOrgUnits();
      const countries = units.filter((u) => u.level === 'country');
      out.append(el('h2', { class: 'mb-4 mt-4', text: t('vol.title') }));
      for (const v of vols) {
        const unitSel = el('select', { class: 'select' },
          countries.map((u) => el('option', { value: u.id, text: u.name,
            selected: u.name === v.country || null })));
        const reason = el('input', { class: 'input', maxlength: '500',
          placeholder: t('recruit.reasonHint') });
        const pay = el('details', { class: 'acc' }, [
          el('summary', { text: t('vol.fullDetails') }),
          el('div', {}, [el('pre', {
            style: 'white-space:pre-wrap;font-size:12px;',
            text: JSON.stringify(v.payload, null, 2) })]),
        ]);
        out.append(el('div', { class: 'card mb-4' }, [
          el('div', { class: 'card__head' }, [
            el('h3', { text: `${v.full_name} — ${v.email}` }),
            el('span', { class: 'badge badge--pipeline',
              text: `${v.network ?? ''} · ${v.country ?? ''}` }),
          ]),
          pay,
          el('div', { class: 'row mt-4' }, [unitSel, reason,
            el('button', { class: 'btn btn--primary', text: t('recruit.approve'),
              onclick: async (e) => {
                if (reason.value.trim().length < 5) {
                  toastError(t('recruit.errReason')); return; }
                e.target.disabled = true;
                try { await decideVolunteer(v.id, true, unitSel.value,
                    reason.value.trim());
                  toast(t('vol.approved'));
                  e.target.closest('.card').remove();
                } catch (err) { toastError(err?.message || t('errors.save'));
                  e.target.disabled = false; }
              } }),
            el('button', { class: 'btn btn--quiet', text: t('recruit.reject'),
              onclick: async (e) => {
                if (reason.value.trim().length < 5) {
                  toastError(t('recruit.errReason')); return; }
                e.target.disabled = true;
                try { await decideVolunteer(v.id, false, unitSel.value,
                    reason.value.trim());
                  toast(t('vol.rejected'));
                  e.target.closest('.card').remove();
                } catch (err) { toastError(err?.message || t('errors.save'));
                  e.target.disabled = false; }
              } }),
          ]),
        ]));
      }
    }
  } catch { /* bridge queue optional */ }

  return shell.teardown;
}

/* ---------------- list ---------------- */

async function renderList(out) {
  const state = { status: '', page: 0 };
  const statusSel = el('select', {
    class: 'select', 'aria-label': t('members.anyStatus'),
    onchange: (e) => { state.status = e.target.value; state.page = 0; load(); },
  }, [
    el('option', { value: '', text: t('recruit.anyStatus') }),
    ...Object.keys(FAMILY).map((s) =>
      el('option', { value: s, text: t(`appstatus.${s}`) })),
  ]);
  const listArea = el('div');
  out.append(el('div', { class: 'toolbar' }, [statusSel]), listArea);
  await load();

  async function load() {
    clear(listArea);
    listArea.append(el('div', { class: 'state' }, [
      el('div', { class: 'spinner' }), el('p', { text: t('app.loading') }),
    ]));
    try {
      const { rows, total } = await listApplications({ ...state, pageSize: PAGE_SIZE });
      clear(listArea);
      if (rows.length === 0) {
        listArea.append(el('div', { class: 'card state' }, [
          el('h3', { text: t('recruit.emptyTitle') }),
          el('p', { text: state.status
            ? t('members.emptyFiltered') : t('recruit.emptyHint') }),
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
        <th>${esc(t('members.network'))}</th>
        <th>${esc(t('recruit.applied'))}</th>
        <th>${esc(t('members.status'))}</th>
      </tr></thead>`;
    const tbody = el('tbody');
    for (const r of rows) {
      const tr = el('tr', {
        tabindex: '0', role: 'link',
        onclick: () => { location.hash = `#/recruitment/${r.id}`; },
        onkeydown: (e) => {
          if (e.key === 'Enter') location.hash = `#/recruitment/${r.id}`;
        },
      });
      tr.innerHTML = `
        <td><strong>${esc(r.first_name)} ${esc(r.last_name)}</strong><br>
            <span class="muted">${esc(r.email)}</span></td>
        <td>${esc(r.network)}</td>
        <td>${esc(fmtDate(r.created_at))}</td>
        <td><span class="badge badge--${FAMILY[r.status]}">
            ${esc(t(`appstatus.${r.status}`))}</span></td>`;
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
        text: t('recruit.count', { n: fmtNumber(total) }) }),
      el('button', { class: 'btn btn--quiet', text: t('app.prev'),
        disabled: state.page === 0 || null,
        onclick: () => { state.page -= 1; load(); } }),
      el('span', { class: 'muted', text: `${state.page + 1} / ${pages}` }),
      el('button', { class: 'btn btn--quiet', text: t('app.next'),
        disabled: state.page >= pages - 1 || null,
        onclick: () => { state.page += 1; load(); } }),
    ]);
  }
}

/* ---------------- detail + workflow actions ---------------- */

async function renderDetail(out, id, ctx) {
  out.append(el('div', { class: 'state' }, [
    el('div', { class: 'spinner' }), el('p', { text: t('app.loading') }),
  ]));

  let app, roles, units;
  try {
    [app, roles, units] = await Promise.all([
      getApplication(id), getMyRoles(), listOrgUnits(),
    ]);
  } catch {
    clear(out);
    out.append(el('div', { class: 'card state' }, [
      el('h3', { text: t('recruit.notFoundTitle') }),
      el('p', { text: t('members.notFoundHint') }),
      el('a', { href: '#/recruitment', class: 'btn btn--quiet',
        text: t('recruit.backToQueue') }),
    ]));
    return;
  }
  draw();

  function draw() {
    clear(out);
    const unitName = units.find((u) => u.id === app.org_unit_id)?.name ?? '—';
    const open = ['submitted', 'under_review', 'recommended'].includes(app.status);
    const approver = isApprover(roles);

    out.append(el('a', { href: '#/recruitment', class: 'muted',
      text: `← ${t('recruit.backToQueue')}` }));

    const info = el('div', { class: 'card mt-4' });
    info.innerHTML = `
      <div class="card__head">
        <h2>${esc(app.first_name)} ${esc(app.last_name)}</h2>
        <span class="badge badge--${FAMILY[app.status]}">
          ${esc(t(`appstatus.${app.status}`))}</span>
      </div>
      <p><strong>${esc(t('auth.email'))}:</strong> ${esc(app.email)}<br>
         <strong>${esc(t('members.phone'))}:</strong> ${esc(app.phone ?? '—')}<br>
         <strong>${esc(t('members.network'))}:</strong> ${esc(app.network)}<br>
         <strong>${esc(t('apply.chapter'))}:</strong> ${esc(unitName)}<br>
         <strong>${esc(t('recruit.applied'))}:</strong> ${esc(fmtDate(app.created_at))}</p>
      <h3>${esc(t('apply.motivation'))}</h3>
      <p>${esc(app.motivation)}</p>
      ${app.reviewer_notes ? `
        <h3>${esc(t('recruit.reviewerNotes'))}</h3>
        <p>${esc(app.reviewer_notes)}</p>` : ''}
      ${app.decision_reason ? `
        <h3>${esc(t('recruit.decisionReason'))}</h3>
        <p>${esc(app.decision_reason)}
           <span class="muted">(${esc(fmtDate(app.decided_at))})</span></p>` : ''}
      ${app.status === 'approved' && !app.profile_id ? `
        <p class="muted">${esc(t('recruit.awaitingAccount'))}</p>` : ''}`;
    out.append(info);

    if (!open) return;

    const notes = el('textarea', {
      class: 'input', rows: '3', maxlength: '2000',
      placeholder: t('recruit.notesPlaceholder'),
    });
    if (app.reviewer_notes) notes.value = app.reviewer_notes;
    const reason = el('textarea', {
      class: 'input', rows: '2', maxlength: '1000',
      placeholder: t('recruit.reasonPlaceholder'),
    });

    const actions = el('div', { class: 'card mt-4' }, [
      el('h3', { class: 'mb-4', text: t('recruit.actions') }),
      el('div', { class: 'field' }, [notes]),
    ]);

    if (app.status === 'submitted') {
      actions.append(btn('btn--primary', t('recruit.startReview'), () =>
        run(() => reviewApplication(app.id, notes.value.trim()))));
    }
    if (app.status === 'under_review') {
      actions.append(btn('btn--primary', t('recruit.recommend'), () => {
        if (notes.value.trim().length < 5) {
          toastError(t('recruit.errNotes')); return;
        }
        run(() => recommendApplication(app.id, notes.value.trim()));
      }));
    }
    if (approver) {
      actions.append(
        el('div', { class: 'field mt-4' }, [
          el('label', { class: 'field__label', text: t('recruit.decisionReason') }),
          reason,
          el('p', { class: 'field__hint', text: t('members.changeReasonHint') }),
        ]),
        el('div', { class: 'row' }, [
          btn('btn--secondary', t('recruit.approve'), () => decide(true)),
          btn('btn--danger', t('recruit.reject'), () => decide(false)),
        ])
      );
    }
    out.append(actions);

    function decide(approve) {
      if (reason.value.trim().length < 5) {
        toastError(t('recruit.errReason')); return;
      }
      run(() => decideApplication(app.id, approve, reason.value.trim()));
    }

    async function run(fn) {
      try {
        app = await fn();
        toast(t('recruit.updated'));
        draw();
      } catch (err) {
        toastError(mapError(err));
      }
    }
  }
}

function btn(kind, text, onclick) {
  return el('button', { class: `btn ${kind}`, text, onclick });
}

function mapError(err) {
  const m = String(err?.message ?? '');
  if (m.includes('not a reviewer')) return t('recruit.errNotReviewer');
  if (m.includes('not an approver')) return t('recruit.errNotApprover');
  if (m.includes('already been decided')) return t('recruit.errDecided');
  if (m.includes('notes are required')) return t('recruit.errNotes');
  if (m.includes('reason is required')) return t('recruit.errReason');
  return t('errors.save');
}
