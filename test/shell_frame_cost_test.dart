// What the shell costs a phone to draw on every start and in use, and what it
// no longer makes it draw (the owner, 11 Nov 2026: "some animations and usage
// feel sluggish in the app, android and ios"): the Android web view straight
// into the window with no offscreen layer of its own
// (lib/src/web_view_composition.dart), the web view made without a fixed
// wait and the loader at rest until it exists (boot_loader_gate.dart), and on
// Android the loader's blurs from pictures (shell_screens.dart).
//
// No phone was at hand: as for the onboarding
// (onboarding_android_cost_test.dart), what each frame asks the GPU for is
// counted (frame_cost.dart), and what the plugin and Android do with a
// setting is read from their code.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/onboarding/flight_loader.dart';
import 'package:foorsa_student/src/onboarding/glass.dart';
import 'package:foorsa_student/src/shell_screens.dart';
import 'package:foorsa_student/src/web_view_composition.dart';

import 'frame_cost.dart';

String _read(String path) => File(path).readAsStringSync();

/// A common Android phone: 1080 x 2400 at 2.625.
void _android(WidgetTester tester) {
  tester.view.devicePixelRatio = 2.625;
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.padding = const FakeViewPadding(top: 63);
  addTearDown(tester.view.reset);
}

/// The loader as the shell shows it, alone on its ground.
Widget _loader({required bool dark, bool bakeGlass = false}) => MaterialApp(
      home: Stack(children: [
        ShellLoadingLayer(
            showing: true,
            covered: false,
            dark: dark,
            bakeGlass: bakeGlass,
            onGone: () {}),
      ]),
    );

/// The loop's moments: the arrow at rest (what shows while the web view is
/// made), the light crossing it, the plane lit, and the plane climbing away.
const _moments = <String, int>{
  'the arrow at rest': 0,
  'the light crossing it': 300,
  'the plane, its lights on': 1700,
  'the plane climbing': 2200,
};

void main() {
  group('the Android web view has no offscreen layer of its own', () {
    test('the shell asks for none', () {
      expect(webViewOffscreenLayer, isFalse);
      // InAppWebView cannot be built in a test (it is a platform view), so
      // the shell's source is held to it.
      final shell = _read('lib/src/shell_page.dart');
      expect(shell, contains('hardwareAcceleration: webViewOffscreenLayer,'));
      expect(shell, isNot(contains('hardwareAcceleration: true')));
    });

    test('the plugin takes that for no layer, never for software', () {
      // The setting is named hardwareAcceleration, and all it does is choose
      // the view's layer type under Hybrid Composition. An upgrade of the
      // plugin that gave false another meaning must fail here.
      final plugin = _read('third_party/flutter_inappwebview_android/android/'
          'src/main/java/com/pichillilorenzo/flutter_inappwebview_android/'
          'webview/in_app_webview/InAppWebView.java');
      expect(
          RegExp(r'if \(customSettings\.useHybridComposition\) \{\s*'
                  r'if \(customSettings\.hardwareAcceleration\)\s*'
                  r'setLayerType\(View\.LAYER_TYPE_HARDWARE, null\);\s*'
                  r'else\s*'
                  r'setLayerType\(View\.LAYER_TYPE_NONE, null\);\s*\}')
              .hasMatch(plugin),
          isTrue);
      final root = Directory(
          'third_party/flutter_inappwebview_android/android/src/main/java');
      final software = [
        for (final file in root.listSync(recursive: true).whereType<File>())
          if (file.path.endsWith('.java') &&
              file.readAsStringSync().contains('LAYER_TYPE_SOFTWARE'))
            file.path,
      ];
      expect(software, isEmpty);
    });

    test('the window is what the GPU draws', () {
      // A view with no layer is drawn by the GPU when its window is hardware
      // accelerated: the activity says so.
      final manifest = _read('android/app/src/main/AndroidManifest.xml');
      expect(manifest, contains('android:hardwareAccelerated="true"'));
    });
  });

  group('every start', () {
    test('the web view is made without a fixed wait', () {
      final app = _read('lib/main.dart');
      expect(
          RegExp(r'webViewDelay:\s*firstLaunch \? FirstLaunchGate\.webViewDelay '
                  r': Duration\.zero,')
              .hasMatch(app),
          isTrue,
          reason: 'only a first launch waits, for the takeoff');
      final shell = _read('lib/src/shell_page.dart');
      expect(shell, contains('this.webViewDelay = Duration.zero,'));
      final prepare = shell.substring(
          shell.indexOf('Future<void> _prepareBiometrics() async {'),
          shell.indexOf('Future<void> _readSession() async {'));
      // What the web view needs is read while the app waits, not after.
      expect(prepare.indexOf('final session = _readSession();'), isNonNegative);
      expect(prepare.indexOf('final session = _readSession();'),
          lessThan(prepare.indexOf('await whenWebViewMayStart(')));
      expect(
          prepare,
          contains('firstFrame: '
              'WidgetsBinding.instance.waitUntilFirstFrameRasterized'));
      expect(prepare, isNot(contains('Future<void>.delayed')));
    });

    test('the loader rests until the web view is made, one second at most',
        () {
      final shell = _read('lib/src/shell_page.dart');
      expect(shell, contains('resting: _loader.resting,'));
      final created = shell.indexOf('onWebViewCreated: (controller) {');
      expect(shell.substring(created, created + 400),
          contains('if (_loader.resting) setState(_loader.webViewMade);'));
      expect(
          shell,
          contains('_restTimer = Timer(BootLoaderGate.restLimit, () {\n'
              '      if (mounted && _loader.resting) '
              'setState(_loader.restExpired);'));
    });

    test('on Android the shell\'s loader bakes its glass', () {
      final shell = _read('lib/src/shell_page.dart');
      expect(shell, contains('bakeGlass: Platform.isAndroid,'));
    });
  });

  group('one frame of the loader on Android', () {
    tearDown(() => GlassBake.enabled = false);

    for (final dark in [true, false]) {
      final theme = dark ? 'dark' : 'light';

      testWidgets('$theme: the arrow and the plane are drawn with no blur pass',
          (tester) async {
        _android(tester);

        /// What each 50 ms of a loop asks for.
        Future<List<FrameCost>> loop({required bool bake}) async {
          await tester.pumpWidget(_loader(dark: dark, bakeGlass: bake));
          final frames = <FrameCost>[];
          for (var ms = 0; ms < flightLoaderSeconds * 1000; ms += 50) {
            frames.add(frameCost(tester));
            await tester.pump(const Duration(milliseconds: 50));
          }
          await tester.pumpWidget(const SizedBox());
          return frames;
        }

        final drawn = await loop(bake: false);
        final baked = await loop(bake: true);
        for (final moment in _moments.entries) {
          final frame = moment.value ~/ 50;
          // Measured: 4 for the pearl arrow and 3 for the navy one (its
          // shadows, the light in its bevel), 2 and 3 for the plane.
          expect(drawn[frame].gaussianBlurs, greaterThanOrEqualTo(2),
              reason: '${moment.key}: ${drawn[frame]}');
          expect(baked[frame].gaussianBlurs, 0,
              reason: '${moment.key}: ${baked[frame]}');
          expect(baked[frame].images, greaterThanOrEqualTo(2),
              reason: '${moment.key}: ${baked[frame]}');
        }
        int blurs(List<FrameCost> frames) =>
            frames.fold(0, (sum, frame) => sum + frame.gaussianBlurs);
        // Measured over a loop: 3.5 a frame before and 1.7 now on the night,
        // 3.2 and 1.2 on white. What is left is the arrow becoming the plane
        // and the next arrow coming up, which change on every frame.
        expect(blurs(baked), lessThan(blurs(drawn) * 0.6),
            reason: '${blurs(baked)} of ${blurs(drawn)}');
      });

      testWidgets('$theme: each picture is made once, and they are small',
          (tester) async {
        _android(tester);
        GlassBake.made = 0;
        await tester.pumpWidget(_loader(dark: dark, bakeGlass: true));
        Future<void> aLoop() async {
          for (var ms = 0; ms < flightLoaderSeconds * 1000; ms += 16) {
            await tester.pump(const Duration(milliseconds: 16));
          }
        }

        await aLoop();
        final made = GlassBake.made;
        expect(made, greaterThan(0));
        // The second loop draws what the first made: a picture whose key
        // changed from frame to frame would be made again on every one.
        await aLoop();
        expect(GlassBake.made, made);
        expect(GlassBake.count, made, reason: 'none was let go and made again');
        // Measured: 10 pictures and 2.9 MB on the night, 8 and 3.8 MB on
        // white, on 1080 x 2400.
        expect(GlassBake.pixels * 4, lessThan(8e6));
        await tester.pumpWidget(const SizedBox());
        expect(GlassBake.count, 0, reason: 'they go with the loader');
      });
    }

    testWidgets('baked, the loader draws what it draws unbaked',
        (tester) async {
      _android(tester);
      Future<Uint8List> shot(
          {required bool dark, required int ms, required bool bake}) async {
        await tester.pumpWidget(_loader(dark: dark, bakeGlass: bake));
        await tester.pump();
        if (ms > 0) await tester.pump(Duration(milliseconds: ms));
        if (bake) expect(GlassBake.count, greaterThan(0));
        final layer =
            tester.binding.renderViews.first.debugLayer! as OffsetLayer;
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
        await tester.pumpWidget(const SizedBox());
        return bytes;
      }

      for (final dark in [true, false]) {
        for (final moment in _moments.entries) {
          final drawn = await shot(dark: dark, ms: moment.value, bake: false);
          final baked = await shot(dark: dark, ms: moment.value, bake: true);
          var worst = 0, total = 0, differing = 0;
          for (var i = 0; i < drawn.length; i++) {
            final d = (drawn[i] - baked[i]).abs();
            if (d > worst) worst = d;
            if (d > 0) differing++;
            total += d;
          }
          final where = '${dark ? 'dark' : 'light'}, ${moment.key}';
          // The onboarding's own measure for its baked glass
          // (onboarding_android_cost_test.dart): a few levels of 255 at
          // worst, next to nothing on average.
          expect(worst, lessThanOrEqualTo(6), reason: where);
          expect(total / drawn.length, lessThan(0.05), reason: where);
          // The two were drawn by different means: were they the same
          // picture twice, this test would hold nothing to anything.
          expect(differing, greaterThan(0), reason: where);
        }
      }
    });
  });
}
