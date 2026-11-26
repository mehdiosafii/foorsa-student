/// Google and passkey sign-in, in the phone's own browser.
///
/// Google refuses its sign-in inside an app's web view ("disallowed_useragent"),
/// and a passkey for home.foorsa.ma is the browser's to use. So the CRM's
/// sign-in page, inside the app, sends those two to the phone's browser
/// (ASWebAuthenticationSession on iPhone and iPad, a Custom Tab on Android):
///
/// 1. The app makes a secret (the verifier) and sends only its SHA-256 (the
///    challenge) to `/native-sign-in` on the CRM.
/// 2. The person signs in there as on any browser, or is already signed in.
///    The page asks the CRM for a one-time code tied to that challenge and
///    hands it back to the app on `foorsacrm://signed-in?code=…`.
/// 3. The app's web view opens `/api/auth/native-handoff/redeem` with the code
///    and the verifier; the CRM checks both, signs the web view in and opens
///    the home page.
///
/// The code works once, for two minutes, and only with the verifier, which
/// never leaves the app: another app catching the code on Android cannot use
/// it.
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import 'config.dart';

/// The verifier and its challenge (RFC 7636's S256, base64url, no padding).
class SignInSecret {
  SignInSecret(this.verifier) : challenge = challengeFor(verifier);

  factory SignInSecret.random([Random? random]) {
    final rng = random ?? Random.secure();
    final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
    return SignInSecret(base64Url.encode(bytes).replaceAll('=', ''));
  }

  final String verifier;
  final String challenge;

  static String challengeFor(String verifier) =>
      base64Url.encode(sha256.convert(utf8.encode(verifier)).bytes).replaceAll('=', '');
}

/// The page the browser opens.
Uri browserSignInUrl(String challenge, {String? method}) =>
    Uri.parse(CrmConfig.baseUrl).replace(path: '/native-sign-in', queryParameters: {
      'challenge': challenge,
      if (method != null && method.isNotEmpty) 'method': method,
    });

/// What the web view opens with the code the browser handed back, or null
/// when the callback carries no code.
Uri? redeemUrl(String callback, String verifier) {
  final uri = Uri.tryParse(callback);
  final code = uri?.queryParameters['code'];
  if (code == null || code.isEmpty || code.length > 200) return null;
  return Uri.parse(CrmConfig.baseUrl).replace(
    path: '/api/auth/native-handoff/redeem',
    queryParameters: {'code': code, 'verifier': verifier},
  );
}

/// The outcome of a sign-in in the browser.
enum BrowserSignInResult { signedIn, cancelled, failed }

/// Opens the browser and, once it hands a code back, loads the redeem page
/// with [load]. Never throws.
Future<BrowserSignInResult> signInInBrowser(
  Future<void> Function(Uri url) load, {
  String? method,
}) async {
  final secret = SignInSecret.random();
  try {
    final callback = await FlutterWebAuth2.authenticate(
      url: browserSignInUrl(secret.challenge, method: method).toString(),
      callbackUrlScheme: CrmConfig.callbackScheme,
      // The browser's own session: someone already signed in to
      // home.foorsa.ma there is signed in to the app with one tap.
      options: const FlutterWebAuth2Options(preferEphemeral: false),
    );
    final url = redeemUrl(callback, secret.verifier);
    if (url == null) return BrowserSignInResult.failed;
    await load(url);
    return BrowserSignInResult.signedIn;
  } on PlatformException catch (e) {
    return e.code == 'CANCELED' ? BrowserSignInResult.cancelled : BrowserSignInResult.failed;
  } catch (_) {
    return BrowserSignInResult.failed;
  }
}
