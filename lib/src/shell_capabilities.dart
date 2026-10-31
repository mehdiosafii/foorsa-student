/// What this build can do, answered to the portal's FoorsaShellCapabilities
/// call so the page can tell it from older builds, which do not answer.
library;

import 'shell_haptics.dart';

Map<String, Object> shellCapabilities({
  required bool isIOS,
  String? appVersion,
  String? appBuild,
}) =>
    {
      // An iframe (a YouTube player) plays in the page instead of leaving
      // the app.
      'embeddedFrames': true,
      // The page may offer its own video picker (the student's introduction
      // video). On an iPhone that picker can film, and iOS closes an app the
      // moment its camera records sound without NSMicrophoneUsageDescription
      // in Info.plist; builds from this one carry it. Android's WebView
      // picker fails to open on some phones, so Android students keep
      // sending the video through their adviser.
      'videoInput': isIOS,
      // Touch by name (shell_haptics.dart): the reveal's textures and the
      // portal's "no". Builds 33 to 46 did not answer it and got ticks.
      'hapticTextures': ShellHaptics.version,
      // The loading screen stays until the portal says its first screen is
      // up (FoorsaShellLoading), and follows the theme the student chose
      // (FoorsaShellAppearance).
      'bootHandoff': true,
      // The app's own version, for Admin Portal › Student App in Foorsa
      // Reward: which version each student runs, and who is still on an old
      // one. Builds before 51 do not say it.
      if (appVersion != null) 'appVersion': appVersion,
      if (appBuild != null) 'appBuild': appBuild,
    };
