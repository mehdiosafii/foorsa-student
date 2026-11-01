// What each onboarding scene says and shows the student to do
// (scene_hint.dart, gesture_demo.dart): the words, the touch that does the
// gesture on the object, and the still chevron with Reduce Motion.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/app_language.dart';
import 'package:foorsa_student/src/onboarding/boarding_pass.dart';
import 'package:foorsa_student/src/onboarding/boarding_style.dart';
import 'package:foorsa_student/src/onboarding/gesture_demo.dart';
import 'package:foorsa_student/src/onboarding/onboarding_flow.dart';
import 'package:foorsa_student/src/onboarding/onboarding_page.dart';
import 'package:foorsa_student/src/onboarding/scene_hint.dart';
import 'package:foorsa_student/src/onboarding/scene_language.dart';
import 'package:foorsa_student/src/onboarding/scene_location.dart';
import 'package:foorsa_student/src/onboarding/scene_scan.dart';
import 'package:foorsa_student/src/onboarding/scene_welcome.dart';
import 'package:foorsa_student/src/onboarding/stage_forms.dart';

class _Phone implements BoardingPermissions {
  final asked = <BoardingAccess>[];

  @override
  Future<AccessState> status(BoardingAccess access) async =>
      AccessState.askable;

  @override
  Future<AccessState> request(BoardingAccess access) async {
    asked.add(access);
    return AccessState.granted;
  }
}

void _screen(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
  addTearDown(tester.view.reset);
}

/// The onboarding on a phone, moving, or with Reduce Motion ([still]).
Widget _onboarding(
  GlobalKey<FirstLaunchOnboardingState> key,
  BoardingPermissions phone, {
  bool still = false,
  Size size = const Size(390, 844),
  double textScale = 1,
  VoidCallback? onBoarded,
}) =>
    MediaQuery(
      data: MediaQueryData(
        size: size,
        padding: const EdgeInsets.only(top: 47, bottom: 34),
        disableAnimations: still,
        textScaler: TextScaler.linear(textScale),
      ),
      child: MaterialApp(
        home: FirstLaunchOnboarding(
          key: key,
          permissions: phone,
          feel: (_, [__ = 1]) {},
          onFinished: () {},
          onBoarded: onBoarded,
          isIOS: true,
          // Every scene the onboarding has, the shield's too.
          asksToTrack: true,
        ),
      ),
    );

Future<void> _frames(WidgetTester tester, Duration length) async {
  for (var t = Duration.zero;
      t < length;
      t += const Duration(milliseconds: 16)) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// On [step], its object ready for the student.
Future<void> _goTo(WidgetTester tester,
    GlobalKey<FirstLaunchOnboardingState> key, BoardingStep step) async {
  await tester.pump();
  key.currentState!.debugJumpTo(step);
  await _frames(tester, const Duration(milliseconds: 1300));
  expect(key.currentState!.armed, isTrue, reason: step.name);
}

/// The guide of the step on the screen.
Finder get _guideFinder => find.byType(SceneGuide).last;
SceneGuideState _guide(WidgetTester tester) =>
    tester.state<SceneGuideState>(_guideFinder);

/// A point of the guide's scene, on the screen.
Offset _onScreen(WidgetTester tester, Offset point) =>
    tester.renderObject<RenderBox>(_guideFinder).localToGlobal(point);

/// Pumps until the guide's touch is on the screen; how long that took.
Future<Duration?> _untilShown(WidgetTester tester,
    {Duration within = const Duration(seconds: 4)}) async {
  for (var t = Duration.zero;
      t < within;
      t += const Duration(milliseconds: 16)) {
    if (_guide(tester).showing) return t;
    await tester.pump(const Duration(milliseconds: 16));
  }
  return _guide(tester).showing ? within : null;
}

/// What a screen reader calls [step]'s object: its action, or, on the
/// languages' pane, the first row's name (English, the default).
String _objectName(BoardingStep step) =>
    step == BoardingStep.language ? 'English' : copyFor(step).action;

Finder _objectNamed(String name) => find
    .byWidgetPredicate((w) =>
        w is Semantics &&
        (w.properties.label ?? w.properties.attributedLabel?.string) ==
            name &&
        w.properties.button == true)
    .last;

/// WCAG's contrast ratio of [a] over [b].
double _contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

void main() {
  group('the touch', () {
    final mic = RRect.fromRectAndRadius(
        Rect.fromCircle(center: const Offset(200, 300), radius: 44),
        const Radius.circular(44));

    test(
        'a tap comes down on the object, presses it, rings out from its edge '
        'and goes', () {
      final demo = GestureDemo.tap(const Offset(209, 311), mic);
      expect(demoAt(demo, -0.01).presence, 0);
      final arriving = demoAt(demo, demoDown / 2);
      expect(arriving.presence, inExclusiveRange(0, 1));
      expect(arriving.scale, greaterThan(1), reason: 'a fingertip nearing');
      final pressed = demoAt(demo, demoPressed + 0.04);
      expect(pressed.presence, 1);
      expect(pressed.press, closeTo(1, 1e-9));
      expect(pressed.at, const Offset(209, 311));
      expect(mic.contains(pressed.at), isTrue);
      expect(pressed.ring, inInclusiveRange(0, 1));
      // The ring starts as the touch presses.
      expect(demoAt(demo, demoRingFrom - 0.01).ring, lessThan(0));
      expect(demoAt(demo, demoEnds(demo)).presence, 0);
      expect(demoAt(demo, demoEnds(demo)).ring, lessThan(0));
    });

    test(
        'a swipe, a drag and a pull start on the object and go the '
        'gesture\'s way, their trail behind them', () {
      for (final gesture in [
        DemoGesture.swipe,
        DemoGesture.drag,
        DemoGesture.pull
      ]) {
        final demo = GestureDemo.move(
            gesture, const Offset(100, 300), const Offset(100, 190));
        // It comes down where the finger goes down, and presses there.
        expect(demoAt(demo, demoDown).at, const Offset(100, 300));
        expect(demoAt(demo, demoPressed).press, closeTo(1, 1e-9));
        var along = -1.0;
        for (var t = 0.0; t < demoEnds(demo); t += 0.01) {
          final pose = demoAt(demo, t);
          expect(pose.along, greaterThanOrEqualTo(along), reason: '$gesture');
          along = pose.along;
          expect(pose.tail, lessThanOrEqualTo(pose.along + 1e-9));
          expect(pose.at.dx, 100);
          expect(pose.at.dy, inInclusiveRange(190, 300));
          expect(pose.ring, lessThan(0), reason: 'only a tap rings');
        }
        expect(along, closeTo(1, 1e-9), reason: '$gesture gets there');
        expect(demoAt(demo, demoEnds(demo)).presence, 0);
        // Still, the chevron points the same way: up.
        expect(demo.cueAngle, closeTo(-math.pi / 2, 1e-9));
      }
      // A drag and a pull carry the object all the way, the finger on it.
      for (final gesture in [DemoGesture.drag, DemoGesture.pull]) {
        final demo = GestureDemo.move(
            gesture, const Offset(100, 300), const Offset(100, 190));
        final there = demoPressed + demo.travelTime;
        expect(demoAt(demo, there).presence, 1, reason: '$gesture');
        expect(demoAt(demo, there).press, closeTo(1, 1e-9));
      }
    });

    test(
        'it shows the gesture calmly, every few seconds, resting longer '
        'than it moves', () {
      expect(guideStartsAfter, lessThan(0.5),
          reason: 'it comes with the object, not after it');
      for (final demo in [
        GestureDemo.tap(const Offset(200, 300), mic),
        for (final gesture in [
          DemoGesture.swipe,
          DemoGesture.drag,
          DemoGesture.pull
        ])
          GestureDemo.move(gesture, Offset.zero, const Offset(0, -100)),
      ]) {
        expect(demo.period, inInclusiveRange(2.5, 4),
            reason: '${demo.gesture}');
        expect(demoEnds(demo), lessThan(demo.period / 2),
            reason: '${demo.gesture}');
      }
      expect(guideInsistsAfter, closeTo(6, 1));
    });

    test(
        'the object answers the touch, and is still again before the next '
        'one', () {
      final tap = GestureDemo.tap(const Offset(200, 300), mic);
      expect(demoAt(tap, demoPressed + 0.04).response, closeTo(1, 1e-9));
      for (final demo in [
        tap,
        GestureDemo.move(DemoGesture.drag, Offset.zero, const Offset(-30, -40)),
        GestureDemo.move(DemoGesture.pull, Offset.zero, const Offset(0, 60)),
        GestureDemo.move(DemoGesture.swipe, Offset.zero, const Offset(0, -90)),
      ]) {
        var most = 0.0;
        for (var t = 0.0; t < demo.period; t += 0.01) {
          most = math.max(most, demoAt(demo, t).response);
        }
        expect(most, greaterThan(0.6), reason: '${demo.gesture}');
        expect(demoAt(demo, demoEnds(demo) + 0.3).response, 0,
            reason: '${demo.gesture}');
      }
    });
  });

  test(
      'what to do is larger than the line under the headline, and stands '
      'out from the night', () {
    for (final e in [0.0, 0.5, 1.0]) {
      final style = instructionStyle(e);
      expect(style.fontSize, greaterThanOrEqualTo(Boarding.body.fontSize!));
      expect(style.fontWeight!.value, greaterThanOrEqualTo(600));
      // WCAG AA for text this size, on the night and on the light behind
      // the object.
      for (final ground in [
        Boarding.night,
        Boarding.nightTop,
        Boarding.nightFoot,
        Boarding.spotlight
      ]) {
        expect(_contrast(style.color!, ground), greaterThanOrEqualTo(4.5),
            reason: 'emphasis $e on $ground');
      }
    }
    // Insisting, it is brighter.
    expect(instructionStyle(1).color!.computeLuminance(),
        greaterThan(instructionStyle(0).color!.computeLuminance()));
  });

  testWidgets(
      'every scene says what to do next to its object and shows it on the '
      'object, from the moment it is ready', (tester) async {
    _screen(tester, const Size(390, 844));
    final key = GlobalKey<FirstLaunchOnboardingState>();
    await tester.pumpWidget(_onboarding(key, _Phone()));
    await tester.pump();
    final steps = key.currentState!.plannedSteps;
    expect(steps, containsAll(BoardingStep.values));
    for (final step in steps) {
      key.currentState!.debugJumpTo(step);
      await tester.pump();
      for (var i = 0; i < 150 && !key.currentState!.armed; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(key.currentState!.armed, isTrue, reason: step.name);
      // The touch is there within a moment of the object being ready; the
      // passport page first lifts out of the frame into the hand.
      final after =
          await _untilShown(tester, within: const Duration(milliseconds: 1500));
      expect(after, isNotNull, reason: step.name);
      expect(
          after!,
          lessThan(step == BoardingStep.camera
              ? const Duration(milliseconds: 1200)
              : const Duration(milliseconds: 600)),
          reason: step.name);
      final copy = copyFor(step);
      final guide = _guide(tester);
      expect(guide.widget.instruction, copy.hint, reason: step.name);
      expect(find.text(copy.hint), findsOneWidget, reason: step.name);
      // It is on the object: the point it comes down on is the object's.
      final from = _onScreen(tester, guide.widget.demo.from);
      final hits = tester.hitTestOnBinding(from).path.map((e) => e.target);
      final object = tester.renderObject(_objectNamed(_objectName(step)));
      expect(hits, contains(object), reason: step.name);
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  group('the gesture the touch shows is the one that moves the onboarding on',
      () {
    Future<(_Phone, GlobalKey<FirstLaunchOnboardingState>)> on(
        WidgetTester tester, BoardingStep step,
        {VoidCallback? onBoarded}) async {
      _screen(tester, const Size(390, 844));
      final phone = _Phone();
      final key = GlobalKey<FirstLaunchOnboardingState>();
      await tester.pumpWidget(_onboarding(key, phone, onBoarded: onBoarded));
      await _goTo(tester, key, step);
      expect(await _untilShown(tester), isNotNull, reason: step.name);
      return (phone, key);
    }

    /// What the touch does, done by a finger: as far, and as fast. A
    /// student who copies it moves on, without having to do more.
    Future<void> copy(WidgetTester tester, GestureDemo demo) async {
      final from = _onScreen(tester, demo.from);
      final to = _onScreen(tester, demo.to);
      final finger = await tester.startGesture(from);
      final steps = (demo.travelTime * 60).round();
      for (var i = 1; i <= steps; i++) {
        await finger.moveTo(Offset.lerp(from, to, i / steps)!);
        await tester.pump(const Duration(milliseconds: 16));
      }
      // It holds a beat at the end, as the touch does, before letting go.
      await tester.pump(const Duration(milliseconds: 100));
      await finger.up();
    }

    Future<void> stopsForGood(WidgetTester tester, String why) async {
      // It goes at once, and does not come back.
      await tester.pump(const Duration(milliseconds: 150));
      expect(_guide(tester).showing, isFalse, reason: why);
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (find.byType(SceneGuide).evaluate().isEmpty) break;
        final guide = _guide(tester);
        // The next step's guide starts on its own; this one stays away.
        if (guide.widget.active) break;
        expect(guide.showing, isFalse, reason: why);
      }
    }

    for (final step in [
      BoardingStep.notifications,
      BoardingStep.microphone,
      BoardingStep.location,
      BoardingStep.tracking,
    ]) {
      testWidgets('a tap, on ${step.name}', (tester) async {
        final (phone, _) = await on(tester, step);
        final demo = _guide(tester).widget.demo;
        expect(demo.gesture, DemoGesture.tap);
        await tester.tapAt(_onScreen(tester, demo.from));
        await stopsForGood(tester, step.name);
        expect(phone.asked, [step.access], reason: step.name);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      });
    }

    testWidgets('a swipe, on the welcome', (tester) async {
      final (_, key) = await on(tester, BoardingStep.welcome);
      final demo = _guide(tester).widget.demo;
      expect(demo.gesture, DemoGesture.swipe);
      await copy(tester, demo);
      expect(key.currentState!.currentStep, BoardingStep.notifications);
      await stopsForGood(tester, 'welcome');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('a drag, on the camera', (tester) async {
      final (phone, _) = await on(tester, BoardingStep.camera);
      final demo = _guide(tester).widget.demo;
      expect(demo.gesture, DemoGesture.drag);
      await copy(tester, demo);
      await stopsForGood(tester, 'camera');
      await _frames(tester, const Duration(milliseconds: 400));
      expect(phone.asked, [BoardingAccess.camera]);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('a pull, on the boarding pass', (tester) async {
      var boarded = false;
      final (_, key) = await on(tester, BoardingStep.boarding,
          onBoarded: () => boarded = true);
      final demo = _guide(tester).widget.demo;
      expect(demo.gesture, DemoGesture.pull);
      await copy(tester, demo);
      await stopsForGood(tester, 'boarding');
      expect(key.currentState!.armed, isFalse);
      for (var i = 0; i < 200 && !boarded; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(boarded, isTrue);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  });

  testWidgets(
      'a finger on the screen sends the touch away at once; let go without '
      'acting, it comes back a moment later', (tester) async {
    _screen(tester, const Size(390, 844));
    final key = GlobalKey<FirstLaunchOnboardingState>();
    await tester.pumpWidget(_onboarding(key, _Phone()));
    await _goTo(tester, key, BoardingStep.location);
    expect(await _untilShown(tester), isNotNull);
    // A finger on the map, not on its arrow.
    final map = tester.getRect(find.byType(LocationScene)).center;
    final finger = await tester.startGesture(map);
    await _frames(tester, const Duration(milliseconds: 100));
    expect(_guide(tester).showing, isFalse, reason: 'gone at once');
    await _frames(tester, const Duration(seconds: 3));
    expect(_guide(tester).showing, isFalse, reason: 'not while it is held');
    await finger.up();
    await _frames(tester, const Duration(milliseconds: 900));
    expect(_guide(tester).showing, isFalse, reason: 'a moment first');
    expect(await _untilShown(tester, within: const Duration(seconds: 2)),
        isNotNull);
    expect(key.currentState!.currentStep, BoardingStep.location);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets(
      'a student who has done nothing for a few seconds is shown it more '
      'strongly', (tester) async {
    _screen(tester, const Size(390, 844));
    final key = GlobalKey<FirstLaunchOnboardingState>();
    await tester.pumpWidget(_onboarding(key, _Phone()));
    await _goTo(tester, key, BoardingStep.microphone);
    final hint = copyFor(BoardingStep.microphone).hint;
    Color words() => tester.widget<Text>(find.text(hint)).style!.color!;
    await _frames(tester, const Duration(seconds: 3));
    expect(_guide(tester).emphasis, 0);
    expect(words().toARGB32(), Boarding.accent.toARGB32());
    await _frames(tester, const Duration(seconds: 5));
    expect(_guide(tester).emphasis, greaterThan(0.95));
    expect(words().computeLuminance(),
        greaterThan(Boarding.accent.computeLuminance()));
    // And the touch is larger.
    expect(await _untilShown(tester), isNotNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets(
      'with Reduce Motion each scene shows a still chevron pointing the '
      'gesture\'s way, and says what to do', (tester) async {
    _screen(tester, const Size(390, 844));
    final key = GlobalKey<FirstLaunchOnboardingState>();
    await tester.pumpWidget(_onboarding(key, _Phone(), still: true));
    await tester.pump();
    for (final step in key.currentState!.plannedSteps) {
      key.currentState!.debugJumpTo(step);
      await _frames(tester, const Duration(milliseconds: 600));
      final guide = _guide(tester);
      final demo = guide.widget.demo;
      expect(find.text(copyFor(step).hint), findsOneWidget, reason: step.name);
      // No touch moves: the chevron stands still where the touch would be.
      expect(guide.showing, isTrue, reason: step.name);
      await _frames(tester, const Duration(milliseconds: 500));
      expect(guide.pose.presence, 0, reason: step.name);
      expect(find.byKey(SceneGuide.demoKey).last, paints..path(),
          reason: step.name);
      // It points the way the gesture goes: at the object, for a tap.
      final way = demo.taps
          ? (demo.target!.center - demo.cueAt).direction
          : (demo.to - demo.from).direction;
      expect(math.cos(way - demo.cueAngle), greaterThan(0.99),
          reason: step.name);
      // And it is not on the words.
      final words = tester.getRect(find.text(copyFor(step).hint));
      expect(words.contains(_onScreen(tester, demo.cueAt)), isFalse,
          reason: step.name);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('moving, the touch is drawn; once acted on, nothing is',
      (tester) async {
    _screen(tester, const Size(390, 844));
    final key = GlobalKey<FirstLaunchOnboardingState>();
    await tester.pumpWidget(_onboarding(key, _Phone()));
    await _goTo(tester, key, BoardingStep.tracking);
    expect(await _untilShown(tester), isNotNull);
    expect(find.byKey(SceneGuide.demoKey).last, paints..circle());
    await tester.tapAt(_onScreen(tester, _guide(tester).widget.demo.from));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(SceneGuide.demoKey).last, paintsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets(
      'a screen reader is told what to do with every object, and hears the '
      'words once', (tester) async {
    final semantics = tester.ensureSemantics();
    _screen(tester, const Size(390, 844));
    final key = GlobalKey<FirstLaunchOnboardingState>();
    await tester.pumpWidget(_onboarding(key, _Phone(), still: true));
    await tester.pump();
    for (final step in key.currentState!.plannedSteps) {
      key.currentState!.debugJumpTo(step);
      await _frames(tester, const Duration(milliseconds: 600));
      final copy = copyFor(step);
      if (step == BoardingStep.language) {
        // Each language is a button named in itself, which says what a
        // double tap does in its own language too.
        for (final language in AppLanguage.values) {
          expect(
              tester.getSemantics(_objectNamed(language.nativeName)),
              isSemantics(
                label: language.nativeName,
                hint: copyFor(step, language).spoken,
                isButton: true,
                isEnabled: true,
                hasTapAction: true,
                hasSelectedState: true,
                isSelected: language == AppLanguage.en,
              ),
              reason: language.name);
        }
      } else {
        final object = _objectNamed(copy.action);
        expect(
            tester.getSemantics(object),
            isSemantics(
              label: copy.action,
              hint: copy.spoken,
              isButton: true,
              isEnabled: true,
              hasTapAction: true,
            ),
            reason: step.name);
      }
      // The words on the screen are for the eye: the object says them.
      expect(find.bySemanticsLabel(copy.hint), findsNothing, reason: step.name);
    }
    await tester.pumpWidget(const SizedBox());
    semantics.dispose();
  });

  testWidgets('the student sees which step this is, of how many',
      (tester) async {
    final semantics = tester.ensureSemantics();
    _screen(tester, const Size(390, 844));
    final key = GlobalKey<FirstLaunchOnboardingState>();
    await tester.pumpWidget(_onboarding(key, _Phone(), still: true));
    await tester.pump();
    final steps = key.currentState!.plannedSteps;
    // The languages come before the welcome, which is the cover: the steps
    // after it are counted.
    final cover = steps.indexOf(BoardingStep.welcome);
    expect(cover, 1);
    expect(find.textContaining(' OF '), findsNothing);
    key.currentState!.debugJumpTo(BoardingStep.welcome);
    await _frames(tester, const Duration(milliseconds: 600));
    expect(find.textContaining(' OF '), findsNothing);
    for (var i = cover + 1; i < steps.length; i++) {
      key.currentState!.debugJumpTo(steps[i]);
      await _frames(tester, const Duration(milliseconds: 600));
      final where = 'Step ${i - cover} of ${steps.length - 1 - cover}';
      expect(find.text(where.toUpperCase()), findsOneWidget);
      expect(tester.getSemantics(find.bySemanticsLabel('Setting up')),
          isSemantics(label: 'Setting up', value: where));
    }
    await tester.pumpWidget(const SizedBox());
    semantics.dispose();
  });

  for (final (name, size, scale) in [
    ('a large phone', const Size(390, 844), 1.0),
    ('the first iPhone SE', const Size(320, 568), 1.0),
    ('an iPhone SE with large text', const Size(375, 667), 1.3),
    ('a large phone with large text', const Size(430, 932), 1.3),
  ]) {
    testWidgets('what to do sits under its object and never on it, on $name',
        (tester) async {
      _screen(tester, size);
      final key = GlobalKey<FirstLaunchOnboardingState>();
      await tester
          .pumpWidget(_onboarding(key, _Phone(), size: size, textScale: scale));
      await tester.pump();
      for (final step in key.currentState!.plannedSteps) {
        await _goTo(tester, key, step);
        final scene = tester.getRect(_guideFinder);
        final stage = scene.size;
        final middle = scene.center;
        // What the student acts on, as it stands on the stage.
        final object = switch (step) {
          BoardingStep.language => languagePaneRect(stage).shift(scene.topLeft),
          BoardingStep.welcome => Rect.fromCenter(
              center: scene.topLeft +
                  Offset(stage.width / 2,
                      stage.height / 2 + launchArrowDrop(stage)),
              width: launchArrowHeight * 1.1,
              height: launchArrowHeight * 1.1),
          BoardingStep.notifications => Rect.fromCenter(
              center: middle, width: cardWidth(stage.width), height: 118),
          BoardingStep.camera => Rect.fromCenter(
              center: middle,
              width: scanFrame(pageWidth(stage.width)).width,
              height: scanFrame(pageWidth(stage.width)).height),
          BoardingStep.microphone =>
            Rect.fromCircle(center: middle, radius: micSide / 2),
          BoardingStep.location =>
            Rect.fromCircle(center: middle, radius: lensRadius(stage))
                .expandToInclude(Rect.fromCircle(
                    center: middle + locateOffset(lensRadius(stage)),
                    radius: locateSide / 2)),
          // The shield and the rings round it.
          BoardingStep.tracking => Rect.fromCircle(center: middle, radius: 100),
          BoardingStep.boarding => passRect(stage).shift(scene.topLeft),
        };
        final words = tester.getRect(find.text(copyFor(step).hint));
        expect(words.top, greaterThanOrEqualTo(object.bottom),
            reason: '${step.name} on $name');
        expect(words.top - object.bottom, lessThan(48),
            reason: '${step.name} on $name: next to it');
        expect(words.left, greaterThanOrEqualTo(0));
        expect(words.right, lessThanOrEqualTo(size.width));
        // On the screen, above the home indicator; on a screen too short
        // for everything, which scrolls, within what scrolls.
        final scroll = find.byType(SingleChildScrollView);
        final end = scroll.evaluate().isEmpty
            ? size.height - 34
            : tester
                .getRect(find
                    .descendant(of: scroll, matching: find.byType(Column))
                    .first)
                .bottom;
        expect(words.bottom, lessThanOrEqualTo(end),
            reason: '${step.name} on $name: where it can be read');
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  }

  test(
      'the pass makes room under it for what to do, giving up a fifth at '
      'most', () {
    for (final stage in const [
      Size(342, 495),
      Size(327, 431),
      Size(272, 354),
      Size(272, 293)
    ]) {
      final full = math.min(
          1.0,
          math.min(
              stage.width / (passWidth + 8), stage.height / (passHeight + 24)));
      final scale = passScale(stage);
      expect(scale, lessThanOrEqualTo(full));
      expect(scale, greaterThanOrEqualTo(full * 0.8 - 1e-9));
    }
    // A tall stage keeps the pass at its own size.
    expect(passScale(const Size(342, 495)), 1);
  });
}
