import 'trusted_portal.dart';

/// Only the iOS chat supplies its own top safe inset and continuous backdrop.
/// Other portal screens retain the shell's existing top SafeArea.
bool chatUsesStatusBarArea(Uri? uri, String baseUrl, {required bool isIOS}) {
  if (!isIOS || !isTrustedPortalOrigin(uri, baseUrl)) return false;
  final path = uri!.path.replaceFirst(RegExp(r'/+$'), '');
  return path == '/contact/chat' || path == '/portal/contact/chat';
}
