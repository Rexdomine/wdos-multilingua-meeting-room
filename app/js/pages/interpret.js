/**
 * WODDI Live Interpretation — Phase 53. The totally-free AI engine:
 *   SPEAK — the interpreter console captures the speaker's words with the
 *           browser's built-in speech recognition (free, no keys) and
 *           broadcasts caption lines through Supabase Realtime (ours).
 *   LISTEN — each attendee's own phone translates the captions into her
 *           chosen language using Chrome's built-in on-device Translator
 *           (free, offline-capable). No servers, no accounts, no cost.
 * Where a device lacks the translator or a language pack, captions show in
 * the speaker's language — graceful, never blank. Optional read-aloud uses
 * the device's own voices where they exist.
 */
import { el, clear } from '../core/dom.js';
import { t } from '../core/i18n.js';
import { db, getOrgSetting, getAiToken } from '../core/db.js';
import { SPACE_LANG, voiceFor, makeTranslator, myMemoryTranslate }
  from '../core/lingua.js';
import { aiTranslate } from '../core/ai.js';
import { spaceSpeakTest } from '../core/ttsprobe.js';
import { renderShell } from '../components/layout.js';
import { toast, toastError } from '../components/toast.js';

const LANGS = [
  ['en', 'English'], ['fr', 'Français'], ['pt', 'Português'],
  ['ar', 'العربية'], ['sw', 'Kiswahili'], ['ha', 'Hausa'],
  ['yo', 'Yorùbá'], ['ig', 'Igbo'],
];

function slugEvent(v) {
  return (v || 'WODDI').trim().toUpperCase()
    .replace(/\s+/g, '-').replace(/[^\w-]/g, '').slice(0, 30) || 'WODDI';
}








export async function render(root, params, ctx) {
  const shell = renderShell(root, {
    profile: ctx.profile, modules: ctx.modules, titleKey: 'nav.interpret',
  });
  const out = shell.outlet;
  clear(out);

  let channel = null;
  let recog = null;
  const teardown = () => {
    try { recog?.stop(); } catch { /* stopped */ }
    try { channel && db().removeChannel(channel); } catch { /* gone */ }
    try { window.speechSynthesis?.cancel(); } catch { /* silent */ }
    return shell.teardown();
  };

  home();
  return teardown;

  /* ------------------------------- home ------------------------------- */
  function home() {
    clear(out);
    out.append(el('p', { class: 'muted mb-4', text: t('itp.hint') }));
    const code = el('input', { class: 'input',
      placeholder: t('itp.eventPh'), style: 'flex:1;min-width:180px;',
      value: params?.e ? String(params.e) : '' });
    out.append(el('div', { class: 'card mb-4' }, [
      el('div', { class: 'card__head' }, [el('h2', { text: t('itp.event') })]),
      el('div', { class: 'row', style: 'gap:8px;flex-wrap:wrap;' }, [
        code,
        el('button', { class: 'btn btn--primary', text: t('itp.listen'),
          onclick: () => pickLang(slugEvent(code.value)) }),
        el('button', { class: 'btn btn--secondary', text: t('itp.speak'),
          onclick: () => speak(slugEvent(code.value)) }),
      ]),
      el('p', { class: 'muted mt-2', style: 'font-size:12px;',
        text: t('itp.freeNote') }),
    ]));
  }

  /* --------------------------- listener side -------------------------- */
  function pickLang(event) {
    clear(out);
    out.append(back(home),
      el('h2', { class: 'mb-2', text: t('itp.pickLang') }),
      el('p', { class: 'muted mb-2', text: t('itp.pickHint') }));
    const grid = el('div', { class: 'lang-grid' });
    for (const [tag, label] of LANGS) {
      grid.append(el('button', { class: 'lang-btn',
        onclick: () => listen(event, tag, label) }, [
        el('span', { class: 'lang-btn__code', text: tag.toUpperCase() }),
        el('span', { text: label }),
      ]));
    }
    out.append(grid);
  }

  async function listen(event, myLang, label) {
    clear(out);
    out.append(back(() => pickLang(event)));
    out.append(el('div', { class: 'row mb-2',
      style: 'gap:8px;flex-wrap:wrap;align-items:center;' }, [
      el('strong', { style: 'flex:1;', text: `${event} · ${label}` }),
    ]));
    const speakBox = el('input', { type: 'checkbox', class: 'toggle' });
    out.append(el('label', { class: 'row mb-2',
      style: 'gap:8px;align-items:center;cursor:pointer;' }, [
      speakBox, el('span', { text: t('itp.readAloud') })]));

    const feed = el('div', { class: 'cap__feed' });
    const status = el('p', { class: 'muted', text: t('itp.waiting') });
    out.append(feed, status);

    const translators = new Map();  // sourceLang -> translator|null
    let warned = false;
    let voiceWarned = false;
    let hfToken = '';
    try { hfToken = String((await getAiToken()) || ''); }
    catch { hfToken = ''; }
    let ttsSpace = 'https://mms-meta-mms.hf.space';
    try {
      const sp = await getOrgSetting('tts_space');
      if (sp && String(sp).trim()) {
        ttsSpace = String(sp).trim().replace(/\/+$/, '');
        if (!ttsSpace.startsWith('http')) ttsSpace = 'https://' + ttsSpace;
      }
    } catch { /* default */ }
    // keep device voices warm (Chrome loads them async)
    try { window.speechSynthesis?.getVoices?.(); } catch { /* none */ }

    const chips = el('div', { class: 'row mb-2',
      style: 'gap:6px;flex-wrap:wrap;' });
    const chipTr = el('span', { class: 'badge',
      text: t('itp.engTr') + ': …' });
    const chipVo = el('span', { class: 'badge',
      text: t('itp.engVo') + ': …' });
    const testBtn = el('button', { class: 'btn btn--quiet',
      style: 'min-height:28px;padding:2px 10px;',
      text: t('itp.testMine'),
      onclick: async () => {
        const sample = 'Welcome to WODDI. No woman is left out.';
        let shown = sample;
        try {
          if (myLang !== 'en') {
            if (hfToken) {
              shown = await aiTranslate(sample, 'en', myLang, hfToken);
              setEngine('tr', 'ai');
            } else {
              shown = await myMemoryTranslate(sample, 'en', myLang);
              setEngine('tr', 'basic');
            }
          }
        } catch { setEngine('tr', 'off'); }
        feed.append(el('p', { class: 'cap__line', text: shown }));
        speakLine(shown);
      } });
    chips.append(chipTr, chipVo, testBtn);
    out.insertBefore(chips, feed);
    function setEngine(which, mode) {
      const label = t('itp.eng_' + mode);
      if (which === 'tr') {
        chipTr.textContent = t('itp.engTr') + ': ' + label;
        chipTr.className = 'badge ' + (mode === 'off'
          ? 'badge--exited' : 'badge--active');
      } else {
        chipVo.textContent = t('itp.engVo') + ': ' + label;
        chipVo.className = 'badge ' + (mode === 'off'
          ? 'badge--exited' : 'badge--active');
      }
    }

    let lastAudioUrl = null;
    const soundBtn = el('button', { class: 'btn btn--secondary', hidden: true,
      style: 'min-height:30px;padding:4px 12px;',
      text: t('itp.tapSound'),
      onclick: async () => {
        soundBtn.hidden = true;
        if (lastAudioUrl) {
          try { await new Audio(lastAudioUrl).play(); } catch { /* still shy */ }
        }
      } });
    chips.append(soundBtn);

    let audioChain = Promise.resolve();
    function speakLine(text) {
      const v = voiceFor(myLang);
      if (v && 'speechSynthesis' in window) {
        setEngine('vo', 'device');
        const u = new SpeechSynthesisUtterance(text);
        u.voice = v; u.lang = v.lang;
        window.speechSynthesis.speak(u);
        return;
      }
      const lang3 = SPACE_LANG[myLang];
      if (lang3 && ttsSpace) {
        setEngine('vo', 'ai');
        audioChain = audioChain
          .then(async () => {
            const u = await spaceSpeakTest(ttsSpace, text, lang3, () => {},
              { patience: 15000 });
            lastAudioUrl = u;
            const audio = new Audio(u);
            try { await audio.play(); }
            catch {
              soundBtn.hidden = false;  // browser wants one tap first
              return;
            }
            await new Promise((r) => { audio.onended = r; audio.onerror = r; });
          })
          .catch(() => { setEngine('vo', 'off'); });
        return;
      }
      setEngine('vo', 'off');
      if (!voiceWarned) { voiceWarned = true; toast(t('itp.noVoice')); }
    }

    channel = db().channel(`interp-${event}`)
      .on('broadcast', { event: 'cap' }, async ({ payload }) => {
        const { text, lang } = payload || {};
        if (!text) return;
        status.hidden = true;
        let shown = text;
        if (lang !== myLang) {
          if (!translators.has(lang)) {
            translators.set(lang, await makeTranslator(lang, myLang));
          }
          const tr = translators.get(lang);
          let done = false;
          if (tr) {
            try { shown = await tr.translate(text); done = true;
              setEngine('tr', 'device'); }
            catch { /* fall through */ }
          }
          if (!done && hfToken) {
            try { shown = await aiTranslate(text, lang, myLang, hfToken);
              done = true; setEngine('tr', 'ai'); }
            catch { /* fall through */ }
          }
          if (!done) {
            try { shown = await myMemoryTranslate(text, lang, myLang);
              done = true; setEngine('tr', 'basic'); }
            catch { /* fall through */ }
          }
          if (!done) {
            setEngine('tr', 'off');
            if (!warned) { warned = true; toast(t('itp.noTranslator')); }
          }
        }
        const line = el('p', { class: 'cap__line', text: shown });
        feed.append(line);
        while (feed.children.length > 60) feed.firstChild.remove();
        feed.scrollTop = feed.scrollHeight;
        if (speakBox.checked) speakLine(shown);
      })
      .subscribe();
  }

  /* --------------------------- speaker side --------------------------- */
  function speak(event) {
    let chanLive = false;
    clear(out);
    out.append(back(home));
    const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
    if (!SR) {
      out.append(el('div', { class: 'card state' }, [
        el('h3', { text: t('errors.loadTitle') }),
        el('p', { text: t('itp.noRecog') }),
      ]));
      return;
    }
    const srcSel = el('select', { class: 'select' }, [
      el('option', { value: 'en-NG', text: 'English (Nigeria)' }),
      el('option', { value: 'en-US', text: 'English (Intl)' }),
      el('option', { value: 'fr-FR', text: 'Français' }),
      el('option', { value: 'pt-PT', text: 'Português' }),
      el('option', { value: 'sw-KE', text: 'Kiswahili' }),
      el('option', { value: 'ar-EG', text: 'العربية' }),
    ]);
    const startBtn = el('button', { class: 'btn btn--primary',
      text: t('itp.start') });
    const stopBtn = el('button', { class: 'btn btn--quiet',
      text: t('itp.stop'), hidden: true });
    out.append(el('div', { class: 'row mb-2',
      style: 'gap:8px;flex-wrap:wrap;align-items:center;' }, [
      el('strong', { style: 'flex:1;', text: event }),
      srcSel, startBtn, stopBtn,
    ]));
    out.append(el('p', { class: 'muted mb-2', text: t('itp.speakHint') }));
    const live = el('div', { class: 'cap__feed' });
    out.append(live);

    channel = db().channel(`interp-${event}`).subscribe((st) => { chanLive = st === 'SUBSCRIBED'; });

    startBtn.addEventListener('click', () => {
      recog = new SR();
      recog.lang = srcSel.value;
      recog.continuous = true;
      recog.interimResults = false;
      recog.onresult = (e) => {
        for (let i = e.resultIndex; i < e.results.length; i += 1) {
          const text = e.results[i][0].transcript.trim();
          if (!text) continue;
          live.append(el('p', { class: 'cap__line', text }));
          while (live.children.length > 40) live.firstChild.remove();
          live.scrollTop = live.scrollHeight;
          if (!chanLive) return;
          channel.send({ type: 'broadcast', event: 'cap',
            payload: { text, lang: srcSel.value.split('-')[0] } });
        }
      };
      recog.onerror = () => toastError(t('itp.micError'));
      recog.onend = () => { if (!stopBtn.hidden) { try { recog.start(); } catch { /* re-arm */ } } };
      try {
        recog.start();
        startBtn.hidden = true; stopBtn.hidden = false; srcSel.disabled = true;
        toast(t('itp.live'));
      } catch { toastError(t('itp.micError')); }
    });
    stopBtn.addEventListener('click', () => {
      stopBtn.hidden = true; startBtn.hidden = false; srcSel.disabled = false;
      try { recog?.stop(); } catch { /* stopped */ }
    });
  }

  function back(fn) {
    return el('button', { class: 'btn btn--quiet mb-2',
      text: '\u2190 ' + t('app.back'), onclick: fn });
  }
}
