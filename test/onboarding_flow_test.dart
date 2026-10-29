import 'package:flutter_test/flutter_test.dart';
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
      BoardingStep.welcome,
      BoardingStep.notifications,
      BoardingStep.camera,
      BoardingStep.microphone,
      BoardingStep.location,
      BoardingStep.boarding,
    ]);
    expect(plan.gates, 4);
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
    expect(plan.steps,
        [BoardingStep.welcome, BoardingStep.location, BoardingStep.boarding]);
    expect(plan.states[BoardingAccess.notifications], AccessState.granted);
  });

  test('a permission plugin that cannot answer never holds the app back',
      () async {
    final plan = await planBoarding(_Broken(), isIOS: true, asksToTrack: true);
    expect(plan.steps, [BoardingStep.welcome, BoardingStep.boarding]);
  });

  test(
      'a screen before a permission prompt says Continue, never Allow, and has nothing else to press',
      () {
    for (final step in BoardingStep.values) {
      final copy = copyFor(step);
      expect(copy.action.toLowerCase(), isNot(contains('allow')),
          reason: step.name);
      expect(
          copy.action.toLowerCase(),
          isNot(
              anyOf(contains('skip'), contains('not now'), contains('later'))));
      if (step.access != null) {
        expect(copy.action, 'Continue', reason: step.name);
      }
    }
  });

  test(
      'every screen says it in English with the Arabic under it, as the shell does',
      () {
    final arabic = RegExp(r'[؀-ۿ]');
    for (final step in BoardingStep.values) {
      final copy = copyFor(step);
      expect(arabic.hasMatch(copy.arabic), isTrue, reason: step.name);
      expect(copy.headline.endsWith('.'), isTrue,
          reason: 'the portal writes its headlines as sentences');
      expect(copy.eyebrow, copy.eyebrow.toUpperCase());
    }
  });

  test('what the student chose is said in words', () {
    expect(outcomeLine(BoardingAccess.notifications, true),
        'Notifications are on');
    expect(outcomeLine(BoardingAccess.notifications, false),
        'Notifications stay off for now');
    expect(outcomeLine(BoardingAccess.camera, true), 'Camera is on');
    expect(outcomeLine(BoardingAccess.location, false),
        'Location stays off for now');
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
}
