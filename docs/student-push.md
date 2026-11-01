# How a phone registers for push notifications, and why it would not

The owner, 31 Oct 2026, testing from TestFlight: "i am not receiving
notifications in support". `student_push_devices` in foorsa-reward was empty:
no phone was registered (its id sequence had been used twice, so a phone or
two had once registered and later gone, a sign-out or a token Firebase no
longer knew). Nothing anywhere said why, because every step that could stop a
registration answered the portal with a status the page dropped. By 1 Nov one
Android phone had registered (31 Oct, 23:30 UTC) and still no iPhone, which
points at the iPhone's half of the chain: Apple's token, the push entitlement
and the three-second wait for it (below).

## The chain

1. The portal (`src/portal/studentPush.ts` in foorsa-reward, only in the app)
   asks the shell for its session (`FoorsaShellScannerSession`, which
   publishes `window.__foorsaScannerNonce` into the main frame), then calls
   `FoorsaBridge { action: 'getPushToken', nonce }`.
2. The shell (`_handleBridgeCall`, `shell_page.dart`) checks the trusted
   origin and the session. A call made before the page had the session is
   answered `{ status: 'pending', reason: 'session' }`, the session is handed
   over again, and the page is told (`foorsa-shell-session`), so it asks at
   once rather than after a fixed wait.
3. `StudentPush.token()` (`student_push.dart`) runs `PushRegistration`
   (`push_registration.dart`): Firebase, the permission (the phone's prompt
   the first time), `setAutoInitEnabled(true)` (which registers with APNs on
   iOS), the APNs token (waited for up to 10 s), the FCM token, the PushKit
   token for adviser calls. Each refusal is named:

   | Answer | Crash board (once a day per reason and phone) |
   |---|---|
   | `unconfigured`, `reason: <error type>` | `push: Firebase not configured: <error type>` |
   | `denied` | `push: permission denied` |
   | `pending`, `reason: 'apns'`, `apnsError` | `push: APNs token never arrived[: <Apple's refusal>]` |
   | `error`, `reason: 'token: <code>'` | `push: token failed: <code>` |

   Only the reason is sent (`CrashReports`, `POST /api/portal/client-error`,
   `source: 'shell'`), never a token or an id. The day's reasons are kept in
   `push_problems.json` in the app's support directory.
4. The portal POSTs `/api/portal/push/register`. A refusal is reported from
   the page (`push: register failed <status>`), and for an app build that
   does not report its own reasons (no `push` in `FoorsaShellCapabilities`),
   the page reports what that build answered, marked `(older app build)`.

`FoorsaShellCapabilities` answers `push: 2` (named reasons, `pushStatus`,
`openNotificationSettings`) and, from this build, `appVersion` and `appBuild`,
which Admin Portal › Student App reads to show which build a student runs.

## What was wrong, and what changed

- **A Firebase that failed once was written off for the app's life**, and a
  local notifications plugin that failed kept Firebase from starting at all
  (one `try` around both). Now each starts on its own, and Firebase is tried
  again by the next registration (at most every 30 s).
- **A registration waited on `getInitialMessage()`**, which the plugin
  resolves only once it has decided whether a notification opened the app. It
  now runs on its own with a 10 s limit; a registration never waits on it.
- **Apple's token was waited for 3 s**, then `pending`, and the page gave up
  after five of those (fifteen seconds in all). The shell waits 10 s, the page
  keeps trying for about five minutes and again on every foreground.
- **Nobody heard Apple refuse the app.** `AppDelegate.swift` now records
  `didFailToRegisterForRemoteNotificationsWithError` and answers it on the
  `ma.foorsa.student/push` channel (`apnsState`), and the shell reports it.
  The likeliest refusal is a build signed without `aps-environment`; see
  below.
- **The iPhone's banners while the app is open never showed, and their taps
  did nothing.** With no delegate of its own, firebase_messaging made itself
  the notification centre's delegate and answered for every notification,
  local ones included, with no banner (its foreground options are off). The
  app delegate is now the delegate, set in `didFinishLaunchingWithOptions`
  before `super` as Apple requires, and Flutter hands each callback to
  firebase_messaging and flutter_local_notifications alike: the "General
  setup" step of flutter_local_notifications' iOS instructions, which the app
  had skipped, as its own example app does it with a UIScene app delegate. The app's own
  banners also set `presentBanner` and `presentList`: since iOS 14
  `presentAlert` alone shows nothing.
- **A test**: `type: 'student_test'` pushes (Profile › Settings › Send me a
  test notification, `POST /api/portal/push/test`) show their fixed sentence
  as a banner even with the app open.

## The push entitlement in TestFlight builds

The App Store build is archived **unsigned** and signed by Apple at export
(cloud signing, README "iOS release build"). An unsigned archive carries no
entitlements of its own; if an export signs it without `aps-environment`,
APNs refuses the app ("no valid aps-environment entitlement string found for
application"), the APNs token never comes, and no iPhone can register: the
failure this document began with. Since 1 Nov 2026 the TestFlight workflow:

- checks the exported IPA (`scripts/push_entitlement.sh`, `codesign` and
  `plutil`) and lists its entitlements in the run's summary;
- in the cloud path, archives again **signed** (automatic signing,
  `APS_ENVIRONMENT=development` to match the development profile, which the
  App Store export turns into production) when the unsigned archive's export
  lacks it;
- marks a build whose `aps-environment` is not `production` with an error
  in the run and its summary, and still uploads it: holding the build back
  would hold back every other fix it carries, and push on it is no worse
  than on the build before.

Whether the builds up to 1.2.30 (61) carried it is not known from here (the
exported IPA was never kept): the next run's summary says, and an iPhone on a
build with this change reports Apple's own refusal if there is one.

## What only a real phone can confirm

- Apple's answer to the registration: the crash board shows `push: APNs
  token never arrived: …` with Apple's words if it refuses.
- FCM accepting a push for that token: Send me a test notification answers
  with FCM's code when it refuses (`THIRD_PARTY_AUTH_ERROR` means the APNs key
  is missing from the Firebase project's Cloud Messaging settings).
- The banner while the app is open, the banner in the background and on the
  lock screen, and a tap on each opening the right screen.
- After sign-out and sign-in, and after reinstalling, a new token registered.

`test/push_registration_test.dart` and `test/student_push_test.dart` pin the
logic, the iPhone delegate, the banner flags and the workflow's check.
