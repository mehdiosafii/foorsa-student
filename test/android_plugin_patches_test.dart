// The two Android plugins the app carries patched (third_party/README.md).
// An upgrade that drops a patch brings back what it fixed, so each is pinned.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

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

  test('the camera takes its still in CameraX quality mode', () {
    final capture = _read('third_party/camera_android_camerax/android/src/main/java/io/flutter/plugins/camerax/'
        'ImageCaptureProxyApi.java');
    expect(capture, contains('builder.setCaptureMode(ImageCapture.CAPTURE_MODE_MAXIMIZE_QUALITY);'));
    expect(capture, contains('builder.setJpegQuality(FOORSA_JPEG_QUALITY);'));
  });

  test('the shell no longer asks Android to pre-raster the page', () {
    expect(_read('lib/src/shell_page.dart'), contains('offscreenPreRaster: false,'));
  });

  test('a web view that never says it was created hands over to the retry screen', () {
    final shell = _read('lib/src/shell_page.dart');
    final created = shell.indexOf('onWebViewCreated: (controller) {');
    expect(created, isNonNegative);
    expect(shell.substring(created, created + 120), contains('_startWatch?.cancel();'));
    expect(RegExp(r'_watchWebViewStart\(\);').allMatches(shell).length, 2,
        reason: 'when the first web view is put up, and when one is rebuilt');
    final watch = shell.substring(shell.indexOf('void _watchWebViewStart() {'));
    expect(watch.substring(0, 500), contains('_enterOffline();'));
  });
}
