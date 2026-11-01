import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/student_push.dart';

void main() {
  test('a banner the app shows itself is presented on iOS 14 and later', () {
    // presentAlert alone shows nothing since iOS 14: the banner and the list need their own flags.
    expect(foregroundBannerDetails.presentBanner, isTrue);
    expect(foregroundBannerDetails.presentList, isTrue);
    expect(foregroundBannerDetails.presentSound, isTrue);
  });

  test('the test push from Settings shows its own fixed words, and nothing else', () {
    expect(isStudentTestPush({'type': 'student_test'}), isTrue);
    expect(isStudentTestPush({'type': 'student_chat'}), isFalse);
    expect(foregroundPushBody(chat: false, test: true), 'This is a test notification from Foorsa.');
    expect(foregroundPushBody(chat: true, test: false), 'You have a new message from your adviser.');
    expect(foregroundPushBody(chat: false, test: false), 'An update is ready in your Foorsa app.');
  });

  test('the iPhone app delegate owns the notification centre and hears what APNs answers', () {
    final delegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    // Before super: Apple wants the delegate set before launch ends, and Flutter
    // then hands every callback to firebase_messaging and flutter_local_notifications.
    final setDelegate = delegate.indexOf('UNUserNotificationCenter.current().delegate = self');
    expect(setDelegate, greaterThan(0));
    expect(setDelegate, lessThan(delegate.indexOf('super.application(application, didFinishLaunchingWithOptions')));
    expect(delegate, contains('didFailToRegisterForRemoteNotificationsWithError'));
    expect(delegate, contains('super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)'));
    expect(delegate, contains('super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)'));
    // The channel student_push.dart reads Apple's refusal on.
    expect(delegate, contains('"ma.foorsa.student/push"'));
    expect(File('lib/src/student_push.dart').readAsStringSync(), contains("MethodChannel('ma.foorsa.student/push')"));
  });

  test('a TestFlight build without the production push entitlement never ships', () {
    final workflow = File('.github/workflows/testflight.yml').readAsStringSync();
    expect(workflow, contains('name: Check the push entitlement'));
    expect(workflow, contains('bash scripts/push_entitlement.sh "\$IPA"'));
    expect(workflow.indexOf('name: Check the push entitlement'), lessThan(workflow.indexOf('name: Upload to TestFlight')));
    // The unsigned archive is archived again, signed, when its export lacks it.
    expect(workflow, contains('[[ "\$(exported_push)" != production ]]'));
    expect(workflow, contains('APS_ENVIRONMENT=development'));
    expect(File('scripts/push_entitlement.sh').readAsStringSync(), contains('plutil -extract aps-environment raw'));
  });

  test('updates open only the fixed inbox with an opaque event id', () {
    const id = '00000000-0000-4000-8000-000000000001';
    expect(studentUpdateRoute({'type': 'student_update', 'route': '/notifications', 'eventId': id}), '/notifications?event=$id');
    expect(studentUpdateRoute({'type': 'student_update', 'route': 'https://evil.test', 'eventId': id}), isNull);
    expect(studentUpdateRoute({'type': 'student_update', 'route': '/notifications', 'eventId': '$id&route=/admin'}), isNull);
    expect(studentUpdateRoute({'type': 'student_update', 'route': '/notifications'}), isNull);
  });
  test('calendar drops missed and malformed alarms and sorts real instants', () {
    final now = DateTime.utc(2026, 10, 27, 10);
    expect(validCalendarTimes([
      {'at': '2026-10-27T12:00:00Z'}, {'at': '2026-10-27T09:00:00Z'},
      {'at': 'bad'}, {'at': '2026-10-27T11:00:00Z'}, {'at': '2030-01-01T00:00:00Z'},
    ], now), [DateTime.utc(2026, 10, 27, 11), DateTime.utc(2026, 10, 27, 12)]);
  });
  test('only student chat payloads open the chat', () {
    expect(
        isStudentChatPush({'type': 'student_chat', 'route': '/contact/chat'}),
        isTrue);
    expect(isStudentChatPush({'type': 'message', 'route': '/contact/chat'}),
        isFalse);
    expect(
        isStudentChatPush(
            {'type': 'student_chat', 'route': 'https://evil.test'}),
        isFalse);
    expect(isStudentChatPush({}), isFalse);
  });
}
