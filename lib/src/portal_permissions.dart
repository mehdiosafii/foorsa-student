/// What the web view may grant when a page asks for a device resource
/// (onPermissionRequest in shell_page.dart), and what the phone must allow
/// first. Pure, so it is tested without a web view.
///
/// Until 1.2.33 (64) the shell granted only CAMERA and MICROPHONE, one at a
/// time. An iPhone asks in two other ways, and both were denied:
/// - one getUserMedia call for video and audio together, which WKWebView
///   reports as one resource, CAMERA_AND_MICROPHONE (the introduction
///   video's studio films that way, so on an iPhone it stopped at "Foorsa
///   can’t use your camera and microphone" before its set-up);
/// - DeviceOrientationEvent.requestPermission(), which WKWebView (iOS 15 and
///   later) hands to the app as DEVICE_ORIENTATION_AND_MOTION (the studio's
///   check of how the phone is held, the admission reveal's tilt).
/// Android names the camera and the microphone separately and delivers the
/// orientation without asking.
library;

import 'package:flutter_inappwebview/flutter_inappwebview.dart'
    show PermissionResourceType;
import 'package:permission_handler/permission_handler.dart' show Permission;

import 'trusted_portal.dart';

/// Each resource the portal may be granted, with the phone permissions asked
/// for before it is. Any other resource is denied.
final Map<PermissionResourceType, List<Permission>> _portalResources = {
  PermissionResourceType.CAMERA: const [Permission.camera],
  PermissionResourceType.MICROPHONE: const [Permission.microphone],
  // Video with sound in one call: no more than CAMERA and MICROPHONE get on
  // their own, asked for in the same order.
  PermissionResourceType.CAMERA_AND_MICROPHONE: const [
    Permission.camera,
    Permission.microphone,
  ],
  // How the phone is held. WebKit reads the motion sensors itself, and the
  // phone has no permission to ask for, so nothing is asked of it.
  // Info.plist says why the app reads them (NSMotionUsageDescription), shown
  // only if iOS ever asks.
  PermissionResourceType.DEVICE_ORIENTATION_AND_MOTION: const [],
};

/// Decides a web view permission request for [resources], made by [origin]
/// while the web view shows [page]. Null denies it; otherwise it is granted
/// once the phone has allowed each permission returned, in order, each once
/// (none for how the phone is held).
///
/// Only the configured portal ([baseUrl]) is granted anything, and only while
/// it is the page on show. A request is granted only if the portal may have
/// every resource in it.
List<Permission>? phonePermissionsBeforeGrant({
  required Uri? origin,
  required Uri? page,
  required List<PermissionResourceType> resources,
  required String baseUrl,
}) {
  if (!isTrustedPortalOrigin(origin, baseUrl) ||
      !isTrustedPortalOrigin(page, baseUrl) ||
      resources.isEmpty ||
      !resources.every(_portalResources.containsKey)) {
    return null;
  }
  return {for (final resource in resources) ..._portalResources[resource]!}
      .toList();
}
