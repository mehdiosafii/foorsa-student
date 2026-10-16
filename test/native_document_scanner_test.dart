import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/guided_scanner/native_document_scanner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final scanner = NativeDocumentScanner();
  void reply(Object? value) {
    messenger.setMockMethodCallHandler(NativeDocumentScanner.channel,
        (call) async {
      expect(call.method, 'scan');
      return value;
    });
  }

  tearDown(() =>
      messenger.setMockMethodCallHandler(NativeDocumentScanner.channel, null));

  test('keeps all pages in order and marks system scans as already processed',
      () async {
    final first = Uint8List.fromList([1, 2, 3]);
    final second = Uint8List.fromList([4, 5, 6]);
    reply({
      'pages': [first, second]
    });
    final result = await scanner.scan();
    expect(result['processed'], true);
    expect(result['engine'], 'visionkit');
    final files = result['files'] as List;
    expect(files.length, 2);
    expect(files[0]['name'], 'scan-page-1.jpg');
    expect(
        files[1]['dataUrl'], 'data:image/jpeg;base64,${base64Encode(second)}');
  });
  test(
      'cancellation and native errors remain final rather than opening another camera',
      () async {
    reply({'cancelled': true});
    expect(await scanner.scan(), {'cancelled': true});
    reply({'error': 'Camera failed'});
    expect(await scanner.scan(), {'error': 'Camera failed'});
    messenger.setMockMethodCallHandler(NativeDocumentScanner.channel,
        (_) async => throw PlatformException(code: 'camera_failed'));
    expect((await scanner.scan())['error'], isA<String>());
  });
  test('only unsupported hardware and missing plugin opt into framed fallback',
      () async {
    reply({'unsupported': true});
    expect(await scanner.scan(), {'unsupported': true});
    messenger.setMockMethodCallHandler(NativeDocumentScanner.channel, null);
    expect(await scanner.scan(), {'unsupported': true});
  });
  test('malformed and partial page batches fail without dropping pages',
      () async {
    for (final pages in [
      null,
      [],
      [Uint8List(0)],
      [Uint8List(1), 'invalid'],
      List.generate(21, (_) => Uint8List(1))
    ]) {
      reply({'pages': pages});
      expect((await scanner.scan())['error'], isA<String>());
    }
  });
}
