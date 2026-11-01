import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/push_registration.dart';

/// A phone for the registration, without Firebase.
class FakePlatform implements PushPlatform {
  FakePlatform({this.isIOS = true});

  @override
  final bool isIOS;
  Object? initError;
  int initCalls = 0;
  PushPermission answer = PushPermission.granted;
  PushPermission system = PushPermission.notDetermined;
  final asked = <bool>[];
  bool autoInit = false;
  String? apns = 'apns-token';

  /// The APNs token arrives after this many asks.
  int apnsAfter = 0;
  int apnsAsks = 0;
  String? refusal;
  Object? tokenError;
  String? fcm = 'fcm-token-${'x' * 140}';
  String? voip = 'a' * 64;

  @override
  Future<void> initialize() async {
    initCalls++;
    if (initError != null) throw initError!;
  }

  @override
  Future<PushPermission> permission({required bool ask}) async {
    asked.add(ask);
    return answer;
  }

  @override
  Future<PushPermission> systemPermission() async => system;

  @override
  Future<void> enableAutoInit() async => autoInit = true;

  @override
  Future<String?> apnsToken() async => apnsAsks++ >= apnsAfter ? apns : null;

  @override
  Future<String?> fcmToken() async {
    if (tokenError != null) throw tokenError!;
    return fcm;
  }

  @override
  Future<String?> voipToken() async => voip;

  @override
  Future<String?> apnsError() async => refusal;
}

void main() {
  late Directory dir;
  late List<String> sent;
  late DateTime clock;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('push_problems_');
    sent = [];
    clock = DateTime.utc(2026, 10, 31, 22);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  PushProblems problems({bool deliver = true}) => PushProblems(
        send: (message) async {
          if (deliver) sent.add(message);
          return deliver;
        },
        directory: () async => dir,
        now: () => clock,
      );

  late PushProblems reporter;
  setUp(() => reporter = problems());

  PushRegistration registration(FakePlatform platform) => PushRegistration(
        platform,
        reporter,
        apnsWait: const Duration(seconds: 1),
        apnsPoll: const Duration(milliseconds: 10),
        now: () => DateTime.now(),
      );

  /// Every report the registration asked for has been sent or dropped.
  Future<void> settle() => reporter.idle();

  test('an iPhone that can registers hands the portal everything the server stores', () async {
    final platform = FakePlatform();
    final device = await registration(platform).token(requestPermission: true, callsEnabled: true);
    expect(device['status'], 'ready');
    expect(device['platform'], 'ios');
    expect(device['token'], platform.fcm);
    expect(device['notificationVersion'], 2);
    expect(device['callsEnabled'], isTrue);
    expect(device['voipToken'], 'a' * 64);
    expect(device['permission'], 'granted');
    expect(platform.asked, [true]);
    expect(platform.autoInit, isTrue);
    await settle();
    expect(sent, isEmpty);
  });

  test('Apple’s token arriving a few seconds late is waited for, not given up on', () async {
    final platform = FakePlatform()..apnsAfter = 4;
    final device = await registration(platform).token(requestPermission: true, callsEnabled: false);
    expect(device['status'], 'ready');
    expect(platform.apnsAsks, greaterThan(4));
  });

  test('an Android phone does not wait for an APNs token', () async {
    final platform = FakePlatform(isIOS: false)..apns = null;
    final device = await registration(platform).token(requestPermission: true, callsEnabled: false);
    expect(device['status'], 'ready');
    expect(device['platform'], 'android');
    expect(platform.apnsAsks, 0);
  });

  test('a Firebase that cannot start says why, to the portal and to the crash board', () async {
    final platform = FakePlatform()..initError = FirebaseException(plugin: 'core', code: 'not-initialized', message: 'secret details');
    final device = await registration(platform).token(requestPermission: true, callsEnabled: false);
    expect(device, {'token': null, 'status': 'unconfigured', 'reason': 'FirebaseException core/not-initialized'});
    await settle();
    expect(sent, ['push: Firebase not configured: FirebaseException core/not-initialized']);
    expect(sent.single, isNot(contains('secret')));
  });

  test('a Firebase that did not start is tried again later, not written off for the app’s life', () async {
    var now = DateTime.utc(2026, 10, 31, 22);
    final platform = FakePlatform()..initError = PlatformException(code: 'channel-error');
    final steps = PushRegistration(platform, reporter, now: () => now, apnsWait: Duration.zero);
    expect((await steps.token(requestPermission: true, callsEnabled: false))['status'], 'unconfigured');
    expect((await steps.token(requestPermission: true, callsEnabled: false))['status'], 'unconfigured');
    expect(platform.initCalls, 1);
    platform.initError = null;
    now = now.add(const Duration(seconds: 31));
    expect((await steps.token(requestPermission: true, callsEnabled: false))['status'], 'ready');
    expect(platform.initCalls, 2);
  });

  test('a student who said no is reported once a day, and the portal is told', () async {
    final platform = FakePlatform()..answer = PushPermission.denied;
    final steps = registration(platform);
    expect(await steps.token(requestPermission: true, callsEnabled: false), {'token': null, 'status': 'denied', 'permission': 'denied'});
    await steps.token(requestPermission: true, callsEnabled: false);
    await settle();
    expect(sent, ['push: permission denied']);
  });

  test('an APNs token that never arrives says so, with Apple’s own refusal', () async {
    final platform = FakePlatform()
      ..apns = null
      ..refusal = 'NSCocoaErrorDomain 3000: no valid “aps-environment” entitlement string found for application';
    final device = await registration(platform).token(requestPermission: true, callsEnabled: true);
    expect(device['status'], 'pending');
    expect(device['reason'], 'apns');
    expect(device['apnsError'], platform.refusal);
    expect(device['token'], isNull);
    await settle();
    expect(sent, ['push: APNs token never arrived: ${platform.refusal}']);
  });

  test('a token Firebase refuses is named by its code, never its message', () async {
    final platform = FakePlatform()..tokenError = FirebaseException(plugin: 'firebase_messaging', code: 'unknown', message: 'with a path /var/mobile');
    final device = await registration(platform).token(requestPermission: true, callsEnabled: false);
    expect(device['status'], 'error');
    expect(device['reason'], 'token: FirebaseException firebase_messaging/unknown');
    await settle();
    expect(sent, ['push: token failed: FirebaseException firebase_messaging/unknown']);
  });

  test('a step that fails unexpectedly is named, reported and tried again, never thrown at the portal', () async {
    final platform = _ThrowingPermission();
    final device = await registration(platform).token(requestPermission: true, callsEnabled: false);
    expect(device, {'token': null, 'status': 'error', 'reason': 'permission: PlatformException no-activity'});
    await settle();
    expect(sent, ['push: permission failed: PlatformException no-activity']);
  });

  test('a token that comes back empty is not handed to the portal', () async {
    final platform = FakePlatform()..fcm = '';
    expect((await registration(platform).token(requestPermission: true, callsEnabled: false))['status'], 'error');
  });

  test('the Settings row reads where the phone stands without asking anything', () async {
    final platform = FakePlatform()..answer = PushPermission.notDetermined;
    expect(await registration(platform).status(), {'platform': 'ios', 'configured': true, 'permission': 'not_determined'});
    expect(platform.asked, [false]);
    final broken = FakePlatform()
      ..initError = PlatformException(code: 'channel-error')
      ..system = PushPermission.denied;
    expect(await registration(broken).status(),
        {'platform': 'ios', 'configured': false, 'reason': 'PlatformException channel-error', 'permission': 'denied'});
  });

  test('a reason goes to the crash board once a day per reason, across restarts', () async {
    await problems().report('push: permission denied');
    await problems().report('push: permission denied');
    await problems().report('push: APNs token never arrived');
    expect(sent, ['push: permission denied', 'push: APNs token never arrived']);
    clock = clock.add(const Duration(days: 1));
    await problems().report('push: permission denied');
    expect(sent.last, 'push: permission denied');
    expect(sent, hasLength(3));
  });

  test('a report that could not be sent is tried again, not counted as sent', () async {
    await problems(deliver: false).report('push: permission denied');
    await problems().report('push: permission denied');
    expect(sent, ['push: permission denied']);
  });

  test('a phone whose files cannot be written still reports, and never throws', () async {
    final reporter = PushProblems(
      send: (message) async {
        sent.add(message);
        return true;
      },
      directory: () async => throw const FileSystemException('no disk'),
    );
    await reporter.report('push: permission denied');
    expect(sent, ['push: permission denied']);
  });

  test('an error is named by its type and code only', () {
    expect(describePushError(PlatformException(code: 'channel-error', message: 'path /x')), 'PlatformException channel-error');
    expect(describePushError(StateError('boom')), 'StateError');
    expect(describePushError(FirebaseException(plugin: 'core', code: 'no-app')), 'FirebaseException core/no-app');
  });
}

class _ThrowingPermission extends FakePlatform {
  @override
  Future<PushPermission> permission({required bool ask}) async => throw PlatformException(code: 'no-activity');
}
