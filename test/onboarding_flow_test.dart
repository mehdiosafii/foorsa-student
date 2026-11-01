import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/app_language.dart';
import 'package:foorsa_student/src/onboarding/onboarding_config.dart';
import 'package:foorsa_student/src/onboarding/onboarding_flow.dart';
import 'package:foorsa_student/src/onboarding/onboarding_permissions.dart';
import 'package:permission_handler/permission_handler.dart';

class _Phone implements BoardingPermissions {
  _Phone([this.states = const {}]);
  final Map<BoardingAccess, AccessState> states;

  @override
  Future<AccessState> status(BoardingAccess access) async {
    final state = states[access];
    if (state == null) return AccessState.askable;
    return state;
  }

  @override
  Future<AccessState> request(BoardingAccess access) async =>
      AccessState.granted;
}

class _Broken extends _Phone {
  @override
  Future<AccessState> status(BoardingAccess access) =>
      throw StateError('plugin missing');
}

void main() {
  test(
      'a new phone is asked everything, most useful first, between the welcome and the pass',
      () async {
    final plan = await planBoarding(_Phone(), isIOS: false, asksToTrack: false);
    expect(plan.steps, [
      BoardingStep.language,
      BoardingStep.welcome,
      BoardingStep.notifications,
      BoardingStep.camera,
      BoardingStep.microphone,
      BoardingStep.location,
      BoardingStep.boarding,
    ]);
  });

  test(
      'tracking is asked only on an iPhone, and only when the build asks to track',
      () async {
    Future<bool> asks({required bool iOS, required bool track}) async =>
        (await planBoarding(_Phone(), isIOS: iOS, asksToTrack: track))
            .steps
            .contains(BoardingStep.tracking);
    expect(await asks(iOS: true, track: true), isTrue);
    expect(await asks(iOS: true, track: false), isFalse);
    expect(await asks(iOS: false, track: true), isFalse);
    final plan = await planBoarding(_Phone(), isIOS: true, asksToTrack: true);
    expect(plan.steps[plan.steps.length - 2], BoardingStep.tracking,
        reason: 'tracking comes last');
  });

  test('no screen is shown before a prompt that will not come', () async {
    final plan = await planBoarding(
      _Phone({
        BoardingAccess.notifications: AccessState.granted,
        BoardingAccess.camera: AccessState.denied,
        BoardingAccess.microphone: AccessState.unavailable,
      }),
      isIOS: true,
      asksToTrack: false,
    );
    expect(plan.steps, [
      BoardingStep.language,
      BoardingStep.welcome,
      BoardingStep.location,
      BoardingStep.boarding
    ]);
    expect(plan.states[BoardingAccess.notifications], AccessState.granted);
  });

  test('a permission plugin that cannot answer never holds the app back',
      () async {
    final plan = await planBoarding(_Broken(), isIOS: true, asksToTrack: true);
    expect(plan.steps, [
      BoardingStep.language,
      BoardingStep.welcome,
      BoardingStep.boarding
    ]);
  });

  test(
      'a screen before a permission prompt leads on as Continue, never Allow, and offers no way round it',
      () {
    for (final step in BoardingStep.values) {
      final copy = copyFor(step);
      for (final words in [copy.action, copy.hint, copy.spoken, copy.body]) {
        expect(words.toLowerCase(), isNot(contains('allow')),
            reason: step.name);
        expect(
            words.toLowerCase(),
            isNot(anyOf(
                contains('skip'), contains('not now'), contains('later'))),
            reason: step.name);
      }
      if (step.access != null) {
        expect(copy.action, 'Continue', reason: step.name);
      }
    }
  });

  test('every screen is one headline, one line under it and one gesture', () {
    for (final step in BoardingStep.values) {
      final copy = copyFor(step);
      expect(copy.headline.endsWith('.'), isTrue,
          reason: 'the portal writes its headlines as sentences');
      // Short enough to read at a glance: two lines on the smallest phone.
      expect(copy.headline.length, lessThanOrEqualTo(36), reason: step.name);
      expect(copy.body.length, lessThanOrEqualTo(72), reason: step.name);
      expect(copy.body.contains('\n'), isFalse, reason: step.name);
      // The gesture is said in a few words, as a phone says it.
      expect(copy.hint.length, lessThanOrEqualTo(32), reason: step.name);
      expect(copy.hint.endsWith('.'), isFalse, reason: step.name);
    }
  });

  test(
      'every screen says exactly what to do, the gesture first, and tells a '
      'screen reader too', () {
    for (final step in BoardingStep.values) {
      final copy = copyFor(step);
      // Verb first, then the object it is done to.
      expect(copy.hint.split(' ').first, isIn(['Swipe', 'Tap', 'Drag', 'Pull']),
          reason: step.name);
      expect(copy.hint.split(' ').length, greaterThanOrEqualTo(3),
          reason: '${step.name}: the gesture and its object');
      // A screen reader's double tap does what the gesture does, and the
      // student is told so after the object's name.
      expect(copy.spoken, startsWith('Double-tap '), reason: step.name);
      expect(copy.spoken.endsWith('.'), isTrue, reason: step.name);
      expect(copy.spoken.length, lessThanOrEqualTo(56), reason: step.name);
    }
  });

  test('permission_handler answers map to what the onboarding can still ask',
      () {
    expect(accessStateOf(PermissionStatus.denied), AccessState.askable);
    expect(accessStateOf(PermissionStatus.granted), AccessState.granted);
    expect(accessStateOf(PermissionStatus.limited), AccessState.granted);
    expect(accessStateOf(PermissionStatus.provisional), AccessState.granted);
    expect(
        accessStateOf(PermissionStatus.permanentlyDenied), AccessState.denied);
    expect(accessStateOf(PermissionStatus.restricted), AccessState.unavailable);
  });

  test(
      'tracking stays off until the app measures ads and its privacy notice says so',
      () {
    // The privacy notice says the Student app does not use advertising
    // tracking, and the privacy manifest says NSPrivacyTracking false. Turning
    // this on is a decision, with those changing in the same commit
    // (docs/first-launch-onboarding.md).
    expect(OnboardingConfig.asksToTrack, isFalse);
  });

  group('in English, French and Arabic', () {
    List<String> words(BoardingCopy c) =>
        [c.headline, c.body, c.action, c.hint, c.spoken];

    test('the language comes first, whatever the phone has already answered',
        () async {
      for (final phone in [
        _Phone(),
        _Phone({for (final a in BoardingAccess.values) a: AccessState.granted}),
        _Broken(),
      ]) {
        final plan = await planBoarding(phone, isIOS: true, asksToTrack: true);
        expect(plan.steps.take(2),
            [BoardingStep.language, BoardingStep.welcome]);
        expect(plan.steps.last, BoardingStep.boarding);
      }
    });

    test('every step has every word in each language, none empty', () {
      for (final language in AppLanguage.values) {
        for (final step in BoardingStep.values) {
          final copy = copyFor(step, language);
          for (final w in words(copy)) {
            expect(w.trim(), isNotEmpty, reason: '${step.name} ${language.name}');
            expect(w, w.trim(), reason: '${step.name} ${language.name}');
            expect(w.contains('\n'), isFalse,
                reason: '${step.name} ${language.name}');
          }
          expect(copy.headline.endsWith('.'), isTrue,
              reason: '${step.name} ${language.name}: a sentence');
          expect(copy.spoken.endsWith('.'), isTrue,
              reason: '${step.name} ${language.name}');
          expect(copy.hint.endsWith('.'), isFalse,
              reason: '${step.name} ${language.name}: said as a phone says it');
          if (language != AppLanguage.en) {
            final english = words(copyFor(step));
            final own = words(copy);
            for (var i = 0; i < own.length; i++) {
              expect(own[i], isNot(english[i]),
                  reason: '${step.name} ${language.name}: translated, '
                      'not left in English');
            }
          }
        }
      }
    });

    test('French is written as French apps write it', () {
      for (final step in BoardingStep.values) {
        final copy = copyFor(step, AppLanguage.fr);
        for (final w in words(copy)) {
          expect(w.contains("'"), isFalse,
              reason: '${step.name}: the typographic apostrophe, ’');
          // A narrow no-break space before ? ! ;, a no-break space before :.
          expect(RegExp(r'[^ ][?!;]').hasMatch(w), isFalse,
              reason: step.name);
          expect(RegExp(r'[^ ]:').hasMatch(w), isFalse,
              reason: step.name);
          expect(w.toLowerCase(), isNot(contains(' tu ')), reason: step.name);
        }
        // What to do, the gesture first.
        expect(copy.hint.split(' ').first,
            isIn(['Touchez', 'Glissez', 'Tirez']),
            reason: step.name);
        expect(copy.spoken, startsWith('Touchez deux fois '),
            reason: step.name);
        if (step.access != null) {
          expect(copy.action, 'Continuer', reason: step.name);
        }
      }
    });

    test(
        'Arabic is written in Arabic, with its own punctuation, Latin digits '
        'and Foorsa as فرصة', () {
      final arabic = RegExp(r'[؀-ۿ]');
      for (final step in BoardingStep.values) {
        final copy = copyFor(step, AppLanguage.ar);
        for (final w in words(copy)) {
          expect(arabic.hasMatch(w), isTrue, reason: step.name);
          expect(RegExp(r'[,;?]').hasMatch(w), isFalse,
              reason: '${step.name}: ، ؛ ؟ after Arabic');
          expect(RegExp(r'[٠-٩۰-۹]').hasMatch(w), isFalse,
              reason: '${step.name}: Latin digits, as Morocco writes them');
          expect(w.contains('Foorsa'), isFalse, reason: step.name);
        }
        expect(copy.spoken, startsWith('اضغط مرتين'), reason: step.name);
        if (step.access != null) {
          expect(copy.action, 'متابعة', reason: step.name);
        }
      }
      expect(copyFor(BoardingStep.tracking, AppLanguage.ar).headline,
          contains('فرصة'));
    });

    test(
        'the language step says what the choice does and where to change it, '
        'and nothing more', () {
      final english = copyFor(BoardingStep.language);
      expect(english.body, contains('emails'));
      expect(english.body, contains('notifications'));
      expect(english.body, contains('Profile › Settings'));
      final french = copyFor(BoardingStep.language, AppLanguage.fr);
      expect(french.body, contains('e-mails'));
      expect(french.body, contains('Profil › Réglages'));
      final arabic = copyFor(BoardingStep.language, AppLanguage.ar);
      expect(arabic.body, contains('الإعدادات'));
      expect(arabic.body, contains('ملفك الشخصي'));
      // It asks the phone for nothing: no access step, no Continue.
      expect(BoardingStep.language.access, isNull);
    });
  });
}
