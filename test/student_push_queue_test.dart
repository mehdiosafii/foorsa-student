// The push service with a phone behind it: what waits on what. The stress
// test of 11 Nov 2026 ran it as a phone in mainland China, where Google never
// answers, and as a student with no calendar reminders.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/push_registration.dart';
import 'package:foorsa_student/src/student_adhan.dart';
import 'package:foorsa_student/src/student_push.dart';

/// A phone in mainland China: everything on the phone answers, Google never does.
class _China implements PushPlatform {
  _China({required this.isIOS});
  @override
  final bool isIOS;
  @override
  Future<void> initialize() async {}
  @override
  Future<PushPermission> permission({required bool ask}) async => PushPermission.granted;
  @override
  Future<PushPermission> systemPermission() async => PushPermission.granted;
  @override
  Future<void> enableAutoInit() async {}
  @override
  Future<String?> apnsToken() async => isIOS ? 'ab12' : null;
  @override
  Future<String?> fcmToken() => Completer<String?>().future;
  @override
  Future<String?> voipToken() async => isIOS ? 'cd34' : null;
  @override
  Future<String?> apnsError() async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const local = MethodChannel('dexterous.com/flutter/local_notifications');
  late Directory dir;
  late List<MethodCall> calls;
  /// Notification ids the phone refuses to schedule.
  late Set<int> refused;

  setUpAll(() {
    // The local notifications plugin as an Android phone has it: on a phone
    // the plugin registers this itself.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    FlutterLocalNotificationsPlatform.instance = AndroidFlutterLocalNotificationsPlugin();
  });
  tearDownAll(() => debugDefaultTargetPlatformOverride = null);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('student_push_');
    calls = [];
    refused = {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(local, (call) async {
      calls.add(call);
      if (call.method == 'initialize' || call.method == 'requestNotificationsPermission') return true;
      if (call.method == 'zonedSchedule' && refused.contains((call.arguments as Map)['id'])) {
        throw PlatformException(code: 'error', message: 'Must be a date in the future');
      }
      return null;
    });
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(local, null);
    await dir.delete(recursive: true);
  });

  StudentPush service(PushPlatform phone, {Duration fcmWait = const Duration(seconds: 2)}) => StudentPush(
        openChat: () async {},
        chatIsVisible: () async => false,
        openUpdate: (_) async {},
        openCalendar: () async {},
        platform: phone,
        problems: PushProblems(send: (_) async => true, directory: () async => dir),
        directory: () async => dir,
        fcmWait: fcmWait,
      );

  int count(String method) => calls.where((call) => call.method == method).length;

  for (final ios in [true, false]) {
    test('${ios ? 'an iPhone' : 'an Android phone'} that cannot reach Google still answers the adhan, the calendar and Settings at once', () async {
      final push = service(_China(isIOS: ios));
      final watch = Stopwatch()..start();
      final token = push.token();
      // The portal asks these as its screens open, right behind the token.
      final adhan = await push.adhan('adhanStatus', {'owner': '42'});
      final calendar = await push.calendar('calendarStatus', {'owner': '42'});
      final status = await push.status();
      expect(watch.elapsedMilliseconds, lessThan(1000), reason: 'none of them waits for Google');
      expect(adhan['supported'], isTrue);
      expect(calendar['supported'], isTrue);
      expect(status['configured'], isTrue);
      // The registration itself ends when Google's time is up.
      final answer = await token;
      expect(watch.elapsedMilliseconds, greaterThanOrEqualTo(1900));
      expect(answer['token'], ios ? 'apns:ab12' : isNull);
      push.dispose();
    });
  }

  test('a student with no reminders: asking where the calendar stands cancels nothing', () async {
    final push = service(_China(isIOS: false));
    await push.calendar('calendarStatus', {'owner': '42'});
    await push.calendar('calendarSync', {'owner': '42', 'reminders': <Object>[]});
    await push.calendar('calendarStatus', {'owner': '42'});
    expect(count('cancel'), 0, reason: 'sixty cancels a call rewrote the phone\'s whole schedule each time');
    // Turning reminders off still cancels them, once.
    await push.calendar('calendarClear', {'owner': '42'});
    expect(count('cancel'), 60);
    push.dispose();
  });

  test('another student signing in on the phone clears the first one\'s reminders', () async {
    final push = service(_China(isIOS: false));
    final at = DateTime.now().toUtc().add(const Duration(hours: 3)).toIso8601String();
    expect((await push.calendar('calendarEnable', {'owner': '42'}))['enabled'], isTrue);
    expect((await push.calendar('calendarSync', {'owner': '42', 'reminders': [{'at': at}]}))['count'], 1);
    final cancelled = count('cancel');
    final other = await push.calendar('calendarStatus', {'owner': '77'});
    expect(other['enabled'], isFalse);
    expect(count('cancel'), cancelled + 60);
    push.dispose();
  });

  test('one reminder the phone refuses does not turn the others, or the reminders, off', () async {
    final push = service(_China(isIOS: false));
    List<Map<String, String>> reminders(int from) => [
          for (var hour = from; hour < from + 3; hour++)
            {'at': DateTime.now().toUtc().add(Duration(hours: hour)).toIso8601String()},
        ];
    await push.calendar('calendarEnable', {'owner': '42'});
    expect((await push.calendar('calendarSync', {'owner': '42', 'reminders': reminders(1)}))['count'], 3);
    // The second sync: the phone refuses the first of the three.
    refused = {1900000000};
    final later = reminders(5);
    final synced = await push.calendar('calendarSync', {'owner': '42', 'reminders': later});
    expect(synced['enabled'], isTrue);
    expect(synced['count'], 2);
    final kept = jsonDecode(File('${dir.path}/calendar-reminders.json').readAsStringSync()) as Map;
    expect(kept['enabled'], isTrue, reason: 'the next start of the app still has the reminders on');
    expect(kept['count'], 2);
    // A schedule with a reminder missing is written again by the next sync.
    refused = {};
    final scheduled = count('zonedSchedule');
    expect((await push.calendar('calendarSync', {'owner': '42', 'reminders': later}))['count'], 3);
    expect(count('zonedSchedule'), scheduled + 3);
    // And one written whole is not written twice.
    await push.calendar('calendarSync', {'owner': '42', 'reminders': later});
    expect(count('zonedSchedule'), scheduled + 3);
    push.dispose();
  });

  test('one adhan call the phone refuses leaves the later prayers scheduled', () async {
    final push = service(_China(isIOS: false));
    final now = DateTime.now().toUtc();
    final calls3 = [
      for (var hour = 1; hour <= 3; hour++)
        {'at': now.add(Duration(hours: hour)).toIso8601String(), 'prayer': 'dhuhr', 'title': 'Dhuhr', 'body': 'It is time to pray.', 'sound': 'full'},
    ];
    refused = {adhanNotificationBase};
    final answer = await push.adhan('adhanSync', {'owner': '42', 'fingerprint': 'a', 'calls': calls3});
    expect(answer['enabled'], isTrue);
    expect(answer['count'], 2);
    expect(count('zonedSchedule'), 3);
    push.dispose();
  });
}
