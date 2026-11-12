/// When the app's loading screen gives way to the portal.
///
/// The portal draws the same loader as the app (the Foorsa flicker on the
/// same ground) until its first screen is ready. The app's used to lift the
/// moment the page finished loading, so a student saw the app's loader, then
/// the portal's one a little lower (the web page starts under the status
/// bar), then the app. Now a portal that says it shows its own loader
/// (`FoorsaShellLoading('hold')`) keeps the app's on top until it says its
/// first screen is up (`'ready'`), and the two are drawn at the same place, so
/// one loader runs from the app icon to the first screen.
///
/// A portal that never says `hold` (one from before this build) gets the old
/// behaviour, and a portal that says `hold` but never `ready` is let go after
/// [holdLimit], the portal's own limit for its loader. Once lifted, the
/// loader never comes back: later page loads are the portal's to cover.
///
/// It also says when the loader starts to move. A web view is made on the
/// thread the app builds its frames on (in this Flutter the phone's main
/// thread and Dart's are one: `merged_platform_ui_thread`, common/settings.h
/// in the engine), so while one is made no frame is built; on Android the
/// first one also loads Chromium. The loader used to play from its first
/// frame, and the web view was made 300 ms later, in the middle of the
/// arrow's shine. Now the web view is made as soon as the loading screen's
/// first frame is drawn ([whenWebViewMayStart]), and until it exists the
/// loader rests on its first picture, the arrow alone ([resting]): the
/// longest hold is over before anything moves, and the portal starts to load
/// up to 300 ms sooner. (On Android the frame that first shows the new view
/// is dropped and drawn again, as Flutter moves its drawing to the main
/// thread for it: the loop opens with a tenth of a second of that same still
/// picture, and counts from the first frame drawn after the rest,
/// flight_loader.dart.)
///
/// A first launch does not rest ([BootLoaderGate.new]'s `rests`): its web
/// view waits for the onboarding's takeoff, and its loader is under the
/// onboarding, neither drawn nor animated, as before.
library;

class BootLoaderGate {
  /// [rests] false for a first launch.
  BootLoaderGate({bool rests = true}) : _restExpired = !rests;

  /// The portal's own loader gives up after 10 s (BOOT_LOADER_MAX_MS).
  static const Duration holdLimit = Duration(seconds: 10);

  /// The shortest time the loader shows, so a fast start does not flash it.
  static const Duration minimum = Duration(milliseconds: 800);

  /// The longest the loader rests on its first picture. A web view that is
  /// slow to come, or never does (the shell's offline screen takes over after
  /// `webViewStartLimit`), does not leave the arrow standing still.
  static const Duration restLimit = Duration(seconds: 1);

  /// How long an ordinary start waits for the loading screen's first frame
  /// before it makes the web view anyway: the wait every start had before.
  static const Duration firstFrameLimit = Duration(milliseconds: 300);

  /// How long after the web view is made something new may come in over the
  /// shell (the device access reminder, portal_handover.dart): the first
  /// frames that show a web view are not the ones to come in on.
  static const Duration settle = Duration(milliseconds: 300);

  bool _webViewMade = false;
  bool _restExpired;

  /// Whether the loader rests on its first picture: from the start until the
  /// web view is made, [restLimit] at most. Once it moves it never rests
  /// again, not even for a web view made anew.
  bool get resting => !_webViewMade && !_restExpired;

  /// The web view exists: making it no longer holds the thread.
  void webViewMade() => _webViewMade = true;

  void restExpired() => _restExpired = true;

  bool _minimumPassed = false;
  bool _pageLoaded = false;
  bool _portalHolds = false;
  bool _portalReady = false;
  bool _holdExpired = false;
  bool _lifted = false;

  /// Whether the loading screen is up.
  bool get showing => !_lifted;

  /// Whether the portal asked to be waited for and has not answered yet.
  bool get waitingForPortal => _portalHolds && !_portalReady && !_holdExpired;

  void minimumPassed() => _update(() => _minimumPassed = true);

  /// The first page load finished, or failed (the offline screen covers it).
  void pageLoaded() => _update(() => _pageLoaded = true);

  /// The portal's `FoorsaShellLoading` message. Returns true when it is the
  /// first `hold`, for the caller to start the [holdLimit] timer.
  bool portalSays(Object? message) {
    if (_lifted) return false;
    if (message == 'ready') {
      _update(() => _portalReady = true);
      return false;
    }
    if (message == 'hold' && !_portalHolds) {
      _update(() => _portalHolds = true);
      return true;
    }
    return false;
  }

  void holdExpired() => _update(() => _holdExpired = true);

  void _update(void Function() change) {
    if (_lifted) return;
    change();
    if (_minimumPassed && _pageLoaded && !waitingForPortal) _lifted = true;
  }
}

/// When the shell may make its web view.
///
/// A first launch gives a [delay]: the web view waits until the onboarding's
/// takeoff has flown (onboarding_gate.dart). Any other start gives none, and
/// the web view is made once the loading screen's [firstFrame] is drawn, so
/// the student sees the loader before the thread is held, and never later
/// than [limit] should that frame not be reported.
Future<void> whenWebViewMayStart({
  required Duration delay,
  required Future<void> firstFrame,
  Duration limit = BootLoaderGate.firstFrameLimit,
}) =>
    delay > Duration.zero
        ? Future<void>.delayed(delay)
        : firstFrame.timeout(limit, onTimeout: () {});
