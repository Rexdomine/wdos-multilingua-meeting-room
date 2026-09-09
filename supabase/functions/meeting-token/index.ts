// ============================================================================
// WDOS meeting-token — Phase 124 (embedded call, no time limit).
//
// Mints a short-lived meeting token for the signed-in WDOS member so the
// meeting engine (Jitsi as a Service on 8x8.vc) can be embedded INSIDE the
// WDOS room page. The public meet.jit.si server cuts embedded calls at
// five minutes; the managed engine has no such limit, but it admits people
// only with a token signed by our private key. WDOS already knows who the
// person is, so the token carries her name, email and whether she is HQ
// staff (moderator). The private key never leaves this function.
//
// Deploy WITHOUT any CLI: Supabase Dashboard → Edge Functions →
// Deploy a new function → name it exactly  meeting-token  → paste this
// whole file → Deploy.
//
// Secrets it reads (Dashboard → Edge Functions → Secrets):
//   JAAS_APP_ID          the App ID from the JaaS console
//                        (looks like vpaas-magic-cookie-1234abcd...)
//   JAAS_KID             the API key id. Short form ("a1b2c3") or full form
//                        ("vpaas-magic-cookie-.../a1b2c3") both work.
//   JAAS_PRIVATE_KEY     the private key file the JaaS console downloaded
//                        when the API key was generated, pasted as text.
//                        Multi-line is fine; "\n" written as two characters
//                        is also fine. PKCS#8 ("BEGIN PRIVATE KEY") and
//                        PKCS#1 ("BEGIN RSA PRIVATE KEY") are both accepted.
//   JAAS_PRIVATE_KEY_B64 optional alternative: the same file base64-encoded.
// SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY are injected
// automatically by Supabase.
//
// Invocation: the WDOS app calls it with the member's own session token
// (supabase.functions.invoke('meeting-token', { body: { room } })).
// Response: { jwt, appId, domain, exp, moderator }.
// Errors:    401 not signed in · 400 bad room name ·
//            503 { error: 'not_configured', missing: [...] } when secrets
//            are absent (the app then falls back to the open-tab call).
// ============================================================================

import { SignJWT, importPKCS8 } from "npm:jose@5.9.6";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") || "";
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";

const JAAS_DOMAIN = "8x8.vc";
const TOKEN_HOURS = 4;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

// ---------------------------------------------------------------- key helpers
function b64ToBytes(b64: string): Uint8Array {
  const bin = atob(b64.replace(/\s+/g, ""));
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i += 1) out[i] = bin.charCodeAt(i);
  return out;
}
function bytesToB64(bytes: Uint8Array): string {
  let s = "";
  for (let i = 0; i < bytes.length; i += 1) s += String.fromCharCode(bytes[i]);
  return btoa(s);
}
// DER length encoding (definite form).
function derLen(n: number): number[] {
  if (n < 0x80) return [n];
  const bytes: number[] = [];
  let v = n;
  while (v > 0) { bytes.unshift(v & 0xff); v >>= 8; }
  return [0x80 | bytes.length, ...bytes];
}
// Wrap a PKCS#1 RSAPrivateKey DER in the PKCS#8 PrivateKeyInfo structure:
// SEQUENCE { INTEGER 0, SEQUENCE { OID rsaEncryption, NULL }, OCTET STRING { pkcs1 } }
function pkcs1ToPkcs8(pkcs1: Uint8Array): Uint8Array {
  const version = [0x02, 0x01, 0x00];
  const algId = [0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d,
    0x01, 0x01, 0x01, 0x05, 0x00];
  const octet = [0x04, ...derLen(pkcs1.length)];
  const bodyLen = version.length + algId.length + octet.length + pkcs1.length;
  const head = [0x30, ...derLen(bodyLen)];
  const out = new Uint8Array(head.length + bodyLen);
  let o = 0;
  for (const part of [head, version, algId, octet]) {
    out.set(part, o); o += part.length;
  }
  out.set(pkcs1, o);
  return out;
}
function pemBody(pem: string, label: string): string | null {
  const m = pem.match(new RegExp(
    `-----BEGIN ${label}-----([\\s\\S]*?)-----END ${label}-----`));
  return m ? m[1].replace(/\s+/g, "") : null;
}
// Returns a PKCS#8 PEM whatever form the secret arrived in.
function normalisePrivateKey(): string | null {
  let pem = Deno.env.get("JAAS_PRIVATE_KEY") || "";
  const b64 = Deno.env.get("JAAS_PRIVATE_KEY_B64") || "";
  if (!pem && b64) {
    try { pem = new TextDecoder().decode(b64ToBytes(b64)); } catch { pem = ""; }
  }
  pem = pem.replace(/\\n/g, "\n").replace(/\r/g, "").trim();
  if (!pem) return null;
  const p8 = pemBody(pem, "PRIVATE KEY");
  if (p8) return `-----BEGIN PRIVATE KEY-----\n${p8}\n-----END PRIVATE KEY-----`;
  const p1 = pemBody(pem, "RSA PRIVATE KEY");
  if (p1) {
    const wrapped = bytesToB64(pkcs1ToPkcs8(b64ToBytes(p1)));
    return `-----BEGIN PRIVATE KEY-----\n${wrapped}\n-----END PRIVATE KEY-----`;
  }
  // Bare base64 without armour: assume PKCS#8.
  if (/^[A-Za-z0-9+/=]+$/.test(pem)) {
    return `-----BEGIN PRIVATE KEY-----\n${pem}\n-----END PRIVATE KEY-----`;
  }
  return null;
}

// ---------------------------------------------------------------- who is calling
async function whoAmI(userJwt: string) {
  const res = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
    headers: { Authorization: `Bearer ${userJwt}`, apikey: ANON_KEY || SERVICE_KEY },
  });
  if (!res.ok) return null;
  const u = await res.json();
  return u && u.id ? { id: String(u.id), email: String(u.email || "") } : null;
}
async function isStaff(userJwt: string): Promise<boolean> {
  try {
    const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/am_i_staff`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${userJwt}`,
        apikey: ANON_KEY || SERVICE_KEY,
        "Content-Type": "application/json",
      },
      body: "{}",
    });
    if (!res.ok) return false;
    return (await res.json()) === true;
  } catch { return false; }
}
async function profileOf(uid: string) {
  try {
    const q = `profiles?id=eq.${encodeURIComponent(uid)}` +
      `&select=first_name,last_name,email`;
    const res = await fetch(`${SUPABASE_URL}/rest/v1/${q}`, {
      headers: { Authorization: `Bearer ${SERVICE_KEY}`, apikey: SERVICE_KEY },
    });
    if (!res.ok) return null;
    const rows = await res.json();
    return Array.isArray(rows) && rows[0] ? rows[0] : null;
  } catch { return null; }
}

// ---------------------------------------------------------------- handler
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "method" }, 405);

  const appId = (Deno.env.get("JAAS_APP_ID") || "").trim();
  const kidRaw = (Deno.env.get("JAAS_KID") || "").trim();
  const pem = normalisePrivateKey();
  const missing: string[] = [];
  if (!appId) missing.push("JAAS_APP_ID");
  if (!kidRaw) missing.push("JAAS_KID");
  if (!pem) missing.push("JAAS_PRIVATE_KEY");
  if (missing.length) return json({ error: "not_configured", missing }, 503);

  const auth = req.headers.get("Authorization") || "";
  const userJwt = auth.replace(/^Bearer\s+/i, "").trim();
  if (!userJwt) return json({ error: "not_signed_in" }, 401);
  const me = await whoAmI(userJwt);
  if (!me) return json({ error: "not_signed_in" }, 401);

  let body: { room?: string } = {};
  try { body = await req.json(); } catch { body = {}; }
  const room = String(body.room || "").trim();
  if (!/^[A-Za-z0-9_-]{3,60}$/.test(room)) return json({ error: "bad_room" }, 400);

  const [staff, prof] = await Promise.all([isStaff(userJwt), profileOf(me.id)]);
  const name = `${prof?.first_name || ""} ${prof?.last_name || ""}`.trim() ||
    (me.email ? me.email.split("@")[0] : "WODDI");
  const email = String(prof?.email || me.email || "");

  // JaaS expects the key id as "<appId>/<keyId>"; accept either form.
  const kid = kidRaw.includes("/") ? kidRaw : `${appId}/${kidRaw}`;

  let key;
  try { key = await importPKCS8(pem!, "RS256"); }
  catch (e) {
    return json({ error: "bad_private_key", detail: String(e?.message || e) }, 500);
  }

  const now = Math.floor(Date.now() / 1000);
  const exp = now + TOKEN_HOURS * 3600;
  const jwt = await new SignJWT({
    aud: "jitsi",
    iss: "chat",
    sub: appId,
    room,
    context: {
      user: {
        id: me.id,
        name,
        email,
        avatar: "",
        moderator: staff,
      },
      features: {
        livestreaming: false,
        recording: false,
        transcription: false,
        "outbound-call": false,
      },
    },
  })
    .setProtectedHeader({ alg: "RS256", kid, typ: "JWT" })
    .setNotBefore(now - 10)
    .setExpirationTime(exp)
    .sign(key);

  return json({ jwt, appId, domain: JAAS_DOMAIN, exp, moderator: staff });
});
