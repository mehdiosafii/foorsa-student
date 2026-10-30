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

BoardingCopy copyFor(BoardingStep step) => switch (step) {
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
