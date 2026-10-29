# First-launch onboarding

Status: implementation branch; physical-device validation pending.

A first-time downloader opens the app on the native splash and boards through
a short onboarding before the sign-in: the splash's F becomes the journey's
airliner and takes off, a departures board welcomes them, one screen asks for
each phone access the app can still ask for, and a boarding pass ends it. The
portal loads underneath the whole time, so when the student tears the stub off
(or taps Board) the sign-in opens through a widening circle, already loaded.

Code: `lib/src/onboarding/`. The words and the order are in
`onboarding_flow.dart`; the gate that decides who sees it is
`onboarding_store.dart` and `onboarding_gate.dart`.

## Who sees it

Only first-time downloaders. An update from an older build has used the
portal already, which leaves the WebView's data on the phone (`app_webview` on
Android, `Library/WebKit` on iOS); those students go straight to the portal as
before, and the old "Set up your device" reminder keeps its behaviour on later
openings. The onboarding is recorded `started` before anything else runs and
`done` when the student boards, so a first launch closed halfway opens on it
again. During the launch that shows the onboarding, the reminder does not
open.

## The steps

| Step | Asks for | Shows |
| --- | --- | --- |
| Welcome | nothing | a split-flap departures board of the voyage's 16 cities; a tap flips it |
| Notifications | `Permission.notification` | the lock screen with Foorsa's real notification texts arriving |
| Camera | `Permission.camera` | a specimen passport page found, read and flattened as the scanner does |
| Microphone | `Permission.microphone` | the live chat: a voice note recorded, sent, read and answered; holding the mic tries it (nothing is recorded) |
| Location | `Permission.locationWhenInUse` | a night map of Hangzhou: the next prayer, the weather, a supermarket nearby |
| Tracking | `Permission.appTrackingTransparency` | off, see below |
| Boarding pass | nothing | the pass, printed, with the student's choices on it |

A step is shown only when the phone will show its prompt (`denied` in
permission_handler: never asked on iOS, never asked or refused once on
Android). An access already granted, or refused for good, gets no screen.

## App Review rules this follows

Guideline 5.1.1(iv), as reviewers apply it: a screen shown before a
permission prompt must lead to the prompt.

- Its one button says **Continue**, never Allow, and there is no Not now,
  Skip or close beside it. `test/onboarding_flow_test.dart` fails if a step's
  action changes.
- Whatever the student answers, the next step follows; nothing promises a
  reward for allowing (App Tracking Transparency forbids that too). The pass
  shows what is on and off, as a status, never as a prize.
- Each prompt's words are the purpose strings already in `Info.plist`.

## Tracking is off

`OnboardingConfig.asksToTrack` is false. The app does not track: the privacy
manifest says `NSPrivacyTracking` false, the App Store label says no tracking,
and the privacy notice says "The Student app does not use advertising
tracking". Asking students to allow it would contradict all three. The screen
is built and tested; turn it on in the same change that adds ad measurement
(an attribution SDK), together with:

1. `'PERMISSION_APP_TRACKING_TRANSPARENCY=1'` in the macros in `ios/Podfile`;
2. `NSUserTrackingUsageDescription` in `ios/Runner/Info.plist`;
3. `NSPrivacyTracking` true and the tracking domains in
   `ios/Runner/PrivacyInfo.xcprivacy`, and the App Store privacy label;
4. the privacy notice (`public/privacy-policy.html` in foorsa-reward).

A build can try the screen with `--dart-define=FOORSA_ASK_TO_TRACK=true`; on
iOS that also needs items 1 and 2, or the plugin reports it refused.

## How it feels

The look is the portal's dark theme (`portal.css`, `portalMaterials.css`):
its ink and muted text, the pale steel accent, glass panels, the pearl main
button, the backdrop's folds over the splash's navy, and the boarding pass of
`flightPass.css`. The wordmark, the F mark, the airliner and the icons are
drawn from the portal's own vectors (`brand_vectors.dart`, `airliner.dart`,
`lucide.dart`). Motion uses the portal's springs (damping and response, as
`fluid.ts`), and touch uses the shell's textures by name (`shell_haptics.dart`):
`unfold` as the plane assembles, `release` as it takes off, `press` on a tap,
`detent` when the scanner locks, `land` for an access turned on, `grain` as
the pass prints and as the stub tears.

Reduce Motion skips the flight, stands every scene still and cross-fades the
steps. Scenes are illustrations at a fixed text size; the words under them
follow the phone's text size, smaller on short screens, and below 220 pt of
scene the screen scrolls. Android's back goes one step back.

## Required device verification

- Fresh install on a physical iPhone and Android phone: every prompt appears
  after its Continue, and its answer reaches the pass.
- Update over an installed build: no onboarding.
- Kill the app mid-onboarding, reopen: it opens on the onboarding again.
- Android 12 and older (no notification prompt): the notifications step is
  skipped. Android 13+: it is shown.
- A refused access: no screen next time; the old reminder offers Settings.
- VoiceOver and TalkBack through every step; Reduce Motion; largest text.
- After boarding: the push token registers on sign-in without a second
  prompt, the status bar follows the portal again, an incoming adviser call
  shows over the onboarding.

## Validation performed locally

- `flutter analyze` and `flutter test` (the onboarding's 23 tests among the
  suite): the plan, the copy rules, the permission mapping, the store, the
  whole walk through with fake permissions, back, and every step on a 320 x
  568 phone, an iPhone SE and a large phone with large text.
- Rendered every screen and the full flow at 60 fps in the Flutter test
  renderer, with a mock-up of iOS's prompts for the recording only.

These do not replace a run on real phones: the prompts, the haptics and the
WebView loading underneath are native.
