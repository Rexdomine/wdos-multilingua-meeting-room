/**
 * WDOS router — hash-based so it works on any static host with no
 * server rewrites and survives offline reloads.
 *
 * Route shape: { path: '#/members/:id', page: fn(params), public: bool }
 * Each page module exports render(container, params) and may export
 * teardown() for cleanup (event listeners, realtime channels).
 */
const routes = [];
let currentTeardown = null;
let guard = null;

export function registerRoute(path, page, { isPublic = false } = {}) {
  const keys = [];
  const pattern = new RegExp(
    '^' +
    path.replace(/:[^/]+/g, (m) => { keys.push(m.slice(1)); return '([^/]+)'; }) +
    '$'
  );
  routes.push({ pattern, keys, page, isPublic });
}

/** guardFn(route) -> '#/somewhere' to redirect, or null to allow. */
export function setGuard(guardFn) { guard = guardFn; }

export function navigate(hash) {
  if (location.hash === hash) return resolve();
  location.hash = hash;
}

async function resolve() {
  // Google (and any OAuth) sign-in can return three ways: tokens in
  // the fragment (#access_token=...), a PKCE code in the query
  // (?code=...), or an error fragment (#error=...). The auth library
  // consumes them a moment after load; without this guard the router
  // would read those as a page name and show "Page not found".
  const authish =
    /(^#|[#&?])(access_token|refresh_token|provider_token|error|error_code|error_description|code)=/;
  if (authish.test(location.hash) || authish.test(location.search)) {
    const outlet = document.getElementById('app');
    outlet.innerHTML =
      '<div class="state"><h3>Signing you in\u2026</h3></div>';
    const hadError = /(^#|[#&?])(error|error_code|error_description)=/.test(location.hash + location.search);
    const { db, hasProfile } = await import('./db.js');
    let signed = false;
    for (let i = 0; i < 40; i++) {
      try {
        const { data } = await db().auth.getSession();
        if (data?.session) { signed = true; break; }
      } catch { /* client still booting */ }
      await new Promise((r) => setTimeout(r, 200));
    }
    // If signed in, give the profile-creation trigger a moment so the
    // dashboard does not render before the row exists.
    if (signed) {
      for (let i = 0; i < 20; i++) {
        try { if (await hasProfile()) break; } catch { /* keep waiting */ }
        await new Promise((r) => setTimeout(r, 250));
      }
    }
    history.replaceState(null, '',
      location.pathname + (signed ? '#/' : '#/login' + (hadError ? '?oauth=failed' : '')));
    return resolve();
  }

  const full = location.hash || '#/';
  const qIdx = full.indexOf('?');
  const hash = qIdx >= 0 ? full.slice(0, qIdx) : full;
  const query = qIdx >= 0
    ? Object.fromEntries(new URLSearchParams(full.slice(qIdx + 1)))
    : {};
  const match = routes
    .map((r) => ({ r, m: hash.match(r.pattern) }))
    .find((x) => x.m);

  const outlet = document.getElementById('app');
  if (!match) {
    outlet.innerHTML =
      '<div class="state"><h3>Page not found</h3>' +
      '<p><a href="#/">Go to the dashboard</a></p></div>';
    return;
  }

  if (guard) {
    const redirect = await guard(match.r);
    if (redirect) { location.hash = redirect; return; }
  }

  if (typeof currentTeardown === 'function') currentTeardown();
  const params = {
    ...query,
    ...Object.fromEntries(
      match.r.keys.map((k, i) => [k, decodeURIComponent(match.m[i + 1])])),
  };
  currentTeardown = await match.r.page(outlet, params);
}

export function startRouter() {
  window.addEventListener('hashchange', resolve);
  return resolve();
}
