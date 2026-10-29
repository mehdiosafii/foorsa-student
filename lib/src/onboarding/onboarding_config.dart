/// Switches for the first-launch onboarding.
library;

class OnboardingConfig {
  OnboardingConfig._();

  /// Whether the onboarding asks for App Tracking Transparency (iPhone only).
  ///
  /// Off. The app does not track today: its privacy manifest says
  /// `NSPrivacyTracking` false, the App Store label says no tracking, and the
  /// privacy notice (student.foorsa.ma/privacy-policy) says "The Student app
  /// does not use advertising tracking". Asking students to allow tracking
  /// that does not exist would contradict all three, and review checks them
  /// against each other. Turn it on in the same change that adds ad
  /// measurement; docs/first-launch-onboarding.md lists the four other places
  /// that change with it (Podfile macro, Info.plist purpose string, privacy
  /// manifest, privacy notice). A build can also try it with
  /// `--dart-define=FOORSA_ASK_TO_TRACK=true`.
  static const bool asksToTrack = bool.fromEnvironment('FOORSA_ASK_TO_TRACK');
}
