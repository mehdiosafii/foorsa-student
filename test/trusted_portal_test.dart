import 'package:flutter_test/flutter_test.dart';
import '../lib/src/trusted_portal.dart';

void main() {
  const portal = 'https://student.foorsa.ma';
  test('allows portal navigation and the default HTTPS port', () {
    expect(isTrustedPortalOrigin(Uri.parse('$portal/documents'), portal), isTrue);
    expect(isTrustedPortalOrigin(Uri.parse('$portal:443'), portal), isTrue);
  });
  test('rejects missing, insecure, sibling and lookalike origins', () {
    expect(isTrustedPortalOrigin(null, portal), isFalse);
    for (final url in [
      'http://student.foorsa.ma',
      'https://foorsa.ma',
      'https://student.foorsa.ma.attacker.example',
      'https://attacker.example@other.foorsa.ma',
      'https://student.foorsa.ma:8443',
    ]) {
      expect(isTrustedPortalOrigin(Uri.parse(url), portal), isFalse);
    }
  });
  test('staging requires the exact configured host and port', () {
    const staging = 'https://staging.example:8443';
    expect(isTrustedPortalOrigin(Uri.parse('$staging/documents'), staging), isTrue);
    expect(isTrustedPortalOrigin(Uri.parse('https://staging.example'), staging), isFalse);
    expect(isTrustedPortalOrigin(Uri.parse(portal), staging), isFalse);
  });
}
