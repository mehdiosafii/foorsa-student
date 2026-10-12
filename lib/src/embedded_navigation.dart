/// WebKit reports iframe navigation here too. Keep embedded web players inside
/// their frame; ordinary links and non-web schemes still use the main policy.
bool isEmbeddedWebNavigation(Uri uri, {required bool? isForMainFrame}) {
  return isForMainFrame == false &&
      (uri.scheme == 'https' || uri.scheme == 'http');
}
