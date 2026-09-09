// ============================================================================
// WDOS speak — cloud voice fallback for listener devices.
//
// Primary path now uses Azure Speech TTS so Friday languages do not depend on
// browser-installed voices: fr-FR, pt-BR, ar-SA, sw-KE. Groq/Google fallbacks
// remain for resilience while Azure rolls out.
// ============================================================================

export {};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

const AZURE_KEY = (Deno.env.get("AZURE_SPEECH_KEY") || "").trim();
const AZURE_REGION = (Deno.env.get("AZURE_SPEECH_REGION") || "").trim();
const AZURE_ENDPOINT = (Deno.env.get("AZURE_SPEECH_ENDPOINT") || "").trim();

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

const AZURE_VOICES: Record<string, { locale: string; voice: string }> = {
  fr: { locale: "fr-FR", voice: "fr-FR-DeniseNeural" },
  pt: { locale: "pt-BR", voice: "pt-BR-FranciscaNeural" },
  ar: { locale: "ar-SA", voice: "ar-SA-ZariyahNeural" },
  sw: { locale: "sw-KE", voice: "sw-KE-ZuriNeural" },
};

const GROQ_VOICES: Record<string, { model: string; voice: string }> = {
  ar: { model: "canopylabs/orpheus-arabic-saudi", voice: "noura" },
  en: { model: "canopylabs/orpheus-v1-english", voice: "hannah" },
};
const GOOGLE_TTS_LANGS = new Set(["fr", "pt", "sw"]);
const MAX_CHARS = 220;
const GROQ_URL = "https://api.groq.com/openai/v1/audio/speech";
const GOOGLE_TTS_URL = "https://translate.google.com/translate_tts";

async function whoAmI(userJwt: string): Promise<{ id: string } | null> {
  try {
    const r = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
      headers: { apikey: ANON_KEY, Authorization: `Bearer ${userJwt}` },
    });
    if (!r.ok) return null;
    const u = await r.json();
    return u?.id ? { id: u.id } : null;
  } catch { return null; }
}

function azureTtsUrl() {
  if (AZURE_REGION) {
    return `https://${AZURE_REGION}.tts.speech.microsoft.com/cognitiveservices/v1`;
  }
  if (AZURE_ENDPOINT) {
    return AZURE_ENDPOINT.replace(/\/+$/, "") + "/cognitiveservices/v1";
  }
  return "";
}

function configuredLangs() {
  const langs = new Set<string>();
  if (AZURE_KEY && azureTtsUrl()) {
    for (const lang of Object.keys(AZURE_VOICES)) langs.add(lang);
  }
  if ((Deno.env.get("GROQ_API_KEY") || "").trim()) {
    for (const lang of Object.keys(GROQ_VOICES)) langs.add(lang);
  }
  for (const lang of GOOGLE_TTS_LANGS) langs.add(lang);
  return [...langs].sort();
}

function escapeXml(s: string) {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;")
    .replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&apos;");
}

async function azureSpeak(text: string, lang: string): Promise<Response | null> {
  const cfg = AZURE_VOICES[lang];
  const url = azureTtsUrl();
  if (!cfg || !AZURE_KEY || !url) return null;
  const ssml = `<speak version='1.0' xml:lang='${cfg.locale}'><voice xml:lang='${cfg.locale}' name='${cfg.voice}'>${escapeXml(text)}</voice></speak>`;
  const r = await fetch(url, {
    method: "POST",
    headers: {
      "Ocp-Apim-Subscription-Key": AZURE_KEY,
      "Content-Type": "application/ssml+xml",
      "X-Microsoft-OutputFormat": "audio-24khz-48kbitrate-mono-mp3",
      "User-Agent": "WDOS-Azure-Live-Interpreter",
    },
    body: ssml,
  });
  if (!r.ok) return null;
  const bytes = new Uint8Array(await r.arrayBuffer());
  return new Response(bytes, { status: 200, headers: {
    ...CORS,
    "Content-Type": "audio/mpeg",
    "Cache-Control": "no-store",
    "X-WDOS-Voice-Provider": "azure_speech_tts",
  } });
}

async function googleSpeak(text: string, lang: string): Promise<Response | null> {
  if (!GOOGLE_TTS_LANGS.has(lang)) return null;
  const url = new URL(GOOGLE_TTS_URL);
  url.searchParams.set("ie", "UTF-8");
  url.searchParams.set("client", "tw-ob");
  url.searchParams.set("tl", lang);
  url.searchParams.set("q", text);
  const r = await fetch(url, { headers: {
    "User-Agent": "Mozilla/5.0 WDOS-Friday-Audio-QA",
    "Referer": "https://translate.google.com/",
  } });
  if (!r.ok) return null;
  const bytes = new Uint8Array(await r.arrayBuffer());
  return new Response(bytes, { status: 200, headers: {
    ...CORS,
    "Content-Type": "audio/mpeg",
    "Cache-Control": "no-store",
    "X-WDOS-Voice-Provider": "google_translate_tts",
  } });
}

async function groqSpeak(text: string, lang: string): Promise<Response | null> {
  const key = (Deno.env.get("GROQ_API_KEY") || "").trim();
  const cfg = GROQ_VOICES[lang];
  if (!cfg || !key) return null;
  const r = await fetch(GROQ_URL, {
    method: "POST",
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({ model: cfg.model, voice: cfg.voice, input: text,
      response_format: "wav" }),
  });
  if (!r.ok) return null;
  const bytes = new Uint8Array(await r.arrayBuffer());
  return new Response(bytes, { status: 200, headers: {
    ...CORS,
    "Content-Type": "audio/wav",
    "Cache-Control": "no-store",
    "X-WDOS-Voice-Provider": "groq_orpheus",
  } });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method === "GET") {
    const langs = configuredLangs();
    return json({ configured: langs.length > 0, langs,
      azureConfigured: !!(AZURE_KEY && azureTtsUrl()),
      azureVoices: AZURE_VOICES,
      fallback: "azure_speech_tts" });
  }
  if (req.method !== "POST") return json({ error: "method" }, 405);

  const auth = req.headers.get("Authorization") || "";
  const userJwt = auth.replace(/^Bearer\s+/i, "").trim();
  if (!userJwt) return json({ error: "not_signed_in" }, 401);
  const me = await whoAmI(userJwt);
  if (!me) return json({ error: "not_signed_in" }, 401);

  let body: { text?: string; lang?: string } = {};
  try { body = await req.json(); } catch { body = {}; }
  const text = String(body.text || "").trim().slice(0, MAX_CHARS);
  const lang = String(body.lang || "").trim().toLowerCase();
  if (!text || !configuredLangs().includes(lang)) return json({ error: "bad_input" }, 400);

  try {
    const azure = await azureSpeak(text, lang);
    if (azure) return azure;
    const google = await googleSpeak(text, lang);
    if (google) return google;
    const groq = await groqSpeak(text, lang);
    if (groq) return groq;
    return json({ error: "not_configured", lang,
      missing: ["AZURE_SPEECH_KEY or provider voice"] }, 503);
  } catch (e) {
    return json({ error: "speak_failed", detail: String(e).slice(0, 300) }, 502);
  }
});
