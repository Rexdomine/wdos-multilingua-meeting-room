// ============================================================================
// WDOS translate — Phase 129 (fast, reliable cloud translation).
//
// The room's translation lane leaned on the browser's built-in translator
// (great when present, absent on many phones) and then on a free public
// service that throttles shared connections — which showed up in real use
// as slow or missing translations. This function translates with a fast
// Groq language model using the SAME free GROQ_API_KEY as the ears and
// the voice. Typical answer time is well under a second.
//
// Deploy WITHOUT any CLI: Supabase Dashboard → Edge Functions →
// Deploy a new function → name it exactly  translate  → paste this whole
// file → Deploy. Leave "Verify JWT" on. No new secret.
//
// Invocation from the app:
//   GET  → { configured }
//   POST { text, from, to }  → { text }
// Errors: 401 not signed in · 400 bad input · 502 translate_failed ·
//         503 not_configured
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

const NAMES: Record<string, string> = {
  en: "English", fr: "French", ar: "Arabic", pt: "Portuguese",
  sw: "Swahili", ha: "Hausa", yo: "Yoruba", ig: "Igbo",
};
const GROQ_URL = "https://api.groq.com/openai/v1/chat/completions";
const MODEL = "llama-3.1-8b-instant"; // fast, generous free allowance
const MAX_CHARS = 1200;

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

  let body: { text?: string; from?: string; to?: string } = {};
  try { body = await req.json(); } catch { body = {}; }
  const text = String(body.text || "").trim().slice(0, MAX_CHARS);
  const from = NAMES[String(body.from || "").trim().toLowerCase()];
  const to = NAMES[String(body.to || "").trim().toLowerCase()];
  if (!text || !from || !to) return json({ error: "bad_input" }, 400);
  if (from === to) return json({ text });

  try {
    const providerStarted = performance.now();
    const r = await fetch(GROQ_URL, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${key}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: MODEL,
        temperature: 0,
        max_tokens: 800,
        messages: [
          { role: "system",
            content: "You are a professional interpreter. Reply with ONLY " +
              "the translation of the user's text, nothing else: no notes, " +
              "no quotation marks, no explanations." },
          { role: "user",
            content: `Translate this from ${from} to ${to}:\n${text}` },
        ],
      }),
    });
    const provider_ms = Math.round(performance.now() - providerStarted);
    if (!r.ok) {
      const detail = (await r.text()).slice(0, 300);
      return json({ error: "translate_failed", status: r.status, detail,
        provider_ms, fn_ms: Math.round(performance.now() - fnStarted) }, 502);
    }
    const data = await r.json();
    const out = String(data?.choices?.[0]?.message?.content || "").trim();
    if (!out) return json({ error: "translate_failed", detail: "empty",
      provider_ms, fn_ms: Math.round(performance.now() - fnStarted) }, 502);
    return json({ text: out, model: MODEL, provider_ms,
      fn_ms: Math.round(performance.now() - fnStarted) });
  } catch (e) {
    return json({ error: "translate_failed", detail: String(e).slice(0, 300),
      fn_ms: Math.round(performance.now() - fnStarted) }, 502);
  }
});
