# Patched plugins

Two Android plugins are built from copies kept here, each with a small Foorsa
patch, through `dependency_overrides` in `pubspec.yaml`. Everything else in them
is the published version, byte for byte (tests and examples left out). iOS uses
neither copy.

`test/android_plugin_patches_test.dart` fails if an override or a patch goes
missing. **To upgrade either plugin**, replace its folder with the new published
version (`lib`, `android` without `src/test`, `LICENSE`, `pubspec.yaml`), apply
the patch below again, check that upstream has not fixed it already, and run
`flutter test` and `flutter build appbundle`.

## flutter_inappwebview_android 1.1.3: guarded web view settings

**What broke.** On some phones the framework hands the app an
`android.webkit.WebSettingsWrapper`, and the installed Android System WebView
casts it to its own `ContentSettingsAdapter`, so every `androidx.webkit`
`WebSettingsCompat` call throws a `ClassCastException`. The plugin makes those
calls, unguarded, in `InAppWebView.prepare()` while the web view is created. On
those phones the portal's web view was never created and the Foorsa app sat on
its loading screen. The crash board had 22 such reports on 1 Nov 2026, on every
build from 1.2.30 (61) to 1.2.33 (64), and only 4 Android sessions all week
(upstream: flutter_inappwebview issues #2397 and #2893, still open for this
call site).

**The patch.** `webview/in_app_webview/SafeWebSettings.java` makes each of those
calls in a `try`, falling back to the framework's own setter where there is one
and skipping it otherwise. `InAppWebView.prepare()`, `setSettings()` and
`InAppWebViewSettings.getRealSettings()` go through it. The portal sets none of
these settings to anything but its default, so nothing it relies on is lost on
such a phone.

## camera_android_camerax 0.6.30: the still in quality mode

**What was wrong.** The plugin left CameraX's `ImageCapture` at its default,
`CAPTURE_MODE_MINIMIZE_LATENCY`, with no focus scan before the shot and JPEG
95. The owner, 1 Nov 2026, on Android: "the quality of the camera is bad it's
not as the original camera of the phone".

**The patch.** `ImageCaptureProxyApi.pigeon_defaultConstructor` sets
`CAPTURE_MODE_MAXIMIZE_QUALITY` and JPEG quality 95. Only the guided scanner
opens this camera.
