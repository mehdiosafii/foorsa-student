/// What the portal may use through the web view's permission requests
/// (onPermissionRequest in shell_page.dart), and what the phone must allow
/// first. Only the portal itself may ask (trusted_portal.dart).
library;

import 'package:flutter_inappwebview/flutter_inappwebview.dart'
    show PermissionResourceType;
import 'package:permission_handler/permission_handler.dart' show Permission;

/// Each resource the portal may be granted, with the phone's own permissions
/// to ask for first. Anything else is denied.
final Map<PermissionResourceType, List<Permission>> _granted = {
  PermissionResourceType.CAMERA: const [Permission.camera],
  PermissionResourceType.MICROPHONE: const [Permission.microphone],
  // How the phone is held, which iOS asks the app about when the page calls
  // DeviceOrientationEvent.requestPermission() inside a tap: the admission
  // reveal leans with the phone, and the introduction video's studio checks
  // that it is upright. Android delivers it without asking. WebKit reads Core
  // Motion's device motion itself, so the phone has nothing to allow here
  // (not Permission.sensors: on iOS that is Motion & Fitness activity, a
  // prompt of its own).
  PermissionResourceType.DEVICE_ORIENTATION_AND_MOTION: const [],
};

/// Whether the portal may have everything [resources] asks for.
bool portalMayUse(List<PermissionResourceType> resources) =>
    resources.isNotEmpty && resources.every(_granted.containsKey);

/// The phone's permissions to ask for, in order, before [resources] are
/// granted to the portal.
List<Permission> phonePermissionsFor(List<PermissionResourceType> resources) =>
    [for (final resource in resources) ...?_granted[resource]];
