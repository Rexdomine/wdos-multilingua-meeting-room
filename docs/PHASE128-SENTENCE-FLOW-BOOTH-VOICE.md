# Phase 128: sentence flow, booth mode, cloud voice (v64.5)

Three fixes from the first real multi-user use of the cloud ears.

## 1. "It takes more than 30 seconds" → sentence flow

Before: the clip was sent only when Speak was tapped a second time, or at
a 30-second safety cutoff. People tapped once, kept talking, never tapped
again, so nothing left until the cutoff.

Now: tap Speak ONCE and talk naturally. The room listens for the pause at
the end of each sentence (about 0.7 s of quiet after at least half a
second of speech), sends that sentence at once, and keeps listening.
Each sentence reaches everyone in their language one to two seconds after
you finish saying it. Tap Speak again when you are done. A very long
stretch without any pause is sent every 20 seconds anyway; ninety seconds
of total silence switches Speak off by itself.

The chip reads "listening… speak in sentences, tap Speak to finish".
Browsers without an audio analyser (rare) fall back to fixed 8-second
clips.

## 2. "They hear English first" → booth mode

Before: Speak also opened your microphone INSIDE the call, so listeners
heard your real English through the call, then the translation.

Now (default): your voice does not enter the call at all. Listeners hear
only the interpreter, in their own language, exactly like a UN booth.
Listeners in YOUR language hear the interpreter say your words too, so
nobody is left with silence.

If HQ ever wants the real voice in the call as well (for example a
same-language meeting), set the org setting:

    insert into org_settings (key, value) values ('call_raw_voice', '"on"'::jsonb)
    on conflict (key) do update set value = excluded.value;

Remove it or set it to anything else to return to booth mode.

## 3. "Arabic does not work" → cloud voice

Diagnosis: most Windows laptops and Android phones have no Arabic voice
installed. The Arabic translation appeared on screen; the device had
nothing to speak it with. The build already showed "No ar voice on this
device" on those devices.

Now: a second function, `speak`, turns text into speech in the cloud with
Groq's Orpheus models (Arabic and English) using the SAME free key as the
cloud ears. Device voices stay first because they are instant and
unlimited; the cloud voice is used only when the device has none.

### Deploy the speak function (browser only, 3 minutes)

1. Supabase Dashboard → Edge Functions → Deploy a new function → editor
   option.
2. Name it exactly `speak`.
3. Open `supabase/functions/speak/index.ts` from this package, copy all,
   paste, replacing the editor's contents.
4. Leave "Verify JWT" on. Deploy. Wait for green.
5. No new secret: it reads GROQ_API_KEY from Phase 127.

Free-tier note: Groq's text-to-speech is free but rate-limited (a modest
number of requests per day). Each Arabic sentence heard on a device
without an Arabic voice costs one request, repeated sentences are cached.
It is comfortable for tests and meetings of normal length; for daily
heavy use, install the Arabic voice pack on the listening devices
(Android: Settings → Text-to-speech → install Arabic) so the free device
voice is used instead.

## Deploy the app

Drag the `app` folder to BOTH Netlify sites. Badge: build v64.5 · db 101.
No SQL migration.

## The proof (two devices)

Laptop: I speak English, Hear in English. Phone: I speak العربية, Hear in
العربية (or Français).

1. Laptop taps Speak once and says three sentences with normal pauses,
   then taps Speak again. Expected on the phone: three Arabic lines
   arriving one after another, each spoken aloud within about two seconds
   of the sentence ending, and NO English voice from the call.
2. Phone taps Speak, says two Arabic sentences, taps again. Expected on
   the laptop: two English lines, spoken aloud.
