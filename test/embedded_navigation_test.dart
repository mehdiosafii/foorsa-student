import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/embedded_navigation.dart';

void main() {
  test('embedded YouTube players stay inside the app', () {
    expect(
        isEmbeddedWebNavigation(
          Uri.parse('https://www.youtube-nocookie.com/embed/Ak6FvRBhaw8'),
          isForMainFrame: false,
        ),
        isTrue);
  });

  test('top-level links and unknown frames still use the external-link policy',
      () {
    final uri = Uri.parse('https://www.youtube.com/watch?v=Ak6FvRBhaw8');
    expect(isEmbeddedWebNavigation(uri, isForMainFrame: true), isFalse);
    expect(isEmbeddedWebNavigation(uri, isForMainFrame: null), isFalse);
  });

  test('iframe custom schemes do not bypass the external-link policy', () {
    for (final url in [
      'youtube://video/Ak6FvRBhaw8',
      'tel:123',
      'file:///tmp/video'
    ]) {
      expect(isEmbeddedWebNavigation(Uri.parse(url), isForMainFrame: false),
          isFalse);
    }
  });
}
