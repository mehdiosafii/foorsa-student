# First-launch onboarding

Status: implementation branch; physical-device validation pending.

A first-time downloader opens the app on the native splash and boards through
a short onboarding before the sign-in. It is told with one object, Foorsa's
arrow. The splash is the arrow alone, in pearl glass; it becomes the
journey's airliner and climbs away.

There are no buttons. On each screen the student acts on the object itself,
wherever it stands: throws the arrow up into the departures board, taps the
notification, puts the passport page in the scanner's frame, taps the mic,
taps the map's locate arrow, tears the boarding pass's stub off. Every
screen says exactly what to do, in one clear line next to the object, and
shows it: a touch of glass does the gesture on the object itself, every few
seconds, until the student does. Between screens the object folds into the
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
them that is the screen's control, and next to the object what to do with
it, said in one clear line and shown by a touch doing it on the object. The
object is in a different place and a different shape on every
screen; there is no button bar. Each object does one thing, then settles. The
objects are made of the portal's own glass (`glass.dart`), paper ones aside.

| Step | Asks for | The object, and what the student does |
| --- | --- | --- |
| Welcome | nothing | one line of a split-flap board in a glass case, flipping through the voyage's 16 cities (a tap flips it), and under it Foorsa's arrow, resting. **Swipe the arrow up to begin**: the arrow is thrown up into the board, or tapped |
| Notifications | `Permission.notification` | a stack of Foorsa's notifications on glass (the app's real texts), a new one landing on top every few seconds. **Tap the notification**; a yes sends the front card up and the phone's own first notification down |
| Camera | `Permission.camera` | the scanner's frame, and a drawn passport page that lifts out of it into the hand, tipped and turned. **Drag the page into the frame**: it straightens as it nears, the corners close on it, and let go close enough it is taken with a soft flash (a tap puts it in) |
| Microphone | `Permission.microphone` | the chat's mic, a glass orb, with a voice running out from it on both sides. **Tap the mic**; pressed, the voice comes up (nothing is recorded) |
| Location | `Permission.locationWhenInUse` | a night map under a glass lens, and on its edge the map's locate button, which is Foorsa's arrow. **Tap the arrow to find yourself**; a yes drops the blue dot onto the map with its heading and the next prayer on a glass chip, then the arrow leaves the button and glides into the map |
| Tracking | `Permission.appTrackingTransparency` | off, see below; a shield in a glass orb. **Tap the shield** |
| Boarding pass | nothing | the pass, PULL TO BOARD printed on its stub. **Pull the stub down to board**: it comes off (a tap tears it too) |

The words in bold are the line each screen shows next to its object, and the
gesture its touch does there (see **What to do** below).

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
  usual activation does what the gesture does. The button says what to do
  after its name, as a screen reader's double tap does it ("Double-tap the
  notification to go on", "Double-tap to put the page in the frame"); the
  words under the object are for the eye, so a screen reader does not read
  them twice. The boarding pass's stub is its own button, **Board**, apart
  from the pass's description.
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
airliner at its tip, and under it, as a departures board prints it, which
step this is of how many (STEP 2 OF 5, said to a screen reader as "Setting
up, Step 2 of 5"; `route_progress.dart`). The welcome is the cover: it shows
the wordmark instead, and the count starts after it. The headline is
32 pt bold with tight tracking and the line under it 17 pt muted, at the top,
centred and broken into even lines (`BalancedText`, like CSS
`text-wrap: balance`), so no word is left alone on a line. The object sits
under them, a little above the middle of what is left, in reach of a thumb;
on a tall phone some of the extra height stays under it rather than between
it and the words.

**What to do** (`scene_hint.dart`, `gesture_demo.dart`). The owner tried the
first version and found it confusing what to do next: one quiet, muted line
that came in 900 ms late and breathed, and a small hop of the object now and
then. Now every scene says it and shows it, with no button added: the object
is still the only way on.

- **Said.** One line next to the object, under it, verb first, naming the
  object: Swipe the arrow up to begin, Tap the notification, Drag the page
  into the frame, Tap the mic, Tap the arrow to find yourself, Tap the
  shield, Pull the stub down to board. 17 pt semibold in the portal's accent
  (`#A9C8E6`, the colour that means "you can press this"), steady, at least
  7:1 on the night and on the light behind the object (WCAG AA asks 4.5:1).
  It follows the phone's text size (never smaller, up to a quarter larger)
  and stays on one line, shrinking to fit a narrow phone. It comes in with
  the object and goes once the student has acted. On a short stage it moves
  up to stay on the screen, never over its object; the boarding pass gives
  up to a fifth of its size on a short phone so the line fits under it
  (`passScale`), and a screen too short for everything scrolls far enough to
  read it.
- **Shown.** A touch, a bead of the portal's glass tinted with the accent,
  does the scene's own gesture on the object, where the object really is
  (each scene's geometry: `welcomeDemo`, `notificationsDemo`, `scanDemo`,
  `voiceDemo`, `locationDemo`, `trackingDemo`, `boardingDemo`). A tap comes
  down, a little low and right of a round object's middle as a thumb would,
  presses (its shadow tightens) and a ring goes out from the object's own
  edge, the card's rounded outline or the orb's circle. A swipe, a drag or a
  pull travels the gesture's way with a soft tail of light behind it: the
  welcome's touch flicks up from the arrow into the board's foot; the
  camera's takes the page from the hand most of the way into the frame (the
  corners close on it, no flash) and lets it settle back; the pass's pulls the
  stub down from just under the perforation to the pass's foot. The object
  answers the touch as it would a finger: the arrow lifts with the flick, the
  page goes with the drag, the stub gives under the pull, the map's arrow
  hops as its button is pressed. Each touch goes exactly as far as the
  gesture needs: a student who does what it shows moves on
  (`test/onboarding_guidance_test.dart` copies each one at its own pace).
  It starts 0.3 s after the object is ready (the camera's once the page has
  lifted into the hand), takes about a second, and comes back every 2.8 to
  3.6 s. A finger anywhere on the picture sends it away at once (it fades in
  80 ms); let go without having acted and it comes back 1.4 s later; once the
  student has acted it is gone. The scene's own ring that went out from the
  mic now and then is gone: the touch's ring replaces it.
- **Insisting.** After 6 s with nothing touched, the cue speaks up over
  0.8 s: the line turns white and grows a little, the touch is larger with a
  stronger light, its ring wider and brighter.
- **Reduce Motion.** No touch moves: a still pair of chevrons points the
  gesture's way, where the touch would be (at the object for a tap, from
  above it, or from outside the map for its arrow; up between the arrow and
  the board; on the passport, an arrow from the page to the frame, in the
  page's ink; down under the pass), and the line stays. Insisting, the line
  turns white and the chevrons brighten and grow a little.

None of it takes a touch or is read out: both layers let the touch through
to the object under them (`IgnorePointer`). Every press is felt; the guide
makes no sound and no haptic of its own.

The camera's page follows the finger from the moment it is touched
(`DragStartBehavior.down`): before, the first 36 pt of a drag were the pan's
slop and moved nothing, so the page trailed the finger and a drag as long as
the page's way into the frame fell short.

**Glass** (`glass.dart`). The portal's material, ported from its CSS: clear,
not frosted, a smoked face, a rim that is hot where it faces the light at the
upper left and cold where it faces away, the slab's inner wall, light caught
in the bevel, and a shadow in three layers that never darkens the glass it is
under. `Glass.pane` is `.glass-2` on the portal's dark theme (the notification
cards, the board's case, the prayer chip), `Glass.tile` its lit
`.portal-tile-pane` (the mic and shield orbs, the map's locate button), and
`Glass.pearl` the arrow: a solid piece of pearl glass. Nothing blurs what is
behind it, as on the portal: on the night there is nothing a blur would show.
On Android its soft light is drawn once and kept as pictures while the
onboarding runs (`GlassBake`, see **Android** below).

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
itself folds into the arrow and unfolds as the next one. Each object keeps its
own glass until it is the arrow's pearl.
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
`scripts/onboarding_sounds/compose.py`): few sounds, and quiet. The first
versions were glass bells synthesized from nothing and mastered almost to full
scale, and nearly every touch rang: a tick on each press, a note on each step,
a ring on each dock, over a loop of bells, 25 sounds in the first 43 seconds.
It sounded like a toy. Now:

- The music is played by sampled instruments (piano, harp, strings and
  celesta, and in the bed a koto for a guzheng and a flute for a dizi, from
  the MuseScore General soundfont, MIT licence), rendered by fluidsynth
  through one soft hall. The cues are in E major; the bed is in its relative
  minor.
- What makes a sound in the story is a recording of a real thing, from
  BigSoundBank under CC0 (`scripts/onboarding_sounds/foley/SOURCES.md`): the
  departures board's flaps (a small ratchet's teeth, slowed into card and
  re-timed into a row settling), the arrow's air (a rope swung through the
  air), the scanner's shutter (a Kodak Instamatic), the stub (a sheet of
  paper torn off) and a small temple gong.
- A plain press and a step changing make no sound: the haptics carry them.

The intro is one file timed to its beats: low strings as the arrow wakes, a
celesta note as it catches the light, a harp running up as it becomes the
plane, two piano notes for its lights, then a chord and the air rising as it
climbs. After it: the flaps as the board turns over, the arrow's air as it
flies (`swoop`) and a plucked E as it settles (`dock`), two rising piano notes
for each yes (`granted`), the shutter as the scanner takes the page, the tear
as the stub comes off, and the arrival chord as the sign-in opens (`board`).
Under the steps, from the welcome until boarding, forty seconds of night music
with something of a spell and something of China in it, played at 0.75 and
looped by starting a second copy as the first fades. It is an original waltz
(3/8, a bar a second) in C sharp minor. The celesta plays the theme over a
harp, with a strings pad and a harmony that turns through A, D and G sharp
the way film magic does. Then a bamboo flute (dizi) answers it over a
guzheng, in the pentatonic mode the melody already moves in, with grace notes,
a string pressed up a tone and a tremolo. Then the theme comes back with the
guzheng playing the waltz under it. A small temple gong opens each loop. The
first and last four seconds, where two copies overlap, keep no beat (a held
C sharp minor seventh, the gong, a guzheng's run), so the timer's jitter
cannot be heard. Every note of that chord is in E major, so the intro's last
chord, a chime or the arrival never rubs against it. The tune is not Hedwig's
Theme or any other film's: Foorsa has no licence to ship film music.

The opening and the arrival are the two moments the music speaks up (about
-20 LUFS, peaks at -6 dBFS). The cues between sit lower (-24 to -36 LUFS) and
the bed lower still (-31 LUFS, then played at 0.75), so what the student does
stands out of it. Each cue is brought to its loudness only as far as its peak
allows, so nothing is squashed, and every file starts and ends in exact
silence.

They play as media, so they are heard: on an iPhone the playback session mixed
with whatever else is playing (the student's music never stops), so the silent
switch does not silence them and the phone's volume buttons set how loud they
are; on Android the media stream, with no audio focus. (The first version
played in iOS's ambient session, which the ring/silent switch silences, and on
Android's interface-sound stream, near zero on most phones.) On Android the
short cues timed to the picture (the arrow's air and its dock, a yes, the
flaps, the shutter, the tear: `lowLatencyCues`) play through its low-latency
player, decoded ahead into memory; through its media player a cue starts a
tenth of a second or more after it is asked for, and the dock's note came
after the arrow had docked. The intro, which a late start seeks into, and the
six-second arrival keep the media player. iOS has one player. There is no
speaker button on the screen: the volume buttons are the control. Nothing
plays while the app is in the background (the app has the audio background
mode, which would otherwise keep the bed playing). The intro loads first,
behind the native splash, and a late one starts where the picture has got to;
the rest load behind it. Everything is let go six seconds after boarding, when
the session goes back to iOS's default. To change one, edit the script and run
it with `--encode`; `test/onboarding_sound_test.dart` fails when a cue the
onboarding plays ships no file, or a file ships that nothing plays.

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
steps cross-fade; the sounds still play. What to do is a still chevron
instead of the moving touch, and the line under the object stays. Objects
are illustrations at a fixed text size; the words above them follow the
phone's text size, smaller on short screens, and so does the line saying
what to do; below 220 pt of room the screen scrolls. Android's back goes one
step back.

## Android: why it was sluggish, and what changed (1 Nov 2026)

The owner, 31 Oct 2026: "the introduction animations on android are very
sluggish and buggy". No Android phone was at hand. The causes below are read
from the engine and documentation of the Flutter this app builds with (3.47.5:
`engine/src/flutter` and `docs/platforms/android` in the SDK), and every change
is measured by tests that count what each frame asks the GPU for
(`test/onboarding_android_cost_test.dart`, with `test/frame_cost.dart`), on a
1080 x 2400 phone.

**The web view was composited under the whole onboarding.** The portal's web
view is made 3.6 s in, so the sign-in loads under the onboarding for the
hand-off. It used Hybrid Composition (HC), the real Android view in the
window. While such a view is in a frame, Flutter rasters its frames on
Android's main thread, draws everything over the view into image views
(`FlutterImageView`, `PlatformViewsController.onDisplayPlatformView`), and
before Android 10 copies each frame from the GPU to memory and back; Flutter's
own page on it: "the rendering changes can significantly impact Flutter's
performance". Flutter does not leave out a view hidden under an opaque
picture, so from the welcome to the hand-off every frame went that way, on the
main thread the web view was loading the portal on, and the frame the view
first appeared in was dropped and drawn again as the threads merged (the
welcome's first moment). Now (`lib/src/web_view_composition.dart`):

- A web view made while the onboarding covers the shell uses Texture Layer
  Hybrid Composition (TLHC): the view is in the window at its place, so
  touches, the keyboard, text selection and accessibility reach it as they do
  with HC, but it draws into a texture that Flutter composes on its own raster
  thread. Flutter's docs say this mode "should be preferred when possible".
- While covered it is not drawn at all (`CoveredByOnboarding`): it is laid
  out, loads and draws into its texture, but is in none of the onboarding's
  frames, until the onboarding starts to fade (`OnboardingScope.covering`
  turns false at `onBoarded`, 0.1 s before the fade), when the texture is
  current and the fade shows it. An HC view cannot be left out like this:
  Android lays it out only once Flutter draws it, so the page would load at no
  size and the arrow could not be landed on the sign-in's.
- Every other web view is HC as before: later launches, one rebuilt after the
  onboarding (a render process gone), and iOS, which has one way.
- Trade-off: the first session after install (the onboarding, the sign-in, and
  whatever the student does before closing the app) runs its web view as a
  texture. TLHC is what Flutter's own web view plugin uses unless told
  otherwise ("for most use cases, this flag should be set to false",
  webview_flutter_android), but this app has always shipped HC, and
  flutter_inappwebview (1.1.3) behaves differently without it: it routes the
  keyboard through a bridge kept from Flutter's older virtual-display mode
  (`InputAwareWebView`; read from its code, it hands the keyboard Chromium's
  own input connection before Android 10 and stands aside from 10 on), and it
  replaces Android's copy and paste bar with one of its own drawn in the page
  (`InAppWebView.rebuildActionMode`: the same actions, cut, copy, paste,
  select all, in a plainer bar). As a texture the web view also costs one more
  copy per frame, and its texture is remade as the keyboard resizes the page.
  So HC is kept for every other launch, and what only a phone can show is that
  first session: typing in the sign-in, a password pasted or filled by a
  password manager, the copy and paste bar, the keyboard in the chat. Should
  any of it fail, `webViewUsesHybridComposition` returning true puts the first
  session back on HC, and the onboarding back on its old cost.

**The app's loader played under the onboarding.** Its loading screen (the
arrow, the stairs, the plane, the cap) stays over the web view until the
portal is ready: on a first launch, through the takeoff and the first scenes,
drawn and animated every frame under the opaque night, three or four blurs
through offscreen passes and a full-screen fill each frame. It now neither
draws nor ticks while covered (`ShellLoadingLayer`); its fade still runs, so a
loader the portal let go of meanwhile is gone before the onboarding fades.
Both platforms; nothing on the screen changes.

**Frames drew what nobody saw, and repainted what did not move.** Both
platforms, same pixels:

| per frame, at rest | welcome | notifications | camera | mic | location | pass |
| --- | --- | --- | --- | --- | --- | --- |
| render objects repainted, before | 36 | 49 | 16 | 22 | 25 | 65 |
| render objects repainted, now | 3 | 6 | 3 | 3 | 4 | 8 |

- The change from one object to the next drew into an offscreen layer the
  size of the stage on every frame, at full opacity, which draws the same as
  drawing straight onto the stage: now only for its last 7 %, as it fades
  (`stage_morph.dart`). The map's lens did the same after its first 0.9 s.
- What moves every frame (the arrow at rest, the voice, the map, the locate
  arrow, the scanner, the shield's rings, the flaps, the flying arrow, the
  change) has a layer of its own, so the scene around it is not redrawn with
  it.
- The pass rebuilt itself and redrew its two shadows every frame, on a clock
  nothing read: gone. Its notched outlines (a `Path.combine`) are made once.
- Anything rebuilt inside a LayoutBuilder is rebuilt within that builder's
  layout (`layout_builder.dart`, `_scheduleRebuild`). The prayer chip's
  builder, on the map's clock, laid the whole location scene out again every
  frame, found or not; it has its own controller now. The notification stack
  and the pass move in an `OwnFrame` (`boarding_style.dart`: their own builder
  and layer), and the cards are made once (`BalancedText` measured their words
  every frame they moved). The stack's springs stop once still.
- The scanner's passport lines are laid out once; the app icon on the cards is
  decoded at its 38 pt, not at 1024 px (a 4 MB texture made as the first card
  landed), and ahead of the scene.

**Blurs Impeller cannot draw in one pass (Android only).** Impeller, Flutter's
renderer on Android 10 and later, draws a blurred rectangle, rounded
rectangle, circle or convex shape in one pass; any other blurred shape goes
through an offscreen picture and two blur passes, every frame
(`impeller/display_list/canvas.cc`), and it keeps no raster cache
(`EnableRasterCache` is false for its surfaces). The arrow (three pieces, not
convex), the plane, the pass's notched shadows and the light inside every
piece of glass (a frame with a hole in it) are such shapes. On Android, while
the onboarding runs, `GlassBake` (`glass.dart`) draws each of those blurred
fields once at the size it is shown and then as a picture, under the same
vector clips, between the same face, wall and rim. Only glass whose shape and
light stay the same is baked, never a blur narrower than 1.5 px on the screen
(a small arrow's bevel, which resampling would soften), and nothing that
changes as it moves (the touch showing what to do, the change between
objects). Each picture is made once and drawn again from then on, keyed by its
shape, its glass and its size on the screen in quarter octaves (so an arrow
that grows as it flies is made a handful of times, never every frame): the
takeoff and the six scenes make 25 together, about 12 MB of textures on a
1080 x 2400 phone, and they go when the onboarding ends. iOS draws as before.

| blurs through offscreen passes, per frame | takeoff arrow | plane | welcome | notifications | mic | location | pass |
| --- | --- | --- | --- | --- | --- | --- | --- |
| before | 4 | 2 | 7 | 2 | 2 | 8 | 1 |
| Android now | 0 | 0 | 3 | 0 | 0 | 2 | 0 |

(The welcome's three are its arrow's bevel and the touch; the location's, the
locate arrow's two narrow lights. The change between objects keeps its four
for its second.) Every scene was drawn with and without, at 2, 2.625 and 3.5
pixels per point, with Skia and with Impeller: 5 levels of 255 apart at most,
0.01 on average.

**Impeller stays.** Impeller compiles every shader when the app is built; the
onboarding is the first thing a new install draws, and Skia would compile its
shaders during the takeoff. Opting out (`EnableImpeller` false) is deprecated
in this Flutter, which logs that the option will go away. The engine already
draws with Skia below Android 10 and on Vivante GPUs, and with Impeller's
OpenGL ES backend on the drivers it knows to be bad (emulators, Huawei, older
MediaTek, several Exynos; `flutter_main.cc`,
`android_context_dynamic_impeller.cc`). `test/onboarding_android_cost_test.dart`
fails on an opt-out.

**Checked, unchanged.** Every animation runs on time, not on frames: a 120 Hz
screen sees the same flight as a 60 Hz one (test). `MainActivity` asks for
the display's highest rate, so a 90 or 120 Hz phone draws the onboarding at
that rate. Android's back steps back; the gestures are in the middle of the
screen, clear of the edge-swipe back. The web view is still made 3.6 s in: on
Android 7 to 9 Flutter waits for the main thread's vsync, so making it, the
first time Chromium loads, can still hold the welcome for a moment there.

## Required device verification

- Fresh install on a physical iPhone and Android phone: the launch screen is
  the arrow alone, and frame one of the onboarding matches it; every prompt
  appears the moment its object is acted on.
- The gestures on a real screen: the throw (and a short pull springing back),
  the page dragged into the frame with a thumb, the stub pulled, each line
  saying what to do readable next to its object, nothing under the home
  indicator.
- What to do, on a real screen, with someone who has not seen the app: the
  touch is seen on every object and its gesture understood without
  explanation; it goes the moment a finger lands and comes back after a
  wrong try; after 6 s it speaks up; it never covers the words, and the
  words never cover the object. Its pace on a 60 Hz and a 120 Hz screen.
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
- VoiceOver and TalkBack through every step (each object read as its name,
  button, then what to do; the step's number on the progress line; the
  stub its own button); Reduce Motion (the still chevrons); largest text.
- After boarding: the push token registers on sign-in without a second
  prompt, the status bar follows the portal again, an incoming adviser call
  shows over the onboarding.
- Android, on a mid-range phone (and a 90 or 120 Hz one): the takeoff and every
  scene and change keep pace, with Profile GPU rendering or a systrace if in
  doubt; nothing flashes as the welcome appears.
- Android, the first session after install, whose web view is a texture: the
  hand-off lands and fades onto a drawn sign-in; typing in it, a password
  pasted and one filled by a password manager; a long press in a field (the
  plugin's own copy and paste bar, under the finger, each action working);
  selecting and copying text; the keyboard in the chat; scrolling; a file
  picked; TalkBack on the sign-in; leaving the app and coming back (the page
  still drawn). Then close the app and reopen it: the same, as before, in the
  window, with Android's own bar.
- Android 7 to 9: the welcome as the web view is made (3.6 s in).

## Validation performed locally

- `flutter analyze` and `flutter test`: the plan, the copy rules, the
  permission mapping, the store, the morph engine, the glass (outlines grown
  for a shadow's spread, every material mixing into every other), the throw
  (faster throws carry on faster, never overshooting; the arrow turns to the
  way it is pulled; a short pull springs back), the swoop (it ends on the
  stage's arrow, its size and way round, and stays on screen) and the glide
  (level, pointing its own way), the fold timed to the docking for both
  flights, the locate arrow on the lens's edge, every object inside its
  stage, the arrow's geometry, the whole walk through with fake
  permissions (one gesture per object, the prompt the moment it is touched,
  no button and no Allow on screen, a chime per yes, the shutter, no sound on
  a press or a step), every cue shipped as a file and no file left over, the
  page dragged into the frame (and not taken when let go short), the map's arrow
  flying on once the dot is found, back, the stub torn by hand and the arrow
  landing on the sign-in's own, and every step on a 320 x 568 phone, an iPhone
  SE and a large phone with large text.
- What to do (`test/onboarding_guidance_test.dart`): every step's line is
  verb first and names its object, and every step tells a screen reader what
  to do; the touch's timeline (a tap comes down, presses and rings from the
  object's edge; a swipe, a drag and a pull start on the object and go the
  gesture's way; each rests longer than it moves, every few seconds; the
  object answers it and is still again before the next); every scene shows
  its line and its touch within a moment of the object being ready, the touch
  on a point that hits the object; the gesture each touch shows, copied by a
  finger at its own pace and distance, moves the onboarding on (four taps,
  the swipe, the drag, the pull), and the touch then stops for good; a
  finger on the screen sends it away at once and it comes back after letting
  go; after 6 s it insists (the line white); with Reduce Motion a still
  chevron pointing the gesture's way, not on the words; once acted on,
  nothing is drawn; each object's button carries its name and what to do,
  and the line is not read twice; the step's number; the line's contrast on
  the night and the light behind the object; the line under its object and
  never on it, on four phones and text sizes; the pass's room.
- Rendered every scene with its guidance (the touch mid-gesture, insisting,
  and Reduce Motion) in the Flutter test renderer, on a large phone, a
  320 x 568 phone and an iPhone SE with large text, and looked at each.
- Rendered every screen and the full flow at 60 fps in the Flutter test
  renderer, with mock-ups of iOS's prompts and its notification banner for
  the recording only, and mixed the sounds in at the frames they were played,
  normalised to -16 LUFS.

- What each frame costs (`test/onboarding_android_cost_test.dart`): the web
  view's composition (a texture only while the onboarding covers it, and left
  out of the frames until it fades), the covering signal from the first frame
  to the fade, the loader neither drawn nor ticking under it and still let go
  of, no offscreen layer at rest or as an object changes, the blurs Android
  draws from pictures and the frames' pixels the same with and without, each
  picture made once (a scene's demonstration played again makes none) and
  what they hold together, the render objects repainted per frame in every
  scene, a 120 Hz flight the same as a 60 Hz one, the icon's decode size, and
  no Impeller opt-out.

These do not replace a run on real phones: the prompts, the haptics, the
audio session and the WebView loading underneath are native.
