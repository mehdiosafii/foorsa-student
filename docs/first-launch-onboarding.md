# First-launch onboarding

Status: implementation branch; physical-device validation pending.

A first-time downloader opens the app on the native splash and boards through
a short onboarding before the sign-in. It is told with one object, Foorsa's
arrow. The splash is the arrow alone, in pearl glass; it becomes the
journey's airliner and climbs away. After that the arrow is the button: it
waits at the gate of the runway, the one control at the foot of the screen,
and the student's press sends it down the runway, into the air and up into
the picture, which folds into an arrow of light for it to dock in and
unfolds as the next picture while the next arrow rolls in. At the end it
cuts the boarding pass's stub off along the perforation, takes the pass into
itself and lands on the sign-in's own arrow. The portal loads underneath the
whole time, and its sign-in is drawn on the same night with the same runway
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
under it, and the runway. Each object does one thing, then settles. The
objects are made of the portal's own glass (`glass.dart`), paper ones aside.

| Step | Asks for | The object |
| --- | --- | --- |
| Welcome | nothing | one line of a split-flap board in a glass case, flipping through the voyage's 16 cities, with its reflection; a tap flips it |
| Notifications | `Permission.notification` | a stack of Foorsa's notifications on glass (the app's real texts), a new one landing on top every few seconds; a yes sends the front card up and the phone's own first notification down |
| Camera | `Permission.camera` | a drawn passport page, tipped back, found by the scanner's corners and straightened flat |
| Microphone | `Permission.microphone` | the chat's mic, a glass orb, with a voice running out from it on both sides; holding it makes the voice louder (nothing is recorded) |
| Location | `Permission.locationWhenInUse` | a night map under a glass lens, the blue dot with its heading, and the next prayer on a glass chip |
| Tracking | `Permission.appTrackingTransparency` | off, see below; a shield in a glass orb |
| Boarding pass | nothing | the pass; the arrow cuts its stub off, or the student tears it off |

A step is shown only when the phone will show its prompt (`denied` in
permission_handler: never asked on iOS, never asked or refused once on
Android). An access already granted, or refused for good, gets no screen.

## App Review rules this follows

Guideline 5.1.1(iv), as reviewers apply it: a screen shown before a
permission prompt must lead to the prompt.

- Its one control, the runway, says **Continue**, never Allow, and there is
  no Not now, Skip or close beside it. `test/onboarding_flow_test.dart` fails
  if a step's action changes. A screen reader hears it as a button named by
  its word; the arrow is drawing.
- Pressing it always leads to the prompt: the arrow rolls down the runway
  and the prompt shows the moment it lifts off, about half a second after
  the press (`test/onboarding_page_test.dart` pins that it asks then, and
  only then). The arrow hovers over the runway while the prompt is up.
- Whatever the student answers, the next step follows; nothing promises a
  reward for allowing (App Tracking Transparency forbids that too). A yes
  shows a check on the runway for a moment; a no simply moves on.
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
airliner at its tip; the welcome shows the wordmark instead, and a small
glass speaker in the corner turns the sound off. The headline is 32 pt bold
with tight tracking and the line under it 17 pt muted, both centred and
broken into even lines (`BalancedText`, like CSS `text-wrap: balance`), so no
word is left alone on a line.

**Glass** (`glass.dart`). The portal's material, ported from its CSS: clear,
not frosted, a smoked face, a rim that is hot where it faces the light at the
upper left and cold where it faces away, the slab's inner wall, light caught
in the bevel, and a shadow in three layers that never darkens the glass it is
under. `Glass.pane` is `.glass-2` on the portal's dark theme (the notification
cards, the board's case, the prayer chip), `Glass.tile` its lit
`.portal-tile-pane` (the runway, the mic and shield orbs, the speaker), and
`Glass.pearl` the arrow: a solid piece of pearl glass. Nothing blurs what is
behind it, as on the portal: on the night there is nothing a blur would show.

**The first picture is the arrow alone** (`takeoff_intro.dart`, 3.4 s). The
native launch image is rendered from the onboarding's own painter
(`scripts/onboarding_splash/render_splash_test.dart`, then
`dart run flutter_native_splash:create`), so frame one is the launch screen
exactly: the pearl-glass arrow, 100 pt tall, on the splash's navy, no roundel.
The arrow catches the light (a glow comes up behind it and a band of light
runs along it, and it draws a breath), then its outline flows into the
airliner's (`shape_morph.dart`: both outlines walked at even steps, turned the
same way round and lined up point for point): the arrow into the fuselage and
wings, its two trailing steps into the tailplanes, the plane pointing the way
the arrow points, the glass's light turning with it. The engines grow under
the wings, light runs along the fuselage, the navigation lights come on (red
left wingtip, green right, white strobes flashing twice, a red beacon), it
draws back a breath and climbs out to the upper right with two contrails.

**The arrow is the button** (`runway.dart`). The runway is a capsule of the
portal's lit glass with the arrow parked at its gate, pointing down it,
breathing and edging forward every few seconds, keen to go. A press holds it
back a little; the release sends it down the runway faster and faster, the
word leaving ahead of it and the runway's lights streaking behind it, and it
pitches up and lifts off past the far end.

**Into the picture** (`arrow_flight.dart`, `stage_morph.dart`). From where it
lifted off (or hovered while the phone asked) the arrow swoops up in one arc,
banking as it turns, a light trail behind it, growing as it comes, and rights
itself as it docks in the middle of the stage. As it nears, the picture folds
into an arrow made of light, only the pearl's edge and a breath of its face
(every step's object stands on one shape in the stage's middle,
`stage_forms.dart`, so the fold starts exactly from it), and the flying arrow
docks into that outline: one arrow, solid pearl. It swells a little, light
crosses it, and it unfolds into the next object's outline, over which the new
object fades in, while the next arrow rolls in to the gate with the next
word. Each object keeps its own glass until it is the arrow's pearl. Going
back (Android), the object folds into the arrow and unfolds on its own.

**Boarding.** The arrow lifts off the runway and swoops to the pass's left
notch, levels off and cuts along the perforation: the stub comes away behind
it and falls. From the right notch it climbs round into the middle as what
is left of the pass folds into it; it shines, and flies onto the sign-in's
own arrow, measured in the page (`portal_handover.dart`,
`[data-foorsa-mark]`); the shell says `foorsa:boarded`, the page replays its
entrance, and the onboarding fades onto the same night. Torn off by hand,
the stub is already gone and the arrow flies straight in. A page with no
arrow (not loaded, or already signed in) gets the fade alone.

**The first real notification.** When the student turns notifications on,
the front card of the stack flies up off the stage and the phone's own first
notification comes down from the top (`showFirstNotification`,
`onboarding_gate.dart`, on the channel Foorsa's updates use): "Notifications
are on. Replies from your adviser will show up here."

**Sound** (`onboarding_sound.dart`, composed by
`scripts/onboarding_sounds/compose.py`): one family of glass bells in E
major, air and paper, synthesized from nothing and passed through one
synthetic hall, so nothing is sampled or licensed, and a forty-second bed of
night music (a slow pad through E major's chords, a glass note now and then)
under the steps from the welcome until boarding, looped by starting a second
copy as the first fades. The intro is one file timed to its beats (a shimmer
as the arrow catches the light, a chord swelling as it becomes the plane, its
chime, two ticks for the strobes, air rising and passing to the right as it
climbs). The runway has its own: a glass tick on the press, the roll and the
lift, the swoop, a bright ring as the arrow docks, then the next picture's
note, one higher each step (E, F sharp, G sharp, B, C sharp, E), and a soft
tock as the next arrow stops at the gate. A yes has two rising notes; the
board its flaps; the cut stub a paper tear; boarding an arrival chord.

They are meant to be heard, which the first version was not: its cues peaked
at -13 dBFS, it played in iOS's ambient session (silenced by the ring/silent
switch) and on Android's interface-sound stream (near zero on most phones).
Now every cue lives above 180 Hz, where a phone's speaker plays, carries its
bells' upper partials, and is mastered loud (main cues around -10 to -15
LUFS, peaks a decibel or two under full scale, transients held down). They
play as media: on an iPhone the playback session mixed with whatever else is
playing (the student's music never stops), so the silent switch does not
silence them and the speaker in the corner does; on Android the media stream,
with no audio focus. Nothing plays while the app is in the background (the
app has the audio background mode, which would otherwise keep the bed
playing). The intro loads first, behind the native splash, and a late one
starts where the picture has got to; the rest load behind it. Everything is
let go six seconds after boarding, when the session goes back to iOS's
default. To change one, edit the script and run it with `--encode`.

Touch stays for moments that mean something (`shell_haptics.dart`): `unfold`
and `release` as the plane forms and leaves, `press` on a press, `release` at
lift-off, a light `detent` as the arrow docks and as the next one stops at the
gate, `land` when an access is turned on and when the arrow lands on the
sign-in's, `grain` as the stub comes away and `release` when it falls.

Reduce Motion skips the flights and the morphs: the arrow stays at the gate,
the prompt comes at once, the objects stand still and the steps cross-fade;
the sounds still play. Objects are illustrations at a fixed text size; the
words under them follow the phone's text size, smaller on short screens, and
below 200 pt of room the screen scrolls. Android's back goes one step back.

## Required device verification

- Fresh install on a physical iPhone and Android phone: the launch screen is
  the arrow alone, and frame one of the onboarding matches it; every prompt
  appears once the runway's arrow lifts off, and a yes shows the check on the
  runway.
- The sounds: audible on the phone's speaker with the silent switch on and
  off, in time with the picture; the speaker in the corner silences them;
  music already playing keeps playing; nothing plays after the app goes to
  the background.
- Turning notifications on shows the phone's own first notification.
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

- `flutter analyze` and `flutter test`: the plan, the copy rules, the
  permission mapping, the store, the morph engine, the glass (outlines grown
  for a shadow's spread, every material mixing into every other), the
  runway's arrow (it leaves the runway exactly where the flight takes it
  over), the swoop (it ends on the stage's arrow, its size and way round, and
  stays on screen), the fold timed to the docking, every object inside its
  stage, the arrow's geometry, the whole walk through with fake permissions
  (the prompt only once the arrow is in the air, the runway's sounds, a chime
  per yes), the speaker, back, the hand-off onto the sign-in's arrow, and
  every step on a 320 x 568 phone, an iPhone SE and a large phone with large
  text.
- Rendered every screen and the full flow at 60 fps in the Flutter test
  renderer, with mock-ups of iOS's prompts and its notification banner for
  the recording only, and mixed the sounds in at the frames they were played,
  normalised to -16 LUFS.

These do not replace a run on real phones: the prompts, the haptics, the
audio session and the WebView loading underneath are native.
