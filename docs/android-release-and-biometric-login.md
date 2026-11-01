# Android release parity and biometric sign-in

Android and iOS use the same Flutter source, assets, portal, and version in
`pubspec.yaml`. On 29 October 2026, both builds succeeded at commit `3814834`
(version 1.2.19, build 50). Android was only producing a debug test APK; it had
no Google Play publisher. A successful Android validation run therefore did
not mean Google Play users had received the update.

## Google Play

Android validation now builds both the debug APK and an **unsigned release
AAB**, so release-only build failures are caught on pull requests. The separate
Google Play workflow builds and publishes a bundle signed with the existing
app's upload key. An unsigned or debug-signed validation artifact is never
submitted to Play.

Configure these repository Actions secrets, without putting them in source or
chat:

| Secret | Required value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Base64 of the existing `ma.foorsa` upload keystore |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_ALIAS` | Upload key alias |
| `ANDROID_KEY_PASSWORD` | Upload key password |

Google Play API access is **keyless**. The foorsa.ma Google Cloud organization
enforces `iam.disableServiceAccountKeyCreation`, so no service-account JSON key
exists or is stored. The publish job exchanges its GitHub OIDC token through
Workload Identity Federation:

- Cloud project `foorsa-play-publishing` (number 1046359922746), Play Android
  Developer, IAM Credentials and STS APIs enabled.
- Pool `github-actions`, provider `foorsa-student` (issuer
  `https://token.actions.githubusercontent.com`), attribute condition: repository
  `mehdiosafii/foorsa-student`, ref `refs/heads/main`, workflow
  `.github/workflows/google-play.yml` only.
- Service account `play-publisher@foorsa-play-publishing.iam.gserviceaccount.com`:
  no Cloud IAM roles; `roles/iam.workloadIdentityUser` granted only to
  `principalSet://iam.googleapis.com/projects/1046359922746/locations/global/workloadIdentityPools/github-actions/attribute.repository/mehdiosafii/foorsa-student`.
  In Play Console it has app-level access to Foorsa limited to releasing to
  production and to testing tracks (plus the default read-only view).

The upload key must match Play Console → App integrity. On 29 October 2026 the
original upload key could not be recovered, so an upload-key reset was
requested with a new key (SHA-1 `C5:23:BC:4A:D0:70:84:35:8F:F1:D0:63:D8:7E:9F:20:86:13:F0:FE`).
Bundles signed with it are accepted only from the activation date Play shows.
Google's app signing key is unchanged, so installed apps keep updating. Play's app signing key remains managed
by Google. Complete any outstanding Play Console listing, app content, testing,
and review requirements there; the publisher does not bypass them.

**The first production release.** `production-release-schedule.yml` started
this workflow on `main` for the production track on 31 October 2026 at 18:28
UTC. Play refused it because the app had not declared its foreground services,
which is "any other failure", so the schedule switched itself off as designed
(it is `disabled_manually` in Actions). Those declarations exist only in Play
Console (the API cannot make them) and need a filmed call, so from 1.2.29 (60)
the Android app holds no foreground service at all (below), and Actions →
Google Play → Run workflow with `production` sends the release without one.
`scripts/scheduled_production_release.py` still switches itself off outside
2026; do not re-enable the schedule for a later release.

### What Play Console asks for this app

- **Foreground services and the full-screen intent: nothing, for now.**
  `flutter_callkit_incoming` rings and holds an adviser call in foreground
  services (phone call, microphone, camera for video) and shows it full
  screen, and Play takes those only with Play Console declarations, each with
  a video of a real call on an Android phone. Nobody could film one when
  1.2.29 (60) went out, so native calls are iPhone only (the owner, 31 Oct
  2026): `nativeAdviserCalls` in `lib/src/student_calls.dart` is off on
  Android, the phone registers with `callsEnabled: false` so the server never
  rings it, and the manifest removes `FOREGROUND_SERVICE*` and
  `USE_FULL_SCREEN_INTENT` and the two services' `foregroundServiceType`
  (the services stay declared and idle: the plugin registers its phone
  account at start-up). A call still rings inside the chat while it is open.
  `test/shell_capabilities_test.dart` pins all of it.
  **To bring native calls to Android:** turn `nativeAdviserCalls` on for
  Android, put back the phone call and microphone permissions and the
  services' types (not the camera one, calls are voice only), then in Play
  Console declare the foreground services (tasks: VoIP, telecom API for the
  phone call; background audio input for the microphone; one video link of an
  adviser call answered and carried on with the app in the background, in
  both fields) and the full-screen intent ("Other": calls are a feature, not
  the app's core, so on Android 14 and later an incoming call rings as a
  heads-up notification).
- **Devices**: no hardware is required to install (the `uses-feature`
  block in the manifest, pinned by `test/shell_capabilities_test.dart`). A
  plugin or permission that adds a hardware requirement shows up in Play's
  release check as devices "no longer supported"; make it optional rather
  than drop them. The minimum is Android 7.0 (API 24), the toolchain's own.

A version change on `main` now triggers both TestFlight and Google Play. Play
defaults to `internal`; use the `GOOGLE_PLAY_TRACK` repository variable to set
the automatic track to `production` after device acceptance testing. Actions →
Google Play → Run workflow on `main` can target internal, alpha, beta, or
production. It rejects overwriting an in-progress staged rollout. A build
number must be higher than all previously uploaded Play bundles, as well as
the last iOS build; check Play Console before bumping the shared version.
The release replaces whatever the track holds, a draft left in Play Console
included, and carries the notes in `android/play-release-notes/<language>.txt`
(one file per listing language, at most 500 characters). While Play Console
holds other changes waiting to be sent (a declaration, the reviewer sign-in
details), Play will not send an edit for review by itself: the script then
commits it with `changesNotSentForReview`, and the run's summary says to press
**Send changes for review** in Publishing overview.

**Sending a version already in Play to another track.** Write the track's
name (`production`, `beta`, `alpha` or `internal`) in
`.github/google-play-promote.txt` and merge: the Google Play workflow's
`promote` job sends main's build number, which an earlier run uploaded, to
that track without rebuilding it (Play keeps one bundle per version code, so
a rebuild could not be uploaded again). It replaces what the track holds, a
Play Console draft included, carries the release notes, and refuses a build
number Play does not have or the track already holds. 1.2.29 (60) went from
internal testing to production this way on 31 October 2026.

Once main has moved past a version, name it after the track:
`production 1.2.31+62`. The job then sends that build, and its release notes
are the ones it was released with, read from history: the notes of the last
commit whose `pubspec.yaml` still said `1.2.31+62` (the parent of the commit
that replaced it), never main's notes for a newer build. A version that was
never in `pubspec.yaml` on main, or a line that is not a track and a version
like `1.2.31+62`, stops the run before Play is asked. 1.2.31 (62) went to
production this way on 1 November 2026, and 1.2.32 (63) replaced it in review
the same afternoon (`production 1.2.32+63`, main's own version, with main's
notes).

A green publishing run means Google accepted the release submission, not that
review or managed publishing has finished. Verify availability in Play Console
and test an **in-place update** of the current Play-installed app. The previous
debug APK cannot update a Play-signed installation.

## Quick sign-in

Since 1.2.21 (52) quick sign-in lives in the portal's own screens; the
native "Welcome back" overlay of 1.2.20 is gone.

- **After a password sign-in** (a successful student `/api/portal/me`
  response), the shell offers Face ID / Touch ID on iOS or strong fingerprint /
  face recognition on Android 9 and later, as one question and two answers
  (`quick_sign_in_offer.dart`, since 1.2.23: "Sign in with Face ID next
  time?", **Not Now** / **Use Face ID**; the owner, 30 Oct 2026: the popup
  "needs to be simpler"). On iOS it is the system's own alert, on Android a
  plain dialog, in the theme the student chose. No note follows a yes: the
  system's Face ID check has just said it. **Not now** is remembered for seven
  days, per student on this device. Ambassador sessions and the mandatory
  password-change screen are excluded. In 1.2.20 the bridge received its
  nonce only before a document scan, so this offer never appeared; the shell
  now hands the nonce over on every page load (`_publishScannerNonce`) and the
  bridge also asks for it when the WebView platform is ready.
- **The sign-in screen** asks `window.__foorsaBiometrics.status()` and, when a
  login is saved, shows a Face ID (or fingerprint) icon at the end of the Sign
  in button. The OS prompt opens only when the student taps that icon (the
  owner, 30 Oct 2026: "you need to click the face id logo"): the portal no
  longer asks for it by itself, and since 1.2.23 the bridge refuses
  `unlock({auto: true})` whatever release of the portal asks. The
  shell reads the vault through the OS prompt, validates the token with the
  server and returns it to the trusted main frame only; the bridge installs it
  as the page's session, kept across launches, and the portal carries on as
  after a typed password.
- **Profile › Settings** has a "Sign in with Face ID" switch: `enable()` saves
  the open session behind the OS prompt; `disable()` forgets it, and the
  student stays signed in.

Enrollment independently validates the token with the server, verifies native
biometric storage with a read-back, and only then marks it enabled. The saved
record contains the session token, account ID, and exact portal origin, never
a password or biometric template. iOS uses a non-synchronizing, device-bound,
passcode-required Keychain item with `biometryCurrentSet`. Android uses a
namespaced encrypted store with an authenticated Android KeyStore key,
strong biometrics only, and enrollment-change invalidation. Android backup and
device transfer are disabled for app data; biometric keys never migrate.

**The student stays signed in when the app closes**, quick sign-in or not
(the owner, 1 Nov 2026: "once you log to the app, even if the app closes
let's make sure you stay signed in"). Until 1.2.37 (68), while quick sign-in
was on, the web login and media tokens lived in the tab's session storage and
each new launch cleared them, so every launch opened on the sign-in screen.
From 1.2.37 they stay in the page's lasting storage, and the first launch of
the new build moves a tab copy an older build left back there
(`biometric_session.js`). Quick sign-in is for signing back in after a
sign-out: the saved login stays behind Face ID or the fingerprint.
Cancellation and temporary network errors do not erase it. **Signing out
keeps it** for the next sign-in; an expired or rejected session, a changed
Face ID / fingerprint set, or a deleted account (`portal-logout` with
`forgetDevice: true`) forgets it.

**A kept session is the saved login's own.** The page tells the shell whether
a session it announces began on the page (`fresh`: a sign-in) or was kept
from an earlier launch. The shell knows the saved token only once Face ID has
read it, so it replaces the saved login only for another account, or for a
new sign-in by the same student (the password typed although Face ID was
saved), which is then offered in its place (`StudentBiometrics.replacedBy`).
Judged by the token alone, a kept session read as a stranger's at every
launch and the saved login was deleted.

**The session renews itself while it is used.** Tokens still last 30 days,
but `/api/portal/me` hands a session that is a day old a fresh one (the
portal's `SESSION_RENEW_AFTER_SECONDS`), so a student who opens the app at
least once a month never has to sign in again. The portal says
`portal-session-renewed` just before it stores the renewal, and the script
takes it for the same sign-in: nothing is offered for it. The app answers
`session: 2` in `FoorsaShellCapabilities`; on older builds, which would take
every new token for a new sign-in, the portal keeps a renewal only in a
session's last week and never while the session is in the tab. The saved
login behind Face ID is not renewed (writing it asks for the face): it signs
back in for 30 days from when it was saved, then the password does. No
password is stored to work around expiry.

## Validation

- `flutter analyze --no-fatal-infos`
- `flutter test`
- `node --test test/biometric_session_test.cjs`
- Android CI: debug APK and release AAB; iOS CI: native archive validation.
- On physical Android and iOS devices: enable, cancel, lock out biometrics,
  force-close and reopen, go offline during restore, switch students, sign out,
  change biometric enrollment, uninstall/reinstall, and install over the
  current store build. Exercise onboarding, camera/scanner, document upload,
  notifications, adviser calls, and keyboard/back navigation after the Android
  activity change. The first session after a fresh install runs its web view
  as a texture rather than in the window (`lib/src/web_view_composition.dart`,
  docs/first-launch-onboarding.md, "Android"): sign in, paste (the web view
  plugin's own copy and paste bar in that session), autofill and type in the
  chat in that session too. Hardware prompts and store delivery
  cannot be proven by unit tests alone.

**Until 1.2.36 (67), no Android phone saw the fingerprint or face prompt.**
flutter_secure_storage (10.3.4, and 11.x alike) reads a store with no cipher
markers yet as data written under its old default ciphers, so the first
opening of a new biometric store looks to it like an algorithm change. With
`migrateOnAlgorithmChange` and `resetOnError` off, as the app sets them so
nothing is rewritten or wiped behind the student's back, it refuses that
opening ("Key mismatch after algorithm change") before Android draws its
prompt, and enrollment opens a new namespace every time, so every attempt
ended on "Quick sign-in could not be saved". The refusal records the store's
ciphers, so `StudentBiometrics._write` tries that one refusal once more and the
second opening goes straight to the prompt (`isNewAndroidStoreRefusal`, pinned
in `test/student_biometrics_test.dart`). Any other error is not retried. A
plugin upgrade must keep this, or turn migration on for a new store only.
