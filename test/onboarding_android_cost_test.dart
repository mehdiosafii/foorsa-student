// What the first-launch onboarding costs a phone to draw, and what it no
// longer makes it draw (docs/first-launch-onboarding.md, "Android"): the web
// view in a texture and out of the picture while the onboarding covers it,
// the shell's loader asleep under it, no offscreen layer where none shows,
// the glass's blurs rastered once on Android, and render objects repainted
// only where something moves.
//
// Every count here is for the screen its test names: the test draws at that
// screen's pixels per point, and the glass is baked at the same.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/onboarding/airliner.dart';
import 'package:foorsa_student/src/onboarding/flight_loader.dart';
import 'package:foorsa_student/src/onboarding/glass.dart';
import 'package:foorsa_student/src/onboarding/glass_arrow.dart';
import 'package:foorsa_student/src/onboarding/onboarding_flow.dart';
import 'package:foorsa_student/src/onboarding/onboarding_gate.dart';
import 'package:foorsa_student/src/onboarding/onboarding_page.dart';
import 'package:foorsa_student/src/onboarding/onboarding_store.dart';
import 'package:foorsa_student/src/onboarding/scene_notifications.dart';
import 'package:foorsa_student/src/onboarding/takeoff_intro.dart';
import 'package:foorsa_student/src/shell_screens.dart';
import 'package:foorsa_student/src/web_view_composition.dart';

import 'frame_cost.dart';

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

/// A phone's screen: its pixels, and how many of them a point covers.
class _Screen {
  const _Screen(this.name, this.pixels, this.density);
  final String name;
  final Size pixels;
  final double density;

  Size get points => pixels / density;
}

/// A common Android phone, the one the doc's numbers are for.
const _fullHd = _Screen('1080 x 2400 at 2.625', Size(1080, 2400), 2.625);

/// A 720p one. A blur under a pixel and a half wide is not baked
/// (GlassBake.softEnough), and with fewer pixels to a point more of the
/// narrow lights are.
const _hd = _Screen('720 x 1600 at 2', Size(720, 1600), 2);

/// Draws for [screen], under a 24 pt status bar. The glass is baked for it
/// too: GlassBake reads the density of the view this sets.
void _android(WidgetTester tester, [_Screen screen = _fullHd]) {
  tester.view.devicePixelRatio = screen.density;
  tester.view.physicalSize = screen.pixels;
  tester.view.padding = FakeViewPadding(top: 24 * screen.density);
  addTearDown(tester.view.reset);
}

Future<void> _frames(WidgetTester tester, Duration length,
    {Duration frame = const Duration(milliseconds: 16)}) async {
  for (var t = Duration.zero; t < length; t += frame) {
    await tester.pump(frame);
  }
}

Widget _onboarding(GlobalKey<FirstLaunchOnboardingState> key,
        {bool still = false, _Screen screen = _fullHd}) =>
    MediaQuery(
      data: MediaQueryData(
          size: screen.points,
          devicePixelRatio: screen.density,
          padding: const EdgeInsets.only(top: 24),
          disableAnimations: still),
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
    );

/// Every scene the Android onboarding has, its object ready.
const _scenes = [
  BoardingStep.welcome,
  BoardingStep.language,
  BoardingStep.notifications,
  BoardingStep.camera,
  BoardingStep.microphone,
  BoardingStep.location,
  BoardingStep.boarding,
];

Future<void> _goTo(WidgetTester tester,
    GlobalKey<FirstLaunchOnboardingState> key, BoardingStep step) async {
  if (step == BoardingStep.welcome) {
    // After the takeoff, past the languages' pane (English, the default).
    await _frames(tester, const Duration(milliseconds: 4200));
    await _pastLanguage(tester, key);
  } else {
    key.currentState!.debugJumpTo(step);
    await _frames(tester, const Duration(milliseconds: 1600));
  }
  expect(key.currentState!.armed, isTrue, reason: step.name);
}

/// The first step is the languages' pane: English, the default, is tapped.
Future<void> _pastLanguage(
    WidgetTester tester, GlobalKey<FirstLaunchOnboardingState> key) async {
  if (key.currentState!.currentStep != BoardingStep.language) return;
  await tester.tap(find
      .byWidgetPredicate((w) =>
          w is Semantics &&
          (w.properties.label ?? w.properties.attributedLabel?.string) ==
              'English' &&
          w.properties.button == true)
      .last);
  await _frames(tester, const Duration(milliseconds: 1600));
}

void main() {
  group('the web view under the onboarding', () {
    test(
        'Android makes it in a texture while the onboarding covers it, and '
        'in the window otherwise; iOS has one way', () {
      expect(webViewUsesHybridComposition(android: true, underOnboarding: true),
          isFalse);
      expect(
          webViewUsesHybridComposition(android: true, underOnboarding: false),
          isTrue);
      expect(
          webViewUsesHybridComposition(android: false, underOnboarding: true),
          isTrue);
      expect(
          webViewUsesHybridComposition(android: false, underOnboarding: false),
          isTrue);
    });

    test(
        'only a web view in a texture is left undrawn, and only while '
        'covered', () {
      expect(
          webViewHiddenUnderOnboarding(
              android: true, hybridComposition: false, covered: true),
          isTrue);
      // In the window, Android lays it out only once Flutter draws it.
      expect(
          webViewHiddenUnderOnboarding(
              android: true, hybridComposition: true, covered: true),
          isFalse);
      expect(
          webViewHiddenUnderOnboarding(
              android: true, hybridComposition: false, covered: false),
          isFalse);
      expect(
          webViewHiddenUnderOnboarding(
              android: false, hybridComposition: false, covered: true),
          isFalse);
    });

    test('the shell asks for it that way', () {
      // InAppWebView cannot be built in a test (it is a platform view), so
      // the shell's source is held to it.
      final shell = File('lib/src/shell_page.dart').readAsStringSync();
      expect(shell, contains('useHybridComposition: _webViewHybrid'));
      expect(shell, isNot(contains('useHybridComposition: true')));
      expect(
          RegExp(r'CoveredByOnboarding\(\s*covered: '
                  r'webViewHiddenUnderOnboarding\(')
              .hasMatch(shell),
          isTrue);
      expect(shell, contains('underOnboarding: _onboardingShown'));
    });

    testWidgets(
        'covered, it is laid out and kept, but neither drawn nor '
        'touched', (tester) async {
      var painted = 0;
      var tapped = 0;
      Widget box(bool covered) => Directionality(
            textDirection: TextDirection.ltr,
            child: CoveredByOnboarding(
              covered: covered,
              child: GestureDetector(
                onTap: () => tapped++,
                child: CustomPaint(
                    size: const Size(200, 100),
                    painter: _Counting(() => painted++)),
              ),
            ),
          );
      await tester.pumpWidget(box(true));
      expect(
          tester.getSize(find.byType(CustomPaint).last), const Size(800, 600));
      expect(painted, 0);
      await tester.tapAt(const Offset(100, 50));
      expect(tapped, 0);
      expect(
          tester.layers
              .whereType<PictureLayer>()
              .where((l) => l.picture != null && l.parent is! TransformLayer),
          isEmpty);

      await tester.pumpWidget(box(false));
      expect(painted, 1);
      await tester.tapAt(const Offset(100, 50));
      expect(tapped, 1);
    });
  });

  group('the gate', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('cost_'));
    tearDown(() {
      GlassBake.enabled = false;
      dir.deleteSync(recursive: true);
    });

    testWidgets(
        'the onboarding covers the shell until it starts to fade onto '
        'the sign-in; Android bakes its glass until it ends', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);
      final covering = <bool>[];
      final active = <bool>[];
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(
            size: Size(390, 844),
            padding: EdgeInsets.only(top: 47, bottom: 34),
            disableAnimations: true),
        child: MaterialApp(
          home: FirstLaunchGate(
            show: true,
            bakeGlass: true,
            store: OnboardingStore(
                directory: () async => dir, webViewData: () async => const []),
            permissions: _Phone(start: {
              for (final a in BoardingAccess.values) a: AccessState.granted
            }),
            child: Builder(builder: (context) {
              covering.add(OnboardingScope.coveringOf(context));
              active.add(OnboardingScope.activeOf(context));
              return const Text('Portal');
            }),
          ),
        ),
      ));
      await _frames(tester, const Duration(milliseconds: 1200));
      expect(covering.last, isTrue);
      expect(active.last, isTrue);
      expect(GlassBake.enabled, isTrue);

      Future<void> act(String label) async {
        await tester.tap(find
            .byWidgetPredicate((w) =>
                w is Semantics &&
                (w.properties.label ?? w.properties.attributedLabel?.string) ==
                    label &&
                w.properties.button == true)
            .last);
        await _frames(tester, const Duration(milliseconds: 600));
      }

      await act('English');
      await act('Get started');
      await tester.tap(find
          .byWidgetPredicate((w) =>
              w is Semantics &&
              w.properties.label == 'Board' &&
              w.properties.button == true)
          .last);
      // The stub is off: the onboarding fades, the shell is seen again.
      var sawUncoveredWhileActive = false;
      for (var i = 0; i < 60 && active.last; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (!covering.last && active.last) sawUncoveredWhileActive = true;
      }
      expect(sawUncoveredWhileActive, isTrue,
          reason: 'the shell draws again as the fade starts');
      await _frames(tester, const Duration(milliseconds: 600));
      expect(active.last, isFalse);
      expect(covering.last, isFalse);
      expect(GlassBake.enabled, isFalse);
      expect(GlassBake.count, 0);
      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('an update never bakes', (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: FirstLaunchGate(
        show: false,
        bakeGlass: true,
        store: OnboardingStore(
            directory: () async => dir, webViewData: () async => const []),
        permissions: _Phone(),
        child: const Text('Portal'),
      )));
      expect(GlassBake.enabled, isFalse);
    });
  });

  group('the shell\'s loader under the onboarding', () {
    Widget layer(
            {required bool showing,
            required bool covered,
            VoidCallback? onGone}) =>
        MaterialApp(
          home: Stack(children: [
            ShellLoadingLayer(
                showing: showing,
                covered: covered,
                dark: true,
                onGone: onGone ?? () {}),
          ]),
        );

    testWidgets('covered, it neither draws nor animates', (tester) async {
      // The loader's own layer (flight_loader.dart draws it in a
      // RepaintBoundary).
      bool drawn() =>
          tester
              .renderObject(find.descendant(
                  of: find.byType(FlightLoader),
                  matching: find.byType(RepaintBoundary)))
              .debugLayer
              ?.attached ??
          false;
      await tester.pumpWidget(layer(showing: true, covered: true));
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.binding.hasScheduledFrame, isFalse,
          reason: 'nothing under the onboarding asks for frames');
      expect(drawn(), isFalse);
      // Seen again, it plays.
      await tester.pumpWidget(layer(showing: true, covered: false));
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.binding.hasScheduledFrame, isTrue);
      expect(drawn(), isTrue);
    });

    testWidgets(
        'let go of while covered, it is gone by the time the '
        'onboarding fades', (tester) async {
      var gone = 0;
      await tester.pumpWidget(layer(showing: true, covered: true));
      await tester.pumpWidget(
          layer(showing: false, covered: true, onGone: () => gone++));
      await tester.pump(const Duration(milliseconds: 240));
      await tester.pump(const Duration(milliseconds: 16));
      expect(gone, 1);
    });
  });

  testWidgets('the glass is baked for the screen a test draws on',
      (tester) async {
    // The engine's own view keeps its density in a test (3, whatever the
    // test sets), and GlassBake read that one: these tests drew for a phone
    // at 2.625 and baked for one at 3. What is baked and what is not depends
    // on the density, so the counts were another phone's.
    for (final screen in [_fullHd, _hd]) {
      _android(tester, screen);
      expect(tester.binding.renderViews.first.configuration.devicePixelRatio,
          screen.density,
          reason: screen.name);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      expect(GlassBake.deviceScale(canvas), screen.density,
          reason: screen.name);
      // A 40 pt arrow, drawn at four tenths of its 100.
      canvas.scale(0.4);
      expect(GlassBake.deviceScale(canvas), closeTo(0.4 * screen.density, 1e-6),
          reason: screen.name);
      recorder.endRecording().dispose();
    }
  });

  group('one frame of each scene', () {
    tearDown(() => GlassBake.enabled = false);

    testWidgets('draws no offscreen layer at rest or as the object changes',
        (tester) async {
      _android(tester);
      final key = GlobalKey<FirstLaunchOnboardingState>();
      await tester.pumpWidget(_onboarding(key));
      for (final step in _scenes) {
        if (step != BoardingStep.welcome) {
          key.currentState!.debugJumpTo(step);
          // Half-way through the change: the old object is the arrow.
          await _frames(tester, const Duration(milliseconds: 480));
          final changing = frameCost(tester);
          expect(changing.saveLayers, 0, reason: '${step.name}: $changing');
        }
        await _goTo(tester, key, step);
        final rest = frameCost(tester);
        // The welcome's floor is the board's reflection, a shader mask the
        // size of the board: the only one.
        expect(rest.saveLayers, step == BoardingStep.welcome ? 1 : 0,
            reason: '${step.name}: $rest');
      }
    });

    // Each scene's glass that keeps its shape drew its blurs through
    // offscreen passes every frame: the arrow (its shadows and its lights),
    // the board's case, the languages' pane, the cards, the mic's orb, the
    // lens, the locate button, the pass's shadows. For each scene: what its
    // own glass asked for at rest, the touch away; what it asks for now,
    // from pictures; and the most a frame asks for now, while the touch
    // shows what to do. What is left is a blur under a pixel and a half
    // wide, drawn as before so that it stays sharp, or one that changes
    // every frame it is drawn: the touch (the two lights in it, and two
    // more for its trail as it moves) is never baked.
    const blursOf = {
      // Its arrow is 40 pt tall: the light along its bevel is 1.05 px wide
      // at 2.625 (0.8 at 2).
      BoardingStep.welcome: (5, 1, 5),
      BoardingStep.language: (1, 0, 2),
      // One for each card on the screen; the first is alone.
      BoardingStep.notifications: (1, 0, 2),
      // The scanner has no glass that bakes: only the touch.
      BoardingStep.camera: (0, 0, 4),
      BoardingStep.microphone: (2, 0, 2),
      // The locate arrow is 19 pt tall. Its two lights are 0.5 and 1.1 px
      // wide, and the narrower of its two shadows 1.496 px at 2.625 (1.14
      // at 2): all four are drawn as before. A screen at 3 pixels per point
      // bakes the shadows, 1.71 px there, and keeps two.
      BoardingStep.location: (8, 4, 6),
      BoardingStep.boarding: (1, 0, 4),
    };

    // The scenes are the same on the two screens. What fewer pixels change
    // is in motion: [leaving], the plane's bevel as it climbs away.
    for (final (screen, leaving) in [(_fullHd, 0), (_hd, 1)]) {
      testWidgets(
          'on Android, draws the glass\'s blurs from pictures: '
          '${screen.name}', (tester) async {
        _android(tester, screen);
        final key = GlobalKey<FirstLaunchOnboardingState>();
        await tester.pumpWidget(_onboarding(key, screen: screen));

        // The blurs through offscreen passes in the frame last drawn: as it
        // was drawn before, and from pictures.
        (int, int) blurs() {
          GlassBake.enabled = false;
          final drawn = frameCost(tester).gaussianBlurs;
          GlassBake.enabled = true;
          return (drawn, frameCost(tester).gaussianBlurs);
        }

        var seconds = 0.0;
        Future<(int, int)> takeoffAt(double at) async {
          for (; seconds < at; seconds += 0.016) {
            await tester.pump(const Duration(milliseconds: 16));
          }
          return blurs();
        }

        // The takeoff's arrow: its two shadows and its two lights.
        expect(await takeoffAt(morphStarts / 2), (4, 0), reason: 'the arrow');
        // The plane at rest: its two lights.
        expect(await takeoffAt((morphEnds + climbStarts) / 2), (2, 0),
            reason: 'the plane');
        // The plane as it leaves, at five eighths of its size, over the
        // languages' pane coming in (one blur of its own, baked). On the
        // 720p screen the light along its bevel is 1.4 px wide by then.
        expect(await takeoffAt(takeoffSeconds - 0.1), (3, leaving),
            reason: 'the plane leaving');

        for (final step in _scenes) {
          if (step == BoardingStep.welcome) {
            await _goTo(tester, key, step);
          } else {
            key.currentState!.debugJumpTo(step);
            // The change between objects is glass that turns as it goes, so
            // none of it is baked: four to six blurs a frame, on any screen,
            // from a quarter of a second in until the new object is there.
            for (var frame = 1; frame <= 100; frame++) {
              await tester.pump(const Duration(milliseconds: 16));
              if (frame < 15 || frame > 54) continue;
              final (drawn, baked) = blurs();
              expect(drawn, inInclusiveRange(4, 6),
                  reason: 'into ${step.name}, frame $frame');
              expect(baked, drawn, reason: 'into ${step.name}, frame $frame');
            }
            expect(key.currentState!.armed, isTrue, reason: step.name);
          }
          // Its objects all in (the map fades in over its first second).
          await _frames(tester, const Duration(milliseconds: 1000));
          // A whole demonstration and the rest after it.
          var drawnAtRest = 99, bakedAtRest = 99, bakedAtMost = 0;
          for (var frame = 0; frame < 220; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
            final (drawn, baked) = blurs();
            drawnAtRest = math.min(drawnAtRest, drawn);
            bakedAtRest = math.min(bakedAtRest, baked);
            bakedAtMost = math.max(bakedAtMost, baked);
          }
          expect((drawnAtRest, bakedAtRest, bakedAtMost), blursOf[step],
              reason: step.name);
        }
      });
    }

    // What the takeoff and the scenes picture together, measured.
    for (final (screen, pictures, megabytes) in [
      (_fullHd, 27, 10.7),
      (_hd, 28, 7.2),
    ]) {
      testWidgets('makes each picture once, and holds little: ${screen.name}',
          (tester) async {
        _android(tester, screen);
        final key = GlobalKey<FirstLaunchOnboardingState>();
        // As the gate does on Android, from the takeoff on.
        GlassBake.enabled = true;
        GlassBake.made = 0;
        await tester.pumpWidget(_onboarding(key, screen: screen));
        for (final step in _scenes) {
          await _goTo(tester, key, step);
          // Its objects all in, and a whole demonstration: what comes on the
          // screen is pictured as it comes.
          await _frames(tester, const Duration(milliseconds: 1000 + 220 * 16));
          // The demonstration again pictures nothing: every frame draws what
          // was made (a piece of glass whose key changed every frame would
          // be made again every frame, and cost more than it saves).
          final made = GlassBake.made;
          await _frames(tester, const Duration(milliseconds: 220 * 16));
          expect(GlassBake.made, made, reason: step.name);
        }
        // Nothing was let go and made again, and the whole onboarding holds
        // a few textures.
        expect(GlassBake.made, GlassBake.count);
        expect(GlassBake.count, pictures);
        expect(GlassBake.pixels * 4 / 1e6, closeTo(megabytes, 0.05));
      });
    }

    testWidgets('repaints only what moves', (tester) async {
      _android(tester);
      final key = GlobalKey<FirstLaunchOnboardingState>();
      await tester.pumpWidget(_onboarding(key));
      var paints = 0;
      final perFrame = <BoardingStep, double>{};
      debugProfilePaintsEnabled = true;
      debugOnProfilePaint = (_) => paints++;
      try {
        for (final step in _scenes) {
          await _goTo(tester, key, step);
          paints = 0;
          // A whole demonstration and the rest after it.
          const frames = 220;
          for (var i = 0; i < frames; i++) {
            await tester.pump(const Duration(milliseconds: 16));
          }
          perFrame[step] = paints / frames;
        }
      } finally {
        debugOnProfilePaint = null;
        debugProfilePaintsEnabled = false;
      }
      // Before (a0b5f27, the same measure): 36.4, 48.9, 15.5, 21.5 and 24.5
      // render objects a frame, and 64.9 on the pass, whose clock nothing
      // read; a builder inside a LayoutBuilder laid the map's whole scene out
      // again every frame.
      // Measured: 3.3, 5.6, 2.5, 2.5, 3.5 and 8.3 (the stub, as the guide's
      // touch pulls it), and 1.5 on the languages' pane.
      for (final step in _scenes) {
        expect(
            perFrame[step]!, lessThan(step == BoardingStep.boarding ? 12 : 8),
            reason: '${step.name}: ${perFrame[step]!.toStringAsFixed(1)}');
      }
    });
  });

  testWidgets('every scene baked draws what it draws unbaked', (tester) async {
    _android(tester);
    addTearDown(() => GlassBake.enabled = false);
    Future<Uint8List> shot() async {
      final layer = tester.binding.renderViews.first.debugLayer! as OffsetLayer;
      late Uint8List bytes;
      await tester.runAsync(() async {
        // The root layer applies the screen's pixel ratio itself.
        final image = await layer
            .toImage(Offset.zero & tester.view.physicalSize, pixelRatio: 1);
        bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
            .buffer
            .asUint8List();
        image.dispose();
      });
      return bytes;
    }

    // Reduce Motion: every scene stands still, so two sessions draw the same
    // frame.
    Future<Uint8List> scene(BoardingStep step, {required bool bake}) async {
      GlassBake.enabled = bake;
      final key = GlobalKey<FirstLaunchOnboardingState>();
      await tester.pumpWidget(_onboarding(key, still: true));
      await _frames(tester, const Duration(milliseconds: 160));
      // The welcome too: the first step is the languages' pane.
      key.currentState!.debugJumpTo(step);
      await _frames(tester, const Duration(milliseconds: 480));
      expect(key.currentState!.currentStep, step);
      final frame = await shot();
      if (bake && step != BoardingStep.camera) {
        expect(GlassBake.count, greaterThan(0), reason: step.name);
      }
      await tester.pumpWidget(const SizedBox());
      GlassBake.enabled = false;
      return frame;
    }

    for (final step in _scenes) {
      final drawn = await scene(step, bake: false);
      final baked = await scene(step, bake: true);
      var worst = 0, total = 0;
      for (var i = 0; i < drawn.length; i++) {
        final d = (drawn[i] - baked[i]).abs();
        if (d > worst) worst = d;
        total += d;
      }
      // Measured on 1080 x 2400 at 2.625, the pictures made at that density:
      // 4 levels of 255 at worst and 0.010 on average with Skia; 6 and 0.020
      // with Impeller (flutter test --enable-impeller), in the light along
      // the lower bevel of the smoked panes.
      expect(worst, lessThanOrEqualTo(6), reason: step.name);
      expect(total / drawn.length, lessThan(0.05), reason: step.name);
    }
  });

  testWidgets(
      'the takeoff\'s arrow and plane, and the flying arrow, baked, '
      'draw what they draw unbaked', (tester) async {
    _android(tester);
    addTearDown(() => GlassBake.enabled = false);
    Future<Uint8List> shot(bool bake) async {
      GlassBake.enabled = bake;
      await tester
          .pumpWidget(CustomPaint(painter: _Glasses(), size: Size.infinite));
      final layer = tester.binding.renderViews.first.debugLayer! as OffsetLayer;
      late Uint8List bytes;
      await tester.runAsync(() async {
        final image = await layer
            .toImage(Offset.zero & tester.view.physicalSize, pixelRatio: 1);
        bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
            .buffer
            .asUint8List();
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox());
      GlassBake.enabled = false;
      return bytes;
    }

    final drawn = await shot(false);
    final baked = await shot(true);
    var worst = 0, total = 0;
    for (var i = 0; i < drawn.length; i++) {
      final d = (drawn[i] - baked[i]).abs();
      if (d > worst) worst = d;
      total += d;
    }
    expect(worst, lessThanOrEqualTo(6));
    expect(total / drawn.length, lessThan(0.05));
  });

  testWidgets('a 120 Hz screen sees the same flight as a 60 Hz one',
      (tester) async {
    _android(tester);

    /// Where the flying arrow is every 50 ms of its way into the board,
    /// the screen drawing [perInterval] frames in each 50 ms.
    Future<List<Offset?>> flight(int perInterval) async {
      final key = GlobalKey<FirstLaunchOnboardingState>();
      await tester.pumpWidget(_onboarding(key));
      await _goTo(tester, key, BoardingStep.welcome);
      await tester.tap(find
          .byWidgetPredicate((w) =>
              w is Semantics &&
              w.properties.label == 'Get started' &&
              w.properties.button == true)
          .last);
      await tester.pump();
      final at = <Offset?>[];
      for (var sample = 0; sample < 8; sample++) {
        for (var i = 0; i < perInterval; i++) {
          // The frames of one interval end exactly on it.
          await tester.pump(Duration(
              microseconds:
                  50000 * (i + 1) ~/ perInterval - 50000 * i ~/ perInterval));
        }
        at.add(key.currentState!.pilotAt);
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      return at;
    }

    final sixty = await flight(3);
    final oneTwenty = await flight(6);
    expect(sixty.whereType<Offset>(), hasLength(greaterThanOrEqualTo(5)));
    for (var i = 0; i < sixty.length; i++) {
      final a = sixty[i], b = oneTwenty[i];
      expect(a == null, b == null, reason: 'sample $i');
      if (a != null && b != null) {
        expect((a - b).distance, lessThan(0.5), reason: 'sample $i');
      }
    }
  });

  test('the cards\' icon is decoded at the size it is shown', () {
    final icon = notificationIcon(3) as ResizeImage;
    expect(icon.width, 114);
    expect(icon.height, 114);
  });

  test('Android keeps Impeller', () {
    // Impeller compiles every shader when the app is built: the onboarding is
    // the first thing a new install draws, and Skia would compile its
    // shaders during the takeoff. The opt-out is deprecated in this Flutter
    // and logs that it will go away. Below Android 10 the engine draws with
    // Skia on its own, and it falls back to Impeller's OpenGL ES on drivers
    // it knows to be bad (flutter_main.cc,
    // android_context_dynamic_impeller.cc).
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest,
        isNot(contains('io.flutter.embedding.android.EnableImpeller')));
  });
}

class _Counting extends CustomPainter {
  _Counting(this.onPaint);
  final VoidCallback onPaint;
  @override
  void paint(Canvas canvas, Size size) => onPaint();
  @override
  bool shouldRepaint(_Counting old) => false;
}

/// The glass that bakes: the arrow at three sizes, turned, and the plane.
class _Glasses extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFF0A131F));
    for (final (at, height) in const [
      (Offset(80, 90), 40.0),
      (Offset(220, 120), 84.0),
      (Offset(120, 300), 100.0),
    ]) {
      canvas.save();
      canvas.translate(at.dx, at.dy);
      canvas.rotate(0.3);
      paintGlassArrow(canvas, height: height, glow: 0.6);
      canvas.restore();
    }
    canvas.save();
    canvas.translate(200, 360);
    paintPearlPlane(canvas, detail: 1, lights: 0);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Glasses old) => false;
}
