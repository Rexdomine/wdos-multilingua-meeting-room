/**
 * WODDI AI core (Phase 63). The 2026 free catalog dropped the classic
 * task models (NLLB, BART, MMS-serverless) — so all text intelligence now
 * rides the chat lane: the router's OpenAI-style endpoint, with a fallback
 * ladder of models and every step printable for the forensics panels.
 * One free key powers translation, the interface builder, and the Scribe.
 */

const CHAT_URL = 'https://router.huggingface.co/v1/chat/completions';
const MODELS = [
  'Qwen/Qwen2.5-7B-Instruct',
  'google/gemma-2-9b-it',
  'meta-llama/Llama-3.1-8B-Instruct',
  'meta-llama/Llama-3.2-3B-Instruct',
];

export const LANG_NAMES = {
  en: 'English', fr: 'French', pt: 'Portuguese', ar: 'Arabic',
  sw: 'Swahili', ha: 'Hausa', yo: 'Yoruba', ig: 'Igbo',
};

export async function aiChat(messages, tok, opts = {}) {
  const say = opts.say || (() => {});
  let lastErr = 'no model answered';
  for (const model of (opts.models || MODELS)) {
    try {
      const r = await fetch(CHAT_URL, {
        method: 'POST',
        headers: { Authorization: 'Bearer ' + tok,
          'Content-Type': 'application/json' },
        body: JSON.stringify({ model, messages,
          temperature: opts.temperature ?? 0.2,
          max_tokens: opts.maxTokens ?? 400 }),
      });
      if (!r.ok) {
        let btxt = '';
        try { btxt = (await r.text()).slice(0, 120); } catch { /* none */ }
        say(`   ${model} → HTTP ${r.status} ${btxt}`);
        lastErr = `HTTP ${r.status}`;
        continue;
      }
      const j = await r.json();
      const out = j?.choices?.[0]?.message?.content?.trim();
      if (out) { say(`   ${model} → 200 ✓`); return { text: out, model }; }
      say(`   ${model} → empty reply`);
    } catch (e) {
      say(`   ${model} → ${e.message}`);
      lastErr = e.message;
    }
  }
  throw new Error(lastErr);
}

export async function aiTranslate(text, fromCode, toCode, tok, opts = {}) {
  const from = LANG_NAMES[fromCode] || fromCode;
  const to = LANG_NAMES[toCode] || toCode;
  const { text: out } = await aiChat([
    { role: 'system',
      content: `You are a precise translator. Translate the user's text from ${from} to ${to}. Reply with ONLY the translation — no notes, no quotes.` },
    { role: 'user', content: text.slice(0, 600) },
  ], tok, { ...opts, temperature: 0 });
  return out;
}

export async function aiTranslateBatch(values, toCode, tok, opts = {}) {
  const to = LANG_NAMES[toCode] || toCode;
  const joined = values.map((v, i) => `${i + 1}. ${v}`).join('\n');
  const { text: out } = await aiChat([
    { role: 'system',
      content: `Translate each numbered English line into ${to}. Reply with the SAME numbered lines, translations only, nothing else. Keep placeholders like {name} or {n} exactly as they are.` },
    { role: 'user', content: joined },
  ], tok, { ...opts, temperature: 0, maxTokens: 900 });
  const map = new Map();
  for (const line of out.split('\n')) {
    const m = line.match(/^\s*(\d+)[).:-]?\s+(.*)$/);
    if (m) map.set(Number(m[1]) - 1, m[2].trim());
  }
  return values.map((v, i) => map.get(i) || v);
}

export async function aiSummarizeMinutes(transcript, tok, opts = {}) {
  const { text: out } = await aiChat([
    { role: 'system',
      content: 'You are WODDI Scribe, a meeting secretary. From the raw transcript, write concise minutes: 3-8 bullet points of decisions and discussion, then a line "Action items:" with owner → task bullets if any were stated. Plain text, no markdown symbols other than the bullet character •.' },
    { role: 'user', content: transcript.slice(0, 6000) },
  ], tok, { ...opts, temperature: 0.2, maxTokens: 500 });
  return out;
}
