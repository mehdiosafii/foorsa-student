/// What the first-launch onboarding asks, in which order, and with which
/// words. Pure, so the tests can pin it (test/onboarding_flow_test.dart).
///
/// App Review (guideline 5.1.1(iv), as reviewers apply it): a screen shown
/// before a permission request must lead to the request. There is no button
/// to press: the student does the one thing the screen shows (taps the
/// notification, puts the page in the scanner's frame, taps the mic, taps the
/// arrow on the map), and that leads to the prompt. Nothing says Allow, and
/// there is no Not now, Skip or close. For a screen reader the object is a
/// button named Continue. Whatever the student answers in the system prompt,
/// the next step follows; nothing on the way promises a reward for allowing
/// (ATT forbids that too).
///
/// The first step is the language (the owner, 1 Nov 2026): English, the
/// default, French or Arabic, each named in itself. It asks the phone for
/// nothing, so it is no pre-permission screen; it says only what the choice
/// does (the app, the emails and the notifications) and where to change it.
/// Every word of every step is written in the three ([copyFor]).
library;

import '../app_language.dart';

/// Phone access the onboarding can ask for.
enum BoardingAccess { notifications, camera, microphone, location, tracking }

/// What the phone says about one access.
enum AccessState {
  /// Never asked: the system prompt will show.
  askable,
  granted,

  /// Refused, or "don't ask again": only Settings can change it now.
  denied,

  /// Not on this phone, or restricted (parental controls, an MDM profile).
  unavailable,
}

/// One screen of the onboarding.
enum BoardingStep {
  language,
  welcome,
  notifications,
  camera,
  microphone,
  location,
  tracking,
  boarding
}

extension BoardingAccessStep on BoardingAccess {
  BoardingStep get step => switch (this) {
        BoardingAccess.notifications => BoardingStep.notifications,
        BoardingAccess.camera => BoardingStep.camera,
        BoardingAccess.microphone => BoardingStep.microphone,
        BoardingAccess.location => BoardingStep.location,
        BoardingAccess.tracking => BoardingStep.tracking,
      };
}

extension BoardingStepAccess on BoardingStep {
  BoardingAccess? get access => switch (this) {
        BoardingStep.notifications => BoardingAccess.notifications,
        BoardingStep.camera => BoardingAccess.camera,
        BoardingStep.microphone => BoardingAccess.microphone,
        BoardingStep.location => BoardingAccess.location,
        BoardingStep.tracking => BoardingAccess.tracking,
        _ => null,
      };
}

/// Reads and asks the phone. The real one is permission_handler
/// (onboarding_permissions.dart); tests and the rehearsal use fakes.
abstract class BoardingPermissions {
  Future<AccessState> status(BoardingAccess access);

  /// Shows the system prompt and says what the student chose.
  Future<AccessState> request(BoardingAccess access);
}

/// The order the onboarding asks in: what matters most to a student first,
/// tracking last.
const boardingOrder = <BoardingAccess>[
  BoardingAccess.notifications,
  BoardingAccess.camera,
  BoardingAccess.microphone,
  BoardingAccess.location,
  BoardingAccess.tracking,
];

/// What the onboarding will show, and what the phone said when it looked.
class BoardingPlan {
  const BoardingPlan(this.steps, this.states);
  final List<BoardingStep> steps;
  final Map<BoardingAccess, AccessState> states;
}

/// The screens a student sees: the language, the welcome, a step for each
/// access the phone can still ask for, and the boarding pass. An access
/// already granted, or refused before (the prompt would not show), gets no
/// screen: a screen before a prompt that never comes is exactly what review
/// refuses.
/// Tracking is asked only on an iPhone and only when [asksToTrack].
Future<BoardingPlan> planBoarding(
  BoardingPermissions permissions, {
  required bool isIOS,
  required bool asksToTrack,
}) async {
  final steps = <BoardingStep>[BoardingStep.language, BoardingStep.welcome];
  final states = <BoardingAccess, AccessState>{};
  for (final access in boardingOrder) {
    if (access == BoardingAccess.tracking && (!isIOS || !asksToTrack)) continue;
    AccessState state;
    try {
      state = await permissions.status(access);
    } catch (_) {
      // A plugin that cannot answer must never hold the app back.
      state = AccessState.unavailable;
    }
    states[access] = state;
    if (state == AccessState.askable) steps.add(access.step);
  }
  steps.add(BoardingStep.boarding);
  return BoardingPlan(steps, states);
}

/// The words of one screen: a headline, one line under it, and what to do
/// with the object.
class BoardingCopy {
  const BoardingCopy({
    required this.headline,
    required this.body,
    required this.action,
    required this.hint,
    required this.spoken,
  });

  final String headline;
  final String body;

  /// What a screen reader calls the object the student acts on: it is the
  /// screen's one way on.
  final String action;

  /// What to do, said under the object and shown on it (scene_hint.dart):
  /// a verb first, then the object, as a phone says it.
  final String hint;

  /// What to do, for a screen reader, after the object's name: a screen
  /// reader's double tap does what the gesture does.
  final String spoken;
}

/// The words of [step] in [language]. A step's words are a story told in a
/// few of them, so French and Arabic say the same thing their own way rather
/// than word for word (shared/i18n/README.md in foorsa-reward: vouvoiement
/// and the typographic apostrophe in French; Modern Standard Arabic as a
/// Moroccan student reads it, فرصة for Foorsa, the student addressed without
/// a gender where the sentence allows).
///
/// The language step's [BoardingCopy.spoken] is what each language's row
/// tells a screen reader, in that row's own language.
BoardingCopy copyFor(BoardingStep step,
        [AppLanguage language = AppLanguage.en]) =>
    switch (language) {
      AppLanguage.en => _english(step),
      AppLanguage.fr => _french(step),
      AppLanguage.ar => _arabic(step),
    };

BoardingCopy _english(BoardingStep step) => switch (step) {
      BoardingStep.language => const BoardingCopy(
          headline: 'Choose your language.',
          body: 'For the app, emails and notifications. '
              'Change it in Profile › Settings.',
          action: 'Language',
          hint: 'Tap your language',
          spoken: 'Double-tap to choose this language.',
        ),
      BoardingStep.welcome => const BoardingCopy(
          headline: 'Your journey to China starts here.',
          body: 'Let’s get your phone ready. It takes a minute.',
          action: 'Get started',
          hint: 'Swipe the arrow up to begin',
          spoken: 'Double-tap to throw the arrow up and begin.',
        ),
      BoardingStep.notifications => const BoardingCopy(
          headline: 'Never miss a moment.',
          body: 'Replies from your adviser and news about your file, '
              'as they happen.',
          action: 'Continue',
          hint: 'Tap the notification',
          spoken: 'Double-tap the notification to go on.',
        ),
      BoardingStep.camera => const BoardingCopy(
          headline: 'Scan papers in seconds.',
          body: 'Hold a paper up to the camera. The app does the rest.',
          action: 'Continue',
          hint: 'Drag the page into the frame',
          spoken: 'Double-tap to put the page in the frame.',
        ),
      BoardingStep.microphone => const BoardingCopy(
          headline: 'Talk to your adviser.',
          body: 'Answer calls and send voice notes, right in the app.',
          action: 'Continue',
          hint: 'Tap the mic',
          spoken: 'Double-tap the mic to go on.',
        ),
      BoardingStep.location => const BoardingCopy(
          headline: 'Feel at home in China.',
          body: 'Prayer times, the weather and places nearby, '
              'while you use the app.',
          action: 'Continue',
          hint: 'Tap the arrow to find yourself',
          spoken: 'Double-tap the map’s arrow to find yourself.',
        ),
      BoardingStep.tracking => const BoardingCopy(
          headline: 'Help others find Foorsa.',
          body: 'Let Foorsa see which of its ads brought you here. '
              'Nothing more.',
          action: 'Continue',
          hint: 'Tap the shield',
          spoken: 'Double-tap the shield to go on.',
        ),
      BoardingStep.boarding => const BoardingCopy(
          headline: 'You’re ready to board.',
          body: 'Tear off the stub to sign in.',
          action: 'Board',
          hint: 'Pull the stub down to board',
          spoken: 'Double-tap to tear off the stub and sign in.',
        ),
    };

BoardingCopy _french(BoardingStep step) => switch (step) {
      BoardingStep.language => const BoardingCopy(
          headline: 'Choisissez votre langue.',
          body: 'Pour l’application, vos e-mails et vos notifications. '
              'Modifiable dans Profil › Réglages.',
          action: 'Langue',
          hint: 'Touchez votre langue',
          spoken: 'Touchez deux fois pour choisir cette langue.',
        ),
      BoardingStep.welcome => const BoardingCopy(
          headline: 'Votre voyage vers la Chine commence ici.',
          body: 'Préparons votre téléphone. Cela ne prend qu’une minute.',
          action: 'Commencer',
          hint: 'Glissez la flèche vers le haut',
          spoken: 'Touchez deux fois pour lancer la flèche et commencer.',
        ),
      BoardingStep.notifications => const BoardingCopy(
          headline: 'Ne manquez aucun moment.',
          body: 'Les réponses de votre conseiller et les nouvelles de votre '
              'dossier, en temps réel.',
          action: 'Continuer',
          hint: 'Touchez la notification',
          spoken: 'Touchez deux fois la notification pour continuer.',
        ),
      BoardingStep.camera => const BoardingCopy(
          headline: 'Scannez vos documents en quelques secondes.',
          body: 'Présentez un document à l’appareil photo, l’application '
              'fait le reste.',
          action: 'Continuer',
          hint: 'Glissez la page dans le cadre',
          spoken: 'Touchez deux fois pour placer la page dans le cadre.',
        ),
      BoardingStep.microphone => const BoardingCopy(
          headline: 'Parlez à votre conseiller.',
          body: 'Répondez aux appels et envoyez des messages vocaux, sans '
              'quitter l’application.',
          action: 'Continuer',
          hint: 'Touchez le micro',
          spoken: 'Touchez deux fois le micro pour continuer.',
        ),
      BoardingStep.location => const BoardingCopy(
          headline: 'Sentez-vous chez vous en Chine.',
          body: 'Les heures de prière, la météo et les lieux proches, quand '
              'vous utilisez l’application.',
          action: 'Continuer',
          hint: 'Touchez la flèche pour vous situer',
          spoken: 'Touchez deux fois la flèche de la carte pour vous situer.',
        ),
      BoardingStep.tracking => const BoardingCopy(
          headline: 'Aidez d’autres personnes à découvrir Foorsa.',
          body: 'Permettez à Foorsa de savoir quelle publicité vous a fait '
              'venir. Rien de plus.',
          action: 'Continuer',
          hint: 'Touchez le bouclier',
          spoken: 'Touchez deux fois le bouclier pour continuer.',
        ),
      BoardingStep.boarding => const BoardingCopy(
          headline: 'Tout est prêt pour l’embarquement.',
          body: 'Détachez le talon pour vous connecter.',
          action: 'Embarquer',
          hint: 'Tirez le talon vers le bas',
          spoken:
              'Touchez deux fois pour détacher le talon et vous connecter.',
        ),
    };

BoardingCopy _arabic(BoardingStep step) => switch (step) {
      BoardingStep.language => const BoardingCopy(
          headline: 'اختر لغتك.',
          body: 'للتطبيق ورسائلك الإلكترونية وإشعاراتك. '
              'يمكنك تغييرها من الإعدادات في ملفك الشخصي.',
          action: 'اللغة',
          hint: 'اضغط على لغتك',
          spoken: 'اضغط مرتين لاختيار هذه اللغة.',
        ),
      BoardingStep.welcome => const BoardingCopy(
          headline: 'رحلتك إلى الصين تبدأ من هنا.',
          body: 'لنجهز هاتفك. لن يستغرق ذلك سوى دقيقة.',
          action: 'البدء',
          hint: 'اسحب السهم إلى الأعلى',
          spoken: 'اضغط مرتين لإطلاق السهم والبدء.',
        ),
      BoardingStep.notifications => const BoardingCopy(
          headline: 'لن يفوتك أي جديد.',
          body: 'ردود مستشارك وأخبار ملفك، أولًا بأول.',
          action: 'متابعة',
          hint: 'اضغط على الإشعار',
          spoken: 'اضغط مرتين على الإشعار للمتابعة.',
        ),
      BoardingStep.camera => const BoardingCopy(
          headline: 'المسح الضوئي لوثائقك في ثوانٍ.',
          body: 'يكفي وضع الوثيقة أمام الكاميرا، والتطبيق يتكفل بالباقي.',
          action: 'متابعة',
          hint: 'اسحب الصفحة إلى الإطار',
          spoken: 'اضغط مرتين لوضع الصفحة في الإطار.',
        ),
      BoardingStep.microphone => const BoardingCopy(
          headline: 'مستشارك على بُعد مكالمة.',
          body: 'الرد على المكالمات وإرسال الرسائل الصوتية، من داخل التطبيق.',
          action: 'متابعة',
          hint: 'اضغط على الميكروفون',
          spoken: 'اضغط مرتين على الميكروفون للمتابعة.',
        ),
      BoardingStep.location => const BoardingCopy(
          headline: 'كأنك في بيتك، في الصين.',
          body: 'أوقات الصلاة والطقس والأماكن القريبة، أثناء استخدامك للتطبيق.',
          action: 'متابعة',
          hint: 'اضغط على السهم لتحديد موقعك',
          spoken: 'اضغط مرتين على سهم الخريطة لتحديد موقعك.',
        ),
      BoardingStep.tracking => const BoardingCopy(
          headline: 'ساعد غيرك على اكتشاف فرصة.',
          body: 'دع فرصة تعرف أي إعلان من إعلاناتها أوصلك إلى هنا، لا أكثر.',
          action: 'متابعة',
          hint: 'اضغط على الدرع',
          spoken: 'اضغط مرتين على الدرع للمتابعة.',
        ),
      BoardingStep.boarding => const BoardingCopy(
          headline: 'كل شيء جاهز للصعود.',
          body: 'اقطع كعب التذكرة لتسجيل الدخول.',
          action: 'الصعود',
          hint: 'اسحب كعب التذكرة إلى الأسفل',
          spoken: 'اضغط مرتين لقطع كعب التذكرة وتسجيل الدخول.',
        ),
    };
