// Every way a document scan takes a photo inside the app is silent (the
// owner, 30 Oct 2026: "when scanning you hear shutter multiple times it needs
// to stay silent"; 1 Nov 2026: "in some docs i still hear shutters of
// capturing while scanning").
//
// - iPhone: the native scanner (FoorsaScannerViewController.swift) is the only
//   camera. From iOS 18 each photo asks for silence; before, the shutter's
//   system sound (1108) is released as the photo is taken (outside the regions
//   whose rules require it). The Flutter camera is never opened on an iPhone:
//   the camera plugin cannot silence a still, so a phone the native scanner
//   cannot serve (no back camera) is told so instead.
// - Android: the guided camera's still is CameraX's ImageCapture, which plays
//   no sound (CameraX 1.5 only reports MediaActionSound.mustPlayShutterSound;
//   it plays nothing, and neither does camera_android_camerax). Nothing in the
//   capture code plays one.
// - The phone's own camera app, which sounds its shutter, opens only when the
//   student taps it, and that button is there only when the guided camera
//   cannot open, under a name that says what it is.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

/// The capture code: the guided scanner, the bridge that opens it, and the
/// native sides of both platforms.
List<File> captureSources() => [
      ...Directory('lib/src/guided_scanner').listSync().whereType<File>().where((f) => f.path.endsWith('.dart')),
      File('lib/src/shell_page.dart'),
      ...Directory('android/app/src/main/kotlin').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.kt')),
      ...Directory('ios/Runner').listSync().whereType<File>().where((f) => f.path.endsWith('.swift')),
    ];

/// The body of the function that starts at [signature], up to its closing brace.
String body(String source, String signature) {
  final start = source.indexOf(signature);
  expect(start, isNonNegative, reason: 'missing $signature');
  final open = source.indexOf('{', start);
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') {
      depth--;
      if (depth == 0) return source.substring(open, i + 1);
    }
  }
  fail('unbalanced $signature');
}

void main() {
  test('no capture code plays a sound', () {
    final sounding = <RegExp>[
      RegExp(r'MediaActionSound\s*\('), // Android's shutter, click and focus sounds
      RegExp(r'\.play\(\s*MediaActionSound'),
      RegExp(r'\bSoundPool\b'),
      RegExp(r'\bToneGenerator\b'),
      RegExp(r'playSoundEffect\s*\('),
      RegExp(r'SystemSound\.play\s*\('), // Flutter's click
      RegExp(r'AudioServicesPlay(Alert|System)Sound'), // iOS system sounds
      RegExp(r'\bAudioPlayer\s*\('),
    ];
    for (final file in captureSources()) {
      final source = file.readAsStringSync();
      for (final pattern in sounding) {
        expect(pattern.hasMatch(source), isFalse, reason: '${file.path} plays a sound (${pattern.pattern})');
      }
    }
  });

  test('every iPhone photo is taken by the native scanner, and asks for silence', () {
    final scanner = read('ios/Runner/FoorsaScannerViewController.swift');
    // One place takes a photo, and it suppresses the shutter where iOS allows.
    expect(RegExp(r'capturePhoto\(with:').allMatches(scanner), hasLength(1));
    final takePhoto = body(scanner, 'private func takePhoto(camera:');
    expect(takePhoto, contains('settings.isShutterSoundSuppressionEnabled = true'));
    expect(takePhoto.indexOf('isShutterSoundSuppressionEnabled'), lessThan(takePhoto.indexOf('capturePhoto(with:')));
    // Before iOS 18, the shutter's system sound is released as the photo is taken.
    final willCapture = body(scanner, 'func photoOutput(_ output: AVCapturePhotoOutput, willCapturePhotoFor');
    expect(willCapture, contains('AudioServicesDisposeSystemSoundID(1108)'));
    // No other iPhone code takes a still.
    for (final file in Directory('ios/Runner').listSync().whereType<File>()) {
      if (file.path.endsWith('FoorsaScannerViewController.swift') || !file.path.endsWith('.swift')) continue;
      expect(file.readAsStringSync().contains('capturePhoto('), isFalse, reason: file.path);
    }
  });

  test('the Flutter camera, whose still the plugin cannot silence on an iPhone, opens only on Android', () {
    final shell = read('lib/src/shell_page.dart');
    final guided = body(shell, 'Future<Map<String, dynamic>> _guidedScanForWeb(');
    final iosBranch = body(guided, 'if (Platform.isIOS)');
    expect(iosBranch, contains("return {'error': guidedScanNoBackCamera};"));
    // The iPhone branch has answered before the Flutter camera is pushed.
    expect(guided.indexOf('if (Platform.isIOS)'), lessThan(guided.indexOf('GuidedScanPage(')));
    expect(RegExp(r'GuidedScanPage\(').allMatches(shell), hasLength(1));
  });

  test('the phone\'s camera app opens only when the student taps it, and only when the scanner cannot open', () {
    final shell = read('lib/src/shell_page.dart');
    // The bridge opens it for the guided scanner only on the scanner's own
    // "Camera app" answer (the portal's own camera picker is the other caller,
    // for builds older than the guided scanner).
    final guided = body(shell, 'Future<Map<String, dynamic>> _guidedScanForWeb(');
    final legacy = body(guided, 'if (result.useLegacyCamera)');
    expect(legacy, contains("_pickForWeb('camera', false)"));
    expect(RegExp(r"_pickForWeb\('camera'").allMatches(guided), hasLength(1));
    final page = read('lib/src/guided_scanner/guided_scan_page.dart');
    // Answered in one place (beside its declaration).
    expect(RegExp(r'pop\(const GuidedScanResult\.fallback\(\)\)').allMatches(page), hasLength(1));
    expect(body(page, 'Future<void> _useOtherCamera()'), contains('GuidedScanResult.fallback()'));
    // Its button is built only while the guided camera cannot open.
    final button = page.substring(page.indexOf('if (_cameraFailed)'), page.indexOf('Text(_cameraApp.of(language))'));
    expect(button, contains('_useOtherCamera'));
    expect(RegExp(r'_useOtherCamera\b').allMatches(page), hasLength(2)); // its definition and that button
  });
}
