import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/chat_viewport.dart';

void main() {
  const portal = 'https://student.foorsa.ma';
  bool enabled(String? url, {bool isIOS = true}) => chatUsesStatusBarArea(
        url == null ? null : Uri.parse(url),
        portal,
        isIOS: isIOS,
      );

  test('iOS chat extends behind the status bar on direct and nested routes',
      () {
    for (final path in [
      '/contact/chat',
      '/contact/chat/',
      '/contact/chat?message=123#latest',
      '/portal/contact/chat'
    ]) {
      expect(enabled('$portal$path'), isTrue, reason: path);
    }
  });

  test('leaving chat restores the native safe area', () {
    for (final path in [
      '/',
      '/contact',
      '/documents',
      '/contact/chat/search'
    ]) {
      expect(enabled('$portal$path'), isFalse, reason: path);
    }
    expect(enabled(null), isFalse);
  });

  test('Android and other origins retain their existing layout', () {
    expect(enabled('$portal/contact/chat', isIOS: false), isFalse);
    for (final origin in [
      'https://other.example',
      'http://student.foorsa.ma',
      'https://student.foorsa.ma:8443'
    ]) {
      expect(enabled('$origin/contact/chat'), isFalse);
    }
  });
}
