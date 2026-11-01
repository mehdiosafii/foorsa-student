// What the first-launch onboarding costs a phone to draw, and what it no
// longer makes it draw (docs/first-launch-onboarding.md, "Android"): the web
// view in a texture and out of the picture while the onboarding covers it,
// the shell's loader asleep under it, no offscreen layer where none shows,
// the glass's blurs rastered once on Android, and render objects repainted
// only where something moves.

import 'dart:io';
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

/// A common Android phone: 1080 x 2400 at 2.625.
void _android(WidgetTester tester) {
  tester.view.devicePixelRatio = 2.625;
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.padding = const FakeViewPadding(top: 63);
  addTearDown(tester.view.reset);
}

Future<void> _frames(WidgetTester tester, Duration length,
    {Duration frame = const Duration(milliseconds: 16)}) async {
  for (var t = Duration.zero; t < length; t += frame) {
    await tester.pump(frame);
  }
}

Widget _onboarding(GlobalKey<FirstLaunchOnboardingState> key,
        {bool still = false}) =>
    MediaQuery(
      data: MediaQueryData(
          size: const Size(1080 / 2.625, 2400 / 2.625),
          devicePixelRatio: 2.625,
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
  BoardingStep.notifications,
  BoardingStep.camera,
  BoardingStep.microphone,
  BoardingStep.location,
  BoardingStep.boarding,
];

Future<void> _goTo(WidgetTester tester,
    GlobalKey<FirstLaunchOnboardingState> key, BoardingStep step) async {
  if (step == BoardingStep.welcome) {
    // After the takeoff.
    await _frames(tester, const Duration(milliseconds: 4200));
  } else {
    key.currentState!.debugJumpTo(step);
    await _frames(tester, const Duration(milliseconds: 1600));
  }
  expect(key.currentState!.armed, isTrue, reason: step.name);
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
                w.properties.label == label &&
                w.properties.button == true)
            .last);
        await _frames(tester, const Duration(milliseconds: 600));
      }

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

    testWidgets('on Android, draws the glass\'s blurs from pictures',
        (tester) async {
      _android(tester);
      final key = GlobalKey<FirstLaunchOnboardingState>();
      final baked = <BoardingStep, FrameCost>{};
      final drawn = <BoardingStep, FrameCost>{};
      await tester.pumpWidget(_onboarding(key));
      for (final step in _scenes) {
        await _goTo(tester, key, step);
        // Its objects all in (the map fades in over its first second).
        await _frames(tester, const Duration(milliseconds: 1000));
        GlassBake.enabled = false;
        drawn[step] = frameCost(tester);
        GlassBake.enabled = true;
        baked[step] = frameCost(tester);
      }
      // Each scene's glass that keeps its shape drew its blurs through
      // offscreen passes every frame: the arrow (its shadows and its lights),
      // the board's case, the cards, the mic's orb, the lens, the locate
      // button, the pass's shadows. The same frame, baked:
      const removed = {
        BoardingStep.welcome: 4,
        BoardingStep.notifications: 1,
        BoardingStep.microphone: 2,
        BoardingStep.location: 6,
        BoardingStep.boarding: 1,
      };
      for (final step in _scenes) {
        final before = drawn[step]!.gaussianBlurs;
        final after = baked[step]!.gaussianBlurs;
        expect(before - after, greaterThanOrEqualTo(removed[step] ?? 0),
            reason: '${step.name}: ${drawn[step]} / ${baked[step]}');
        // What is left changes every frame it is drawn (the touch showing
        // what to do, and its trail), or is a light under a pixel and a half
        // wide (the small arrows' bevels), drawn as before so that it stays
        // sharp.
        expect(after, lessThanOrEqualTo(5),
            reason: '${step.name}: ${baked[step]}');
      }
    });

    testWidgets('makes each picture once, and holds little', (tester) async {
      _android(tester);
      final key = GlobalKey<FirstLaunchOnboardingState>();
      // As the gate does on Android, from the takeoff on.
      GlassBake.enabled = true;
      GlassBake.made = 0;
      await tester.pumpWidget(_onboarding(key));
      for (final step in _scenes) {
        await _goTo(tester, key, step);
        // Its objects all in, and a whole demonstration: what comes on the
        // screen is pictured as it comes.
        await _frames(tester, const Duration(milliseconds: 1000 + 220 * 16));
        // The demonstration again pictures nothing: every frame draws what
        // was made (a piece of glass whose key changed every frame would be
        // made again every frame, and cost more than it saves).
        final made = GlassBake.made;
        await _frames(tester, const Duration(milliseconds: 220 * 16));
        expect(GlassBake.made, made, reason: step.name);
      }
      // Nothing was let go and made again, and the whole onboarding holds a
      // few textures: measured 25 pictures, 11.8 MB, on 1080 x 2400.
      expect(GlassBake.made, GlassBake.count);
      expect(GlassBake.pixels * 4, lessThan(24e6));
    });

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
      // Measured: 3.0, 5.6, 2.5, 2.5, 3.5 and 8.3 (the stub, as the guide's
      // touch pulls it).
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
      if (step != BoardingStep.welcome) key.currentState!.debugJumpTo(step);
      await _frames(tester, const Duration(milliseconds: 480));
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
      // Measured on 1080 x 2400: 4 levels of 255 at worst, 0.015 on average,
      // with Skia and with Impeller.
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
