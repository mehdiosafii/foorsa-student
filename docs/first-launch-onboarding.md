# First-launch onboarding

Status: implementation branch; physical-device validation pending.

A first-time downloader opens the app on the native splash and boards through
a short onboarding before the sign-in. It is told with one object, Foorsa's
arrow. The splash is the arrow alone, in pearl glass; it becomes the
journey's airliner and climbs away.

There are no buttons. On each screen the student acts on the object itself,
wherever it stands: throws the arrow up into the departures board, taps the
notification, puts the passport page in the scanner's frame, taps the mic,
taps the map's locate arrow, tears the boarding pass's stub off. What to do
is said quietly under the object. Between screens the object folds into the
arrow and unfolds as the next one; where the object is itself an arrow (the
one under the board, the one in the map's button) it flies up into the
picture, which folds into an arrow of light for it to dock in. At the end
what is left of the pass folds into the arrow, which lands on the sign-in's
own arrow. The portal loads underneath the whole time, and its sign-in is
drawn on the same night (NightStage.tsx in foorsa-reward), so the onboarding
simply fades onto it.

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

Every screen is a headline and one line under it, then one object under
them that is the screen's control, and under the object, quietly, what to do
with it. The object is in a different place and a different shape on every
screen; there is no button bar. Each object does one thing, then settles. The
objects are made of the portal's own glass (`glass.dart`), paper ones aside.

| Step | Asks for | The object, and what the student does |
| --- | --- | --- |
| Welcome | nothing | one line of a split-flap board in a glass case, flipping through the voyage's 16 cities (a tap flips it), and under it Foorsa's arrow, resting. **Swipe up to begin**: the arrow is thrown up into the board, or tapped |
| Notifications | `Permission.notification` | a stack of Foorsa's notifications on glass (the app's real texts), a new one landing on top every few seconds. **Tap the notification**; a yes sends the front card up and the phone's own first notification down |
| Camera | `Permission.camera` | the scanner's frame, and a drawn passport page that lifts out of it into the hand, tipped and turned. **Drag the page into the frame**: it straightens as it nears, the corners close on it, and let go close enough it is taken with a soft flash (a tap puts it in) |
| Microphone | `Permission.microphone` | the chat's mic, a glass orb, with a voice running out from it on both sides. **Tap the mic**; pressed, the voice comes up (nothing is recorded) |
| Location | `Permission.locationWhenInUse` | a night map under a glass lens, and on its edge the map's locate button, which is Foorsa's arrow. **Tap the arrow to find yourself**; a yes drops the blue dot onto the map with its heading and the next prayer on a glass chip, then the arrow leaves the button and glides into the map |
| Tracking | `Permission.appTrackingTransparency` | off, see below; a shield in a glass orb. **Tap the shield** |
| Boarding pass | nothing | the pass, PULL TO BOARD printed on its stub. **The stub is pulled down and off** (a tap tears it too) |

A step is shown only when the phone will show its prompt (`denied` in
permission_handler: never asked on iOS, never asked or refused once on
Android). An access already granted, or refused for good, gets no screen.

## App Review rules this follows

Guideline 5.1.1(iv), as reviewers apply it: a screen shown before a
permission prompt must lead to the prompt.

- There is no button, and nothing on the screen says Allow. The one way on
  is the object, and acting on it always leads to the prompt, the moment it
  is touched (`test/onboarding_page_test.dart` pins that it asks then, and
  only then). There is no Not now, Skip or close.
- For a screen reader each object is a button named **Continue**
  (`test/onboarding_flow_test.dart` fails if a step's name changes), and its
  usual activation does what the gesture does. The words under the object
  are for the eye only.
- Whatever the student answers, the next step follows; nothing promises a
  reward for allowing (App Tracking Transparency forbids that too). A yes
  shows on the object for a moment (the notification goes up, the page is
  read, the voice comes up, the dot drops onto the map); a no simply moves
  on.
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
32 pt bold with tight tracking and the line under it 17 pt muted, at the top,
centred and broken into even lines (`BalancedText`, like CSS
`text-wrap: balance`), so no word is left alone on a line. The object sits
under them, a little above the middle of what is left, in reach of a thumb;
on a tall phone some of the extra height stays under it rather than between
it and the words.

**What to do** (`scene_hint.dart`). Under the object, a beat after it
appears, one quiet line (15 pt, muted, breathing) says the gesture: Swipe up
to begin, Tap the notification, Drag the page into the frame. It lets a touch
through to the object under it, and goes once the student has acted. Every
few seconds an object that has been waiting shows it can be acted on with one
small movement (`idleNudge`): the arrow hops, the page drifts towards the
frame, a ring goes out from the mic, the map's arrow hops along its own way,
the stub tugs at the perforation. A tap on the map, rather than its arrow,
makes the arrow answer. Every press is felt and heard alike (a glass tick).

**Glass** (`glass.dart`). The portal's material, ported from its CSS: clear,
not frosted, a smoked face, a rim that is hot where it faces the light at the
upper left and cold where it faces away, the slab's inner wall, light caught
in the bevel, and a shadow in three layers that never darkens the glass it is
under. `Glass.pane` is `.glass-2` on the portal's dark theme (the notification
cards, the board's case, the prayer chip), `Glass.tile` its lit
`.portal-tile-pane` (the mic and shield orbs, the map's locate button), and
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

**The welcome's arrow** (`scene_welcome.dart`). Under the board the arrow
rests, floating, a pool of its light on the stage under it, and hops now and
then. Drawn up, it turns to the way it is pulled and its light comes up;
thrown (past 64 pt, or flicked faster than 420 pt/s), it flies on at the
speed it was thrown, straight up into the board, which folds to meet it
(`FlightTimes.thrown`: docked 0.38 s after it leaves the finger). Let go
short, it springs back and waits. A tap throws it too.

**Into the picture** (`arrow_flight.dart`, `stage_morph.dart`). A flying arrow
grows as it comes, a light trail behind it, and rights itself as it docks in
the middle of the stage. As it nears, the picture folds into an arrow made of
light, only the pearl's edge and a breath of its face (every step's object
stands on one shape in the stage's middle, `stage_forms.dart`, so the fold
starts exactly from it), and the flying arrow docks into that outline: one
arrow, solid pearl. It swells a little, light crosses it, and it unfolds into
the next object's outline, over which the new object fades in, and the words
follow. The thrown arrow points the way it flies and banks as it turns; the
map's arrow, whose way to the middle would turn it round, glides in level,
still pointing its own way (`Swoop.follow`). Where no arrow flies, the object
itself folds into the arrow and unfolds as the next one, its note sounding as
it unfolds. Each object keeps its own glass until it is the arrow's pearl.
Going back (Android), the same, the other way.

**The scanner** (`scene_scan.dart`). The page arrives in the frame, as the
last object became it, then lifts out into the hand: tipped back, turned, a
little smaller, its shadow lifted. The scanner's corners stay on the frame,
looking. Dragged, it follows the finger; near the frame it straightens and
the corners close on it (a detent as they find it); let go close enough, or
thrown towards it, it springs home and is taken: the corners pinch, a soft
flash, the shutter. Let go short, it goes back to the hand.

**Boarding.** The stub is pulled down: the paper gives (a run of small rips)
past seven tenths of the way, and the stub comes off and falls. What is left
of the pass folds into the arrow, which shines and flies onto the sign-in's
own arrow, measured in the page (`portal_handover.dart`,
`[data-foorsa-mark]`); the shell says `foorsa:boarded`, the page replays its
entrance, and the onboarding fades onto the same night. If the page has not
answered by the time the arrow has shone, the arrow shines on until it does
(0.9 s at most). A page with no arrow (not loaded, or already signed in) gets
the fade alone.

The fade moves nothing, because by then both nights are the same picture.
The stage's light flies with the arrow and ends the size of the light behind
the sign-in's (540 across beside a 64 pt arrow, 420 beside a 48). It is never
drawn under the status bar (`UnderStatusBar`), where the shell paints the
page's colour flat. The stars are placed in the web view's frame, under the
status bar (`statusBarHeight`), as the page places its own. Their drift
springs back to none as the stub comes off. Until then, the light stayed in
the middle of the screen and the stars sat up to 46 pt higher and drifted
sideways, so the fade swapped one sky for another.

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
climbs). Every press on an object is a glass tick; the scanner taking the
page a soft double click and a breath of light; a flying arrow a swoop of
air and a bright ring as it docks; then the next picture's note, one higher
each step (E, F sharp, G sharp, B, C sharp, E). A yes has two rising notes;
the board its flaps; the stub a quick tear as the paper gives; boarding an
arrival chord.

They are meant to be heard, which the first version was not: its cues peaked
at -13 dBFS, it played in iOS's ambient session (silenced by the ring/silent
switch) and on Android's interface-sound stream (near zero on most phones).
Now every cue lives above 180 Hz, where a phone's speaker plays, carries its
bells' upper partials, and is mastered loud (main cues around -10 to -15
LUFS, peaks a decibel or two under full scale, transients held down). They
play as media: on an iPhone the playback session mixed with whatever else is
playing (the student's music never stops), so the silent switch does not
silence them and the phone's volume buttons set how loud they are; on
Android the media stream, with no audio focus. There is no speaker button on
the screen: the volume buttons are the control. Nothing plays while the app is in the background (the
app has the audio background mode, which would otherwise keep the bed
playing). The intro loads first, behind the native splash, and a late one
starts where the picture has got to; the rest load behind it. Everything is
let go six seconds after boarding, when the session goes back to iOS's
default. To change one, edit the script and run it with `--encode`.

Touch stays for moments that mean something (`shell_haptics.dart`): `unfold`
and `release` as the plane forms and leaves, `press` on every press, `grain`
as the arrow is drawn up and as the stub is pulled, `release` as the arrow is
thrown and as the stub falls, a light `detent` as the arrow docks, as the
scanner's corners find the page and close on it, and as something let go
short springs back, and `land` when an access is turned on and when the arrow
lands on the sign-in's.

Reduce Motion skips the flights and the morphs: the objects stand still (a
finger still moves the arrow, the page and the stub, which is the student's
own motion), the prompt comes the moment the object is touched, and the
steps cross-fade; the sounds still play. Objects are illustrations at a fixed
text size; the words above them follow the phone's text size, smaller on
short screens, and below 220 pt of room the screen scrolls. Android's back
goes one step back.

## Required device verification

- Fresh install on a physical iPhone and Android phone: the launch screen is
  the arrow alone, and frame one of the onboarding matches it; every prompt
  appears the moment its object is acted on.
- The gestures on a real screen: the throw (and a short pull springing back),
  the page dragged into the frame with a thumb, the stub pulled, each hint
  readable under its object, nothing under the home indicator.
- The sounds: audible on the phone's speaker with the silent switch on and
  off, in time with the picture; the volume buttons set their level; music
  already playing keeps playing; nothing plays after the app goes to the
  background.
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
  for a shadow's spread, every material mixing into every other), the throw
  (faster throws carry on faster, never overshooting; the arrow turns to the
  way it is pulled; a short pull springs back), the swoop (it ends on the
  stage's arrow, its size and way round, and stays on screen) and the glide
  (level, pointing its own way), the fold timed to the docking for both
  flights, the locate arrow on the lens's edge, the idle nudge, every object
  inside its stage, the arrow's geometry, the whole walk through with fake
  permissions (one gesture per object, the prompt the moment it is touched,
  no button and no Allow on screen, a chime per yes, the shutter), the page
  dragged into the frame (and not taken when let go short), the map's arrow
  flying on once the dot is found, back, the stub torn by hand and the arrow
  landing on the sign-in's own, and every step on a 320 x 568 phone, an iPhone
  SE and a large phone with large text.
- Rendered every screen and the full flow at 60 fps in the Flutter test
  renderer, with mock-ups of iOS's prompts and its notification banner for
  the recording only, and mixed the sounds in at the frames they were played,
  normalised to -16 LUFS.

These do not replace a run on real phones: the prompts, the haptics, the
audio session and the WebView loading underneath are native.
