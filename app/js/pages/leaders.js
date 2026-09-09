/**
 * WDOS Leader Atlas — Phase 90. The established leadership family on one
 * page: country by country (state and LGA when known), every CR/DCR with
 * their access code, course performance, last-seen, and login state —
 * message one leader or a whole country at once. HQ eyes only; the
 * server enforces it.
 */
import { el, esc, clear } from '../core/dom.js';
import { t, fmtDate } from '../core/i18n.js';
import { db, leadersAtlas, sendStaffMessage, promotionCandidates,
  vacantSeatsFor, promoteCandidate, createTask, addTaskFile,
  submitSpotlightNomination, avatarUrl } from '../core/db.js';
import { openModal, closeModal } from '../components/modal.js';
import { renderShell } from '../components/layout.js';
import { toast, toastError } from '../components/toast.js';
import { icon } from '../components/icons.js';

export async function render(root, _params, ctx) {
  const shell = renderShell(root, {
    profile: ctx.profile, modules: ctx.modules, titleKey: 'nav.leaders',
  });
  const out = shell.outlet;
  clear(out);
  out.append(el('p', { class: 'muted mb-4', text: t('atlas.sub') }));
  const box = el('div');
  out.append(box);
  box.append(el('div', { class: 'state' }, [el('div', { class: 'spinner' })]));

  let candidates = [];
  try { candidates = await promotionCandidates() || []; } catch { /* n/a */ }

  let rows = [];
  try { rows = await leadersAtlas() || []; }
  catch (err) {
    clear(box);
    box.append(el('p', { class: 'muted',
      text: err?.message === 'HQ only'
        ? t('atlas.hqOnly') : t('atlas.needs74') }));
    return;
  }
  clear(box);
  if (!rows.length) {
    box.append(el('p', { class: 'muted', text: t('atlas.none') }));
    return;
  }

  /* ---- summary ---- */
  const countries = [...new Set(rows.map((r) => r.country || '—'))];
  const withLogin = rows.filter((r) => r.has_login).length;
  const avgPct = Math.round(rows.reduce((a, r) => a
    + (r.modules_total ? r.modules_passed / r.modules_total : 0), 0)
    / rows.length * 100);
  box.append(el('div', { class: 'stats mb-4' }, [
    tile(t('atlas.leaders'), rows.length),
    tile(t('atlas.countries'), countries.length),
    tile(t('atlas.withLogin'), `${withLogin}/${rows.length}`),
    tile(t('atlas.avgCourse'), `${avgPct}%`),
  ]));

  /* ---- promotion candidates: passed the activation, awaiting a seat ---- */
  if (candidates.length) {
    const pcCard = el('div', { class: 'card mb-4', style:
      'border-left:4px solid #7CB518;' });
    pcCard.append(el('h3', { style: 'margin:0 0 4px;',
      text: t('atlas.candTitle', { n: candidates.length }) }));
    pcCard.append(el('p', { class: 'muted', style: 'font-size:13px;',
      text: t('atlas.candHint') }));
    candidates.forEach((c) => {
      const row = el('div', { style:
        'display:flex;align-items:center;gap:10px;padding:8px 0;'
        + 'border-top:1px solid var(--line);flex-wrap:wrap;' });
      row.innerHTML = `<div style="flex:1;min-width:200px;">
        <b>${esc(c.name)}</b> <span class="muted" style="font-size:12px;">
        · ${esc(c.role_applied || '')}</span><br>
        <span class="muted" style="font-size:12px;">${esc(
          [c.country, c.state, c.lga].filter(Boolean).join(' · '))}</span>`;
      const btn = el('button', { class: 'btn btn--secondary',
        text: t('atlas.assignSeat') });
      btn.addEventListener('click', () => assignSeat(c));
      row.append(btn);
      pcCard.append(row);
    });
    box.append(pcCard);
  }

  async function assignSeat(c) {
    const ISO = { Benin: 'BJ', 'Burkina Faso': 'BF', Burundi: 'BI',
      Cameroon: 'CM', 'Central African Republic': 'CF', Chad: 'TD',
      Congo: 'CG', "Côte d'Ivoire": 'CI', 'DR Congo': 'CD', Gambia: 'GM',
      Ghana: 'GH', Guinea: 'GN', 'Guinea-Bissau': 'GW', Kenya: 'KE',
      Madagascar: 'MG', Mali: 'ML', Morocco: 'MA', Niger: 'NE',
      Nigeria: 'NG', Rwanda: 'RW', Senegal: 'SN', 'South Africa': 'ZA',
      Togo: 'TG', Tunisia: 'TN', Uganda: 'UG' };
    const iso = ISO[c.country];
    if (!iso) { toastError(t('atlas.noCountryMatch')); return; }
    let seats = [];
    try { seats = await vacantSeatsFor(iso) || []; }
    catch { toastError(t('atlas.needs75')); return; }
    if (!seats.length) {
      toast(t('atlas.noVacancy', { country: c.country })); return;
    }
    const list = seats.map((s, i) =>
      `${i + 1}. ${s.role} — ${s.location}`).join('\n');
    const pick = prompt(
      t('atlas.pickSeat', { name: c.name, list }));
    const idx = Number(pick) - 1;
    if (!Number.isInteger(idx) || !seats[idx]) return;
    const seat = seats[idx];
    try {
      await promoteCandidate(c.id, seat.org_unit_id, seat.role);
      toast(t('atlas.promoted', { name: c.name, role: seat.role,
        loc: seat.location }));
      render(root);
    } catch (err) { toastError(err?.message || t('errors.load')); }
  }

  /* ---- country groups ---- */
  const byCountry = new Map();
  rows.forEach((r) => {
    const k = r.country || '—';
    if (!byCountry.has(k)) byCountry.set(k, []);
    byCountry.get(k).push(r);
  });

  [...byCountry.keys()].sort().forEach((country) => {
    const group = byCountry.get(country);
    const card = el('div', { class: 'card mb-3' });
    const head = el('div', { style:
      'display:flex;align-items:center;gap:10px;flex-wrap:wrap;' }, [
      el('h3', { style: 'margin:0;flex:1;',
        text: `${country} · ${group.length}` }),
      el('button', { class: 'btn btn--secondary',
        text: t('atlas.msgAll', { n: group.length }),
        onclick: () => bulkMessage(group, country) }),
      el('button', { class: 'btn btn--secondary',
        text: t('atlas.taskAll', { n: group.length }),
        onclick: () => taskModal(group, country) }),
    ]);
    card.append(head);

    /* Nigeria (and any country with states) groups one level deeper */
    const byState = new Map();
    group.forEach((r) => {
      const s = r.state || '';
      if (!byState.has(s)) byState.set(s, []);
      byState.get(s).push(r);
    });
    [...byState.keys()].sort().forEach((state) => {
      if (state) {
        card.append(el('p', { class: 'muted',
          style: 'margin:10px 0 2px;font-weight:600;',
          text: state + (byState.get(state)[0].lga
            ? '' : '') }));
      }
      byState.get(state).forEach((r) => card.append(leaderRow(r)));
    });
    box.append(card);
  });

  function leaderRow(r) {
    const pct = r.modules_total
      ? Math.round(r.modules_passed * 100 / r.modules_total) : 0;
    const row = el('div', { style:
      'display:flex;align-items:center;gap:10px;padding:10px 0;'
      + 'border-top:1px solid var(--line);flex-wrap:wrap;' });
    row.append(el('span', { title: r.has_login
      ? t('atlas.loginYes') : t('atlas.loginNo'),
      style: `width:10px;height:10px;border-radius:50%;flex:0 0 auto;`
        + `background:${r.has_login ? '#7CB518' : '#d1d5db'};` }));
    // Phase 131b: the leader's photo (HQ sets it from #/accounts → Photo);
    // initials when none is stored yet or she has no login.
    const initials = String(r.name || '?').split(/\s+/).map((w) => w[0] || '').join('').slice(0, 2).toUpperCase();
    const ava = r.has_login && r.id
      ? el('img', { class: 'acc-ava', alt: '', src: avatarUrl(r.id),
          onerror: (e) => { e.target.replaceWith(el('div', { class: 'acc-ava acc-ava--none', text: initials })); } })
      : el('div', { class: 'acc-ava acc-ava--none', text: initials });
    row.append(ava);
    const who = el('div', { style: 'flex:1;min-width:180px;' });
    who.innerHTML = `<b>${esc(r.name)}</b>
      <span class="muted" style="font-size:12px;">· ${esc(r.role_applied || '')}</span><br>
      <span class="muted" style="font-size:12px;">${esc(r.membership_no || '')}`
      + `${r.lga ? ' · ' + esc(r.lga) : ''}</span>`;
    row.append(who);
    const perf = el('div', { style: 'min-width:130px;' });
    perf.innerHTML = `<div class="muted" style="font-size:11px;">
        ${esc(t('atlas.courses'))}: ${r.modules_passed}/${r.modules_total}
        · ${pct}%</div>
      <div style="height:5px;border-radius:3px;background:var(--line);
        overflow:hidden;"><div style="height:100%;width:${pct}%;
        background:var(--brand,#D4006A);"></div></div>`;
    row.append(perf);
    row.append(el('span', { class: 'muted',
      style: 'font-size:11px;min-width:86px;',
      text: r.last_seen ? fmtDate(r.last_seen) : t('atlas.neverIn') }));
    row.append(el('button', { class: 'btn btn--quiet',
      text: t('atlas.msg'),
      onclick: () => { location.hash = `#/messages?u=${r.id}`; } }));
    if (r.id) {
      row.append(el('button', { class: 'btn btn--quiet',
        text: t('atlas.taskOne'),
        onclick: () => taskModal([r], r.name) }));
      row.append(el('button', { class: 'btn btn--quiet',
        text: t('atlas.nominate'),
        onclick: () => nominateModal(r) }));
    }
    return row;
  }

  function nominateModal(leader) {
    const catSel = el('select', { class: 'input' }, [
      el('option', { value: 'SCA', text: t('atlas.catSCA') }),
      el('option', { value: 'QSR', text: t('atlas.catQSR') }),
      el('option', { value: 'LGR', text: t('atlas.catLGR') }),
      el('option', { value: 'MAR', text: t('atlas.catMAR') }),
      el('option', { value: 'TCR', text: t('atlas.catTCR') }),
    ]);
    const contribution = el('textarea', { class: 'input', rows: '4',
      placeholder: t('atlas.nomContribPh') });
    const evidence = el('textarea', { class: 'input', rows: '3',
      placeholder: t('atlas.nomEvidencePh') });
    const others = el('input', { class: 'input',
      placeholder: t('atlas.nomOthersPh') });
    const err = el('p', { class: 'field__error', hidden: true });
    const submit = el('button', { class: 'btn btn--primary', type: 'submit',
      text: t('atlas.nomSubmit') });
    const form = el('form', { onsubmit: async (e) => {
      e.preventDefault();
      if (contribution.value.trim().length < 20) {
        err.textContent = t('atlas.nomErrShort'); err.hidden = false; return;
      }
      err.hidden = true; submit.disabled = true;
      try {
        await submitSpotlightNomination({
          category: catSel.value, nomineeId: leader.id,
          contribution: contribution.value.trim(),
          evidence: evidence.value.trim() || t('atlas.nomEvidenceDefault'),
          otherContributors: others.value.trim() });
        toast(t('atlas.nomSent', { name: leader.name }));
        closeModal();
      } catch (err2) {
        err.textContent = err2?.message || t('errors.save');
        err.hidden = false; submit.disabled = false;
      }
    } }, [
      el('p', { class: 'muted mb-2',
        text: t('atlas.nomHint', { name: leader.name }) }),
      el('div', { class: 'field' }, [
        el('label', { class: 'field__label', text: t('atlas.nomCategory') }),
        catSel]),
      el('div', { class: 'field' }, [
        el('label', { class: 'field__label', text: t('atlas.nomContrib') }),
        contribution]),
      el('div', { class: 'field' }, [
        el('label', { class: 'field__label', text: t('atlas.nomEvidence') }),
        evidence]),
      el('div', { class: 'field' }, [
        el('label', { class: 'field__label', text: t('atlas.nomOthers') }),
        others]),
      err,
      el('div', { class: 'row' }, [el('span', { class: 'grow' }), submit]),
    ]);
    openModal(t('atlas.nomModalTitle'), form);
  }

  async function bulkMessage(group, label) {
    const withId = group.filter((g) => g.id);
    const text = prompt(t('atlas.bulkPrompt', { where: label,
      n: withId.length }));
    if (!text || !text.trim()) return;
    let sent = 0;
    toast(t('atlas.bulkSending'));
    for (const g of withId) {
      try {
        // eslint-disable-next-line no-await-in-loop
        await sendStaffMessage(g.id, text.trim());
        sent += 1;
      } catch { /* keep going — count tells the truth */ }
    }
    toast(t('atlas.bulkDone', { sent, n: withId.length }));
  }

  let hqUnitId = null;
  async function ensureHqUnit() {
    if (hqUnitId) return hqUnitId;
    const { data } = await db().from('org_units').select('id')
      .eq('level', 'headquarters').limit(1).maybeSingle();
    hqUnitId = data?.id || null;
    return hqUnitId;
  }

  /** The real task-assignment form: topic, full description, due date,
   *  an optional document, an optional voice note — sent to one leader
   *  or a whole country at once. Replaces the old title-only prompt(). */
  function taskModal(group, label) {
    const withId = group.filter((g) => g.id);
    const topic = el('input', { class: 'input', maxlength: '160',
      placeholder: t('atlas.taskTopicPh') });
    const full = el('textarea', { class: 'input', rows: '5',
      maxlength: '4000', placeholder: t('atlas.taskFullPh') });
    const due = el('input', { class: 'input', type: 'date' });
    const fileIn = el('input', { type: 'file', hidden: true });
    let pendingFile = null;
    const fileBtn = el('button', { class: 'btn btn--secondary',
      type: 'button', text: t('atlas.taskAttachDoc') });
    fileBtn.addEventListener('click', () => fileIn.click());
    fileIn.addEventListener('change', () => {
      pendingFile = fileIn.files[0] || null;
      fileBtn.textContent = pendingFile
        ? `\u{1F4CE} ${pendingFile.name}` : t('atlas.taskAttachDoc');
    });

    let rec = null; let chunks = []; let voiceFile = null;
    const micBtn = el('button', { class: 'btn btn--secondary',
      type: 'button', text: t('atlas.taskAttachVoice') });
    const micStatus = el('span', { class: 'muted',
      style: 'font-size:12px;margin-left:8px;' });
    micBtn.addEventListener('click', async () => {
      if (rec) { rec.stop(); return; }
      try {
        const stream = await navigator.mediaDevices
          .getUserMedia({ audio: true });
        rec = MediaRecorder.isTypeSupported('audio/webm')
          ? new MediaRecorder(stream, { mimeType: 'audio/webm' })
          : new MediaRecorder(stream);
        chunks = [];
        rec.ondataavailable = (e) => chunks.push(e.data);
        rec.onstop = async () => {
          stream.getTracks().forEach((tk) => tk.stop());
          const blob = new Blob(chunks, { type: 'audio/webm' });
          rec = null;
          micBtn.classList.remove('btn--danger');
          let peak = 0;
          try {
            const ac = new (window.AudioContext
              || window.webkitAudioContext)();
            const decoded = await ac.decodeAudioData(await blob.arrayBuffer());
            const ch = decoded.getChannelData(0);
            for (let i = 0; i < ch.length; i += 256) {
              peak = Math.max(peak, Math.abs(ch[i]));
            }
            ac.close();
          } catch { peak = 1; /* decode unsupported: trust the recording */ }
          if (peak < 0.01) {
            voiceFile = null;
            micBtn.textContent = t('atlas.taskAttachVoice');
            micStatus.textContent = t('atlas.taskVoiceSilent');
            return;
          }
          voiceFile = new File([blob], `voice-${Date.now()}.webm`,
            { type: 'audio/webm' });
          micBtn.textContent = `\u{1F3A4}\u2713 ${t('atlas.taskVoiceReady')}`;
          micStatus.textContent = '';
        };
        rec.start();
        micBtn.textContent = `\u23F9 ${t('atlas.taskRecording')}`;
        micBtn.classList.add('btn--danger');
      } catch { toastError(t('itp.micError')); rec = null; }
    });

    const err = el('p', { class: 'field__error', hidden: true });
    const submit = el('button', { class: 'btn btn--primary',
      type: 'submit', text: t('atlas.taskSend', { n: withId.length }) });
    const form = el('form', { novalidate: true, onsubmit: async (e) => {
      e.preventDefault();
      if (topic.value.trim().length < 3) {
        err.textContent = t('tasks.errTitle'); err.hidden = false; return;
      }
      err.hidden = true;
      submit.disabled = true;
      const unit = await ensureHqUnit();
      if (!unit) {
        err.textContent = t('errors.load'); err.hidden = false;
        submit.disabled = false; return;
      }
      let sent = 0;
      toast(t('atlas.taskSending'));
      for (const g of withId) {
        try {
          // eslint-disable-next-line no-await-in-loop
          const task = await createTask({ title: topic.value.trim(),
            details: full.value.trim() || null, assigned_to: g.id,
            org_unit_id: unit, priority: 'medium',
            due_on: due.value || null });
          if (pendingFile) {
            // eslint-disable-next-line no-await-in-loop
            await addTaskFile(task.id, pendingFile).catch(() => {});
          }
          if (voiceFile) {
            // eslint-disable-next-line no-await-in-loop
            await addTaskFile(task.id, voiceFile).catch(() => {});
          }
          sent += 1;
        } catch { /* keep going — count tells the truth */ }
      }
      toast(t('atlas.taskDone', { sent, n: withId.length }));
      closeModal();
    } }, [
      el('p', { class: 'muted mb-2',
        text: t('atlas.taskModalHint', { where: label, n: withId.length }) }),
      el('div', { class: 'form-grid' }, [
        wrap(t('atlas.taskTopic'), topic),
        wrap(t('atlas.taskDue'), due),
      ]),
      wrap(t('atlas.taskFull'), full),
      el('div', { class: 'row', style: 'gap:8px;flex-wrap:wrap;margin:8px 0;' },
        [fileBtn, micBtn, micStatus]),
      err,
      el('div', { class: 'row' }, [el('span', { class: 'grow' }), submit]),
    ]);
    function wrap(label2, node) {
      return el('div', { class: 'field' }, [
        el('label', { class: 'field__label', text: label2 }), node]);
    }
    openModal(t('atlas.taskModalTitle'), form);
  }

  function tile(label, value) {
    return el('div', { class: 'stat' }, [
      el('div', { class: 'stat__icon' }, [icon('users')]),
      el('div', {}, [
        el('div', { class: 'stat__value', text: String(value) }),
        el('div', { class: 'stat__label', text: label }),
      ]),
    ]);
  }
}
