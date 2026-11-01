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
