# Phase 124: the call lives inside WDOS (app v64.0, db stays 101)

## What changed and why

The Saturday test with the Rochas students failed for one structural reason:
the interpreter ran in the WDOS tab while the video ran in a separate
meet.jit.si tab. A phone shows one tab at a time, and Chrome suspends the
microphone recognition of any tab in the background. Every student sat in
the video tab, so the interpreter on her phone heard nothing and showed
nothing. That is what "nothing works" looked like from her seat.

The separate tab existed only because meet.jit.si cuts EMBEDDED calls at
five minutes. Phase 124 replaces the public server with the managed version
of the same engine, Jitsi as a Service (JaaS, run by 8x8 at 8x8.vc). It
embeds inside WDOS with no time limit, so a phone has one screen:

    video on top · one big Speak button · captions and spoken translation below

Other changes in the same build:

* Everyone joins as a LISTENER. The call microphone is muted on arrival and
  the interpreter is off. Tapping Speak opens both; tapping again closes
  both. Unmuting inside the call does the same thing. A muted phone can
  never "hear" the room's audio as speech, which removes the repeat loops
  seen in remote use.
* The person's language choices are remembered on the device, so she picks
  once.
* No app prompt on phones (the engine's deep-link nag is disabled), no
  pre-join page, one tap from the room card to the meeting.
* If a phone refuses the interpreter a second microphone while the call
  holds the first (some Android and iPhone builds do), the app stops
  retrying after three refusals, keeps the call microphone open so the
  others still hear her voice, and says plainly that she can listen in her
  language but should speak from a laptop or another phone.
* If the managed engine is not configured yet, the page falls back to the
  open-tab call as before, and HQ users see a one-line diagnostic naming
  the missing secret.

Every participant needs a personal token signed with our private key. That
is not extra friction: WDOS already knows who she is, so the token carries
her name, email and whether she is HQ staff (moderator). The signing runs
in a small Supabase Edge Function called `meeting-token`. The private key
lives only in Supabase secrets, never in the app.

## Cost line for the founder

JaaS is free on its Developer tier up to 25 monthly active users. Above
that it moves to fixed monthly tiers starting at 99 US dollars for up to
300 monthly active users, with an overage charge of 0.99 dollars per extra
active user. A person counts once per month however many meetings she
joins (the token uses her WDOS user id). Server-side transcription, which
would remove the need for any phone to run speech recognition, is a
per-minute add-on (about 0.03 dollars per minute) and needs a card on the
JaaS account. Check the current figures in the JaaS console before quoting
them.

## Part A: create the JaaS account (browser only, about 20 minutes)

1. Go to https://jaas.8x8.vc and sign up on the free Developer plan
   (use the WODDI IT email so the account belongs to the organisation).
2. On the console home you will see the App ID. It looks like
   `vpaas-magic-cookie-1234abcd5678...`. Copy it somewhere safe.
3. Open the API Keys page and choose to generate a new key pair. The
   console downloads the PRIVATE key file (often named after the key id,
   ending `.pk`) and shows the key id. Copy the key id. Keep the file: it
   is the only copy, and anyone holding it can mint tokens for our rooms.
4. Nothing else needs to be set on the JaaS side for the first test.

## Part B: give Supabase the secrets (browser only)

1. Supabase Dashboard → project `vhudbuprjpsyizporkcn` → Edge Functions →
   Secrets (sometimes under "Manage secrets").
2. Add three secrets, names exactly as written:

   | Name               | Value                                              |
   |--------------------|----------------------------------------------------|
   | `JAAS_APP_ID`      | the App ID from Part A step 2                      |
   | `JAAS_KID`         | the key id from Part A step 3                      |
   | `JAAS_PRIVATE_KEY` | the whole text of the private key file, from the `-----BEGIN` line to the `-----END` line |

   Open the `.pk` file in Notepad or TextEdit, select all, copy, paste. If
   the secrets box only allows a single line, that is fine: the function
   accepts the key with its line breaks written as `\n`, and it also
   accepts a base64 copy under the name `JAAS_PRIVATE_KEY_B64` instead.

## Part C: deploy the Edge Function (browser only)

1. Supabase Dashboard → Edge Functions → Deploy a new function → choose the
   editor option (not the CLI option).
2. Name it exactly `meeting-token`.
3. Open `supabase/functions/meeting-token/index.ts` from this package,
   select all, copy, and paste it into the editor, replacing whatever the
   editor pre-filled.
4. Leave "Verify JWT" switched on (the app calls the function with the
   member's own session token).
5. Deploy. Wait for the green status.

## Part D: deploy the app

1. Drag the `app` folder to woddicrm.netlify.app, then to
   woddiwdos.netlify.app.
2. On each device: close the WDOS tab completely, reopen woddicrm.org,
   hard refresh. The badge must read `build v64.0 · db 101`.
   No SQL migration this phase (the database stays at 101).

## Part E: the two-device rehearsal (do this before any group test)

Device 1: your laptop, Chrome. Device 2: your own phone, Chrome.

1. Both sign in, both open Rooms → HQ room (or the same custom room).
   Expected on both: the video appears INSIDE the page, the top chip reads
   `☁️ WODDI call · no time limit`, and the Speak button reads
   "Tap to speak". Nobody is heard yet.
   If the chip reads `↗ open-tab call` instead, the engine is not
   configured: HQ users see a line naming which secret is missing.
2. Laptop: I speak = English, Hear in = French. Phone: I speak = French,
   Hear in = English. (Solo rule still applies: speak and hear must differ
   on the device you are testing alone.)
3. Laptop: tap Speak, say "Good morning everyone, welcome to WODDI", tap
   Speak again. Expected: the phone shows the English line and the French
   line, and voices the French once. The laptop shows its own line and
   hears itself in French (the solo proof).
4. Phone: tap Speak, say a French sentence, tap again. Expected: the laptop
   shows and voices the English.
5. Leave both connected for SEVEN minutes doing nothing. Expected: no
   disconnect, no "rejoining" toast. This is the five-minute limit gone.
6. Phone: switch to another app for ten seconds, come back. Expected: the
   call is still there, the Speak button has returned to "Tap to speak"
   (leaving the page mutes you on purpose).
7. Phone: tap Speak. If the diagnostic line says the phone would not give
   the interpreter a second microphone, that phone is a listen-only device
   for now: note the make and model. The call itself keeps working.

If step 3 or 4 fails, do not change code: send the badge, the chips, and a
screenshot of the captions area from BOTH devices.

## Part F: the student re-test, run of show

* Send each student only the room link
  `https://woddicrm.org/#/room?r=<ROOM>` (Invite button copies it) plus the
  one-line rule: "Chrome, earphones, tap Speak only when you talk."
* Ask everyone to set BOTH pickers to their own language. HQ = English on
  both.
* HQ starts. HQ taps Speak, gives a two-sentence welcome, taps Speak again.
  Every phone should show it and voice it in the student's language.
* Then one student at a time: tap Speak, one sentence, tap again.
* Keep the printed feedback forms for after the call; photograph them and
  send them for the results report.

## Known limits, stated plainly

* Speech recognition (speaking) needs Chrome or Edge, and Safari on
  iPhone; Firefox and some in-app browsers can listen but not feed the
  interpreter. Listening (captions and voice) works everywhere.
* Speaking Hausa, Yorùbá and Igbo is still listen-side only (no browser
  recogniser hears them); hearing them uses the voice Space.
* The free JaaS tier is 25 active people per month. Keep the first tests
  inside that, or have the founder approve the next tier.
* Consecutive interpretation is by design a few seconds behind; short
  sentences and pauses keep it feeling quick.
