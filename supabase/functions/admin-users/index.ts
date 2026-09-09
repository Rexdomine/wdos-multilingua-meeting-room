// ============================================================================
// WDOS admin-users — Phase 131 (HQ account control).
//
// The browser can never hold the service-role key, so anything that touches
// auth.users directly (create a login, set a temporary password, change the
// sign-in email, suspend or restore sign-in, delete an account) runs here.
// The function checks two things before acting: the caller is signed in,
// and the caller currently holds an HQ role (super_admin, executive_director
// or hq_team). Everyone else gets 403.
//
// Passwords: a temporary password is generated here (or supplied by HQ),
// returned ONCE in the response so HQ can hand it over, and never stored or
// logged anywhere. The member changes it on first sign-in from the
// dashboard. HQ can issue a new one at any time.
//
// Deploy WITHOUT any CLI: Supabase Dashboard → Edge Functions →
// Deploy a new function → name it exactly  admin-users  → paste this whole
// file → Verify JWT ON → Deploy. No new secret is needed: SUPABASE_URL,
// SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY are injected automatically.
//
// Invocation (from WDOS): supabase.functions.invoke('admin-users',
//   { body: { action, ...fields } })
//
// Actions and bodies:
//   create   { email, password?, first_name, last_name, network, phone?,
//              country?, state_region?, lga?, role_applied?, is_leader?,
//              member_code? }            → { id, email, temp_password }
//   set_password { id, password? }       → { id, temp_password }
//   set_email    { id, email }           → { id, email }
//   ban          { id, on: true|false }  → { id, banned }
//   delete       { id }                  → { id, deleted: true }
//   ping         {}                      → { ok: true, hq: true }
//
// Errors: 401 not signed in · 403 not HQ · 400 bad input ·
//         409 email already registered · 502 auth service error
// ============================================================================

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") || "";
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";

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

const HQ_ROLES = ["super_admin", "executive_director", "hq_team"];
const LEADER_ROLES = ["country_rep", "deputy_country_rep", "state_coordinator",
  "assistant_state_coordinator", "district_coordinator", "chapter_lead"];

// ---------------------------------------------------------------- who is calling
async function whoAmI(userJwt: string) {
  const res = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
    headers: { Authorization: `Bearer ${userJwt}`, apikey: ANON_KEY || SERVICE_KEY },
  });
  if (!res.ok) return null;
  const u = await res.json();
  return u && u.id ? { id: String(u.id), email: String(u.email || "") } : null;
}

// Service-role read of role_assignments: does the caller hold an HQ seat now?
async function callerIsHq(uid: string): Promise<boolean> {
  const url = `${SUPABASE_URL}/rest/v1/role_assignments?select=role` +
    `&profile_id=eq.${uid}&ends_at=is.null&role=in.(${HQ_ROLES.join(",")})&limit=1`;
  const res = await fetch(url, {
    headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}` },
  });
  if (!res.ok) return false;
  const rows = await res.json();
  return Array.isArray(rows) && rows.length > 0;
}

// Service-role read: is the target an HQ super admin? (protected from deletion
// and suspension by anyone but another super admin)
async function targetRoles(uid: string): Promise<string[]> {
  const url = `${SUPABASE_URL}/rest/v1/role_assignments?select=role` +
    `&profile_id=eq.${uid}&ends_at=is.null`;
  const res = await fetch(url, {
    headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}` },
  });
  if (!res.ok) return [];
  const rows = await res.json();
  return Array.isArray(rows) ? rows.map((r: { role: string }) => String(r.role)) : [];
}

// ---------------------------------------------------------------- helpers
// 12 characters, unambiguous alphabet (no 0/O, 1/l/I), always has a digit
// and both cases. Shown once to HQ; never stored by this function.
function tempPassword(): string {
  const upper = "ABCDEFGHJKMNPQRSTUVWXYZ";
  const lower = "abcdefghjkmnpqrstuvwxyz";
  const digits = "23456789";
  const all = upper + lower + digits;
  const pick = (set: string) => set[crypto.getRandomValues(new Uint32Array(1))[0] % set.length];
  const chars = [pick(upper), pick(lower), pick(digits)];
  while (chars.length < 12) chars.push(pick(all));
  // shuffle
  for (let i = chars.length - 1; i > 0; i -= 1) {
    const j = crypto.getRandomValues(new Uint32Array(1))[0] % (i + 1);
    [chars[i], chars[j]] = [chars[j], chars[i]];
  }
  return chars.join("");
}

function validEmail(e: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(e);
}

async function adminAuth(path: string, method: string, body?: unknown) {
  const res = await fetch(`${SUPABASE_URL}/auth/v1/admin/${path}`, {
    method,
    headers: {
      apikey: SERVICE_KEY,
      Authorization: `Bearer ${SERVICE_KEY}`,
      "Content-Type": "application/json",
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  let data: Record<string, unknown> = {};
  try { data = await res.json(); } catch { data = {}; }
  return { ok: res.ok, status: res.status, data };
}

async function patchProfile(uid: string, patch: Record<string, unknown>) {
  const clean: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(patch)) {
    if (v !== undefined && v !== null && v !== "") clean[k] = v;
  }
  if (Object.keys(clean).length === 0) return true;
  const res = await fetch(`${SUPABASE_URL}/rest/v1/profiles?id=eq.${uid}`, {
    method: "PATCH",
    headers: {
      apikey: SERVICE_KEY,
      Authorization: `Bearer ${SERVICE_KEY}`,
      "Content-Type": "application/json",
      Prefer: "return=minimal",
    },
    body: JSON.stringify(clean),
  });
  return res.ok;
}

// ---------------------------------------------------------------- main
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  if (!SERVICE_KEY) return json({ error: "not_configured", missing: ["SUPABASE_SERVICE_ROLE_KEY"] }, 503);

  const auth = req.headers.get("Authorization") || "";
  const userJwt = auth.replace(/^Bearer\s+/i, "").trim();
  if (!userJwt) return json({ error: "not_signed_in" }, 401);
  const me = await whoAmI(userJwt);
  if (!me) return json({ error: "not_signed_in" }, 401);
  if (!(await callerIsHq(me.id))) return json({ error: "hq_only" }, 403);

  let body: Record<string, unknown> = {};
  try { body = await req.json(); } catch { body = {}; }
  const action = String(body.action || "");
  const str = (k: string) => (body[k] === undefined || body[k] === null) ? "" : String(body[k]).trim();

  try {
    if (action === "ping") return json({ ok: true, hq: true });

    // ---------------------------------------------------------------- create
    if (action === "create") {
      const email = str("email").toLowerCase();
      const first = str("first_name"), last = str("last_name");
      const network = str("network").toUpperCase();
      if (!validEmail(email)) return json({ error: "bad_email" }, 400);
      if (first.length < 1 || last.length < 1) return json({ error: "name_required" }, 400);
      if (!["WGMN", "WNNN"].includes(network)) return json({ error: "bad_network" }, 400);
      const password = str("password") || tempPassword();
      if (password.length < 8) return json({ error: "password_short" }, 400);

      const created = await adminAuth("users", "POST", {
        email,
        password,
        email_confirm: true,
        user_metadata: {
          first_name: first, last_name: last, network,
          phone: str("phone") || undefined,
          created_by_hq: me.id,
        },
      });
      if (!created.ok) {
        const msg = String(created.data?.msg || created.data?.message || created.data?.error || "");
        if (/already|exists|registered|duplicate/i.test(msg)) return json({ error: "email_exists", detail: msg }, 409);
        return json({ error: "auth_error", detail: msg || created.status }, 502);
      }
      const uid = String(created.data?.id || (created.data?.user as { id?: string } | undefined)?.id || "");
      if (!uid) return json({ error: "auth_error", detail: "no id returned" }, 502);

      // handle_new_user created the profile from the metadata; enrich it.
      const isLeader = body.is_leader === true || String(body.is_leader) === "true";
      await patchProfile(uid, {
        phone: str("phone"),
        country: str("country"),
        state_region: str("state_region"),
        lga: str("lga"),
        role_applied: str("role_applied"),
        is_leader: isLeader ? true : undefined,
        membership_no: str("member_code") || undefined,
      });
      return json({ id: uid, email, temp_password: password });
    }

    // ---------------------------------------------------------------- targeted
    const id = str("id");
    if (!id) return json({ error: "id_required" }, 400);

    if (action === "set_password") {
      const password = str("password") || tempPassword();
      if (password.length < 8) return json({ error: "password_short" }, 400);
      const r = await adminAuth(`users/${id}`, "PUT", { password });
      if (!r.ok) return json({ error: "auth_error", detail: r.data?.msg || r.status }, 502);
      return json({ id, temp_password: password });
    }

    if (action === "set_email") {
      const email = str("email").toLowerCase();
      if (!validEmail(email)) return json({ error: "bad_email" }, 400);
      const r = await adminAuth(`users/${id}`, "PUT", { email, email_confirm: true });
      if (!r.ok) {
        const msg = String(r.data?.msg || r.data?.message || "");
        if (/already|exists|registered|duplicate/i.test(msg)) return json({ error: "email_exists", detail: msg }, 409);
        return json({ error: "auth_error", detail: msg || r.status }, 502);
      }
      const ok = await patchProfile(id, { email });
      return json({ id, email, profile_updated: ok });
    }

    if (action === "ban") {
      if (id === me.id) return json({ error: "cannot_ban_self" }, 400);
      const roles = await targetRoles(id);
      if (roles.includes("super_admin")) return json({ error: "protected_account" }, 403);
      const on = body.on === true || String(body.on) === "true";
      // 100 years = suspended; "none" = restored
      const r = await adminAuth(`users/${id}`, "PUT", { ban_duration: on ? "876000h" : "none" });
      if (!r.ok) return json({ error: "auth_error", detail: r.data?.msg || r.status }, 502);
      return json({ id, banned: on });
    }

    if (action === "delete") {
      if (id === me.id) return json({ error: "cannot_delete_self" }, 400);
      const roles = await targetRoles(id);
      if (roles.includes("super_admin")) return json({ error: "protected_account" }, 403);
      const r = await adminAuth(`users/${id}`, "DELETE");
      if (!r.ok) return json({ error: "auth_error", detail: r.data?.msg || r.status }, 502);
      // profiles.id references auth.users on delete cascade: the profile,
      // her role seats, tasks comments and notices go with the login.
      return json({ id, deleted: true });
    }

    return json({ error: "unknown_action" }, 400);
  } catch (err) {
    return json({ error: "server_error", detail: String((err as Error)?.message || err) }, 500);
  }
});
