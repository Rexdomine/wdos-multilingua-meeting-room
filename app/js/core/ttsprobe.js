/**
 * Free-Space voice probe (Phase 62): talks to any Gradio Space by reading
 * its own API description — prints every step so failures teach us.
 */
const metaCache = new Map();  // base -> { meta, langValue }

export async function spaceSpeakTest(base, text, lang3, say, opts = {}) {
  const cached = metaCache.get(base + '|' + lang3);
  if (cached && !opts.fresh) {
    return callSpace(base, cached.meta, cached.apiName, cached.params,
      cached.langValue, text, say);
  }
  let meta = null;
  const patience = opts.patience ?? 60000;
  try { await fetch(base + '/', { mode: 'no-cors' }); } catch { /* nudge awake */ }
  const started = Date.now();
  while (!meta && Date.now() - started < patience) {
    for (const path of ['/gradio_api/info', '/info']) {
      try {
        const r = await fetch(base + path);
        say('   probe ' + path + ' → HTTP ' + r.status);
        if (r.ok) {
          meta = { info: await r.json(), api: path.replace('/info', '') };
          break;
        }
      } catch (e) { say('   probe ' + path + ' → ' + e.message); }
    }
    if (!meta) {
      say('   Space seems asleep — nudged it; retrying in 5s '
        + '(' + Math.round((patience - (Date.now() - started)) / 1000)
        + 's patience left)…');
      await new Promise((rs) => setTimeout(rs, 5000));
    }
  }
  if (!meta) throw new Error('Space stayed unreachable for 60s — it may be '
    + 'paused by its owner; paste another MMS TTS Space address and retest');
  const eps = meta.info?.named_endpoints || {};
  const names = Object.keys(eps);
  say('   endpoints: ' + (names.join(', ') || 'none'));
  let apiName = null; let params = [];
  for (const [name, def] of Object.entries(eps)) {
    const ps = def?.parameters || [];
    const hasText = ps.some((pp) =>
      /text|sentence|input/i.test(pp.label || pp.parameter_name || ''));
    if (!hasText) continue;
    if (!apiName || /tts|synth|speech/i.test(name)) { apiName = name; params = ps; }
  }
  if (!apiName) throw new Error('no text-taking endpoint found on this Space');
  say('   using ' + apiName + ' (' + params.length + ' params)');
  // resolve the language the way the Space's own dropdown spells it
  let langValue = lang3;
  try {
    const cfg = await (await fetch(base + '/config')).json();
    const dd = (cfg?.components || []).find((c) =>
      Array.isArray(c?.props?.choices) && c.props.choices.length > 10);
    if (dd) {
      const flat = dd.props.choices.map((c) =>
        Array.isArray(c) ? String(c[0]) : String(c));
      const hit = flat.find((c) => c.includes('(' + lang3 + ')'))
        || flat.find((c) => c === lang3)
        || flat.find((c) => c.toLowerCase().startsWith(lang3));
      if (hit) { langValue = hit; say('   language choice: "' + hit + '"'); }
    }
  } catch { /* keep bare code */ }

  metaCache.set(base + '|' + lang3,
    { meta, apiName, params, langValue });
  return callSpace(base, meta, apiName, params, langValue, text, say);
}

/** Download the claimed audio and prove it is audio. Returns a local
 *  blob URL the player is guaranteed to play, or null with the honest
 *  reason printed to the panel. data: URLs are already local — pass. */
async function verifyAudio(url, say, dialect) {
  if (url.startsWith('data:audio')) {
    say(`   audio \u2713 (${dialect}, inline)`);
    return url;
  }
  try {
    const r = await fetch(url);
    if (!r.ok) {
      say(`   ${dialect}: audio address replied HTTP ${r.status} \u2014 `
        + 'the Space made a file it will not hand over');
      return null;
    }
    const blob = await r.blob();
    if (blob.size < 800) {
      say(`   ${dialect}: audio file is only ${blob.size} bytes \u2014 `
        + 'not real audio');
      return null;
    }
    const head = new Uint8Array(await blob.slice(0, 16).arrayBuffer());
    const ascii = String.fromCharCode(...head.slice(0, 8));
    let mime = null;
    if (ascii.startsWith('RIFF')) mime = 'audio/wav';
    else if (ascii.startsWith('ID3')
      || (head[0] === 0xFF && (head[1] & 0xE0) === 0xE0)) mime = 'audio/mpeg';
    else if (ascii.startsWith('OggS')) mime = 'audio/ogg';
    else if (ascii.startsWith('fLaC')) mime = 'audio/flac';
    else if (head[0] === 0x1A && head[1] === 0x45
      && head[2] === 0xDF && head[3] === 0xA3) mime = 'audio/webm';
    if (!mime) {
      const peek = ascii.replace(/[^\x20-\x7E]/g, '.');
      if (/^\s*[<{]/.test(ascii)) {
        say(`   ${dialect}: the address returned a web page, not audio \u2014 `
          + 'this Space refuses to hand over its files at that path');
      } else {
        say(`   ${dialect}: ${Math.round(blob.size / 1024)} KB arrived but `
          + `the format is unknown (starts \u201c${peek}\u201d)`);
      }
      return null;
    }
    if (mime === 'audio/wav') {
      try {
        const minted = remintWav(await blob.arrayBuffer(), say);
        say(`   audio \u2713 (${dialect}, ${Math.round(blob.size / 1024)} KB `
          + 'wav, re-minted to browser-standard PCM16)');
        return URL.createObjectURL(minted);
      } catch (we) {
        say(`   wav re-mint skipped (${we.message}) \u2014 playing as-is`);
      }
    }
    say(`   audio \u2713 (${dialect}, ${Math.round(blob.size / 1024)} KB, `
      + `${mime.split('/')[1]} verified by content)`);
    return URL.createObjectURL(blob.slice(0, blob.size, mime));
  } catch (e) {
    say(`   ${dialect}: audio download failed \u2014 ${e.message}`);
    return null;
  }
}

/** Parse any RIFF/WAVE flavour (int 8/16/24/32, float 32/64, any
 *  channel count) and re-encode it as the one canonical 16-bit PCM
 *  mono WAV every browser plays. Prints the file's true recipe. */
function remintWav(buf, say) {
  const dv = new DataView(buf);
  const tag = (o) => String.fromCharCode(
    dv.getUint8(o), dv.getUint8(o + 1), dv.getUint8(o + 2), dv.getUint8(o + 3));
  if (tag(0) !== 'RIFF' || tag(8) !== 'WAVE') {
    throw new Error('not RIFF/WAVE');
  }
  let pos = 12; let fmt = null; let dataOff = -1; let dataLen = 0;
  while (pos + 8 <= dv.byteLength) {
    const id = tag(pos); const size = dv.getUint32(pos + 4, true);
    if (id === 'fmt ') {
      fmt = {
        code: dv.getUint16(pos + 8, true),
        channels: dv.getUint16(pos + 10, true),
        rate: dv.getUint32(pos + 12, true),
        bits: dv.getUint16(pos + 22, true),
      };
      if (fmt.code === 0xFFFE && size >= 40) {   // extensible: real code
        fmt.code = dv.getUint16(pos + 32, true); // sits in the GUID head
      }
    } else if (id === 'data') { dataOff = pos + 8; dataLen = size; }
    pos += 8 + size + (size % 2);
  }
  if (!fmt || dataOff < 0) throw new Error('fmt/data chunk missing');
  if (dataOff + dataLen > dv.byteLength) {
    dataLen = dv.byteLength - dataOff;         // tolerate short files
  }
  const bytesPer = fmt.bits / 8;
  const frames = Math.floor(dataLen / (bytesPer * fmt.channels));
  if (!frames) throw new Error('no audio frames');
  say(`   wav recipe: ${fmt.code === 3 ? 'float' : 'int'}${fmt.bits} `
    + `${fmt.rate} Hz ${fmt.channels}ch ${frames} frames`);
  const mono = new Float32Array(frames);
  for (let i = 0; i < frames; i += 1) {
    let acc = 0;
    for (let c = 0; c < fmt.channels; c += 1) {
      const o = dataOff + (i * fmt.channels + c) * bytesPer;
      let v = 0;
      if (fmt.code === 3 && fmt.bits === 32) v = dv.getFloat32(o, true);
      else if (fmt.code === 3 && fmt.bits === 64) v = dv.getFloat64(o, true);
      else if (fmt.bits === 16) v = dv.getInt16(o, true) / 32768;
      else if (fmt.bits === 8) v = (dv.getUint8(o) - 128) / 128;
      else if (fmt.bits === 24) {
        v = ((dv.getUint8(o) | (dv.getUint8(o + 1) << 8)
          | (dv.getUint8(o + 2) << 16)) << 8 >> 8) / 8388608;
      } else if (fmt.bits === 32) v = dv.getInt32(o, true) / 2147483648;
      else throw new Error(`unhandled ${fmt.bits}-bit code ${fmt.code}`);
      acc += v;
    }
    mono[i] = acc / fmt.channels;
  }
  const out = new ArrayBuffer(44 + frames * 2);
  const w = new DataView(out);
  const ws = (o, t) => { for (let i = 0; i < t.length; i += 1) {
    w.setUint8(o + i, t.charCodeAt(i)); } };
  ws(0, 'RIFF'); w.setUint32(4, 36 + frames * 2, true); ws(8, 'WAVE');
  ws(12, 'fmt '); w.setUint32(16, 16, true); w.setUint16(20, 1, true);
  w.setUint16(22, 1, true); w.setUint32(24, fmt.rate, true);
  w.setUint32(28, fmt.rate * 2, true); w.setUint16(32, 2, true);
  w.setUint16(34, 16, true); ws(36, 'data');
  w.setUint32(40, frames * 2, true);
  for (let i = 0; i < frames; i += 1) {
    const v = Math.max(-1, Math.min(1, mono[i]));
    w.setInt16(44 + i * 2, v < 0 ? v * 32768 : v * 32767, true);
  }
  return new Blob([out], { type: 'audio/wav' });
}

async function callSpace(base, meta, apiName, params, langValue, text, say) {
  const args = params.map((pp) => {
    const label = (pp.label || pp.parameter_name || '').toLowerCase();
    if (/text|sentence|input/.test(label)) return text;
    if (/lang|language|locale/.test(label)) return langValue;
    return pp.default ?? null;
  });

  const toUrl = (item) => {
    if (typeof item === 'string') {
      if (item.startsWith('data:audio')) return item;
      if (item.startsWith('http')) return item;
      if (/\.(wav|mp3|flac|ogg)$/i.test(item)) return base + '/file=' + item;
      if (item.length > 2000 && /^[A-Za-z0-9+/=\r\n]+$/.test(item)) {
        return 'data:audio/wav;base64,' + item.replace(/\s/g, '');
      }
      return null;
    }
    if (item && typeof item === 'object') {
      if (typeof item.data === 'string' && item.data.startsWith('data:')) {
        return item.data;              // the audio itself, already inline
      }
      const pth = item.url || item.path || item.name;
      if (!pth) return null;
      return String(pth).startsWith('http') ? pth : base + '/file=' + pth;
    }
    return null;
  };

  // ── dialect 1: Gradio 4 (two-step call + SSE)
  try {
    const post = await fetch(base + meta.api + '/call' + apiName, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ data: args }),
    });
    say('   modern call → HTTP ' + post.status);
    if (post.ok) {
      const { event_id: ev } = await post.json();
      const res = await fetch(base + meta.api + '/call' + apiName + '/' + ev);
      const raw = await res.text();
      const lines = raw.split('\n').filter((l) => l.startsWith('data:'));
      if (lines.length) {
        const payload = JSON.parse(lines[lines.length - 1].slice(5));
        const url = toUrl(Array.isArray(payload) ? payload[0] : payload);
        if (url) {
          const proven = await verifyAudio(url, say, 'modern');
          if (proven) return proven;
        }
      }
    }
  } catch (e) { say('   modern call \u2192 ' + e.message); }

  // ── dialect 2: Gradio 3 (direct POST, JSON straight back)
  for (const path of ['/run' + apiName, '/api' + apiName]) {
    try {
      const r = await fetch(base + path, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ data: args }),
      });
      say('   classic ' + path + ' \u2192 HTTP ' + r.status);
      if (!r.ok) continue;
      const j = await r.json();
      const first = Array.isArray(j?.data) ? j.data[0] : null;
      const url = toUrl(first);
      if (url) {
        const shapes = [url];
        if (url.includes('/file=')) {
          shapes.push(url.replace('/file=', '/file/').replace('//tmp', '/tmp'));
        }
        for (const shape of shapes) {
          const proven = await verifyAudio(shape, say, 'classic');
          if (proven) return proven;
        }
      } else {
        say('   classic replied without audio: '
          + JSON.stringify(first).slice(0, 120));
      }
    } catch (e) { say('   classic ' + path + ' \u2192 ' + e.message); }
  }
  throw new Error('Space alive but no dialect produced audio \u2014 screenshot this panel');
}
