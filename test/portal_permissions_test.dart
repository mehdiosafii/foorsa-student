import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/portal_permissions.dart';
import 'package:foorsa_student/src/trusted_portal.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  // The plugin fixes each resource's native value the first time it is read,
  // for the platform of that moment. Every test here runs as an iPhone, where
  // the requests below come from, so nothing may read one before setUpAll.
  setUpAll(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);
  tearDownAll(() => debugDefaultTargetPlatformOverride = null);

  test('the portal may use its camera, its microphone and how the phone is held', () {
    for (final resources in [
      [PermissionResourceType.CAMERA],
      [PermissionResourceType.MICROPHONE],
      [PermissionResourceType.CAMERA, PermissionResourceType.MICROPHONE],
      [PermissionResourceType.CAMERA_AND_MICROPHONE],
      [PermissionResourceType.DEVICE_ORIENTATION_AND_MOTION],
    ]) {
      expect(portalMayUse(resources), isTrue, reason: '$resources');
    }
  });

  test('everything else is denied, alone or alongside what is allowed', () {
    final allowed = [
      PermissionResourceType.CAMERA,
      PermissionResourceType.MICROPHONE,
      PermissionResourceType.CAMERA_AND_MICROPHONE,
      PermissionResourceType.DEVICE_ORIENTATION_AND_MOTION,
    ];
    final others = PermissionResourceType.values.where((r) => !allowed.contains(r));
    expect(others, isNotEmpty);
    for (final resource in others) {
      expect(portalMayUse([resource]), isFalse, reason: '$resource');
      expect(portalMayUse([...allowed, resource]), isFalse, reason: 'with $resource');
    }
    expect(portalMayUse(const []), isFalse);
  });

  test('the phone allows the camera and the microphone first, and nothing for the tilt', () {
    expect(phonePermissionsFor([PermissionResourceType.CAMERA]), [Permission.camera]);
    expect(phonePermissionsFor([PermissionResourceType.MICROPHONE]), [Permission.microphone]);
    expect(
        phonePermissionsFor(
            [PermissionResourceType.CAMERA, PermissionResourceType.MICROPHONE]),
        [Permission.camera, Permission.microphone]);
    expect(phonePermissionsFor([PermissionResourceType.CAMERA_AND_MICROPHONE]),
        [Permission.camera, Permission.microphone]);
    expect(phonePermissionsFor([PermissionResourceType.DEVICE_ORIENTATION_AND_MOTION]),
        isEmpty);
  });

  test("an iPhone asks for the tilt as WKWebView does, and the portal may have it", () {
    // flutter_inappwebview_ios (InAppWebView.swift) sends WebKit's
    // requestDeviceOrientationAndMotionPermission with the page's origin as
    // protocol://host and this native resource.
    final request = PermissionRequest.fromMap({
      'origin': 'https://student.foorsa.ma',
      'resources': ['deviceOrientationAndMotion'],
    })!;
    expect(request.resources, [PermissionResourceType.DEVICE_ORIENTATION_AND_MOTION]);
    expect(isTrustedPortalOrigin(request.origin, 'https://student.foorsa.ma'), isTrue);
    expect(portalMayUse(request.resources), isTrue);
    expect(phonePermissionsFor(request.resources), isEmpty);
  });

  test('an iPhone asks for camera and microphone together as one resource', () {
    // WebKit names getUserMedia with audio and video
    // WKMediaCaptureTypeCameraAndMicrophone, which the plugin sends as 2: the
    // introduction video's studio films this way.
    final request = PermissionRequest.fromMap({
      'origin': 'https://student.foorsa.ma',
      'resources': [2],
    })!;
    expect(request.resources, [PermissionResourceType.CAMERA_AND_MICROPHONE]);
    expect(portalMayUse(request.resources), isTrue);
    expect(phonePermissionsFor(request.resources),
        [Permission.camera, Permission.microphone]);
  });

  test('the iPhone app may read how it is held: its motion purpose string is declared', () {
    // WebKit reads the sensors in the app's own process. iOS 27.2 lets people
    // restrict an app's motion data, so the app says why it reads it.
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(plist, contains('<key>NSMotionUsageDescription</key>'));
  });
}
