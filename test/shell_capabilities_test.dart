import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/shell_capabilities.dart';

void main() {
  test('an iPhone build offers the portal its video picker', () {
    expect(shellCapabilities(isIOS: true), {
      'embeddedFrames': true,
      'videoInput': true,
      'hapticTextures': 3,
      'bootHandoff': true,
    });
  });

  test('Android keeps the video with the adviser', () {
    expect(shellCapabilities(isIOS: false), {
      'embeddedFrames': true,
      'videoInput': false,
      'hapticTextures': 3,
      'bootHandoff': true,
    });
  });

  test('the iPhone app may film: its microphone permission is declared', () {
    // Without it iOS closes the app as soon as the picker records a video.
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(plist, contains('<key>NSMicrophoneUsageDescription</key>'));
    expect(plist, contains('<key>NSCameraUsageDescription</key>'));
  });

  test('Android may play the textures: VIBRATE is declared', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('android.permission.VIBRATE'));
  });
}
