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

export function estimateSpeakMs(text) {
  return Math.min(1500 + String(text || '').length * 90, 30000);
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
    const { data, error } = await db().functions.invoke('speak',
      { body: { text, lang } });
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
          const url = URL.createObjectURL(blob);
          const audio = new Audio(url);
          let finishAudio = () => {};
          const cancel = () => {
            try { audio.pause(); audio.currentTime = 0; } catch { /* optional */ }
            URL.revokeObjectURL(url);
            finishAudio();
          };
          signal?.addEventListener?.('abort', cancel, { once: true });
          try { await audio.play(); }
          catch {
            status.voice = 'blocked';
            status.voiceDetail = 'Tap required to start generated audio';
            onBlockedUrl?.(url);
            return 'blocked';
          }
          await new Promise((r) => {
            finishAudio = r;
            audio.onended = r;
            audio.onerror = r;
          });
          signal?.removeEventListener?.('abort', cancel);
          if (aborted(signal)) return 'cancelled';
          URL.revokeObjectURL(url);
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
        const audio = new Audio(url);
        await beforeStart?.();
        let finishAudio = () => {};
        const cancel = () => {
          try { audio.pause(); audio.currentTime = 0; } catch { /* optional */ }
          finishAudio();
        };
        signal?.addEventListener?.('abort', cancel, { once: true });
        try { await audio.play(); }
        catch {
          status.voice = 'blocked';
          status.voiceDetail = 'Tap required to start generated audio';
          onBlockedUrl?.(url);
          return 'blocked';
        }
        await new Promise((r) => {
          finishAudio = r;
          audio.onended = r;
          audio.onerror = r;
        });
        signal?.removeEventListener?.('abort', cancel);
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

  return { translate, speak, voiceStatus, estimateSpeakMs, status };
}
