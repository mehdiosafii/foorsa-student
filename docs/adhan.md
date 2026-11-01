# The adhan at prayer times, with the app closed

The owner, 1 Nov 2026: "if applicant chooses adan, an adan real life one,
needs to play where ever it's time". A student who turns the adhan on in the
portal (Prayer times, or the Prayer tool on the flight Home) hears a real
recorded adhan at each prayer they chose, where they are, whether the app is
open, in the background or closed and the phone locked.

## Who does what

- **The portal computes the times, on the phone.** `shared/prayerTimes.ts` and
  `shared/adhanSchedule.ts` in foorsa-reward work out the next six days of
  calls (at most 30) for the student's place (the phone's position, or a city
  they chose) and the calculation method of that country (Morocco's Ministry of
  Habous, Tunisia, Muslim World League in China, Umm al-Qura), and write each
  call's title and line in the student's language. `src/portal/prayer/
  adhanBridge.ts` sends them with `adhanSync` each time the app opens and
  whenever the place, the method, the prayers or the language change.
- **The app schedules one local notification per call**
  (`StudentPush.adhan`, `student_push.dart`), each with the adhan as its
  sound. Nothing is fetched or computed natively, and the notification opens
  the portal's Prayer times (`payload: '/prayer'`).

## The bridge

`FoorsaBridge` with the page's session (`nonce`, as the push calls), each with
`owner` (the applicant id):

| Action | What it does | Answer |
|---|---|---|
| `adhanStatus` | Nothing; reads the state | `{ enabled, permission, count, through, exact }` |
| `adhanEnable` | Asks to notify (iOS alert and sound; Android 13+'s permission), inside the student's tap | the status |
| `adhanSync` | `calls: [{ at, prayer, sound: 'full' \| 'short', title, body }]` and a `fingerprint`; schedules them again only when the fingerprint, the account or the exact-alarm setting changed | the status |
| `adhanClear` | Cancels every call | the status |
| `adhanExactAlarms` | Opens Android's "Alarms & reminders" page for this app | the status |

`validAdhanCalls` (`student_adhan.dart`) keeps a call only with a known prayer,
a time in the next 15 days, a sound and both lines (control characters taken
out, 120 and 200 characters at most), one per minute, soonest first, at most
40. Another student signing in on the phone clears the previous one's calls,
and signing out clears them all (`_clear`). `FoorsaShellCapabilities` answers
`adhan: 1` from 1.2.36 (67); an older build answers nothing, and the portal
then sounds the adhan only while it is open (its in-page player).

## The sound

One freely licensed recording: Aaqib Azeez's adhan on Wikimedia Commons
(CC BY-SA 4.0), credited on the portal's Prayer times screen. The portal's
`scripts/adhan/make.py` cuts it from the pinned file (its SHA-256 is in the
script), levels it (EBU R128, -14 LUFS) and writes, with `--student <path to
this repo>`:

- **iPhone**: `assets/sounds/adhan/foorsa_adhan.caf`, the opening (26.8 s, IMA4
  at 22.05 kHz). iOS plays a notification's sound only when it is under 30
  seconds, and only from the app bundle or the app's `Library/Sounds`, where
  the app copies it before it schedules the first call
  (`_installIosAdhanSound`). So an iPhone calls with the opening whatever the
  prayer; the portal plays the whole adhan when the notification is opened.
- **Android**: `res/raw/foorsa_adhan.ogg`, the whole call (86 s), on the
  `foorsa_adhan_v1` channel, and `res/raw/foorsa_adhan_short.ogg`, the
  opening, on `foorsa_adhan_fajr_v1` for Fajr. No freely licensed Fajr adhan
  (with "as-salatu khayrun min an-nawm") was found, so Fajr calls with the
  opening both adhans share, on every phone. `res/raw/keep.xml` keeps both
  files through resource shrinking.

A channel's sound cannot change once Android has made it: a new recording
needs new channel ids (`_v2`), and the old channels deleted.

## What limits it

- **An iPhone holds an app's 64 soonest notifications**, the class reminders
  included, so the portal sends six days and every open moves them on. A
  student who does not open the app for a week stops hearing it until they do.
- **Android delivers on time only with exact alarms.** `SCHEDULE_EXACT_ALARM`
  is declared (the user-granted one; `USE_EXACT_ALARM`, which Google Play
  restricts to alarm and calendar apps and asks a declaration for, is not).
  Android 13 and later do not grant it to a new install, so the app checks it
  (`canScheduleExactNotifications`) before every schedule and otherwise
  schedules inexact calls, which Android may move by some minutes; the
  portal's Prayer times offers the setting page.
- **The phone's own settings win.** A silenced iPhone, Focus, Do Not Disturb,
  or the channel's sound turned down in Android's settings silence it, as for
  any notification. The adhan's volume is the notification volume.

## Checking it on a phone

Turn the adhan on in Prayer times with a test student, pick a city whose next
prayer is a few minutes away (or set the phone's clock), close the app and lock
the phone: the call must sound at the minute, with the app's adhan. Then: a
second student signing in clears the first one's calls; signing out clears
them; changing the language rewrites them; on Android 14, refusing exact
alarms still delivers (later), and granting them makes it on time.
