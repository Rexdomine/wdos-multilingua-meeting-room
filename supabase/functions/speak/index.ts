// ============================================================================
// WDOS speak — Phase 128 (cloud voice for languages a device cannot speak).
//
// Most Windows laptops and Android phones have no Arabic voice installed,
// so an Arabic listener saw the correct translation on screen and heard
// nothing. This function turns text into speech with Groq's Orpheus
// models (Arabic and English) using the SAME free GROQ_API_KEY as the
// transcribe function. The room asks for it only when the device itself
// has no voice for the language; device voices stay first because they
// are instant and unlimited.
//
// Deploy WITHOUT any CLI: Supabase Dashboard → Edge Functions →
// Deploy a new function → name it exactly  speak  → paste this whole
// file → Deploy. Leave "Verify JWT" on. No new secret: GROQ_API_KEY is
// already there from Phase 127.
//
// Invocation from the app:
//   GET  → { configured, langs: ['ar','en'] }
//   POST { text, lang }  → audio/wav bytes (or JSON error)
// Errors: 401 not signed in · 400 bad input · 502 speak_failed ·
//         503 not_configured
// Note: the English model may ask you to accept its terms once in the
// Groq Playground (console.groq.com/playground, model
// canopylabs/orpheus-v1-english). English devices normally have their
// own voice, so this only matters if you want the cloud English voice.
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

// Language → Groq model + a clear female voice (WODDI is a women's
// organisation; change the voice names here if a different one suits).
const VOICES: Record<string, { model: string; voice: string }> = {
  ar: { model: "canopylabs/orpheus-arabic-saudi", voice: "noura" },
  en: { model: "canopylabs/orpheus-v1-english", voice: "hannah" },
};
const MAX_CHARS = 200; // the Arabic model's published input limit
const GROQ_URL = "https://api.groq.com/openai/v1/audio/speech";

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
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  const key = (Deno.env.get("GROQ_API_KEY") || "").trim();
  if (req.method === "GET") {
    return json({ configured: !!key, langs: key ? Object.keys(VOICES) : [] });
  }
  if (req.method !== "POST") return json({ error: "method" }, 405);
  if (!key) return json({ error: "not_configured", missing: ["GROQ_API_KEY"] }, 503);

  const auth = req.headers.get("Authorization") || "";
  const userJwt = auth.replace(/^Bearer\s+/i, "").trim();
  if (!userJwt) return json({ error: "not_signed_in" }, 401);
  const me = await whoAmI(userJwt);
  if (!me) return json({ error: "not_signed_in" }, 401);

  let body: { text?: string; lang?: string } = {};
  try { body = await req.json(); } catch { body = {}; }
  const text = String(body.text || "").trim().slice(0, MAX_CHARS);
  const lang = String(body.lang || "").trim().toLowerCase();
  const cfg = VOICES[lang];
  if (!text || !cfg) return json({ error: "bad_input" }, 400);

  try {
    const r = await fetch(GROQ_URL, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${key}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: cfg.model,
        voice: cfg.voice,
        input: text,
        response_format: "wav",
      }),
    });
    if (!r.ok) {
      const detail = (await r.text()).slice(0, 300);
      return json({ error: "speak_failed", status: r.status, detail }, 502);
    }
    const bytes = new Uint8Array(await r.arrayBuffer());
    return new Response(bytes, {
      status: 200,
      headers: {
        ...CORS,
        "Content-Type": "audio/wav",
        "Cache-Control": "no-store",
      },
    });
  } catch (e) {
    return json({ error: "speak_failed", detail: String(e).slice(0, 300) }, 502);
  }
});
