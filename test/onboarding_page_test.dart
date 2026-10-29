import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/onboarding/onboarding_flow.dart';
import 'package:foorsa_student/src/onboarding/onboarding_gate.dart';
import 'package:foorsa_student/src/onboarding/onboarding_page.dart';
import 'package:foorsa_student/src/onboarding/onboarding_store.dart';

class _Phone implements BoardingPermissions {
  _Phone({this.answers = const {}, this.start = const {}});
  final Map<BoardingAccess, AccessState> answers;
  final Map<BoardingAccess, AccessState> start;
  final asked = <BoardingAccess>[];

  @override
  Future<AccessState> status(BoardingAccess access) async =>
      start[access] ?? AccessState.askable;

  @override
  Future<AccessState> request(BoardingAccess access) async {
    asked.add(access);
    return answers[access] ?? AccessState.granted;
  }
}

/// A phone with Reduce Motion on: every scene stands still, so the steps
/// can be walked without waiting out animations.
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

void _screen(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _press(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).last);
  await _settle(tester);
}

void main() {
  testWidgets(
      'the onboarding walks a new phone through every access, one Continue each',
      (tester) async {
    final semantics = tester.ensureSemantics();
    _screen(tester, const Size(390, 844));
    final phone =
        _Phone(answers: {BoardingAccess.microphone: AccessState.denied});
    final key = GlobalKey<FirstLaunchOnboardingState>();
    var finished = false;
    await tester.pumpWidget(_phone(FirstLaunchOnboarding(
      key: key,
      permissions: phone,
      feel: (_, [__ = 1]) {},
      onFinished: () => finished = true,
      isIOS: true,
      asksToTrack: false,
    )));
    await _settle(tester);

    expect(find.text('Your journey to China starts here.'), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);
    await _press(tester, 'Get started');

    final expected = [
      (
        BoardingStep.notifications,
        BoardingAccess.notifications,
        'Never miss a moment.'
      ),
      (BoardingStep.camera, BoardingAccess.camera, 'Scan papers in seconds.'),
      (
        BoardingStep.microphone,
        BoardingAccess.microphone,
        'Talk to your adviser.'
      ),
      (
        BoardingStep.location,
        BoardingAccess.location,
        'Feel at home in China.'
      ),
    ];
    for (final (step, access, headline) in expected) {
      expect(key.currentState!.currentStep, step);
      expect(find.text(headline), findsOneWidget);
      // Review: the only way on is Continue, which shows the system prompt.
      expect(find.text('Continue'), findsOneWidget);
      for (final exit in ['Not now', 'Skip', 'Later', 'Allow']) {
        expect(find.text(exit), findsNothing, reason: '$exit on ${step.name}');
      }
      final before = phone.asked.length;
      await tester.tap(find.text('Continue').last);
      await tester.pump(const Duration(milliseconds: 100));
      expect(phone.asked.length, before + 1);
      expect(phone.asked.last, access);
      // A yes shows on the button for a moment; a no simply moves on.
      expect(find.bySemanticsLabel('Continue, turned on'),
          access == BoardingAccess.microphone ? findsNothing : findsOneWidget);
      // Granted or not, the next step follows by itself.
      await tester.pump(const Duration(milliseconds: 1200));
      await _settle(tester);
    }

    expect(key.currentState!.currentStep, BoardingStep.boarding);
    expect(find.text('You’re ready to board.'), findsOneWidget);
    expect(find.text('FOORSA STUDENT'), findsOneWidget);
    expect(
        find.bySemanticsLabel(RegExp('^Your boarding pass')), findsOneWidget);

    await _press(tester, 'Board');
    await tester.pump(const Duration(milliseconds: 400));
    expect(finished, isTrue);
    await tester.pumpWidget(const SizedBox());
    semantics.dispose();
  });

  testWidgets(
      'a phone that has answered everything goes from the welcome to the pass',
      (tester) async {
    _screen(tester, const Size(390, 844));
    final phone = _Phone(
        start: {for (final a in BoardingAccess.values) a: AccessState.granted});
    final key = GlobalKey<FirstLaunchOnboardingState>();
    await tester.pumpWidget(_phone(FirstLaunchOnboarding(
      key: key,
      permissions: phone,
      feel: (_, [__ = 1]) {},
      onFinished: () {},
      isIOS: true,
      asksToTrack: true,
    )));
    await _settle(tester);
    await _press(tester, 'Get started');
    expect(key.currentState!.currentStep, BoardingStep.boarding);
    expect(phone.asked, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('back goes one step back, and Continue there does not ask twice',
      (tester) async {
    _screen(tester, const Size(390, 844));
    final phone = _Phone();
    final key = GlobalKey<FirstLaunchOnboardingState>();
    await tester.pumpWidget(_phone(FirstLaunchOnboarding(
      key: key,
      permissions: phone,
      feel: (_, [__ = 1]) {},
      onFinished: () {},
      isIOS: false,
      asksToTrack: false,
    )));
    await _settle(tester);
    await _press(tester, 'Get started');
    await _press(tester, 'Continue');
    await tester.pump(const Duration(milliseconds: 1200));
    await _settle(tester);
    expect(key.currentState!.currentStep, BoardingStep.camera);

    key.currentState!.back();
    await _settle(tester);
    expect(key.currentState!.currentStep, BoardingStep.notifications);
    await _press(tester, 'Continue');
    expect(phone.asked, [BoardingAccess.notifications]);
    expect(key.currentState!.currentStep, BoardingStep.camera);
    await tester.pumpWidget(const SizedBox());
  });

  for (final (name, size, scale) in [
    ('the first iPhone SE', const Size(320, 568), 1.0),
    ('an iPhone SE', const Size(375, 667), 1.0),
    ('a large phone with large text', const Size(430, 932), 1.3),
    ('an iPhone SE with large text', const Size(375, 667), 1.3),
  ]) {
    testWidgets('every step fits $name', (tester) async {
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
        ),
        size: size,
        textScale: scale,
      ));
      await _settle(tester);
      for (final step in key.currentState!.plannedSteps) {
        key.currentState!.debugJumpTo(step);
        await _settle(tester);
        expect(tester.takeException(), isNull, reason: '${step.name} on $name');
      }
      await tester.pumpWidget(const SizedBox());
    });
  }

  group('the gate', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('gate_'));
    tearDown(() => dir.deleteSync(recursive: true));

    OnboardingStore store() => OnboardingStore(
        directory: () async => dir, webViewData: () async => const []);

    testWidgets('an update shows the portal straight away', (tester) async {
      _screen(tester, const Size(390, 844));
      await tester.pumpWidget(_phone(FirstLaunchGate(
        show: false,
        store: store(),
        permissions: _Phone(),
        child: const Text('Portal'),
      )));
      expect(find.text('Portal'), findsOneWidget);
      expect(find.byType(FirstLaunchOnboarding), findsNothing);
    });

    testWidgets(
        'a first launch boards over the loading portal, then leaves it for good',
        (tester) async {
      _screen(tester, const Size(390, 844));
      var active = <bool>[];
      await tester.pumpWidget(_phone(FirstLaunchGate(
        show: true,
        store: store(),
        permissions: _Phone(start: {
          for (final a in BoardingAccess.values) a: AccessState.granted
        }),
        child: Builder(builder: (context) {
          active.add(OnboardingScope.activeOf(context));
          return const Text('Portal');
        }),
      )));
      await _settle(tester);
      // The portal is there underneath the whole time, loading.
      expect(find.text('Portal', skipOffstage: false), findsOneWidget);
      expect(find.byType(FirstLaunchOnboarding), findsOneWidget);
      expect(active.last, isTrue);

      await _press(tester, 'Get started');
      await _press(tester, 'Board');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.byType(FirstLaunchOnboarding), findsNothing);
      expect(active.last, isFalse);
      // The record is a real file: the write runs on the real clock, its
      // steps in between frames.
      var record = OnboardingRecord.none;
      for (var i = 0; i < 40 && record != OnboardingRecord.done; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
        record = (await tester.runAsync(() => store().read()))!;
      }
      expect(record, OnboardingRecord.done);
      // The tear's touch (two taps 60 ms apart) finishes.
      await tester.pump(const Duration(milliseconds: 200));
    });
  });
}
