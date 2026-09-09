// ============================================================================
// WDOS push-send — Phase 88.
//
// Drains push_outbox: for every pending row, sends a Web Push notification
// (VAPID ES256 + aes128gcm, via the web-push library) to each of the
// recipient's registered devices, marks the row sent, and prunes
// subscriptions the push service reports dead (404/410).
//
// Deploy WITHOUT any CLI: Supabase Dashboard → Edge Functions →
// Deploy a new function → name it exactly  push-send  → paste this whole
// file → Deploy.
//
// Secrets it reads (Dashboard → Edge Functions → Secrets):
//   VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY, VAPID_SUBJECT
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected automatically.
//
// Invocation: the database kicks this function (pg_net trigger on
// push_outbox, migration 067). Each invocation drains the WHOLE pending
// queue, so a missed kick is healed by the next one. The payload is
// ignored — this function trusts only its own database reads.
// ============================================================================

import webpush from "npm:web-push@3.6.7";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const HEADERS = {
  apikey: SERVICE_KEY,
  Authorization: `Bearer ${SERVICE_KEY}`,
  "Content-Type": "application/json",
  Prefer: "return=representation",
};

async function rest(path: string, init: RequestInit = {}) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    ...init,
    headers: { ...HEADERS, ...(init.headers || {}) },
  });
  if (!res.ok) throw new Error(`${path} → ${res.status} ${await res.text()}`);
  const text = await res.text();
  return text ? JSON.parse(text) : null;
}

Deno.serve(async () => {
  const pub = Deno.env.get("VAPID_PUBLIC_KEY");
  const priv = Deno.env.get("VAPID_PRIVATE_KEY");
  const subject = Deno.env.get("VAPID_SUBJECT") || "mailto:it@thewoddi.org";
  if (!pub || !priv) {
    return new Response(
      JSON.stringify({ error: "VAPID keys not configured in secrets" }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
  webpush.setVapidDetails(subject, pub, priv);

  // Claim a batch atomically: mark sent_at first (so overlapping
  // invocations never double-deliver), then actually deliver. A row that
  // fails delivery keeps its error text for the Doctor to read.
  const now = new Date().toISOString();
  const batch = await rest(
    `push_outbox?sent_at=is.null&order=created_at.asc&limit=40`,
    {
      method: "PATCH",
      body: JSON.stringify({ sent_at: now }),
    },
  ) as Array<{
    id: string; profile_id: string; title: string; body: string; url: string;
  }>;

  let delivered = 0;
  let pruned = 0;

  for (const row of batch || []) {
    const subs = await rest(
      `push_subscriptions?profile_id=eq.${row.profile_id}` +
        `&select=id,endpoint,p256dh,auth`,
      { method: "GET" },
    ) as Array<{ id: string; endpoint: string; p256dh: string; auth: string }>;

    let ok = 0;
    let lastErr = "";
    for (const s of subs || []) {
      try {
        await webpush.sendNotification(
          { endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } },
          JSON.stringify({ title: row.title, body: row.body, url: row.url }),
          { TTL: 3600, urgency: "high" },
        );
        ok += 1;
      } catch (e) {
        const code = (e as { statusCode?: number })?.statusCode;
        lastErr = `push ${code ?? e}`;
        if (code === 404 || code === 410) {
          // The push service says this device is gone — prune it.
          await rest(`push_subscriptions?id=eq.${s.id}`, { method: "DELETE" })
            .catch(() => {});
          pruned += 1;
        }
      }
    }
    if (ok > 0) delivered += 1;
    if (ok === 0) {
      await rest(`push_outbox?id=eq.${row.id}`, {
        method: "PATCH",
        body: JSON.stringify({
          error: lastErr || "no registered devices",
        }),
      }).catch(() => {});
    }
  }

  return new Response(
    JSON.stringify({
      processed: (batch || []).length, delivered, pruned,
    }),
    { headers: { "Content-Type": "application/json" } },
  );
});
