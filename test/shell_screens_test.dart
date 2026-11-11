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
            bool resting = false,
            bool bakeGlass = false,
            VoidCallback? onGone}) =>
        _phone(Stack(children: [
          ShellLoadingLayer(
              showing: showing,
              covered: false,
              dark: true,
              resting: resting,
              bakeGlass: bakeGlass,
              onGone: onGone ?? () {}),
        ]));

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

    testWidgets('the loader and the onboarding each bake for themselves',
        (tester) async {
      addTearDown(() => GlassBake.enabled = false);
      // A first launch: the onboarding bakes, the loader under it too.
      GlassBake.enabled = true;
      await tester.pumpWidget(layer(bakeGlass: true));
      // The portal is ready while the onboarding still runs: the loader goes,
      // the onboarding's glass stays baked.
      await tester.pumpWidget(const SizedBox());
      expect(GlassBake.enabled, isTrue);
      // The other way round: the onboarding ends on a loader still up.
      await tester.pumpWidget(layer(bakeGlass: true));
      GlassBake.enabled = false;
      expect(GlassBake.enabled, isTrue);
      await tester.pumpWidget(const SizedBox());
      expect(GlassBake.enabled, isFalse);
    });
  });
}
