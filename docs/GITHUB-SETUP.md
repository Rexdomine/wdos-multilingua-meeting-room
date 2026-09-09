# Ending the copy-paste era: GitHub + automatic deploys

This guide replaces the "copy config.json, drag folder to Netlify" ritual
with: save files → they deploy themselves. One-time setup, ~20 minutes,
no coding.

## Why

- Your project lives in ONE place instead of a trail of zip folders.
- Netlify redeploys automatically whenever the project changes.
- Your `config.json`, `supabase.js`, and `africa.svg` are added once and
  never copied again.
- Every change is recorded — you can see and undo any version, forever.
- This is also ownership protection: WODDI's source code sits in an
  account WODDI controls (gap analysis, clause 25).

## Part 1 — GitHub account and app (5 min)

1. Go to https://github.com → **Sign up** (use a WODDI email if possible —
   this account will own the code).
2. Download **GitHub Desktop** from https://desktop.github.com and install
   it like any program. Sign in with the account from step 1.

## Part 2 — Create the repository (5 min)

1. In GitHub Desktop: **File → New repository**.
   - Name: `wdos`
   - Local path: choose where the project will live (e.g. Documents).
   - Leave everything else as is → **Create repository**.
2. Open that new `wdos` folder on your computer. Copy INTO it the entire
   contents of your latest project folder — `app/`, `supabase/`, `docs/`,
   `netlify.toml` — including your personal files (`app/config.json`,
   `app/assets/vendor/supabase.js`, `app/assets/vendor/africa.svg`).
   (The anon key in config.json is designed to be public — all security
   is enforced by the database. It is safe in the repository.)
3. Back in GitHub Desktop you'll see every file listed as a change. In the
   bottom-left box type `WDOS through phase 12` → **Commit to main**.
4. Click **Publish repository**. Untick "Keep this code private" ONLY if
   you want it public — for WODDI, keep it **private** (leave ticked).

Your code now lives safely on GitHub.

## Part 3 — Connect Netlify (5 min)

1. In https://app.netlify.com → your site → **Site configuration →
   Build & deploy → Link repository** (wording varies slightly; look for
   "Link to Git" / "Connect to Git provider").
2. Choose **GitHub** → authorise → pick the `wdos` repository.
3. Settings when asked:
   - Branch: `main`
   - Base directory: (leave empty)
   - Build command: (leave empty — there is no build step)
   - Publish directory: `app`
4. Save. Netlify deploys once from GitHub. Open your site and confirm it
   still works.

## Part 4 — Your new routine (forever)

When I hand you a new phase:
1. Copy the changed files from the zip into your `wdos` repository folder
   (overwrite when asked). Your personal files are already there — no
   more copying them.
2. GitHub Desktop shows what changed → type a short message
   (e.g. `phase 13`) → **Commit to main** → **Push origin**.
3. Netlify deploys by itself within a minute.
4. If the phase came with a migration, run it in the Supabase SQL Editor —
   and the app itself now tells you if you forget (red banner + Settings →
   System health).

## If you get stuck

Tell Claude which part and step number, plus a screenshot — same routine
as always.
