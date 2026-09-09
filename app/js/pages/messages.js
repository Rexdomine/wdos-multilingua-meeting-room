/**
 * WDOS Messages — Phase 49. Real two-way conversations: volunteer leaders
 * write to HQ, HQ replies, staff chat among themselves — one inbox, chat
 * bubbles, unread markers. Members cannot message each other directly
 * (the wall holds); the compose picker only offers HQ staff to members.
 */
import { el, esc, clear, personLabel } from '../core/dom.js';
import { t, fmtDateTime } from '../core/i18n.js';
import { db, getSession, sendStaffMessage, searchMessageRecipients,
  messageIdentities, staffFileUrl } from '../core/db.js';
import { renderShell } from '../components/layout.js';
import { toast, toastError } from '../components/toast.js';

export async function render(root, _params, ctx) {
  const shell = renderShell(root, {
    profile: ctx.profile, modules: ctx.modules, titleKey: 'nav.messages',
  });
  const out = shell.outlet;
  clear(out);

  const session = await getSession();
  const myId = session.user.id;

  let channel = null;
  const listBox = el('div');
  out.append(el('p', { class: 'muted mb-2', text: t('msgs.hint') }), listBox);
  const deepU = _params?.u ? String(_params.u) : null;
  if (deepU && deepU !== myId) {
    let nm2 = t('bell.someone');
    let ver2 = false;
    try {
      const idn = (await messageIdentities())
        .find((x) => x.profile_id === deepU);
      if (idn) { nm2 = idn.display_name || nm2; ver2 = !!idn.verified; }
      else {
        const { data } = await db().from('profiles')
          .select('first_name, last_name').eq('id', deepU).single();
        if (data) nm2 = `${data.first_name} ${data.last_name}`;
      }
    } catch { /* keep placeholder */ }
    thread(deepU, nm2, ver2);
  } else {
    await conversations();
  }
  return () => {
    try { if (channel) db().removeChannel(channel); } catch { /* gone */ }
    return shell.teardown();
  };

  /* ---------------- data ---------------- */
  async function fetchAll() {
    const { data, error } = await db().from('staff_messages')
      .select('id, sender_id, recipient_id, body, read_at, created_at, attachment_path, attachment_name')
      .order('created_at', { ascending: false }).limit(400);
    if (error) throw error;
    return data;
  }
  async function names(ids) {
    if (!ids.length) return new Map();
    const out = new Map();
    try {
      for (const r of await messageIdentities()) {
        out.set(r.profile_id,
          { name: r.display_name || t('bell.someone'), verified: !!r.verified });
      }
    } catch { /* fall through to profiles */ }
    const missing = ids.filter((id) => !out.has(id));
    if (missing.length) {
      const { data } = await db().from('profiles')
        .select('id, first_name, last_name').in('id', missing);
      for (const p of (data || [])) {
        out.set(p.id, { name: personLabel(p), verified: false });
      }
    }
    return out;
  }
  function nameEl(idn) {
    const wrap = el('span', {}, [
      el('span', { text: (idn && idn.name) || t('bell.someone') })]);
    if (idn && idn.verified) {
      wrap.append(el('span', { class: 'vtick',
        title: t('msgs.verified'), text: '\u2713' }));
    }
    return wrap;
  }

  /* ---------------- conversation list ---------------- */
  async function conversations() {
    clear(listBox);
    listBox.append(el('div', { class: 'state' }, [el('div', { class: 'spinner' })]));
    let msgs;
    try { msgs = await fetchAll(); }
    catch { clear(listBox); listBox.append(el('p', { class: 'muted', text: t('errors.loadHint') })); return; }

    const convs = new Map();  // otherId -> {last, unread}
    for (const m of msgs) {
      const other = m.sender_id === myId ? m.recipient_id : m.sender_id;
      if (!convs.has(other)) convs.set(other, { last: m, unread: 0 });
      if (m.recipient_id === myId && !m.read_at) convs.get(other).unread += 1;
    }
    const nm = await names([...convs.keys()]);
    clear(listBox);

    listBox.append(el('button', { class: 'btn btn--primary mb-4',
      text: t('msgs.new'), onclick: () => compose() }));

    if (!convs.size) {
      listBox.append(el('p', { class: 'muted', text: t('msgs.none') }));
      return;
    }
    const wrap = el('div', { class: 'card' });
    for (const [other, c] of convs) {
      const idn = nm.get(other);
      wrap.append(el('button', { class: 'conv',
        onclick: () => thread(other, (idn && idn.name) || t('bell.someone'),
          !!(idn && idn.verified)) }, [
        el('div', { class: 'conv__main' }, [
          el('strong', {}, [nameEl(idn)]),
          el('span', { class: 'conv__snippet',
            text: (c.last.sender_id === myId ? t('msgs.you') + ' ' : '')
              + (c.last.body || '').slice(0, 70) }),
        ]),
        el('div', { class: 'conv__meta' }, [
          el('span', { class: 'muted', text: fmtDateTime(c.last.created_at) }),
          c.unread ? el('span', { class: 'bell__badge',
            style: 'position:static;', text: String(c.unread) }) : null,
        ]),
      ]));
    }
    listBox.append(wrap);
  }

  /* ---------------- compose (pick a recipient) ---------------- */
  async function compose() {
    clear(listBox);
    listBox.append(back(conversations));
    const search = el('input', { class: 'input',
      placeholder: t('msgs.searchPh') });
    const results = el('div', { class: 'card mt-2' });
    listBox.append(el('h2', { class: 'mb-2', text: t('msgs.new') }),
      el('p', { class: 'muted mb-2', text: t('msgs.membersHint') }),
      search, results);

    async function find() {
      clear(results);
      try {
        const rows = await searchMessageRecipients(search.value.trim());
        clear(results);
        if (!rows || !rows.length) {
          results.append(el('p', { class: 'muted', text: t('msgs.noResults') }));
          return;
        }
        for (const r of rows.filter((x) => x.id !== myId)) {
          const isHq = r.kind === 'hq';
          const nm3 = isHq ? t('msgs.hqName')
            : `${r.first_name} ${r.last_name}`;
          const ver3 = isHq || r.kind === 'staff';
          results.append(el('button', { class: 'conv',
            onclick: () => thread(r.id, nm3, ver3) }, [
            el('div', { class: 'conv__main' }, [
              el('strong', {}, [nameEl({ name: nm3, verified: ver3 })]),
              el('span', { class: 'conv__snippet',
                text: [r.sub || '', r.kind === 'member'
                  ? t('msgs.memberTag') : ''].filter(Boolean).join(' \u00b7 ') }),
            ]),
          ]));
        }
      } catch {
        clear(results);
        results.append(el('p', { class: 'muted', text: t('msgs.noResults') }));
      }
    }
    search.addEventListener('input', () => find());
    await find();
  }

  function fmtBody(txt) {
    let h = esc(txt || '');
    h = h.replace(/\*\*([^*\n]{1,200})\*\*/g, '<strong>$1</strong>');
    h = h.replace(/(^|[^*])\*([^*\n]{1,200})\*/g, '$1<em>$2</em>');
    h = h.replace(/`([^`\n]{1,120})`/g,
      '<code style="background:rgba(0,0,0,.12);padding:0 4px;border-radius:4px;">$1</code>');
    return h.replace(/\n/g, '<br>');
  }

  function attachmentEl(m) {
    if (!m.attachment_path) return null;
    const isAudio = /\.(webm|ogg|mp3|m4a|wav)$/i.test(m.attachment_name || '');
    const isImage = /\.(png|jpe?g|gif|webp)$/i.test(m.attachment_name || '');
    if (isAudio) {
      const wrap = el('span');
      const audio = el('audio', { controls: '', preload: 'metadata',
        style: 'display:block;margin-top:6px;max-width:230px;' });
      const linkFallback = () => {
        const a = el('a', { href: '#',
          style: 'display:block;margin-top:6px;',
          text: `\u{1F3A4} ${m.attachment_name || 'voice note'}`,
          onclick: async (ev) => {
            ev.preventDefault();
            try {
              window.open(await staffFileUrl(m.attachment_path),
                '_blank', 'noopener');
            } catch { toastError(t('msgs.voiceGone')); }
          } });
        wrap.replaceChildren(a);
      };
      // voice notes recorded in browsers carry no duration header;
      // force the real length so the player doesn't sit at 0:00
      audio.addEventListener('loadedmetadata', () => {
        if (!Number.isFinite(audio.duration)) {
          const fix = () => {
            audio.currentTime = 0;
            audio.removeEventListener('timeupdate', fix);
          };
          audio.addEventListener('timeupdate', fix);
          audio.currentTime = 1e10;
        }
      });
      audio.addEventListener('error', linkFallback);
      staffFileUrl(m.attachment_path)
        .then((u) => { audio.src = u; }).catch(linkFallback);
      wrap.append(audio);
      return wrap;
    }
    if (isImage) {
      const img = el('img', { alt: m.attachment_name || '',
        style: 'display:block;max-width:220px;border-radius:8px;margin-top:6px;' });
      staffFileUrl(m.attachment_path)
        .then((u) => { img.src = u; }).catch(() => img.remove());
      return img;
    }
    return el('a', { href: '#', style: 'display:block;margin-top:6px;',
      text: `\u{1F4CE} ${m.attachment_name || 'file'}`,
      onclick: async (ev) => {
        ev.preventDefault();
        try {
          window.open(await staffFileUrl(m.attachment_path),
            '_blank', 'noopener');
        } catch { /* expired */ }
      } });
  }

  /* ---------------- thread ---------------- */
  async function thread(otherId, otherName, otherVerified = false) {
    if (otherId === myId) { toastError(t('msgs.notSelf')); return; }
    clear(listBox);
    listBox.append(back(conversations));
    listBox.append(el('h2', { class: 'mb-2' },
      [nameEl({ name: otherName, verified: otherVerified })]));

    const log = el('div', { class: 'ask__log', style: 'max-height:50vh;' });
    const input = el('textarea', { class: 'input', rows: '2',
      placeholder: t('msgs.replyPh'), style: 'flex:1;' });
    const send = el('button', { class: 'btn btn--primary', text: t('msgs.send') });
    const fileIn = el('input', { type: 'file', hidden: true });
    let pendingFile = null;
    const attachBtn = el('button', { class: 'btn btn--quiet msg-iconbtn',
      title: t('msgs.attach'), text: '\u{1F4CE}',
      onclick: () => fileIn.click() });
    fileIn.addEventListener('change', () => {
      pendingFile = fileIn.files[0] || null;
      attachBtn.textContent = pendingFile
        ? '\u{1F4CE}\u2713' : '\u{1F4CE}';
    });
    let rec = null; let recChunks = []; let recDone = null;
    let recCtx = null; let recMeter = null;
    const micBtn = el('button', { class: 'btn btn--quiet msg-iconbtn',
      title: t('msgs.voice'), text: '\u{1F3A4}' });
    micBtn.addEventListener('click', async () => {
      if (rec) { rec.stop(); return; }
      try {
        const stream = await navigator.mediaDevices
          .getUserMedia({ audio: true });
        rec = MediaRecorder.isTypeSupported('audio/webm')
          ? new MediaRecorder(stream, { mimeType: 'audio/webm' })
          : new MediaRecorder(stream);
        recChunks = [];
        rec.ondataavailable = (e) => recChunks.push(e.data);

        // ── the microphone must prove itself: live level bar while
        //    recording, and a silence check before anything is sent.
        let live = true; let peakLive = 0;
        try {
          recCtx = new (window.AudioContext || window.webkitAudioContext)();
          const srcNode = recCtx.createMediaStreamSource(stream);
          const an = recCtx.createAnalyser(); an.fftSize = 512;
          srcNode.connect(an);
          recMeter = el('div', { style: 'height:6px;border-radius:3px;'
            + 'background:var(--line);overflow:hidden;margin:6px 0 0;' });
          const mFill = el('div', { style: 'height:100%;width:0%;'
            + 'background:#7CB518;transition:width .12s;' });
          recMeter.append(mFill);
          failBox.before(recMeter);
          const buf = new Uint8Array(an.frequencyBinCount);
          (function pump() {
            if (!live) return;
            an.getByteTimeDomainData(buf);
            let p = 0;
            for (let i = 0; i < buf.length; i += 1) {
              p = Math.max(p, Math.abs(buf[i] - 128) / 128);
            }
            peakLive = Math.max(peakLive, p);
            mFill.style.width = `${Math.min(100, Math.round(p * 140))}%`;
            mFill.style.background = p < 0.02 ? '#dc2626' : '#7CB518';
            requestAnimationFrame(pump);
          }());
        } catch { /* no meter — silence check below still runs */ }

        rec.onstop = async () => {
          live = false;
          stream.getTracks().forEach((tk) => tk.stop());
          if (recMeter) { recMeter.remove(); recMeter = null; }
          try { if (recCtx) { recCtx.close(); recCtx = null; } }
          catch { /* already closed */ }
          const blob = new Blob(recChunks, { type: 'audio/webm' });
          let peak = peakLive;
          try {
            const ac = new (window.AudioContext
              || window.webkitAudioContext)();
            const decoded = await ac.decodeAudioData(await blob.arrayBuffer());
            const ch = decoded.getChannelData(0);
            for (let i = 0; i < ch.length; i += 256) {
              peak = Math.max(peak, Math.abs(ch[i]));
            }
            ac.close();
          } catch { /* decode unsupported — the live meter's peak decides */ }
          rec = null;
          micBtn.classList.remove('btn--danger');
          if (peak < 0.01) {
            pendingFile = null;
            micBtn.textContent = '\u{1F3A4}';
            failBox.textContent = t('msgs.voiceSilent');
            failBox.hidden = false;
            if (recDone) { recDone(); recDone = null; }
            return;
          }
          failBox.hidden = true;
          pendingFile = new File([blob],
            `voice-${Date.now()}.webm`, { type: 'audio/webm' });
          micBtn.textContent = '\u{1F3A4}\u2713';
          if (recDone) { recDone(); recDone = null; }
          else toast(t('msgs.voiceReady'));
        };
        rec.start();
        micBtn.textContent = '\u23F9';
        micBtn.classList.add('btn--danger');
        toast(t('msgs.voiceRec'));
      } catch { toastError(t('itp.micError')); rec = null; }
    });
    const failBox = el('div', { hidden: true, class: 'card mt-2', style:
      'border-left:4px solid #dc2626;padding:10px 14px;background:'
      + 'rgba(220,38,38,.06);' });
    listBox.append(failBox);
    listBox.append(log,
      el('p', { class: 'muted', style: 'font-size:11px;margin:6px 0 0;',
        text: t('msgs.fmtHint') }),
      el('div', { class: 'row mt-2',
        style: 'gap:6px;align-items:flex-end;' },
        [attachBtn, micBtn, input, send]), fileIn);

    try { if (channel) db().removeChannel(channel); } catch { /* gone */ }
    channel = db().channel(`msg-${myId}-${Date.now()}`)
      .on('postgres_changes', { event: 'INSERT', schema: 'public',
        table: 'staff_messages' }, (pl) => {
        const n = pl?.new;
        if (!n) return;
        if ((n.sender_id === otherId && n.recipient_id === myId)
            || (n.sender_id === myId && n.recipient_id === otherId)) {
          paint();
        }
        document.dispatchEvent(new CustomEvent('wdos:notify'));
      })
      .subscribe();

    async function paint() {
      let msgs;
      try { msgs = await fetchAll(); } catch { return; }
      const mine = msgs.filter((m) =>
        (m.sender_id === myId && m.recipient_id === otherId)
        || (m.sender_id === otherId && m.recipient_id === myId))
        .reverse();
      clear(log);
      for (const m of mine) {
        const body = el('p');
        body.innerHTML = fmtBody(m.body);
        const bub = el('div', {
          class: 'ask__msg ' + (m.sender_id === myId
            ? 'ask__msg--me' : 'ask__msg--bot') }, [body]);
        const att = attachmentEl(m);
        if (att) bub.append(att);
        bub.append(el('span', { class: 'muted',
          style: 'font-size:10px;display:block;',
          text: fmtDateTime(m.created_at) }));
        log.append(bub);
      }
      log.scrollTop = log.scrollHeight;
      // mark incoming as read
      db().from('staff_messages')
        .update({ read_at: new Date().toISOString() })
        .eq('recipient_id', myId).eq('sender_id', otherId).is('read_at', null)
        .then(() => document.dispatchEvent(new CustomEvent('wdos:notify')))
        .catch?.(() => {});
    }
    await paint();

    send.addEventListener('click', async () => {
      if (rec) {  // still recording — finish it, then send (3s cap)
        await Promise.race([
          new Promise((res) => { recDone = res;
            try { rec.stop(); } catch { res(); } }),
          new Promise((res) => setTimeout(res, 3000)),
        ]);
        rec = null;
      }
      const v = input.value.trim();
      if (v.length < 1 && !pendingFile) {
        toastError(t('msgs.nothingToSend'));
        return;
      }
      send.disabled = true;
      try {
        await sendStaffMessage(otherId, v || '\u{1F4CE}', pendingFile);
        input.value = '';
        failBox.hidden = true;
        pendingFile = null; fileIn.value = '';
        attachBtn.textContent = '\u{1F4CE}';
        micBtn.textContent = '\u{1F3A4}';
        await paint();
      } catch (err) {
        const why = String(err?.message || err?.error_description
          || err?.hint || JSON.stringify(err) || '').slice(0, 400);
        toastError(t('msgs.sendFailed'));
        failBox.hidden = false;
        clear(failBox);
        failBox.append(
          el('strong', { text: t('msgs.sendFailed') }),
          el('p', { style: 'margin:6px 0;overflow-wrap:anywhere;'
            + 'font-size:13px;', text: why || '(no reason returned)' }),
          el('button', { class: 'btn btn--quiet',
            style: 'min-height:30px;padding:4px 12px;',
            text: t('doc.copy'),
            onclick: () => { navigator.clipboard?.writeText(why);
              toast(t('doc.copied')); } }));
      }
      finally { send.disabled = false; }
    });
  }

  function back(fn) {
    return el('button', { class: 'btn btn--quiet mb-2',
      text: '\u2190 ' + t('app.back'), onclick: fn });
  }
}
