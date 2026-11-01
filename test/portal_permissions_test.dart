import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/portal_permissions.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  const portal = 'https://student.foorsa.ma';

  // The plugin works out a resource's native value the first time it is read,
  // for the platform of that moment, and how the phone is held has one only
  // on iOS. This file runs as an iPhone, so nothing may read a resource before
  // setUpAll: the lists below are late.
  setUpAll(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);
  tearDownAll(() => debugDefaultTargetPlatformOverride = null);

  late final allowed = [
    PermissionResourceType.CAMERA,
    PermissionResourceType.MICROPHONE,
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

  test('the portal has its camera and microphone once the phone allows them',
      () {
    expect(decide([PermissionResourceType.CAMERA]), [Permission.camera]);
    expect(
        decide([PermissionResourceType.MICROPHONE]), [Permission.microphone]);
    expect(
        decide([
          PermissionResourceType.CAMERA,
          PermissionResourceType.MICROPHONE,
        ]),
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
    // Among them CAMERA_AND_MICROPHONE, WKWebView's name for a getUserMedia
    // call asking for video and audio together.
    expect(others, contains(PermissionResourceType.CAMERA_AND_MICROPHONE));
    expect(others, contains(PermissionResourceType.UNKNOWN));
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

  test("an iPhone's request for the tilt, as the plugin hands it over, is granted",
      () {
    // flutter_inappwebview_ios 1.1.2 (InAppWebView.swift) turns WebKit's
    // requestDeviceOrientationAndMotionPermissionFor into this: the page's
    // origin as protocol://host, and one native resource.
    final request = PermissionRequest.fromMap({
      'origin': 'https://student.foorsa.ma',
      'resources': ['deviceOrientationAndMotion'],
    })!;
    expect(request.resources,
        [PermissionResourceType.DEVICE_ORIENTATION_AND_MOTION]);
    expect(
        phonePermissionsBeforeGrant(
          origin: request.origin,
          page: Uri.parse('$portal/'),
          resources: request.resources,
          baseUrl: portal,
        ),
        const <Permission>[]);
  });
}
