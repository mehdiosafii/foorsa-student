/// What this build can do, answered to the portal's FoorsaShellCapabilities
/// call so the page can tell it from older builds, which do not answer.
library;

import 'shell_haptics.dart';

Map<String, Object> shellCapabilities({required bool isIOS}) => {
      // An iframe (a YouTube player) plays in the page instead of leaving
      // the app.
      'embeddedFrames': true,
      // The page may offer its own video picker (the student's introduction
      // video). On an iPhone that picker can film, and iOS closes an app the
      // moment its camera records sound without NSMicrophoneUsageDescription
      // in Info.plist; builds from 46 carry it. On Android the WebView's
      // chooser offers the phone's videos and, with the camera allowed, the
      // camera; from 1.2.30 (61) the manifest's <queries> let Android 11 and
      // later find the camera and file apps, which the chooser failed to
      // open without (the owner, 31 Oct 2026: "in android i can't upload
      // introduction video they are asking me to send it to my advisory").
      'videoInput': true,
      // Touch by name (shell_haptics.dart): the reveal's textures and the
      // portal's "no". Builds 33 to 46 did not answer it and got ticks.
      'hapticTextures': ShellHaptics.version,
      // The loading screen stays until the portal says its first screen is
      // up (FoorsaShellLoading), and follows the theme the student chose
      // (FoorsaShellAppearance).
      'bootHandoff': true,
      // The app speaks the student's language (English, French, Arabic): the
      // portal says it with FoorsaShellLanguage, and the onboarding's first
      // step hands it to the portal (app_language.dart).
      'language': true,
    };
