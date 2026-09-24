/// Central configuration for the Foorsa Student shell.
library;

class AppConfig {
  AppConfig._();

  /// The student portal this shell wraps.
  static const String baseUrl = 'https://student.foorsa.ma';

  /// Hosts that stay inside the WebView. Anything else opens externally.
  static const List<String> internalHosts = <String>[
    'student.foorsa.ma',
    'foorsa.ma',
    'www.foorsa.ma',
  ];
  static const List<String> internalHostSuffixes = <String>[
    '.foorsa.ma',
    '.supabase.co',
    '.vercel.app',
  ];

  /// User-Agent product so the portal can detect the native shell.
  static const String userAgentProduct = 'FoorsaStudentApp';

  /// JS bridge handler name (kept identical to the team app contract).
  static const String bridgeName = 'FoorsaBridge';

  static const int brandColorValue = 0xFF183250;
}
