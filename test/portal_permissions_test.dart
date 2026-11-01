import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/portal_permissions.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  const portal = 'https://student.foorsa.ma';

  // The plugin works out a resource's native value the first time it is read,
  // for the platform of that moment, and the resources below have theirs on
  // iOS. This file runs as an iPhone, so nothing may read a resource before
  // setUpAll: the lists below are late.
  setUpAll(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);
  tearDownAll(() => debugDefaultTargetPlatformOverride = null);

  late final allowed = [
    PermissionResourceType.CAMERA,
    PermissionResourceType.MICROPHONE,
    PermissionResourceType.CAMERA_AND_MICROPHONE,
    PermissionResourceType.DEVICE_ORIENTATION_AND_MOTION,
  ];
  late final others = PermissionResourceType.values
      .where((resource) => !allowed.contains(resource))
      .toList();

  List<Permission>? decide(List<PermissionResourceType> resources,
          {String origin = portal, String? page = '$portal/home'}) =>
      phonePermissionsBeforeGrant(
        origin: Uri.parse(origin),
        page: page == null ? null : Uri.parse(page),
        resources: resources,
        baseUrl: portal,
      );

  // How the iOS plugin (flutter_inappwebview_ios 1.1.2, InAppWebView.swift)
  // hands WebKit's question over: the page's origin as protocol://host, and
  // one native resource.
  PermissionRequest fromIPhone(Object nativeResource) =>
      PermissionRequest.fromMap({
        'origin': portal,
        'resources': [nativeResource],
      })!;

  test('the portal has its camera and microphone, apart or together, once the '
      'phone allows them', () {
    expect(decide([PermissionResourceType.CAMERA]), [Permission.camera]);
    expect(
        decide([PermissionResourceType.MICROPHONE]), [Permission.microphone]);
    expect(
        decide([
          PermissionResourceType.CAMERA,
          PermissionResourceType.MICROPHONE,
        ]),
        [Permission.camera, Permission.microphone]);
    expect(decide([PermissionResourceType.CAMERA_AND_MICROPHONE]),
        [Permission.camera, Permission.microphone]);
  });

  test('the portal reads how the phone is held without asking the phone', () {
    // Granted (not null), and permission_handler is asked for nothing.
    expect(decide([PermissionResourceType.DEVICE_ORIENTATION_AND_MOTION]),
        const <Permission>[]);
  });

  test('no other origin is granted anything, nor the portal under another page',
      () {
    for (final resource in allowed) {
      for (final origin in [
        'https://attacker.example',
        'http://student.foorsa.ma',
        'https://student.foorsa.ma.attacker.example',
        'https://student.foorsa.ma:8443',
        'https://www.youtube-nocookie.com',
      ]) {
        expect(decide([resource], origin: origin), isNull,
            reason: '$resource from $origin');
      }
      expect(decide([resource], page: 'https://attacker.example/'), isNull,
          reason: '$resource under another page');
      expect(decide([resource], page: null), isNull,
          reason: '$resource with no page');
    }
  });

  test('any other resource is denied, and so is a request for nothing', () {
    expect(others, contains(PermissionResourceType.UNKNOWN));
    expect(others, contains(PermissionResourceType.MIDI_SYSEX));
    for (final resource in others) {
      expect(decide([resource]), isNull, reason: '$resource');
    }
    expect(decide(const []), isNull);
  });

  test('a mixed request is granted only if every resource in it is allowed',
      () {
    expect(
        decide([
          PermissionResourceType.DEVICE_ORIENTATION_AND_MOTION,
          PermissionResourceType.CAMERA,
        ]),
        [Permission.camera]);
    // Each phone permission is asked for once.
    expect(decide(allowed), [Permission.camera, Permission.microphone]);
    for (final other in others) {
      expect(
          decide([PermissionResourceType.DEVICE_ORIENTATION_AND_MOTION, other]),
          isNull,
          reason: 'orientation with $other');
      expect(decide([...allowed, other]), isNull,
          reason: 'everything allowed with $other');
    }
  });

  test("an iPhone's request for the tilt, as the plugin hands it over, is "
      'granted', () {
    // WebKit's requestDeviceOrientationAndMotionPermissionFor: the page called
    // DeviceOrientationEvent.requestPermission() inside a tap.
    final request = fromIPhone('deviceOrientationAndMotion');
    expect(request.resources,
        [PermissionResourceType.DEVICE_ORIENTATION_AND_MOTION]);
    expect(
        phonePermissionsBeforeGrant(
          origin: request.origin,
          page: Uri.parse('$portal/introduction-video'),
          resources: request.resources,
          baseUrl: portal,
        ),
        const <Permission>[]);
  });

  test("an iPhone's request to film with sound, as the plugin hands it over, "
      'is granted after the camera and the microphone', () {
    // WebKit's requestMediaCapturePermissionFor with
    // WKMediaCaptureType.cameraAndMicrophone (2): one getUserMedia call asking
    // for video and audio, as the introduction video's studio films.
    final request = fromIPhone(2);
    expect(request.resources, [PermissionResourceType.CAMERA_AND_MICROPHONE]);
    expect(
        phonePermissionsBeforeGrant(
          origin: request.origin,
          page: Uri.parse('$portal/introduction-video'),
          resources: request.resources,
          baseUrl: portal,
        ),
        [Permission.camera, Permission.microphone]);
    // And the camera and the microphone alone, as before.
    expect(fromIPhone(0).resources, [PermissionResourceType.CAMERA]);
    expect(fromIPhone(1).resources, [PermissionResourceType.MICROPHONE]);
  });

  test('the iPhone app says why it reads how the phone is held', () {
    // Shown only if iOS ever asks; worded in French and Arabic too
    // (shell_languages_test.dart holds every purpose string to that).
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(plist, contains('<key>NSMotionUsageDescription</key>'));
  });
}
