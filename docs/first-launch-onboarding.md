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

Every screen is the same three things under one object: a headline, one line
under it, and one button. Each object does one thing, then settles.

| Step | Asks for | The object |
| --- | --- | --- |
| Welcome | nothing | one line of a split-flap board, flipping through the voyage's 16 cities, with its reflection; a tap flips it |
| Notifications | `Permission.notification` | a stack of Foorsa's notifications (the app's real texts), a new one landing on top every few seconds |
| Camera | `Permission.camera` | a drawn passport page, tipped back, found by the scanner's corners and straightened flat |
| Microphone | `Permission.microphone` | the chat's mic with a voice running out from it on both sides; holding it makes the voice louder (nothing is recorded) |
| Location | `Permission.locationWhenInUse` | a night map seen through a fading lens, the blue dot with its heading, and the next prayer |
| Tracking | `Permission.appTrackingTransparency` | off, see below; a shield |
| Boarding pass | nothing | the pass, which lies down flat as Wallet adds a card; its stub tears off |

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
  reward for allowing (App Tracking Transparency forbids that too). A yes
  shows a check on the button for a moment; a no simply moves on.
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

Less is more: every screen is one lit object on a still night, so nothing
competes with the one thing it says. The ground is the night the native
splash deepens into, a few faint stars high up and one soft light behind the
object (`night_sky.dart`). Progress is one hairline with the journey's
airliner at its tip; the welcome shows the wordmark instead. The headline is
32 pt bold with tight tracking and the line under it 17 pt muted, both centred
and broken into even lines (`BalancedText`, like CSS `text-wrap: balance`), so
no word is left alone on a line. The one button is the portal's flat pearl
pill (`--portal-primary-fill`).

The colours are the portal's dark theme (`portal.css`, `portalMaterials.css`)
and the pass is `flightPass.css`'s paper and ink. The wordmark, the airliner
and the icons are drawn from the portal's own vectors (`brand_vectors.dart`,
`airliner.dart`, `lucide.dart`). Motion uses the portal's springs (damping and
response, as `fluid.ts`): an object comes in from a little smaller and lower,
the words follow it a beat apart. Touch is kept for moments that mean
something (`shell_haptics.dart`): `unfold` and `release` as the plane takes
off, `press` on a tap, `land` when an access is turned on and when the pass
lies down, `grain` as the stub tears and `release` when it comes off. Nothing
buzzes on its own.

Reduce Motion skips the flight, stands every object still and cross-fades the
steps. Objects are illustrations at a fixed text size; the words under them
follow the phone's text size, smaller on short screens, and below 200 pt of
room the screen scrolls. Android's back goes one step back.

## Required device verification

- Fresh install on a physical iPhone and Android phone: every prompt appears
  after its Continue, and a yes shows the check on the button.
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

- `flutter analyze` and `flutter test` (the onboarding's 26 tests among the
  suite): the plan, the copy rules, the permission mapping, the store, the
  whole walk through with fake permissions, back, and every step on a 320 x
  568 phone, an iPhone SE and a large phone with large text.
- Rendered every screen and the full flow at 60 fps in the Flutter test
  renderer, with a mock-up of iOS's prompts for the recording only.

These do not replace a run on real phones: the prompts, the haptics and the
WebView loading underneath are native.
