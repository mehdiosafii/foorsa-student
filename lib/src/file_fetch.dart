/// Fetching a file for the portal (a download, an in-app preview) and the
/// small loader shown over the portal while it is fetched.
///
/// Through 1.2.40 (71) the three fetches in shell_page.dart had no time limit at all:
/// on a connection that stalls (a weak signal, a network in mainland China
/// that stops answering mid-file) the loader stayed over the app for good, and
/// on an iPhone, which has no back button, the only way out was to close the
/// app. And the loader was taken away with a plain `Navigator.pop()`: on
/// Android a student who pressed back while it showed had already closed it,
/// so when the file arrived the pop took the app's own page instead and left
/// a blank screen (the stress test, 11 Nov 2026).
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

/// How long the server has to accept the connection.
const fileConnectLimit = Duration(seconds: 15);

/// How long the server has to start answering, and how long the file may go
/// without a byte arriving, before the fetch is given up.
const fileStallLimit = Duration(seconds: 30);

/// A server that answered with an error instead of the file.
class FileFetchStatus implements IOException {
  const FileFetchStatus(this.statusCode);
  final int statusCode;
  @override
  String toString() => 'HTTP $statusCode';
}

/// Downloads [uri] into [file]. Throws when the server cannot be reached,
/// answers with an error ([FileFetchStatus]) or stops sending for
/// [stallLimit] ([TimeoutException]); a file left half written is removed.
/// The connection is always closed.
Future<void> fetchToFile(
  Uri uri,
  File file, {
  Map<String, String> headers = const {},
  Duration connectLimit = fileConnectLimit,
  Duration stallLimit = fileStallLimit,
  HttpClient Function()? newClient,
}) async {
  final client = (newClient ?? HttpClient.new)()
    ..connectionTimeout = connectLimit;
  IOSink? sink;
  var complete = false;
  try {
    final request = await client.getUrl(uri).timeout(connectLimit);
    headers.forEach(request.headers.set);
    final response = await request.close().timeout(stallLimit);
    if (response.statusCode >= 400) {
      // The body is not wanted; reading it frees the connection.
      unawaited(response.drain<void>().catchError((Object _) {}));
      throw FileFetchStatus(response.statusCode);
    }
    sink = file.openWrite();
    await sink.addStream(response.timeout(stallLimit));
    await sink.flush();
    complete = true;
  } finally {
    try {
      await sink?.close();
    } catch (_) {
      // The file is removed just below.
    }
    // Not `close()`: a stalled connection would be waited for.
    client.close(force: true);
    if (!complete) {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {
        // A temporary file the system clears.
      }
    }
  }
}

/// The loader over the portal while a file is fetched: a route of its own,
/// taken away by removing that route and no other. Android's back button
/// closes it (the fetch goes on behind); [dismiss] is then a no-op.
class ShellSpinner {
  ShellSpinner._(this._navigator, this._route);

  final NavigatorState _navigator;
  final Route<void> _route;

  /// Shows [child] centred over everything; null when [context] is no longer
  /// on screen.
  static ShellSpinner? show(BuildContext context, {required Widget child}) {
    if (!context.mounted) return null;
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(child: child),
    );
    unawaited(navigator.push(route));
    return ShellSpinner._(navigator, route);
  }

  /// Whether the loader is still on screen.
  bool get showing => _route.isActive;

  /// Takes the loader away if it is still there. Safe to call twice, after
  /// the student closed it, and after the app's page has gone.
  void dismiss() {
    if (!_route.isActive || !_navigator.mounted) return;
    _navigator.removeRoute(_route);
  }
}
