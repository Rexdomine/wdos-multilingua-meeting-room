/**
 * WDOS Lingua (Phase 78) — the shared translation & voice engine.
 * One pipeline, used by the Interpreter page and the in-call translator:
 *   translate: device Translator API → chat AI → MyMemory → passthrough
 *   speak:     device voice → WODDI voice Space (ha/yo/ig/sw…)
 */
import { db, getOrgSetting, getAiToken } from './db.js';
import { aiTranslate } from './ai.js';
import { spaceSpeakTest } from './ttsprobe.js';

export const SPACE_LANG = { ha: 'hau', yo: 'yor', ig: 'ibo', sw: 'swh',
  en: 'eng', fr: 'fra', pt: 'por', ar: 'ara' };

const VOICE_WAIT_MS = 1200;
const SPEECH_CHUNK_CHARS = 180;
const CLOUD_FIRST_LANGS = new Set(['fr', 'pt', 'ar', 'sw']);
const CLOUD_SPEAK_TIMEOUT_MS = 12000;
let audioCtx = null;
let outputAudio = null;
let warmupUrl = null;

export function estimateSpeakMs(text) {
  return Math.min(1500 + String(text || '').length * 90, 30000);
}

function withTimeout(promise, ms, label = 'timeout') {
  let timer;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error(label)), ms);
  });
  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}

export async function unlockAudio() {
  const audio = ensureOutputAudio();
  let mediaOk = false;
  if (!warmupUrl) warmupUrl = tinyWarmupUrl();
  try {
    audio.pause();
    audio.src = warmupUrl;
    audio.currentTime = 0;
    audio.volume = 0.04;
    const playPromise = audio.play();
    if (playPromise?.then) await withTimeout(playPromise, 1200, 'audio-unlock-timeout');
    mediaOk = true;
    await new Promise((resolve) => setTimeout(resolve, 160));
    try { audio.pause(); audio.currentTime = 0; audio.volume = 1; } catch { /* optional */ }
  } catch {
    try { audio.volume = 1; } catch { /* optional */ }
  }
  const AC = window.AudioContext || window.webkitAudioContext;
  let ctxOk = false;
  if (AC) {
    if (!audioCtx) audioCtx = new AC();
    const buffer = audioCtx.createBuffer(1, 1, audioCtx.sampleRate);
    const source = audioCtx.createBufferSource();
    const gain = audioCtx.createGain();
    gain.gain.value = 0.001;
    source.buffer = buffer;
    source.connect(gain).connect(audioCtx.destination);
    source.start(0);
    if (audioCtx.state !== 'running') {
      await audioCtx.resume().catch(() => {});
      ctxOk = audioCtx.state === 'running';
    } else ctxOk = true;
  }
  return mediaOk || (!HTMLMediaElement.prototype.play && ctxOk);
}

function ensureOutputAudio() {
  if (outputAudio) return outputAudio;
  outputAudio = new Audio();
  outputAudio.preload = 'auto';
  outputAudio.autoplay = false;
  outputAudio.controls = false;
  outputAudio.playsInline = true;
  outputAudio.setAttribute('playsinline', '');
  outputAudio.setAttribute('webkit-playsinline', '');
  outputAudio.style.cssText = 'position:absolute;width:1px;height:1px;opacity:0;pointer-events:none;';
  try { document.body?.appendChild(outputAudio); } catch { /* optional */ }
  return outputAudio;
}

function tinyWarmupUrl() {
  const sampleRate = 8000;
  const samples = Math.floor(sampleRate * 0.08);
  const dataSize = samples * 2;
  const buffer = new ArrayBuffer(44 + dataSize);
  const view = new DataView(buffer);
  const write = (offset, text) => {
    for (let i = 0; i < text.length; i++) view.setUint8(offset + i, text.charCodeAt(i));
  };
  write(0, 'RIFF'); view.setUint32(4, 36 + dataSize, true); write(8, 'WAVE');
  write(12, 'fmt '); view.setUint32(16, 16, true); view.setUint16(20, 1, true);
  view.setUint16(22, 1, true); view.setUint32(24, sampleRate, true);
  view.setUint32(28, sampleRate * 2, true); view.setUint16(32, 2, true);
  view.setUint16(34, 16, true); write(36, 'data'); view.setUint32(40, dataSize, true);
  for (let i = 0; i < samples; i++) {
    const amp = Math.sin(2 * Math.PI * 440 * (i / sampleRate)) * 900;
    view.setInt16(44 + i * 2, amp, true);
  }
  return URL.createObjectURL(new Blob([buffer], { type: 'audio/wav' }));
}

function resumeSynth() {
  try {
    const sy = window.speechSynthesis;
    if (sy?.paused) sy.resume();
  } catch { /* no synth */ }
}

function waitForVoices(ms = VOICE_WAIT_MS) {
  return new Promise((r) => {
    let done = false;
    const finish = () => {
      if (done) return;
      done = true;
      r();
    };
    try {
      window.speechSynthesis?.addEventListener?.('voiceschanged', finish,
        { once: true });
    } catch { /* listener optional */ }
    setTimeout(finish, ms);
  });
}

function speechChunks(text) {
  const raw = String(text || '').replace(/\s+/g, ' ').trim();
  if (raw.length <= SPEECH_CHUNK_CHARS) return raw ? [raw] : [];
  const out = [];
  let rest = raw;
  while (rest.length > SPEECH_CHUNK_CHARS) {
    const slice = rest.slice(0, SPEECH_CHUNK_CHARS);
    const cut = Math.max(slice.lastIndexOf('. '), slice.lastIndexOf('? '),
      slice.lastIndexOf('! '), slice.lastIndexOf('; '),
      slice.lastIndexOf(', '), slice.lastIndexOf(' '));
    const at = cut > 60 ? cut + 1 : SPEECH_CHUNK_CHARS;
    out.push(rest.slice(0, at).trim());
    rest = rest.slice(at).trim();
  }
  if (rest) out.push(rest);
  return out;
}

// Chrome quirks, shielded once at module load: the voice list arrives
// late (getVoices() is empty at first ask), and the synthesiser can
// wedge itself paused and go silent until poked. Warm the list and keep
// a small heartbeat that unwedges it.
try {
  window.speechSynthesis?.getVoices?.();
  window.speechSynthesis?.addEventListener?.('voiceschanged', () => {});
  setInterval(() => {
    resumeSynth();
  }, 4000);
} catch { /* no synth */ }

export function voiceFor(lang) {
  const vs = window.speechSynthesis?.getVoices?.() || [];
  return vs.find((v) => v.lang?.toLowerCase().startsWith(lang)) || null;
}

export async function makeTranslator(from, to) {
  try {
    if ('Translator' in window) {
      const avail = await window.Translator.availability({
        sourceLanguage: from, targetLanguage: to });
      if (avail !== 'unavailable') {
        return await window.Translator.create({
          sourceLanguage: from, targetLanguage: to });
      }
    }
  } catch { /* fall through */ }
  return null;
}

const mmCache = new Map();
export async function myMemoryTranslate(text, from, to) {
  const key = `${from}|${to}|${text}`;
  if (mmCache.has(key)) return mmCache.get(key);
  const url = 'https://api.mymemory.translated.net/get?q='
    + encodeURIComponent(text.slice(0, 450))
    + '&langpair=' + encodeURIComponent(`${from}|${to}`);
  const res = await fetch(url);
  if (!res.ok) throw new Error('quota');
  const data = await res.json();
  const outText = data?.responseData?.translatedText;
  if (!outText || Number(data?.responseStatus) >= 400
      || /MYMEMORY WARNING|QUERY LENGTH LIMIT|INVALID LANGUAGE/i.test(outText)) {
    throw new Error('quota');
  }
  mmCache.set(key, outText);
  return outText;
}

/** A reusable translator between two 2-letter codes. */
export function createLingua() {
  const translators = new Map();
  let hfToken = null;
  const status = {
    translate: '…',
    translateDetail: '',
    voice: '…',
    voiceDetail: '',
  };

  async function token() {
    if (hfToken === null) {
      try { hfToken = String((await getAiToken()) || ''); }
      catch { hfToken = ''; }
    }
    return hfToken;
  }

  const tCache = new Map();
  const remember = (k, out, mode, detail = '') => {
    if (tCache.size > 300) tCache.clear();
    tCache.set(k, { out, mode, detail });
    status.translate = mode;
    status.translateDetail = detail;
    return out;
  };
  async function translate(text, from, to) {
    if (!text) return text;
    if (from === to) {
      status.translate = 'same';
      status.translateDetail = '';
      return text;
    }
    const ck = `${from}|${to}|${text}`;
    if (tCache.has(ck)) {
      const hit = tCache.get(ck);
      status.translate = hit.mode || 'free';
      status.translateDetail = hit.detail || '';
      return hit.out;
    }
    const key = `${from}|${to}`;
    if (!translators.has(key)) {
      translators.set(key, await makeTranslator(from, to));
    }
    const dev = translators.get(key);
    if (dev) {
      try {
        const out = await dev.translate(text);
        return remember(ck, out, 'device');
      } catch { /* next */ }
    }
    if (await cloudTranslateReady()) {
      try {
        const out = await cloudTranslate(text, from, to);
        return remember(ck, out, 'cloud');
      } catch { /* next */ }
    }
    const tok = await token();
    if (tok) {
      try {
        const out = await aiTranslate(text, from, to, tok);
        return remember(ck, out, 'ai');
      } catch { /* next */ }
    }
    try {
      const out = await myMemoryTranslate(text, from, to);
      return remember(ck, out, 'free');
    } catch { /* next */ }
    status.translate = 'off';
    status.translateDetail = `${from}->${to} passthrough`;
    return text;
  }

  /** Speak text in lang; returns 'device' | 'ai' | 'blocked' | 'off'. */
  let chain = Promise.resolve();
  let space = null;
  async function ttsSpace() {
    if (space === null) {
      try { space = String((await getOrgSetting('tts_space')) || ''); }
      catch { space = ''; }
    }
    return space;
  }

  // Phase 128: cloud voice (Groq, same key as the cloud ears) for the
  // languages a device usually cannot speak. Probed once; languages are
  // whatever the function reports (Arabic and English today).
  // Phase 129: cloud translation (Groq, same key) — fast and reliable
  // where the device translator is absent and the free public service
  // throttles. Probed once.
  let cloudTrans = null;
  async function cloudTranslateReady() {
    if (cloudTrans === null) {
      try {
        const { data, error } = await db().functions.invoke('translate',
          { method: 'GET' });
        cloudTrans = !error && !!data?.configured;
      } catch { cloudTrans = false; }
    }
    return cloudTrans;
  }
  async function cloudTranslate(text, from, to) {
    const { data, error } = await db().functions.invoke('translate',
      { body: { text, from, to } });
    if (error) throw error;
    const out = String(data?.text || '').trim();
    if (!out) throw new Error('empty');
    return out;
  }

  let cloudLangs = null;
  async function cloudVoiceLangs() {
    if (cloudLangs === null) {
      try {
        const fns = db().functions;
        const { data, error } = await fns.invoke('speak', { method: 'GET' });
        cloudLangs = (!error && data?.configured && Array.isArray(data.langs))
          ? data.langs.map(String) : [];
      } catch { cloudLangs = []; }
    }
    return cloudLangs;
  }
  const cloudAudio = new Map(); // text|lang -> Blob (repeats are free)
  async function cloudSpeakBlob(text, lang) {
    const k = `${lang}|${text}`;
    if (cloudAudio.has(k)) return cloudAudio.get(k);
    const { data, error } = await withTimeout(db().functions.invoke('speak',
      { body: { text, lang } }), CLOUD_SPEAK_TIMEOUT_MS, 'cloud-speak-timeout');
    if (error) throw error;
    const blob = data instanceof Blob ? data
      : new Blob([data], { type: 'audio/wav' });
    if (cloudAudio.size > 60) cloudAudio.clear();
    cloudAudio.set(k, blob);
    return blob;
  }

  async function voiceStatus(lang) {
    const cl = await cloudVoiceLangs();
    if (CLOUD_FIRST_LANGS.has(lang) && cl.includes(lang)) {
      status.voice = 'cloud';
      status.voiceDetail = 'WODDI cloud voice';
      return { mode: 'cloud', detail: status.voiceDetail };
    }
    let v = voiceFor(lang);
    if (!v && 'speechSynthesis' in window
        && (window.speechSynthesis.getVoices?.() || []).length === 0) {
      // Diagnostics wait for the late-arriving browser voice list instead
      // of declaring "no voice" during Chrome's empty initial response.
      await waitForVoices();
      v = voiceFor(lang);
    }
    if (v && 'speechSynthesis' in window) {
      status.voice = 'device';
      status.voiceDetail = `${v.name || 'voice'} (${v.lang || lang})`;
      return { mode: 'device', voice: v, detail: status.voiceDetail };
    }
    if (cl.includes(lang)) {
      status.voice = 'cloud';
      status.voiceDetail = 'WODDI cloud voice';
      return { mode: 'cloud', detail: status.voiceDetail };
    }
    const lang3 = SPACE_LANG[lang];
    const spaceUrl = await ttsSpace();
    if (lang3 && spaceUrl) {
      status.voice = 'ai';
      status.voiceDetail = 'WODDI voice Space';
      return { mode: 'ai', space: spaceUrl, lang3,
        detail: status.voiceDetail };
    }
    status.voice = 'off';
    status.voiceDetail = `No ${lang} voice on this device`;
    return { mode: 'off', detail: status.voiceDetail };
  }

  const aborted = (signal) => !!signal?.aborted;
  function throwIfAborted(signal) {
    if (aborted(signal)) throw new DOMException('cancelled', 'AbortError');
  }

  async function playUrlWithElement(url, signal, revoke = false) {
    const audio = ensureOutputAudio();
    audio.preload = 'auto';
    let cleanup = () => {};
    try {
      audio.pause();
      audio.src = url;
      audio.currentTime = 0;
      audio.volume = 1;
      throwIfAborted(signal);
      const playPromise = audio.play();
      if (playPromise?.then) await playPromise;
      throwIfAborted(signal);
      await new Promise((resolve) => {
        let done = false;
        const finish = () => {
          if (done) return;
          done = true;
          cleanup();
          resolve();
        };
        const cancel = () => {
          try { audio.pause(); audio.currentTime = 0; } catch { /* optional */ }
          finish();
        };
        cleanup = () => {
          signal?.removeEventListener?.('abort', cancel);
          audio.onended = null;
          audio.onerror = null;
        };
        signal?.addEventListener?.('abort', cancel, { once: true });
        audio.onended = finish;
        audio.onerror = finish;
        const dur = Number.isFinite(audio.duration) && audio.duration > 0
          ? audio.duration * 1000 : estimateSpeakMs(' '.repeat(40));
        setTimeout(finish, Math.max(2500, dur + 3000));
      });
      throwIfAborted(signal);
    } finally {
      cleanup();
      if (revoke) setTimeout(() => URL.revokeObjectURL(url), 30000);
    }
  }

  async function playBlobWithElement(blob, signal) {
    const url = URL.createObjectURL(blob);
    await playUrlWithElement(url, signal, true);
  }

  async function playBlobWithContext(blob, signal) {
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) throw new Error('audio-context-unavailable');
    if (!audioCtx) audioCtx = new AC();
    if (audioCtx.state !== 'running') await audioCtx.resume();
    throwIfAborted(signal);
    const bytes = await blob.arrayBuffer();
    throwIfAborted(signal);
    const buffer = await audioCtx.decodeAudioData(bytes.slice(0));
    throwIfAborted(signal);
    const source = audioCtx.createBufferSource();
    source.buffer = buffer;
    source.connect(audioCtx.destination);
    await new Promise((resolve, reject) => {
      let done = false;
      const finish = () => {
        if (done) return;
        done = true;
        resolve();
      };
      const cancel = () => {
        try { source.stop(0); } catch { /* already stopped */ }
        finish();
      };
      signal?.addEventListener?.('abort', cancel, { once: true });
      source.onended = finish;
      try { source.start(0); }
      catch (e) { reject(e); }
      setTimeout(finish, Math.max(2500, buffer.duration * 1000 + 3000));
    });
    throwIfAborted(signal);
  }

  async function speakDevice(text, lang, voice, signal) {
    const chunks = speechChunks(text);
    if (!chunks.length) return;
    const sy = window.speechSynthesis;
    for (const part of chunks) {
      throwIfAborted(signal);
      resumeSynth();
      const u = new SpeechSynthesisUtterance(part);
      u.voice = voice; u.lang = voice.lang || lang;
      let failed = false;
      await new Promise((r) => {
        let done = false;
        const finish = () => {
          if (done) return;
          done = true;
          r();
        };
        u.onend = finish;
        u.onerror = () => { failed = true; finish(); };
        const cancel = () => {
          try { sy.cancel(); } catch { /* optional */ }
          finish();
        };
        signal?.addEventListener?.('abort', cancel, { once: true });
        try {
          sy.speak(u);
          setTimeout(resumeSynth, 40);
        } catch {
          failed = true;
          finish();
        }
        setTimeout(finish, estimateSpeakMs(part) + 1000);
      });
      throwIfAborted(signal);
      if (failed) throw new Error('speech blocked');
      await new Promise((r) => setTimeout(r, 60));
    }
  }

  async function playCloudBlob(blob, signal) {
    try {
      await playBlobWithElement(blob, signal);
      return 'element';
    } catch (elementErr) {
      if (elementErr?.name === 'AbortError' || aborted(signal)) throw elementErr;
      await playBlobWithContext(blob, signal);
      return 'context';
    }
  }

  async function doSpeak(text, lang, { onBlockedUrl, beforeStart, signal } = {}) {
    if (aborted(signal)) return 'cancelled';
    const info = await voiceStatus(lang);
    if (aborted(signal)) return 'cancelled';
    if (info.mode === 'device') {
      try {
        if (aborted(signal)) return 'cancelled';
        await beforeStart?.();
        await speakDevice(text, lang, info.voice, signal);
        status.voice = 'device';
        status.voiceDetail = info.detail;
        return 'device';
      } catch (e) {
        if (e?.name === 'AbortError' || aborted(signal)) return 'cancelled';
        status.voice = 'blocked';
        status.voiceDetail = 'Browser speech engine refused playback';
        return 'blocked';
      }
    }
    if (info.mode === 'cloud') {
      try {
        const parts = speechChunks(text);
        if (aborted(signal)) return 'cancelled';
        await beforeStart?.();
        for (const part of parts) {
          if (aborted(signal)) return 'cancelled';
          const blob = await cloudSpeakBlob(part, lang);
          if (aborted(signal)) return 'cancelled';
          try { await playCloudBlob(blob, signal); }
          catch {
            const url = URL.createObjectURL(blob);
            status.voice = 'blocked';
            status.voiceDetail = 'Tap required to start generated audio';
            onBlockedUrl?.(url);
            return 'blocked';
          }
          if (aborted(signal)) return 'cancelled';
        }
        status.voice = 'cloud';
        status.voiceDetail = info.detail;
        return 'cloud';
      } catch (e) {
        if (e?.name === 'AbortError' || aborted(signal)) return 'cancelled';
        status.voice = 'off';
        status.voiceDetail = 'WODDI cloud voice did not answer';
        return 'off';
      }
    }
    if (info.mode === 'ai') {
      try {
        if (aborted(signal)) return 'cancelled';
        const url = await spaceSpeakTest(info.space, text, info.lang3,
          () => {}, { patience: 15000 });
        if (aborted(signal)) return 'cancelled';
        await beforeStart?.();
        try { await playUrlWithElement(url, signal); }
        catch {
          status.voice = 'blocked';
          status.voiceDetail = 'Tap required to start generated audio';
          onBlockedUrl?.(url);
          return 'blocked';
        }
        if (aborted(signal)) return 'cancelled';
        status.voice = 'ai';
        status.voiceDetail = info.detail;
        return 'ai';
      } catch (e) {
        if (e?.name === 'AbortError' || aborted(signal)) return 'cancelled';
        status.voice = 'off';
        status.voiceDetail = 'WODDI voice Space did not return playable audio';
        return 'off';
      }
    }
    return 'off';
  }

  async function speak(text, lang, opts = {}) {
    const job = chain.then(() => doSpeak(text, lang, opts));
    chain = job.catch(() => {});
    return job;
  }

  return { translate, speak, voiceStatus, unlockAudio,
    playUrl: playUrlWithElement, estimateSpeakMs, status };
}
