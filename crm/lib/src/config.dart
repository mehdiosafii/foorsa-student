/// Where the Foorsa CRM app points, and what it keeps inside itself.
library;

class CrmConfig {
  CrmConfig._();

  /// The staff platform the app shows. A build can point at a preview with
  /// --dart-define=FOORSA_CRM_URL=https://... without touching production.
  static const String baseUrl = String.fromEnvironment(
    'FOORSA_CRM_URL',
    defaultValue: 'https://home.foorsa.ma',
  );

  /// The app's name in the user agent. The CRM finds its native app by
  /// "FoorsaApp" (src/lib/nativeBridge.ts in foorsa-reward); "FoorsaCrmApp"
  /// tells it which one. Never "FoorsaStudentApp": that is the student app.
  static const String userAgentProduct = 'FoorsaApp FoorsaCrmApp';

  /// The JS bridge the CRM calls (nativeBridge.ts): getPushToken, appInfo.
  static const String bridgeName = 'FoorsaBridge';

  /// The custom scheme the phone's browser hands a sign-in back on
  /// (lib/src/browser_sign_in.dart, /native-sign-in on the CRM).
  static const String callbackScheme = 'foorsacrm';

  /// Foorsa's own pages stay in the app; anything else opens in the phone's
  /// browser or the app it belongs to (WhatsApp, Maps, the phone).
  static bool isFoorsa(Uri uri) {
    if (uri.scheme != 'https' && uri.scheme != 'http') return false;
    final host = uri.host.toLowerCase();
    return host == 'foorsa.ma' || host.endsWith('.foorsa.ma') || host == Uri.parse(baseUrl).host;
  }

  /// The staff platform's own host, where the app's bridge is trusted.
  static bool isCrm(Uri? uri) =>
      uri != null && uri.host.toLowerCase() == Uri.parse(baseUrl).host.toLowerCase();

  /// The status bar's colour until the CRM reports its own: the sign-in
  /// page's top colour (SIGN_IN_THEME_COLOR in staffChrome.ts).
  static const int signInTopColor = 0xFF0B1220;

  /// The Foorsa navy behind the loading screen.
  static const int navy = 0xFF041229;
}
