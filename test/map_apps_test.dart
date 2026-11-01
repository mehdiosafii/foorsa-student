import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/map_apps.dart';

void main() {
  test('an iPhone names the map apps it has, in order, and nothing it lacks', () async {
    final asked = <String>[];
    final apps = await installedMapApps(
      isIOS: true,
      canLaunch: (uri) async {
        asked.add(uri.toString());
        return uri.scheme == 'iosamap' || uri.scheme == 'waze';
      },
    );
    expect(apps, ['amap', 'waze']);
    expect(asked, iosMapAppSchemes.values.toList());
  });

  test('Android is asked by package, and answers in the portal\'s names', () async {
    List<String>? asked;
    final apps = await installedMapApps(
      isIOS: false,
      canLaunch: (_) async => fail('Android is not asked by scheme'),
      installedPackages: (packages) async {
        asked = packages;
        return ['com.waze', 'com.google.android.apps.maps'];
      },
    );
    expect(asked, androidMapAppPackages.values.toList());
    expect(apps, ['google', 'waze']);
  });

  test('a phone that cannot be asked has none: the portal keeps Apple Maps and the chooser', () async {
    expect(await installedMapApps(isIOS: false, installedPackages: (_) async => const []), isEmpty);
  });

  test('the portal only knows these four', () {
    // foorsa-reward shared/mapApps.ts DETECTABLE_MAP_APPS.
    expect(iosMapAppSchemes.keys, ['google', 'amap', 'baidu', 'waze']);
    expect(androidMapAppPackages.keys, iosMapAppSchemes.keys);
  });

  test('iOS may ask about every app: each scheme is under LSApplicationQueriesSchemes', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    final start = plist.indexOf('<key>LSApplicationQueriesSchemes</key>');
    expect(start, greaterThanOrEqualTo(0));
    final list = plist.substring(start, plist.indexOf('</array>', start));
    for (final scheme in iosMapAppSchemes.values) {
      expect(list, contains('<string>${Uri.parse(scheme).scheme}</string>'), reason: scheme);
    }
  });

  test('Android 11 and later may ask about every app: each package is under <queries>', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final queries = manifest.substring(manifest.indexOf('<queries>'), manifest.indexOf('</queries>'));
    for (final package in androidMapAppPackages.values) {
      expect(queries, contains('<package android:name="$package"/>'), reason: package);
    }
    final activity = File('android/app/src/main/kotlin/ma/foorsa/student/MainActivity.kt').readAsStringSync();
    expect(activity, contains('"foorsa/map_apps"'));
  });

  test('an app\'s own address reaches the phone as the portal wrote it', () {
    // Uri would hand Amap `viewmap`.
    expect(Uri.parse('iosamap://viewMap?lat=1').toString(), 'iosamap://viewmap?lat=1');
    expect(appAddressAsWritten('iosamap://viewMap?sourceApplication=Foorsa&lat=30.26&dev=1'),
        'iosamap://viewMap?sourceApplication=Foorsa&lat=30.26&dev=1');
    expect(appAddressAsWritten(' androidamap://viewMap?x=1 '), 'androidamap://viewMap?x=1');
    expect(appAddressAsWritten('geo:30.26,120.12?q=30.26%2C120.12(Zhejiang%20University)'), startsWith('geo:'));
    // Web addresses keep going through Uri, as before.
    expect(appAddressAsWritten('https://maps.apple.com/?ll=1,2'), isNull);
    expect(appAddressAsWritten('http://example.com'), isNull);
    expect(appAddressAsWritten('not an address'), isNull);
  });
}
