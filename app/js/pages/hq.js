import { el, esc, clear, debounce, renderMarkup } from '../core/dom.js';
import { t, fmtDate, fmtDateTime, fmtNumber } from '../core/i18n.js';
import { db, listDepartments, listStaff, addStaff, listStaffReports, submitStaffReport,
  avatarUrl, uploadAvatar, createTask, getHqUnitId,
  listStaffMessages, sendStaffMessage, markMessageRead, staffFileUrl,
  updateStaffReport, reviewStaffReport, getMyRoles,
  searchAppointableMembers, getSession,
} from '../core/db.js';
import { renderShell } from '../components/layout.js';
import { toast, toastError } from '../components/toast.js';

const HQ_ROLES = new Set(['super_admin', 'executive_director', 'hq_team']);
const R_FAMILY = { submitted: 'pipeline', revision_requested: 'paused',
  approved: 'active' };
const PERIODS = ['daily', 'weekly', 'monthly'];

export async function render(root, _params, ctx) {
  const shell = renderShell(root, {
    profile: ctx.profile, modules: ctx.modules, titleKey: 'nav.hq',
  });
  const out = shell.outlet;

  /* WODDI Rooms — live group calls (Phase 51) */
  const roomCard = el('div', { class: 'card mb-4 room-card--hq' }, [
    el('div', { class: 'card__head' }, [
      el('h2', { text: t('room.hqCardTitle') }),
      el('a', { href: '#/room', class: 'btn btn--primary',
        text: t('room.open') }),
    ]),
    el('p', { class: 'muted', text: t('room.hqCardHint') }),
  ]);
  const session = await getSession();
  const myId = session.user.id;
  let isExec = false;
  try {
    isExec = (await getMyRoles()).some((r) => HQ_ROLES.has(r.role));
  } catch { /* non-exec */ }
  out.append(roomCard);

  out.append(el('div', { class: 'state' }, [
    el('div', { class: 'spinner' }), el('p', { text: t('app.loading') }),
  ]));

  let departments, staffRows;
  try {
    [departments, staffRows] = await Promise.all([
      listDepartments(), listStaff(),
    ]);
  } catch {
    clear(out);
    out.append(roomCard);
    out.append(el('div', { class: 'card state' }, [
      el('h3', { text: t('errors.loadTitle') }),
      el('p', { text: t('errors.loadHint') }),
      el('button', { class: 'btn btn--quiet', text: t('app.retry'),
        onclick: () => render(root, _params, ctx) }),
    ]));
    return shell.teardown;
  }

  const iAmStaff = staffRows.some((s) => s.profile_id === myId);
  const safeName = (st) => st?.person
    ? `${st.person.first_name} ${st.person.last_name}` : '\u2014';
  clear(out);
  out.append(roomCard);

  /* ---------- section: my report (staff only) ---------- */
  if (iAmStaff) out.append(myReportCard());

  /* ---------- section: review queue (managers/execs) ---------- */
  const managesSomeone = staffRows.some((s) => s.reports_to === myId);
  if (isExec || managesSomeone) {
    const queue = el('div');
    out.append(el('h2', { class: 'mb-4 mt-4', text: t('hq.queueTitle') }), queue);
    loadQueue(queue);
  }

  /* ---------- section: assign a staff task (execs & managers) ---------- */
  if (isExec || managesSomeone) {
    out.append(el('h2', { class: 'mb-4 mt-4', text: t('hq.taskTitle') }),
      staffTaskCard());
  }

  /* ---------- section: messages (modern inbox preview) ---------- */
  if (iAmStaff || isExec) {
    const inboxCard = el('div', { class: 'card mb-4' });
    inboxCard.append(el('div', { class: 'card__head' }, [
      el('h2', { text: t('hq.messages') }),
      el('a', { href: '#/messages', class: 'btn btn--primary',
        text: t('hq.openMessages') }),
    ]));
    const inboxList = el('div');
    inboxCard.append(inboxList);
    out.append(inboxCard);
    (async () => {
      try {
        const { data } = await db().from('staff_messages')
          .select('id, sender_id, recipient_id, body, read_at, created_at')
          .order('created_at', { ascending: false }).limit(120);
        const convs = new Map();
        for (const m of (data || [])) {
          const other = m.sender_id === myId ? m.recipient_id : m.sender_id;
          if (!convs.has(other)) convs.set(other, { last: m, unread: 0 });
          if (m.recipient_id === myId && !m.read_at) {
            convs.get(other).unread += 1;
          }
        }
        const ids = [...convs.keys()].slice(0, 5);
        if (!ids.length) {
          inboxList.append(el('p', { class: 'muted',
            text: t('hq.noMessages') }));
          return;
        }
        const { data: ppl } = await db().from('profiles')
          .select('id, first_name, last_name').in('id', ids);
        const nm = new Map((ppl || []).map((x) =>
          [x.id, `${x.first_name} ${x.last_name}`]));
        for (const oid of ids) {
          const c = convs.get(oid);
          inboxList.append(el('a', { class: 'conv',
            href: `#/messages?u=${oid}`, style: 'text-decoration:none;' }, [
            el('div', { class: 'conv__main' }, [
              el('strong', { text: nm.get(oid) || '—' }),
              el('span', { class: 'conv__snippet',
                text: (c.last.body || '').slice(0, 60) }),
            ]),
            c.unread ? el('span', { class: 'bell__badge',
              style: 'position:static;', text: String(c.unread) }) : null,
          ]));
        }
      } catch (err) {
        inboxList.append(el('p', { class: 'muted',
          text: t('errors.loadHint') + ' — '
            + String(err?.message || '').slice(0, 100) }));
      }
    })();
  }

  /* ---------- section: staff directory ---------- */
  out.append(el('h2', { class: 'mb-4 mt-4', text: t('hq.directory') }),
    directoryCard());

  return shell.teardown;

  /* ================= staff tasks ================= */
  function staffTaskCard() {
    const card = el('div', { class: 'card mb-4' });
    const title = el('input', { class: 'input', maxlength: '160' });
    const who = el('select', { class: 'select' },
      staffRows.map((st) => el('option', { value: st.profile_id,
        text: `${safeName(st)} — ${st.position_title}` })));
    const prio = el('select', { class: 'select' },
      ['low', 'medium', 'high', 'urgent'].map((p) =>
        el('option', { value: p, selected: p === 'medium' || null,
          text: t(`taskprio.${p}`) })));
    const due = el('input', { class: 'input', type: 'date' });
    const approval = el('input', { type: 'checkbox', id: 'hq-task-approval' });
    const details = el('textarea', { class: 'input', rows: '2',
      maxlength: '4000' });
    const err = el('p', { class: 'field__error', role: 'alert', hidden: true });
    const submit = el('button', { class: 'btn btn--primary', type: 'submit',
      text: t('tasks.create') });
    const form = el('form', { novalidate: true, onsubmit: async (e) => {
      e.preventDefault();
      if (title.value.trim().length < 3) {
        err.textContent = t('tasks.errTitle'); err.hidden = false; return;
      }
      err.hidden = true;
      submit.disabled = true;
      try {
        await createTask({
          title: title.value.trim(),
          details: details.value.trim(),
          org_unit_id: await getHqUnitId(),
          assigned_to: who.value,
          priority: prio.value,
          requires_approval: approval.checked,
          due_on: due.value,
        });
        toast(t('hq.taskAssigned'));
        form.reset();
      } catch { err.textContent = t('errors.save'); err.hidden = false; }
      finally { submit.disabled = false; }
    } }, [
      el('div', { class: 'form-grid' }, [
        wrapField(t('tasks.title'), title),
        wrapField(t('hq.assignee'), who),
        wrapField(t('tasks.priority'), prio),
        wrapField(t('tasks.dueOn'), due),
      ]),
      wrapField(t('tasks.details'), details),
      el('div', { class: 'row mb-4' }, [approval,
        el('label', { for: 'hq-task-approval', class: 'muted',
          text: t('tasks.requiresApprovalHint') })]),
      err,
      el('div', { class: 'row' }, [
        el('span', { class: 'muted grow', text: t('hq.taskHint') }),
        submit]),
    ]);
    card.append(form);
    return card;
  }

  /* ================= staff messages ================= */
  async function messagesPanel(area) {
    area.append(el('div', { class: 'card state' }, [
      el('div', { class: 'spinner' })]));
    let box;
    try { box = await listStaffMessages(); }
    catch {
      area.replaceChildren(el('div', { class: 'card state' }, [
        el('h3', { text: t('errors.loadTitle') }),
        el('button', { class: 'btn btn--quiet', text: t('app.retry'),
          onclick: () => { clear(area); messagesPanel(area); } }),
      ]));
      return;
    }
    const nameOf = new Map(staffRows.map((st) =>
      [st.profile_id, safeName(st)]));
    try {
    const card = el('div', { class: 'card mb-4' });

    /* compose */
    const who = el('select', { class: 'select' },
      staffRows.filter((st) => st.profile_id !== myId)
        .map((st) => el('option', { value: st.profile_id,
          text: nameOf.get(st.profile_id) ?? '\u2014' })));
    const body = el('textarea', { class: 'input', rows: '3',
      maxlength: '4000', placeholder: t('hq.msgPlaceholder') });

    /* formatting toolbar: wraps the selected text */
    const wrapSel = (mark) => {
      const a = body.selectionStart, b = body.selectionEnd;
      const sel = body.value.slice(a, b) || t('hq.msgFmtSample');
      body.value = body.value.slice(0, a) + mark + sel + mark +
        body.value.slice(b);
      body.focus();
    };
    const fileInput = el('input', { type: 'file', hidden: true });
    const fileTag = el('span', { class: 'muted' });
    fileInput.addEventListener('change', () => {
      fileTag.textContent = fileInput.files[0]
        ? `\u{1F4CE} ${fileInput.files[0].name}` : '';
    });
    const toolbar = el('div', { class: 'row mb-4' }, [
      el('button', { class: 'btn btn--quiet', type: 'button', text: 'B',
        style: 'font-weight:800;min-height:32px;padding:2px 12px;',
        'aria-label': t('hq.msgBold'), onclick: () => wrapSel('**') }),
      el('button', { class: 'btn btn--quiet', type: 'button', text: 'I',
        style: 'font-style:italic;min-height:32px;padding:2px 12px;',
        'aria-label': t('hq.msgItalic'), onclick: () => wrapSel('*') }),
      el('button', { class: 'btn btn--quiet', type: 'button',
        style: 'min-height:32px;padding:2px 12px;',
        'aria-label': t('hq.msgAttach'), text: '\u{1F4CE}',
        onclick: () => fileInput.click() }),
      fileTag, fileInput,
    ]);

    card.append(
      el('div', { class: 'form-grid' }, [
        wrapField(t('hq.msgTo'), who),
        wrapField(t('hq.msgBody'), body),
      ]),
      toolbar,
      el('div', { class: 'row mb-4' }, [
        el('span', { class: 'grow' }),
        el('button', { class: 'btn btn--primary', text: t('hq.msgSend'),
          onclick: async (e) => {
            if (!body.value.trim() || !who.value) return;
            e.target.disabled = true;
            try {
              await sendStaffMessage(who.value, body.value.trim(),
                fileInput.files[0] ?? null);
              body.value = '';
              fileInput.value = '';
              fileTag.textContent = '';
              toast(t('hq.msgSent'));
              clear(area); messagesPanel(area);
            } catch { toastError(t('errors.save')); }
            finally { e.target.disabled = false; }
          } }),
      ])
    );

    /* thread list */
    if (box.rows.length === 0) {
      card.append(el('p', { class: 'muted', text: t('hq.msgEmpty') }));
    }
    for (const m of box.rows) {
      const mine = m.sender_id === box.myId;
      const unread = !mine && !m.read_at;
      const line = el('p', {
        style: unread ? 'font-weight:650;' : '',
      }, [
        el('span', { class: 'muted',
          text: `${fmtDateTime(m.created_at)} · ` }),
        el('span', { text: (mine
          ? t('hq.msgToLine', { name: nameOf.get(m.recipient_id) ?? '—' })
          : t('hq.msgFromLine', { name: nameOf.get(m.sender_id) ?? '—' }))
          + ': ' }),
      ]);
      const rich = el('span');
      rich.innerHTML = renderMarkup(m.body);
      line.append(rich);
      if (m.attachment_path) {
        const isImage = /\.(png|jpe?g|gif|webp)$/i
          .test(m.attachment_name ?? '');
        if (isImage) {
          const img = el('img', { alt: m.attachment_name ?? '',
            style: 'display:block;max-width:260px;border-radius:8px;' +
              'margin-top:6px;border:1px solid var(--line);' });
          staffFileUrl(m.attachment_path)
            .then((u) => { img.src = u; }).catch(() => img.remove());
          line.append(img);
        } else {
          line.append(el('a', { href: '#',
            style: 'display:block;margin-top:4px;',
            text: `\u{1F4CE} ${m.attachment_name ?? t('hq.msgFile')}`,
            onclick: async (ev) => {
              ev.preventDefault();
              try {
                window.open(await staffFileUrl(m.attachment_path),
                  '_blank', 'noopener');
              } catch { /* expired */ }
            } }));
        }
      }
      if (unread) {
        line.append(el('button', {
          class: 'btn btn--quiet', text: t('ann.markRead'),
          style: 'min-height:28px;padding:2px 8px;margin-left:8px;',
          onclick: async (e) => {
            e.target.disabled = true;
            try {
              await markMessageRead(m.id);
              line.style.fontWeight = '';
              e.target.remove();
            } catch { e.target.disabled = false; }
          } }));
      }
      card.append(line);
    }
    area.replaceChildren(card);
    } catch {
      area.replaceChildren(el('div', { class: 'card state' }, [
        el('h3', { text: t('errors.loadTitle') }),
        el('button', { class: 'btn btn--quiet', text: t('app.retry'),
          onclick: () => { clear(area); messagesPanel(area); } }),
      ]));
    }
  }

  /* ================= my report ================= */
  function myReportCard() {
    const period = el('select', { class: 'select', style: 'width:auto;' },
      PERIODS.map((p) => el('option', { value: p, text: t(`period.${p}`) })));
    const date = el('input', { class: 'input', type: 'date',
      value: new Date().toISOString().slice(0, 10), style: 'width:auto;' });
    const f = {
      done: area(t('hq.tasksCompleted'), true),
      doing: area(t('hq.tasksInProgress')),
      challenges: area(t('hq.challenges')),
      support: area(t('hq.supportRequired')),
      next: area(t('hq.nextPriorities')),
    };
    const err = el('p', { class: 'field__error', role: 'alert', hidden: true });
    const submit = el('button', { class: 'btn btn--primary', type: 'submit',
      text: t('hq.submitReport') });
    const mineArea = el('div', { class: 'mt-4' });

    const form = el('form', { novalidate: true, onsubmit: async (e) => {
      e.preventDefault();
      if (f.done.input.value.trim().length < 2) {
        err.textContent = t('hq.errCompleted'); err.hidden = false; return;
      }
      err.hidden = true;
      submit.disabled = true;
      try {
        await submitStaffReport({
          report_date: date.value,
          period: period.value,
          tasks_completed: f.done.input.value.trim(),
          tasks_in_progress: f.doing.input.value.trim(),
          challenges: f.challenges.input.value.trim(),
          support_required: f.support.input.value.trim(),
          next_priorities: f.next.input.value.trim(),
        });
        toast(t('hq.reportSubmitted'));
        form.reset();
        date.value = new Date().toISOString().slice(0, 10);
        loadMine();
      } catch (e2) {
        err.textContent = String(e2?.message ?? '').includes('duplicate')
          ? t('hq.errDuplicate') : t('errors.save');
        err.hidden = false;
      } finally { submit.disabled = false; }
    } }, [
      el('div', { class: 'row mb-4' }, [period, date]),
      f.done.node, f.doing.node, f.challenges.node, f.support.node, f.next.node,
      err,
      el('div', { class: 'row' }, [el('span', { class: 'grow' }), submit]),
    ]);

    const card = el('div', { class: 'card mb-4' }, [
      el('div', { class: 'card__head' }, [
        el('h2', { text: t('hq.myReport') })]),
      form, mineArea,
    ]);
    loadMine();
    return card;

    async function loadMine() {
      clear(mineArea);
      try {
        const rows = await listStaffReports({ mine: true, pageSize: 5 });
        if (rows.length === 0) return;
        mineArea.append(el('h3', { class: 'mb-4', text: t('hq.myRecent') }));
        for (const r of rows) mineArea.append(reportRow(r, false));
      } catch { /* silent: section is secondary */ }
    }
  }

  /* ================= review queue ================= */
  async function loadQueue(queue) {
    clear(queue);
    queue.append(el('div', { class: 'state' }, [
      el('div', { class: 'spinner' })]));
    try {
      const rows = await listStaffReports({ status: 'submitted',
        excludeAuthor: myId, pageSize: 25 });
      clear(queue);
      if (rows.length === 0) {
        queue.append(el('div', { class: 'card state' }, [
          el('h3', { text: t('hq.queueEmpty') })]));
        return;
      }
      const card = el('div', { class: 'card' });
      for (const r of rows) card.append(reportRow(r, true, () => loadQueue(queue)));
      queue.append(card);
    } catch {
      clear(queue);
      queue.append(el('div', { class: 'card state' }, [
        el('h3', { text: t('errors.loadTitle') }),
        el('button', { class: 'btn btn--quiet', text: t('app.retry'),
          onclick: () => loadQueue(queue) }),
      ]));
    }
  }

  function reportRow(r, reviewable, onDone) {
    const box = el('div', {
      style: 'padding:12px 0;border-bottom:1px solid var(--line);' });
    const who = r.author
      ? `${r.author.first_name} ${r.author.last_name} — ` : '';
    box.innerHTML = `
      <div class="row">
        <strong class="grow">${esc(who)}${esc(t(`period.${r.period}`))}
          · ${esc(fmtDate(r.report_date))}</strong>
        <span class="badge badge--${R_FAMILY[r.status]}">
          ${esc(t(`rstatus.${r.status}`))}</span>
      </div>
      <p><strong>${esc(t('hq.tasksCompleted'))}:</strong>
        ${esc(r.tasks_completed)}</p>
      ${r.tasks_in_progress ? `<p><strong>${esc(t('hq.tasksInProgress'))}:</strong> ${esc(r.tasks_in_progress)}</p>` : ''}
      ${r.challenges ? `<p><strong>${esc(t('hq.challenges'))}:</strong> ${esc(r.challenges)}</p>` : ''}
      ${r.support_required ? `<p><strong>${esc(t('hq.supportRequired'))}:</strong> ${esc(r.support_required)}</p>` : ''}
      ${r.next_priorities ? `<p><strong>${esc(t('hq.nextPriorities'))}:</strong> ${esc(r.next_priorities)}</p>` : ''}
      ${r.reviewer_note ? `<p class="muted">${esc(t('hq.reviewerNote'))}: ${esc(r.reviewer_note)}</p>` : ''}`;
    if (reviewable && r.status === 'submitted') {
      const note = el('input', { class: 'input', maxlength: '2000',
        placeholder: t('hq.reviewNoteHint'), style: 'flex:2;' });
      box.append(el('div', { class: 'row mt-4' }, [
        note,
        el('button', { class: 'btn btn--secondary', text: t('hq.approve'),
          onclick: () => decide(true) }),
        el('button', { class: 'btn btn--danger', text: t('hq.requestRevision'),
          onclick: () => decide(false) }),
      ]));
      async function decide(approve) {
        if (!approve && note.value.trim().length < 5) {
          toastError(t('recruit.errReason')); return;
        }
        try {
          await reviewStaffReport(r.id, approve, note.value.trim() || null);
          toast(t('hq.reviewed'));
          onDone?.();
        } catch (err) {
          toastError(String(err?.message ?? '').includes('manager')
            ? t('hq.errReviewAuth') : t('errors.save'));
        }
      }
    }
    return box;
  }

  /* ================= directory ================= */
  function directoryCard() {
    const card = el('div', { class: 'card mb-4' });
    const byId = new Map(staffRows.map((s) => [s.profile_id, s]));
    const deptName = (id) =>
      departments.find((d) => d.id === id)?.name ?? '—';
    const personName = (s) =>
      s.person ? `${s.person.first_name} ${s.person.last_name}` : '—';

    if (staffRows.length === 0) {
      card.append(el('p', { class: 'muted', text: t('hq.noStaff') }));
    } else {
      const wrap = el('div', { class: 'table-wrap' });
      const tbl = el('table', { class: 'table' });
      const bust = String(Date.now());
      tbl.innerHTML = `
        <thead><tr>
          <th></th>
          <th>${esc(t('members.name'))}</th>
          <th>${esc(t('hq.position'))}</th>
          <th>${esc(t('hq.department'))}</th>
          <th>${esc(t('hq.manager'))}</th>
        </tr></thead>
        <tbody>${staffRows.map((s) => `
          <tr style="cursor:default;" data-pid="${esc(s.profile_id)}">
            <td><img class="avatar" alt=""
                 src="${esc(avatarUrl(s.profile_id, bust))}"
                 onerror="this.classList.add('avatar--hidden')"></td>
            <td><strong>${esc(personName(s))}</strong></td>
            <td>${esc(s.position_title)}</td>
            <td>${esc(deptName(s.department_id))}</td>
            <td>${esc(s.reports_to && byId.get(s.reports_to)
              ? personName(byId.get(s.reports_to)) : '—')}</td>
          </tr>`).join('')}</tbody>`;
      wrap.append(tbl);
      card.append(wrap);

      /* exec: per-row photo upload */
      if (isExec) {
        tbl.querySelector('thead tr').append(el('th', { text: t('hq.photo') }));
        for (const tr of tbl.querySelectorAll('tbody tr')) {
          const pid = tr.dataset.pid;
          const input = el('input', { type: 'file',
            accept: 'image/*', hidden: true });
          input.addEventListener('change', async () => {
            const file = input.files[0];
            if (!file) return;
            try {
              await uploadAvatar(pid, file);
              const img = tr.querySelector('img.avatar');
              img.classList.remove('avatar--hidden');
              img.src = avatarUrl(pid, String(Date.now()));
              toast(t('hq.photoSaved'));
            } catch { toastError(t('errors.save')); }
            input.value = '';
          });
          const btn = el('button', {
            class: 'btn btn--quiet', text: t('hq.setPhoto'),
            style: 'min-height:32px;padding:4px 10px;',
            onclick: () => input.click(),
          });
          tr.append(el('td', {}, [btn, input]));
        }
      }
    }

    if (!isExec) return card;

    /* exec: add staff */
    const search = el('input', { class: 'input', type: 'search',
      placeholder: t('org.searchMember') });
    const who = el('select', { class: 'select', size: '3' });
    search.addEventListener('input', debounce(async () => {
      try {
        const rows = await searchAppointableMembers(search.value.trim());
        clear(who);
        for (const p of rows) {
          who.append(el('option', { value: p.id,
            text: `${p.first_name} ${p.last_name} — ${p.email}` }));
        }
      } catch { toastError(t('errors.load')); }
    }));
    const position = el('input', { class: 'input', maxlength: '100',
      placeholder: t('hq.positionHint') });
    const deptSel = el('select', { class: 'select' },
      departments.map((d) => el('option', { value: d.id, text: d.name })));
    const mgrSel = el('select', { class: 'select' }, [
      el('option', { value: '', text: t('hq.noManager') }),
      ...staffRows.map((s) => el('option', { value: s.profile_id,
        text: personName(s) })),
    ]);
    card.append(
      el('h3', { class: 'mb-4 mt-4', text: t('hq.addStaff') }),
      el('div', { class: 'form-grid' }, [
        wrapField(t('org.searchMember'), search, who),
        wrapField(t('hq.position'), position),
        wrapField(t('hq.department'), deptSel),
        wrapField(t('hq.manager'), mgrSel),
      ]),
      el('div', { class: 'row' }, [
        el('span', { class: 'grow' }),
        el('button', { class: 'btn btn--primary', text: t('hq.add'),
          onclick: async (e) => {
            if (!who.value) { toastError(t('org.errPickMember')); return; }
            if (position.value.trim().length < 2) {
              toastError(t('hq.errPosition')); return;
            }
            e.target.disabled = true;
            try {
              await addStaff({
                profile_id: who.value,
                department_id: deptSel.value,
                position_title: position.value.trim(),
                reports_to: mgrSel.value || null,
              });
              toast(t('hq.staffAdded'));
              render(root, _params, ctx);
            } catch (err) {
              toastError(String(err?.message ?? '').includes('duplicate')
                ? t('hq.errAlreadyStaff') : t('errors.save'));
              e.target.disabled = false;
            }
          } }),
      ])
    );
    return card;
  }
}

function area(label, required = false) {
  const input = el('textarea', { class: 'input', rows: '2',
    maxlength: '4000', required: required || null });
  const node = el('div', { class: 'field' }, [
    el('label', { class: 'field__label', text: label }), input,
  ]);
  return { node, input };
}

function wrapField(label, ...controls) {
  return el('div', { class: 'field' }, [
    el('label', { class: 'field__label', text: label }), ...controls,
  ]);
}
