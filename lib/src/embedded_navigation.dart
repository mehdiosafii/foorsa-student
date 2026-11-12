/// WebKit reports iframe navigation here too. Keep embedded web players inside
/// their frame; ordinary links and non-web schemes still use the main policy.
bool isEmbeddedWebNavigation(Uri uri, {required bool? isForMainFrame}) {
  return isForMainFrame == false &&
      (uri.scheme == 'https' || uri.scheme == 'http');
}

/// A file of the portal's own that a link opens in a new window.
class PreviewableFile {
  const PreviewableFile(this.name, this.mime);
  final String name;
  final String mime;
}

const _previewMimes = {
  'webp': 'image/webp',
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'gif': 'image/gif',
  'pdf': 'application/pdf',
};

/// The picture or PDF [uri] names, for the app's own viewer; null for a page.
///
/// Through 1.2.40 (71) a link that opens one of the portal's own files in a
/// new window ("Tap the sample to view it full size", under every paper's
/// help) was loaded into the web view itself: the whole app became a bare
/// picture, with nothing to close it, and an iPhone has no back button (the
/// stress test, 11 Nov 2026). A page of the portal still loads in the web
/// view, as before.
PreviewableFile? previewableFile(Uri uri) {
  if (uri.scheme != 'https' && uri.scheme != 'http') return null;
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.isEmpty) return null;
  final name = segments.last;
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) return null;
  final mime = _previewMimes[name.substring(dot + 1).toLowerCase()];
  return mime == null ? null : PreviewableFile(name, mime);
}
