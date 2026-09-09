# PHASE 136 - Referral Links
Build v68.0 · db 112 · 7 Sep 2026

## What it does
- A link is a short code: https://woddicrm.org/#/r/CODE. Opening it records the
  visit (time, where the visitor came from such as WhatsApp or Facebook, language,
  time zone, device) and keeps the code on the visitor's device for 30 days. The
  landing page says who invited her and for what (position, place, network) and
  offers Apply for this position / Join as a member / I already have a login.
- When she submits the application door or the membership door, the record is
  stamped with the code. No door was rewritten: the doors call one extra function
  after a successful submission.
- Headquarters (HQ Operations → Referral Links): create campaign links for any
  network, country or unit and position; see every link with its owner, visits,
  applications and members; see every person who came through any link with who
  referred her, where she came from, her location, position sought and status.
- Volunteer leaders (sidebar → Referral Links): a "Get link" for every VACANT seat
  under them (by position, location and network, from the same seat matrix as
  Leadership Structure), a general membership link for their area, the people who
  came through their links, Copy and WhatsApp share, deactivate/activate.
- Location: the application's country, state and LGA, or the unit chosen, or the
  member's profile geography. WDOS does not geolocate visitors by IP; it records
  what the person states and where the link was opened from.
- A referral records the source only. Selection and appointment stay with HQ.

## Deploy
Run `112_referral_links.sql`, drag `app` to both Netlify sites → badge v68.0 · db 112.

## Limits
- A visitor who clears her browser storage before registering is recorded as a
  visit but not attached to her registration.
- Attachment only stamps a record created within two hours of the submission and
  never overwrites an existing referral code.
