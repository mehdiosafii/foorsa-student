# foorsa_student

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Android releases and quick sign-in

Android now validates a release App Bundle as well as the test APK, and has a
Google Play publishing workflow using the same shared version as iOS. Students
stay signed in when the app closes (from 1.2.38), and can opt into securely
saved Face ID, Touch ID, or Android biometric sign-in for after a sign-out.
See [release setup, session behavior, and device checks](docs/android-release-and-biometric-login.md).

## The adhan

From 1.2.38 (69) the app sounds a recorded adhan at the prayer times the
student chose in the portal, with the app closed: local notifications the
portal schedules through `FoorsaBridge`. See [the adhan](docs/adhan.md).

## iOS release build

Validated locally with Flutter 3.47.5 and Xcode 27.0. The GitHub build uses
Flutter 3.47.5 and the newest stable Xcode on the `macos-26` runner (Xcode 26.6
in the September 2026 image), which meets Apple's Xcode 26 / iOS 26 SDK minimum
for uploads. iOS deployment target is 15.0. The project keeps CocoaPods
integration because the current splash plugin cannot resolve its Swift Package
Manager headers. Release device signing uses team G865J7CMBG and the
`Foorsa Student App Store` distribution profile.

### TestFlight from GitHub Actions

`.github/workflows/testflight.yml` builds the app on a GitHub macOS runner and
uploads it to TestFlight:

- **Release by bumping the version.** Merging a change to `version:` in
  `pubspec.yaml` into `main` (for example `1.2.17+34` to `1.2.17+35`) builds that
  version and uploads it. Other edits to `pubspec.yaml` do not release anything.
  Each build number uploads once; to ship again, raise it.
- **Or by hand.** Actions → TestFlight → Run workflow builds the branch you pick.
  Only a run on `main` uploads; untick "Upload the build to TestFlight" for a
  build that stops before TestFlight. Use it to retry a release whose automatic
  run failed ("Re-run jobs" would rebuild the old commit).
- A pull request that touches the workflow, `pubspec.yaml`, `pubspec.lock` or
  `ios/` runs the same build without uploading: signed when the secrets are set,
  unsigned otherwise.

Flutter analysis and tests run first, on Linux. Before building, an upload run
stops in seconds when App Store Connect already has the build number. After the
upload, the run waits until Apple has processed the build (usually under half an
hour), so a green run means the build is in TestFlight; a rejected build fails
the run, and the reason is in App Store Connect → TestFlight and in Apple's email.
Internal testers get the build automatically when their TestFlight group has
automatic distribution turned on.

The repository is public, so GitHub's macOS runners cost nothing. Its run logs
are public too: GitHub masks the four secrets below, the Key ID and Issuer ID
(variables) are printed but are useless without the `.p8`, and runs for pull
requests from forks get no secrets at all.

**First release after setting this up.** Merging the workflow does not touch
`pubspec.yaml`, so it uploads nothing by itself. Add the secrets and variables
below, then open Actions → TestFlight → Run workflow on `main` with the upload
box ticked: that uploads the version `main` is on (`1.2.17+34`). If App Store
Connect already has that build number, the run says so; bump the number and
merge instead.

**Two ways to sign.** The App Store Connect key below is always needed: it
uploads the build. On its own, as an **Admin** key, it is enough: Apple signs
the build in the cloud with the team's cloud-managed distribution certificate,
so nothing has to be exported from a Mac (24 Oct 2026). The archive is built
unsigned and signed once, by Apple, at export; if an export ever refuses the
unsigned archive, the run archives again with automatic signing, and the
development certificate Xcode makes on the runner for that is revoked at the
end of the run (`scripts/app_store_connect.py revoke-new`; only certificates
Xcode made "Created via API" during the run). A distribution certificate is
never revoked by the workflow: Apple marks a build that is uploaded but not
yet submitted for review "Invalid Binary" when the certificate that signed it
is revoked. An App Manager key signs in but Apple refuses it cloud signing
("Cloud signing permission error"); with an App Manager key, add the
certificate and the profile too. When `IOS_DISTRIBUTION_P12`, its password and
`IOS_PROVISIONING_PROFILE` are all set, the run signs with them instead, as
before. The run's summary says which it used.

**One-time setup** (repository Settings → Secrets and variables → Actions):

| Name | Kind | What to put in it |
|---|---|---|
| `IOS_DISTRIBUTION_P12` | Secret, optional with an Admin key | The Apple Distribution certificate **with its private key**. On the Mac that holds it: Keychain Access → login → My Certificates → "Apple Distribution: … (G865J7CMBG)" (a key shows beneath it) → File → Export Items… → Personal Information Exchange (.p12), saved as `dist.p12`; then `base64 -i dist.p12 \| pbcopy`. If it is not under My Certificates, its key is not on that Mac: make a new Apple Distribution certificate and update the profile to use it |
| `IOS_DISTRIBUTION_P12_PASSWORD` | Secret, optional with an Admin key | The password chosen when exporting the `.p12`. It must not be empty: GitHub does not store an empty secret, and the workflow then treats signing as not set up |
| `IOS_PROVISIONING_PROFILE` | Secret, optional with an Admin key | The `Foorsa Student App Store` profile from developer.apple.com → Certificates, Identifiers & Profiles → Profiles, base64-encoded: `base64 -i Foorsa_Student_App_Store.mobileprovision \| pbcopy` |
| `APPSTORE_API_PRIVATE_KEY` | Secret | The contents of `AuthKey_XXXXXXXXXX.p8` (`pbcopy < AuthKey_XXXXXXXXXX.p8`), from App Store Connect → Users and Access → Integrations → App Store Connect API → Team Keys → + (created by the Account Holder or an Admin, with the **Admin** role for cloud signing, or App Manager when the certificate and profile are set; the file downloads only once, and if the page shows Request Access the Account Holder clicks it first) |
| `APPSTORE_API_KEY_ID` | Variable | That key's Key ID (on the Variables tab) |
| `APPSTORE_ISSUER_ID` | Variable | The Issuer ID shown above the keys list (on the Variables tab) |

An upload run without the key stops at once and names what is missing. With
the certificate secrets, the workflow also checks before building that the
profile is the `Foorsa Student App Store` one for `ma.foorsa.foorsaStudent`,
that it has not expired, and that it was made for the certificate in the
`.p12`.

The certificate and the profile each last a year (every run's log prints the
profile's expiry). A renewed profile replaces only `IOS_PROVISIONING_PROFILE`;
keep its name. A new certificate means editing the `Foorsa Student App Store`
profile on developer.apple.com to use it and downloading the profile again, so
replace `IOS_DISTRIBUTION_P12`, `IOS_DISTRIBUTION_P12_PASSWORD` and
`IOS_PROVISIONING_PROFILE` together.

### Building on a Mac

The same build by hand, with that profile and its certificate installed:

```sh
flutter pub get
flutter analyze --no-fatal-infos
flutter test
flutter build ipa --release --build-name 1.2.17 --build-number 34 \
  --export-options-plist=/path/to/ExportOptions.plist
```

Use an App Store Connect export options file with manual signing and the profile
above (the workflow writes the same file). The production archive and IPA
completed successfully on 5 October 2026. Analysis reports five existing
informational lints. Physical-device permission testing is still required before
final submission.

## First launch

A first-time downloader boards through a native onboarding before the
sign-in, told with one object: the launch screen is Foorsa's arrow alone, in
pearl glass, and it becomes the journey's airliner. There are no buttons: on
each screen the student acts on the object itself, wherever it stands. They
throw the arrow up into the departures board, tap the notification, drag the
passport page into the scanner's frame, tap the mic, tap the map's locate
arrow (Foorsa's own), and tear the boarding pass's stub off, each with a quiet
line under it saying what to do. Between screens the object folds into the
arrow and unfolds as the next. One screen asks for each phone access
(notifications, camera, microphone, location), each a single object in the
portal's glass; sounds you can hear (a soft music bed, a glass note per step),
set by the phone's volume buttons; the first real notification when they are
turned on. At the end what is left of the pass folds into the arrow, which
lands on the sign-in's own arrow while the portal fades in on the same
night. Updates skip it. Acting on an object always leads straight to the
system prompt, nothing on screen says Allow, and for a screen reader each
object is a button named Continue (App Review 5.1.1(iv)); tracking is built
but off, because the app does not track. See `docs/first-launch-onboarding.md`.

## What the portal tells the app

The portal (student.foorsa.ma, `src/portal` in foorsa-reward) calls these
handlers through `window.flutter_inappwebview.callHandler`. Builds that do not
know one ignore it, so the portal sends them to every build.

- `FoorsaShellCapabilities` answers what this build does (`shell_capabilities.dart`):
  `embeddedFrames`, `videoInput`, `hapticTextures` (3: the admission reveal's
  textures and `error`), `bootHandoff`, `language`, `push` (2: push registration names its
  reasons and answers `pushStatus`), `pagePermissions` (2), `adhan` (1: the
  adhan at prayer times with the app closed), `session` (2: the student stays
  signed in across launches, and a renewed session is not taken for a new
  sign-in) and the build's `appVersion` and `appBuild`.
- `FoorsaBridge` with the page's session (`nonce`): `getPushToken` (a token, or
  why there is none), `pushStatus` (the permission, without asking),
  `openNotificationSettings`, `clearPushToken` (sign-out) and the calendar's
  reminders. A call made before the page had the session gets
  `{ status: 'pending', reason: 'session' }`, and the shell hands the session
  over again with a `foorsa-shell-session` event. See `docs/student-push.md`.
  The same bridge takes the adhan's `adhanStatus`, `adhanEnable`, `adhanSync`,
  `adhanClear` and `adhanExactAlarms` (`docs/adhan.md`).
- `FoorsaShellLoading('hold' | 'ready')`: the portal draws the app's own loader
  until its first screen, so the app keeps its loader on top from `hold` to
  `ready` (at most 10 s), centred where the portal centres its one, and one
  loader runs from the app icon to the first screen (`boot_loader_gate.dart`).
- `FoorsaShellAppearance('light' | 'dark' | 'system')`: the theme the student
  chose, kept on the phone (`shell_appearance.dart`) so the next start's loader
  and the offline screen open in it.
- `FoorsaShellLanguage('en' | 'fr' | 'ar')`: the language the portal runs in,
  at start and when the student changes it in Profile › Settings, kept on the
  phone (`app_language.dart`) so the app's own screens speak it. The other way
  round, a language chosen in the onboarding's first step is written into the
  portal's `localStorage.foorsa_portal_language` before its code runs (only
  where nothing is chosen yet, or once per choice made in the onboarding), and
  a page already open is told with `window.dispatchEvent(new
  CustomEvent('foorsa:language', { detail: '<code>' }))`.
- `FoorsaShellHaptic(name, level)`: a texture by name (`shell_haptics.dart`,
  `ShellHaptics.kt` on Android at media strength, Taptic impacts on iOS); a
  number is an ordinary press, one light tick. Builds 33 to 46 shipped without
  the textures and played a tick for every one.
- `FoorsaShellTheme(color)`: the status bar follows the page.

## What the app lets the portal use

When a page asks for a device, the web view asks the app
(`onPermissionRequest` in `shell_page.dart`), and `portal_permissions.dart`
decides. Only the configured portal is granted anything, and only while it is
the page on show; every other resource is denied.

- The camera and the microphone, each once the phone allows it. An iPhone asks
  for video with sound in one request (`CAMERA_AND_MICROPHONE`, the
  introduction video's studio); it is granted after the camera, then the
  microphone. Android names the two separately.
- How the phone is held (`DEVICE_ORIENTATION_AND_MOTION`): iOS 15 and later
  ask when the page calls `DeviceOrientationEvent.requestPermission()` inside a
  tap (the studio's set-up, the admission reveal's tilt). The phone has no
  permission to ask for, so nothing is asked of it; Info.plist says why the
  app reads the motion sensors (`NSMotionUsageDescription`), in case iOS ever
  asks. Android delivers the orientation without asking.

Before 1.2.33 (64) the iPhone app denied both: the studio stopped at
"Foorsa can’t use your camera and microphone" before its set-up, and the
reveal's letter never followed the phone. `FoorsaShellCapabilities` answers
`pagePermissions: 2` from that build on.

## Firebase phone notifications

### Android device-test build

The Android validation workflow runs independently of Apple setup. It verifies
the Firebase registrations, runs Flutter analysis and tests, and builds an ARM64
debug APK. Open the successful Android validation run in GitHub Actions and
download its `foorsa-android-device-test-<commit>` artifact. The run summary
records the APK checksum. Artifacts are retained for 14 days.

This APK is for a dedicated test Android device and a test student account. It
uses the production portal and is debug-signed; it is not a Google Play release
and cannot update a Play-installed app signed by another certificate. Do not
uninstall a live student's app for testing. Check permission granted/denied,
token registration, foreground/background delivery, notification taps, sign-out
and account switching before publishing a signed release.

Google Play distribution still needs the existing upload-signing configuration
and a release build. Bump the version only when preparing a signed release: a
new `version:` on `main` also uploads an iOS build to TestFlight.

### Registered Firebase clients

Supabase remains the student backend. Firebase Cloud Messaging delivers remote
phone notifications through the existing push service in foorsa-reward.

The checked-in client registrations come from Firebase project `foorsa-d71c1`
(sender `643586848398`): Android `ma.foorsa`, iOS `ma.foorsa.foorsaStudent`.
`android/app/google-services.json` is loaded by the Google Services Gradle
plugin; the existing Xcode build phase bundles
`ios/Runner/GoogleService-Info.plist`. These files contain public client
identifiers, not server credentials. Never commit service-account private keys,
APNs authentication keys, or App Store Connect signing keys.

Run `python3 scripts/verify_firebase_config.py` before building. The TestFlight
checks job also verifies the registrations against the actual Android and iOS
application IDs. The older `com.foorsa.app` Firebase registration is not the
current Android application's ID.

iOS remote delivery additionally requires an APNs authentication key or valid
APNs certificate in Firebase Project settings → Cloud Messaging for this iOS
app, plus a signed release with the push entitlement. Registering the app does
not establish device delivery. Verify consent, token registration, and a push
to a dedicated test device before releasing broadly. TestFlight signing and
upload credentials are configured separately as described above.
