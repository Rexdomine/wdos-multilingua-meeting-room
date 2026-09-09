/**
 * Phase 33 — "My WODDI": the mobile-first leader / volunteer experience.
 * Four tabs: Home, Journey (the 14-day activation, live), Learn (the
 * engagement library), Profile. Runs in the phone-shaped mobile shell.
 */
import { el, clear, esc } from '../core/dom.js';
import { t, fmtDate, fmtNumber } from '../core/i18n.js';
import {
  getJourney, getActivationDays, getAllActivationItems, getMyResponses,
  submitActivationItem, getActivationSummary, getEngagementFor, listEngagement,
  getMyDay, getMyRoles, avatarUrl, uploadAvatar, changePassword,
  getMyNotices, markNoticeRead, updateMyProfile, amIStaff, programmeState,
  db, listStaffMessages, sendStaffMessage, markMessageRead, hqInboxTarget,
  journeySignals, logJourneyEvent, uploadMemberCv, myTeam, mySubtree,
} from '../core/db.js';
import { setLocale, getLocale, supportedLocales } from '../core/i18n.js';
import { renderMobile } from '../components/mobileshell.js';
import { AFRICAN_COUNTRIES, NG_STATES } from '../core/geo.js';
import { renderCourses } from '../components/courses.js';
import { toast, toastError } from '../components/toast.js';
import { icon } from '../components/icons.js';

const LOCALE_NAMES = {
  en: 'English', fr: 'Français', pt: 'Português', ar: 'العربية',
  sw: 'Kiswahili', ha: 'Hausa', yo: 'Yorùbá', ig: 'Igbo',
};

// Convening levels per network (Phase 94). Module-scope on purpose: the
// leader home draws this card while render() is still running, so a
// constant declared inside render() would not exist yet (TDZ error seen
// as "Cannot access 'CONVENING' before initialization").
const CONVENING = {
  WGMN: [
    { code: 'WCGC', name: 'Continental Governance Council', freq: 'Bi-Annual',
      months: 'February, September',
      who: 'HQ Team, Country Representatives, Deputy Country '
        + 'Representatives, State/Province/Regional Coordinators & '
        + 'Assistants',
      purpose: 'Strategic vision, institutional governance and '
        + 'continental alignment' },
    { code: 'WNLA', name: 'National Leadership Assembly', freq: 'Tri-Annual',
      months: 'April, August, December',
      who: 'HQ Team, CRs, DCRs, State/Province/Regional Coordinators & '
        + 'Assistants, LGA Administrators & Assistants, Chapter Leads & '
        + 'Communications Officers',
      purpose: 'Country coordination, national programme leadership and '
        + 'implementation' },
    { code: 'WRCF', name: 'Regional Coordination Forum', freq: 'Bi-Monthly',
      months: 'February, April, June, August, October, December',
      who: 'State/Province/Regional Coordinators & Assistants, LGA '
        + 'Administrators & Assistants, Chapter Leads & Communications '
        + 'Officers',
      purpose: 'Sub-national coordination, chapter support and community '
        + 'mobilisation' },
    { code: 'WCTC', name: 'Community Transformation Circle', freq: 'Quarterly',
      months: 'March, June, August, November',
      who: 'CRs, DCRs, State/Province/Regional Coordinators & Assistants, '
        + 'LGA Administrators & Assistants, Chapter Leads & '
        + 'Communications Officers',
      purpose: 'Grassroots empowerment, WGMN programmes and community '
        + 'transformation' },
  ],
  WNNN: [
    { code: 'WCGC', name: 'Continental Governance Council', freq: 'Bi-Annual',
      months: 'February, September',
      who: 'HQ Team, Country Lead, Deputy Lead, State/Province/Regional '
        + 'Coordinators & Assistants',
      purpose: 'Strategic vision, institutional governance and '
        + 'continental alignment' },
    { code: 'WNLA', name: 'National Leadership Assembly', freq: 'Tri-Annual',
      months: 'April, August, December',
      who: 'HQ Team, Country Lead, Deputy Lead, State/Province/Regional '
        + 'Coordinators & Assistants, LGA Administrators & Assistants, '
        + 'Chapter Leads & Communications Officers',
      purpose: 'Country coordination, national programme leadership and '
        + 'implementation' },
    { code: 'WRCF', name: 'Regional Coordination Forum', freq: 'Bi-Monthly',
      months: 'February, April, June, August, October, December',
      who: 'State/Province/Regional Coordinators & Assistants, LGA '
        + 'Administrators & Assistants, Chapter Leads & Communications '
        + 'Officers',
      purpose: 'Sub-national coordination, chapter support and community '
        + 'mobilisation' },
    { code: 'WCTC', name: 'Community Transformation Circle', freq: 'Quarterly',
      months: 'March, June, August, November',
      who: 'Country Lead, Deputy Lead, State/Province/Regional '
        + 'Coordinators & Assistants, LGA Administrators & Assistants, '
        + 'Chapter Leads & Communications Officers',
      purpose: 'Grassroots empowerment, WNNN programmes and community '
        + 'transformation' },
  ],
};

export async function render(root, params, ctx) {
  const profile = ctx.profile;

  let progState = 'open';
  try { progState = String(await programmeState()); } catch { /* open */ }
  const progBanner = () => progState === 'open' ? null
    : el('div', { class: 'card mb-2', style:
        'border-left:4px solid var(--lime,#7CB518);padding:10px 14px;' }, [
      el('strong', { text: t(`prog.${progState}Title`) }),
      el('p', { class: 'muted', style: 'font-size:13px;margin:4px 0 0;',
        text: t(`prog.${progState}Body`) }),
    ]);

  // The wall: My WODDI is the volunteer leadership space. HQ staff work
  // in the central dashboard and are redirected with a friendly note.
  if (await amIStaff()) {
    clear(root);
    root.append(el('div', { class: 'mob' }, [
      el('div', { class: 'mob__body' }, [
        el('div', { class: 'card state', style: 'margin-top:40px;' }, [
          el('h3', { text: t('me.staffTitle') }),
          el('p', { class: 'muted', text: t('me.staffHint') }),
          el('a', { class: 'btn btn--primary mt-4', href: '#/',
            text: t('me.goDashboard') }),
        ]),
      ]),
    ]));
    return () => {};
  }

  const state = {
    journey: undefined, days: null, items: null, responses: null,
    roles: null, day: null,          // currently-open day number
    hqChannel: null,                 // realtime lane for the HQ thread card
  };
  try {
    const { getSession } = await import('../core/db.js');
    const sess = await getSession();
    state.emailVerified = !!sess?.user?.email_confirmed_at;
  } catch { state.emailVerified = false; }
  try {
    const { avatarUrl } = await import('../core/db.js');
    const head = await fetch(avatarUrl(profile.id, Date.now()),
      { method: 'HEAD' });
    state.hasAvatar = head.ok;
  } catch { state.hasAvatar = false; }

  const established = profile.is_leader
    || ['activated', 'in_training', 'active', 'reinstated']
      .includes(profile.status);

  const shell = renderMobile(root, {
    profile,
    active: params.tab || 'home',
    established,
    onTab: (id) => { state.day = null; show(id); },
  });

  let current = params.tab || 'home';
  await show(current);
  return () => {
    try { if (state.hqChannel) db().removeChannel(state.hqChannel); }
    catch { /* gone */ }
    state.hqChannel = null;
  };

  async function inlineReader(docKey) {
    const META = {
      coc: { file: '/content/code-of-conduct.html',
        title: t('read.cocTitle'), tick: 'conduct' },
      manual: { file: '/content/leadership-manual.html',
        title: t('read.manualTitle'), tick: 'handbook' },
      agreement: { file: '/content/volunteer-agreement.html',
        title: t('read.agreeTitle'), tick: 'agreement', decide: true },
    };
    const meta = META[docKey] || META.manual;
    clear(shell.body);
    shell.body.append(el('button', { class: 'btn btn--quiet',
      style: 'margin-bottom:12px;',
      text: `\u2190 ${t('me.backToDays')}`,
      onclick: () => show('journey') }));
    shell.body.append(el('div', { class: 'mob-sec__h', text: meta.title }));
    const article = el('div', { class: 'card',
      style: 'line-height:1.75;font-size:15px;' });
    article.innerHTML = '<div class="state"><div class="spinner"></div></div>';
    shell.body.append(article);
    const tickAndBack = (msg) => {
      try {
        const cur = JSON.parse(sessionStorage.getItem('wdos.ticks') || '[]');
        if (!cur.includes(meta.tick)) cur.push(meta.tick);
        sessionStorage.setItem('wdos.ticks', JSON.stringify(cur));
      } catch { /* best effort */ }
      toast(msg);
      show('journey');
    };
    if (meta.decide) {
      shell.body.append(el('div', { class: 'row',
        style: 'gap:10px;margin:14px 0 24px;' }, [
        el('button', { class: 'btn btn--primary', style: 'flex:1;',
          text: t('read.accept'),
          onclick: () => tickAndBack(t('read.accepted')) }),
        el('button', { class: 'btn btn--quiet', style: 'flex:1;',
          text: t('read.decline'),
          onclick: () => {
            toastError(t('read.declined'));
            show('journey');
          } }),
      ]));
    } else {
      const done = el('button', { class: 'btn btn--primary',
        style: 'width:100%;margin:14px 0 24px;', text: t('read.markDone') });
      done.addEventListener('click', () => tickAndBack(t('read.marked')));
      shell.body.append(done);
    }
    try {
      const res = await fetch(meta.file, { cache: 'no-cache' });
      if (!res.ok) throw new Error(String(res.status));
      article.innerHTML = await res.text();
    } catch {
      clear(article);
      article.append(el('p', { class: 'muted', text: t('errors.loadHint') }));
    }
  }

  async function show(tab) {
    current = tab;
    shell.setActive(tab);
    clear(shell.body);
    shell.body.append(spinner());
    try {
      if (tab === 'home') await home();
      else if (tab === 'journey') await journey();
      else if (tab === 'learn') await learn();
      else await profileTab();
    } catch (err) {
      console.error('[me] view failed:', tab, err);
      clear(shell.body);
      shell.body.append(errorState(() => show(tab), err));
    }
  }

  /* ---- shared loaders -------------------------------------------------- */
  async function ensureJourney() {
    if (state.journey === undefined) {
      state.journey = await getJourney(profile.id).catch(() => null);
    }
    return state.journey;
  }
  async function ensureActivation() {
    await ensureJourney();
    if (!state.days) {
      [state.days, state.items] = await Promise.all([
        getActivationDays(), getAllActivationItems(),
      ]);
    }
    if (state.journey && !state.responses) {
      state.responses = await getMyResponses(state.journey.id);
    }
  }
  function respMap() {
    return new Map((state.responses || []).map((r) => [r.item_id, r]));
  }
  function dayDone(dayNo, rmap) {
    const req = state.items.filter((i) => i.day === dayNo && i.is_required);
    return req.length > 0 && req.every((i) => rmap.has(i.id));
  }
  function currentDayNo() {
    if (!state.journey) return 1;
    const elapsed = Math.floor(
      (Date.now() - new Date(state.journey.started_at)) / 86400000);
    return Math.min(14, Math.max(1, elapsed + 1));
  }

  /* ===================================================================== */
  /* MESSAGES WITH WODDI HQ (Phase 88)                                     */
  /* ===================================================================== */
  /** The four-level Convening Structure, exactly as published on
   *  thewoddi.org — network-scoped automatically from the leader's own
   *  profile, the same way every other network-specific view in WDOS
   *  already works. No manual switch: a WGMN leader simply never sees
   *  WNNN's calendar, and vice versa. */

  function conveningCard(network) {
    const levels = CONVENING[network] || CONVENING.WGMN;
    const sec = el('div', { class: 'mob-sec' }, [
      el('div', { class: 'mob-sec__h',
        text: t('me.conveningTitle', { net: network }) }),
    ]);
    levels.forEach((lv, i) => {
      const card = el('div', { class: 'card', style:
        (i > 0 ? 'margin-top:8px;' : '') });
      card.innerHTML = `
        <div style="display:flex;align-items:center;gap:8px;flex-wrap:wrap;">
          <b style="flex:1;min-width:160px;">${esc('Level ' + (i + 1) + ' \u2014 '
            + network + ' ' + lv.name)}</b>
          <span class="badge badge--pipeline">${esc(lv.code)}</span>
          <span class="badge badge--active">${esc(lv.freq)}</span>
        </div>
        <div class="muted" style="font-size:12px;margin-top:4px;">
          ${esc(t('me.conveningSchedule'))}: ${esc(lv.months)}</div>
        <div class="muted" style="font-size:12px;margin-top:2px;">
          ${esc(t('me.conveningWho'))}: ${esc(lv.who)}</div>
        <div style="font-size:13px;margin-top:6px;">${esc(lv.purpose)}</div>`;
      sec.append(card);
    });
    return sec;
  }

  /** My Team \u2014 established leaders see their own colleagues (e.g. a
   *  Country Lead sees her Deputy) and can message them directly. This is
   *  a deliberate, narrow exception to the member\u2192HQ-only wall: it only
   *  ever shows people who share one of MY OWN leadership seats. */
  async function teamCard() {
    const mates = await myTeam();
    if (!mates || !mates.length) return el('div', { style: 'display:none;' });
    const { rows: allMine, myId } = await listStaffMessages()
      .catch(() => ({ rows: [], myId: profile.id }));

    const sec = el('div', { class: 'mob-sec' }, [
      el('div', { class: 'mob-sec__h', text: t('me.myTeam') }),
    ]);
    const list = el('div', { class: 'card' });
    sec.append(list);

    mates.forEach((mate, idx) => {
      const row = el('div', { style:
        'display:flex;align-items:center;gap:10px;padding:8px 0;'
        + (idx > 0 ? 'border-top:1px solid var(--line);' : '') });
      row.innerHTML = `<div style="flex:1;min-width:0;">
        <b>${esc(mate.name)}</b>
        <span style="color:#7CB518;font-weight:900;">\u2713</span><br>
        <span class="muted" style="font-size:12px;">${esc(mate.role_applied || '')}</span>
      </div>`;
      const toggle = el('button', { class: 'btn btn--secondary',
        text: t('me.message') });
      row.append(toggle);
      const thread = el('div', { hidden: true, style: 'margin-top:8px;' });
      list.append(row, thread);

      toggle.addEventListener('click', () => {
        if (!thread.hidden) { thread.hidden = true; return; }
        thread.hidden = false;
        if (thread.childNodes.length) return;   // already built once
        const log = el('div', { style: 'display:flex;flex-direction:column;'
          + 'gap:6px;max-height:36vh;overflow:auto;padding:6px 0;' });
        const mine = (allMine || [])
          .filter((m) => (m.sender_id === mate.id && m.recipient_id === myId)
            || (m.sender_id === myId && m.recipient_id === mate.id))
          .slice().reverse();
        const bubble = (m) => el('div', { style:
          'max-width:82%;padding:8px 12px;border-radius:14px;font-size:14px;'
          + 'white-space:pre-wrap;word-break:break-word;'
          + (m.sender_id === myId
            ? 'align-self:flex-end;background:var(--brand,#D4006A);color:#fff;'
            : 'align-self:flex-start;background:rgba(124,181,24,.14);') },
          [el('div', { text: m.body || '' }),
           el('div', { class: 'muted', style: 'font-size:10px;margin-top:2px;'
             + (m.sender_id === myId ? 'color:rgba(255,255,255,.75);' : ''),
             text: fmtDate(m.created_at) })]);
        if (mine.length) mine.forEach((m) => log.append(bubble(m)));
        else log.append(el('p', { class: 'muted',
          style: 'font-size:13px;', text: t('me.teamNoMsgs') }));
        const input = el('textarea', { class: 'input grow', rows: '2',
          placeholder: t('me.writeToTeammate', { name: mate.name }) });
        const send = el('button', { class: 'btn btn--primary',
          text: t('me.send') });
        send.addEventListener('click', async () => {
          const body = input.value.trim();
          if (!body) return;
          send.disabled = true;
          try {
            await sendStaffMessage(mate.id, body);
            log.append(bubble({ body, sender_id: myId,
              created_at: new Date().toISOString() }));
            input.value = '';
            log.scrollTop = log.scrollHeight;
          } catch (err) { toastError(err?.message || t('errors.save')); }
          send.disabled = false;
        });
        thread.append(log, el('div', {
          class: 'row mt-2', style: 'gap:8px;align-items:flex-end;' },
          [input, send]));
        setTimeout(() => { log.scrollTop = log.scrollHeight; }, 0);
      });
    });
    return sec;
  }

  /** My Region — everyone at or below any seat I hold, country down
   *  through state, LGA and chapter. Filled seats show who's there and
   *  can be messaged (via the same hierarchy exception in the wall as
   *  My Team); vacant seats are shown honestly, exactly as vacant. */
  async function regionCard() {
    const nodes = await mySubtree();
    if (!nodes || !nodes.length) return el('div', { style: 'display:none;' });
    const { rows: allMine, myId } = await listStaffMessages()
      .catch(() => ({ rows: [], myId: profile.id }));

    const LEVEL_LABEL = {
      country: t('me.lvlCountry'), state_region: t('me.lvlState'),
      district_lga: t('me.lvlLga'), chapter: t('me.lvlChapter'),
    };
    const sec = el('div', { class: 'mob-sec' }, [
      el('div', { class: 'mob-sec__h', text: t('me.myRegion') }),
    ]);
    const list = el('div', { class: 'card' });
    sec.append(list);

    nodes.forEach((n, idx) => {
      const row = el('div', { style:
        'display:flex;align-items:center;gap:10px;padding:8px 0;'
        + (idx > 0 ? 'border-top:1px solid var(--line);' : '') });
      const who = el('div', { style: 'flex:1;min-width:0;' });
      who.innerHTML = `<span class="muted" style="font-size:11px;">${esc(
        LEVEL_LABEL[n.level] || n.level)} \u00b7 ${esc(n.location)}</span><br>`
        + (n.vacant
          ? `<span class="muted" style="font-style:italic;">${esc(t('me.vacant'))}</span>`
          : `<b>${esc(n.holder_name)}</b>
             <span style="color:#7CB518;font-weight:900;">\u2713</span>`);
      row.append(who);
      if (!n.vacant && n.holder_id) {
        const toggle = el('button', { class: 'btn btn--secondary',
          text: t('me.message') });
        row.append(toggle);
        const thread = el('div', { hidden: true, style: 'margin-top:8px;' });
        list.append(row, thread);
        toggle.addEventListener('click', () => {
          if (!thread.hidden) { thread.hidden = true; return; }
          thread.hidden = false;
          if (thread.childNodes.length) return;
          const log = el('div', { style: 'display:flex;flex-direction:column;'
            + 'gap:6px;max-height:36vh;overflow:auto;padding:6px 0;' });
          const mine = (allMine || [])
            .filter((m) => (m.sender_id === n.holder_id && m.recipient_id === myId)
              || (m.sender_id === myId && m.recipient_id === n.holder_id))
            .slice().reverse();
          const bubble = (m) => el('div', { style:
            'max-width:82%;padding:8px 12px;border-radius:14px;font-size:14px;'
            + 'white-space:pre-wrap;word-break:break-word;'
            + (m.sender_id === myId
              ? 'align-self:flex-end;background:var(--brand,#D4006A);color:#fff;'
              : 'align-self:flex-start;background:rgba(124,181,24,.14);') },
            [el('div', { text: m.body || '' }),
             el('div', { class: 'muted', style: 'font-size:10px;margin-top:2px;'
               + (m.sender_id === myId ? 'color:rgba(255,255,255,.75);' : ''),
               text: fmtDate(m.created_at) })]);
          if (mine.length) mine.forEach((m) => log.append(bubble(m)));
          else log.append(el('p', { class: 'muted',
            style: 'font-size:13px;', text: t('me.teamNoMsgs') }));
          const input = el('textarea', { class: 'input grow', rows: '2',
            placeholder: t('me.writeToTeammate', { name: n.holder_name }) });
          const send = el('button', { class: 'btn btn--primary',
            text: t('me.send') });
          send.addEventListener('click', async () => {
            const body = input.value.trim();
            if (!body) return;
            send.disabled = true;
            try {
              await sendStaffMessage(n.holder_id, body);
              log.append(bubble({ body, sender_id: myId,
                created_at: new Date().toISOString() }));
              input.value = '';
              log.scrollTop = log.scrollHeight;
            } catch (err) { toastError(err?.message || t('errors.save')); }
            send.disabled = false;
          });
          thread.append(log, el('div', {
            class: 'row mt-2', style: 'gap:8px;align-items:flex-end;' },
            [input, send]));
          setTimeout(() => { log.scrollTop = log.scrollHeight; }, 0);
        });
      } else {
        list.append(row);
      }
    });
    return sec;
  }

  async function hqThreadCard() {
    const { rows, myId } = await listStaffMessages();
    const msgs = (rows || []).slice().reverse(); // oldest first
    const log = el('div', {
      style: 'display:flex;flex-direction:column;gap:6px;'
        + 'max-height:46vh;overflow:auto;padding:4px 0;' });
    const bubble = (m) => {
      const mine = m.sender_id === myId;
      return el('div', {
        style: 'max-width:82%;padding:8px 12px;border-radius:14px;'
          + 'font-size:14px;white-space:pre-wrap;word-break:break-word;'
          + (mine
            ? 'align-self:flex-end;background:var(--brand,#D4006A);color:#fff;'
            : 'align-self:flex-start;background:rgba(124,181,24,.14);'),
      }, [
        el('div', { text: m.body || '' }),
        attachEl(m),
        el('div', { class: 'muted',
          style: 'font-size:10px;margin-top:2px;'
            + (mine ? 'color:rgba(255,255,255,.75);' : ''),
          text: fmtDate(m.created_at) }),
      ]);
    };
    function attachEl(m) {
      if (!m.attachment_path) return null;
      const openIt = async (ev) => {
        ev.preventDefault();
        try {
          const { data, error } = await db().storage.from('staff-files')
            .createSignedUrl(m.attachment_path, 3600);
          if (error) throw error;
          window.open(data.signedUrl, '_blank', 'noopener');
        } catch { toastError(t('me.fileGone')); }
      };
      if (/\.(webm|ogg|mp3|m4a|wav)$/i.test(m.attachment_name || '')) {
        const wrap = el('span');
        const audio = el('audio', { controls: '', preload: 'metadata',
          style: 'display:block;margin-top:6px;max-width:210px;' });
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
        const fb = () => wrap.replaceChildren(el('a', { href: '#',
          style: 'display:block;margin-top:6px;text-decoration:underline;',
          text: `\u{1F3A4} ${m.attachment_name || 'voice note'}`,
          onclick: openIt }));
        audio.addEventListener('error', fb);
        db().storage.from('staff-files')
          .createSignedUrl(m.attachment_path, 3600)
          .then(({ data, error }) => {
            if (error) throw error;
            audio.src = data.signedUrl;
          }).catch(fb);
        wrap.append(audio);
        return wrap;
      }
      if (/\.(png|jpe?g|gif|webp)$/i.test(m.attachment_name || '')) {
        const img = el('img', { alt: m.attachment_name || '',
          style: 'display:block;max-width:200px;border-radius:8px;'
            + 'margin-top:6px;' });
        db().storage.from('staff-files')
          .createSignedUrl(m.attachment_path, 3600)
          .then(({ data, error }) => {
            if (error) throw error;
            img.src = data.signedUrl;
          }).catch(() => img.remove());
        return img;
      }
      return el('a', { href: '#',
        style: 'display:block;margin-top:6px;text-decoration:underline;',
        text: `\u{1F4CE} ${m.attachment_name || 'file'}`, onclick: openIt });
    }
    if (msgs.length) for (const m of msgs) log.append(bubble(m));
    else log.append(el('p', { class: 'muted', text: t('me.hqNoMsgs') }));

    // Everything sent to me and unread → read, now that it is on screen.
    for (const m of msgs) {
      if (m.recipient_id === myId && !m.read_at) {
        markMessageRead(m.id).catch(() => {});
      }
    }

    const input = el('textarea', { class: 'input', rows: '2',
      placeholder: t('me.hqReplyPh'), style: 'flex:1;' });
    const send = el('button', { class: 'btn btn--primary',
      text: t('me.hqSend') });
    send.addEventListener('click', async () => {
      const body = input.value.trim();
      if (!body) return;
      send.disabled = true;
      try {
        // Reply to whichever HQ person last wrote; otherwise the HQ inbox.
        const lastIn = [...msgs].reverse()
          .find((m) => m.sender_id !== myId);
        const to = lastIn ? lastIn.sender_id : await hqInboxTarget();
        if (!to) throw new Error(t('me.hqNoTarget'));
        await sendStaffMessage(to, body);
        input.value = '';
        const m2 = { sender_id: myId, recipient_id: to, body,
          created_at: new Date().toISOString() };
        msgs.push(m2);
        if (log.querySelector('p.muted')) clear(log);
        log.append(bubble(m2));
        log.scrollTop = log.scrollHeight;
        toast(t('me.hqSent'));
      } catch (err) {
        toastError(err?.message || t('errors.save'));
      }
      send.disabled = false;
    });

    // Live: new HQ messages land in the card the moment they arrive.
    try {
      const ch = db().channel(`me-hq-${myId}`)
        .on('postgres_changes',
          { event: 'INSERT', schema: 'public', table: 'staff_messages',
            filter: `recipient_id=eq.${myId}` },
          ({ new: m }) => {
            if (!m) return;
            msgs.push(m);
            if (log.querySelector('p.muted')) clear(log);
            log.append(bubble(m));
            log.scrollTop = log.scrollHeight;
            markMessageRead(m.id).catch(() => {});
          })
        .subscribe();
      state.hqChannel = ch;
    } catch { /* realtime optional */ }

    const sec = el('div', { class: 'mob-sec', id: 'me-hq-msgs' }, [
      el('div', { class: 'mob-sec__h' }, [
        el('span', { text: t('me.hqThreadTitle') }),
        el('span', { class: 'vtick', title: t('msgs.verified'),
          text: '\u2713' }),
      ]),
      el('div', { class: 'card' }, [
        log,
        el('div', { class: 'row mt-2', style: 'gap:8px;align-items:flex-end;' },
          [input, send]),
      ]),
    ]);
    setTimeout(() => { log.scrollTop = log.scrollHeight; }, 0);
    return sec;
  }

  /* ===================================================================== */
  /* HOME                                                                  */
  /* ===================================================================== */
  async function home() {
    const [day, roles] = await Promise.all([
      getMyDay().catch(() => null), getMyRoles().catch(() => []),
    ]);
    state.roles = roles;
    // Activation content is optional for established leaders (they have
    // no journey); a hiccup there must not blank the whole home tab.
    try { await ensureActivation(); }
    catch (err) { if (!established) throw err; console.warn('[me] activation skipped', err); }
    clear(shell.body);

    shell.body.append(hero(roles, established));
    if (established) {
      try { shell.body.append(await teamCard()); } catch { /* no team yet */ }
      try { shell.body.append(await regionCard()); } catch { /* no subtree */ }
      shell.body.append(conveningCard(profile.network || 'WGMN'));
    }
    // Back to the main dashboard
    shell.body.append(el('div', { class: 'mob-sec' }, [
      el('div', { class: 'card', style:
        'display:flex;align-items:center;gap:12px;' }, [
        el('div', { style: 'flex:1;', text: t('me.backDashTitle') }),
        el('a', { class: 'btn btn--secondary', href: '#/',
          style: 'flex:0 0 auto;', text: t('me.backDashBtn') }),
      ]),
    ]));


    shell.body.append(el('div', { class: 'row mt-2', style: 'gap:8px;' }, [
      el('button', { class: 'btn btn--secondary',
        style: 'flex:1;text-align:center;', text: t('me.messageHq'),
        onclick: () => {
          const c = document.getElementById('me-hq-msgs');
          if (c) {
            c.scrollIntoView({ behavior: 'smooth', block: 'start' });
            const ta = c.querySelector('textarea');
            if (ta) setTimeout(() => ta.focus(), 350);
          }
        } }),
      el('a', { href: '#/room', class: 'btn btn--primary',
        style: 'flex:1;text-align:center;', text: t('me.joinRoom') }),
    ]));

    // Messages with WODDI HQ — the member's own thread, right here on #/me.
    try { shell.body.append(await hqThreadCard()); }
    catch { /* messaging needs migration 067; the card is optional */ }

    /* For you — the personal notice feed (journey days, birthdays,
       weekly/monthly inspiration, nudges) */
    try {
      const notices = await getMyNotices(6);
      if (notices.length) {
        const sec = el('div', { class: 'mob-sec' }, [
          el('div', { class: 'mob-sec__h', text: t('me.forYou') }),
        ]);
        for (const nz of notices) sec.append(noticeCard(nz));
        shell.body.append(sec);
      }
    } catch { /* notices need migration 032; feed is optional */ }

    if (day) {
      shell.body.append(el('div', { class: 'mob-quick' }, [
        quick(t('me.qTasks'), day.myOpen, '#/tasks'),
        quick(t('me.qMeetings'), day.meetingsWeek, '#/meetings'),
      ]));
    }

    // Journey door — one clean call to action (details live in the tab)
    if (state.journey && !established) {
      shell.body.append(el('div', { class: 'mob-sec' }, [
        el('div', { class: 'card', style:
          'display:flex;align-items:center;gap:14px;' }, [
          el('div', { style: 'flex:1;min-width:0;' }, [
            el('div', { style: 'font-weight:700;',
              text: t('me.beginJourney') }),
            el('div', { class: 'muted', style: 'font-size:13px;',
              text: t('me.beginJourneyHint') }),
          ]),
          el('button', { class: 'btn btn--primary', style: 'flex:0 0 auto;',
            text: t('me.continue'), onclick: () => show('journey') }),
        ]),
      ]));
    }

    // This week's inspiration
    const wk = isoWeek();
    const insp = established
      ? await getEngagementFor('weekly', wk).catch(() => null) : null;
    if (insp) {
      shell.body.append(el('div', { class: 'mob-sec' }, [
        el('div', { class: 'mob-sec__h', text: t('me.thisWeek') }),
        el('div', { class: 'learn-card learn-card--week' }, [
          el('small', { text: t('me.week', { n: wk }) }),
          el('h3', { text: insp.title }),
          insp.focus ? el('p', { text: insp.focus }) : null,
        ]),
      ]));
    }
  }

  function hero(roles, established) {
    const ava = el('img', {
      class: 'mob-hero__ava', alt: '', loading: 'lazy',
      src: avatarUrl(profile.id, Date.now()),
      onerror: (e) => {
        const initials = ((profile.first_name || '?')[0] +
          (profile.last_name || '')[0]).toUpperCase();
        e.target.replaceWith(el('div', { class: 'mob-hero__ava', text: initials }));
      },
    });
    const seat = roles && roles[0];
    const roleLabel = (established && profile.role_applied)
      || (seat ? t(`role.${seat.role}`) : null);
    // established leaders show WHERE they lead; everyone else shows network
    const subRight = established
      ? (seat?.org_unit?.name || profile.country)
      : profile.network;
    return el('div', { class: 'mob-hero' }, [
      ava,
      el('div', { style: 'flex:1;min-width:0;' }, [
        el('div', { class: 'mob-hero__name',
          style: 'display:flex;align-items:center;gap:6px;' }, [
          el('span', { text: `${profile.first_name} ${profile.last_name}` }),
          established ? el('span', { title: t('me.verifiedLeader'),
            style: 'color:#7CB518;font-size:15px;font-weight:900;',
            text: '\u2713' }) : null,
        ]),
        el('div', { class: 'mob-hero__sub',
          text: [roleLabel, subRight].filter(Boolean).join(' · ') || t('me.volunteer') }),
        el('span', { class: 'badge', style: 'margin-top:6px;display:inline-block;',
          text: t(`status.${profile.status}`) }),
      ]),
    ]);
  }

  function quick(label, value, href) {
    return el('a', { href }, [
      el('div', { class: 'q' }, [
        el('b', { text: fmtNumber(value ?? 0) }),
        el('span', { text: label }),
      ]),
    ]);
  }

  /* ===================================================================== */
  /* JOURNEY                                                               */
  /* ===================================================================== */
  async function journey() {
    if (established) { show('home'); return; }
    await ensureActivation();
    try { state.signals = await journeySignals(); }
    catch { state.signals = state.signals || {}; }
    state.roJourney = !!(state.journey
      && state.journey.status !== 'in_progress');
    clear(shell.body);
    const pb = progBanner();
    if (pb) shell.body.append(pb);

    if (!state.journey) {
      shell.body.append(el('div', { class: 'card state' }, [
        icon('check', 34),
        el('h3', { text: t('me.noJourneyTitle') }),
        el('p', { class: 'muted', text: t('me.noJourneyHint') }),
      ]));
      return;
    }
    if (state.day) { await dayDetail(state.day); return; }
    if (state.roJourney) {
      shell.body.append(el('div', { class: 'card', style:
        'background:rgba(124,181,24,.12);border:1px solid #7CB518;'
        + 'margin-bottom:12px;' }, [
        el('b', { text: state.journey.status === 'completed'
          ? t('me.journeyDoneBanner') : t('me.journeyClosedBanner') }),
        el('p', { class: 'muted', style: 'margin:4px 0 0;font-size:13px;',
          text: t('me.journeyRoHint') }),
      ]));
    }
    const backDash = () => el('div', { class: 'mob-sec' }, [
      el('div', { class: 'mob-sec__h', text: t('me.goBackDash') }),
      el('div', { class: 'card', style:
        'display:flex;align-items:center;gap:12px;' }, [
        el('div', { style: 'flex:1;', class: 'muted',
          text: t('me.goBackDashHint') }),
        el('button', { class: 'btn btn--secondary',
          style: 'flex:0 0 auto;', text: t('me.backDashBtn'),
          onclick: () => show('home') }),
      ]),
    ]);
    state.backDash = backDash;

    const rmap = respMap();
    const doneCount = state.days.filter((d) => dayDone(d.day, rmap)).length;
    const pct = Math.round((doneCount / 14) * 100);
    const deadline = state.journey.extended_until ?? state.journey.due_at;
    const daysLeft = Math.ceil((new Date(deadline) - Date.now()) / 86400000);

    shell.body.append(el('div', { class: 'card',
      style: 'display:flex;align-items:center;gap:16px;' }, [
      ring(pct, `${pct}%`),
      el('div', { style: 'flex:1;' }, [
        el('div', { style: 'font-weight:800;font-size:18px;', text: t('journey.title') }),
        el('div', { class: 'muted', style: 'font-size:13px;',
          text: state.journey.status === 'in_progress'
            ? (daysLeft >= 0
                ? t('journey.daysLeft', { n: fmtNumber(daysLeft) })
                : t('journey.overdue', { n: fmtNumber(-daysLeft) }))
            : t(`journey.${state.journey.status}`) }),
      ]),
    ]));

    // Founder's extension: a journey extended into the future has every
    // day open — no gating, finish at your own pace before the deadline.
    const allOpen = state.journey.extended_until
      && new Date(state.journey.extended_until) > Date.now();
    if (allOpen) {
      shell.body.append(el('div', {
        class: 'card', style: 'background:#F3F9EA;border:1px solid #7CB518;'
          + 'padding:10px 14px;margin-bottom:10px;font-weight:700;',
        text: t('journey.extendedNote', {
          date: fmtDate(state.journey.extended_until) }) }));
    }
    const openTo = currentDayNo();
    for (const d of state.days) {
      const done = dayDone(d.day, rmap);
      const locked = !allOpen
        && state.journey.status === 'in_progress' && d.day > openTo && !done;
      const cls = 'day-row' + (done ? ' day-row--done' : d.is_gate ? ' day-row--gate' : '');
      const opensOn = new Date(new Date(state.journey.started_at).getTime()
        + (d.day - 1) * 86400000);
      shell.body.append(el('button', {
        class: cls, disabled: locked || null,
        onclick: () => { state.day = d.day; journey(); },
      }, [
        el('div', { class: 'day-row__n',
          text: done ? '\u2713' : String(d.day) }),
        el('div', { class: 'day-row__t' }, [
          el('b', { text: `${t('me.day')} ${d.day} — ${d.title}` }),
          el('span', { text: d.is_gate ? t('me.checkpoint') : t(`me.kind.${d.kind}`) }),
        ]),
        el('div', { class: 'day-row__meta',
          text: done ? t('me.done')
            : locked ? t('me.opens', { d: fmtDate(opensOn.toISOString()) })
            : t('me.open') }),
      ]));
    }
    if (state.backDash) shell.body.append(state.backDash());
  }

  async function dayDetail(dayNo) {
    const d = state.days.find((x) => x.day === dayNo);
    clear(shell.body);
    shell.body.append(el('button', { class: 'btn btn--quiet',
      style: 'margin-bottom:12px;',
      text: `← ${t('me.backToDays')}`,
      onclick: () => { state.day = null; journey(); } }));
    const dayBackDash = () => el('div', { class: 'mob-sec',
      style: 'margin-top:14px;' }, [
      el('div', { class: 'mob-sec__h', text: t('me.goBackDash') }),
      el('div', { class: 'card', style:
        'display:flex;align-items:center;gap:12px;' }, [
        el('div', { style: 'flex:1;', class: 'muted',
          text: t('me.goBackDashHint') }),
        el('button', { class: 'btn btn--secondary',
          style: 'flex:0 0 auto;', text: t('me.backDashBtn'),
          onclick: () => { state.day = null; show('home'); } }),
      ]),
    ]);
    setTimeout(() => shell.body.append(dayBackDash()), 0);

    shell.body.append(el('div', { class: 'learn-card learn-card--month' }, [
      el('small', { text: `${t('me.day')} ${d.day}${d.is_gate ? ' · ' + t('me.checkpoint') : ''}` }),
      el('h3', { text: d.title }),
      d.intro ? el('p', { text: d.intro }) : null,
    ]));

    if (d.kind === 'evaluation') { await evaluation(); return; }

    const rmap = respMap();
    const items = state.items.filter((i) => i.day === dayNo);
    if (!items.length) {
      shell.body.append(el('p', { class: 'muted', text: t('me.noItems') }));
      return;
    }

    // ── guided mode: one task at a time
    const answeredFor = (i, r) =>
      !!r && (i.kind !== 'checklist' || r.is_correct === true);
    let step = items.findIndex((i) => !answeredFor(i, rmap.get(i.id)));
    if (step < 0) step = items.length;  // all answered → congratulations
    const stage = el('div');
    shell.body.append(stage);
    paintStep();

    function paintStep() {
      clear(stage);
      const fresh = respMap();
      if (step >= items.length) {
        stage.append(el('div', { class: 'card state' }, [
          el('h3', { text: t('me.dayDoneTitle', { n: dayNo }) }),
          el('p', { class: 'muted', text: t('me.dayDoneBody') }),
          el('button', { class: 'btn btn--primary mt-2',
            text: t('me.backToDays'),
            onclick: () => { state.day = null; journey(); } }),
        ]));
        toast(t('me.dayDoneToast', { n: dayNo }));
        return;
      }
      const it = items[step];
      stage.append(el('p', { class: 'muted',
        style: 'font-size:13px;margin-bottom:6px;',
        text: t('me.taskOf', { i: step + 1, n: items.length }) }));
      try {
        stage.append(itemCard(it, fresh.get(it.id)));
      } catch (err) {
        console.error('itemCard failed', err);
        stage.append(el('div', { class: 'card state' }, [
          el('p', { class: 'muted', text: t('errors.load') }),
          el('button', { class: 'btn btn--secondary',
            text: t('me.retry'), onclick: paintStep }),
        ]));
      }
      if (/profile|photo|passport/i.test(it.prompt)) {
        stage.append(el('button', { class: 'btn btn--secondary',
          style: 'width:100%;margin-top:6px;',
          text: t('me.goProfile'), onclick: () => show('profile') }));
      }
      const nextBtn = el('button', { class: 'btn btn--primary',
        style: 'flex:1;',
        text: step + 1 >= items.length ? t('me.finishDay') : t('me.next') });
      nextBtn.addEventListener('click', () => {
        if (!state.roJourney) {
          const now = respMap();
          const r = now.get(it.id);
          if (!r || (it.kind === 'checklist' && r.is_correct !== true)) {
            toastError(t('me.finishThisFirst')); return;
          }
        }
        step += 1;
        paintStep();
      });
      const navRow = el('div', { class: 'row',
        style: 'gap:8px;margin-top:10px;' });
      if (step > 0) {
        navRow.append(el('button', { class: 'btn btn--quiet',
          style: 'flex:0 0 auto;',
          text: '\u2190 ' + t('me.prevTask'),
          onclick: () => { step -= 1; paintStep(); } }));
      }
      navRow.append(nextBtn);
      stage.append(navRow);
    }
  }

  function itemCard(it, existing) {
    const card = el('div', { class: 'q-item' });
    const driveM = String(it.prompt).match(
      /https?:\/\/(?:drive|docs)\.[\w.]*google\w*\.com\/\S*?(?:id=|\/d\/)([\w-]{20,})\S*/);
    const videoM = String(it.prompt).match(/video:(\/\S+\.(?:mp4|webm))/);
    const shownPrompt = videoM
      ? it.prompt.replace(videoM[0], '').trim()
      : driveM ? it.prompt.replace(driveM[0], '').trim() : it.prompt;
    card.append(el('div', { class: 'q-item__p', text: shownPrompt }));
    const feedback = el('div', { class: 'q-feedback' });
    if (videoM) {
      const vid = el('video', {
        src: videoM[1], controls: '', playsinline: '',
        preload: 'metadata',
        controlslist: 'nodownload noplaybackrate',
        disablepictureinpicture: '',
        style: 'display:block;width:100%;border-radius:12px;margin:8px 0 4px;'
          + 'border:1px solid var(--line);background:#000;' });
      card.append(vid);
      // watched-progress bar + status line
      const barOuter = el('div', { style:
        'height:6px;border-radius:3px;background:var(--line);'
        + 'overflow:hidden;margin:0 0 6px;' });
      const barInner = el('div', { style:
        'height:100%;width:0%;background:var(--brand,#D4006A);'
        + 'transition:width .3s;' });
      barOuter.append(barInner);
      const st = el('p', { class: 'muted', style: 'font-size:12px;',
        text: existing ? '\u2713 ' + t('me.videoDone')
                       : t('me.videoAutoHint') });
      card.append(barOuter, st);
      if (existing) barInner.style.width = '100%';

      if (!existing && state.roJourney) {
        st.textContent = t('me.journeyRoHint');
      }
      if (!existing && !state.roJourney) {
        // ── the watch-guard ─────────────────────────────────────────────
        // The system, not the scrubber, decides "watched": we credit only
        // seconds that actually played, forbid seeking past the watched
        // frontier, lock playback to 1×, and tick at ≥95% genuinely seen.
        const key = `wdos.vid.${it.id}`;
        let savedW = { f: 0, w: [] };
        try { savedW = JSON.parse(localStorage.getItem(key)) || savedW; }
        catch { /* fresh start */ }
        const watched = new Set(savedW.w || []);
        let frontier = Number(savedW.f) || 0;
        let dur = 0; let done = false; let warnAt = 0;
        const need = () => Math.max(1, Math.ceil(dur * 0.95));
        const saveW = () => {
          try {
            localStorage.setItem(key,
              JSON.stringify({ f: frontier, w: [...watched] }));
          } catch { /* storage full: tracking continues in memory */ }
        };
        const paint = () => {
          if (!dur) return;
          const pct = Math.min(100, Math.round(watched.size * 100 / dur));
          barInner.style.width = pct + '%';
          if (!done) st.textContent = t('me.watchedPct', { p: pct });
        };
        let mark = null;
        const finish = async () => {
          if (done) return; done = true;
          try {
            await persist(true);
            barInner.style.width = '100%';
            st.style.color = '';
            st.textContent = '\u2713 ' + t('me.videoDone');
            toast(t('me.videoDone'));
            if (mark) mark.remove();
            try { localStorage.removeItem(key); } catch { /* fine */ }
          } catch (err) {
            done = false;
            console.error('video tick failed', err);
            const why = String(err?.message || err || '').slice(0, 160);
            st.style.color = '#dc2626';
            st.textContent = t('me.tickFailed', { why });
            // watching is verified — offer a visible retry they control
            if (!mark) {
              mark = el('button', { class: 'btn btn--secondary',
                style: 'width:100%;margin-top:6px;',
                text: t('me.markWatched') });
              mark.addEventListener('click', () => {
                mark.disabled = true;
                finish().finally(() => { mark.disabled = false; });
              });
              st.after(mark);
            }
          }
        };
        vid.addEventListener('loadedmetadata', () => {
          dur = Math.floor(vid.duration) || 0;
          if (frontier > 0 && frontier < dur) vid.currentTime = frontier;
          paint();
        });
        vid.addEventListener('timeupdate', () => {
          if (vid.seeking || !dur) return;
          watched.add(Math.floor(vid.currentTime));
          if (vid.currentTime > frontier) frontier = vid.currentTime;
          if (watched.size % 5 === 0) saveW();
          paint();
          if (watched.size >= need()) finish();
        });
        vid.addEventListener('seeking', () => {
          // rewinding to rewatch: always allowed; jumping ahead: never
          if (vid.currentTime > frontier + 2) {
            vid.currentTime = Math.max(0, frontier);
            const now = Date.now();
            if (now - warnAt > 4000) {
              warnAt = now;
              toastError(t('me.noSkip'));
            }
          }
        });
        vid.addEventListener('ratechange', () => {
          if (vid.playbackRate !== 1) vid.playbackRate = 1;
        });
        vid.addEventListener('ended', () => {
          saveW();
          if (dur && watched.size >= need()) finish();
        });
        vid.addEventListener('pause', saveW);
        vid.addEventListener('error', () => {
          // playback impossible on this device → honest manual fallback
          const fb = el('button', { class: 'btn btn--secondary',
            style: 'width:100%;', text: t('me.confirm') });
          fb.addEventListener('click', async () => {
            fb.disabled = true;
            try { await persist(true); fb.textContent = '\u2713 ' + t('me.confirmed'); }
            catch { fb.disabled = false; }
          });
          card.append(fb);
        });
      }
      card.append(feedback);
      return card;
    }
    if (it.kind === 'ack') {
      const L = String(it.prompt).toLowerCase();
      let ticks = [];
      try {
        ticks = JSON.parse(sessionStorage.getItem('wdos.ticks') || '[]');
      } catch { ticks = []; }
      const spec =
        (/profile/.test(L) && !/photo|passport/.test(L)) ? {
          ok: () => !!(profile.first_name && profile.last_name
            && profile.phone && profile.country && profile.state_region),
          text: t('me.goProfile2'),
          go: () => { state.fromJourney = true; show('profile'); } }
        : /photo|passport/.test(L) ? {
          ok: () => !!state.hasAvatar,
          text: t('me.goProfile2'),
          go: () => { state.fromJourney = true; show('profile'); } }
        : /verify.*email|email.*verif/.test(L) ? {
          ok: () => !!state.emailVerified,
          text: t('me.goProfile2'),
          go: () => { state.fromJourney = true; show('profile'); } }
        : /volunteer agreement/.test(L) ? {
          ok: () => ticks.includes('agreement'),
          text: t('me.openDocs'), go: () => inlineReader('agreement') }
        : /code of conduct/.test(L) ? {
          ok: () => ticks.includes('conduct'),
          text: t('me.openDocs'), go: () => inlineReader('coc') }
        : /handbook|manual/.test(L) ? {
          ok: () => ticks.includes('handbook')
            || !!(state.signals && state.signals.handbook),
          text: t('me.openDocs'), go: () => inlineReader('manual') }
        : null;
      if (spec) {
        const st = el('p', { class: 'muted',
          style: 'font-size:13px;margin:8px 0;' });
        card.append(st);
        const saveNow = () => persist(true).then(() => {
          st.style.color = '';
          st.textContent = '\u2713 ' + t('me.sysVerified');
        }).catch((err) => {
          st.style.color = '#dc2626';
          st.textContent = t('me.tickFailed',
            { why: String(err?.message || err || '').slice(0, 120) });
          const again = el('button', { class: 'btn btn--secondary',
            style: 'width:100%;margin-top:6px;',
            text: t('me.saveAgain') });
          again.addEventListener('click', () => {
            again.remove(); saveNow();
          });
          st.after(again);
        });
        if (existing) {
          st.textContent = '\u2713 ' + t('me.sysVerified');
        } else if (state.roJourney) {
          st.textContent = t('me.journeyRoHint');
        } else if (spec.ok()) {
          st.textContent = '\u2713 ' + t('me.sysVerified');
          saveNow();
        } else {
          st.textContent = t('me.sysWaiting');
          card.append(el('button', { class: 'btn btn--secondary',
            style: 'width:100%;', text: spec.text, onclick: spec.go }));
        }
        card.append(feedback);
        return card;
      }
    }
    if (driveM) {
      const holder = el('div', { style:
        'position:relative;width:100%;aspect-ratio:16/9;margin:8px 0;'
        + 'border-radius:12px;overflow:hidden;border:1px solid var(--line);' });
      holder.append(el('iframe', {
        src: `https://drive.google.com/file/d/${driveM[1]}/preview`,
        allow: 'autoplay; fullscreen',
        style: 'position:absolute;inset:0;width:100%;height:100%;border:0;',
        title: shownPrompt }));
      card.append(holder);
    }

    async function persist(answer) {
      const res = await submitActivationItem(state.journey.id, it.id, answer);
      // keep local cache in sync so day-done recomputes
      const r = { item_id: it.id, answer, is_correct: res.is_correct,
        score: res.score, submitted_at: new Date().toISOString() };
      const idx = (state.responses || []).findIndex((x) => x.item_id === it.id);
      if (idx >= 0) state.responses[idx] = r;
      else (state.responses = state.responses || []).push(r);
      return res;
    }

    if (it.kind === 'mcq' || it.kind === 'tf') {
      const opts = it.options.map((label) => {
        const key = it.kind === 'tf' ? label : label.split('.')[0].trim();
        const b = el('button', { class: 'opt', 'data-key': key }, [
          el('span', { class: 'opt__box' }), el('span', { text: label }),
        ]);
        b.addEventListener('click', () => choose(key));
        return b;
      });
      opts.forEach((o) => card.append(o));
      card.append(feedback);

      if (existing) lock(existing.answer, existing.is_correct, null);

      async function choose(key) {
        opts.forEach((o) => (o.disabled = true));
        try {
          const res = await persist(key);
          lock(key, res.is_correct, res.reveal);
        } catch (err) {
          opts.forEach((o) => (o.disabled = false));
          toastError(err?.message || t('errors.save'));
        }
      }
      function lock(chosen, correct, reveal) {
        opts.forEach((o) => {
          o.disabled = true;
          const k = o.getAttribute('data-key');
          if (reveal != null && k === reveal) o.classList.add('opt--correct');
          if (k === chosen) {
            o.setAttribute('aria-pressed', 'true');
            o.classList.add(correct ? 'opt--correct' : 'opt--wrong');
          }
        });
        feedback.className = 'q-feedback ' + (correct ? 'q-feedback--ok' : 'q-feedback--no');
        feedback.textContent = correct ? t('me.correct') : t('me.incorrect');
      }
    }

    else if (it.kind === 'checklist') {
      const chosen = new Set(existing && Array.isArray(existing.answer)
        ? existing.answer.map(Number) : []);
      let readerTicks = [];
      try {
        readerTicks = JSON.parse(sessionStorage.getItem('wdos.ticks') || '[]');
      } catch { readerTicks = []; }
      const sig = state.signals || {};
      // auto-verify what the system can see for itself
      const autoDone = (label) => {
        const L = label.toLowerCase();
        if (/upload.*cv|cv.*upload/.test(L)) return sig.cv || null;
        if (/course module|learn section/.test(L)) return sig.module || null;
        if (/message to the hq|write .*hq/.test(L)) return sig.msg_hq || null;
        if (/announcement/.test(L)) return sig.announcement || null;
        if (/handbook|manual/.test(L)) {
          if (sig.handbook) return true;
        }
        if (/dashboard.*tasks|tasks.*available/.test(L)) {
          return sig.tasks || null;
        }
        if (/ask woddi/.test(L)) return sig.ask || null;
        if (/profile/.test(L) && !/photo|passport/.test(L)) {
          return !!(profile.first_name && profile.last_name && profile.phone
            && profile.country && profile.state_region);
        }
        if (/verify.*email|email.*verif/.test(L)) {
          return !!state.emailVerified;
        }
        if (/photo|passport/.test(L)) {
          return state.hasAvatar ? true : null;
        }
        return null;  // not auto-detectable
      };
      const doorFor = (label) => {
        const L = label.toLowerCase();
        if (/profile|photo|passport/.test(L)) {
          return { text: t('me.goProfile2'),
            go: () => { state.fromJourney = true; show('profile'); } };
        }
        if (/conduct/.test(L)) {
          return { text: t('me.openDocs'),
            go: () => inlineReader('coc') };
        }
        if (/handbook|manual/.test(L)) {
          return { text: t('me.pdfDownload'),
            go: () => {
              logJourneyEvent('handbook_downloaded');
              window.open('/content/leadership-manual.pdf',
                '_blank', 'noopener');
            } };
        }
        if (/agreement/.test(L)) {
          return { text: t('me.openDocs'),
            go: () => inlineReader('agreement') };
        }
        if (/upload.*cv|cv.*upload/.test(L)) {
          return { text: t('me.uploadCv'), go: () => cvPicker() };
        }
        if (/course module|learn section/.test(L)) {
          return { text: t('me.goLearn'), go: () => show('learn') };
        }
        if (/message to the hq|write .*hq/.test(L)) {
          return { text: t('me.goMsgHq'), go: () => {
            show('home');
            setTimeout(() => {
              const c = document.getElementById('me-hq-msgs');
              if (c) c.scrollIntoView({ behavior: 'smooth' });
            }, 400);
          } };
        }
        if (/announcement/.test(L)) {
          return { text: t('me.goOpen'),
            go: () => { location.hash = '#/announcements'; } };
        }
        if (/dashboard.*tasks|tasks.*available/.test(L)) {
          return { text: t('me.goOpen'),
            go: () => { location.hash = '#/tasks'; } };
        }
        if (/ask woddi/.test(L)) {
          return { text: t('me.goOpen'),
            go: () => { location.hash = '#/ask'; } };
        }
        return null;
      };
      function cvPicker() {
        const fi = el('input', { type: 'file', hidden: true,
          accept: '.pdf,.doc,.docx,.png,.jpg,.jpeg' });
        document.body.append(fi);
        fi.addEventListener('change', async () => {
          const f = fi.files[0]; fi.remove();
          if (!f) return;
          toast(t('me.cvUploading'));
          try {
            await uploadMemberCv(f);
            state.signals = { ...(state.signals || {}), cv: true };
            toast(t('me.cvUploaded'));
            show('journey');            // repaint: the row ticks itself
          } catch (err) {
            toastError(err?.message || t('me.cvErr'));
          }
        });
        fi.click();
      }
      const opts = it.options.map((label, i) => {
        const auto = autoDone(label);
        if (auto === true) chosen.add(i);
        const LL = label.toLowerCase();
        if ((readerTicks.includes('conduct') && /conduct/.test(LL))
            || (readerTicks.includes('handbook') && /handbook|manual/.test(LL))
            || (readerTicks.includes('agreement') && /agreement/.test(LL))) {
          chosen.add(i);
        }
        const b = el('button', { class: 'opt',
          'aria-pressed': String(chosen.has(i)) }, [
          el('span', { class: 'opt__box', text: chosen.has(i) ? '\u2713' : '' }),
          el('span', { style: 'flex:1;text-align:left;', text: label }),
        ]);
        const door = doorFor(label);
        if (door) {
          b.append(el('span', { class: 'badge badge--pipeline',
            style: 'flex:none;cursor:pointer;', text: door.text,
            onclick: (ev) => { ev.stopPropagation(); door.go(); } }));
        }
        if (auto === true) {
          b.append(el('span', { class: 'muted',
            style: 'font-size:11px;flex:none;', text: t('me.autoDone') }));
        }
        const sysRow = /upload.*cv|cv.*upload|course module|learn section|message to the hq|write .*hq|announcement|dashboard.*tasks|tasks.*available|ask woddi/
          .test(label.toLowerCase());
        b.addEventListener('click', () => {
          if (auto === true) return;  // verified rows stay done
          if (sysRow) {               // the SYSTEM ticks these, not the hand
            toastError(t('me.systemTicks'));
            return;
          }
          if (chosen.has(i)) { chosen.delete(i); }
          else { chosen.add(i); }
          b.setAttribute('aria-pressed', String(chosen.has(i)));
          b.querySelector('.opt__box').textContent = chosen.has(i) ? '\u2713' : '';
        });
        return b;
      });
      opts.forEach((o) => card.append(o));
      // Persist silently whenever verification is ahead of the saved answer.
      const savedCount = existing && Array.isArray(existing.answer)
        ? existing.answer.length : 0;
      if (chosen.size > savedCount && !state.roJourney) {
        persist([...chosen].map(String)).catch(() => {});
      }
      const btn = el('button', { class: 'btn btn--secondary',
        style: 'width:100%;margin-top:6px;', text: t('me.submit') });
      btn.addEventListener('click', async () => {
        if (chosen.size < it.options.length) { toastError(t('me.tickAll')); return; }
        btn.disabled = true;
        try {
          await persist([...chosen].map(String));
          feedback.className = 'q-feedback q-feedback--ok';
          feedback.textContent = t('me.saved');
          toast(t('me.saved'));
        } catch (err) {
          btn.disabled = false;
          toastError(err?.message || t('errors.save'));
        }
      });
      card.append(btn, feedback);
      if (existing && chosen.size >= it.options.length) {
        feedback.className = 'q-feedback q-feedback--ok';
        feedback.textContent = t('me.done');
      }
    }

    else if (it.kind === 'written') {
      const ta = el('textarea', { placeholder: t('me.writeHere'),
        value: existing ? existing.answer : '' });
      const btn = el('button', { class: 'btn btn--secondary',
        style: 'width:100%;margin-top:8px;',
        text: existing ? t('me.update') : t('me.save') });
      btn.addEventListener('click', async () => {
        const v = ta.value.trim();
        if (v.length < 2) { toastError(t('me.writeSomething')); return; }
        btn.disabled = true;
        try {
          await persist(v);
          btn.textContent = t('me.update');
          feedback.className = 'q-feedback q-feedback--ok';
          feedback.textContent = t('me.submitted');
          toast(t('me.saved'));
        } catch (err) { toastError(err?.message || t('errors.save')); }
        finally { btn.disabled = false; }
      });
      card.append(ta, btn, feedback);
      if (existing) {
        feedback.className = 'q-feedback q-feedback--ok';
        feedback.textContent = t('me.submitted');
      }
    }

    else { // ack
      const btn = el('button', { class: 'btn btn--secondary',
        style: 'width:100%;', text: existing ? '\u2713 ' + t('me.confirmed') : t('me.confirm') });
      btn.disabled = !!existing;
      btn.addEventListener('click', async () => {
        btn.disabled = true;
        try {
          await persist(true);
          btn.textContent = '\u2713 ' + t('me.confirmed');
          toast(t('me.saved'));
        } catch (err) {
          btn.disabled = false;
          toastError(err?.message || t('errors.save'));
        }
      });
      card.append(btn);
    }
    return card;
  }

  async function evaluation() {
    const wrap = el('div', { class: 'card' });
    wrap.append(el('div', { class: 'state' }, [el('div', { class: 'spinner' })]));
    shell.body.append(wrap);
    let s;
    try { s = await getActivationSummary(state.journey.id); }
    catch { wrap.replaceChildren(el('p', { class: 'muted', text: t('errors.load') })); return; }

    const recCls = s.recommendation === 'advance' ? 'active'
      : s.recommendation === 'mentoring' ? 'pipeline' : 'exited';
    clear(wrap);
    wrap.append(
      el('div', { style: 'display:flex;align-items:center;gap:16px;' }, [
        ring(s.percent, `${s.percent}%`),
        el('div', [
          el('div', { style: 'font-weight:800;font-size:18px;', text: t('me.yourScore') }),
          el('div', { class: 'muted', style: 'font-size:13px;',
            text: t('me.scoreDetail', { earned: s.earned, possible: s.possible }) }),
        ]),
      ]),
      el('p', { style: 'margin-top:12px;',
        text: t('me.writtenDetail', { done: s.written_done, total: s.written_total }) }),
      el('div', { class: 'row', style: 'margin-top:10px;gap:8px;flex-wrap:wrap;' }, [
        el('span', { class: `badge badge--${s.gate6 ? 'active' : 'exited'}`,
          text: (s.gate6 ? '\u2713 ' : '\u2717 ') + t('me.gateSafeguarding') }),
        el('span', { class: `badge badge--${s.gate13 ? 'active' : 'exited'}`,
          text: (s.gate13 ? '\u2713 ' : '\u2717 ') + t('me.gateCommitment') }),
      ]),
      el('div', { class: 'mob-sec', style: 'margin-top:16px;' }, [
        el('div', { class: 'mob-sec__h', text: t('me.recommendation') }),
        el('span', { class: `badge badge--${recCls}`,
          style: 'font-size:14px;padding:6px 12px;',
          text: t(`me.rec.${s.recommendation}`) }),
        el('p', { class: 'muted', style: 'margin-top:8px;font-size:13px;',
          text: t('me.recHint') }),
      ]),
    );
  }

  /* ===================================================================== */
  /* LEARN                                                                 */
  /* ===================================================================== */
  async function learn() {
    const wk = isoWeek();
    clear(shell.body);
    const pb = progBanner();
    if (pb) shell.body.append(pb);
    // Courses first — the heart of Learn
    const coursesSec = el('div', { class: 'mob-sec', style: 'margin-top:0;' }, [
      el('div', { class: 'mob-sec__h', text: t('course.title') }),
    ]);
    const coursesBox = el('div');
    coursesSec.append(coursesBox);
    shell.body.append(coursesSec);
    renderCourses(coursesBox, profile, null).catch(() => {});
    const inspSec = el('div');
    shell.body.append(inspSec);
    await learnInspiration(inspSec, wk);
  }

  async function learnInspiration(target, wk) {
    const mo = new Date().getMonth() + 1;
    const [week, month, mclass, allClass] = await Promise.all([
      getEngagementFor('weekly', wk).catch(() => null),
      getEngagementFor('monthly', mo).catch(() => null),
      getEngagementFor('masterclass', mo).catch(() => null),
      listEngagement('masterclass').catch(() => []),
    ]);
    const shellBody = target;   // sections below render into the target box

    if (week) shellBody.append(el('div', { class: 'learn-card learn-card--week' }, [
      el('small', { text: t('me.week', { n: wk }) + ' · ' + t('me.inspiration') }),
      el('h3', { text: week.title }),
      week.focus ? el('p', { text: week.focus }) : null,
    ]));
    if (month) shellBody.append(el('div', { class: 'learn-card learn-card--month' }, [
      el('small', { text: t('me.thisMonth') + ' · ' + t('me.message') }),
      el('h3', { text: month.title }),
      month.focus ? el('p', { text: month.focus }) : null,
    ]));
    if (mclass) shellBody.append(el('div', { class: 'learn-card learn-card--class' }, [
      el('small', { text: t('me.thisMonth') + ' · ' + t('me.masterclass') }),
      el('h3', { text: mclass.title }),
      mclass.focus ? el('p', { text: mclass.focus }) : null,
    ]));

    if (allClass && allClass.length) {
      shellBody.append(el('div', { class: 'mob-sec' }, [
        el('div', { class: 'mob-sec__h', text: t('me.yearCurriculum') }),
        el('ul', { class: 'mob-list' }, allClass.map((c) =>
          el('li', [el('b', { text: monthShort(c.period) }),
            el('span', { text: c.title })]))),
      ]));
    }
  }

  /* ===================================================================== */
  /* PROFILE                                                               */
  /* ===================================================================== */
  async function profileTab() {
    clear(shell.body);
    if (state.fromJourney) {
      const stFile = el('input', { type: 'file', accept: 'image/*',
        capture: 'user', hidden: true });
      const preview = el('img', { alt: '', style:
        'width:96px;height:96px;border-radius:50%;object-fit:cover;'
        + 'border:3px solid var(--brand,#D4006A);background:#eee;' });
      preview.src = avatarUrl(profile.id, Date.now());
      preview.onerror = () => { preview.style.opacity = '.35'; };
      stFile.addEventListener('change', async () => {
        const f = stFile.files[0]; if (!f) return;
        try {
          await uploadAvatar(profile.id, f);
          state.hasAvatar = true;
          toast(t('me.photoSaved'));
          state.fromJourney = false;
          toast(t('me.backToTask'));
          show('journey');
        } catch (err) {
          toastError(err?.message || t('me.photoErr'));
        }
      });
      shell.body.append(el('div', { class: 'card mb-4', style:
        'display:flex;flex-direction:column;align-items:center;gap:12px;'
        + 'text-align:center;border:2px solid var(--brand,#D4006A);' }, [
        preview,
        el('strong', { text: t('me.passportTitle') }),
        el('p', { class: 'muted', style: 'font-size:13px;margin:0;',
          text: t('me.passportHint') }),
        el('button', { class: 'btn btn--primary', style: 'width:100%;',
          text: t('me.passportBtn'), onclick: () => stFile.click() }),
        el('button', { class: 'btn btn--quiet', style: 'width:100%;',
          text: t('me.backNoPhoto'),
          onclick: () => { state.fromJourney = false; show('journey'); } }),
        stFile,
      ]));
    }
    // ── Complete your profile — the card the Day-1 task verifies against
    {
      const f = (val) => el('input', { class: 'input', value: val || '' });
      const inFirst = f(profile.first_name);
      const inLast = f(profile.last_name);
      const inPhone = f(profile.phone);
      const inCountry = el('select', { class: 'select' },
        [el('option', { value: '', text: t('me.countryPick') }),
         ...AFRICAN_COUNTRIES.map((c) => el('option', { value: c, text: c,
           selected: profile.country === c || null }))]);
      const stateWrap = el('div');
      let stateCtl;
      const buildState = () => {
        const isNG = inCountry.value === 'Nigeria';
        stateCtl = isNG
          ? el('select', { class: 'select' },
              [el('option', { value: '', text: t('me.statePick') }),
               ...NG_STATES.map((st) => el('option', { value: st, text: st,
                 selected: profile.state_region === st || null }))])
          : el('input', { class: 'input',
              value: profile.state_region || '' });
        stateWrap.replaceChildren(stateCtl);
      };
      inCountry.addEventListener('change', buildState);
      buildState();
      const inLga = f(profile.lga);
      const inNet = el('select', { class: 'select' },
        ['WGMN', 'WNNN'].map((n) => el('option', { value: n,
          text: n === 'WGMN' ? t('me.netWgmn') : t('me.netWnnn'),
          selected: (profile.network || 'WGMN') === n || null })));
      const ROLES = ['Country Representative', 'Deputy Country Representative',
        'Country Lead', 'Deputy Country Lead',
        'State/Regional Coordinator', 'Assistant State/Regional Coordinator',
        'LGA/District Coordinator', 'Assistant LGA/District Coordinator',
        'Chapter Lead', 'Assistant Chapter Lead',
        'Campus Ambassador', 'Professional Mentor', 'Volunteer'];
      const inRole = el('select', { class: 'select' },
        [el('option', { value: '', text: t('me.rolePick') }),
         ...ROLES.map((r) => el('option', { value: r, text: r,
           selected: profile.role_applied === r || null }))]);
      const saveBtn = el('button', { class: 'btn btn--primary',
        style: 'width:100%;margin-top:10px;', text: t('me.saveProfile') });
      saveBtn.addEventListener('click', async () => {
        saveBtn.disabled = true;
        saveBtn.textContent = t('me.saving');
        try {
          const patch = {
            first_name: inFirst.value.trim(),
            last_name: inLast.value.trim(),
            phone: inPhone.value.trim(),
            country: inCountry.value,
            state_region: (stateCtl?.value || '').trim(),
            network: inNet.value,
            lga: inLga.value.trim(),
            role_applied: inRole.value || null,
          };
          await updateMyProfile(patch);
          Object.assign(profile, patch);
          toast(t('me.profileSaved'));
          if (state.fromJourney) {
            state.fromJourney = false;
            show('journey');
            return;
          }
        } catch (err) {
          toastError(err?.message || t('errors.save'));
        }
        saveBtn.disabled = false;
        saveBtn.textContent = t('me.saveProfile');
      });
      const fld = (label, input) => el('div', { class: 'field' }, [
        el('label', { class: 'field__label', text: label }), input]);
      shell.body.append(el('div', { class: 'mob-sec' }, [
        el('div', { class: 'mob-sec__h', text: t('me.completeProfile') }),
        el('div', { class: 'card' }, [
          fld(t('me.fFirst'), inFirst), fld(t('me.fLast'), inLast),
          fld(t('me.fPhone'), inPhone), fld(t('me.fCountry'), inCountry),
          fld(t('me.fState'), stateWrap), fld(t('me.fLga'), inLga),
          fld(t('me.fNetwork'), inNet),
          fld(t('me.fRole'), inRole),
          saveBtn,
          el('button', { class: 'btn btn--quiet',
            style: 'width:100%;margin-top:6px;',
            text: t('bn.enableBtn'),
            onclick: async (e) => {
              const { enableBrowserNotifications } =
                await import('../core/notifybrowser.js');
              const st = await enableBrowserNotifications(profile);
              if (st === 'granted') {
                toast(t('bn.on'));
                try {
                  const { enablePush } = await import('../core/push.js');
                  const ps = await enablePush();
                  if (ps === 'on') toast(t('push.on'));
                } catch { toastError(t('push.err')); }
              } else if (st === 'denied') toastError(t('bn.denied'));
              else toastError(t('bn.unsupported'));
              e.target.blur();
            } }),
        ]),
      ]));
    }

    shell.body.append(hero(state.roles || []));

    // Avatar upload
    const file = el('input', { type: 'file', accept: 'image/*', hidden: true });
    file.addEventListener('change', async () => {
      const f = file.files[0]; if (!f) return;
      try {
        await uploadAvatar(profile.id, f);
        state.hasAvatar = true;
        toast(t('me.photoSaved'));
        if (state.fromJourney) {
          state.fromJourney = false;
          toast(t('me.backToTask'));
          show('journey');
        } else {
          show('profile');
        }
      } catch { toastError(t('me.photoErr')); }
    });
    shell.body.append(el('div', { class: 'mob-sec' }, [
      el('div', { class: 'mob-sec__h', text: t('me.photo') }),
      el('button', { class: 'btn btn--quiet', style: 'width:100%;',
        text: t('me.changePhoto'), onclick: () => file.click() }),
      file,
    ]));

    // Change password
    const pw1 = el('input', { class: 'input', type: 'password', autocomplete: 'new-password' });
    const pw2 = el('input', { class: 'input', type: 'password', autocomplete: 'new-password' });
    const err = el('p', { class: 'field__error', hidden: true });
    shell.body.append(el('div', { class: 'mob-sec' }, [
      el('div', { class: 'mob-sec__h', text: t('acct.title') }),
      el('div', { class: 'card' }, [
        el('div', { class: 'field' }, [
          el('label', { class: 'field__label', text: t('acct.newPw') }), pw1]),
        el('div', { class: 'field' }, [
          el('label', { class: 'field__label', text: t('acct.confirmPw') }), pw2]),
        err,
        el('button', { class: 'btn btn--secondary', style: 'width:100%;',
          text: t('acct.change'), onclick: async (e) => {
            if (pw1.value.length < 8) { err.textContent = t('acct.errShort'); err.hidden = false; return; }
            if (pw1.value !== pw2.value) { err.textContent = t('acct.errMatch'); err.hidden = false; return; }
            err.hidden = true; e.target.disabled = true;
            try { await changePassword(pw1.value); pw1.value = ''; pw2.value = ''; toast(t('acct.changed')); }
            catch { err.textContent = t('errors.save'); err.hidden = false; }
            finally { e.target.disabled = false; }
          } }),
      ]),
    ]));

    // Birthday (powers the automatic birthday wish)
    const bday = el('input', { class: 'input', type: 'date',
      value: profile.birth_date || '' });
    bday.addEventListener('change', async () => {
      try {
        await updateMyProfile({ birth_date: bday.value || null });
        profile.birth_date = bday.value || null;
        toast(t('me.birthdaySaved'));
      } catch { toastError(t('errors.save')); }
    });
    shell.body.append(el('div', { class: 'mob-sec' }, [
      el('div', { class: 'mob-sec__h', text: t('me.birthday') }),
      el('div', { class: 'card' }, [
        el('p', { class: 'muted', style: 'font-size:13px;margin-bottom:8px;',
          text: t('me.birthdayHint') }),
        bday,
      ]),
    ]));

    // Language
    const sel = el('select', { class: 'select',
      onchange: async (e) => {
        try {
          const code = e.target.value;
          await setLocale(code);
          try { await updateMyProfile({ preferred_locale: code }); }
          catch { /* account save best-effort */ }
          location.reload();
        } catch { toastError(t('errors.localeLoad')); }
      } },
      supportedLocales().map((c) => el('option', {
        value: c, selected: c === getLocale() || null, text: LOCALE_NAMES[c] })));
    shell.body.append(el('div', { class: 'mob-sec' }, [
      el('div', { class: 'mob-sec__h', text: t('app.language') }), sel,
    ]));
  }

  function noticeLabel(nz) {
    const known = ['journey_day', 'nudge', 'birthday', 'weekly', 'monthly'];
    return known.includes(nz.kind) ? t(`me.notice.${nz.kind}`) : t('me.notice.manual');
  }
  function noticeCard(nz) {
    const card = el('button', {
      class: 'notice' + (nz.read_at ? '' : ' notice--new'),
    });
    const body = el('div', { class: 'notice__body', hidden: true });
    if (nz.body) body.textContent = nz.body;
    card.append(
      el('div', { class: 'notice__head' }, [
        el('span', { class: 'notice__dot' }),
        el('div', { style: 'flex:1;min-width:0;' }, [
          el('span', { class: 'notice__kind', text: noticeLabel(nz) }),
          el('b', { text: nz.title }),
        ]),
        el('span', { class: 'notice__date', text: fmtDate(nz.created_at) }),
      ]),
      body,
    );
    card.addEventListener('click', async () => {
      if (nz.body) body.hidden = !body.hidden;
      if (!nz.read_at) {
        nz.read_at = new Date().toISOString();
        card.classList.remove('notice--new');
        try { await markNoticeRead(nz.id); } catch { /* best effort */ }
      }
    });
    return card;
  }

  /* ---- little helpers -------------------------------------------------- */
  function ring(pct, label) {
    return el('div', { class: 'ring', style: `--p:${Math.max(0, Math.min(100, pct))}` }, [
      el('div', { class: 'ring__in', text: label }),
    ]);
  }
  function monthShort(m) {
    return new Intl.DateTimeFormat(getLocale(), { month: 'short' })
      .format(new Date(2000, m - 1, 1));
  }
}

function spinner() {
  return el('div', { class: 'state' }, [el('div', { class: 'spinner' })]);
}
function errorState(retry, err) {
  // The reason is printed in plain sight: a support screenshot then tells
  // us exactly which call failed instead of "check your connection".
  const why = String(err?.message || err?.details || err?.code || err || '')
    .slice(0, 160);
  return el('div', { class: 'card state' }, [
    el('h3', { text: t('errors.loadTitle') }),
    el('p', { text: t('errors.loadHint') }),
    why ? el('p', { class: 'muted', style: 'font-size:12px;word-break:break-word;',
      text: why }) : null,
    el('button', { class: 'btn btn--quiet', text: t('app.retry'), onclick: retry }),
  ]);
}

/** ISO-8601 week number, clamped to the 1..52 library range. */
function isoWeek(d = new Date()) {
  const date = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
  const dayNum = (date.getUTCDay() + 6) % 7;
  date.setUTCDate(date.getUTCDate() - dayNum + 3);
  const firstThursday = new Date(Date.UTC(date.getUTCFullYear(), 0, 4));
  const week = 1 + Math.round(
    ((date - firstThursday) / 86400000 - 3 + ((firstThursday.getUTCDay() + 6) % 7)) / 7);
  return Math.min(52, Math.max(1, week));
}
