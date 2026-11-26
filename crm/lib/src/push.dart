/// Notifications on the team's phones.
///
/// The CRM asks the app for a token after each sign-in (registerNativePushDevice
/// in foorsa-reward's src/lib/nativeBridge.ts) and stores it in device_tokens;
/// its chat and call notifications are then sent to it (fcmPush.service.ts).
///
/// - iPhone and iPad: Apple's own device token, as `apns:<hex>`, sent straight
///   through Apple (apnsPush.service.ts). No Google service is involved, so it
///   also works in mainland China.
/// - Android: a Firebase token, from the Firebase project the CRM's sender
///   already uses. A build without its Firebase file has none, and the CRM
///   falls back to its in-app alerts.
///
/// The native halves are AppDelegate.swift / PushBridge.swift and
/// MainActivity.kt / CrmMessagingService.kt, on the channel below.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class CrmPush {
  CrmPush._();
  static final CrmPush instance = CrmPush._();

  static const MethodChannel _channel = MethodChannel('foorsa_crm/push');

  /// Called with the CRM path a tapped notification asks for (`/?chat=…`).
  void Function(String route)? onOpen;

  bool _started = false;

  /// Listens for taps, and hands over the one that launched the app.
  Future<String?> start() async {
    if (_started) return null;
    _started = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'open' && call.arguments is String) {
        onOpen?.call(call.arguments as String);
      }
      return null;
    });
    try {
      final route = await _channel.invokeMethod<String>('ready');
      return (route != null && route.isNotEmpty) ? route : null;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// The token the CRM registers, after asking for permission to notify.
  /// Null when the phone said no, or push is not set up in this build.
  Future<String?> token() async {
    try {
      if (Platform.isAndroid) {
        final status = await Permission.notification.request();
        if (!status.isGranted) return null;
      }
      final token = await _channel
          .invokeMethod<String>('getToken')
          .timeout(const Duration(seconds: 15), onTimeout: () => null);
      return (token != null && token.isNotEmpty) ? token : null;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
