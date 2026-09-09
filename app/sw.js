/**
 * WDOS service worker — offline-first viewing.
 *
 * Strategy:
 *  - App shell (HTML): network-first, cache fallback → the app always
 *    opens, even fully offline.
 *  - Static assets (CSS/JS/locales/vendor/icons): stale-while-revalidate
 *    → instant loads, silent background refresh.
 *  - Supabase REST reads (GET /rest/v1/...): network-first with cache
 *    fallback → last-loaded data remains viewable offline.
 *  - Auth and realtime endpoints: never cached.
 *  - Writes (POST/PATCH/...): never intercepted, never cached.
 *
 * The data cache is cleared on sign-out (see app.js) so cached rows
 * never leak between accounts on a shared device.
 *
 * VERSION is bumped with every release; old caches are removed on
 * activation.
 */
const VERSION = 'wdos-v68.12';
const STATIC_CACHE = `${VERSION}-static`;
const DATA_CACHE = 'wdos-data';   // stable name: app.js deletes it on sign-out

const CORE = [
  '/',
  '/index.html',
  '/assets/css/wdos.css',
  '/assets/favicon.svg',
  '/assets/woddi-logo.png',
  '/manifest.json',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(STATIC_CACHE)
      .then((c) => c.addAll(CORE))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) => Promise.all(
      keys
        .filter((k) => k.startsWith('wdos-v') && k !== STATIC_CACHE)
        .map((k) => caches.delete(k))
    )).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;             // never touch writes

  const url = new URL(req.url);

  if (url.origin === self.location.origin) {
    if (req.mode === 'navigate') {
      event.respondWith(networkFirst(req, STATIC_CACHE, '/index.html'));
    } else {
      // Network-first for ALL same-origin files. A deploy is atomic on the
      // server; serving any file from cache while others come fresh mixes
      // versions and kills the module graph (the v48 blank). Cache is now
      // strictly an offline fallback.
      event.respondWith(networkFirst(req, STATIC_CACHE));
    }
    return;
  }

  // Supabase REST reads only; auth/realtime/storage stay network-only.
  if (url.hostname.endsWith('.supabase.co')
      && url.pathname.startsWith('/rest/v1/')) {
    event.respondWith(networkFirst(req, DATA_CACHE));
  }
});

async function networkFirst(req, cacheName, fallbackPath) {
  const cache = await caches.open(cacheName);
  try {
    const res = await fetch(new Request(req, { cache: 'reload' }));
    if (res && res.ok) cache.put(req, res.clone());
    return res;
  } catch {
    const hit = await cache.match(req);
    if (hit) return hit;
    if (fallbackPath) {
      const fb = await cache.match(fallbackPath);
      if (fb) return fb;
    }
    return new Response('', { status: 503, statusText: 'Offline' });
  }
}

async function staleWhileRevalidate(req, cacheName) {
  const cache = await caches.open(cacheName);
  const hit = await cache.match(req);
  const refresh = fetch(new Request(req, { cache: 'reload' }))
    .then((res) => {
      if (res && res.ok) cache.put(req, res.clone());
      return res;
    })
    .catch(() => undefined);
  return hit || refresh.then((res) =>
    res || new Response('', { status: 503, statusText: 'Offline' }));
}

/* ---- Web Push (Phase 88) -------------------------------------------- */
/* The push-send Edge Function delivers {title, body, url}. Show it even
   when no WDOS tab exists — that is the whole point of push. The tag
   matches notifybrowser.js's scheme so an in-tab notification and a push
   for the same target replace, not stack. */
self.addEventListener('push', (event) => {
  let data = {};
  try { data = event.data ? event.data.json() : {}; } catch { /* text */ }
  const title = data.title || 'WDOS';
  const target = data.url || '#/me';
  event.waitUntil(self.registration.showNotification(title, {
    body: String(data.body || '').slice(0, 160),
    icon: '/assets/icon.png',
    badge: '/assets/icon.png',
    tag: 'wdos-' + target,
    renotify: true,
    data: { url: target },
  }));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const target = (event.notification.data && event.notification.data.url)
    || '#/me';
  event.waitUntil((async () => {
    const wins = await clients.matchAll({
      type: 'window', includeUncontrolled: true });
    for (const w of wins) {
      if ('focus' in w) {
        await w.focus();
        try { await w.navigate('/' + target); } catch { /* SPA hash */ }
        return;
      }
    }
    if (clients.openWindow) await clients.openWindow('/' + target);
  })());
});
