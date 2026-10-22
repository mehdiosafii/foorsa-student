/// What this build can do, answered to the portal's FoorsaShellCapabilities
/// call so the page can tell it from older builds, which do not answer.
Map<String, Object> shellCapabilities({required bool isIOS}) => {
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
    };
