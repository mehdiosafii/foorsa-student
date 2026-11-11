import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/onboarding/flight_loader.dart';

FlightLoaderPainter _painter(WidgetTester tester) => tester
    .widget<CustomPaint>(find.descendant(
        of: find.byType(FlightLoader), matching: find.byType(CustomPaint)))
    .painter! as FlightLoaderPainter;

void main() {
  // The owner, 31 Oct 2026: the loading screen is the arrow that turns into
  // the plane, not the dots.
  testWidgets('loops the arrow into the plane and back, in both themes', (tester) async {
    for (final dark in [true, false]) {
      await tester.pumpWidget(MaterialApp(home: Center(child: FlightLoader(size: 64, dark: dark))));
      expect(tester.getSize(find.byType(FlightLoader)), const Size.square(64 * 2.6));
      // Every beat of two loops paints without a fault.
      for (var i = 0; i < 64; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.takeException(), isNull);
      expect(_painter(tester).dark, dark);
    }
  });

  // The owner, 1 Nov 2026: "the loading screen shows logo stairs, it should
  // logo airplane than stairs". For a day the loader was a 6.8 s story whose
  // second form was stairs, so a load of a second or two showed the logo
  // turning into stairs. It is the arrow turning into the plane again, on the
  // portal's and the CRM's timing (foorsa-reward src/portal/flightLoaderModel.ts:
  // LOOP_SECONDS 3.2, CALM_SECONDS 4.4), so the hand-over to the web shows one
  // sign. Change these with that file.
  test('plays the portal\'s loop: the arrow becomes the plane, 3.2 s a loop', () {
    expect(flightLoaderSeconds, 3.2);
    expect(flightLoaderCalmSeconds, 4.4);
  });

  testWidgets('is named for a screen reader', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Center(child: FlightLoader())));
    expect(find.bySemanticsLabel('Loading'), findsOneWidget);
  });

  testWidgets('under Reduce Motion it changes where it stands', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: Center(child: FlightLoader()))));
    expect(_painter(tester).calm, isTrue);
    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);
  });

  // The app's loading screen while its web view is made
  // (boot_loader_gate.dart): the arrow alone, and nothing asked of the phone.
  testWidgets('resting, it is the loop\'s first picture and asks for no frame',
      (tester) async {
    Widget loader({required bool resting, bool still = false}) => MaterialApp(
        home: MediaQuery(
            data: MediaQueryData(disableAnimations: still),
            child: Center(child: FlightLoader(resting: resting))));
    for (final still in [false, true]) {
      await tester.pumpWidget(loader(resting: true, still: still));
      await tester.pump(const Duration(milliseconds: 700));
      expect(_painter(tester).clock.value, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);

      // It plays from that picture, not from where a clock would have got to.
      await tester.pumpWidget(loader(resting: false, still: still));
      expect(_painter(tester).clock.value, 0);
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final loop = still ? flightLoaderCalmSeconds : flightLoaderSeconds;
      expect(_painter(tester).clock.value, closeTo(0.4 / loop, 0.001));

      // And back, should it ever rest again.
      await tester.pumpWidget(loader(resting: true, still: still));
      expect(_painter(tester).clock.value, 0);
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.pumpWidget(const SizedBox());
    }
  });

  // The frames after a web view is made may come late (on Android the one
  // that first shows it is drawn twice). A clock started inside a frame
  // counts from that frame, so the loop opened as far in as the next frame
  // was late.
  testWidgets('let go of its rest, it opens on its first picture however late the next frame',
      (tester) async {
    Widget loader({required bool resting}) =>
        MaterialApp(home: Center(child: FlightLoader(resting: resting)));
    await tester.pumpWidget(loader(resting: true));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpWidget(loader(resting: false));
    // The next frame, 300 ms late.
    await tester.pump(const Duration(milliseconds: 300));
    expect(_painter(tester).clock.value, 0);
    await tester.pump(const Duration(milliseconds: 160));
    expect(_painter(tester).clock.value, closeTo(0.16 / flightLoaderSeconds, 0.001));
  });

  testWidgets('it plays at once unless told to rest', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Center(child: FlightLoader())));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    expect(_painter(tester).clock.value, closeTo(0.1, 0.001));
  });
}
