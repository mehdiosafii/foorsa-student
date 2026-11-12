import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/file_fetch.dart';

/// A real server on this machine, so the fetch runs as it does on a phone:
/// the stress test of 11 Nov 2026 found that a download whose connection
/// stalled kept its loader over the app for good (no time limit anywhere).
void main() {
  late HttpServer server;
  late Directory dir;
  late Uri base;
  final held = <HttpResponse>[];

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('foorsa_fetch_');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = Uri.parse('http://127.0.0.1:${server.port}');
    server.listen((request) async {
      final response = request.response;
      switch (request.uri.path) {
        case '/file':
          response.headers.contentType = ContentType('application', 'pdf');
          response.headers.set('x-seen-cookie', request.headers.value('cookie') ?? '');
          response.add(List<int>.filled(70000, 37));
          await response.close();
        case '/echo':
          response.write('${request.headers.value('cookie')}|${request.headers.value('user-agent')}');
          await response.close();
        case '/missing':
          response.statusCode = 404;
          response.write('no such file');
          await response.close();
        case '/stalls':
          // Half the file, then nothing more: a connection that died quietly.
          response.contentLength = 20000;
          response.add(List<int>.filled(10000, 1));
          await response.flush();
          held.add(response);
        case '/silent':
          // The request is taken and never answered.
          held.add(response);
      }
    });
  });

  tearDown(() async {
    held.clear();
    await server.close(force: true);
    await dir.delete(recursive: true);
  });

  test('a file is saved whole, with the headers it was asked with', () async {
    final file = File('${dir.path}/paper.pdf');
    await fetchToFile(base.resolve('/file'), file);
    expect(await file.length(), 70000);
    final echo = File('${dir.path}/echo.txt');
    await fetchToFile(base.resolve('/echo'), echo,
        headers: {'Cookie': 'sid=abc', HttpHeaders.userAgentHeader: 'FoorsaStudentApp/1.2.40'});
    expect(await echo.readAsString(), 'sid=abc|FoorsaStudentApp/1.2.40');
  });

  test('an error from the server is an error, and leaves no file', () async {
    final file = File('${dir.path}/missing.pdf');
    await expectLater(fetchToFile(base.resolve('/missing'), file),
        throwsA(isA<FileFetchStatus>().having((e) => e.statusCode, 'statusCode', 404)));
    expect(await file.exists(), isFalse);
    expect('${const FileFetchStatus(404)}', 'HTTP 404');
  });

  test('a download that stalls half way is given up, and its half file removed', () async {
    final file = File('${dir.path}/stalls.pdf');
    final watch = Stopwatch()..start();
    await expectLater(
        fetchToFile(base.resolve('/stalls'), file, stallLimit: const Duration(milliseconds: 400)),
        throwsA(isA<TimeoutException>()));
    // Given up after the limit, not after the system's own minutes.
    expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
    expect(await file.exists(), isFalse);
  });

  test('a server that never answers is given up', () async {
    final file = File('${dir.path}/silent.pdf');
    final watch = Stopwatch()..start();
    await expectLater(
        fetchToFile(base.resolve('/silent'), file, stallLimit: const Duration(milliseconds: 400)),
        throwsA(isA<TimeoutException>()));
    expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
    expect(await file.exists(), isFalse);
  });

  test('an address nothing listens on fails at once', () async {
    final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = closed.port;
    await closed.close();
    final file = File('${dir.path}/refused.pdf');
    await expectLater(fetchToFile(Uri.parse('http://127.0.0.1:$port/x'), file), throwsA(isA<SocketException>()));
    expect(await file.exists(), isFalse);
  });

  test('the shell fetches every file through it, and no loader is taken away with a bare pop', () {
    final shell = File('lib/src/shell_page.dart').readAsStringSync();
    // Three fetches: the download, the preview, and a link the page hands over.
    expect('await fetchToFile('.allMatches(shell).length, 3);
    expect(shell, isNot(contains('HttpClient()')));
    expect(shell, isNot(contains('Navigator.of(context, rootNavigator: true).pop()')));
    expect('ShellSpinner.show('.allMatches(shell).length, 2);
  });
}
