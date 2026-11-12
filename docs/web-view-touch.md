# Touch, Paste and the keyboard in the web view

The owner, 12 Nov 2026: "when pasting the otp ... no paste button is there it freezes, also many
times the scrolling and keyboard are stuck".

The portal is a web view inside a Flutter app, and on both phones something of Flutter's or of the
web view plugin's stood between a finger and the page. Read from the plugin's, Flutter's and the
engine's source and held by tests; **no phone was at hand**, so what one has to confirm is at the
end.

## Android: the first launch ran the web view through the plugin's virtual-display paths

On a first launch the web view is made in a texture while the onboarding covers it
(`web_view_composition.dart`: `useHybridComposition: false`, so that it need not be drawn under the
onboarding). It is not made again afterwards: the student signs in, and uses the app until it is
closed, in that very web view.

The plugin's Dart side takes `false` to mean "in a texture" (`initSurfaceAndroidView`: a texture, or
Hybrid Composition where a texture cannot be had). Its Java side took the same `false` for the mode
it was written for years earlier, a **virtual display**, where the view is not in the activity's
window at all, and did three things that only make sense there:

- **No Paste.** `InAppWebView.startActionMode` hands Android's own selection menu back only in
  Hybrid Composition. Otherwise it hides the menu Android started, empties it, finishes it and draws
  a floating menu of its own from what it copied.
- **A page that stops answering.** Each time that menu starts, `rebuildActionMode` calls
  `onWindowFocusChanged(containerView.isFocused())`, a workaround for the clipboard under a virtual
  display. In a view that is really in the window, the Flutter view is not the focused one, the web
  view is: so the web view is told its window lost focus, at every long press on a field.
- **A keyboard that will not come, or will not go.** `InputAwareWebView` points Android's input
  method at a proxy on the Flutter view (`checkInputConnectionProxy`), and back at the Flutter view
  whenever the web view's focus is cleared (`clearFocus`).

Flutter never puts this view in a virtual display, in either mode the app asks for. So from
1.2.43 (build 75 on Google Play) the patched copy of the plugin (`third_party/README.md`) tells its Java side the view is
in the window, always: `FlutterWebView` sets `customSettings.useHybridComposition = true` after
reading what the Dart side sent. How the view is drawn is still the Dart side's choice, and is
unchanged: a texture under the onboarding, the window on every later launch. Every launch after the
first already ran this way.

`test/android_plugin_patches_test.dart` fails if the line goes, if any of the three paths is no
longer behind the flag, if the Dart side ever asks for a virtual display, or if the shell asks for
a menu of the plugin's.

## iPhone: every touch of the web view waited on Flutter

On iOS a platform view sits under a view of Flutter's that catches its touches. By default (the
"eager" policy, which the plugin registers with) that view carries a recognizer every other
recognizer must wait for (`FlutterDelayingGestureRecognizer`, `FlutterPlatformViews.mm`): a tap, a
long press for the Paste menu, a scroll, the tap that raises the keyboard. None of WebKit's own may
start until Flutter has answered, over the platform channel, that the touch is the web view's.

The shell had met this once (30 Oct 2026: a long press "reached WebKit late or not at all, and the
Copy / Paste menu came and went") and answered by winning Flutter's gesture arena at once
(`EagerGestureRecognizer`). That shortened the wait; it did not remove it, nor what Flutter's own
documentation says of this arrangement with some native views, a `WKWebView` the known one: their
"internal gesture recognizers get stuck in a stale state". The engine carries a workaround for it
per iOS release (links that could not be tapped on iOS 18.2, then again on iOS 26:
flutter/flutter#158961, #175099).

Flutter now offers the remedy itself: `UiKitViewGestureBlockingPolicy.doNotBlockGesture`, "a
workaround to address a few bugs related to platform view's gesture recognizers being stuck in a
stale state". The waiting recognizer is not there, and WebKit has its touches as any app's web view
has them.

From 1.2.43 (74) the web view is made with it (`lib/src/web_view_touch.dart`). The plugin builds its
`UiKitView` itself and has no setting for the policy, so the app hands the plugin a platform of its
own (`InAppWebViewPlatform.instance`, the plugin's public way in) that builds the same view and adds
the policy. No copy of the iOS plugin is kept, and nothing native changes.

**What it gives up, and why that is nothing here.** Under this policy Flutter cannot take back a
gesture that began on the web view. This app never asked it to: the web view fills the screen, and
the shell already tells Flutter the web view wins every such gesture. What the app draws over the
web view (the loader, the offline screen, a call, a dialog, the onboarding) covers it, and a touch
there is kept from the web view by where the finger lands (`hitTest`), under every policy alike.

`test/web_view_touch_test.dart` builds the real web view widget as on an iPhone and reads what the
engine is told: `gestureBlockingPolicy: doNotBlockGesture` for the plugin's view, with everything
the plugin gave its view still there; left to the plugin, the same web view says
`fallbackToPluginDefault`.

## The portal's side, the same day

- The code screen has a **Paste** button of its own in the field, so a code can be pasted without
  the phone's menu.
- A screen left while a sheet it had opened was still up could leave the page unable to scroll for
  the rest of the visit. The portal's scroll lock is one counted lock now.

Both are the portal's and reach every build at once.

## What a phone has to confirm

On an **Android** phone, from a fresh install (so the onboarding plays and the web view is the
texture one):

1. On the sign-in, tap the email field: the keyboard comes; tap outside: it goes.
2. Long-press the empty email or code field: Android's own Paste appears, and pastes.
3. After a long press, typing still works.
4. Scroll Home and a long screen (Documents): it follows the finger.
5. Close the app, open it again (the window web view): the same four.

On an **iPhone**:

1. Tap a field: the keyboard comes at the first tap. Tap again in the field: Paste appears.
2. Paste the sign-in code from Mail, by the menu and by the screen's own Paste button.
3. Scroll every dock screen, the live chat with the keyboard up, and a sheet's own list.
4. With the loader up, with the offline screen up, during a call: a tap on them does nothing to the
   page under them.
5. Explore China's map (pinch, drag), the document viewer (pinch), a video.
6. The edge swipe back still goes back.

If the iPhone change misbehaves, `webViewGestureBlockingPolicy` in `web_view_touch.dart` is the one
line: `UiKitViewGestureBlockingPolicy.fallbackToPluginDefault` is how it was. That takes a new
version.
