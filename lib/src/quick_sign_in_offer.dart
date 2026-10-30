/// The question asked once a student has signed in with their password: use
/// Face ID (or the fingerprint) next time?
///
/// One line and two answers (the owner, 30 Oct 2026: the Face ID popup "needs
/// to be simpler"). It was a Material dialog with an icon, a title and three
/// sentences. On an iPhone it is now the system's own alert; on Android a
/// plain dialog. Either follows the theme the student chose in the portal.
/// Closing it any other way than "Use" is "Not now".
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'config.dart';

/// What the question says for the phone's [label]: 'Face ID', 'Touch ID', or
/// Android's 'fingerprint or face recognition'.
String quickSignInQuestion(String label) => label == 'Face ID' || label == 'Touch ID'
    ? 'Sign in with $label next time?'
    : 'Sign in with your fingerprint or face next time?';

/// Asks, and answers true only for "Use".
Future<bool> showQuickSignInOffer(
  BuildContext context, {
  required String label,
  required bool dark,
}) async {
  final offer = QuickSignInOffer(label: label, dark: dark);
  final answer = Theme.of(context).platform == TargetPlatform.iOS
      ? await showCupertinoDialog<bool>(context: context, builder: (_) => offer)
      : await showDialog<bool>(context: context, builder: (_) => offer);
  return answer == true;
}

class QuickSignInOffer extends StatelessWidget {
  const QuickSignInOffer({super.key, required this.label, required this.dark});

  final String label;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final brightness = dark ? Brightness.dark : Brightness.light;
    final question = Text(quickSignInQuestion(label));
    if (Theme.of(context).platform == TargetPlatform.iOS) {
      return CupertinoTheme(
        data: CupertinoThemeData(brightness: brightness),
        child: CupertinoAlertDialog(
          title: question,
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Not Now'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(context, true),
              child: Text('Use $label'),
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
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Turn on'),
          ),
        ],
      ),
    );
  }
}
