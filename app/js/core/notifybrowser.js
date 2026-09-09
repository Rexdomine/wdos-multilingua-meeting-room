/**
 * WDOS Browser Notifications (Phase 87). System notifications for new
 * messages, task assignments, announcements and personal notices — fired
 * over the org's own realtime lanes the instant rows land.
 *
 * Honest scope: these fire while WDOS is open in ANY tab (focused,
 * backgrounded, minimised). True push with the browser fully closed
 * needs a push server (VAPID) — parked on the roadmap.
 */
import { db } from './db.js';
import { t } from './i18n.js';

let channel = null;

export function notifyPermission() {
  return ('Notification' in window) ? Notification.permission : 'unsupported';
}

/** Must be called from a user gesture (button click). */
export async function enableBrowserNotifications(profile) {
  if (!('Notification' in window)) return 'unsupported';
  let perm = Notification.permission;
  if (perm === 'default') {
    perm = await Notification.requestPermission();
  }
  if (perm === 'granted') {
    initBrowserNotify(profile);
    fire(t('bn.testTitle'), t('bn.testBody'), '#/');
  }
  return perm;
}

function fire(title, body, target) {
  try {
    if (document.visibilityState === 'visible') return; // toasts cover this
    const n = new Notification(title, {
      body: String(body || '').slice(0, 140),
      tag: 'wdos-' + target,
      badge: '/assets/icon.png',
      icon: '/assets/icon.png',
    });
    n.onclick = () => {
      try { window.focus(); } catch { /* fine */ }
      location.hash = target;
      n.close();
    };
  } catch { /* notification blocked mid-flight */ }
}

export function initBrowserNotify(profile) {
  if (!('Notification' in window)
      || Notification.permission !== 'granted'
      || !profile?.id || channel) return;

  channel = db().channel(`sysnotify-${profile.id}`)
    .on('postgres_changes',
      { event: 'INSERT', schema: 'public', table: 'staff_messages',
        filter: `recipient_id=eq.${profile.id}` },
      ({ new: m }) => fire(t('bn.msgTitle'), m?.body || '', '#/messages'))
    .on('postgres_changes',
      { event: 'INSERT', schema: 'public', table: 'tasks',
        filter: `assigned_to=eq.${profile.id}` },
      ({ new: r }) => fire(t('bn.taskTitle'), r?.title || '', '#/tasks'))
    .on('postgres_changes',
      { event: 'INSERT', schema: 'public', table: 'member_notices',
        filter: `profile_id=eq.${profile.id}` },
      ({ new: r }) => fire(r?.title || t('bn.noticeTitle'),
        r?.body || '', '#/me'))
    .on('postgres_changes',
      { event: 'INSERT', schema: 'public', table: 'announcements' },
      ({ new: r }) => fire(t('bn.annTitle'), r?.title || '',
        '#/announcements'))
    .subscribe();
}

export function teardownBrowserNotify() {
  try { if (channel) db().removeChannel(channel); } catch { /* gone */ }
  channel = null;
}
