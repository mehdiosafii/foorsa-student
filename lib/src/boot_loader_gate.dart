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
library;

class BootLoaderGate {
  /// The portal's own loader gives up after 10 s (BOOT_LOADER_MAX_MS).
  static const Duration holdLimit = Duration(seconds: 10);

  /// The shortest time the loader shows, so a fast start does not flash it.
  static const Duration minimum = Duration(milliseconds: 800);

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
