// The app's own screens around the portal speak the student's language too:
// no connection, the quick sign-in question, the call screen, the scanner.

import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/app_language.dart';
import 'package:foorsa_student/src/guided_scanner/scan_document_profile.dart';
import 'package:foorsa_student/src/guided_scanner/scan_guidance.dart';
import 'package:foorsa_student/src/guided_scanner/scan_text_reading.dart';
import 'package:foorsa_student/src/onboarding/flight_loader.dart';
import 'package:foorsa_student/src/quick_sign_in_offer.dart';
import 'package:foorsa_student/src/shell_screens.dart';
import 'package:foorsa_student/src/student_calls.dart';

Widget _in(AppLanguage language, Widget child, {TargetPlatform? platform}) =>
    MaterialApp(
      theme: ThemeData(platform: platform),
      builder: (context, child) =>
          AppLanguageScope(language: language, child: child!),
      home: child,
    );

void main() {
  testWidgets('no connection, said once in French, and in Arabic right to left',
      (tester) async {
    await tester.pumpWidget(
        _in(AppLanguage.fr, ShellOfflineScreen(onRetry: () {}, dark: false)));
    expect(find.text('Pas de connexion Internet'), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);
    expect(find.textContaining('se reconnecte'), findsOneWidget);
    expect(find.text('No internet connection'), findsNothing);
    expect(find.text('لا يوجد اتصال بالإنترنت'), findsNothing);

    await tester.pumpWidget(
        _in(AppLanguage.ar, ShellOfflineScreen(onRetry: () {}, dark: true)));
    final title = find.text('لا يوجد اتصال بالإنترنت');
    expect(title, findsOneWidget);
    expect(Directionality.of(tester.element(title)), TextDirection.rtl);
    expect(find.text('إعادة المحاولة'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
  });

  testWidgets('the loader is named in the student\'s language', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
        _in(AppLanguage.ar, const Center(child: FlightLoader())));
    expect(find.bySemanticsLabel('جارٍ التحميل'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    semantics.dispose();
  });

  test('the quick sign-in question keeps Face ID\'s name in every language',
      () {
    expect(quickSignInQuestion('Face ID', AppLanguage.fr),
        'Se connecter avec Face ID la prochaine fois ?');
    expect(quickSignInQuestion('Touch ID', AppLanguage.ar),
        'تسجيل الدخول باستخدام Touch ID في المرة القادمة؟');
    expect(
        quickSignInQuestion('fingerprint or face recognition', AppLanguage.ar),
        'تسجيل الدخول ببصمتك أو بوجهك في المرة القادمة؟');
  });

  testWidgets('on an iPhone, in French: Plus tard and Utiliser Face ID',
      (tester) async {
    await tester.pumpWidget(_in(AppLanguage.fr,
        const QuickSignInOffer(label: 'Face ID', dark: false),
        platform: TargetPlatform.iOS));
    final words = tester
        .widgetList<Text>(find.descendant(
            of: find.byType(CupertinoAlertDialog), matching: find.byType(Text)))
        .map((text) => text.data)
        .toList();
    expect(words, [
      'Se connecter avec Face ID la prochaine fois ?',
      'Plus tard',
      'Utiliser Face ID'
    ]);
  });

  testWidgets('on Android, in Arabic, right to left', (tester) async {
    await tester.pumpWidget(_in(
        AppLanguage.ar,
        const QuickSignInOffer(
            label: 'fingerprint or face recognition', dark: false),
        platform: TargetPlatform.android));
    final words = tester
        .widgetList<Text>(find.descendant(
            of: find.byType(AlertDialog), matching: find.byType(Text)))
        .map((text) => text.data)
        .toList();
    expect(words,
        ['تسجيل الدخول ببصمتك أو بوجهك في المرة القادمة؟', 'ليس الآن', 'تفعيل']);
    expect(Directionality.of(tester.element(find.text('تفعيل'))),
        TextDirection.rtl);
  });

  test('a call\'s status is said in the language, and stays English as data',
      () {
    expect(callStatusText('Incoming call', AppLanguage.fr), 'Appel entrant');
    expect(callStatusText('Connecting…', AppLanguage.ar), 'جارٍ الاتصال…');
    expect(callStatusText('Connected', AppLanguage.en), 'Connected');
    // Anything the app does not know is shown as it came.
    expect(callStatusText('Ringing', AppLanguage.fr), 'Ringing');
  });

  test('every scanner instruction is written in French and Arabic', () {
    for (final language in [AppLanguage.fr, AppLanguage.ar]) {
      for (final hint in ScanHint.values) {
        final said = hint.labelIn(language);
        expect(said.trim(), isNotEmpty, reason: '${hint.name} $language');
        expect(said, isNot(hint.label), reason: '${hint.name} $language');
      }
      for (final guidance in ScanTextGuidance.values) {
        for (final kind in ScanPaperKind.values) {
          final copy = guidance.copy(kind, language);
          final english = guidance.copy(kind);
          for (final (own, source) in [
            (copy.title, english.title),
            (copy.detail, english.detail),
            (copy.compact, english.compact),
          ]) {
            expect(own.trim(), isNotEmpty,
                reason: '${guidance.name} ${kind.name} $language');
            expect(own, isNot(source),
                reason: '${guidance.name} ${kind.name} $language');
          }
        }
      }
    }
    // English is as it was.
    expect(ScanHint.position.label, 'Align all four edges');
    expect(ScanTextGuidance.reading.copy(ScanPaperKind.passport).detail,
        'Reading the two lines at the bottom…');
  });

  test('what the portal does not say about a paper, the app says in the language',
      () {
    final passport =
        GuidedDocumentProfile.fromPortal('passport', AppLanguage.fr);
    expect(passport.title, 'Passeport');
    expect(passport.instruction, contains('deux lignes'));
    final medical = GuidedDocumentProfile.fromPortal(
        {'documentKey': 'medical_check'}, AppLanguage.ar);
    expect(medical.pagesHintIn(AppLanguage.ar), contains('الصفحة 2'));
    // What the portal says is kept as it says it.
    final named = GuidedDocumentProfile.fromPortal(
        {'documentKey': 'identity', 'title': 'Passeport'}, AppLanguage.ar);
    expect(named.title, 'Passeport');
    // English unchanged.
    expect(GuidedDocumentProfile.fromPortal('passport').title, 'Passport');
  });

  test(
      'every permission the iPhone asks for is worded in French and Arabic, '
      'and the app says it speaks them', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    final keys = RegExp(r'<key>(NS\w+UsageDescription)</key>')
        .allMatches(plist)
        .map((m) => m[1]!)
        .toSet();
    expect(keys, isNotEmpty);
    for (final language in ['fr', 'ar']) {
      final strings =
          File('ios/Runner/$language.lproj/InfoPlist.strings').readAsStringSync();
      for (final key in keys) {
        expect(RegExp('"$key" = "[^"]+";').hasMatch(strings), isTrue,
            reason: '$key in $language');
      }
    }
    for (final language in ['en', 'fr', 'ar']) {
      expect(plist, contains('<string>$language</string>'));
    }
    expect(plist, contains('<key>CFBundleLocalizations</key>'));
    final project =
        File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    expect(project, contains('path = fr.lproj/InfoPlist.strings;'));
    expect(project, contains('path = ar.lproj/InfoPlist.strings;'));
    expect(project, contains('/* InfoPlist.strings in Resources */,'));
  });

  test('Android lays the app\'s own screens out right to left in Arabic', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('android:supportsRtl="true"'));
  });
}
