import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/student_calls.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  test('calls start on a phone whose plugin implements none of their methods',
      () async {
    // iOS's plugin answers registerBackgroundHandler "not implemented"; thrown
    // out of main, that kept every iPhone on the launch screen (build 49).
    messenger.setMockMethodCallHandler(
        const MethodChannel('flutter_callkit_incoming'),
        (call) async => throw MissingPluginException());
    messenger.setMockMethodCallHandler(
        const MethodChannel('flutter_callkit_incoming_events'),
        (call) async => null);
    addTearDown(() {
      messenger.setMockMethodCallHandler(
          const MethodChannel('flutter_callkit_incoming'), null);
      messenger.setMockMethodCallHandler(
          const MethodChannel('flutter_callkit_incoming_events'), null);
    });
    await expectLater(StudentCalls.instance.start(), completes);
  });

  test('a calls start-up that fails or stalls never holds the app back',
      () async {
    await expectLater(
        startStudentCalls(start: () async => throw StateError('no calls')),
        completes);
    final stalled = Stopwatch()..start();
    await startStudentCalls(
        start: () => Completer<void>().future,
        patience: const Duration(milliseconds: 50));
    expect(stalled.elapsed, lessThan(const Duration(seconds: 1)));
  });

  test('incoming call requires a bounded fresh signed capability', () {
    final invite = <String, dynamic>{
      'callId': 'a1111111-1111-4111-8111-111111111111',
      'token': 'x' * 128,
      'expiresAt':
          DateTime.now().add(const Duration(seconds: 40)).toIso8601String()
    };
    expect(validStudentCall(invite), isTrue);
    expect(validStudentCall({...invite, 'token': ''}), isFalse);
    expect(
        validStudentCall({
          ...invite,
          'expiresAt': DateTime.now()
              .subtract(const Duration(seconds: 1))
              .toIso8601String()
        }),
        isFalse);
    expect(
        validStudentCall({
          ...invite,
          'expiresAt':
              DateTime.now().add(const Duration(hours: 1)).toIso8601String()
        }),
        isFalse);
  });
  test('each answering device receives its own UUID', () {
    final first = callDeviceId(), second = callDeviceId();
    expect(
        first,
        matches(RegExp(
            r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$')));
    expect(first, isNot(second));
  });
}
