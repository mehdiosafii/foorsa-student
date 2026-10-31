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

**The first production release went through Play Console.**
`production-release-schedule.yml` started this workflow on `main` for the
production track on 31 October 2026 at 18:28 UTC. Play refused it because the
app had not declared its foreground services, which is "any other failure", so
the schedule switched itself off as designed (it is `disabled_manually` in
Actions). Those declarations exist only in Play Console (the API cannot make
them); once they are saved, Actions → Google Play → Run workflow with
`production` sends the release. `scripts/scheduled_production_release.py`
still switches itself off outside 2026; do not re-enable the schedule for a
later release.

### What Play Console asks for this app

- **Foreground services** (Règles et programmes → Contenu de l'application):
  only `FOREGROUND_SERVICE_PHONE_CALL` and `FOREGROUND_SERVICE_MICROPHONE`,
  both from `flutter_callkit_incoming`'s adviser calls. The camera type is
  removed from the merged manifest (calls are voice only), so it is never
  declared. Tasks: VoIP, telecom API for the phone call, and background audio
  input for the microphone, each with a link to a video of an adviser call
  answered and carried on with the app in the background.
- **Full-screen intent**: `USE_FULL_SCREEN_INTENT` comes from the same plugin.
  Calls are one feature of the app, not its core, so the declaration answers
  "Other": on Android 14 and later Play does not grant it at install, and an
  incoming call rings as a heads-up notification rather than over the lock
  screen. Claiming "making and receiving calls" as the core feature would not
  be true and Google reviews that answer.
- **Devices**: no hardware is required to install (the `uses-feature`
  block in the manifest, pinned by `test/shell_capabilities_test.dart`). A
  plugin or permission that adds a hardware requirement shows up in Play's
  release check as devices "no longer supported"; make it optional rather
  than drop them. The minimum is Android 7.0 (API 24), the toolchain's own.

Once the declarations are saved they apply to every later bundle, and a
version bump on `main` goes to Play from this workflow again.

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
  as this launch's tab session and the portal carries on as after a typed
  password.
- **Profile › Settings** has a "Sign in with Face ID" switch: `enable()` saves
  the open session behind the OS prompt; `disable()` forgets it and moves the
  session back to ordinary storage, so the student stays signed in.

Enrollment independently validates the token with the server, verifies native
biometric storage with a read-back, and only then marks it enabled. The saved
record contains the session token, account ID, and exact portal origin, never
a password or biometric template. iOS uses a non-synchronizing, device-bound,
passcode-required Keychain item with `biometryCurrentSet`. Android uses a
namespaced encrypted store with an authenticated Android KeyStore key,
strong biometrics only, and enrollment-change invalidation. Android backup and
device transfer are disabled for app data; biometric keys never migrate.

While quick sign-in is on, the web login and media tokens live in the current
tab's session storage, and each new native launch clears them, so the app
opens on the portal's sign-in screen with Face ID. Cancellation and temporary
network errors do not erase the saved login. **Signing out keeps it** for the
next sign-in; an expired or rejected session, a changed Face ID / fingerprint
set, or a deleted account (`portal-logout` with `forgetDevice: true`) forgets
it. Signing in as a different student replaces it.

Tokens retain the server's existing 30-day lifetime; this feature does not
extend it or store passwords to work around expiry.

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
  activity change. Hardware prompts and store delivery cannot be proven by
  unit tests alone.
