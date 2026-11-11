import 'dart:async';
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

  /// Firebase's token never comes (Google's servers do not answer, as in China).
  bool tokenHangs = false;
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

  /// Each request for Firebase's token that Google has not answered yet.
  final unanswered = <Completer<String?>>[];

  @override
  Future<String?> fcmToken() async {
    if (tokenHangs) {
      final request = Completer<String?>();
      unanswered.add(request);
      return request.future;
    }
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
        fcmWait: const Duration(milliseconds: 200),
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
    final platform = FakePlatform(isIOS: false)..tokenError = FirebaseException(plugin: 'firebase_messaging', code: 'unknown', message: 'with a path /var/mobile');
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
    final platform = FakePlatform(isIOS: false)..fcm = '';
    expect((await registration(platform).token(requestPermission: true, callsEnabled: false))['status'], 'error');
  });

  test('an iPhone that cannot reach Google registers with Apple, and its calls still ring', () async {
    final platform = FakePlatform()
      ..apns = 'AB${'c' * 62}'
      ..tokenError = FirebaseException(plugin: 'firebase_messaging', code: 'unknown', message: 'no network');
    final device = await registration(platform).token(requestPermission: true, callsEnabled: true);
    expect(device['status'], 'ready');
    expect(device['platform'], 'ios');
    expect(device['token'], 'apns:ab${'c' * 62}');
    expect(device['voipToken'], 'a' * 64);
    expect(device['callsEnabled'], isTrue);
    expect(device.containsKey('apnsToken'), isFalse);
    await settle();
    expect(sent, ['push: token failed: FirebaseException firebase_messaging/unknown (registered with Apple)']);
  });

  test('a Firebase token that never comes is given up on, and the iPhone registers with Apple', () async {
    final platform = FakePlatform()..tokenHangs = true;
    final started = DateTime.now();
    final device = await registration(platform).token(requestPermission: true, callsEnabled: false);
    expect(DateTime.now().difference(started), lessThan(const Duration(seconds: 5)));
    expect(device['token'], 'apns:apns-token');
    await settle();
    expect(sent, ['push: token failed: timeout (registered with Apple)']);
  });

  test('an Android phone that cannot reach Google says so, with nothing to register', () async {
    final platform = FakePlatform(isIOS: false)
      ..apns = null
      ..tokenHangs = true;
    final device = await registration(platform).token(requestPermission: true, callsEnabled: false);
    expect(device, {'token': null, 'status': 'error', 'reason': 'token: timeout', 'permission': 'granted'});
  });

  // The stress test, 11 Nov 2026: the portal asks for the token at every
  // return to the app and after each failure, and in mainland China each of
  // those calls waited the whole of Firebase's time again.
  test('a Google that did not answer is not waited for again, until it answers', () async {
    final platform = FakePlatform()..tokenHangs = true;
    final push = registration(platform);
    final first = Stopwatch()..start();
    final apple = await push.token(requestPermission: true, callsEnabled: false);
    expect(first.elapsedMilliseconds, greaterThanOrEqualTo(190), reason: 'the first call gives Google its time');
    expect(apple['token'], 'apns:apns-token');

    final again = Stopwatch()..start();
    final second = await push.token(requestPermission: true, callsEnabled: false);
    expect(again.elapsedMilliseconds, lessThan(100), reason: 'the next call does not wait again');
    expect(second['token'], 'apns:apns-token');
    expect(second['status'], 'ready');
    // One request stays out, however often the portal asks.
    await push.token(requestPermission: true, callsEnabled: false);
    expect(platform.unanswered, hasLength(2));

    // Google answers (a VPN turned on): the next call waits for the token and has it.
    platform.tokenHangs = false;
    platform.unanswered.last.complete(platform.fcm);
    await Future<void>.delayed(Duration.zero);
    final third = await push.token(requestPermission: true, callsEnabled: false);
    expect(third['token'], platform.fcm);
    expect(third['apnsToken'], 'apns-token');
    await settle();
  });

  test('an Android phone that cannot reach Google is told so at once the second time, and asked again later', () async {
    final platform = FakePlatform(isIOS: false)..tokenHangs = true;
    final push = PushRegistration(platform, reporter,
        fcmWait: const Duration(milliseconds: 200), fcmQuiet: const Duration(milliseconds: 400), now: () => DateTime.now());
    expect((await push.token(requestPermission: true, callsEnabled: false))['reason'], 'token: timeout');
    final again = Stopwatch()..start();
    expect((await push.token(requestPermission: true, callsEnabled: false))['reason'], 'token: timeout');
    expect(again.elapsedMilliseconds, lessThan(100));
    // Once the quiet time has passed Google is given its time again.
    await Future<void>.delayed(const Duration(milliseconds: 450));
    final later = Stopwatch()..start();
    expect((await push.token(requestPermission: true, callsEnabled: false))['reason'], 'token: timeout');
    expect(later.elapsedMilliseconds, greaterThanOrEqualTo(190));
    await settle();
  });

  test('an iPhone with a Firebase token also names its Apple token, so the server drops an older Apple-only row', () async {
    final platform = FakePlatform()..apns = 'ABCD';
    final device = await registration(platform).token(requestPermission: true, callsEnabled: false);
    expect(device['token'], platform.fcm);
    expect(device['apnsToken'], 'abcd');
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
