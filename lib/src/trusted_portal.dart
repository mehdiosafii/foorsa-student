/// Camera capabilities belong only to the configured HTTPS portal origin.
bool isTrustedPortalOrigin(Uri? uri, String baseUrl) {
  if (uri == null) return false;
  final configured = Uri.parse(baseUrl);
  return uri.scheme == 'https' &&
      uri.scheme == configured.scheme &&
      uri.host.toLowerCase() == configured.host.toLowerCase() &&
      uri.port == configured.port;
}
