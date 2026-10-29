/// What the first-launch onboarding asks, in which order, and with which
/// words. Pure, so the tests can pin it (test/onboarding_flow_test.dart).
///
/// App Review (guideline 5.1.1(iv), as reviewers apply it): a screen shown
/// before a permission request must lead to the request. Its one button says
/// Continue, never Allow, and there is no Not now, Skip or close beside it.
/// Whatever the student answers in the system prompt, the next step follows;
/// nothing on the way promises a reward for allowing (ATT forbids that too).
library;

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

  /// The permission steps, the gates on the route.
  int get gates => steps.where((s) => s.access != null).length;
}

/// The screens a student sees: the welcome, a step for each access the phone
/// can still ask for, and the boarding pass. An access already granted, or
/// refused before (the prompt would not show), gets no screen: a screen
/// before a prompt that never comes is exactly what review refuses.
/// Tracking is asked only on an iPhone and only when [asksToTrack].
Future<BoardingPlan> planBoarding(
  BoardingPermissions permissions, {
  required bool isIOS,
  required bool asksToTrack,
}) async {
  final steps = <BoardingStep>[BoardingStep.welcome];
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

/// The words of one screen.
class BoardingCopy {
  const BoardingCopy({
    required this.eyebrow,
    required this.headline,
    required this.arabic,
    required this.body,
    required this.action,
    this.footnote,
  });

  final String eyebrow;
  final String headline;

  /// The headline in Arabic, under it, as the shell's offline screen does.
  final String arabic;
  final String body;

  /// The one button.
  final String action;
  final String? footnote;
}

const _change = 'You can change this anytime in Settings.';

BoardingCopy copyFor(BoardingStep step) => switch (step) {
      BoardingStep.welcome => const BoardingCopy(
          eyebrow: 'WELCOME TO FOORSA',
          headline: 'Your journey to China starts here.',
          arabic: 'رحلتك إلى الصين تبدأ من هنا',
          body:
              'Your file, your universities, your visa and your flight, in one app. '
              'Let’s get your phone ready.',
          action: 'Get started',
          footnote: 'Takes less than a minute.',
        ),
      BoardingStep.notifications => const BoardingCopy(
          eyebrow: 'NOTIFICATIONS',
          headline: 'Know the moment there’s news.',
          arabic: 'كن أول من يعرف بكل جديد',
          body:
              'We let you know when your adviser replies, when there’s an update on '
              'your file, and before your classes.',
          action: 'Continue',
          footnote: _change,
        ),
      BoardingStep.camera => const BoardingCopy(
          eyebrow: 'CAMERA',
          headline: 'Scan your papers in seconds.',
          arabic: 'امسح وثائقك في ثوانٍ',
          body:
              'Hold a paper up to the camera. The app finds its edges, straightens it '
              'and checks it can be read.',
          action: 'Continue',
          footnote: _change,
        ),
      BoardingStep.microphone => const BoardingCopy(
          eyebrow: 'MICROPHONE',
          headline: 'Talk to your adviser, from anywhere.',
          arabic: 'تحدّث مع مستشارك من أي مكان',
          body:
              'Answer your adviser’s calls in the app and send voice notes in the chat.',
          action: 'Continue',
          footnote: _change,
        ),
      BoardingStep.location => const BoardingCopy(
          eyebrow: 'LOCATION',
          headline: 'Feel at home in your new city.',
          arabic: 'اشعر وكأنك في بيتك في مدينتك الجديدة',
          body:
              'Prayer times, the local weather and nearby places like supermarkets, '
              'only while you’re using the app.',
          action: 'Continue',
          footnote: _change,
        ),
      BoardingStep.tracking => const BoardingCopy(
          eyebrow: 'ADS AND PRIVACY',
          headline: 'Help more students find Foorsa.',
          arabic: 'ساعدنا لنصل إلى طلاب مثلك',
          body:
              'If you allow it, Foorsa can see which of its ads brought you here, so it '
              'can reach more students like you.',
          action: 'Continue',
          footnote: _change,
        ),
      BoardingStep.boarding => const BoardingCopy(
          eyebrow: 'ALL SET',
          headline: 'You’re ready to board.',
          arabic: 'أنت جاهز للإقلاع',
          body: 'Sign in with the details your Foorsa adviser sent you.',
          action: 'Board',
          footnote: 'Or tear off the stub.',
        ),
    };

/// What the boarding pass and the step's own line say about an answer.
String accessName(BoardingAccess access) => switch (access) {
      BoardingAccess.notifications => 'Notifications',
      BoardingAccess.camera => 'Camera',
      BoardingAccess.microphone => 'Microphone',
      BoardingAccess.location => 'Location',
      BoardingAccess.tracking => 'Ad measurement',
    };

String outcomeLine(BoardingAccess access, bool on) {
  final name = accessName(access);
  final plural = access == BoardingAccess.notifications;
  if (on) return '$name ${plural ? 'are' : 'is'} on';
  return '$name ${plural ? 'stay' : 'stays'} off for now';
}
