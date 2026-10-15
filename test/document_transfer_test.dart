import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/document_transfer.dart';

void main() {
  late HttpServer server;
  late Directory directory;
  late File target;
  final timers = <Timer>[];
  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    directory = await Directory.systemTemp.createTemp('foorsa-transfer-test-');
    target = File('${directory.path}/document.pdf');
  });
  tearDown(() async {
    for (final timer in timers) {
      timer.cancel();
    }
    timers.clear();
    await server.close(force: true);
    await directory.delete(recursive: true);
  });
  Future<void> fetch({Duration? response, Duration? body, Duration? total}) =>
      transferDocument(
          Uri.parse('http://127.0.0.1:${server.port}/document'), target,
          connectionTimeout: const Duration(seconds: 1),
          responseTimeout: response ?? const Duration(seconds: 1),
          bodyTimeout: body ?? const Duration(seconds: 1),
          totalTimeout: total ?? const Duration(seconds: 2));

  test('saves complete PDF bytes and cleans staging files', () async {
    server.listen((request) {
      request.response.write('%PDF-1.7 complete');
      request.response.close();
    });
    await fetch();
    expect(await target.readAsString(), '%PDF-1.7 complete');
    expect(directory.listSync().length, 1);
  });
  test('failed HTTP response preserves prior file and permits retry', () async {
    await target.writeAsString('prior file');
    var attempt = 0;
    server.listen((request) {
      request.response.statusCode = attempt++ == 0 ? 403 : 200;
      request.response.write('new document');
      request.response.close();
    });
    await expectLater(fetch(), throwsA(isA<HttpException>()));
    expect(await target.readAsString(), 'prior file');
    await fetch();
    expect(await target.readAsString(), 'new document');
    expect(directory.listSync().length, 1);
  });
  test('TLS connection handshake cannot stall indefinitely', () async {
    final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <Socket>[];
    listener
        .listen(sockets.add); // Accept TCP but never answer the TLS handshake.
    try {
      await expectLater(
        transferDocument(
          Uri.parse('https://127.0.0.1:${listener.port}/document'),
          target,
          connectionTimeout: const Duration(milliseconds: 100),
          totalTimeout: const Duration(seconds: 2),
        ),
        throwsA(isA<TimeoutException>()),
      );
      expect(directory.listSync(), isEmpty);
    } finally {
      for (final socket in sockets) {
        socket.destroy();
      }
      await listener.close();
    }
  });
  test('accepted connection with stalled headers times out and cleans up',
      () async {
    server.listen((request) {});
    final watch = Stopwatch()..start();
    await expectLater(fetch(response: const Duration(milliseconds: 100)),
        throwsA(isA<TimeoutException>()));
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    expect(directory.listSync(), isEmpty);
  });
  test('response with stalled body times out and removes partial bytes',
      () async {
    server.listen((request) {
      request.response.contentLength = 100;
      request.response.write('partial');
      request.response.flush();
    });
    await expectLater(fetch(body: const Duration(milliseconds: 100)),
        throwsA(isA<TimeoutException>()));
    expect(directory.listSync(), isEmpty);
  });
  test('continuous trickle cannot bypass total deadline', () async {
    server.listen((request) {
      request.response.contentLength = 10000;
      timers.add(Timer.periodic(const Duration(milliseconds: 25), (_) {
        request.response.write('x');
        unawaited(request.response.flush().catchError((_) {}));
      }));
    });
    final watch = Stopwatch()..start();
    await expectLater(fetch(total: const Duration(milliseconds: 200)),
        throwsA(isA<TimeoutException>()));
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    expect(directory.listSync(), isEmpty);
  });
}
