/* Tracker-safe deep links: email links carry ?tk= in the REAL query
   (fragments die inside click-trackers). Translate before boot. */
(function () {
  try {
    if (location.search && /[?&]tk=/.test(location.search)) {
      var tk = new URLSearchParams(location.search).get('tk');
      if (tk) {
        location.replace('/#/reset?tk=' + encodeURIComponent(tk));
      }
    }
  } catch (e) { /* boot normally */ }
})();

/* WDOS boot guardian v2 — external (CSP-legal). Before anything else:
   if this browser carries a service worker or caches from a DIFFERENT
   build, purge them and reload once. No buttons, no rituals. */
(function () {
  var BUILD = 'wdos-v53.1';
  try {
    var done = localStorage.getItem('wdos.purged.for') === BUILD;
    if (!done && 'serviceWorker' in navigator) {
      localStorage.setItem('wdos.purged.for', BUILD);
      Promise.all([
        navigator.serviceWorker.getRegistrations().then(function (rs) {
          return Promise.all(rs.map(function (r) { return r.unregister(); }));
        }).catch(function () {}),
        (window.caches ? caches.keys().then(function (ks) {
          return Promise.all(ks.map(function (k) { return caches.delete(k); }));
        }) : Promise.resolve()).catch(function () {}),
      ]).then(function () { location.reload(); });
      return;
    }
  } catch (e) { /* continue to boot */ }
})();

// Boot guardian: capture the first real error; if the app has not
    // painted within 12s, replace the blank with the reason + a repair key.
    window.__wdosErr = '';
    window.addEventListener('error', function (e) {
      if (!window.__wdosErr) window.__wdosErr = String(e.message || e.error || '');
    });
    window.addEventListener('unhandledrejection', function (e) {
      if (!window.__wdosErr) window.__wdosErr = String((e.reason && e.reason.message) || e.reason || '');
    });
    setTimeout(function () {
      var painted = false;
      try {
        painted = (document.getElementById('app').children.length > 0)
          || window.__wdosReady === true;
      } catch (eP) {}
      if (painted) return;
      var el = document.getElementById('app');
      if (!el) return;
      el.innerHTML =
        '<div style="max-width:520px;margin:14vh auto;padding:24px;'
        + 'font-family:system-ui,sans-serif;">'
        + '<h3 style="margin:0 0 8px;">WDOS did not finish loading</h3>'
        + '<p style="color:#666;font-size:14px;">'
        + (window.__wdosErr
            ? 'Captured error: ' + window.__wdosErr.replace(/</g, '&lt;')
            : 'No error was thrown; something is stuck. '
              + 'Repair clears stored state and caches, then reloads.')
        + '</p>'
        + '<button id="wdosRepair" style="margin-top:12px;padding:12px 18px;'
        + 'background:#d4006a;color:#fff;border:0;border-radius:10px;'
        + 'font-size:15px;">Repair and restart</button></div>';
      document.getElementById('wdosRepair').onclick = async function () {
        try { localStorage.removeItem('wdos.locale'); } catch (e2) {}
        try {
          var regs = await navigator.serviceWorker.getRegistrations();
          for (var i = 0; i < regs.length; i++) await regs[i].unregister();
        } catch (e3) {}
        try {
          var keys = await caches.keys();
          for (var j = 0; j < keys.length; j++) await caches.delete(keys[j]);
        } catch (e4) {}
        location.replace('/');
      };
    }, 6000);
