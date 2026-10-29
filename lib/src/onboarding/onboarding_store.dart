/// Whether this phone should see the first-launch onboarding.
///
/// It is for first-time downloaders. A student updating from an older build
/// has used the app already: the WebView has kept its data on the phone
/// (`app_webview` beside the app's files on Android, Library/WebKit on iOS),
/// so they go straight to the portal, as before, and never see it.
///
/// The onboarding is marked `started` before anything else runs, because the
/// portal loads behind it and creates that WebView data at once: a first
/// launch closed halfway must open on the onboarding again next time, not be
/// taken for an update.
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';

enum OnboardingRecord { none, started, done }

class OnboardingStore {
  OnboardingStore({
    Future<Directory> Function()? directory,
    Future<List<Directory>> Function()? webViewData,
  })  : _directory = directory ?? getApplicationSupportDirectory,
        _webViewData = webViewData ?? _defaultWebViewData;

  final Future<Directory> Function() _directory;
  final Future<List<Directory>> Function() _webViewData;

  static const _fileName = 'first_launch_onboarding';

  /// Where a WebView that has run before keeps its data.
  static Future<List<Directory>> _defaultWebViewData() async {
    final dirs = <Directory>[];
    try {
      if (Platform.isAndroid) {
        final files = await getApplicationSupportDirectory();
        dirs.add(Directory('${files.parent.path}/app_webview'));
      } else if (Platform.isIOS) {
        final library = await getLibraryDirectory();
        dirs.add(Directory('${library.path}/WebKit'));
      }
    } catch (_) {
      // Nothing known: treated as a first launch.
    }
    return dirs;
  }

  Future<File> _file() async =>
      File('${(await _directory()).path}${Platform.pathSeparator}$_fileName');

  Future<OnboardingRecord> read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return OnboardingRecord.none;
      return switch ((await file.readAsString()).trim()) {
        'done' => OnboardingRecord.done,
        'started' => OnboardingRecord.started,
        _ => OnboardingRecord.none,
      };
    } catch (_) {
      return OnboardingRecord.none;
    }
  }

  Future<void> _write(String value) async {
    try {
      await (await _file()).writeAsString(value, flush: true);
    } catch (_) {
      // Worst case the onboarding shows once more.
    }
  }

  /// Whether to show the onboarding on this launch, decided once before the
  /// first frame. Never throws: the app must open whatever happens here.
  Future<bool> shouldShow() async {
    try {
      switch (await read()) {
        case OnboardingRecord.done:
          return false;
        case OnboardingRecord.started:
          return true;
        case OnboardingRecord.none:
          for (final dir in await _webViewData()) {
            if (await dir.exists()) {
              // An update: this phone has run the portal before.
              await _write('done');
              return false;
            }
          }
          await _write('started');
          return true;
      }
    } catch (_) {
      return false;
    }
  }

  Future<void> markDone() => _write('done');
}
