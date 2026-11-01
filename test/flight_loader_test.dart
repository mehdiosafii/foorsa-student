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
}
