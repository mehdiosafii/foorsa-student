import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/flicker_spinner.dart';
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
    final centre = tester.getCenter(find.byType(FlickerSpinner));
    // The web page starts under the status bar and runs to the bottom edge.
    expect(centre.dy, closeTo(47 + (844 - 47) / 2, 0.5));
    expect(centre.dx, closeTo(390 / 2, 0.5));
    expect(_ground(tester, ShellLoadingScreen), const Color(0xFF183250));
    await tester.pumpWidget(_phone(const ShellLoadingScreen(dark: false)));
    expect(_ground(tester, ShellLoadingScreen), Colors.white);
  });
}
