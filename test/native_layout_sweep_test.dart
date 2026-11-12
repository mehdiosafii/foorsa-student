import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/app_language.dart';
import 'package:foorsa_student/src/config.dart';
import 'package:foorsa_student/src/device_access.dart';
import 'package:foorsa_student/src/quick_sign_in_offer.dart';
import 'package:foorsa_student/src/shell_screens.dart';
import 'package:foorsa_student/src/student_calls.dart';

/// The app's own screens (the ones that are not the portal's web page) on
/// every phone they can meet: a small one, a large one, a phone on its side
/// (the app rotates), a tablet, with the text size a student may have set in
/// the phone's settings, in the three languages.
///
/// The owner's stress test, 12 Nov 2026. Until then only the onboarding had
/// been laid out on a small phone and with larger text; nothing had been
/// tried on its side or at the largest text.
///
/// A screen fails here when Flutter reports that something does not fit (in
/// a release that is content cut off at the screen's edge), or when the
/// control the screen exists for is not wholly on it.

const _phones = <(String, Size, EdgeInsets)>[
  ('the first iPhone SE', Size(320, 568), EdgeInsets.only(top: 20)),
  ('a small Android', Size(360, 640), EdgeInsets.only(top: 24)),
  ('an iPhone 14', Size(390, 844), EdgeInsets.only(top: 47, bottom: 34)),
  ('a large Android', Size(412, 915), EdgeInsets.only(top: 32, bottom: 16)),
  ('the first iPhone SE on its side', Size(568, 320), EdgeInsets.zero),
  (
    'an iPhone 14 on its side',
    Size(844, 390),
    EdgeInsets.only(left: 47, right: 47, bottom: 21)
  ),
  ('a tablet', Size(768, 1024), EdgeInsets.only(top: 24, bottom: 20)),
];

/// 1.3 is the largest text of the ordinary settings on both systems; 2.0 is
/// Android's largest and well into an iPhone's accessibility sizes.
const _scales = [1.0, 1.3, 2.0];

typedef _Case = ({String phone, Size size, double scale, AppLanguage language});

var _arabicFont = false;

Iterable<_Case> _cases() sync* {
  for (final (phone, size, _) in _phones) {
    for (final scale in _scales) {
      for (final language in AppLanguage.values) {
        if (language == AppLanguage.ar && !_arabicFont) continue;
        yield (phone: phone, size: size, scale: scale, language: language);
      }
    }
  }
}

/// Loads the fonts; false (and the test marked skipped) where the SDK's are
/// not to be found.
Future<bool> _ready(WidgetTester tester) async {
  final fonts = await tester.runAsync(_loadFonts);
  if (fonts == null || !fonts.latin) {
    markTestSkipped('The Flutter SDK\'s fonts are not here.');
    return false;
  }
  _arabicFont = fonts.arabic;
  return true;
}

String _name(_Case c) =>
    '${c.phone} (${c.size.width.toInt()}x${c.size.height.toInt()}), '
    'text x${c.scale}, ${c.language.code}';

void _phone(WidgetTester tester, _Case c) {
  final padding = _phones.firstWhere((p) => p.$1 == c.phone).$3;
  tester.view.physicalSize = c.size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = FakeViewPadding(
      left: padding.left,
      top: padding.top,
      right: padding.right,
      bottom: padding.bottom);
  tester.platformDispatcher.textScaleFactorTestValue = c.scale;
}

void _reset(WidgetTester tester) {
  tester.view.reset();
  tester.platformDispatcher.clearTextScaleFactorTestValue();
}

/// The fonts a phone draws with, from the Flutter SDK's own files: the test
/// framework's stand-in font draws every letter as a square, about twice as
/// wide as text is, and would call most of these screens too narrow.
///
/// Roboto is in the SDK's cache wherever Flutter runs. An Arabic face is in
/// the SDK's source tree; where it is not, Arabic is left out of the sweep
/// rather than measured in squares.
Future<({bool latin, bool arabic})> _loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return (latin: false, arabic: false);
  final dir = Directory('$root/bin/cache/artifacts/material_fonts');
  if (!dir.existsSync()) return (latin: false, arabic: false);
  Future<ByteData> bytes(String path) async =>
      ByteData.sublistView(await File(path).readAsBytes());
  await (FontLoader('Roboto')
        ..addFont(bytes('${dir.path}/Roboto-Regular.ttf'))
        ..addFont(bytes('${dir.path}/Roboto-Medium.ttf'))
        ..addFont(bytes('${dir.path}/Roboto-Bold.ttf')))
      .load();
  await (FontLoader('MaterialIcons')
        ..addFont(bytes('${dir.path}/MaterialIcons-Regular.otf')))
      .load();
  final naskh = File(
      '$root/engine/src/flutter/txt/third_party/fonts/NotoNaskhArabic-Regular.ttf');
  if (!naskh.existsSync()) return (latin: true, arabic: false);
  await (FontLoader('NotoNaskhArabic')..addFont(bytes(naskh.path))).load();
  return (latin: true, arabic: true);
}

/// The app as main.dart builds it: its theme, and its language over every
/// screen and every dialog (the call screen sits there too).
Widget _app(_Case c, Widget child,
        {TargetPlatform? platform, bool calls = false}) =>
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        platform: platform,
        fontFamily: 'Roboto',
        fontFamilyFallback: const ['NotoNaskhArabic'],
        colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(AppConfig.brandColorValue)),
      ),
      builder: (context, page) => AppLanguageScope(
        language: c.language,
        child: calls
            ? StudentCallOverlay(child: page ?? const SizedBox.shrink())
            : page ?? const SizedBox.shrink(),
      ),
      home: child,
    );

/// What Flutter reported since the last look, in one line.
String? _reported(WidgetTester tester) {
  final error = tester.takeException();
  if (error == null) return null;
  return error.toString().split('\n').first;
}

/// Whether [finder]'s one widget lies wholly on a screen of [size].
String? _offScreen(WidgetTester tester, Finder finder, Size size, String what) {
  if (finder.evaluate().isEmpty) return '$what is not there';
  final rect = tester.getRect(finder.first);
  const slack = 0.5;
  if (rect.left < -slack ||
      rect.top < -slack ||
      rect.right > size.width + slack ||
      rect.bottom > size.height + slack) {
    return '$what is off the screen: ${rect.left.round()},${rect.top.round()} '
        'to ${rect.right.round()},${rect.bottom.round()}';
  }
  return null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('no connection: the whole screen, and Try again, on every phone',
      (tester) async {
    if (!await _ready(tester)) return;
    final problems = <String>[];
    for (final c in _cases()) {
      for (final dark in [false, true]) {
        _phone(tester, c);
        // Under the shell's own Scaffold, as shell_page.dart shows it.
        await tester.pumpWidget(_app(
            c,
            Scaffold(
                body: ShellOfflineScreen(
                    onRetry: () {}, dark: dark, language: c.language))));
        await tester.pump();
        var said = _reported(tester);
        final retry = find.text(offlineRetry.of(c.language));
        // With the phone's ordinary text, Try again is on the screen as it
        // opens, on its side too. With larger text the screen may have to
        // scroll to it: it must then be there to scroll to.
        if (said == null && c.scale > 1 && retry.evaluate().isNotEmpty) {
          await tester.ensureVisible(retry);
          await tester.pump();
          said = _reported(tester);
        }
        said ??= _offScreen(tester, retry, c.size, 'Try again');
        if (said != null) {
          problems.add('${_name(c)}${dark ? ', dark' : ''}: $said');
        }
        await tester.pumpWidget(const SizedBox());
      }
    }
    _reset(tester);
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  testWidgets('the loader fits wherever it is shown', (tester) async {
    if (!await _ready(tester)) return;
    final problems = <String>[];
    for (final c in _cases().where((c) => c.language == AppLanguage.en)) {
      _phone(tester, c);
      await tester.pumpWidget(_app(c, const ShellLoadingScreen(dark: true)));
      await tester.pump(const Duration(milliseconds: 400));
      final said = _reported(tester);
      if (said != null) problems.add('${_name(c)}: $said');
      await tester.pumpWidget(const SizedBox());
    }
    _reset(tester);
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  group('"Set up your device"', () {
    const channel = MethodChannel('flutter.baseflow.com/permissions/methods');
    // camera = 1, microphone = 7, locationWhenInUse = 5.
    // 0 denied, 1 granted, 2 restricted, 4 permanently denied.
    var statuses = <int, int>{};
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'checkPermissionStatus') {
          return statuses[call.arguments as int] ?? 0;
        }
        if (call.method == 'requestPermissions') {
          return {for (final id in call.arguments as List) id: 4};
        }
        if (call.method == 'openAppSettings') return false;
        return null;
      });
    });
    tearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    for (final (state, values) in [
      ('nothing allowed yet', <int, int>{}),
      ('one allowed, one blocked, one restricted', {1: 1, 7: 4, 5: 2}),
    ]) {
      testWidgets('fits and keeps Continue in reach, $state', (tester) async {
        if (!await _ready(tester)) return;
        statuses = values;
        final problems = <String>[];
        for (final c in _cases()) {
          _phone(tester, c);
          await tester.pumpWidget(_app(
              c, const DeviceAccess(child: Scaffold(body: Text('Portal')))));
          await tester.pumpAndSettle();
          final continues = switch (c.language) {
            AppLanguage.en => 'Continue',
            AppLanguage.fr => 'Continuer',
            AppLanguage.ar => 'متابعة',
          };
          final said = _reported(tester) ??
              _offScreen(tester, find.text(continues), c.size, 'Continue');
          if (said != null) problems.add('${_name(c)}: $said');
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
        }
        _reset(tester);
        expect(problems, isEmpty, reason: problems.join('\n'));
      });
    }
  });

  testWidgets('the call screen: the name, and End in reach, on every phone',
      (tester) async {
    if (!await _ready(tester)) return;
    final calls = StudentCalls.instance;
    final problems = <String>[];
    addTearDown(() {
      calls.invite = null;
      calls.status = '';
    });
    for (final name in [
      'Salma',
      'Mohammed Abdelrahman El Ouazzani Touhami',
      'محمد عبد الرحمان الوزاني التهامي',
      null,
    ]) {
      for (final status in ['Connecting…', 'Connected']) {
        for (final c in _cases()) {
          _phone(tester, c);
          calls.invite = {'callerName': name, 'token': 't', 'callId': 'c'};
          calls.status = status;
          await tester.pumpWidget(
              _app(c, const Scaffold(body: Text('Portal')), calls: true));
          await tester.pump();
          final said = _reported(tester) ??
              _offScreen(tester, find.byIcon(Icons.call_end), c.size, 'End') ??
              _offScreen(
                  tester,
                  find.byWidgetPredicate((w) =>
                      w is Icon &&
                      (w.icon == Icons.mic || w.icon == Icons.mic_off)),
                  c.size,
                  'Mute');
          if (said != null) {
            problems.add('${_name(c)}, caller ${name ?? 'unnamed'}: $said');
          }
          await tester.pumpWidget(const SizedBox());
        }
      }
    }
    _reset(tester);
    expect(problems.toSet(), isEmpty, reason: problems.toSet().join('\n'));
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('the Face ID question fits, ${platform.name}', (tester) async {
      if (!await _ready(tester)) return;
      final problems = <String>[];
      for (final c in _cases()) {
        for (final label in [
          'Face ID',
          'fingerprint or face recognition',
        ]) {
          _phone(tester, c);
          await tester.pumpWidget(_app(
              c,
              Builder(
                  builder: (context) => Center(
                      child: TextButton(
                          onPressed: () => showQuickSignInOffer(context,
                              label: label, dark: false, language: c.language),
                          child: const Text('Signed in')))),
              platform: platform));
          await tester.tap(find.text('Signed in'));
          await tester.pumpAndSettle();
          final dialog = platform == TargetPlatform.iOS
              ? find.byType(CupertinoAlertDialog)
              : find.byType(AlertDialog);
          final said = _reported(tester) ??
              _offScreen(tester, dialog, c.size, 'the question');
          if (said != null) problems.add('${_name(c)}, $label: $said');
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
        }
      }
      _reset(tester);
      expect(problems, isEmpty, reason: problems.join('\n'));
    });
  }
}
