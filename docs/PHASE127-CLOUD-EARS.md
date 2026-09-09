# Phase 127: cloud ears (speaking works in ANY browser, any phone)

## What changed and why

Every build until now asked the BROWSER to understand speech. That engine
(webkitSpeechRecognition) exists only in Google Chrome, has been broken in
Microsoft Edge since version 134, stops when a phone tab goes to the
background, and some phones refuse to give it a microphone while the call
already holds one. Translation and voice-out always worked; capturing the
speaker was the weak link, and it was the browser's problem, not ours.

From v64.4 the room no longer depends on it. When the new `transcribe`
function is configured, the Speak button becomes push-to-talk:

    tap Speak → say your sentence → tap Speak again
    → a short clip is recorded (this works in every browser on earth)
    → the clip goes to a WODDI function which sends it to Groq's free
      Whisper service (one of the best speech models available)
    → the text comes back in about a second and takes the same
      translate-and-voice path as before

Edge, Safari, Firefox, Chrome, every Android and iPhone: all the same.
If the function is NOT configured, the room quietly falls back to the old
browser recogniser (Chrome only), so nothing is lost by deploying early.

## Part A: get the free key (browser only, about 3 minutes)

1. Go to https://console.groq.com and create a free account (Google
   sign-in works). No card is asked for.
2. Left menu → API Keys → Create API Key → give it a name (WODDI) →
   copy the key that appears (it starts with gsk_). You will not see it
   again, so paste it somewhere safe for the next minute.

## Part B: give Supabase the secret (browser only)

1. Supabase Dashboard → your WDOS project → Edge Functions → Secrets.
2. Add a secret: name exactly `GROQ_API_KEY`, value = the key you copied.
3. Save.

## Part C: deploy the function (browser only)

1. Supabase Dashboard → Edge Functions → Deploy a new function → choose
   the editor option (not the CLI option).
2. Name it exactly `transcribe`.
3. Open `supabase/functions/transcribe/index.ts` from this package, select
   all, copy, and paste it into the editor, replacing whatever the editor
   pre-filled.
4. Leave "Verify JWT" switched on.
5. Deploy. Wait for the green status.

## Part D: deploy the app

Unzip this package, drag the `app` folder to BOTH Netlify sites, hard
refresh, and confirm the badge reads build v64.4 · db 101. No SQL
migration this time.

## Part E: the proof (two minutes, one device, ANY browser)

1. Open the room. In the captions area you should see one grey line:
   "Cloud interpreter ready: tap Speak, talk, tap again. Works in every
   browser." If you do not see it, the function is not reachable: check
   Parts B and C (the function name must be exactly `transcribe`).
2. I speak = English, Hear in = Français.
3. Tap Speak. The chip reads "recording…". Say: "Good morning everyone,
   welcome to WODDI." Tap Speak again. The chip reads "understanding…" for
   about a second, then your English line appears, then the French line,
   and the French is spoken aloud.
4. Now do exactly the same in Microsoft Edge, or Safari on an iPhone. It
   behaves identically. That is the point of this phase.

## Part F: the two-device test and the meeting rules

Same as before: each person sets BOTH pickers to their own language;
HQ is English/English. Earphones. To talk: tap Speak, one or two
sentences, tap again. Your words reach everyone in their language a
second or two after you tap the second time. One person speaks at a time.

## Limits, stated plainly

* Push-to-talk, not open-mic. Each clip stops itself after 30 seconds, so
  speak in sentences, not speeches.
* About one to two seconds from the second tap to the translation.
* Whisper handles English, French, Arabic, Portuguese and Swahili well,
  African accents included. Yoruba, Hausa and Igbo remain hear-only.
* Groq's free tier is generous for meetings (hours of audio a day) but is
  not a plan for millions of users; the founder's scale vision needs the
  paid engines discussed separately. This phase makes today's meetings
  work on every device for free.
