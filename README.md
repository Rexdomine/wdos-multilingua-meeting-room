# WDOS Multilingua Meeting Room

Static WDOS application candidate for the Friday multilingual meeting-room QA.

## Current candidate

- App version: `68.4-friday-audio-qa`
- Supabase project: `vhudbuprjpsyizporkcn`
- Frontend: static JavaScript app in `app/`
- Backend: Supabase Auth, Realtime, Postgres, and Edge Functions in `supabase/functions/`

## Friday interpreter spine

```txt
Browser mic → sentence VAD → short audio clip → server transcription → room caption event → listener translation → translated audio playback
```

Initial audible target:

- English → French
- English → Portuguese

## Deployment

Vercel should serve the `app/` directory as a static site. No package install or build step is required.

## Important QA caveat

Live backend checks have passed for auth, meeting token, transcription, translation, and Realtime caption broadcast. French/Portuguese audible playback still depends on browser/device voices unless a hosted FR/PT voice service is configured.

## Security note

`app/config.json` contains the Supabase URL and anon key. That is expected for a Supabase browser app; database security is enforced by RLS and authenticated Edge Functions. Do not commit service-role keys or provider secrets.
