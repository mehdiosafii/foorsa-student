# What the shell costs a phone, on every start and in use

Status: released as 1.2.41 (72) on 12 Nov 2026 at the owner's word ("push live",
straight to the stores), before any check on a phone. The device verification
below is still owed.

The owner, 11 Nov 2026: "some animations and usage feel sluggish in the app,
android and ios (not a big deal) investigate and fix it for the cleanest ux".

The app is the portal in a web view, so most of what a student feels in use
is the portal's own code (foorsa-reward, `src/portal`). This is about what the
app itself added to it: three things, two of them on every start.

No phone was at hand. Each cause below is read from the code that runs on the
phone (the web view plugin kept in `third_party/`, the framework and engine
of the Flutter this app builds with, 3.47.5, and hwui, Android's renderer),
and each change is held by tests, the frames' costs counted as the
onboarding's are (`test/shell_frame_cost_test.dart` with
`test/frame_cost.dart`). What only a phone can show is listed at the end.

## Android: the web view was drawn twice

The shell set the plugin's `hardwareAcceleration: true`, "to keep the web
content on the GPU path". Under Hybrid Composition, which every start but the
first uses (`web_view_composition.dart`), that setting does one thing: it
chooses the view's layer type, `View.LAYER_TYPE_HARDWARE` for true and
`View.LAYER_TYPE_NONE` for false (`InAppWebView.prepare`). Neither is
software rendering. What makes Android draw with the GPU is the window
(`android:hardwareAccelerated="true"` on the activity, the default since API
14): a view with no layer is drawn by the GPU straight into it, which is how
a WebView is drawn in any app that leaves it alone.

A hardware layer is an offscreen texture the size of the view: Android draws
the view into it whenever the view changes, then draws the texture into the
window. For a view that stands still while it is moved or faded as a whole,
that saves work, and Android's guide recommends it "only for the duration of
the animation". A web view is the opposite. It changes on every frame of a
scroll or of an animation in the page, and on each of those frames the page
was drawn into the texture and the texture into the window: one full-screen
pass more than drawing it once. And:

- the texture is about 10 MB on a 1080 x 2400 phone, in an app whose web view
  Android closes when it grows too large (`web-view-recovery.md`);
- Android allocates a new one each time the view's size passes another 64 px,
  and from Android 11 the keyboard resizes the web view on every frame of its
  way up or down, so opening the keyboard in the chat went through one
  texture after another.

Now the setting is `webViewOffscreenLayer`, false: no layer. iOS ignores it,
and the first session after install, whose web view is in a texture, had none
already.

Read from `InAppWebView.java` in `third_party/flutter_inappwebview_android`;
hwui's `SkiaPipeline::renderLayerImpl` and
`SkiaGpuPipeline::createOrUpdateLayer` (frameworks/base, libs/hwui); the
engine's `ImeSyncDeferringInsetsCallback`; and "Hardware acceleration", View
layers, on developer.android.com. A test holds the plugin's code to this
reading: where it reads the setting, and the only layers it ever sets.

## Both: the web view was made late, in the middle of the loader's first move

A web view is made on the thread the app builds its frames on (in this
Flutter, Dart runs on the phone's main thread: `merged_platform_ui_thread`),
so while one is made nothing on the screen moves. On Android the first web
view of a start also loads Chromium.

The loader played from its first frame. The shell waited a fixed 300 ms, then
read what the web view needs (the session script, the quick sign-in record),
then made it: a third of a second into the loop, as a band of light crosses
the arrow (0.1 to 0.6 s). And the portal began to load that much later than
it could have.

Now (`boot_loader_gate.dart`, wired in `shell_page.dart`):

- The web view is made as soon as the loading screen's first frame is drawn
  (`whenWebViewMayStart`: Flutter's `waitUntilFirstFrameRasterized`, and never
  later than the 300 ms it was). What it needs is read meanwhile, not after.
- Until the web view exists the loader rests on its first picture, the arrow
  alone, which is how its loop begins anyway (`BootLoaderGate.resting`,
  `FlightLoader.resting`); resting, it asks for no frame. `onWebViewCreated`
  starts the loop. It rests one second at most (`restLimit`), so a web view
  slow to come, or one that cannot be made (the offline screen takes over
  after 15 s), does not leave the arrow standing.
- Making the web view is the longest hold, not the only one: on Android the
  frame that first shows the new view is dropped and drawn again as Flutter
  moves its drawing to the main thread for it, and Android lays the view out
  and draws it for the first time. So the loop counts from the first frame
  drawn after the rest, however late that frame comes (a clock started while
  a frame is built counts from that frame, `Ticker.start`), and it opens
  with a tenth of a second of the same still arrow.
- The "Set up your device" reminder, which opens with the app for a student
  who has not allowed the camera, the microphone and the location, used to
  come in during those first 300 ms. It now waits until the web view has
  been made and has had 300 ms to be put on the screen, 1.3 s at most
  (`DeviceAccess.after`, `PortalHandover.webViewSettled`,
  `BootLoaderGate.settle`), so it comes in neither while the thread is held
  nor on the frames that first show the view. When the app comes back to
  the front it opens at once, as before.
- A first launch is as it was: the web view waits for the onboarding's
  takeoff (3.6 s), and the loader, under the onboarding, is neither drawn
  nor animated and does not rest (`BootLoaderGate(rests: false)`): should it
  still be needed when the onboarding fades, it plays from its first
  picture.

So a start shows the launch image, the arrow, then the loop from its
beginning, and the portal's first screen comes up to 300 ms sooner.

## Android: the loader's blurs, on the thread the page loads on

The loader is over the web view from the first frame to the portal's first
screen. While an Android web view is in the window, Flutter rasters every
frame on the phone's main thread and draws what is over the view into an
image view (`first-launch-onboarding.md`, "Android"); that is the thread the
page is loading on. And each frame of the loop asked for blurs Impeller can
only draw through an offscreen picture and two passes (the arrow and the
plane are neither rectangles nor circles): their shadows and the light in
their bevels.

On Android the loader's glass is now drawn as the onboarding's is, from
pictures made once (`GlassBake`, `onboarding/glass.dart`;
`ShellLoadingLayer.bakeGlass`), and let go with the loader.

| blurs through offscreen passes, per frame | arrow | becoming the plane | plane | next arrow coming up | a loop, on average |
| --- | --- | --- | --- | --- | --- |
| dark, before | 4 | 5 | 2 | 4 to 6 | 3.5 |
| dark, now, 1080 x 2400 at 2.625 | 0 | 5 | 0 | 4 to 5 | 1.75 |
| dark, now, 720 x 1600 at 2 | 1 | 5 | 1 | 4 to 5 | 2.4 |
| light, before | 3 | 3 | 3 | 3 to 6 | 3.2 |
| light, now, 1080 x 2400 at 2.625 | 0 | 3 | 0, 1 as it leaves | 3 to 4 | 1.3 |
| light, now, 720 x 1600 at 2 | 1 | 3 | 1 | 3 to 4 | 1.9 |

What changes shape or fades from one frame to the next (the arrow becoming
the plane, the next arrow coming up) is drawn as before: a picture of it
would be made again on every frame. And a blur under a pixel and a half wide
on the screen stays a blur, as in the onboarding, so that it stays sharp: on
a 720p phone that is the light along the arrow's and the plane's bevel, one
blur a frame. The pictures, on the dark ground and on the light one: 6 and
0.9 MB, 5 and 1.5 MB at 720 x 1600; 9 and 1.9 MB, 7 and 2.5 MB at
1080 x 2400; 11 and 4.4 MB, 9 and 5.7 MB at 1440 x 3200. The loader was
drawn with and without them at four moments of its loop, on both grounds, at
720 x 1600 and at 1080 x 2400, with Skia and with Impeller: 5 levels of 255
apart at most, 0.007 on average. iOS draws as before.

The loader and the onboarding each keep the baking on for themselves
(`GlassBake.hold` and `release` beside the onboarding's `enabled`): on a
first launch the loader may be let go before the onboarding ends, or after.
The pictures are kept together. When the onboarding ends its pictures go,
and a loader still up makes its own few again; when nobody bakes any more,
all go.

A test that draws for a given phone says its density to `GlassBake`
(`debugScreenDensity`): `GlassBake` reads the engine's own view, whose
density a test's view does not change (it stays 3). The onboarding's own
cost tests were written before this was known, and bake at 3 while they draw
at 2.625; their numbers in `first-launch-onboarding.md` are for that.

## Looked at, and left as it is

- **A redraw of the shell does not drop a touch.** The shell rebuilds when
  the portal changes the status bar's colour, and it hands the web view a new
  gesture recognizer factory each time. The framework compares factories by
  type and keeps the recognizer (`_factoryTypesSetEquals`,
  rendering/platform_view.dart), and on Android the surface is made once
  (`PlatformViewLink`).
- **Hybrid Composition stays** for every start but the first, for the reasons
  in `web_view_composition.dart`. This Flutter has a newer mode, Hybrid
  Composition++ (docs/platforms/android in the SDK), that takes Flutter's
  frames off the main thread; it is opt-in (a manifest flag), needs Android 14
  and Vulkan, and lists limits with transparent views, so it is for a day
  with a phone at hand.
- **The keyboard.** Flutter resizes the web view on every frame of the
  keyboard's way up, on both platforms. The chat was tuned on phones with it
  that way; without the layer above, each of those frames now costs Android
  less.
- **iOS in use.** With nothing drawn over the web view, Flutter draws no
  frame while the portal is used, and a touch reaches WebKit as soon as Dart
  has seen it (`EagerGestureRecognizer`). The plugin's `preventGestureDelay`
  looks for a class this engine has renamed, so it would do nothing.
- **The onboarding's pace** (a second from one object to the next, a moment
  on each yes) is its design (`first-launch-onboarding.md`).
- **What the portal itself costs** (its scripts and styles, its own
  animations) was not measured here: it is foorsa-reward's.

## Required device verification

- Android, an ordinary start (not the first after install), on a mid-range
  phone and a 90 or 120 Hz one: every screen of the portal is drawn, in light
  and in dark, with nothing blank, black or flickering; scrolling Home, the
  documents and a long list; the chat as the keyboard comes up and goes down;
  the copy and paste bar; a place's video playing; the admission letter; the
  introduction video's studio; a paper picked and uploaded; leaving the app
  and coming back. Should the web view draw wrongly anywhere,
  `webViewOffscreenLayer` true puts the layer back. That takes a new version:
  the setting is built into the app, and nothing outside it can switch it.
- Both, a start: the launch image, the arrow standing, then its loop from the
  beginning with nothing jumping, and the first screen fading in; in light
  and in dark; with Reduce Motion; on a slow connection (the loop keeps
  playing).
- Android: the loader's arrow and plane look as they did (their shadows, the
  light in their edges), on a 720p phone too.
- Both: a start with no connection reaches the offline screen as before, and
  its retry brings the portal back.
- Both, with an access refused: the reminder comes in whole, a moment after
  the loop begins, and again, at once, after leaving the app and coming back.
- A first launch is unchanged: the onboarding, then the sign-in; on a slow
  connection, the loader still up when the onboarding fades, playing from its
  first picture.

## Validation performed locally

- `flutter analyze` and `flutter test` (483 tests).
- The loader's rest (`test/boot_loader_gate_test.dart`,
  `test/flight_loader_test.dart`, `test/shell_screens_test.dart`): it rests
  from the start and plays once the web view is made, or after a second, and
  not at all on a first launch; the resting loader is the loop's first
  picture and asks for no frame; let go, it opens on that picture however
  late the next frame comes, under Reduce Motion too; uncovered by the
  onboarding, or let go of its rest while covered, it plays from its first
  picture; a loader let go of while it rests still fades and says so.
- When the web view is made: as soon as the first frame is drawn, never later
  than 300 ms, and after the takeoff on a first launch.
- The reminder (`test/device_access_test.dart`,
  `test/portal_handover_test.dart`): it opens once the web view is made and
  settled and not before, after 1.3 s if none comes, at once when one is
  there already, not at all if a call comes in or the app's screen goes
  meanwhile, and with every access granted nothing waits.
- What each frame costs (`test/shell_frame_cost_test.dart`): the shell asks
  for no layer; in the plugin's code the setting is read in one file, to set
  a hardware layer or none where the web view is made and where its settings
  change, and no other layer is set anywhere; the manifest does not turn the
  window's acceleration off; the shell's start-up steps in their order; the
  loader's blurs counted over a loop with and without the pictures on three
  phones, each picture made once and all let go with the loader, the pixels
  the same with and without; the shell redrawing the loader holding the
  pictures once; the onboarding's pictures going when it ends, and the
  loader making its own again.

These do not replace a run on real phones: how the web view draws, how the
keyboard moves it and how a start looks are native.
