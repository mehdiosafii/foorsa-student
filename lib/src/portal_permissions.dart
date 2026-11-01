/// What the web view may grant when a page asks for a device resource
/// (onPermissionRequest in shell_page.dart), and what the phone must allow
/// first. Pure, so it is tested without a web view.
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
  // Both at once: WKWebView's name for one getUserMedia call asking for video
  // and audio together, as the introduction video's studio films. Android
  // names each, as CAMERA and MICROPHONE.
  PermissionResourceType.CAMERA_AND_MICROPHONE: const [
    Permission.camera,
    Permission.microphone,
  ],
  // How the phone is held. iOS 15 and later ask the app when the page calls
  // DeviceOrientationEvent.requestPermission() (or DeviceMotionEvent's) inside
  // a tap: the admission reveal, the introduction video's set-up. WebKit
  // reads the motion sensors itself and the phone has no permission to ask
  // for, so nothing is asked of it. Info.plist still says why the app reads
  // them (NSMotionUsageDescription), in case iOS starts asking: iOS 27.2 adds
  // CMMotionManager.authorizationStatus. Android delivers it without asking.
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
