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
