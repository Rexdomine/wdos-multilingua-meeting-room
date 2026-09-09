(async function () {
  var out = [];
  function say(s) { out.push(s); document.getElementById('out').textContent = out.join('\n'); }
  say('origin: ' + location.origin);
  say('time:   ' + new Date().toString());
  say('');
  var files = ['/index.html', '/sw.js', '/js/app.js', '/js/core/db.js',
               '/js/core/lingua.js', '/js/pages/room.js',
               '/assets/vendor/azure-speech/microsoft.cognitiveservices.speech.sdk.bundle-min.js',
               '/config.json', '/locales/en.json', '/assets/vendor/supabase.js'];
  for (var i = 0; i < files.length; i++) {
    var f = files[i];
    try {
      var r = await fetch(f + '?bc=' + Date.now(), { cache: 'no-store' });
      var txt = await r.text();
      var mark = '';
      var m = txt.match(/WDOS build v[\w.-]+|wdos-v[\w.-]+|APP_VERSION = '[\w.-]+'/);
      if (m) mark = '   [' + m[0] + ']';
      say((r.ok ? 'OK  ' : 'FAIL') + ' ' + f + '  (' + r.status + ', '
          + txt.length + ' bytes)' + mark);
    } catch (e) { say('FAIL ' + f + '  ' + (e && e.message)); }
  }
  say('');
  try {
    var regs = await navigator.serviceWorker.getRegistrations();
    say('service workers here: ' + regs.length);
  } catch (e) { say('service workers: n/a'); }
  try {
    var keys = await caches.keys();
    say('caches here: ' + (keys.join(', ') || 'none'));
  } catch (e) { say('caches: n/a'); }
  say('');
  say('READ IT LIKE THIS:');
  say('- index.html should show [WDOS build v68.20-explicit-audio-play] → server is current.');
  say('- If it shows an older build or FAIL → the deploy did not reach');
  say('  THIS site; drag the folder to the site owning ' + location.host + '.');
  say('- If server is current but the app is blank → press Repair below.');
})();
document.getElementById('repair').onclick = async function () {
  try {
    var regs = await navigator.serviceWorker.getRegistrations();
    for (var i = 0; i < regs.length; i++) await regs[i].unregister();
  } catch (e) {}
  try {
    var keys = await caches.keys();
    for (var j = 0; j < keys.length; j++) await caches.delete(keys[j]);
  } catch (e) {}
  try { localStorage.removeItem('wdos.locale'); } catch (e) {}
  location.replace('/');
};
