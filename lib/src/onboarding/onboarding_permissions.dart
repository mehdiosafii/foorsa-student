/// The phone's own answers, through permission_handler.
///
/// iOS reports a permission never asked as `denied` and one refused as
/// `permanentlyDenied`; Android reports never asked and refused once as
/// `denied` (asking again still shows the prompt) and "don't ask again" as
/// `permanentlyDenied`. So `denied` is what the onboarding can still ask on
/// both. Each one needs its PERMISSION_* macro in ios/Podfile, or iOS reports
/// it refused without ever asking.
library;

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import 'onboarding_flow.dart';

class SystemBoardingPermissions implements BoardingPermissions {
  const SystemBoardingPermissions();

  Permission? _permission(BoardingAccess access) => switch (access) {
        BoardingAccess.notifications => Permission.notification,
        BoardingAccess.camera => Permission.camera,
        BoardingAccess.microphone => Permission.microphone,
        BoardingAccess.location => Permission.locationWhenInUse,
        // App Tracking Transparency exists on iOS only.
        BoardingAccess.tracking => defaultTargetPlatform == TargetPlatform.iOS
            ? Permission.appTrackingTransparency
            : null,
      };

  @override
  Future<AccessState> status(BoardingAccess access) async {
    final permission = _permission(access);
    if (permission == null) return AccessState.unavailable;
    return accessStateOf(await permission.status);
  }

  @override
  Future<AccessState> request(BoardingAccess access) async {
    final permission = _permission(access);
    if (permission == null) return AccessState.unavailable;
    final answer = accessStateOf(await permission.request());
    // Straight after a prompt, "not yet" means the student said no.
    return answer == AccessState.askable ? AccessState.denied : answer;
  }
}

@visibleForTesting
AccessState accessStateOf(PermissionStatus status) {
  if (status.isGranted || status.isLimited || status.isProvisional) {
    return AccessState.granted;
  }
  if (status.isRestricted) return AccessState.unavailable;
  if (status.isPermanentlyDenied) return AccessState.denied;
  return AccessState.askable;
}
