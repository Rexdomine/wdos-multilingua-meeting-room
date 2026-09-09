// ============================================================================
// WDOS transcribe — Phase 127 ("cloud ears": speaking works in ANY browser).
//
// Every earlier build asked the BROWSER to understand speech
// (webkitSpeechRecognition). That engine exists only in Chrome, is broken
// in Edge since v134, dies in background tabs on phones, and some phones
// refuse it a microphone while the call holds one. This function replaces
// it: the room page RECORDS a short clip (MediaRecorder works everywhere:
// Chrome, Edge, Safari, Firefox, every phone) and sends it here; this
// function forwards it to Groq's free Whisper API and returns the text.
// The room then translates and voices it exactly as before.
//
// Deploy WITHOUT any CLI: Supabase Dashboard → Edge Functions →
// Deploy a new function → name it exactly  transcribe  → paste this whole
// file → Deploy. Leave "Verify JWT" on.
//
// Secret it reads (Dashboard → Edge Functions → Secrets):
//   GROQ_API_KEY   a free key from https://console.groq.com (API Keys).
//                  No card needed. The free tier covers hours of audio a day.
//
// Invocation from the app:
//   GET  → { configured: true|false }        (the room probes this on open)
//   POST multipart form: audio=<clip file>, lang=en|fr|ar|pt|sw
//        → { text }
// Errors: 401 not signed in · 400 bad input · 413 clip too large ·
//         502 { error: 'transcribe_failed', detail } ·
//         503 { error: 'not_configured', missing: ['GROQ_API_KEY'] }
// ============================================================================

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

// Whisper language hints. Anything else is sent without a hint and Whisper
// detects the language itself.
const LANGS = new Set(["en", "fr", "ar", "pt", "sw", "ha", "yo", "ig"]);
const MAX_BYTES = 6 * 1024 * 1024; // 6 MB ≈ well over a minute of speech
const GROQ_URL = "https://api.groq.com/openai/v1/audio/transcriptions";
const MODEL = "whisper-large-v3-turbo";

async function whoAmI(userJwt: string): Promise<{ id: string } | null> {
  try {
    const r = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
      headers: { apikey: ANON_KEY, Authorization: `Bearer ${userJwt}` },
    });
    if (!r.ok) return null;
    const u = await r.json();
    return u?.id ? { id: u.id } : null;
  } catch {
    return null;
  }
}

Deno.serve(async (req) => {
  const fnStarted = performance.now();
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  const key = (Deno.env.get("GROQ_API_KEY") || "").trim();

  if (req.method === "GET") return json({ configured: !!key });
  if (req.method !== "POST") return json({ error: "method" }, 405);
  if (!key) return json({ error: "not_configured", missing: ["GROQ_API_KEY"] }, 503);

  const auth = req.headers.get("Authorization") || "";
  const userJwt = auth.replace(/^Bearer\s+/i, "").trim();
  if (!userJwt) return json({ error: "not_signed_in" }, 401);
  const me = await whoAmI(userJwt);
  if (!me) return json({ error: "not_signed_in" }, 401);

  let form: FormData;
  try {
    form = await req.formData();
  } catch {
    return json({ error: "bad_input" }, 400);
  }
  const audio = form.get("audio");
  if (!(audio instanceof File) || audio.size === 0) {
    return json({ error: "bad_input" }, 400);
  }
  if (audio.size > MAX_BYTES) return json({ error: "too_large" }, 413);
  const lang = String(form.get("lang") || "").trim().toLowerCase();

  // Give the file an extension Whisper recognises, from its real type.
  const type = (audio.type || "").toLowerCase();
  const ext = type.includes("mp4") || type.includes("m4a") || type.includes("aac")
    ? "m4a"
    : type.includes("ogg") ? "ogg"
    : type.includes("wav") ? "wav"
    : "webm";

  const out = new FormData();
  out.append("file", audio, `clip.${ext}`);
  out.append("model", MODEL);
  out.append("response_format", "json");
  out.append("temperature", "0");
  if (LANGS.has(lang)) out.append("language", lang);

  try {
    const providerStarted = performance.now();
    const r = await fetch(GROQ_URL, {
      method: "POST",
      headers: { Authorization: `Bearer ${key}` },
      body: out,
    });
    const provider_ms = Math.round(performance.now() - providerStarted);
    if (!r.ok) {
      const detail = (await r.text()).slice(0, 300);
      return json({ error: "transcribe_failed", status: r.status, detail,
        provider_ms, fn_ms: Math.round(performance.now() - fnStarted) }, 502);
    }
    const data = await r.json();
    const text = String(data?.text || "").trim();
    return json({ text, provider_ms,
      fn_ms: Math.round(performance.now() - fnStarted) });
  } catch (e) {
    return json({ error: "transcribe_failed", detail: String(e).slice(0, 300),
      fn_ms: Math.round(performance.now() - fnStarted) }, 502);
  }
});
