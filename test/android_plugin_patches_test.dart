// The two Android plugins the app carries patched (third_party/README.md).
// An upgrade that drops a patch brings back what it fixed, so each is pinned.
// The camera plugin is reached through the camera package, and its selectors
// through its own library, as its own tests do.
// ignore_for_file: depend_on_referenced_packages, implementation_imports
import 'dart:io';

import 'package:camera_android_camerax/camera_android_camerax.dart'
    show foorsaImageAnalysisMaxSelector, foorsaImageAnalysisMaxSize;
import 'package:camera_android_camerax/src/camerax_library.dart' as camerax;
import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

// CameraX's objects, made without a phone: the test records what each was
// made with.
class _Size extends Fake implements camerax.CameraSize {}

class _Strategy extends Fake implements camerax.ResolutionStrategy {}

class _Aspect extends Fake implements camerax.AspectRatioStrategy {}

class _Selector extends Fake implements camerax.ResolutionSelector {}

void main() {
  test('the app builds with both patched plugins', () {
    final pubspec = _read('pubspec.yaml');
    expect(pubspec, contains('flutter_inappwebview_android:\n    path: third_party/flutter_inappwebview_android'));
    expect(pubspec, contains('camera_android_camerax:\n    path: third_party/camera_android_camerax'));
    final lock = _read('pubspec.lock');
    expect(lock, contains('path: "third_party/flutter_inappwebview_android"'));
    expect(lock, contains('path: "third_party/camera_android_camerax"'));
  });

  test('no androidx.webkit settings call is left unguarded', () {
    // On some phones every WebSettingsCompat call throws a ClassCastException
    // (WebSettingsWrapper cannot be cast to ContentSettingsAdapter); made
    // while the web view was created, it was never created, and the app sat on
    // its loader (crash board, 1 Nov 2026).
    final root = Directory('third_party/flutter_inappwebview_android/android/src/main/java');
    final calls = <String>[];
    for (final file in root.listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.java') || file.path.endsWith('SafeWebSettings.java')) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (RegExp(r'WebSettingsCompat\.(set|get|is)\w*\(').hasMatch(lines[i])) {
          calls.add('${file.path}:${i + 1}');
        }
      }
    }
    expect(calls, isEmpty);
    final safe = _read('third_party/flutter_inappwebview_android/android/src/main/java/com/pichillilorenzo/'
        'flutter_inappwebview_android/webview/in_app_webview/SafeWebSettings.java');
    final compat = RegExp(r'WebSettingsCompat\.\w+\(').allMatches(safe).length;
    final guarded = RegExp(r'catch \(RuntimeException e\)').allMatches(safe).length;
    expect(compat, greaterThan(0));
    expect(guarded, greaterThanOrEqualTo(compat), reason: 'every compat call has its catch');
  });

  test('the web view keeps Android\'s own Paste menu and keyboard, however it is drawn', () {
    // On a first launch the web view is made in a texture under the onboarding
    // (web_view_composition.dart: useHybridComposition false). The plugin read
    // that as its virtual-display mode: its own floating menu in place of
    // Android's (Paste), the window's focus taken from the web view each time
    // the menu started, and the keyboard handed to a proxy on the Flutter
    // view. The student then signs in in that very web view (the owner,
    // 12 Nov 2026: "when pasting the otp ... no paste button is there it
    // freezes, also many times the scrolling and keyboard are stuck").
    const dir = 'third_party/flutter_inappwebview_android/android/src/main/java/com/pichillilorenzo/'
        'flutter_inappwebview_android/webview/in_app_webview';
    final view = _read('$dir/FlutterWebView.java');
    final parsed = view.indexOf('customSettings.parse(initialSettings);');
    final forced = view.indexOf('customSettings.useHybridComposition = true;');
    final made = view.indexOf('webView = new InAppWebView(');
    expect(parsed, isNonNegative);
    expect(forced, greaterThan(parsed), reason: 'after what the Dart side sent is read');
    expect(made, greaterThan(forced), reason: 'before the web view is made from it');
    // What the patch keeps the web view out of: each is still behind the flag.
    final web = _read('$dir/InAppWebView.java');
    expect(web, contains('if (customSettings.useHybridComposition && !customSettings.disableContextMenu && '
        '(contextMenu == null || contextMenu.keySet().size() == 0)) {\n      return super.startActionMode(callback, type);'));
    expect(web, contains('if (!customSettings.useHybridComposition && containerView != null) {\n      onWindowFocusChanged(containerView.isFocused());'));
    final input = _read('$dir/InputAwareWebView.java');
    expect(input, contains('public boolean checkInputConnectionProxy(final View view) {\n    if (useHybridComposition) {\n      return super.checkInputConnectionProxy(view);'));
    expect(input, contains('super.clearFocus();\n\n    if (useHybridComposition) {\n      return;'));
    // The Dart side still decides how the view is drawn: in a texture, or in the window.
    final widget = _read('third_party/flutter_inappwebview_android/lib/src/in_app_webview/in_app_webview.dart');
    expect(widget, contains('return PlatformViewsService.initSurfaceAndroidView('));
    expect(widget, isNot(contains('initAndroidView(')), reason: 'a virtual display is never asked for');
    // And the shell asks for nothing that would bring the plugin's own menu back.
    final shell = _read('lib/src/shell_page.dart');
    expect(shell, isNot(contains('contextMenu:')));
    expect(shell, isNot(contains('disableContextMenu')));
    expect(shell, isNot(contains('.setSettings(')));
  });

  test('the camera takes its still in CameraX quality mode', () {
    final capture = _read('third_party/camera_android_camerax/android/src/main/java/io/flutter/plugins/camerax/'
        'ImageCaptureProxyApi.java');
    expect(capture, contains('builder.setCaptureMode(ImageCapture.CAPTURE_MODE_MAXIMIZE_QUALITY);'));
    expect(capture, contains('builder.setJpegQuality(FOORSA_JPEG_QUALITY);'));
  });

  test('beside a still at the maximum, the image stream asks for 4:3 at preview size', () {
    // The owner, 1 Nov 2026, on an Android 17 phone: "the scanning didn't show
    // the auto scanning interface". Upstream asks the stream for the sensor's
    // largest frame too, beside the still that does.
    addTearDown(camerax.PigeonOverrides.pigeon_reset);
    final made = <String, Object?>{};
    final size = _Size(), strategy = _Strategy(), aspect = _Aspect(), selector = _Selector();
    camerax.PigeonOverrides.cameraSize_new = ({required int width, required int height}) {
      made['size'] = (width, height);
      return size;
    };
    camerax.PigeonOverrides.resolutionStrategy_new = ({required boundSize, required fallbackRule}) {
      made['bound'] = boundSize;
      made['fallback'] = fallbackRule;
      return strategy;
    };
    camerax.PigeonOverrides.aspectRatioStrategy_new = ({required preferredAspectRatio, required fallbackRule}) {
      made['aspect'] = preferredAspectRatio;
      made['aspectFallback'] = fallbackRule;
      return aspect;
    };
    camerax.PigeonOverrides.resolutionSelector_new = ({resolutionFilter, resolutionStrategy, aspectRatioStrategy}) {
      made['selector'] = (resolutionFilter, resolutionStrategy, aspectRatioStrategy);
      return selector;
    };

    expect(foorsaImageAnalysisMaxSelector(), same(selector));
    expect(foorsaImageAnalysisMaxSize, (width: 1440, height: 1080));
    expect(made['size'], (1440, 1080));
    expect(made['bound'], same(size));
    expect(made['fallback'], camerax.ResolutionStrategyFallbackRule.closestLowerThenHigher,
        reason: 'a phone without 1440x1080 takes the nearest size below it');
    expect(made['aspect'], camerax.AspectRatio.ratio4To3, reason: 'the still\'s and the preview\'s own shape');
    expect(made['aspectFallback'], camerax.AspectRatioStrategyFallbackRule.auto);
    expect(made['selector'], (null, strategy, aspect));

    // Only the stream, and only at the maximum: the preview and the still keep
    // the preset's own selector, the sensor's highest.
    final plugin = _read('third_party/camera_android_camerax/lib/src/android_camera_camerax.dart');
    expect(plugin, contains('imageAnalysis = ImageAnalysis(\n      resolutionSelector: _imageAnalysisResolutionSelector,'));
    expect(plugin, contains('_imageAnalysisResolutionSelector =\n'
        '        mediaSettings?.resolutionPreset == ResolutionPreset.max\n'
        '        ? foorsaImageAnalysisMaxSelector()\n'
        '        : _presetResolutionSelector;'));
    expect(RegExp(r'resolutionSelector: _presetResolutionSelector,').allMatches(plugin).length, 2,
        reason: 'the Preview and the ImageCapture');
  });

  test('the shell no longer asks Android to pre-raster the page', () {
    expect(_read('lib/src/shell_page.dart'), contains('offscreenPreRaster: false,'));
  });

  test('a web view that never says it was created hands over to the retry screen', () {
    final shell = _read('lib/src/shell_page.dart');
    final created = shell.indexOf('onWebViewCreated: (controller) {');
    expect(created, isNonNegative);
    expect(shell.substring(created, created + 120), contains('_startWatch.created();'));
    expect(RegExp(r'_watchWebViewStart\(\);').allMatches(shell).length, 2,
        reason: 'when the first web view is put up, and when one is rebuilt');
    expect(shell, contains('void _watchWebViewStart() => _startWatch.start();'));
    // The watch itself (how long, and only while the app is on screen) is
    // web_view_recovery.dart's WebViewStartWatch, with its own tests; here,
    // that running out of time still puts the retry screen up.
    final watch = shell.substring(shell.indexOf('late final WebViewStartWatch _startWatch'));
    final stuck = watch.substring(0, watch.indexOf('  );') + 4);
    expect(stuck, contains('onStuck: () {'));
    expect(stuck, contains("report('Web view stopped: not created in time')"));
    expect(stuck, contains('_enterOffline();'));
  });
}
