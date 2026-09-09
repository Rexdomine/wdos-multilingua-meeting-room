# Phase 88 — HQ ↔ Member Messaging & True Push (v54.0, schema 67)

What this phase delivers:

1. **HQ can message any member personally.** New message → the picker now
   lists field members (searchable by name, email, or Volunteer ID) as well
   as staff. Every member detail page also has a **Message** button.
2. **Members reply from `#/me`.** A "Messages — WODDI HQ ✓" card sits on
   the member home: full conversation, reply box, live updates. The
   *Message HQ* quick button now jumps straight to it.
3. **The verified voice.** To a member, every HQ-side sender appears as
   **WODDI HQ** with a green tick. The tick is decided by the database
   from staff and role records — a profile renaming itself "WODDI HQ"
   gets nothing.
4. **True push — browser closed.** Registered devices receive
   notifications for direct messages, task assignments, meetings and
   journey notices even with no WDOS tab open.
5. Audit fixes: Reports page no longer dies when one analytics RPC fails
   (and `people_analytics` itself is repaired), the Tasks list/board/
   calendar buttons now actually appear, `fmtDate` import fixed, SETUP.md
   migration instructions corrected.

---

## Deploy — in this order

### 1. Run the migration
SQL editor → paste and run
`supabase/migrations/067_hq_member_messaging_push.sql`.
System Health should then show **schema 67**.

### 2. Deploy the Edge Function (no CLI — dashboard only)
Supabase Dashboard → **Edge Functions** → **Deploy a new function**
→ name it exactly `push-send` → delete the sample code → paste the whole
of `supabase/functions/push-send/index.ts` → **Deploy**.

You have already stored the three secrets
(`VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`, `VAPID_SUBJECT`)
under Edge Functions → Secrets. The function reads them from there.

### 3. Tell the database how to kick the function
SQL editor → run (values pre-filled for your project):

```sql
select set_push_secret('push_fn_url',
  'https://vhudbuprjpsyizporkcn.supabase.co/functions/v1/push-send');
select set_push_secret('push_fn_key',
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZodWRidXByanBzeWl6cG9ya2NuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQyNzA1ODIsImV4cCI6MjA5OTg0NjU4Mn0.tc0exijzOLOoltFrLK3MIYaymB5Ipp3ZhF1S5LsXEAA');
```

(That second value is the anon key — public by design; the function is
JWT-gated and does its real work with its own service-role environment.)

### 4. Deploy the app
Drag the `app` folder to **both** Netlify sites. Corner badge must read
**build v54.0 · db 67**.

### 5. Enable push on each device
On any dashboard, press the existing **Enable notifications** button
(sidebar footer, or #/me → profile). Grant the permission; you should see
"Push enabled on this device". Each phone/laptop is registered
separately.

### 6. Test the whole loop
1. Master account → Members → open any member → **Message** → send.
2. That member's `#/me` shows the message under **Messages — WODDI HQ ✓**
   (live, no refresh), and their registered devices get a push titled
   **WODDI HQ** — even with the browser closed.
3. Member types a reply in the same card → it lands in the master
   account's Messages page.
4. `#/doctor` now has a **Web push** row: it reports this device's state
   and whether the function URL/key are set.

---

## Honest limits (say this to testers before Friday)

- **Chrome / Edge on Windows and Android:** closed-browser delivery works.
- **macOS:** a fully *quit* browser delivers when next opened.
- **iPhone / iPad:** push works **only** when WDOS is installed to the
  home screen (Safari → Share → *Add to Home Screen*), on iOS 16.4+.
  In-tab alerts work regardless.
- Delivery for announcements is not pushed yet (bell + in-tab only);
  direct messages, tasks, meetings and journey notices are.

## Troubleshooting

- Push row in `#/doctor` says *fn url MISSING* → step 3 not run.
- `push_outbox` rows with `error` text → open the row's error; `push 404/
  410` means the device unsubscribed (auto-pruned), anything else usually
  means the Edge Function secrets are wrong.
- No push but bell works → the device was never enrolled (step 5), or the
  browser is one of the limited platforms above.
