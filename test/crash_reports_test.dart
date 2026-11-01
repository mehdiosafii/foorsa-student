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

  test('Android says its release and WebView, in the shapes the server keeps', () async {
    expect(CrashReports.androidDescription({'release': '16', 'sdk': 36, 'webView': '142.0.7444.171'}),
        (os: 'Android 16', webView: 'WebView 142.0.7444.171'));
    expect(CrashReports.androidDescription({'release': '8.1.0', 'webView': null}),
        (os: 'Android 8.1.0', webView: null));
    expect(CrashReports.androidDescription({'release': 'Baklava', 'webView': 'dev build'}),
        (os: null, webView: null));
    expect(CrashReports.androidDescription(null), (os: null, webView: null));

    final sent = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      sent.add(jsonDecode(request.body) as Map<String, dynamic>);
      return http.Response('{"ok":true}', 200);
    });
    final reports = CrashReports(client: client, baseUrl: 'https://student.foorsa.ma', os: 'Android 16')
      ..webView = 'WebView 142.0.7444.171';
    await reports.report('Dart: PlatformException(error, cast)');
    await reports.report('Flutter: overflow', where: 'rendering library');
    expect(sent[0]['where'], 'WebView 142.0.7444.171', reason: 'a report with no place names the WebView');
    expect(sent[0]['os'], 'Android 16');
    expect(sent[1]['where'], 'rendering library');
  });
}
