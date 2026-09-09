# WDOS — Setup & Deployment (Phase 1)

## What this phase contains

A complete, working vertical slice of WDOS:

- **Database foundation** (migrations 001–002): full organisational hierarchy
  (HQ → Country → State/Region → District/LGA → Chapter), profiles with the
  12-status membership lifecycle and enforced transitions, time-bounded role
  assignments with history, an append-only audit log with triggers on every
  core table, and Row Level Security that scopes every query to the user's
  administered subtree.
- **Application shell**: config loader (no hard-coded environment values),
  hash router with auth guards, i18n layer (8 locales supported, English +
  French shipped, automatic fallback), XSS-safe DOM helpers, toasts,
  offline banner, responsive sidebar shell in WODDI brand colours.
- **Working modules**: Sign-in, Dashboard (live RLS-scoped counts), and
  Members (search, filter, pagination, detail view, editing with validation,
  lifecycle-aware status changes with an audit reason recorded atomically).

Nothing in this build is a placeholder. Modules not yet built simply do not
appear in the navigation.

## 1. Supabase

1. Create a project at https://supabase.com (region: choose the closest to
   your primary user base — `eu-west-2` or `eu-central-1` currently give the
   best latency to West Africa).
2. In the SQL editor, run the migrations **in order**:
   - **every** file in `supabase/migrations/`, in numeric order,
     `001_…` through the highest number present (currently `067_…`).
     Running only the first two leaves most of WDOS without its tables —
     tasks, messages, reports, HQ operations and everything after
     migration 002 would simply not exist. The in-app System Health
     check (and `#/doctor`) will tell you which versions are missing.
3. Seed the organisational root and your own admin role (replace the email
   with the account you will create in step 4):

```sql
insert into public.org_units (level, name) values ('headquarters', 'WODDI HQ');
```

4. In **Authentication → Users**, create your first user (email + password).
   The `on_auth_user_created` trigger creates the matching profile row.
5. Grant yourself Super Administrator (run as the `postgres` role in the SQL
   editor, which bypasses RLS):

```sql
insert into public.role_assignments (profile_id, role, org_unit_id)
select p.id, 'super_admin', o.id
from public.profiles p, public.org_units o
where p.email = 'you@thewoddi.org' and o.level = 'headquarters';
```

6. **Authentication → Providers**: enable Email. Disable public sign-ups
   (Settings → "Allow new users to sign up" → off) — recruitment flows will
   create accounts through a controlled pipeline in a later phase.
7. **Authentication → MFA**: enable TOTP. Enforce enrolment for leadership
   roles as part of your rollout policy.

## 2. Application configuration

Copy `app/config.example.json` to `app/config.json` and fill in your
project's URL and anon key (Settings → API in Supabase). The anon key is
safe to publish: all authority comes from RLS, not from the key.

## 3. Get the Supabase client file (no tools needed)

The app keeps its own copy of the Supabase client library so it never
depends on anyone else's server at runtime.

1. In your browser, open:
   `https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/dist/umd/supabase.js`
2. Save the page (Ctrl+S / Cmd+S) as a file named exactly `supabase.js`.
3. Inside the project, create the folder `app/assets/vendor/` and put the
   file there, so the path is `app/assets/vendor/supabase.js`.

That's it. `index.html` loads this local file before the app starts.
(Node.js and npm are NOT required anywhere in this project.)

## 3b. (Optional) The Africa coverage map

Reports can show a live map of WODDI's presence across Africa. Like the
Supabase client, you download the map file once:

1. Open in your browser:
   `https://www.amcharts.com/lib/3/maps/svg/africaLow.svg`
   (a free map whose country shapes carry standard two-letter country ids).
2. Save it (Ctrl+S / Cmd+S) named exactly `africa.svg`.
3. Put it in `app/assets/vendor/` next to `supabase.js`.

Without the file, Reports shows the same coverage as a text list — nothing
breaks.

## 4. Netlify

1. Connect the repository; `netlify.toml` already sets the publish directory
   to `app/` and applies security headers (CSP, frame denial, etc.).
2. For separate staging/production environments, serve a different
   `config.json` per site — the code never changes between environments.

## 5. Local development

```bash
cd app && python3 -m http.server 8080
# then open http://localhost:8080
```

Any static file server works; there is no build step for the app itself.

## 6. Verifying the security model

After setup, confirm with two accounts:

- A `chapter_lead` assigned to one chapter sees **only** profiles in that
  chapter; a `country_rep` sees the whole country subtree.
- A member editing their own profile can change contact details but gets
  "You may only edit your contact details" when attempting to change their
  own status (column guard).
- An invalid lifecycle jump (e.g. `applicant → active`) is rejected by the
  database regardless of what any client sends.
- Every insert/update/delete on `org_units`, `profiles`, and
  `role_assignments` appears in `audit_log`, and `update`/`delete` against
  `audit_log` itself fails.
