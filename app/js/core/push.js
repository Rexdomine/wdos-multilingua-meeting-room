/**
 * WDOS Web Push (Phase 88) — true notifications with the browser closed.
 *
 * The in-tab engine (notifybrowser.js) covers open tabs over realtime;
 * this module registers the DEVICE with the browser's push service so the
 * push-send Edge Function can reach it when no tab is open. Each device
 * (a leader's phone, her laptop) is its own row in push_subscriptions.
 *
 * The application server key below is the VAPID PUBLIC key — public by
 * design (it is what the browser uses to pin which server may push here).
 * The private half lives only in Supabase Edge Function secrets.
 *
 * Honest limits, browser by browser: Chrome/Edge on desktop keep a
 * background process, so "closed" delivery works; a fully quit browser on
 * macOS delivers on next open; iOS delivers only when WDOS is installed
 * to the home screen (Add to Home Screen from Safari).
 */
import { db, getSession } from './db.js';

export const VAPID_PUBLIC_KEY =
  'BAEoCY7dk-yBQjg1detVwvtOTe9pMGxxfQ7a3GfB1JfomGtjLfZUzt1FTUO6xVJgvoJvGF8ptVsI5FK0hXnTLjU';

function b64ToBytes(b64) {
  const pad = '='.repeat((4 - (b64.length % 4)) % 4);
  const raw = atob((b64 + pad).replace(/-/g, '+').replace(/_/g, '/'));
  return Uint8Array.from(raw, (c) => c.charCodeAt(0));
}

export function pushSupported() {
  return ('serviceWorker' in navigator) && ('PushManager' in window)
    && ('Notification' in window);
}

/** Current device state: 'unsupported' | 'denied' | 'off' | 'on'. */
export async function pushState() {
  if (!pushSupported()) return 'unsupported';
  if (Notification.permission === 'denied') return 'denied';
  try {
    const reg = await navigator.serviceWorker.ready;
    const sub = await reg.pushManager.getSubscription();
    return sub ? 'on' : 'off';
  } catch {
    return 'off';
  }
}

/** Must run from a user gesture. Registers this device and saves the row. */
export async function enablePush() {
  if (!pushSupported()) return 'unsupported';
  let perm = Notification.permission;
  if (perm === 'default') perm = await Notification.requestPermission();
  if (perm !== 'granted') return perm;

  const reg = await navigator.serviceWorker.ready;
  let sub = await reg.pushManager.getSubscription();
  if (!sub) {
    sub = await reg.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: b64ToBytes(VAPID_PUBLIC_KEY),
    });
  }
  const json = sub.toJSON();
  const session = await getSession();
  const { error } = await db().from('push_subscriptions').upsert({
    profile_id: session.user.id,
    endpoint: sub.endpoint,
    p256dh: json.keys.p256dh,
    auth: json.keys.auth,
    ua: navigator.userAgent.slice(0, 200),
    last_seen_at: new Date().toISOString(),
  }, { onConflict: 'endpoint' });
  if (error) throw error;
  return 'on';
}

/** Unsubscribes this device and removes its row. */
export async function disablePush() {
  if (!pushSupported()) return;
  const reg = await navigator.serviceWorker.ready;
  const sub = await reg.pushManager.getSubscription();
  if (!sub) return;
  try {
    await db().from('push_subscriptions')
      .delete().eq('endpoint', sub.endpoint);
  } catch { /* row may already be pruned */ }
  await sub.unsubscribe();
}
