import { el, esc, clear , personLabel, linkify, isUrl } from '../core/dom.js';
import { t, fmtDate, fmtNumber } from '../core/i18n.js';
import {
  listMeetings, createMeeting, updateMeeting, listOrgUnits,
  listUnitMembers, getAttendance, saveAttendance,
  meetingJoin, listCheckins, uploadMeetingFile, listMeetingFiles, meetingFileUrl, db,
} from '../core/db.js';
import { renderShell } from '../components/layout.js';
import { toast, toastError } from '../components/toast.js';

const MODES = ['in_person', 'virtual', 'hybrid'];
const FAMILY = { scheduled: 'pipeline', completed: 'active', cancelled: 'exited' };
const PAGE_SIZE = 25;

export async function render(root, _params, ctx) {
  const shell = renderShell(root, {
    profile: ctx.profile, modules: ctx.modules, titleKey: 'nav.meetings',
  });
  const out = shell.outlet;
  const state = { scope: 'upcoming', page: 0 };

  const tabs = el('div', { class: 'row' });
  for (const scope of ['upcoming', 'past']) {
    tabs.append(el('button', {
      class: 'btn btn--quiet', 'data-scope': scope,
      text: t(`meet.scope_${scope}`),
      onclick: () => { state.scope = scope; state.page = 0; paint(); load(); },
    }));
  }
  const newBtn = el('button', {
    class: 'btn btn--primary', text: t('meet.new'),
    onclick: () => { formCard.hidden = !formCard.hidden; },
  });

  const formCard = await buildForm();
  formCard.hidden = true;
  const listArea = el('div');
  out.append(
    el('div', { class: 'toolbar' }, [tabs, el('span', { class: 'grow' }), newBtn]),
    formCard, listArea
  );
  paint();
  await load();
  return shell.teardown;

  function paint() {
    tabs.querySelectorAll('button').forEach((b) => {
      b.classList.toggle('btn--secondary', b.dataset.scope === state.scope);
      b.classList.toggle('btn--quiet', b.dataset.scope !== state.scope);
    });
  }

  async function load() {
    clear(listArea);
    listArea.append(el('div', { class: 'state' }, [
      el('div', { class: 'spinner' }), el('p', { text: t('app.loading') }),
    ]));
    try {
      const { rows, total } = await listMeetings({ ...state, pageSize: PAGE_SIZE });
      clear(listArea);
      if (rows.length === 0) {
        listArea.append(el('div', { class: 'card state' }, [
          el('h3', { text: t('meet.emptyTitle') }),
          el('p', { text: t('meet.emptyHint') }),
        ]));
        return;
      }
      for (const m of rows) listArea.append(meetingCard(m));
      listArea.append(pager(total));
    } catch (err) {
      clear(listArea);
      listArea.append(el('div', { class: 'card state' }, [
        el('h3', { text: t('errors.loadTitle') }),
        el('p', { text: t('errors.loadHint') }),
        el('p', { class: 'muted', style: 'font-size:12px;',
          text: String(err?.message || '').slice(0, 160) }),
        el('button', { class: 'btn btn--quiet', text: t('app.retry'), onclick: load }),
      ]));
    }
  }

  function meetingCard(m) {
    const card = el('div', { class: 'card mb-4' });
    const when = new Intl.DateTimeFormat(document.documentElement.lang, {
      dateStyle: 'medium', timeStyle: 'short',
    });
    const head = el('div', { class: 'card__head' });
    const rawLoc = (m.location || '').trim();
    const isWoddi = m.platform === 'woddi' && rawLoc.startsWith('WODDI-');
    const joinHref = isWoddi
      ? `#/room?r=${encodeURIComponent(rawLoc)}&m=${m.id}`
      : (isUrl(rawLoc) ? rawLoc
        : (/^[\w.-]+\.[a-z]{2,}([\/#?].*)?$/i.test(rawLoc)
            ? 'https://' + rawLoc : null));
    const joinable = !!joinHref;
    head.innerHTML = `
      <div>
        <h2>${esc(m.title)}</h2>
        <span class="muted">
          ${esc(when.format(new Date(m.starts_at)))} –
          ${esc(new Intl.DateTimeFormat(document.documentElement.lang,
            { timeStyle: 'short' }).format(new Date(m.ends_at)))}
          · ${esc(t(`meetmode.${m.mode}`))}
          ${m.location && !joinable ? ' · ' + esc(m.location) : ''}
          · ${esc(t('meet.hostedBy',
              { name: personLabel(m.host) }))}
        </span>
      </div>
      <span class="badge badge--${FAMILY[m.status]}">
        ${esc(t(`meetstatus.${m.status}`))}</span>`;
    card.append(head);
    if (joinable && m.status === 'scheduled') {
      card.append(el('div', { class: 'row mt-2' }, [
        el('a', { class: 'btn btn--primary', href: joinHref,
          onclick: () => { meetingJoin(m.id).catch(() => {}); },
          target: '_blank', rel: 'noopener noreferrer',
          text: t('meet.join') }),
        el('span', { class: 'muted', style: 'font-size:12px;align-self:center;overflow-wrap:anywhere;',
          text: m.location }),
      ]));
    }
    if (m.agenda) {
      const p = el('p', { class: 'mt-2',
        style: 'white-space:pre-wrap;line-height:1.6;' });
      p.innerHTML = linkify(m.agenda);
      card.append(el('h3', { class: 'mt-2', text: t('meet.agendaFull') }), p);
    }
    if (m.platform) {
      card.append(el('span', { class: 'badge badge--pipeline',
        text: t(`meet.pf_${m.platform}`) }));
    }

    /* ── attached documents ── */
    const filesBox = el('div', { class: 'mt-2' });
    card.append(filesBox);
    listMeetingFiles(m.id).then((fs) => {
      if (!fs.length) return;
      filesBox.append(el('h3', { text: t('meet.docs') }));
      for (const f of fs) {
        filesBox.append(el('a', { href: '#',
          style: 'display:block;margin:4px 0;',
          text: `\u{1F4CE} ${f.name}`,
          onclick: async (ev) => {
            ev.preventDefault();
            try {
              window.open(await meetingFileUrl(f.path), '_blank', 'noopener');
            } catch { /* expired */ }
          } }));
      }
    }).catch(() => {});

    /* ── LIVE attendance: names as they join + region counts ── */
    const liveBox = el('div', { class: 'mt-2 live-box' });
    card.append(liveBox);
    const regionOf = new Map();
    async function regionName(unitId) {
      if (!unitId) return t('meet.regionUnknown');
      if (regionOf.has(unitId)) return regionOf.get(unitId);
      try {
        const units = await listOrgUnits();
        const byId = new Map(units.map((u) => [u.id, u]));
        let cur = byId.get(unitId); let name = cur?.name || '?';
        while (cur && cur.parent_id && byId.get(cur.parent_id)
               && byId.get(cur.parent_id).level !== 'headquarters') {
          cur = byId.get(cur.parent_id); name = cur.name;
        }
        regionOf.set(unitId, name);
        return name;
      } catch { return t('meet.regionUnknown'); }
    }
    async function paintLive() {
      let rows = [];
      try { rows = await listCheckins(m.id); } catch { return; }
      clear(liveBox);
      liveBox.append(el('h3', {
        text: t('meet.liveHead', { n: rows.length }) }));
      const counts = new Map();
      const names = el('div', { class: 'row',
        style: 'gap:6px;flex-wrap:wrap;' });
      for (const r of rows) {
        const nm = r.profile
          ? `${r.profile.first_name} ${r.profile.last_name}` : '—';
        names.append(el('span', { class: 'badge badge--active', text: nm }));
        const reg = await regionName(r.profile?.org_unit_id);
        counts.set(reg, (counts.get(reg) || 0) + 1);
      }
      liveBox.append(names);
      if (counts.size) {
        const regs = el('p', { class: 'muted mt-2', style: 'font-size:13px;',
          text: t('meet.byRegion') + ' ' + [...counts.entries()]
            .sort((a, b) => b[1] - a[1])
            .map(([k, v]) => `${k}: ${v}`).join(' · ') });
        liveBox.append(regs);
      }
    }
    paintLive();
    const ch = db().channel(`mtg-${m.id}`)
      .on('postgres_changes', { event: 'INSERT', schema: 'public',
        table: 'meeting_checkins', filter: `meeting_id=eq.${m.id}` },
        () => paintLive())
      .subscribe();
    card.addEventListener('wdos:teardown', () => {
      try { db().removeChannel(ch); } catch { /* gone */ }
    });
    if (m.minutes) {
      const p = el('p');
      p.innerHTML = linkify(m.minutes);
      card.append(el('h3', { text: t('meet.minutes') }), p);
    }

    const actions = el('div', { class: 'row mt-4' });
    if (m.status === 'scheduled') {
      actions.append(
        el('button', { class: 'btn btn--secondary', text: t('meet.close'),
          onclick: () => closeFlow(m, card) }),
        el('button', { class: 'btn btn--danger', text: t('meet.cancel'),
          onclick: async () => {
            try {
              await updateMeeting(m.id, { status: 'cancelled' });
              toast(t('meet.updated')); load();
            } catch (err) { toastError(mapError(err)); }
          } })
      );
    }
    actions.append(el('button', { class: 'btn btn--quiet',
      text: t('meet.attendance'),
      onclick: () => attendanceFlow(m, card) }));
    card.append(actions);
    return card;
  }

  /* Close a meeting: minutes + completed */
  function closeFlow(m, card) {
    if (card.querySelector('.close-flow')) return;
    const minutes = el('textarea', { class: 'input', rows: '4',
      maxlength: '8000', placeholder: t('meet.minutesPlaceholder') });
    if (m.minutes) minutes.value = m.minutes;
    const box = el('div', { class: 'close-flow mt-4' }, [
      el('h3', { class: 'mb-4', text: t('meet.minutes') }),
      minutes,
      el('div', { class: 'row mt-4' }, [
        el('span', { class: 'grow' }),
        el('button', { class: 'btn btn--secondary', text: t('meet.markCompleted'),
          onclick: async () => {
            try {
              await updateMeeting(m.id, {
                status: 'completed', minutes: minutes.value.trim() || null,
              });
              toast(t('meet.updated')); load();
            } catch (err) { toastError(mapError(err)); }
          } }),
      ]),
    ]);
    card.append(box);
  }

  /* Attendance sheet */
  async function attendanceFlow(m, card) {
    if (card.querySelector('.att-flow')) return;
    const box = el('div', { class: 'att-flow mt-4' }, [
      el('div', { class: 'state' }, [el('div', { class: 'spinner' })]),
    ]);
    card.append(box);
    let members, marks;
    try {
      [members, marks] = await Promise.all([
        listUnitMembers(m.org_unit_id), getAttendance(m.id),
      ]);
    } catch {
      box.replaceChildren(el('p', { class: 'field__error',
        text: t('errors.load') }));
      return;
    }
    const byProfile = new Map(marks.map((x) => [x.profile_id, x.present]));
    box.replaceChildren(el('h3', { class: 'mb-4', text: t('meet.attendance') }));
    if (members.length === 0) {
      box.append(el('p', { class: 'muted', text: t('meet.noMembers') }));
      return;
    }
    const rows = [];
    for (const p of members) {
      const sel = el('select', { class: 'select', style: 'width:auto;' }, [
        el('option', { value: '', text: t('meet.unmarked'),
          selected: !byProfile.has(p.id) || null }),
        el('option', { value: 'yes', text: t('meet.present'),
          selected: byProfile.get(p.id) === true || null }),
        el('option', { value: 'no', text: t('meet.absent'),
          selected: byProfile.get(p.id) === false || null }),
      ]);
      rows.push({ profile: p, sel });
      box.append(el('div', { class: 'row',
        style: 'padding:6px 0;border-bottom:1px solid var(--line);' }, [
        el('span', { class: 'grow',
          text: personLabel(p) +
            (p.membership_no ? ` · ${p.membership_no}` : '') }),
        sel,
      ]));
    }
    box.append(el('div', { class: 'row mt-4' }, [
      el('span', { class: 'grow' }),
      el('button', { class: 'btn btn--primary', text: t('meet.saveAttendance'),
        onclick: async (e) => {
          const entries = rows
            .filter((r) => r.sel.value !== '')
            .map((r) => ({ profile_id: r.profile.id,
              present: r.sel.value === 'yes' }));
          if (entries.length === 0) { toastError(t('meet.errNoMarks')); return; }
          e.target.disabled = true;
          try {
            await saveAttendance(m.id, entries);
            toast(t('meet.attendanceSaved'));
          } catch (err) { toastError(mapError(err)); }
          finally { e.target.disabled = false; }
        } }),
    ]));
  }

  function pager(total) {
    const pages = Math.max(1, Math.ceil(total / PAGE_SIZE));
    return el('div', { class: 'row mt-4' }, [
      el('span', { class: 'muted grow',
        text: t('meet.count', { n: fmtNumber(total) }) }),
      el('button', { class: 'btn btn--quiet', text: t('app.prev'),
        disabled: state.page === 0 || null,
        onclick: () => { state.page -= 1; load(); } }),
      el('span', { class: 'muted', text: `${state.page + 1} / ${pages}` }),
      el('button', { class: 'btn btn--quiet', text: t('app.next'),
        disabled: state.page >= pages - 1 || null,
        onclick: () => { state.page += 1; load(); } }),
    ]);
  }

  /* ---- scheduling form ---- */
  async function buildForm() {
    let units = [];
    try { units = await listOrgUnits(); } catch { /* surfaced on submit */ }

    const title = el('input', { class: 'input', maxlength: '160' });
    const unitSel = el('select', { class: 'select' },
      units.map((u) => el('option', { value: u.id,
        text: `${t(`org.${u.level}`)} — ${u.name}` })));
    const mode = el('select', { class: 'select' },
      MODES.map((x) => el('option', { value: x, text: t(`meetmode.${x}`) })));
    const location = el('input', { class: 'input', maxlength: '300',
      placeholder: t('meet.locationHint') });
    const start = el('input', { class: 'input', type: 'datetime-local' });
    const end = el('input', { class: 'input', type: 'datetime-local' });
    const agenda = el('textarea', { class: 'input', rows: '3', maxlength: '4000' });
    const err = el('p', { class: 'field__error', role: 'alert', hidden: true });
    const submit = el('button', { class: 'btn btn--primary', type: 'submit',
      text: t('meet.schedule') });

    const form = el('form', { novalidate: true, onsubmit: async (e) => {
      e.preventDefault();
      if (title.value.trim().length < 3) { fail(t('tasks.errTitle')); return; }
      if (!start.value || !end.value) { fail(t('meet.errTimes')); return; }
      const s = new Date(start.value); const en = new Date(end.value);
      if (!(en > s)) { fail(t('meet.errOrder')); return; }
      err.hidden = true;
      submit.disabled = true;
      try {
        const autoRoom = platform.value === 'woddi'
          ? 'WODDI-' + title.value.trim().toUpperCase()
              .replace(/\s+/g, '-').replace(/[^\w-]/g, '').slice(0, 40)
          : null;
        const created = await createMeeting({
          title: title.value.trim(),
          agenda: agenda.value.trim(),
          org_unit_id: unitSel.value,
          mode: mode.value,
          platform: platform.value,
          audience: audience.value,
          location: autoRoom || location.value.trim(),
          starts_at: s.toISOString(),
          ends_at: en.toISOString(),
        });
        try {
          for (const f of Array.from(files.files || []).slice(0, 6)) {
            await uploadMeetingFile(created.id, f);
          }
        } catch { toastError(t('meet.attachFail')); }
        toast(t('meet.scheduled'));
        form.reset();
        formCard.hidden = true;
        load();
      } catch (e2) { fail(mapError(e2)); }
      finally { submit.disabled = false; }
      function fail(msg) { err.textContent = msg; err.hidden = false; }
    } }, [
      el('div', { class: 'form-grid' }, [
        wrapField(t('meet.title'), title),
        wrapField(t('members.orgUnit'), unitSel),
        wrapField(t('meet.mode'), mode),
        wrapField(t('meet.location'), location),
        wrapField(t('meet.startsAt'), start),
        wrapField(t('meet.endsAt'), end),
      ]),
      wrapField(t('meet.agenda'), agenda),
      err,
      el('div', { class: 'row' }, [el('span', { class: 'grow' }), submit]),
    ]);
    return el('div', { class: 'card mb-4' }, [
      el('div', { class: 'card__head' }, [el('h2', { text: t('meet.new') })]),
      form,
    ]);
  }
}

function wrapField(label, control) {
  return el('div', { class: 'field' }, [
    el('label', { class: 'field__label', text: label }), control,
  ]);
}

function mapError(err) {
  const m = String(err?.message ?? '');
  if (m.includes('row-level security')) return t('meet.errScope');
  if (m.includes('Invalid meeting transition')) return t('meet.errTransition');
  if (m.includes('meeting_times_valid')) return t('meet.errOrder');
  return t('errors.save');
}
