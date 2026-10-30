import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/quick_sign_in_offer.dart';

/// The Face ID question after a password sign-in (the owner, 30 Oct 2026: the
/// popup "needs to be simpler"): one line and two answers, the system's own
/// alert on an iPhone, a plain dialog on Android.
void main() {
  Future<bool?> ask(WidgetTester tester, {required TargetPlatform platform, required String label, bool dark = false, required String tap}) async {
    bool? answer;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(platform: platform),
      home: Builder(builder: (context) => Center(child: TextButton(
        onPressed: () async => answer = await showQuickSignInOffer(context, label: label, dark: dark),
        child: const Text('Signed in'),
      ))),
    ));
    await tester.tap(find.text('Signed in'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(tap));
    await tester.pumpAndSettle();
    return answer;
  }

  testWidgets('on an iPhone it is the system alert: one question, Not Now and Use Face ID', (tester) async {
    bool? answer;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(platform: TargetPlatform.iOS),
      home: Builder(builder: (context) => Center(child: TextButton(
        onPressed: () async => answer = await showQuickSignInOffer(context, label: 'Face ID', dark: false),
        child: const Text('Signed in'),
      ))),
    ));
    await tester.tap(find.text('Signed in'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Sign in with Face ID next time?'), findsOneWidget);
    expect(find.byType(Icon), findsNothing);
    final words = tester.widgetList<Text>(find.descendant(of: find.byType(CupertinoAlertDialog), matching: find.byType(Text)))
        .map((text) => text.data).toList();
    expect(words, ['Sign in with Face ID next time?', 'Not Now', 'Use Face ID']);
    await tester.tap(find.text('Use Face ID'));
    await tester.pumpAndSettle();
    expect(answer, isTrue);
    expect(find.byType(CupertinoAlertDialog), findsNothing);
  });

  testWidgets('Not Now on an iPhone is no', (tester) async {
    expect(await ask(tester, platform: TargetPlatform.iOS, label: 'Touch ID', tap: 'Not Now'), isFalse);
  });

  testWidgets('on Android it is a plain dialog in the same words', (tester) async {
    bool? answer;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(platform: TargetPlatform.android),
      home: Builder(builder: (context) => Center(child: TextButton(
        onPressed: () async => answer = await showQuickSignInOffer(context, label: 'fingerprint or face recognition', dark: false),
        child: const Text('Signed in'),
      ))),
    ));
    await tester.tap(find.text('Signed in'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    final words = tester.widgetList<Text>(find.descendant(of: find.byType(AlertDialog), matching: find.byType(Text)))
        .map((text) => text.data).toList();
    expect(words, ['Sign in with your fingerprint or face next time?', 'Not now', 'Turn on']);
    await tester.tap(find.text('Turn on'));
    await tester.pumpAndSettle();
    expect(answer, isTrue);
  });

  testWidgets('closing it any other way is not now', (tester) async {
    bool? answer;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(platform: TargetPlatform.android),
      home: Builder(builder: (context) => Center(child: TextButton(
        onPressed: () async => answer = await showQuickSignInOffer(context, label: 'fingerprint or face recognition', dark: false),
        child: const Text('Signed in'),
      ))),
    ));
    await tester.tap(find.text('Signed in'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(answer, isFalse);
  });

  // The app's own theme is light only, so the dialog takes the student's choice itself.
  testWidgets('it follows the theme the student chose, on an iPhone', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(platform: TargetPlatform.iOS),
      home: const QuickSignInOffer(label: 'Face ID', dark: true),
    ));
    final context = tester.element(find.text('Sign in with Face ID next time?'));
    expect(CupertinoTheme.brightnessOf(context), Brightness.dark);
  });

  testWidgets('it follows the theme the student chose, on Android', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(platform: TargetPlatform.android),
      home: const QuickSignInOffer(label: 'fingerprint or face recognition', dark: true),
    ));
    final context = tester.element(find.text('Sign in with your fingerprint or face next time?'));
    expect(Theme.of(context).colorScheme.brightness, Brightness.dark);
  });
}
