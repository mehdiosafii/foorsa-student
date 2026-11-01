import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/app_language.dart';

/// The student's language in the app (the owner, 1 Nov 2026): English, the
/// default, French or Arabic, kept on the phone and handed to the portal.
void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('language_'));
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  AppLanguageStore store() => AppLanguageStore(directory: () async => dir);

  test('reads a language as the portal does, and anything else as none', () {
    expect(AppLanguage.parse('en'), AppLanguage.en);
    expect(AppLanguage.parse('fr'), AppLanguage.fr);
    expect(AppLanguage.parse(' AR '), AppLanguage.ar);
    // parseStudentLanguage reads the first two letters.
    expect(AppLanguage.parse('fr-FR'), AppLanguage.fr);
    expect(AppLanguage.parse('ar-MA'), AppLanguage.ar);
    expect(AppLanguage.parse('de'), isNull);
    expect(AppLanguage.parse('e'), isNull);
    expect(AppLanguage.parse(''), isNull);
    expect(AppLanguage.parse(null), isNull);
    expect(AppLanguage.parse(3), isNull);
  });

  test('each language is named in itself, and only Arabic reads right to left',
      () {
    expect([for (final l in AppLanguage.values) l.nativeName],
        ['English', 'Français', 'العربية']);
    expect(AppLanguage.ar.direction, TextDirection.rtl);
    expect(AppLanguage.en.direction, TextDirection.ltr);
    expect(AppLanguage.fr.direction, TextDirection.ltr);
    expect([for (final l in AppLanguage.values) l.code], ['en', 'fr', 'ar']);
  });

  test('the language kept on the phone comes back as it was', () async {
    expect(await store().read(), isNull);
    for (final language in AppLanguage.values) {
      await store().write(StoredLanguage(language));
      expect(await store().read(), StoredLanguage(language));
    }
    await store().write(
        const StoredLanguage(AppLanguage.ar, handOver: 'abcdefgh1234'));
    expect(await store().read(),
        const StoredLanguage(AppLanguage.ar, handOver: 'abcdefgh1234'));
    await store().write(null);
    expect(await store().read(), isNull);
  });

  test('a damaged record is no choice, never an error', () {
    expect(AppLanguageStore.parse('de'), isNull);
    expect(AppLanguageStore.parse('french'), isNull);
    expect(AppLanguageStore.parse(''), isNull);
    // A stamp that is not one is dropped, the language kept.
    expect(AppLanguageStore.parse('fr\nhandover <script>'),
        const StoredLanguage(AppLanguage.fr));
  });

  test('a folder it cannot read never stops the app', () async {
    final broken = AppLanguageStore(
        directory: () async => throw const FileSystemException('no disk'));
    expect(await broken.read(), isNull);
    await broken.write(const StoredLanguage(AppLanguage.fr));
  });

  group('the app\'s language', () {
    test('English until somebody chooses', () async {
      final shell = ShellLanguage(store: store());
      await shell.load();
      expect(shell.chosen, isNull);
      expect(shell.current, AppLanguage.en);
    });

    test('chosen in the onboarding: spoken at once, kept, and handed over',
        () async {
      final shell = ShellLanguage(store: store());
      var told = 0;
      shell.addListener(() => told++);
      shell.chooseInOnboarding(AppLanguage.ar);
      expect(shell.current, AppLanguage.ar);
      expect(shell.handOver, isNotNull);
      expect(told, 1);
      await shell.flush();
      final next = ShellLanguage(store: store());
      await next.load();
      expect(next.current, AppLanguage.ar);
      expect(next.handOver, shell.handOver,
          reason: 'a restart still hands it to a portal that never got it');
    });

    test(
        'a page that started before the choice cannot take it back; the '
        'portal saying the choice ends the hand-over', () async {
      var now = DateTime(2026, 11, 1, 9);
      final shell = ShellLanguage(store: store(), clock: () => now);
      shell.chooseInOnboarding(AppLanguage.fr);
      expect(shell.portalSays('en'), isFalse);
      expect(shell.current, AppLanguage.fr);
      expect(shell.portalSays('fr'), isTrue);
      expect(shell.handOver, isNull);
      // From then on the portal leads: Profile › Settings.
      expect(shell.portalSays('ar'), isTrue);
      expect(shell.current, AppLanguage.ar);
      await shell.flush();
      expect(await store().read(), const StoredLanguage(AppLanguage.ar));
    });

    test('a hand-over the portal never confirms does not hold the app for good',
        () async {
      var now = DateTime(2026, 11, 1, 9);
      final shell = ShellLanguage(store: store(), clock: () => now);
      shell.chooseInOnboarding(AppLanguage.fr);
      now = now.add(ShellLanguage.handOverWindow);
      expect(shell.portalSays('ar'), isTrue);
      expect(shell.current, AppLanguage.ar);
      expect(shell.handOver, isNull);
      await shell.flush();
    });

    test('the portal\'s word is taken only when it is a language', () async {
      final shell = ShellLanguage(store: store());
      expect(shell.portalSays('klingon'), isFalse);
      expect(shell.portalSays(null), isFalse);
      expect(shell.chosen, isNull);
      expect(shell.portalSays('fr'), isTrue);
      expect(shell.current, AppLanguage.fr);
      // The word is kept on the phone: let that write finish before the
      // folder is removed, or the removal races it ("Directory not empty").
      await shell.flush();
    });
  });

  group('the script that gives the portal the language', () {
    const origin = 'https://student.foorsa.ma';

    test('runs only on the portal, and writes only a language', () {
      for (final language in AppLanguage.values) {
        final script =
            portalLanguageScript(origin: origin, language: language);
        expect(script, contains('location.origin !== "$origin"'));
        expect(script, contains('var language = "${language.code}";'));
        expect(script, contains('"foorsa_portal_language"'));
        // Without a hand-over it fills only an empty choice, so a change the
        // student makes in the portal's Settings is never undone.
        expect(script, contains('var handOver = null;'));
        expect(script, isNot(contains('foorsa:language')));
      }
    });

    test('a hand-over is written once, by its stamp, and announced to an open page',
        () {
      final script = portalLanguageScript(
          origin: origin,
          language: AppLanguage.ar,
          handOver: 'stamp1234',
          announce: true);
      expect(script, contains('var handOver = "stamp1234";'));
      expect(script, contains('localStorage.getItem(mark) !== handOver'));
      expect(
          script,
          contains(
              'new CustomEvent("foorsa:language", { detail: language })'));
    });

    test('nothing is written for a phone where nobody has chosen', () async {
      final shell = ShellLanguage(store: store());
      await shell.load();
      expect(portalLanguageScriptFor(shell, origin), isNull);
      // A word that is not a language changes nothing.
      shell.portalSays('de');
      expect(portalLanguageScriptFor(shell, origin), isNull);
      shell.portalSays('fr');
      expect(portalLanguageScriptFor(shell, origin),
          contains('var language = "fr";'));
      await shell.flush();
    });
  });
}
