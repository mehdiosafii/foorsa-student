import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/app_language.dart';
import 'package:foorsa_student/src/onboarding/onboarding_flow.dart';
import 'package:foorsa_student/src/onboarding/onboarding_page.dart';

/// The first-launch onboarding, every step of it, on every phone it can
/// open on: small, large, on its side (a student may well hold the phone
/// that way when the app first opens), a tablet, with the phone's text set
/// larger, in the three languages.
///
/// The owner's stress test, 12 Nov 2026. Its scenes had been placed on an
/// upright phone, the smallest and with text a third larger; this walks the
/// rest. A step fails when Flutter reports that something does not fit, or
/// when what the step tells the student to do is not wholly on the screen
/// from side to side.

const _phones = <(String, Size, FakeViewPadding)>[
  ('the first iPhone SE', Size(320, 568), FakeViewPadding(top: 20)),
  ('a small Android', Size(360, 640), FakeViewPadding(top: 24)),
  ('an iPhone 14', Size(390, 844), FakeViewPadding(top: 47, bottom: 34)),
  ('a large Android', Size(412, 915), FakeViewPadding(top: 32, bottom: 16)),
  ('the first iPhone SE on its side', Size(568, 320), FakeViewPadding.zero),
  (
    'an iPhone 14 on its side',
    Size(844, 390),
    FakeViewPadding(left: 47, right: 47, bottom: 21)
  ),
  ('a tablet', Size(768, 1024), FakeViewPadding(top: 24, bottom: 20)),
];
const _scales = [1.0, 1.3, 2.0];

class _Phone implements BoardingPermissions {
  @override
  Future<AccessState> status(BoardingAccess access) async =>
      AccessState.askable;
  @override
  Future<AccessState> request(BoardingAccess access) async =>
      AccessState.granted;
}

/// The fonts a phone draws with (see native_layout_sweep_test.dart).
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
  final naskh = File(
      '$root/engine/src/flutter/txt/third_party/fonts/NotoNaskhArabic-Regular.ttf');
  if (!naskh.existsSync()) return (latin: true, arabic: false);
  await (FontLoader('NotoNaskhArabic')..addFont(bytes(naskh.path))).load();
  return (latin: true, arabic: true);
}

void main() {
  for (final language in AppLanguage.values) {
    testWidgets('every step fits on every phone, in ${language.code}',
        (tester) async {
      final fonts = await tester.runAsync(_loadFonts);
      if (fonts == null || !fonts.latin) {
        markTestSkipped('The Flutter SDK\'s fonts are not here.');
        return;
      }
      if (language == AppLanguage.ar && !fonts.arabic) {
        markTestSkipped('No Arabic font in this Flutter SDK.');
        return;
      }
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      // Reduce Motion, so each step is at rest at once: where things are is
      // the same, and the walk takes seconds.
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      final problems = <String>[];
      var steps = 0;
      var hints = 0;
      for (final (phone, size, padding) in _phones) {
        for (final scale in _scales) {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          tester.view.padding = padding;
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          final where = '$phone (${size.width.toInt()}x'
              '${size.height.toInt()}), text x$scale';
          final key = GlobalKey<FirstLaunchOnboardingState>();
          await tester.pumpWidget(MaterialApp(
            theme: ThemeData(
                useMaterial3: true,
                fontFamily: 'Roboto',
                fontFamilyFallback: const ['NotoNaskhArabic']),
            home: FirstLaunchOnboarding(
              key: key,
              permissions: _Phone(),
              feel: (_, [__ = 1]) {},
              onFinished: () {},
              isIOS: true,
              // Every scene the onboarding has, the shield's too.
              asksToTrack: true,
              language: language,
            ),
          ));
          await tester.pump();
          var said = tester.takeException();
          if (said != null) {
            problems.add('$where, as it opens: '
                '${said.toString().split('\n').first}');
          }
          for (final step in key.currentState!.plannedSteps) {
            key.currentState!.debugJumpTo(step);
            for (var i = 0; i < 14; i++) {
              await tester.pump(const Duration(milliseconds: 100));
            }
            steps++;
            said = tester.takeException();
            if (said != null) {
              problems.add('$where, ${step.name}: '
                  '${said.toString().split('\n').first}');
              continue;
            }
            // What the step tells the student to do.
            final hint = find.text(copyFor(step, language).hint);
            if (hint.evaluate().isEmpty) continue;
            hints++;
            final words = tester.getRect(hint.first);
            if (words.left < -0.5 || words.right > size.width + 0.5) {
              problems.add('$where, ${step.name}: what to do runs off the '
                  'side (${words.left.round()} to ${words.right.round()})');
            }
          }
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 1));
          tester.takeException();
        }
      }
      expect(problems, isEmpty, reason: problems.join('\n'));
      // The walk really took place: every phone and text size, every step,
      // and the words of most steps found where they are drawn.
      expect(steps, greaterThanOrEqualTo(_phones.length * _scales.length * 6));
      expect(hints, greaterThan(steps ~/ 2));
    });
  }
}
