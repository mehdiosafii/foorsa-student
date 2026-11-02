import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/student_adhan.dart';

void main() {
  final now = DateTime.utc(2026, 11, 1, 10);
  Map<String, Object?> call(String at, {String prayer = 'asr', String sound = 'full', String title = 'Asr · 15:16', String body = 'It is time for Asr.'}) =>
      {'at': at, 'prayer': prayer, 'sound': sound, 'title': title, 'body': body};

  test('keeps the calls that can be scheduled, soonest first, one a minute', () {
    final calls = validAdhanCalls([
      call('2026-11-02T04:12:00.000Z', prayer: 'fajr', sound: 'short'),
      call('2026-11-01T14:16:00.000Z'),
      call('2026-11-01T14:16:00.000Z'),
      call('2026-11-01T09:00:00.000Z'), // already past
      call('2026-11-30T09:00:00.000Z'), // too far ahead
      call('2026-11-01T16:43:00.000Z', prayer: 'sunrise'), // never called
      call('2026-11-01T16:43:00.000Z', sound: 'loud'),
      call('not a time'),
      'not a call',
    ], now);
    expect(calls.map((c) => c.prayer), ['asr', 'fajr']);
    expect(calls.first.at, DateTime.utc(2026, 11, 1, 14, 16));
    expect(calls.first.full, isTrue);
    expect(calls.last.full, isFalse);
  });

  test('Fajr always calls with the opening, whatever was asked', () {
    final calls = validAdhanCalls([call('2026-11-02T04:12:00.000Z', prayer: 'fajr', sound: 'full')], now);
    expect(calls.single.full, isFalse);
  });

  test('a text is one short line: control characters and length are cut, an empty one refused', () {
    final calls = validAdhanCalls([
      call('2026-11-01T14:16:00.000Z', title: 'Asr\n· 15:16\u0007', body: 'x' * 500),
      call('2026-11-01T17:43:00.000Z', prayer: 'maghrib', title: '   '),
    ], now);
    expect(calls.single.title, 'Asr · 15:16');
    expect(calls.single.body.length, 200);
  });

  test('holds at most the calls an iPhone keeps room for', () {
    final many = [for (var i = 0; i < 60; i++) call(now.add(Duration(hours: i + 1)).toIso8601String())];
    expect(validAdhanCalls(many, now), hasLength(adhanMaxCalls));
  });

  test('the sounds ship: the iPhone opening and the two Android channels, kept from shrinking', () {
    final caf = File(adhanIosSoundAsset);
    expect(caf.existsSync(), isTrue);
    // IMA4 at 22.05 kHz mono: about 11 KB a second, so under 30 seconds is under 340 KB.
    expect(caf.lengthSync(), lessThan(340 * 1024));
    expect(File('android/app/src/main/res/raw/$adhanAndroidSound.ogg').existsSync(), isTrue);
    expect(File('android/app/src/main/res/raw/$adhanAndroidFajrSound.ogg').existsSync(), isTrue);
    final keep = File('android/app/src/main/res/raw/keep.xml').readAsStringSync();
    expect(keep, contains('@raw/$adhanAndroidSound'));
    expect(keep, contains('@raw/$adhanAndroidFajrSound'));
    expect(File('pubspec.yaml').readAsStringSync(), contains('- assets/sounds/adhan/'));
  });

  test('Android may call on the minute, with the permission the student grants, never USE_EXACT_ALARM', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('android.permission.SCHEDULE_EXACT_ALARM'));
    expect(manifest, isNot(contains('android.permission.USE_EXACT_ALARM')));
    // Scheduled notifications survive a restart.
    expect(manifest, contains('ScheduledNotificationBootReceiver'));
  });
}
