/// What this build can do, answered to the portal's FoorsaShellCapabilities
/// call so the page can tell it from older builds, which do not answer.
library;

import 'shell_haptics.dart';

Map<String, Object> shellCapabilities({required bool isIOS, String? appVersion, String? appBuild}) => {
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
      // Push notifications (student_push.dart): 2 names why a phone could not
      // register, and answers pushStatus and openNotificationSettings, so the
      // portal's Settings shows On, Off or Not set up yet.
      'push': 2,
      // What the page may be granted (portal_permissions.dart). 2, from
      // 1.2.33 (64): the camera and the microphone together, as an iPhone
      // asks for video with sound (the introduction video's studio), and how
      // the phone is held (its set-up, the admission reveal's tilt). Builds
      // before answer nothing: an iPhone was granted the camera and the
      // microphone only one at a time, and never the tilt.
      'pagePermissions': 2,
      // The adhan at prayer times, with the app closed (student_adhan.dart): FoorsaBridge
      // adhanStatus, adhanEnable, adhanSync, adhanClear and adhanExactAlarms, from 1.2.37 (68).
      'adhan': 1,
      // The session stays signed in across launches, quick sign-in or not, and a renewed session
      // (the portal's /me, a day on) is kept without being taken for a new sign-in, from 1.2.37
      // (68). Builds before cleared the session at each launch while quick sign-in was on.
      'session': 2,
      // Which build a student runs, for Admin Portal › Student App (the board
      // read it from here, and no build said it until this one).
      if (appVersion != null && RegExp(r'^[0-9A-Za-z.+_-]{1,40}$').hasMatch(appVersion)) 'appVersion': appVersion,
      if (appBuild != null && RegExp(r'^[0-9A-Za-z.+_-]{1,40}$').hasMatch(appBuild)) 'appBuild': appBuild,
    };
