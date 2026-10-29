import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/crash_reports.dart';

void main() {
  test('a report says what broke and nothing about the student', () {
    final body = crashReportBody(
      message: 'Failed to open https://student.foorsa.ma/documents?t=abc '
          'for sara@example.com at /var/mobile/Containers/Data/passport.pdf '
          'phone 0612345678\nsecond line',
      where: 'src/shell_page.dart:812',
      build: '1.2.20+51',
      isIOS: true,
      osVersion: 'iOS 18.2',
    );
    expect(body['source'], 'shell');
    expect(body['platform'], 'ios');
    expect(body['os'], 'iOS 18.2');
    expect(body['build'], '1.2.20+51');
    expect(body['where'], 'src/shell_page.dart:812');
    final message = body['message']! as String;
    expect(message, contains('<url>'));
    expect(message, contains('<email>'));
    expect(message, contains('<path>'));
    expect(message, contains('<number>'));
    expect(message, isNot(contains('second line')));
    expect(message, isNot(contains('sara')));
    expect(message, isNot(contains('passport')));
  });

  test('a long message is cut, and an empty one stays empty', () {
    expect(cleanCrashLine('x' * 500, 300).length, 300);
    expect(cleanCrashLine('\n  \n', 300), '');
  });

  test('the frame named is the first in the app code', () {
    final stack = StackTrace.fromString(
      '#0 Object.noSuchMethod (dart:core-patch/object_patch.dart:38:5)\n'
      '#1 ShellPageState._pick (package:foorsa_student/src/shell_page.dart:812:9)\n'
      '#2 main (package:foorsa_student/main.dart:20:3)',
    );
    expect(firstAppFrame(stack), 'src/shell_page.dart:812');
    expect(firstAppFrame(StackTrace.fromString('#0 dart:async')), isNull);
    expect(firstAppFrame(null), isNull);
  });

  test('the system version is read on iOS only', () {
    expect(osVersionOf('Version 18.2 (Build 22C152)', isIOS: true), 'iOS 18.2');
    expect(osVersionOf('Version 26.0.1 (Build 23A355)', isIOS: true),
        'iOS 26.0.1');
    expect(osVersionOf('Linux 5.10.198-android13', isIOS: false), isNull);
  });
}
