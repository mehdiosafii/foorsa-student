# First-launch onboarding

Status: implementation branch; physical-device validation pending.

A first-time downloader opens the app on the native splash and boards through
a short onboarding before the sign-in. It is told with one object: the F of
the splash is an arrow, the arrow becomes the journey's airliner and climbs
away, and between every two steps the object on the stage melts back into the
arrow and unfolds into the next. At the end the boarding pass becomes the
arrow once more and lands on the sign-in's own arrow. The portal loads
underneath the whole time, and its sign-in is drawn on the same night
(NightStage.tsx in foorsa-reward), so the onboarding simply fades onto it.

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

**The arrow becomes the plane** (`takeoff_intro.dart`, 3.4 s). Frame one is
the launch screen. The roundel's white opens like an iris and lets go as a
ring of light; exactly where it has opened, the F turns from navy to pearl, so
the inversion runs out from the middle. The F's outline then flows into the
airliner's (`shape_morph.dart`: both outlines walked at even steps, turned the
same way round and lined up point for point): the arrow into the fuselage and
wings, its two trailing steps into the tailplanes, the plane pointing the way
the arrow points. Mid-change it glows and softens for a moment. The engines
grow under the wings, light runs along the fuselage, the navigation lights
come on (red left wingtip, green right, white strobes flashing twice, a red
beacon), it draws back a breath and climbs out to the upper right with two
contrails.

**Between steps the object becomes the arrow and the arrow the next object**
(`stage_morph.dart`, 1.05 s). Every step's object stands on one shape in the
stage's middle (`stage_forms.dart`: the board's line, the front notification,
the passport page, the mic, the map's lens, the shield, the pass), and each
scene starts exactly there, at rest. The old object fades over its own
outline, the outline flows into the arrow (its two steps growing out of it),
the arrow swells a little and light crosses it, and it unfolds into the next
object's outline, over which the new object fades in. Each object keeps its
colour until the arrow is pearl.

**Boarding.** The stub tears away; what is left of the pass becomes the
arrow; the shell measures where the sign-in draws its arrow
(`portal_handover.dart`, `[data-foorsa-mark]`) and the arrow flies onto it;
the shell says `foorsa:boarded`, the page replays its entrance, and the
onboarding fades onto the same night. A page with no arrow (not loaded, or
already signed in) gets the fade alone.

**Sound** (`onboarding_sound.dart`, composed by
`scripts/onboarding_sounds/compose.py`): one family of soft glass bells in E
major, air and paper, synthesized from nothing and passed through one
synthetic hall, so nothing is sampled or licensed. The intro's sound is one
file timed to its beats (a breath as the iris opens, a chord swelling as the
arrow becomes the plane, its chime, two ticks for the strobes, air rising and
passing to the right as it climbs). Each transition sounds a breath and a
glass note at the arrow, one note higher each step forward (E, F sharp, G
sharp, B, C sharp, E), so the onboarding plays a scale, and back goes down.
A yes has two rising notes; the button a barely there tock; the board its
flaps; the stub a paper tear; boarding an arrival chord. On an iPhone they
play in the ambient session, so the ring/silent switch silences them and they
never stop the student's music; on Android as interface sounds with no audio
focus. They are loaded behind the native splash (at most 700 ms; the intro is
dropped rather than played late), and let go six seconds after boarding,
when the session goes back to iOS's default. To change one, edit the script
and run it with `--encode`.

Touch stays for moments that mean something (`shell_haptics.dart`): `unfold`
and `release` as the plane forms and leaves, `press` on a tap, a light
`detent` at each arrow, `land` when an access is turned on, `grain` as the
stub tears and `release` when it comes off.

Reduce Motion skips the flight and the morphs, stands every object still and
cross-fades the steps; the sounds still play. Objects are illustrations at a
fixed text size; the words under them follow the phone's text size, smaller
on short screens, and below 200 pt of room the screen scrolls. Android's back
goes one step back.

## Required device verification

- Fresh install on a physical iPhone and Android phone: every prompt appears
  after its Continue, and a yes shows the check on the button.
- The sounds: in time with the picture, silent with the iPhone's silent
  switch on, and music already playing keeps playing.
- Boarding lands the arrow on the sign-in's arrow exactly, with and without a
  notch, and on a small phone where the sign-in scrolls.
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

- `flutter analyze` and `flutter test` (the onboarding's 33 tests among the
  suite): the plan, the copy rules, the permission mapping, the store, the
  morph engine, every object inside its stage, the arrow's geometry, the
  whole walk through with fake permissions (the scale of step notes, a chime
  per yes), back, the hand-off onto the sign-in's arrow, and every step on a
  320 x 568 phone, an iPhone SE and a large phone with large text.
- Rendered every screen and the full flow at 60 fps in the Flutter test
  renderer, with a mock-up of iOS's prompts for the recording only.

These do not replace a run on real phones: the prompts, the haptics and the
WebView loading underneath are native.
