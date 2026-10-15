/// Central configuration for the Foorsa Student shell.
library;

class AppConfig {
  AppConfig._();

  /// The student portal this shell wraps.
  static const String baseUrl = 'https://student.foorsa.ma';

  /// Exact owned HTTPS origins allowed for top-level navigation.
  static const Set<String> internalOrigins = {
    baseUrl,
    'https://foorsa.ma',
    'https://www.foorsa.ma',
  };

  static bool isInternal(Uri uri) =>
      uri.scheme == 'https' &&
      uri.hasAuthority &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty &&
      internalOrigins.contains(uri.origin);

  /// Native permissions are reserved for the student portal.
  static bool isNativePermissionOrigin(Uri uri) =>
      uri.scheme == 'https' &&
      uri.hasAuthority &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty &&
      uri.origin == baseUrl;

  /// User-Agent product so the portal can detect the native shell.
  static const String userAgentProduct = 'FoorsaStudentApp';

  /// JS bridge handler name (kept identical to the team app contract).
  static const String bridgeName = 'FoorsaBridge';

  static const int brandColorValue = 0xFF183250;
}
