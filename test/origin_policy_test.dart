import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/config.dart';
import 'package:foorsa_student/src/embedded_navigation.dart';

void main() {
  test(
      'main navigation and native permissions have separate exact HTTPS origins',
      () {
    expect(
        AppConfig.isInternal(Uri.parse('https://foorsa.ma/privacy')), isTrue);
    expect(AppConfig.isNativePermissionOrigin(Uri.parse('https://foorsa.ma')),
        isFalse);
    expect(
        AppConfig.isNativePermissionOrigin(
            Uri.parse('https://student.foorsa.ma:443/app')),
        isTrue);
    for (final value in [
      'https:',
      'https:///missing-host',
      'http://student.foorsa.ma',
      'https://student.foorsa.ma:8443',
      'https://evil.vercel.app',
      'https://evil.supabase.co',
      'https://other.foorsa.ma',
      'https://student.foorsa.ma.evil.com',
      'https://student.foorsa.ma@evil.com',
      'file:///tmp/document',
    ]) {
      expect(AppConfig.isInternal(Uri.parse(value)), isFalse, reason: value);
      expect(AppConfig.isNativePermissionOrigin(Uri.parse(value)), isFalse,
          reason: value);
    }
  });
  test('learning and media frames stay embedded without native privileges', () {
    for (final host in [
      'csca.foorsa.ma',
      'hsk.foorsa.ma',
      'hsk.guide',
      'www.youtube-nocookie.com',
      'www.youtube.com'
    ]) {
      final uri = Uri.parse('https://$host/embed');
      expect(isEmbeddedWebNavigation(uri, isForMainFrame: false), isTrue);
      expect(AppConfig.isNativePermissionOrigin(uri), isFalse);
    }
    for (final value in [
      'https://evil.vercel.app',
      'http://csca.foorsa.ma',
      'https://hsk.foorsa.ma:8443'
    ]) {
      expect(isEmbeddedWebNavigation(Uri.parse(value), isForMainFrame: false),
          isFalse);
    }
  });
}
