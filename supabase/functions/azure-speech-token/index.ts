// ============================================================================
// WDOS azure-speech-token — Azure Speech Translation short-lived token mint.
//
// Browser clients must never receive AZURE_SPEECH_KEY. This function verifies
// the caller is a signed-in Supabase user, then exchanges the private Azure key
// for a short-lived Speech authorization token. The app uses that token with
// Azure Speech SDK browser streaming translation.
//
// Secrets required:
//   AZURE_SPEECH_KEY
//   AZURE_SPEECH_REGION     e.g. uksouth
//   AZURE_SPEECH_ENDPOINT   e.g. https://uksouth.api.cognitive.microsoft.com/
// ============================================================================

export {};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") || "";
const AZURE_KEY = Deno.env.get("AZURE_SPEECH_KEY") || "";
const AZURE_REGION = (Deno.env.get("AZURE_SPEECH_REGION") || "").trim();
const AZURE_ENDPOINT = (Deno.env.get("AZURE_SPEECH_ENDPOINT") || "").trim();

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

async function currentUser(req: Request) {
  const auth = req.headers.get("Authorization") || "";
  if (!auth.toLowerCase().startsWith("bearer ")) return null;
  const res = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
    headers: { Authorization: auth, apikey: ANON_KEY },
  });
  if (!res.ok) return null;
  return await res.json();
}

function tokenEndpoint() {
  if (AZURE_ENDPOINT) {
    return AZURE_ENDPOINT.replace(/\/+$/, "") + "/sts/v1.0/issueToken";
  }
  if (AZURE_REGION) {
    return `https://${AZURE_REGION}.api.cognitive.microsoft.com/sts/v1.0/issueToken`;
  }
  return "";
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS });
  if (!["GET", "POST"].includes(req.method)) return json({ error: "method" }, 405);

  const missing = [];
  if (!AZURE_KEY) missing.push("AZURE_SPEECH_KEY");
  if (!AZURE_REGION) missing.push("AZURE_SPEECH_REGION");
  if (!tokenEndpoint()) missing.push("AZURE_SPEECH_ENDPOINT");
  if (missing.length) return json({ configured: false, missing }, 503);

  const user = await currentUser(req).catch(() => null);
  if (!user?.id) return json({ error: "unauthorized" }, 401);

  try {
    const started = performance.now();
    const res = await fetch(tokenEndpoint(), {
      method: "POST",
      headers: {
        "Ocp-Apim-Subscription-Key": AZURE_KEY,
        "Content-Type": "application/x-www-form-urlencoded",
      },
    });
    const token = await res.text();
    if (!res.ok || !token) {
      return json({ error: "azure_token_failed", status: res.status }, 502);
    }
    return json({
      configured: true,
      provider: "azure_speech_translation",
      token,
      region: AZURE_REGION,
      endpoint: AZURE_ENDPOINT,
      source: "en-US",
      targets: ["fr", "pt", "ar", "sw"],
      voices: { fr: "fr-FR", pt: "pt-BR", ar: "ar-SA", sw: "sw-KE" },
      expires_in_seconds: 540,
      fn_ms: Math.round(performance.now() - started),
    });
  } catch (err) {
    return json({ error: "token_exception", message: String(err?.message || err) }, 502);
  }
});
