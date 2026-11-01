/// The map apps on the student's phone, answered to the portal's
/// FoorsaShellMapApps call so its Open in maps sheet offers only those
/// (foorsa-reward: src/portal/openInMaps.ts, shared/mapApps.ts; the owner,
/// 1 Nov 2026: "open on whatever maps he have in his phone").
///
/// An iPhone is asked with each app's own scheme: canOpenURL answers only for
/// schemes listed under LSApplicationQueriesSchemes in Info.plist. Android is
/// asked by package name (MainActivity.kt, channel `foorsa/map_apps`): Android
/// 11 and later answer only for packages listed under the manifest's `<queries>`.
/// A scheme does not do on Android: Dart's Uri lowercases the host, and an
/// intent filter's host is matched case by case. test/map_apps_test.dart holds
/// both lists to the ones here. Apple Maps is on every iPhone and the portal's
/// last Android choice is the phone's own chooser, which lists every map app,
/// so neither is asked about. The answer names apps, never what the student
/// does with them.
library;

import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

/// iPhone: canOpenURL looks at the scheme alone.
const Map<String, String> iosMapAppSchemes = {
  'google': 'comgooglemaps://',
  'amap': 'iosamap://',
  'baidu': 'baidumap://',
  'waze': 'waze://',
};

/// Android: each app's package.
const Map<String, String> androidMapAppPackages = {
  'google': 'com.google.android.apps.maps',
  'amap': 'com.autonavi.minimap',
  'baidu': 'com.baidu.BaiduMap',
  'waze': 'com.waze',
};

const MethodChannel _mapApps = MethodChannel('foorsa/map_apps');

Future<bool> _canLaunch(Uri uri) async {
  try {
    return await launcher.canLaunchUrl(uri);
  } catch (_) {
    return false;
  }
}

Future<List<String>> _installedPackages(List<String> packages) async {
  try {
    final found = await _mapApps.invokeListMethod<String>('installed', packages);
    return found ?? const [];
  } catch (_) {
    return const [];
  }
}

/// The apps among google, amap, baidu and waze that the phone has, in that
/// order. One that cannot be asked about counts as absent: the portal then
/// still offers Apple Maps on an iPhone and the chooser on Android.
Future<List<String>> installedMapApps({
  required bool isIOS,
  Future<bool> Function(Uri uri) canLaunch = _canLaunch,
  Future<List<String>> Function(List<String> packages) installedPackages = _installedPackages,
}) async {
  if (isIOS) {
    final found = <String>[];
    for (final entry in iosMapAppSchemes.entries) {
      if (await canLaunch(Uri.parse(entry.value))) found.add(entry.key);
    }
    return found;
  }
  final present = (await installedPackages(androidMapAppPackages.values.toList())).toSet();
  return [
    for (final entry in androidMapAppPackages.entries)
      if (present.contains(entry.value)) entry.key,
  ];
}

/// The address to hand the phone for [raw], an address the portal asked to
/// open: an app's own address exactly as written, because Dart's Uri lowercases
/// the host and an app may read it case by case (Amap's `viewMap`, on both
/// platforms); null for a web address or anything unreadable, which keeps
/// going through Uri as before.
String? appAddressAsWritten(String raw) {
  final text = raw.trim();
  final uri = Uri.tryParse(text);
  if (uri == null || uri.scheme.isEmpty) return null;
  if (uri.scheme == 'http' || uri.scheme == 'https') return null;
  return text;
}
