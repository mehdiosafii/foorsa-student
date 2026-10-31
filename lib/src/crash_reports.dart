/// The app's own crashes reach the crash board in Foorsa Reward's Admin
/// Portal › Student App (POST /api/portal/client-error, `source: 'shell'`),
/// beside the portal's.
///
/// A report says what broke and where in the app's code, on which version and
/// system, and nothing about the student: no account, no page address, no file
/// name. The portal's own screens report their crashes themselves; this covers
/// what only the app sees: a Dart error, and the web view's content process
/// dying.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'config.dart';

/// The fields of one report, cleaned. Exposed for tests.
@visibleForTesting
Map<String, Object?> crashReportBody({
  required String message,
  String? where,
  String? build,
  required bool isIOS,
  String? osVersion,
}) {
  return {
    'source': 'shell',
    'message': cleanCrashLine(message, 300),
    'where': where == null ? null : cleanCrashLine(where, 200),
    'build': build,
    'platform': isIOS ? 'ios' : 'android',
    'os': osVersion,
  };
}

/// One line, short, with anything that could name a person or a file taken out.
@visibleForTesting
String cleanCrashLine(String text, int max) {
  var line = text
      .split('\n')
      .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '')
      .trim();
  line = line
      .replaceAll(
          RegExp(r'[a-z][a-z0-9+.-]*://\S+', caseSensitive: false), '<url>')
      .replaceAll(RegExp(r'(/[^\s/:]+){2,}'), '<path>')
      .replaceAll(RegExp(r'[^\s@]+@[^\s@]+\.[^\s@]+'), '<email>')
      .replaceAll(RegExp(r'\d{6,}'), '<number>');
  return line.length > max ? line.substring(0, max) : line;
}

/// The first frame of the app's own code in a stack, as `file.dart:line`.
@visibleForTesting
String? firstAppFrame(StackTrace? stack) {
  final match = RegExp(r'package:foorsa_student/([^\s:)]+):(\d+)')
      .firstMatch('$stack');
  return match == null ? null : '${match.group(1)}:${match.group(2)}';
}

/// "iOS 18.2" from iOS's "Version 18.2 (Build 22C152)". Android reports no
/// version here.
@visibleForTesting
String? osVersionOf(String operatingSystemVersion, {required bool isIOS}) {
  if (!isIOS) return null;
  final match = RegExp(r'(\d+(?:\.\d+){0,2})').firstMatch(operatingSystemVersion);
  return match == null ? null : 'iOS ${match.group(1)}';
}

class CrashReports {
  CrashReports._();
  static final CrashReports instance = CrashReports._();

  /// A launch sends at most this many, and the same message once.
  static const int maxPerLaunch = 5;
  final Set<String> _sent = {};
  String? _build;

  /// Hooks Flutter's and the platform's error handlers, keeping what was
  /// there before.
  void install() {
    PackageInfo.fromPlatform().then<void>(
      (info) => _build = '${info.version}+${info.buildNumber}',
      onError: (Object _) {},
    );
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      previous?.call(details);
      report(details.exceptionAsString(), stack: details.stack);
    };
    final platformPrevious = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      report('$error', stack: stack);
      return platformPrevious?.call(error, stack) ?? false;
    };
  }

  /// Sends one report and never throws.
  void report(String message, {StackTrace? stack, String? where}) {
    if (kDebugMode) return;
    final key = cleanCrashLine(message, 300);
    if (key.isEmpty || _sent.length >= maxPerLaunch || !_sent.add(key)) return;
    final body = crashReportBody(
      message: message,
      where: where ?? firstAppFrame(stack),
      build: _build,
      isIOS: Platform.isIOS,
      osVersion: osVersionOf(Platform.operatingSystemVersion,
          isIOS: Platform.isIOS),
    );
    unawaited(http
        .post(
          Uri.parse(AppConfig.baseUrl).resolve('/api/portal/client-error'),
          headers: {
            'Content-Type': 'application/json',
            'User-Agent': AppConfig.userAgentProduct,
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 10))
        .then<void>((_) {}, onError: (Object _) {}));
  }
}
