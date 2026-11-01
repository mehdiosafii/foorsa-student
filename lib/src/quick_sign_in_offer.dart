/// The question asked once a student has signed in with their password: use
/// Face ID (or the fingerprint) next time?
///
/// One line and two answers (the owner, 30 Oct 2026: the Face ID popup "needs
/// to be simpler"). It was a Material dialog with an icon, a title and three
/// sentences. On an iPhone it is now the system's own alert; on Android a
/// plain dialog. Either follows the theme the student chose in the portal.
/// Closing it any other way than "Use" is "Not now". It is asked in the
/// student's language; Face ID and Touch ID keep their names.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_language.dart';
import 'config.dart';

/// What the question says for the phone's [label]: 'Face ID', 'Touch ID', or
/// Android's 'fingerprint or face recognition'. [label] is the phone's kind,
/// never translated (student_biometrics.dart compares it).
String quickSignInQuestion(String label,
        [AppLanguage language = AppLanguage.en]) =>
    label == 'Face ID' || label == 'Touch ID'
        ? const Words(
                'Sign in with {label} next time?',
                'Se connecter avec {label} la prochaine fois\u202F?',
                'تسجيل الدخول باستخدام {label} في المرة القادمة؟')
            .of(language)
            .replaceFirst('{label}', label)
        : const Words(
                'Sign in with your fingerprint or face next time?',
                'Se connecter avec votre empreinte ou votre visage la '
                    'prochaine fois\u202F?',
                'تسجيل الدخول ببصمتك أو بوجهك في المرة القادمة؟')
            .of(language);

/// The answers: on an iPhone the system's own words (Not Now, Use Face ID),
/// on Android the plain dialog's.
const _notNowIOS = Words('Not Now', 'Plus tard', 'ليس الآن');
const _use = Words('Use {label}', 'Utiliser {label}', 'استخدام {label}');
const _notNow = Words('Not now', 'Plus tard', 'ليس الآن');
const _turnOn = Words('Turn on', 'Activer', 'تفعيل');

/// Asks, and answers true only for "Use".
Future<bool> showQuickSignInOffer(
  BuildContext context, {
  required String label,
  required bool dark,
  AppLanguage? language,
}) async {
  final offer = QuickSignInOffer(label: label, dark: dark, language: language);
  final answer = Theme.of(context).platform == TargetPlatform.iOS
      ? await showCupertinoDialog<bool>(context: context, builder: (_) => offer)
      : await showDialog<bool>(context: context, builder: (_) => offer);
  return answer == true;
}

class QuickSignInOffer extends StatelessWidget {
  const QuickSignInOffer(
      {super.key, required this.label, required this.dark, this.language});

  final String label;
  final bool dark;

  /// The student's language; the app's (AppLanguageScope) when not given.
  final AppLanguage? language;

  @override
  Widget build(BuildContext context) {
    final language = this.language ?? AppLanguageScope.of(context);
    return Directionality(
      textDirection: language.direction,
      child: Builder(builder: (context) => _dialog(context, language)),
    );
  }

  Widget _dialog(BuildContext context, AppLanguage language) {
    final brightness = dark ? Brightness.dark : Brightness.light;
    final question = Text(quickSignInQuestion(label, language));
    if (Theme.of(context).platform == TargetPlatform.iOS) {
      return CupertinoTheme(
        data: CupertinoThemeData(brightness: brightness),
        child: CupertinoAlertDialog(
          title: question,
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context, false),
              child: Text(_notNowIOS.of(language)),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(context, true),
              child: Text(_use.of(language).replaceFirst('{label}', label)),
            ),
          ],
        ),
      );
    }
    return Theme(
      data: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(AppConfig.brandColorValue),
          brightness: brightness,
        ),
      ),
      child: AlertDialog(
        title: question,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_notNow.of(language)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_turnOn.of(language)),
          ),
        ],
      ),
    );
  }
}
