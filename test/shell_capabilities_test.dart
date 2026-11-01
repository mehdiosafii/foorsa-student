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
      'language': true,
      'push': 2,
      'pagePermissions': 2,
      'mapApps': 1,
    });
  });

  test('Android offers the portal its video picker too', () {
    expect(shellCapabilities(isIOS: false), {
      'embeddedFrames': true,
      'videoInput': true,
      'hapticTextures': 3,
      'bootHandoff': true,
      'language': true,
      'push': 2,
      'pagePermissions': 2,
      'mapApps': 1,
    });
  });

  test('the build says which version it is, for the Student App board', () {
    final caps = shellCapabilities(isIOS: true, appVersion: '1.2.30', appBuild: '61');
    expect(caps['appVersion'], '1.2.30');
    expect(caps['appBuild'], '61');
    // Only the shape the server stores (student_app_sessions.app_version).
    final odd = shellCapabilities(isIOS: true, appVersion: '1.2 beta<script>', appBuild: '');
    expect(odd.containsKey('appVersion'), isFalse);
    expect(odd.containsKey('appBuild'), isFalse);
  });

  test('the iPhone app may film: its microphone permission is declared', () {
    // Without it iOS closes the app as soon as the picker records a video.
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(plist, contains('<key>NSMicrophoneUsageDescription</key>'));
    expect(plist, contains('<key>NSCameraUsageDescription</key>'));
  });

  test('Android 11 and later can open the camera and file apps from the page', () {
    // Without these queries the WebView's chooser finds nothing to open.
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('<action android:name="android.media.action.IMAGE_CAPTURE"/>'));
    expect(manifest, contains('<action android:name="android.media.action.VIDEO_CAPTURE"/>'));
    expect(manifest, contains('<action android:name="android.intent.action.GET_CONTENT"/>'));
  });

  test('Android may play the textures: VIBRATE is declared', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('android.permission.VIBRATE'));
  });

  test('Android holds no foreground service or full-screen intent', () {
    // Native adviser calls are iPhone only for now (nativeAdviserCalls):
    // Google Play takes foreground services and full-screen intents only with
    // Play Console declarations and a video of a real call.
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    for (final permission in [
      'FOREGROUND_SERVICE',
      'FOREGROUND_SERVICE_PHONE_CALL',
      'FOREGROUND_SERVICE_MICROPHONE',
      'FOREGROUND_SERVICE_CAMERA',
      'USE_FULL_SCREEN_INTENT',
    ]) {
      expect(
          manifest,
          contains('<uses-permission android:name="android.permission.$permission" '
              'tools:node="remove"/>'),
          reason: permission);
    }
    for (final service in ['CallkitNotificationService', 'CallkitConnectionService']) {
      expect(
          RegExp('android:name="com\\.hiennv\\.flutter_callkit_incoming\\.$service"'
                  r'\s+tools:remove="android:foregroundServiceType"')
              .hasMatch(manifest),
          isTrue,
          reason: service);
    }
    expect(manifest, isNot(contains('android:foregroundServiceType=')));
  });

  test('no hardware is required to install the app on Android', () {
    // Each permission or plugin below would make Google Play require the
    // hardware, and 1.2.27 (58) would have dropped 148 devices that ran
    // 1.2.17 (32). The plugin's camera.any must be overridden, not just
    // declared again: its required defaults to true.
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final features = RegExp(r'<uses-feature\b[^>]*>').allMatches(manifest).map((m) => m[0]!);
    String? declared(String name) =>
        features.where((tag) => tag.contains('android:name="$name"')).firstOrNull;
    for (final name in [
      'android.hardware.camera',
      'android.hardware.camera.any',
      'android.hardware.camera.autofocus',
      'android.hardware.microphone',
      'android.hardware.bluetooth',
      'android.hardware.location',
    ]) {
      expect(declared(name), contains('android:required="false"'), reason: name);
    }
    expect(declared('android.hardware.camera.any'), contains('tools:replace="android:required"'));
  });
}
