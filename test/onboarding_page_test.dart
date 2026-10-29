import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/onboarding/onboarding_flow.dart';
import 'package:foorsa_student/src/onboarding/onboarding_gate.dart';
import 'package:foorsa_student/src/onboarding/onboarding_page.dart';
import 'package:foorsa_student/src/onboarding/onboarding_sound.dart';
import 'package:foorsa_student/src/onboarding/onboarding_store.dart';
import 'package:foorsa_student/src/onboarding/scene_location.dart';
import 'package:foorsa_student/src/onboarding/scene_scan.dart';
import 'package:foorsa_student/src/onboarding/stage_forms.dart';

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

/// The same phone with motion on.
Widget _moving(Widget child) => MediaQuery(
      data: const MediaQueryData(
          size: Size(390, 844), padding: EdgeInsets.only(top: 47, bottom: 34)),
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

/// The object on the screen that is its control, by what a screen reader
/// calls it.
Finder _object(String label) => find
    .byWidgetPredicate((w) =>
        w is Semantics &&
        w.properties.label == label &&
        w.properties.button == true)
    .last;

Future<void> _act(WidgetTester tester, String label) async {
  await tester.tap(_object(label));
  await _settle(tester);
}

class _Heard extends BoardingSounds {
  final cues = <String>[];
  var bed = false;
  @override
  void play(String cue) => cues.add(cue);
  @override
  void stop(String cue) => cues.add('stop $cue');
  @override
  void startBed() => bed = true;
  @override
  void endBed() => bed = false;
}

/// Frames, at the phone's rate, for animations that are not stilled.
Future<void> _frames(WidgetTester tester, Duration length) async {
  for (var t = Duration.zero;
      t < length;
      t += const Duration(milliseconds: 16)) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  testWidgets(
      'the onboarding walks a new phone through every access, one gesture on '
      'each object', (tester) async {
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
    // No button: the arrow is thrown, and the screen says so under it.
    expect(find.text('Swipe up to begin'), findsOneWidget);
    expect(find.byType(ElevatedButton), findsNothing);
    expect(find.bySemanticsLabel('Get started'), findsOneWidget);
    await _act(tester, 'Get started');

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
      expect(key.currentState!.armed, isTrue);
      expect(find.text(headline), findsOneWidget);
      expect(find.text(copyFor(step).hint), findsOneWidget);
      // Review: the only way on is the object, named Continue, which shows
      // the system prompt. Nothing on screen says Allow, or offers a way out.
      expect(find.bySemanticsLabel('Continue'), findsOneWidget);
      for (final exit in ['Not now', 'Skip', 'Later', 'Allow', 'Continue']) {
        expect(find.text(exit), findsNothing, reason: '$exit on ${step.name}');
      }
      final before = phone.asked.length;
      await tester.tap(_object('Continue'));
      await tester.pump(const Duration(milliseconds: 50));
      // The prompt comes the moment the object is touched.
      expect(phone.asked.length, before + 1);
      expect(phone.asked.last, access);
      // Granted or not, the next step follows by itself.
      await tester.pump(const Duration(milliseconds: 1200));
      await _settle(tester);
    }

    expect(key.currentState!.currentStep, BoardingStep.boarding);
    expect(find.text('You’re ready to board.'), findsOneWidget);
    expect(find.text('FOORSA STUDENT'), findsOneWidget);
    expect(find.text('PULL TO BOARD'), findsOneWidget);
    expect(
        find.bySemanticsLabel(RegExp('^Your boarding pass')), findsOneWidget);

    await _act(tester, 'Board');
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
    await _act(tester, 'Get started');
    expect(key.currentState!.currentStep, BoardingStep.boarding);
    expect(phone.asked, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'back goes one step back, and the object there does not ask twice',
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
    await _act(tester, 'Get started');
    await _act(tester, 'Continue');
    await tester.pump(const Duration(milliseconds: 1200));
    await _settle(tester);
    expect(key.currentState!.currentStep, BoardingStep.camera);

    key.currentState!.back();
    await _settle(tester);
    expect(key.currentState!.currentStep, BoardingStep.notifications);
    await _act(tester, 'Continue');
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
        if (step != BoardingStep.boarding) {
          expect(find.text(copyFor(step).hint), findsOneWidget,
              reason: step.name);
        }
      }
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('each step sounds a note higher, and a yes has its own chime',
      (tester) async {
    _screen(tester, const Size(390, 844));
    final heard = _Heard();
    await tester.pumpWidget(_phone(FirstLaunchOnboarding(
      permissions: _Phone(answers: {BoardingAccess.camera: AccessState.denied}),
      feel: (_, [__ = 1]) {},
      onFinished: () {},
      isIOS: false,
      asksToTrack: false,
      sounds: heard,
    )));
    await _settle(tester);
    await _act(tester, 'Get started');
    for (var i = 0; i < 4; i++) {
      await _act(tester, 'Continue');
      await tester.pump(const Duration(milliseconds: 1200));
      await _settle(tester);
    }
    await tester.tap(_object('Board'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(heard.cues.where((c) => c.startsWith('step-')),
        ['step-1', 'step-2', 'step-3', 'step-4', 'step-5']);
    // Three yeses (the camera was refused), one chime each.
    expect(heard.cues.where((c) => c == 'granted'), hasLength(3));
    // The scanner took the page, and every press was heard.
    expect(heard.cues.where((c) => c == 'shutter'), hasLength(1));
    expect(heard.cues.where((c) => c == 'tap').length, greaterThanOrEqualTo(5));
    expect(heard.cues.contains('flap'), isTrue);
    expect(heard.cues.sublist(heard.cues.length - 2), ['tear', 'board']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'tearing the stub lands the arrow on the sign-in\'s, then lets the '
      'sign-in show', (tester) async {
    _screen(tester, const Size(390, 844));
    final key = GlobalKey<FirstLaunchOnboardingState>();
    final heard = _Heard();
    var asked = 0;
    var boarded = 0;
    var finished = false;
    await tester.pumpWidget(_moving(FirstLaunchOnboarding(
      key: key,
      permissions: _Phone(start: {
        for (final a in BoardingAccess.values) a: AccessState.granted
      }),
      feel: (_, [__ = 1]) {},
      onFinished: () => finished = true,
      isIOS: true,
      asksToTrack: false,
      sounds: heard,
      findMark: () async {
        asked++;
        return const Rect.fromLTWH(163, 127, 64, 64);
      },
      onBoarded: () => boarded++,
    )));
    await tester.pump();
    key.currentState!.debugJumpTo(BoardingStep.boarding);
    await _frames(tester, const Duration(milliseconds: 1500));
    expect(key.currentState!.armed, isTrue);

    // Pulled down by hand, past the point where the paper gives.
    final stub = tester.getCenter(_object('Board'));
    await tester.dragFrom(stub, const Offset(0, 140));
    for (var i = 0; i < 320 && boarded == 0; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    // As the sign-in shows, the arrow is on the sign-in's own.
    expect(boarded, 1);
    expect((key.currentState!.pilotAt! - const Offset(195, 159)).distance,
        lessThan(16));
    for (var i = 0; i < 320 && !finished; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(asked, 1);
    expect(boarded, 1);
    expect(finished, isTrue);
    expect(heard.cues.where((c) => c == 'tear'), hasLength(1));
    expect(heard.cues, containsAllInOrder(['tear', 'dock', 'board']));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets(
      'the welcome\'s arrow is thrown up into the board, and only a real '
      'throw sends it', (tester) async {
    _screen(tester, const Size(390, 844));
    final heard = _Heard();
    final key = GlobalKey<FirstLaunchOnboardingState>();
    await tester.pumpWidget(_moving(FirstLaunchOnboarding(
      key: key,
      permissions: _Phone(),
      feel: (_, [__ = 1]) {},
      onFinished: () {},
      isIOS: false,
      asksToTrack: false,
      sounds: heard,
    )));
    await tester.pump();
    key.currentState!.debugJumpTo(BoardingStep.welcome);
    await _frames(tester, const Duration(milliseconds: 1000));
    expect(key.currentState!.armed, isTrue);
    expect(heard.bed, isTrue);

    // A small, slow push up: it springs back and waits.
    final arrow = tester.getCenter(_object('Get started'));
    final gesture = await tester.startGesture(arrow);
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(0, -3));
      await tester.pump(const Duration(milliseconds: 40));
    }
    await tester.pump(const Duration(milliseconds: 400));
    await gesture.up();
    await _frames(tester, const Duration(milliseconds: 600));
    expect(key.currentState!.currentStep, BoardingStep.welcome);
    expect(heard.cues, isNot(contains('swoop')));

    // Thrown: it flies into the board, which becomes the next picture.
    await tester.fling(_object('Get started'), const Offset(0, -160), 1400);
    await tester.pump();
    expect(key.currentState!.currentStep, BoardingStep.notifications);
    expect(heard.cues, contains('swoop'));
    await _frames(tester, const Duration(milliseconds: 1500));
    expect(key.currentState!.armed, isTrue);
    expect(heard.cues, containsAllInOrder(['swoop', 'dock', 'step-1']));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets(
      'the passport page put back in the frame is taken, and the phone asks '
      'for the camera then', (tester) async {
    _screen(tester, const Size(390, 844));
    final phone = _Phone();
    final heard = _Heard();
    final key = GlobalKey<FirstLaunchOnboardingState>();
    await tester.pumpWidget(_moving(FirstLaunchOnboarding(
      key: key,
      permissions: phone,
      feel: (_, [__ = 1]) {},
      onFinished: () {},
      isIOS: false,
      asksToTrack: false,
      sounds: heard,
    )));
    await tester.pump();
    key.currentState!.debugJumpTo(BoardingStep.camera);
    await _frames(tester, const Duration(milliseconds: 2400));
    expect(key.currentState!.armed, isTrue);

    final stage = tester.getRect(find.byType(ScanScene));
    final width = pageWidth(stage.width);
    final rest = Offset(width * 0.13, width * 0.704 * 0.27);
    // Moved about in the hand, away from the frame, and let go: it goes
    // back to the hand and nothing is asked.
    final away = await tester.startGesture(stage.center + rest);
    for (var i = 0; i < 6; i++) {
      await away.moveBy(const Offset(3, 4));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 300));
    await away.up();
    await _frames(tester, const Duration(milliseconds: 700));
    expect(phone.asked, isEmpty);

    // Into the frame: the scanner takes it and the phone asks.
    final gesture = await tester.startGesture(stage.center + rest);
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(-rest / 12);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await _frames(tester, const Duration(milliseconds: 700));
    expect(phone.asked, [BoardingAccess.camera]);
    expect(heard.cues, containsAllInOrder(['shutter', 'granted']));
    await _frames(tester, const Duration(milliseconds: 2200));
    expect(key.currentState!.currentStep, BoardingStep.microphone);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets(
      'the map\'s arrow finds the student, then flies on into the next '
      'picture', (tester) async {
    _screen(tester, const Size(390, 844));
    final phone = _Phone();
    final heard = _Heard();
    final key = GlobalKey<FirstLaunchOnboardingState>();
    await tester.pumpWidget(_moving(FirstLaunchOnboarding(
      key: key,
      permissions: phone,
      feel: (_, [__ = 1]) {},
      onFinished: () {},
      isIOS: false,
      asksToTrack: false,
      sounds: heard,
    )));
    await tester.pump();
    key.currentState!.debugJumpTo(BoardingStep.location);
    await _frames(tester, const Duration(milliseconds: 1500));
    expect(key.currentState!.armed, isTrue);

    // A tap on the map is not the arrow: nothing is asked.
    await tester.tapAt(tester.getRect(find.byType(LocationScene)).center);
    await _frames(tester, const Duration(milliseconds: 300));
    expect(phone.asked, isEmpty);

    await tester.tap(_object('Continue'));
    await tester.pump();
    expect(phone.asked, [BoardingAccess.location]);
    // The dot drops in while the arrow waits in its button, then it flies.
    await _frames(tester, const Duration(milliseconds: 600));
    expect(key.currentState!.currentStep, BoardingStep.location);
    expect(heard.cues.last, 'granted');
    await _frames(tester, const Duration(milliseconds: 500));
    expect(key.currentState!.currentStep, BoardingStep.boarding);
    expect(heard.cues, containsAllInOrder(['granted', 'swoop']));
    await _frames(tester, const Duration(milliseconds: 1500));
    expect(heard.cues, containsAllInOrder(['swoop', 'dock', 'step-5']));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

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

      await _act(tester, 'Get started');
      await _act(tester, 'Board');
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
