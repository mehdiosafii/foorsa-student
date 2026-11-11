import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/onboarding/flight_loader.dart';
import 'package:foorsa_student/src/onboarding/glass.dart';
import 'package:foorsa_student/src/shell_screens.dart';

Widget _phone(Widget child) => MaterialApp(home: child);

/// A 390 x 844 iPhone with its status bar and home indicator.
void _iphone(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
  addTearDown(tester.view.reset);
}

Color? _ground(WidgetTester tester, Type screen) {
  final box = tester.widget<Container>(
      find.descendant(of: find.byType(screen), matching: find.byType(Container)).first);
  final decoration = box.decoration;
  if (decoration is BoxDecoration) return decoration.color ?? decoration.gradient?.colors.first;
  return box.color;
}

void main() {
  testWidgets('no connection is said in English, with the Arabic under it', (tester) async {
    _iphone(tester);
    var retried = 0;
    await tester.pumpWidget(_phone(ShellOfflineScreen(onRetry: () => retried++, dark: false)));
    expect(find.text('No internet connection'), findsOneWidget);
    expect(find.text('لا يوجد اتصال بالإنترنت'), findsOneWidget);
    expect(find.textContaining('reconnects by itself'), findsOneWidget);
    expect(find.textContaining('Pas de connexion'), findsNothing);
    await tester.tap(find.text('Try again'));
    expect(retried, 1);
  });

  testWidgets('the offline screen follows the theme the student chose', (tester) async {
    _iphone(tester);
    await tester.pumpWidget(_phone(ShellOfflineScreen(onRetry: () {}, dark: false)));
    final light = _ground(tester, ShellOfflineScreen)!;
    await tester.pumpWidget(_phone(ShellOfflineScreen(onRetry: () {}, dark: true)));
    final dark = _ground(tester, ShellOfflineScreen)!;
    expect(light.computeLuminance(), greaterThan(0.8));
    expect(dark.computeLuminance(), lessThan(0.05));
  });

  testWidgets('the loader sits where the portal draws its own, under the status bar', (tester) async {
    _iphone(tester);
    await tester.pumpWidget(_phone(const ShellLoadingScreen(dark: true)));
    final centre = tester.getCenter(find.byType(FlightLoader));
    // The web page starts under the status bar and runs to the bottom edge.
    expect(centre.dy, closeTo(47 + (844 - 47) / 2, 0.5));
    expect(centre.dx, closeTo(390 / 2, 0.5));
    expect(_ground(tester, ShellLoadingScreen), const Color(0xFF183250));
    await tester.pumpWidget(_phone(const ShellLoadingScreen(dark: false)));
    expect(_ground(tester, ShellLoadingScreen), Colors.white);
  });

  group('the loading screen over the web view', () {
    Widget layer(
            {bool showing = true,
            bool covered = false,
            bool resting = false,
            bool bakeGlass = false,
            VoidCallback? onGone}) =>
        _phone(Stack(children: [
          ShellLoadingLayer(
              showing: showing,
              covered: covered,
              dark: true,
              resting: resting,
              bakeGlass: bakeGlass,
              onGone: onGone ?? () {}),
        ]));

    double clock(WidgetTester tester) => (tester
            .widget<CustomPaint>(find.descendant(
                of: find.byType(FlightLoader),
                matching: find.byType(CustomPaint)))
            .painter! as FlightLoaderPainter)
        .clock
        .value;

    testWidgets('rests on the arrow while the web view is made, then plays',
        (tester) async {
      await tester.pumpWidget(layer(resting: true));
      expect(tester.widget<FlightLoader>(find.byType(FlightLoader)).resting, isTrue);
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.binding.hasScheduledFrame, isFalse,
          reason: 'nothing moves, so nothing is drawn again');
      await tester.pumpWidget(layer());
      expect(tester.widget<FlightLoader>(find.byType(FlightLoader)).resting, isFalse);
      expect(tester.binding.hasScheduledFrame, isTrue);
    });

    testWidgets('let go of while it still rests, it fades and says so',
        (tester) async {
      var gone = 0;
      await tester.pumpWidget(layer(resting: true));
      await tester.pumpWidget(
          layer(resting: true, showing: false, onGone: () => gone++));
      await tester.pump(const Duration(milliseconds: 240));
      await tester.pump(const Duration(milliseconds: 16));
      expect(gone, 1);
    });

    // A first launch: the loader does not rest (BootLoaderGate's rests), it
    // is under the onboarding, and a slow sign-in may still need it when the
    // onboarding fades onto the shell.
    testWidgets('uncovered by the onboarding, it plays from its first picture',
        (tester) async {
      // As the app builds it: before its first frame, not inside one
      // (runApp mounts the tree from a timer). A clock started inside a
      // frame counts from that frame, even while it is not ticking.
      var up = false;
      late StateSetter put;
      await tester.pumpWidget(StatefulBuilder(builder: (context, setState) {
        put = setState;
        return up ? layer(covered: true) : const SizedBox();
      }));
      put(() => up = true);
      tester.binding.buildOwner!.buildScope(tester.binding.rootElement!);
      expect(find.byType(FlightLoader), findsOneWidget);
      await tester.pump();
      // The takeoff and the steps.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 365));
      }
      // The onboarding fades onto the shell: the loader is seen.
      await tester.pumpWidget(StatefulBuilder(
          builder: (context, setState) => layer()));
      await tester.pump();
      expect(clock(tester), 0);
      await tester.pump(const Duration(milliseconds: 160));
      expect(clock(tester), closeTo(0.16 / flightLoaderSeconds, 0.001));
    });

    testWidgets('its rest ended while it was covered, it still plays from its first picture',
        (tester) async {
      // Not what a first launch does any more (it does not rest), but a
      // loader let go of its rest out of sight must not have been counting.
      await tester.pumpWidget(layer(covered: true, resting: true));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(layer(covered: true));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 365));
      }
      await tester.pumpWidget(layer());
      await tester.pump();
      expect(clock(tester), 0);
      await tester.pump(const Duration(milliseconds: 160));
      expect(clock(tester), closeTo(0.16 / flightLoaderSeconds, 0.001));
    });

    testWidgets('on Android its glass is baked while it is up, no longer',
        (tester) async {
      addTearDown(() => GlassBake.enabled = false);
      await tester.pumpWidget(layer());
      expect(GlassBake.enabled, isFalse, reason: 'iOS draws as before');
      await tester.pumpWidget(const SizedBox());

      await tester.pumpWidget(layer(bakeGlass: true));
      expect(GlassBake.enabled, isTrue);
      await tester.pump(const Duration(milliseconds: 100));
      expect(GlassBake.count, greaterThan(0));
      // The shell takes the loader away once it has faded: its pictures go.
      await tester.pumpWidget(const SizedBox());
      expect(GlassBake.enabled, isFalse);
      expect(GlassBake.count, 0);
    });

    testWidgets('the shell redrawing it does not hold the pictures twice',
        (tester) async {
      addTearDown(() => GlassBake.enabled = false);
      // The shell rebuilds the layer on every change of its own (the
      // portal's colour, the loader let go of, the rest ending).
      await tester.pumpWidget(layer(bakeGlass: true, resting: true));
      await tester.pumpWidget(layer(bakeGlass: true));
      await tester.pumpWidget(layer(bakeGlass: true, showing: false));
      await tester.pump(const Duration(milliseconds: 100));
      expect(GlassBake.enabled, isTrue);
      await tester.pumpWidget(const SizedBox());
      expect(GlassBake.enabled, isFalse, reason: 'one hold, one release');
      expect(GlassBake.count, 0);
    });

    testWidgets('the loader and the onboarding each keep baking on for themselves',
        (tester) async {
      addTearDown(() => GlassBake.enabled = false);
      // A first launch: the onboarding bakes, the loader under it too.
      GlassBake.enabled = true;
      await tester.pumpWidget(layer(bakeGlass: true));
      await tester.pump(const Duration(milliseconds: 100));
      expect(GlassBake.count, greaterThan(0));
      // The portal is ready while the onboarding still runs: the loader goes,
      // the onboarding's glass stays baked.
      await tester.pumpWidget(const SizedBox());
      expect(GlassBake.enabled, isTrue);
      expect(GlassBake.count, greaterThan(0));

      // The other way round: the onboarding ends on a loader still up. Its
      // pictures go with it, all of them, and the loader, still baking,
      // makes its own few again.
      await tester.pumpWidget(layer(bakeGlass: true));
      await tester.pump(const Duration(milliseconds: 100));
      GlassBake.enabled = false;
      expect(GlassBake.enabled, isTrue);
      expect(GlassBake.count, 0);
      await tester.pump(const Duration(milliseconds: 100));
      expect(GlassBake.count, greaterThan(0));
      await tester.pumpWidget(const SizedBox());
      expect(GlassBake.enabled, isFalse);
      expect(GlassBake.count, 0);
    });
  });
}
