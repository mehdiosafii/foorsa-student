import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/crash_reports.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('a report carries what broke, the screen, the build and the system, nothing else', () async {
    final sent = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      expect(request.url.toString(), 'https://student.foorsa.ma/api/portal/client-error');
      sent.add(jsonDecode(request.body) as Map<String, dynamic>);
      return http.Response('{"ok":true}', 200);
    });
    final reports = CrashReports(client: client, baseUrl: 'https://student.foorsa.ma', os: 'iOS 18.7')..build = '1.2.30+61';
    expect(await reports.report('Web view stopped: content process terminated',
        screen: 'https://student.foorsa.ma/documents/identity/passport?paper=passport'), isTrue);
    expect(sent.single.keys.toSet(), {'source', 'platform', 'message', 'screen', 'build', 'os'});
    expect(sent.single['source'], 'shell');
    expect(sent.single['screen'], '/documents/identity');
    expect(sent.single['build'], '1.2.30+61');
    expect(sent.single['os'], 'iOS 18.7');
  });

  test('the same report is sent once in ten minutes', () async {
    var calls = 0;
    final client = MockClient((_) async { calls++; return http.Response('{"ok":true}', 200); });
    final reports = CrashReports(client: client, baseUrl: 'https://student.foorsa.ma', os: null);
    final at = DateTime(2026, 10, 31, 22);
    await reports.report('Web view stopped', screen: '/documents', now: at);
    await reports.report('Web view stopped', screen: '/documents', now: at.add(const Duration(minutes: 5)));
    await reports.report('Web view stopped', screen: '/documents', now: at.add(const Duration(minutes: 11)));
    expect(calls, 2);
  });

  test('a failed report never throws', () async {
    final client = MockClient((_) async => throw Exception('offline'));
    final reports = CrashReports(client: client, baseUrl: 'https://student.foorsa.ma', os: null);
    expect(await reports.report('Dart: boom'), isFalse);
  });

  test('only the shapes the server reads are sent', () {
    expect(CrashReports.screenPath('https://student.foorsa.ma/'), '/');
    expect(CrashReports.screenPath('https://student.foorsa.ma/contact/chat?c=1'), '/contact/chat');
    expect(CrashReports.screenPath(null), isNull);
    expect(CrashReports.systemVersion('Version 18.7 (Build 22H20)', true), 'iOS 18.7');
    expect(CrashReports.systemVersion('Linux 5.10.43-android12', false), isNull);
    final body = CrashReports.reportBody('x', build: 'not a build!', os: 'Windows 11');
    expect(body.containsKey('build'), isFalse);
    expect(body.containsKey('os'), isFalse);
  });
}
