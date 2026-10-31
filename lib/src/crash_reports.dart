import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'config.dart';

/// The app's own failures, on the crash board (Admin Portal › Student App in
/// foorsa-reward, `POST /api/portal/client-error` with `source: 'shell'`).
///
/// Nothing about the student is sent: what broke, the screen's path, the
/// build and the system. The server cleans the text again (addresses, tokens,
/// emails and long numbers are taken out) and stores no student on the row.
/// Until 1.2.30 (61) the app reported nothing, so a web view that died for
/// memory after a few uploads never reached the board.
class CrashReports {
  CrashReports({http.Client? client, String? baseUrl, String? os})
      : _client = client,
        _baseUrl = baseUrl ?? AppConfig.baseUrl,
        _os = os ?? systemVersion();

  static final CrashReports instance = CrashReports();

  final http.Client? _client;
  final String _baseUrl;
  final String? _os;

  /// "1.2.30+61", set once the package info is read.
  String? build;

  /// The same report is sent at most once in this long: a web view that keeps
  /// dying must not spend the endpoint's per-device budget on one line.
  static const repeatAfter = Duration(minutes: 10);
  final Map<String, DateTime> _sent = {};

  /// Sends one report; never throws and never waits more than a few seconds.
  Future<bool> report(String message, {String? screen, String? where, DateTime? now}) async {
    final text = message.trim();
    if (text.isEmpty) return false;
    final at = now ?? DateTime.now();
    final key = '$text|${screen ?? ''}';
    final last = _sent[key];
    if (last != null && at.difference(last) < repeatAfter) return false;
    _sent[key] = at;
    final body = reportBody(text, screen: screen, where: where, build: build, os: _os);
    final client = _client ?? http.Client();
    try {
      final response = await client
          .post(Uri.parse(_baseUrl).resolve('/api/portal/client-error'),
              headers: const {'Content-Type': 'application/json'}, body: jsonEncode(body))
          .timeout(const Duration(seconds: 8));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      if (_client == null) client.close();
    }
  }

  /// The report as the server reads it (`cleanCrashReport`): a screen is a
  /// path's first two segments, a build and a system version only in the
  /// shapes it accepts.
  @visibleForTesting
  static Map<String, Object> reportBody(String message,
      {String? screen, String? where, String? build, String? os}) {
    final path = screenPath(screen);
    return {
      'source': 'shell',
      'platform': Platform.isIOS ? 'ios' : 'android',
      'message': message.length > 300 ? message.substring(0, 300) : message,
      if (where != null && where.isNotEmpty) 'where': where.length > 200 ? where.substring(0, 200) : where,
      if (path != null) 'screen': path,
      if (build != null && RegExp(r'^[A-Za-z0-9._+-]{1,40}$').hasMatch(build)) 'build': build,
      if (os != null && RegExp(r'^(iOS|Android) [0-9][0-9.]{0,10}$').hasMatch(os)) 'os': os,
    };
  }

  /// "/documents/identity" from a portal address; null for anything else.
  @visibleForTesting
  static String? screenPath(String? url) {
    if (url == null || url.isEmpty) return null;
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final parts = uri.path.split('/').where((part) => part.isNotEmpty).take(2).toList();
    final path = '/${parts.join('/')}';
    return RegExp(r'^/[a-z0-9/-]{0,60}$', caseSensitive: false).hasMatch(path) ? path : null;
  }

  /// "iOS 18.7" or "Android 14" when the system says so plainly, else null.
  @visibleForTesting
  static String? systemVersion([String? raw, bool? isIOS]) {
    final ios = isIOS ?? Platform.isIOS;
    final value = raw ?? Platform.operatingSystemVersion;
    final match = RegExp(r'(\d+(?:\.\d+){0,2})').firstMatch(value);
    if (!ios) return null; // Android's string is the kernel's, not the system's.
    return match == null ? null : 'iOS ${match.group(1)}';
  }
}

/// Reports a Dart error that reached the top of the app, without changing what
/// Flutter does with it.
void reportUncaughtErrors() {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    unawaited(CrashReports.instance.report('Flutter: ${_firstLine(details.exceptionAsString())}',
        where: details.library));
    previous?.call(details);
  };
  final dispatcherPrevious = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(CrashReports.instance.report('Dart: ${_firstLine('$error')}'));
    return dispatcherPrevious?.call(error, stack) ?? false;
  };
}

String _firstLine(String text) {
  final line = text.split('\n').first.trim();
  return line.length > 240 ? line.substring(0, 240) : line;
}
