import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_crm/src/browser_sign_in.dart';
import 'package:foorsa_crm/src/config.dart';
import 'package:foorsa_crm/src/crm_shell.dart';
import 'package:foorsa_crm/src/downloads.dart';

void main() {
  group('notification routes', () {
    test('a CRM path opens on the CRM', () {
      expect(crmAddressFor('/?chat=12')?.toString(), 'https://home.foorsa.ma/?chat=12');
      expect(crmAddressFor('/applicants/5603')?.host, 'home.foorsa.ma');
    });

    test('anything that is not a CRM path is refused', () {
      expect(crmAddressFor('https://evil.example/x'), isNull);
      expect(crmAddressFor('//evil.example/x'), isNull);
      expect(crmAddressFor(r'/\evil.example'), isNull);
      expect(crmAddressFor('javascript:alert(1)'), isNull);
      expect(crmAddressFor(''), isNull);
    });
  });

  group('links', () {
    test('Foorsa stays in the app', () {
      for (final url in [
        'https://home.foorsa.ma/applicants',
        'https://student.foorsa.ma/',
        'https://flight-tracking.foorsa.ma/RAX777/2026-09-14/0215',
        'https://foorsa.ma/',
      ]) {
        expect(routeFor(Uri.parse(url)), LinkRoute.stay, reason: url);
      }
    });

    test('other sites and apps leave the app', () {
      for (final url in [
        'https://wa.me/212600000000',
        'tel:+212537911271',
        'mailto:contact@foorsa.ma',
        'https://maps.google.com/?q=Rabat',
        'https://foorsa.ma.evil.example/',
        'https://notfoorsa.ma/',
      ]) {
        expect(routeFor(Uri.parse(url)), LinkRoute.external, reason: url);
      }
    });

    test('schemes nobody should be sent to are refused', () {
      expect(routeFor(Uri.parse('file:///etc/passwd')), LinkRoute.block);
      expect(routeFor(Uri.parse('javascript:alert(1)')), LinkRoute.block);
    });

    test('only the CRM host is trusted with the bridge', () {
      expect(CrmConfig.isCrm(Uri.parse('https://home.foorsa.ma/x')), isTrue);
      expect(CrmConfig.isCrm(Uri.parse('https://student.foorsa.ma/')), isFalse);
      expect(CrmConfig.isCrm(null), isFalse);
    });
  });

  group('status bar colour', () {
    test('reads what the CRM reports', () {
      expect(parseCssColor('#ffffff'), const Color(0xFFFFFFFF));
      expect(parseCssColor('#101b2d'), const Color(0xFF101B2D));
      expect(parseCssColor('rgb(11, 18, 32)'), const Color(0xFF0B1220));
      expect(parseCssColor('rgba(11,18,32,0.9)'), const Color(0xFF0B1220));
    });

    test('ignores what it cannot use', () {
      expect(parseCssColor('rgba(0,0,0,0.1)'), isNull);
      expect(parseCssColor('navy'), isNull);
      expect(parseCssColor('#fff'), isNull);
    });
  });

  group('sign-in in the browser', () {
    test('the challenge is RFC 7636 S256', () {
      // RFC 7636, appendix B.
      expect(SignInSecret.challengeFor('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'),
          'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM');
    });

    test('a random secret is long and unpadded', () {
      final secret = SignInSecret.random();
      expect(secret.verifier.length, greaterThanOrEqualTo(43));
      expect(secret.verifier.contains('='), isFalse);
      expect(secret.challenge, SignInSecret.challengeFor(secret.verifier));
    });

    test('the browser opens the CRM page with the challenge only', () {
      final url = browserSignInUrl('abc', method: 'google');
      expect(url.toString(), 'https://home.foorsa.ma/native-sign-in?challenge=abc&method=google');
    });

    test('the code comes back to the CRM with the verifier', () {
      final url = redeemUrl('foorsacrm://signed-in?code=XYZ', 'verifier');
      expect(url?.toString(),
          'https://home.foorsa.ma/api/auth/native-handoff/redeem?code=XYZ&verifier=verifier');
      expect(redeemUrl('foorsacrm://signed-in', 'v'), isNull);
      expect(redeemUrl('foorsacrm://signed-in?code=${'x' * 300}', 'v'), isNull);
    });
  });

  group('downloads', () {
    test('file names are safe and keep their type', () {
      expect(safeFileName('Receipt.pdf'), 'Receipt.pdf');
      expect(safeFileName('../../etc/passwd'), '.._.._etc_passwd');
      expect(safeFileName('', mime: 'application/pdf'), 'Foorsa file.pdf');
      expect(safeFileName('export', mime: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'), 'export.xlsx');
      expect(safeFileName('a:b*c?.csv'), 'a_b_c_.csv');
    });

    test('the page script reads blobs and keeps them long enough', () {
      expect(downloadBridgeScript, contains("callHandler('FoorsaBridge'"));
      expect(downloadBridgeScript, contains('URL.revokeObjectURL'));
      expect(downloadBridgeScript, contains("action: 'saveFile'"));
      expect(downloadBridgeScript, contains("action: 'print'"));
    });
  });
}
