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

## Three languages

The first step is the language (the owner, 1 Nov 2026: "give to the student
three choices of language when he first use the app first thing, arabic,
french or english (the default)"). It asks the phone for nothing, so the App
Review rules for screens before a prompt do not apply to it; its words say
only what the choice does: the app, the emails and the notifications, and
where to change it (Profile › Settings, in the portal).

- Every word of the onboarding is written in the three (`copyFor(step,
  language)` in `onboarding_flow.dart`, the scenes' own words beside them),
  following the portal's style rules (foorsa-reward `shared/i18n/README.md`).
  Arabic lays out right to left; the drawings keep their own way round (the
  arrow thrown up, the page dragged into the frame, the boarding pass with
  Casablanca at the left and China at the right).
- The choice is kept on the phone (`app_language.dart`, file
  `portal_language`) and handed to the portal loading underneath: its
  `localStorage.foorsa_portal_language` is written before its code runs, and a
  page already open is told with `foorsa:language`, on which it starts again
  in the language, unseen. So the portal never shows its own chooser after the
  onboarding.
- The portal says its language with `FoorsaShellLanguage` at start and when
  the student changes it in Settings; the app's own screens follow (the
  loading and offline screens, the quick sign-in question, the call screen,
  the scanner, notifications). The phone's permission prompts are iOS's own,
  in the phone's language (`ios/Runner/*.lproj/InfoPlist.strings`).

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
| Language | nothing | three rows on one glass pane, each language named in itself (English, marked Default, Français, العربية) and laid out in its own direction. **Tap your language**: the check moves to it, the screen's words change to it at once, and a beat later the pane folds into the arrow and unfolds as the welcome, in that language |
| Welcome | nothing | one line of a split-flap board in a glass case, flipping through the voyage's 16 cities (a tap flips it), and under it Foorsa's arrow, resting. **Swipe the arrow up to begin**: the arrow is thrown up into the board, or tapped |
| Notifications | `Permission.notification` | a stack of Foorsa's notifications on glass (the app's real texts), a new one landing on top every few seconds. **Tap the notification**; a yes sends the front card up and the phone's own first notification down |
| Camera | `Permission.camera` | the scanner's frame, and a drawn passport page that lifts out of it into the hand, tipped and turned. **Drag the page into the frame**: it straightens as it nears, the corners close on it, and let go close enough it is taken with a soft flash (a tap puts it in) |
| Microphone | `Permission.microphone` | the chat's mic, a glass orb, with a voice running out from it on both sides. **Tap the mic**; pressed, the voice comes up (nothing is recorded) |
| Location | `Permission.locationWhenInUse` | a night map under a glass lens, and on its edge the map's locate button, which is Foorsa's arrow. **Tap the arrow to find yourself**; a yes drops the blue dot onto the map with its heading and the next prayer on a glass chip, then the arrow leaves the button and glides into the map |
| Tracking | `Permission.appTrackingTransparency` | off, see below; a shield in a glass orb. **Tap the shield** |
| Boarding pass | nothing | the pass, PULL TO BOARD printed on its stub (DÉTACHER ICI, اسحب للصعود). **Pull the stub down to board**: it comes off (a tap tears it too) |

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
up, Step 2 of 5"; `route_progress.dart`). The language and the welcome come
before the count: they show the wordmark instead, and the count starts after
the welcome. The headline is
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
Android's interface-sound stream, near zero on most phones.) There is no
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

These do not replace a run on real phones: the prompts, the haptics, the
audio session and the WebView loading underneath are native.
