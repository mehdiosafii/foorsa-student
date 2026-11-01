/// How this phone gets the token the portal registers for push notifications,
/// and why it did not when it did not.
///
/// The owner, 31 Oct 2026, testing from TestFlight: "i am not receiving
/// notifications in support". Not one phone was registered. Every step that
/// could stop a registration answered the portal with a status it dropped
/// without a word (`unconfigured`, `denied`, a `pending` that gave up after
/// fifteen seconds), so nobody could see which one it was. Now each reason is
/// sent to the crash board (Admin Portal › Student App in foorsa-reward), once a
/// day per reason and phone, and the portal is told the reason too:
///
/// - `push: Firebase not configured: <error type>`
/// - `push: permission denied`
/// - `push: APNs token never arrived` (with Apple's own error once the app
///   heard it: a build without the push entitlement says so here)
/// - `push: token failed: <code>`
///
/// Nothing about the student is sent: no token, no id, only the reason.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'crash_reports.dart';

/// The phone's notification permission, as the portal's Settings row shows it.
enum PushPermission { granted, provisional, denied, notDetermined }

String pushPermissionName(PushPermission permission) => switch (permission) {
      PushPermission.granted => 'granted',
      PushPermission.provisional => 'provisional',
      PushPermission.denied => 'denied',
      PushPermission.notDetermined => 'not_determined',
    };

/// What the phone does for a registration, so the logic can be tested without
/// Firebase (FirebasePushPlatform in student_push.dart is the real one).
abstract class PushPlatform {
  bool get isIOS;

  /// Firebase, and the handlers that need it. Throws when it cannot start.
  Future<void> initialize();

  /// The notification permission, asking the student first when [ask].
  Future<PushPermission> permission({required bool ask});

  /// The permission as the system has it, without Firebase.
  Future<PushPermission> systemPermission();

  /// Lets Firebase register with APNs (iOS registers for remote notifications).
  Future<void> enableAutoInit();

  /// The APNs device token once Apple gave one; null on Android.
  Future<String?> apnsToken();

  /// The FCM token the server sends to. May throw.
  Future<String?> fcmToken();

  /// The PushKit token for adviser calls (iPhone).
  Future<String?> voipToken();

  /// Apple's refusal of the APNs registration, if the app heard one.
  Future<String?> apnsError();
}

/// A short name for an error, never its message: an exception's type and its
/// code ("FirebaseException core/not-initialized", "PlatformException channel-error").
String describePushError(Object error) {
  final detail = switch (error) {
    FirebaseException(:final plugin, :final code) => '$plugin/$code',
    PlatformException(:final code) => code,
    _ => '',
  };
  final name = error.runtimeType.toString();
  final text = detail.isEmpty ? name : '$name $detail';
  final clean = text.replaceAll(RegExp(r'[^A-Za-z0-9 _./-]'), '');
  return clean.length > 80 ? clean.substring(0, 80) : clean;
}

/// Sends a reason a phone could not register to the crash board, at most once
/// a day per reason (kept on the phone, so a restart does not send it again).
class PushProblems {
  PushProblems({
    Future<bool> Function(String message)? send,
    Future<Directory> Function()? directory,
    DateTime Function()? now,
  })  : _send = send ?? ((message) => CrashReports.instance.report(message)),
        _directory = directory ?? getApplicationSupportDirectory,
        _now = now ?? DateTime.now;

  final Future<bool> Function(String message) _send;
  final Future<Directory> Function() _directory;
  final DateTime Function() _now;
  Map<String, String>? _sent;
  Future<void> _queue = Future<void>.value();

  static const _fileName = 'push_problems.json';

  /// Sends [reason] unless it went today; never throws.
  Future<void> report(String reason) {
    final next = _queue.then((_) => _report(reason));
    _queue = next.catchError((Object _) {});
    return _queue;
  }

  /// Done when every report asked for so far has been sent or dropped.
  @visibleForTesting
  Future<void> idle() => _queue;

  Future<void> _report(String reason) async {
    final text = reason.trim();
    if (text.isEmpty) return;
    final today = _now().toUtc().toIso8601String().substring(0, 10);
    final sent = _sent ??= await _read();
    if (sent[text] == today) return;
    if (!await _send(text)) return;
    sent[text] = today;
    // Only today's are worth keeping.
    sent.removeWhere((_, day) => day != today);
    await _write(sent);
  }

  Future<Map<String, String>> _read() async {
    try {
      final file = File('${(await _directory()).path}/$_fileName');
      if (!await file.exists()) return {};
      final value = jsonDecode(await file.readAsString());
      if (value is! Map) return {};
      return {for (final entry in value.entries) if (entry.value is String) '${entry.key}': entry.value as String};
    } catch (_) {
      return {};
    }
  }

  Future<void> _write(Map<String, String> sent) async {
    try {
      await File('${(await _directory()).path}/$_fileName').writeAsString(jsonEncode(sent));
    } catch (_) {
      // Sent again tomorrow at worst.
    }
  }
}

/// Getting a token for the portal, step by step, each refusal named.
class PushRegistration {
  PushRegistration(
    this.platform,
    this.problems, {
    this.apnsWait = const Duration(seconds: 10),
    this.apnsPoll = const Duration(milliseconds: 500),
    this.retryInitAfter = const Duration(seconds: 30),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final PushPlatform platform;
  final PushProblems problems;

  /// How long to wait for Apple's token after asking for it. The first one can
  /// take a few seconds on a slow network; three was not always enough.
  final Duration apnsWait;
  final Duration apnsPoll;

  /// A Firebase that did not start is tried again after this long: it used to
  /// be written off for the rest of the app's life.
  final Duration retryInitAfter;
  final DateTime Function() _now;

  bool _ready = false;
  String? _error;
  DateTime? _triedAt;
  Future<String?>? _starting;

  bool get ready => _ready;

  /// Starts Firebase once; null when it runs, else what stopped it.
  Future<String?> ensureReady() {
    if (_ready) return Future<String?>.value(null);
    final tried = _triedAt;
    if (_error != null && tried != null && _now().difference(tried) < retryInitAfter) {
      return Future<String?>.value(_error);
    }
    return _starting ??= _start().whenComplete(() => _starting = null);
  }

  Future<String?> _start() async {
    _triedAt = _now();
    try {
      await platform.initialize();
      _ready = true;
      _error = null;
      return null;
    } catch (error) {
      _error = describePushError(error);
      return _error;
    }
  }

  void _report(String reason) => unawaited(problems.report(reason));

  /// The token for `POST /api/portal/push/register`, or why there is none.
  /// Never throws: a step that fails unexpectedly is an `error` named by its
  /// step and type (`push: permission failed: PlatformException …`), so the
  /// portal tries again rather than finding the bridge call refused.
  Future<Map<String, dynamic>> token({required bool requestPermission, required bool callsEnabled}) async {
    var step = 'start';
    try {
      return await _token(requestPermission: requestPermission, callsEnabled: callsEnabled, at: (name) => step = name);
    } catch (error) {
      final code = describePushError(error);
      _report('push: $step failed: $code');
      return {'token': null, 'status': 'error', 'reason': '$step: $code'};
    }
  }

  Future<Map<String, dynamic>> _token({
    required bool requestPermission,
    required bool callsEnabled,
    required void Function(String step) at,
  }) async {
    final error = await ensureReady();
    if (error != null) {
      _report('push: Firebase not configured: $error');
      return {'token': null, 'status': 'unconfigured', 'reason': error};
    }
    at('permission');
    final permission = await platform.permission(ask: requestPermission);
    if (permission == PushPermission.denied) {
      _report('push: permission denied');
      return {'token': null, 'status': 'denied', 'permission': 'denied'};
    }
    if (permission == PushPermission.notDetermined) {
      return {'token': null, 'status': 'denied', 'permission': 'not_determined'};
    }
    at('auto-init');
    await platform.enableAutoInit();
    if (platform.isIOS) {
      at('APNs token');
      final deadline = _now().add(apnsWait);
      var apns = await platform.apnsToken();
      while (apns == null && _now().isBefore(deadline)) {
        await Future<void>.delayed(apnsPoll);
        apns = await platform.apnsToken();
      }
      if (apns == null) {
        final apnsError = await platform.apnsError();
        _report(apnsError == null ? 'push: APNs token never arrived' : 'push: APNs token never arrived: $apnsError');
        return {
          'token': null,
          'status': 'pending',
          'reason': 'apns',
          if (apnsError != null) 'apnsError': apnsError,
          'permission': pushPermissionName(permission),
        };
      }
    }
    String? token;
    try {
      token = await platform.fcmToken();
    } catch (error) {
      final code = describePushError(error);
      _report('push: token failed: $code');
      return {'token': null, 'status': 'error', 'reason': 'token: $code', 'permission': pushPermissionName(permission)};
    }
    if (token == null || token.isEmpty) {
      _report('push: token failed: empty');
      return {'token': null, 'status': 'error', 'reason': 'token: empty', 'permission': pushPermissionName(permission)};
    }
    String? voip;
    try {
      voip = await platform.voipToken();
    } catch (_) {
      voip = null;
    }
    return {
      'token': token,
      'platform': platform.isIOS ? 'ios' : 'android',
      'status': 'ready',
      'notificationVersion': 2,
      // The server rings only devices that say so (nativeAdviserCalls).
      'callsEnabled': callsEnabled,
      'voipToken': voip == null || voip.isEmpty ? null : voip,
      'permission': pushPermissionName(permission),
    };
  }

  /// Where this phone stands, without asking the student anything: the
  /// portal's Settings row (On, Off, Not set up yet).
  Future<Map<String, dynamic>> status() async {
    final error = await ensureReady();
    PushPermission permission;
    try {
      permission = error == null ? await platform.permission(ask: false) : await platform.systemPermission();
    } catch (_) {
      permission = PushPermission.notDetermined;
    }
    return {
      'platform': platform.isIOS ? 'ios' : 'android',
      'configured': error == null,
      if (error != null) 'reason': error,
      'permission': pushPermissionName(permission),
    };
  }

  @visibleForTesting
  String? get lastError => _error;
}
