// The onboarding's first step, the language (the owner, 1 Nov 2026): three
// choices, English the default, a tap is the choice, and every word after it
// is in that language, Arabic laid out right to left.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/app_language.dart';
import 'package:foorsa_student/src/onboarding/onboarding_flow.dart';
import 'package:foorsa_student/src/onboarding/onboarding_gate.dart';
import 'package:foorsa_student/src/onboarding/onboarding_page.dart';
import 'package:foorsa_student/src/onboarding/onboarding_store.dart';
import 'package:foorsa_student/src/onboarding/scene_hint.dart';
import 'package:foorsa_student/src/onboarding/scene_language.dart';

class _Phone implements BoardingPermissions {
  _Phone({this.start = const {}});
  final Map<BoardingAccess, AccessState> start;

  @override
  Future<AccessState> status(BoardingAccess access) async =>
      start[access] ?? AccessState.askable;

  @override
  Future<AccessState> request(BoardingAccess access) async =>
      AccessState.granted;
}

void _screen(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
  addTearDown(tester.view.reset);
}

/// A phone with Reduce Motion on, so the steps can be walked quickly.
Widget _phone(Widget child,
        {Size size = const Size(390, 844), double textScale = 1}) =>
    MediaQuery(
      data: MediaQueryData(
        size: size,
        padding: const EdgeInsets.only(top: 47, bottom: 34),
        disableAnimations: true,
        textScaler: TextScaler.linear(textScale),
      ),
      child: MaterialApp(home: child),
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// A language's row, by the name a screen reader hears.
Finder _row(AppLanguage language) => find.byWidgetPredicate((w) =>
    w is Semantics &&
    w.properties.attributedLabel?.string == language.nativeName &&
    w.properties.button == true);

void main() {
  testWidgets(
      'the language comes first: three names, each in itself and its own '
      'language, English the default', (tester) async {
    final semantics = tester.ensureSemantics();
    _screen(tester, const Size(390, 844));
    final key = GlobalKey<FirstLaunchOnboardingState>();
    await tester.pumpWidget(_phone(FirstLaunchOnboarding(
      key: key,
      permissions: _Phone(),
      feel: (_, [__ = 1]) {},
      onFinished: () {},
      isIOS: true,
      asksToTrack: false,
    )));
    await _settle(tester);

    expect(key.currentState!.plannedSteps.first, BoardingStep.language);
    expect(key.currentState!.currentStep, BoardingStep.language);
    expect(key.currentState!.armed, isTrue);
    expect(find.text('Choose your language.'), findsOneWidget);
    expect(find.text('Default'), findsOneWidget);
    for (final language in AppLanguage.values) {
      expect(find.text(language.nativeName), findsOneWidget);
      // Its name and what a double tap does are said in its own language,
      // and the screen reader is told which language that is.
      final row = tester.widget<Semantics>(_row(language));
      final label = row.properties.attributedLabel!;
      final hint = row.properties.attributedHint!;
      expect(hint.string, copyFor(BoardingStep.language, language).spoken);
      for (final said in [label, hint]) {
        final attribute = said.attributes.single as LocaleStringAttribute;
        expect(attribute.locale, Locale(language.code));
        expect(attribute.range, TextRange(start: 0, end: said.string.length));
      }
      // Each row is laid out in its own direction.
      final name = tester.element(find.text(language.nativeName));
      expect(Directionality.of(name), language.direction);
    }
    // English is the one already chosen.
    expect(tester.getSemantics(_row(AppLanguage.en)),
        isSemantics(isSelected: true, hasSelectedState: true, isButton: true));
    expect(tester.getSemantics(_row(AppLanguage.ar)),
        isSemantics(isSelected: false, hasSelectedState: true, isButton: true));
    await tester.pumpWidget(const SizedBox());
    semantics.dispose();
  });

  testWidgets(
      'choosing Arabic: the words change at once, right to left, and the '
      'welcome follows in Arabic', (tester) async {
    _screen(tester, const Size(390, 844));
    final key = GlobalKey<FirstLaunchOnboardingState>();
    final chosen = <AppLanguage>[];
    await tester.pumpWidget(_phone(FirstLaunchOnboarding(
      key: key,
      permissions: _Phone(),
      feel: (_, [__ = 1]) {},
      onFinished: () {},
      isIOS: true,
      asksToTrack: false,
      onLanguage: chosen.add,
    )));
    await _settle(tester);

    await tester.tap(_row(AppLanguage.ar));
    await tester.pump(const Duration(milliseconds: 60));
    // At once, before the onboarding moves on.
    expect(key.currentState!.currentStep, BoardingStep.language);
    expect(chosen, [AppLanguage.ar]);
    expect(key.currentState!.language, AppLanguage.ar);
    final headline = find.text(copyFor(BoardingStep.language, AppLanguage.ar)
        .headline);
    expect(headline, findsOneWidget);
    expect(Directionality.of(tester.element(headline)), TextDirection.rtl);
    // The English words fade out as the Arabic ones come in.
    await tester.pump(const Duration(milliseconds: 260));
    expect(find.text('Choose your language.'), findsNothing);
    expect(key.currentState!.currentStep, BoardingStep.language);

    // A beat later, the welcome, in Arabic.
    await _settle(tester);
    expect(key.currentState!.currentStep, BoardingStep.welcome);
    final welcome = copyFor(BoardingStep.welcome, AppLanguage.ar);
    expect(find.text(welcome.headline), findsOneWidget);
    expect(find.text(welcome.hint), findsOneWidget);
    expect(Directionality.of(tester.element(find.text(welcome.headline))),
        TextDirection.rtl);
    expect(find.bySemanticsLabel(welcome.action), findsOneWidget);
    // The board's own words too, its cities left as an airport prints them.
    expect(find.text('الرحلة القادمة'), findsOneWidget);
    expect(find.text('NEXT DEPARTURE'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'with motion, the pane folds into the arrow and unfolds as the welcome, '
      'in the language chosen', (tester) async {
    _screen(tester, const Size(390, 844));
    final key = GlobalKey<FirstLaunchOnboardingState>();
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(
          size: Size(390, 844), padding: EdgeInsets.only(top: 47, bottom: 34)),
      child: MaterialApp(
        home: FirstLaunchOnboarding(
          key: key,
          permissions: _Phone(),
          feel: (_, [__ = 1]) {},
          onFinished: () {},
          isIOS: false,
          asksToTrack: false,
        ),
      ),
    ));
    // The takeoff, then the languages.
    for (var i = 0; i < 300 && !key.currentState!.armed; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(key.currentState!.currentStep, BoardingStep.language);
    await tester.tap(_row(AppLanguage.fr));
    for (var t = 0; t < 2600; t += 16) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(tester.takeException(), isNull);
    expect(key.currentState!.currentStep, BoardingStep.welcome);
    expect(key.currentState!.armed, isTrue);
    expect(
        find.text(copyFor(BoardingStep.welcome, AppLanguage.fr).headline),
        findsOneWidget);
    // Back from the welcome goes back to the languages.
    key.currentState!.back();
    for (var t = 0; t < 1400; t += 16) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(key.currentState!.currentStep, BoardingStep.language);
    expect(find.text('Choisissez votre langue.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a second tap while the words change does not choose again',
      (tester) async {
    _screen(tester, const Size(390, 844));
    final key = GlobalKey<FirstLaunchOnboardingState>();
    final chosen = <AppLanguage>[];
    await tester.pumpWidget(_phone(FirstLaunchOnboarding(
      key: key,
      permissions: _Phone(),
      feel: (_, [__ = 1]) {},
      onFinished: () {},
      isIOS: false,
      asksToTrack: false,
      onLanguage: chosen.add,
    )));
    await _settle(tester);
    await tester.tap(_row(AppLanguage.fr));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(_row(AppLanguage.ar), warnIfMissed: false);
    await _settle(tester);
    expect(chosen, [AppLanguage.fr]);
    expect(key.currentState!.language, AppLanguage.fr);
    expect(key.currentState!.currentStep, BoardingStep.welcome);
    await tester.pumpWidget(const SizedBox());
  });

  for (final language in [AppLanguage.fr, AppLanguage.ar]) {
    for (final (name, size, scale) in [
      ('the first iPhone SE', const Size(320, 568), 1.0),
      ('an iPhone SE with large text', const Size(375, 667), 1.3),
      ('a large phone', const Size(430, 932), 1.0),
    ]) {
      testWidgets('every step speaks ${language.name} and fits $name',
          (tester) async {
        _screen(tester, size);
        final key = GlobalKey<FirstLaunchOnboardingState>();
        await tester.pumpWidget(_phone(
          FirstLaunchOnboarding(
            key: key,
            permissions: _Phone(),
            feel: (_, [__ = 1]) {},
            onFinished: () {},
            isIOS: true,
            asksToTrack: true,
            language: language,
          ),
          size: size,
          textScale: scale,
        ));
        await _settle(tester);
        for (final step in key.currentState!.plannedSteps) {
          key.currentState!.debugJumpTo(step);
          await _settle(tester);
          expect(tester.takeException(), isNull,
              reason: '${step.name} on $name');
          final copy = copyFor(step, language);
          expect(find.text(copy.hint), findsOneWidget, reason: step.name);
          expect(find.text(copy.headline), findsOneWidget, reason: step.name);
          expect(find.text(copyFor(step).headline), findsNothing,
              reason: '${step.name}: no English left');
          expect(
              Directionality.of(tester.element(find.text(copy.headline))),
              language.direction,
              reason: step.name);
        }
        // The pass is printed in the language, and keeps its way round.
        final title = find.text(language == AppLanguage.fr
            ? 'CARTE D’EMBARQUEMENT'
            : 'بطاقة الصعود');
        expect(title, findsOneWidget);
        expect(Directionality.of(tester.element(title)), TextDirection.ltr);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  testWidgets(
      'the step counter and the guide speak the language, Arabic without '
      'spacing between its letters', (tester) async {
    _screen(tester, const Size(390, 844));
    final key = GlobalKey<FirstLaunchOnboardingState>();
    await tester.pumpWidget(_phone(FirstLaunchOnboarding(
      key: key,
      permissions: _Phone(),
      feel: (_, [__ = 1]) {},
      onFinished: () {},
      isIOS: false,
      asksToTrack: false,
      language: AppLanguage.ar,
    )));
    await _settle(tester);
    key.currentState!.debugJumpTo(BoardingStep.notifications);
    await _settle(tester);
    final steps = key.currentState!.plannedSteps;
    expect(find.text('الخطوة 1 من ${steps.length - 2}'), findsOneWidget);
    final hint = tester.widget<Text>(
        find.text(copyFor(BoardingStep.notifications, AppLanguage.ar).hint));
    expect(hint.style!.letterSpacing, 0);
    final headline = tester.widget<Text>(find.text(
        copyFor(BoardingStep.notifications, AppLanguage.ar).headline));
    expect(headline.style!.letterSpacing, 0);
    expect(find.text('لديك رسالة جديدة من مستشارك.'), findsWidgets);
    expect(tester.getRect(find.byType(SceneGuide).last).isEmpty, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'the languages\' pane is the object the transitions fold, and stands '
      'where they leave it', (tester) async {
    for (final stage in const [Size(342, 430), Size(272, 200)]) {
      final pane = languagePaneRect(stage);
      expect(pane.center, stage.center(Offset.zero));
      expect(pane.width, lessThanOrEqualTo(stage.width));
      expect(pane.height, lessThanOrEqualTo(stage.height));
    }
    expect(languagePaneRect(const Size(342, 430)).height, 3 * 58);
  });

  group('the gate', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('gate_language_'));
    tearDown(() => dir.deleteSync(recursive: true));

    testWidgets(
        'keeps the choice, speaks it, and hands it to the portal behind the '
        'onboarding', (tester) async {
      _screen(tester, const Size(390, 844));
      final shell = ShellLanguage(
          store: AppLanguageStore(directory: () async => dir));
      await tester.pumpWidget(_phone(ListenableBuilder(
        listenable: shell,
        builder: (context, _) => AppLanguageScope(
          language: shell.current,
          child: FirstLaunchGate(
            show: true,
            store: OnboardingStore(
                directory: () async => dir,
                webViewData: () async => const []),
            permissions: _Phone(start: {
              for (final a in BoardingAccess.values) a: AccessState.granted
            }),
            language: shell,
            child: const Text('Portal'),
          ),
        ),
      )));
      await _settle(tester);
      await tester.tap(_row(AppLanguage.fr));
      await _settle(tester);
      expect(shell.current, AppLanguage.fr);
      expect(shell.handOver, isNotNull,
          reason: 'until the portal says it runs in French');
      expect(find.text(copyFor(BoardingStep.welcome, AppLanguage.fr).headline),
          findsOneWidget);
      // Kept on the phone (a real file: written on the real clock).
      StoredLanguage? kept;
      for (var i = 0; i < 40 && kept == null; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        kept = await tester.runAsync<StoredLanguage?>(
            () => AppLanguageStore(directory: () async => dir).read());
      }
      expect(kept?.language, AppLanguage.fr);
      expect(kept?.handOver, shell.handOver);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('opens in the language already kept on the phone',
        (tester) async {
      _screen(tester, const Size(390, 844));
      await tester.pumpWidget(_phone(AppLanguageScope(
        language: AppLanguage.ar,
        child: FirstLaunchGate(
          show: true,
          store: OnboardingStore(
              directory: () async => dir, webViewData: () async => const []),
          permissions: _Phone(),
          child: const Text('Portal'),
        ),
      )));
      await _settle(tester);
      expect(find.text('اختر لغتك.'), findsOneWidget);
      expect(tester.getSemantics(_row(AppLanguage.ar)),
          isSemantics(isSelected: true, hasSelectedState: true, isButton: true));
      await tester.pumpWidget(const SizedBox());
    });
  });
}
