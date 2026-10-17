import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/guided_scanner/native_document_scanner.dart';
import 'package:foorsa_student/src/guided_scanner/scan_document_profile.dart';

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

  test('converts one retained page and exposes non-sensitive native diagnostics',
      () async {
    final first = Uint8List.fromList([1, 2, 3]);
    reply({
      'pages': [first],
      'engine': 'avfoundation_vision',
      'scannerBuild': 'custom-live-v4',
      'capabilities': ['live_quadrilateral', 'automatic_single_page'],
    });
    final result = await scanner.scan();
    expect(result['processed'], true);
    expect(result['engine'], 'avfoundation_vision');
    expect(result['scannerBuild'], 'custom-live-v4');
    expect(result['capabilities'], contains('live_quadrilateral'));
    final files = result['files'] as List;
    expect(files.length, 1);
    expect(files[0]['name'], 'scan-page-1.jpg');
    expect(
        files[0]['dataUrl'], 'data:image/jpeg;base64,${base64Encode(first)}');
  });
  test('passes only validated document guidance to the native camera',
      () async {
    Object? arguments;
    messenger.setMockMethodCallHandler(NativeDocumentScanner.channel,
        (call) async {
      arguments = call.arguments;
      return {
        'pages': [
          Uint8List.fromList([1])
        ]
      };
    });
    final profile = GuidedDocumentProfile.fromPortal({
      'documentKey': 'identity',
      'title': 'Passport',
      'instruction': 'Include all four corners.',
      'layout': 'adaptive',
    });
    await scanner.scan(profile: profile);
    final native = (arguments as Map)['profile'] as Map;
    expect(native['documentKey'], 'identity');
    expect(native['layout'], 'passport');
    expect(native.keys, hasLength(5));
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
  test('only unsupported hardware opts into framed fallback', () async {
    reply({'unsupported': true});
    expect(await scanner.scan(), {'unsupported': true});
    messenger.setMockMethodCallHandler(NativeDocumentScanner.channel, null);
    expect((await scanner.scan())['error'], contains('unavailable'));
  });
  test('malformed or multi-page native responses fail safely',
      () async {
    for (final pages in [
      null,
      [],
      [Uint8List(0)],
      [Uint8List(1), 'invalid'],
      [Uint8List(1), Uint8List(1)],
      List.generate(21, (_) => Uint8List(1))
    ]) {
      reply({'pages': pages});
      expect((await scanner.scan())['error'], isA<String>());
    }
  });
}
