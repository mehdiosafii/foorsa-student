/// Learning and video frames stay embedded without receiving native privileges.
/// Sources: portal LearnScreen, portal-learn routes, and YouTube galleries.
const embeddedOrigins = {
  'https://student.foorsa.ma',
  'https://csca.foorsa.ma',
  'https://hsk.foorsa.ma',
  'https://hsk.guide',
  'https://www.youtube-nocookie.com',
  'https://www.youtube.com',
};

bool isEmbeddedWebNavigation(Uri uri, {required bool? isForMainFrame}) {
  return isForMainFrame == false &&
      uri.scheme == 'https' &&
      uri.hasAuthority &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty &&
      embeddedOrigins.contains(uri.origin);
}
