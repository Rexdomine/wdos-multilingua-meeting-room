/**
 * WDOS notification bell — Phase 34.
 * Live counts AND previews of the actual items (who messaged, which task,
 * which announcement), realtime via Supabase (RLS applies to the stream),
 * a code-generated chirp, and — new — browser system notifications when
 * the person is in another tab or window (permission asked in-panel,
 * never on page load).
 */
import { el, esc, personLabel } from '../core/dom.js';
import { t } from '../core/i18n.js';
import { db, getSession } from '../core/db.js';
import { toast } from './toast.js';

const PREVIEW_N = 4;
const state = {
  msgs: 0, tasks: 0, anns: 0, notices: 0,
  msgItems: [], taskItems: [], annItems: [], noticeItems: [],
  channel: null, userId: null, audio: null,
};

function total() { return state.msgs + state.tasks + state.anns + state.notices; }

/* ---------------- sound ---------------- */
function chirp() {
  try {
    state.audio = state.audio
      || new (window.AudioContext || window.webkitAudioContext)();
    const ctx = state.audio;
    if (ctx.state === 'suspended') ctx.resume().catch(() => {});
    const o = ctx.createOscillator();
    const g = ctx.createGain();
    o.type = 'sine';
    o.frequency.setValueAtTime(880, ctx.currentTime);
    o.frequency.exponentialRampToValueAtTime(1320, ctx.currentTime + 0.12);
    g.gain.setValueAtTime(0.08, ctx.currentTime);
    g.gain.exponentialRampToValueAtTime(0.0001, ctx.currentTime + 0.35);
    o.connect(g).connect(ctx.destination);
    o.start();
    o.stop(ctx.currentTime + 0.36);
  } catch { /* sound is a garnish, never an error */ }
}

/* ---------------- system notifications ---------------- */
const sysWanted = () => localStorage.getItem('wdos.sysnotify') === 'on';

function sysNotify(title, body, opts = {}) {
  // Only when the person is NOT looking at this tab — no double-noise.
  // opts.force (group calls) pops it even while the tab is visible.
  if (!sysWanted() || !('Notification' in window)) return;
  if (Notification.permission !== 'granted') return;
  if (!document.hidden && !opts.force) return;
  try {
    const n = new Notification(title, {
      body: body ? String(body).slice(0, 120) : undefined,
      icon: '/assets/favicon.svg', tag: 'wdos', renotify: false,
    });
    n.onclick = () => { window.focus(); n.close(); };
  } catch { /* never let a notification break the app */ }
}

/* ---------------- data ---------------- */
async function head(table, build) {
  let q = db().from(table).select('*', { count: 'exact', head: true });
  const { count, error } = await build(q);
  if (error) throw error;
  return count ?? 0;
}

async function refreshCounts() {
  const me = state.userId;
  const [msgs, tasks, annTotal, annRead, notices] = await Promise.all([
    head('staff_messages', (q) => q.eq('recipient_id', me).is('read_at', null))
      .catch(() => 0),
    head('tasks', (q) => q.eq('assigned_to', me).eq('status', 'not_started'))
      .catch(() => 0),
    head('announcements', (q) => q).catch(() => 0),
    head('announcement_reads', (q) => q.eq('profile_id', me)).catch(() => 0),
    head('member_notices', (q) => q.eq('profile_id', me).is('read_at', null))
      .catch(() => 0),
  ]);
  state.notices = notices;
  state.msgs = msgs;
  state.tasks = tasks;
  state.anns = Math.max(0, annTotal - annRead);
}

async function refreshPreviews() {
  const me = state.userId;

  // Unread staff messages, newest first, with sender names.
  const msgItems = await (async () => {
    const { data } = await db().from('staff_messages')
      .select('id, sender_id, body, created_at')
      .eq('recipient_id', me).is('read_at', null)
      .order('created_at', { ascending: false }).limit(PREVIEW_N);
    if (!data || !data.length) return [];
    const ids = [...new Set(data.map((m) => m.sender_id))];
    const { data: people } = await db().from('profiles')
      .select('id, first_name, last_name').in('id', ids);
    const names = new Map((people || []).map((p) => [p.id, personLabel(p)]));
    return data.map((m) => ({
      title: names.get(m.sender_id) || t('bell.someone'),
      body: (m.body || '').slice(0, 80),
      href: '#/messages',
    }));
  })().catch(() => []);

  // My tasks not yet started.
  const taskItems = await (async () => {
    const { data } = await db().from('tasks')
      .select('id, title, due_on')
      .eq('assigned_to', me).eq('status', 'not_started')
      .order('created_at', { ascending: false }).limit(PREVIEW_N);
    return (data || []).map((tk) => ({
      title: tk.title, body: '', href: '#/tasks',
    }));
  })().catch(() => []);

  // Latest announcements the person hasn't read.
  const annItems = await (async () => {
    const [{ data: anns }, { data: reads }] = await Promise.all([
      db().from('announcements').select('id, title, created_at')
        .order('created_at', { ascending: false }).limit(10),
      db().from('announcement_reads').select('announcement_id')
        .eq('profile_id', me),
    ]);
    const seen = new Set((reads || []).map((r) => r.announcement_id));
    return (anns || []).filter((a) => !seen.has(a.id)).slice(0, PREVIEW_N)
      .map((a) => ({ title: a.title, body: '', href: '#/announcements' }));
  })().catch(() => []);

  const noticeItems = await (async () => {
    const { data } = await db().from('member_notices')
      .select('id, title, created_at')
      .eq('profile_id', me).is('read_at', null)
      .order('created_at', { ascending: false }).limit(PREVIEW_N);
    return (data || []).map((nz) => ({
      title: nz.title, body: '', href: '#/me',
    }));
  })().catch(() => []);

  state.msgItems = msgItems;
  state.taskItems = taskItems;
  state.annItems = annItems;
  state.noticeItems = noticeItems;
}

async function refreshAll() {
  await Promise.all([
    refreshCounts().catch(() => {}),
    refreshPreviews().catch(() => {}),
  ]);
  document.dispatchEvent(new CustomEvent('wdos:notify'));
}

/* ---------------- realtime ---------------- */
let refreshTimer = null;
function queueRefresh() {
  clearTimeout(refreshTimer);
  refreshTimer = setTimeout(() => refreshAll(), 800);
}

function subscribe() {
  if (state.channel) return;
  const me = state.userId;
  state.channel = db()
    .channel('wdos-notify')
    .on('postgres_changes', {
      event: 'INSERT', schema: 'public', table: 'staff_messages',
      filter: `recipient_id=eq.${me}`,
    }, (p) => {
      state.msgs += 1; chirp();
      toast(t('bell.newMessage'));
      sysNotify(t('bell.newMessage'), p?.new?.body);
      document.dispatchEvent(new CustomEvent('wdos:notify'));
      queueRefresh();
    })
    .on('postgres_changes', {
      event: 'INSERT', schema: 'public', table: 'tasks',
      filter: `assigned_to=eq.${me}`,
    }, (p) => {
      state.tasks += 1; chirp();
      toast(t('bell.newTask'));
      sysNotify(t('bell.newTask'), p?.new?.title);
      document.dispatchEvent(new CustomEvent('wdos:notify'));
      queueRefresh();
    })
    .on('postgres_changes', {
      event: 'INSERT', schema: 'public', table: 'task_comment_mentions',
      filter: `profile_id=eq.${me}`,
    }, () => {
      chirp();
      toast(t('bell.newMention'));
      sysNotify(t('bell.newMention'));
    })
    .on('postgres_changes', {
      event: 'INSERT', schema: 'public', table: 'member_notices',
      filter: `profile_id=eq.${me}`,
    }, (p) => {
      state.notices += 1; chirp();
      const isCall = !!(p?.new?.meta && p.new.meta.call);
      toast(isCall ? (p?.new?.title || t('bell.newNotice')) : t('bell.newNotice'));
      sysNotify(p?.new?.title || t('bell.newNotice'),
        p?.new?.body || '', { force: isCall });
      document.dispatchEvent(new CustomEvent('wdos:notify'));
      queueRefresh();
    })
    .on('postgres_changes', {
      event: 'INSERT', schema: 'public', table: 'announcements',
    }, (p) => {
      state.anns += 1; chirp();
      toast(t('bell.newAnnouncement'));
      sysNotify(t('bell.newAnnouncement'), p?.new?.title);
      document.dispatchEvent(new CustomEvent('wdos:notify'));
      queueRefresh();
    })
    .subscribe();
}

/* ---------------- UI ---------------- */
export function bellButton(bellIcon) {
  const badge = el('span', { class: 'bell__badge', hidden: true });
  const panel = el('div', { class: 'bell__panel', hidden: true });
  const btn = el('button', {
    class: 'btn btn--icon btn--quiet bell',
    style: 'background:#fff;color:#D4006A;border:0;',
    'aria-label': t('bell.label'),
    onclick: () => {
      panel.hidden = !panel.hidden;
      if (!panel.hidden) refreshAll();
    },
  }, [bellIcon, badge, panel]);
  panel.addEventListener('click', (e) => e.stopPropagation());

  function section(labelKey, items, count, href) {
    const wrap = el('div', { class: 'bell__sec' });
    wrap.append(el('div', { class: 'bell__sec-h' }, [
      el('span', { text: t(labelKey) }),
      el('a', { href, text: count > 0 ? t('bell.viewAll', { n: count }) : '',
        onclick: () => { panel.hidden = true; } }),
    ]));
    if (!items.length) {
      wrap.append(el('div', { class: 'bell__empty', text: t('bell.empty') }));
      return wrap;
    }
    for (const it of items) {
      wrap.append(el('a', {
        class: 'bell__item', href: it.href,
        onclick: () => { panel.hidden = true; },
      }, [
        el('span', { class: 'bell__item-t', text: it.title }),
        it.body ? el('span', { class: 'bell__item-b', text: it.body }) : null,
      ]));
    }
    return wrap;
  }

  function sysRow() {
    const supported = 'Notification' in window;
    const row = el('div', { class: 'bell__sys' });
    if (!supported) return row;
    const on = sysWanted() && Notification.permission === 'granted';
    const blocked = Notification.permission === 'denied';
    const label = el('span', {
      text: blocked ? t('bell.sysBlocked') : t('bell.sysLabel') });
    const toggle = el('input', {
      type: 'checkbox', class: 'toggle',
      disabled: blocked || null,
      onchange: async () => {
        if (sysWanted()) { localStorage.setItem('wdos.sysnotify', 'off'); }
        else {
          let perm = Notification.permission;
          if (perm === 'default') {
            perm = await Notification.requestPermission().catch(() => 'denied');
          }
          localStorage.setItem('wdos.sysnotify',
            perm === 'granted' ? 'on' : 'off');
        }
        paint();
      },
    });
    toggle.checked = on;
    row.append(label, toggle);
    return row;
  }

  function paint() {
    const n = total();
    badge.hidden = n === 0;
    badge.textContent = n > 99 ? '99+' : String(n);
    panel.replaceChildren(
      section('bell.notices', state.noticeItems, state.notices, '#/me'),
      section('bell.messages', state.msgItems, state.msgs, '#/messages'),
      section('bell.tasks', state.taskItems, state.tasks, '#/tasks'),
      section('bell.announcements', state.annItems, state.anns, '#/announcements'),
      sysRow(),
    );
  }

  document.addEventListener('wdos:notify', paint);
  paint();

  (async () => {
    if (!state.userId) {
      const session = await getSession().catch(() => null);
      if (!session) return;
      state.userId = session.user.id;
    }
    await refreshAll();
    subscribe();
  })();

  return btn;
}
