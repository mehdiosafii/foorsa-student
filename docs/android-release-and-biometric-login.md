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
| `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` | Service-account JSON authorized for `ma.foorsa` releases in Play Console, with the Android Publisher API enabled |

The upload key must match Play Console → App integrity. Do not create a new key
as a substitute for the existing key. Play's app signing key remains managed
by Google. Complete any outstanding Play Console listing, app content, testing,
and review requirements there; the publisher does not bypass them.

A version change on `main` now triggers both TestFlight and Google Play. Play
defaults to `internal`; use the `GOOGLE_PLAY_TRACK` repository variable to set
the automatic track to `production` after device acceptance testing. Actions →
Google Play → Run workflow on `main` can target internal, alpha, beta, or
production. It rejects overwriting an in-progress staged rollout. A build
number must be higher than all previously uploaded Play bundles, as well as
the last iOS build; check Play Console before bumping the shared version.

A green publishing run means Google accepted the release submission, not that
review or managed publishing has finished. Verify availability in Play Console
and test an **in-place update** of the current Play-installed app. The previous
debug APK cannot update a Play-signed installation.

## Quick sign-in

After a successful student `/api/portal/me` response, the native shell offers
Face ID/Touch ID on iOS or strong fingerprint/face recognition on Android.
Students can choose **Not now**; that decision is remembered for seven days,
per student on this device. Ambassador sessions and the initial mandatory
password-change screen are excluded. No portal deployment is required: the
versioned top-frame script adapts the existing portal token contract.

Enrollment independently validates the token with the server, verifies native
biometric storage with a read-back, and only then marks it enabled. The saved
record contains the session token, account ID, and exact portal origin, never
a password or biometric template. iOS uses a non-synchronizing, device-bound,
passcode-required Keychain item with `biometryCurrentSet`. Android uses a
namespaced encrypted store with an authenticated Android KeyStore key,
strong biometrics only, and enrollment-change invalidation. Android backup and
device transfer are disabled for app data; biometric keys never migrate.

For enrolled users, the bridge moves the active web token out of persistent
`localStorage` into the current tab's session storage. Each new native launch
clears that tab session before the portal starts. A native unlock screen reads
the vault through OS biometric authentication, validates the token with the
server, and restores it only to the configured HTTPS main frame. Cancellation
and temporary network errors do not erase the saved login. **Use password**
forgets quick sign-in and opens ordinary sign-in. Explicit sign-out and an
expired/rejected session forget the saved record. Missing installation metadata
cannot revive a surviving iOS Keychain item after reinstall.

Tokens retain the server's existing 30-day lifetime; this feature does not
extend it or store passwords to work around expiry. Reauthenticate with the
password and opt in again after expiry. Biometrics are required on a new app
launch; this feature does not introduce a lock on every background/resume event.

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
