import 'dart:async';
import 'dart:ui' show AppLifecycleState;

/// What the shell does when the portal's page dies or a load fails (the owner,
/// 31 Oct 2026: "after uploading one file or two the app is a bit sluggish ...
/// without sudden crashes or freezing or going back to home screen").
///
/// Before 1.2.30 (61) three things sent a student back to Home or out of the
/// app: on Android a web view killed for memory took the whole app with it (no
/// `onRenderProcessGone`); on iPhone it went blank; and any main-frame load the
/// app or the page cancelled (a file download, a link handed to another app)
/// read as being offline, whose retry loaded the start page, which is Home.
class WebViewRecovery {
  WebViewRecovery(this.home);

  /// The portal's start page, used only when no page has been seen yet.
  final Uri home;

  /// The last portal page the student was on, the page to come back to.
  Uri? get lastPage => _lastPage;
  Uri? _lastPage;

  /// A page that keeps dying is not reloaded forever: after this many deaths
  /// in [restartWindow] the shell shows its offline screen and its retry.
  static const maxRestarts = 3;
  static const restartWindow = Duration(minutes: 2);
  final List<DateTime> _restarts = [];

  /// Remembers a page of the portal (never another site, never a one-time
  /// link's token: a reload must not replay a sign-in or reset link).
  void notePage(Uri? url, {required bool trusted}) {
    if (url == null || !trusted) return;
    if (url.scheme != 'https' && url.scheme != 'http') return;
    _lastPage = withoutToken(url);
  }

  /// Where a reload goes: the page the student was on, else the start page.
  Uri pageToReload() => _lastPage ?? home;

  /// Whether the page may be reloaded after a death now.
  bool mayRestart(DateTime now) {
    _restarts.removeWhere((at) => now.difference(at) > restartWindow);
    if (_restarts.length >= maxRestarts) return false;
    _restarts.add(now);
    return true;
  }

  static Uri withoutToken(Uri url) {
    final page = url.hasFragment ? url.removeFragment() : url;
    final params = Map<String, String>.of(page.queryParameters);
    if (params.remove('token') == null) return page;
    return Uri(
      scheme: page.scheme,
      host: page.host,
      port: page.hasPort ? page.port : null,
      path: page.path,
      queryParameters: params.isEmpty ? null : params,
    );
  }
}

/// Whether a main-frame error means the page could not be loaded, rather than
/// a load the app or the page stopped on purpose: a new navigation (iOS
/// -999), a response the app handled itself, such as a download or a link
/// handed to another app (WebKit 102 "frame load interrupted" and 204
/// "plug-in handled load"), or Android's "net::ERR_ABORTED".
bool isLoadFailure({required int? code, required String description, required bool isIOS}) {
  if (isIOS) return code != -999 && code != 102 && code != 204;
  return !description.contains('ERR_ABORTED');
}

/// How long a web view put on the screen has to say it was created before the
/// offline screen and its retry take over (shell_page.dart). Creating one
/// takes well under a second; on 1 Nov 2026 some phones' WebView refused a
/// settings call while it was being made, and the student sat on the loader.
const webViewStartLimit = Duration(seconds: 15);

/// How late the start watch may end, by the phone's clock, and still be
/// believed. A watch that ends later than this did not run for the whole of
/// its time: the app was suspended, or its thread was held.
const webViewStartSlack = Duration(seconds: 5);

/// Whether the app can draw. Flutter builds no frame while the app is hidden
/// or paused (`SchedulerBinding.framesEnabled`), and a web view is made by a
/// frame: until the app is back on screen none can be created, however long
/// it waits. Unknown (before the phone has said) counts as on screen.
bool appCanDraw(AppLifecycleState? state) =>
    state == null ||
    state == AppLifecycleState.resumed ||
    state == AppLifecycleState.inactive;

/// Times a web view's creation, while the app can draw.
///
/// Through 1.2.40 (71) the fifteen seconds ran whatever the app was doing. An app
/// started without being shown (a device farm that runs each new build with
/// its screen off, an iPhone woken in the background), or left within its
/// first seconds, drew no frame, so no web view was even asked for; the
/// watch still ended, reported `Web view stopped: not created in time` and
/// put the offline screen up for a student who had a connection (13 such
/// reports from 1 to 8 Nov 2026, in pairs seconds apart, on every build from
/// 1.2.34 to 1.2.40, none with an error). Now the time only counts while the
/// app is on screen, and starts again when it comes back.
///
/// And the offline screen's retry made a new web view every six seconds
/// while there was none: one that needed longer than that was thrown away
/// before it could finish, each time. [mayRebuild] leaves a web view being
/// made its [limit] first, as `shouldRetryLoad` does for a page.
class WebViewStartWatch {
  WebViewStartWatch({
    required this.onStuck,
    this.limit = webViewStartLimit,
    this.slack = webViewStartSlack,
    DateTime Function()? now,
    AppLifecycleState? Function()? lifecycle,
  })  : _now = now ?? DateTime.now,
        _lifecycle = lifecycle ?? (() => null);

  /// The web view had its time, on screen, and never said it was created.
  final void Function() onStuck;
  final Duration limit;
  final Duration slack;
  final DateTime Function() _now;
  final AppLifecycleState? Function() _lifecycle;

  Timer? _timer;
  DateTime? _startedAt;
  bool _waiting = false;

  /// When the web view now being made started to be timed; null when none is
  /// being made, or the app cannot draw.
  DateTime? get startedAt => _startedAt;

  /// Whether a web view is being waited for.
  bool get waiting => _waiting;

  /// A web view was put on the screen.
  void start() {
    _waiting = true;
    _arm();
  }

  /// It said it was created.
  void created() {
    _waiting = false;
    _disarm();
  }

  /// The app went away or came back.
  void lifecycleChanged(AppLifecycleState state) {
    if (!_waiting) return;
    if (!appCanDraw(state)) {
      _disarm();
    } else if (_timer == null) {
      _arm();
    }
  }

  /// Whether the retry may make a new web view now: none is being made, or
  /// the one being made has had its time. Never while the app cannot draw: a
  /// new one could not be made either.
  bool mayRebuild() {
    if (!appCanDraw(_lifecycle())) return false;
    final started = _startedAt;
    return started == null || _now().difference(started) >= limit;
  }

  void dispose() {
    _waiting = false;
    _disarm();
  }

  void _disarm() {
    _timer?.cancel();
    _timer = null;
    _startedAt = null;
  }

  void _arm() {
    _disarm();
    if (!appCanDraw(_lifecycle())) return;
    final armedAt = _now();
    _startedAt = armedAt;
    _timer = Timer(limit, () {
      _timer = null;
      if (!_waiting) return;
      // Ended late by the phone's clock, or with the app away: it did not
      // have its time. Counted again from now, if the app can draw.
      if (!appCanDraw(_lifecycle()) ||
          _now().difference(armedAt) > limit + slack) {
        _arm();
        return;
      }
      onStuck();
    });
  }
}

/// How long a load started by the offline screen's retry is left to finish
/// before the next retry may start another (shell_page.dart). The retry ticks
/// every six seconds, and each new load cancelled the one before: on a slow
/// connection, such as from mainland China, where the portal's first load
/// takes several seconds, no load ever finished and the student sat on "No
/// internet connection" with a network that worked (6 Nov 2026).
const retryLoadPatience = Duration(seconds: 45);

/// Whether the offline screen's retry may start a new load now: none is under
/// way, or the one under way has had [retryLoadPatience] and not finished.
bool shouldRetryLoad({required DateTime? loadStartedAt, required DateTime now}) =>
    loadStartedAt == null || now.difference(loadStartedAt) >= retryLoadPatience;
