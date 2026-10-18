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

  test(
      'converts one retained page and exposes non-sensitive native diagnostics',
      () async {
    final first = Uint8List.fromList([1, 2, 3]);
    reply({
      'pages': [first],
      'engine': 'avfoundation_vision',
      'scannerBuild': 'custom-live-v5',
      'capabilities': [
        'live_quadrilateral',
        'automatic_single_page',
        'aligned_three_frame_median_fusion',
      ],
      'burstProcessing': {
        'mode': 'aligned_median_fusion',
        'framesConsidered': 3,
        'framesUsed': 3,
        'alignmentModels': ['translation', 'homography'],
      },
    });
    final result = await scanner.scan();
    expect(result['processed'], true);
    expect(result['engine'], 'avfoundation_vision');
    expect(result['scannerBuild'], 'custom-live-v5');
    expect(result['capabilities'], contains('live_quadrilateral'));
    expect(result['burstProcessing'], {
      'mode': 'aligned_median_fusion',
      'framesConsidered': 3,
      'framesUsed': 3,
      'alignmentModels': ['translation', 'homography'],
    });
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
      'adaptive lighting capture keeps one page after a variable number of shots',
      () async {
    final lighting = {
      'shadowCorrectionApplied': true,
      'glarePixelsReplacedFraction': 0.02,
      'unresolvedGlareFraction': 0.0,
      'needsDifferentAngle': false,
    };
    reply({
      'pages': [
        Uint8List.fromList([1, 2, 3])
      ],
      'scannerBuild': 'custom-live-v8',
      'burstProcessing': {
        'mode': 'aligned_lighting_fusion',
        'framesConsidered': 3,
        'framesUsed': 3,
        'acceptedGuidedAngles': 4,
        'retainedUsefulViews': 4,
        'guidedExtraCaptures': 5,
        'photosTaken': 6,
        'lighting': lighting,
      },
    });
    final result = await scanner.scan();
    expect(result['scannerBuild'], 'custom-live-v8');
    expect(result['files'], hasLength(1));
    final diagnostics = result['burstProcessing'] as Map;
    expect(diagnostics['framesUsed'], 3);
    expect(diagnostics['acceptedGuidedAngles'], 4);
    expect(diagnostics['retainedUsefulViews'], 4);
    expect(diagnostics['photosTaken'], 6);
    expect(diagnostics['lighting'], lighting);
    expect(diagnostics.containsKey('pages'), false);
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
  test('malformed or multi-page native responses fail safely', () async {
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
  final imagegenProfile = GuidedDocumentProfile.fromPortal({
    'documentKey': 'identity', 'outputMode': 'imagegen',
  });
  Uint8List jpeg([int size = 6]) {
    final bytes = Uint8List(size);
    bytes[0] = 0xff; bytes[1] = 0xd8;
    bytes[size - 2] = 0xff; bytes[size - 1] = 0xd9;
    return bytes;
  }
  test('imagegen is explicit and preserves exact original bytes as source files', () async {
    final raw = jpeg();
    raw[2] = 123;
    reply({'pages': [jpeg()], 'originals': [raw, jpeg()], 'processing': 'imagegen'});
    final result = await scanner.scan(profile: imagegenProfile);
    expect(imagegenProfile.toNativeRequest()['outputMode'], 'imagegen');
    expect(result['processing'], 'imagegen');
    expect(result['files'], hasLength(1));
    final originals = result['originals'] as List;
    expect(originals, hasLength(2));
    expect(originals.first['name'], 'scan-original-1.jpg');
    expect(originals.first['dataUrl'], 'data:image/jpeg;base64,${base64Encode(raw)}');
    expect(GuidedDocumentProfile.fromPortal({'outputMode': 'other'}).toNativeRequest(),
      isNot(contains('outputMode')));
    expect((await scanner.scan())['error'], isA<String>());
  });
  test('imagegen rejects missing, malformed, oversized or excessive originals', () async {
    for (final originals in [null, [], [Uint8List(0)], [Uint8List.fromList([1, 2, 3])],
      [jpeg(NativeDocumentScanner.maximumOriginalBytes + 1)],
      List.generate(7, (_) => jpeg()),
      List.generate(5, (_) => jpeg(NativeDocumentScanner.maximumOriginalBytes)),
    ]) {
      reply({'pages': [jpeg()], 'originals': originals, 'processing': 'imagegen'});
      expect((await scanner.scan(profile: imagegenProfile))['error'], isA<String>());
    }
    reply({'pages': [jpeg()], 'originals': [jpeg()]});
    expect((await scanner.scan(profile: imagegenProfile))['error'], isA<String>());
    reply({'pages': [Uint8List.fromList([1])], 'originals': [jpeg()], 'processing': 'imagegen'});
    expect((await scanner.scan(profile: imagegenProfile))['error'], isA<String>());
  });
  test('imagegen cancellation cannot leak originals and a later retry is independent', () async {
    reply({'cancelled': true, 'originals': [jpeg()], 'processing': 'imagegen'});
    expect(await scanner.scan(profile: imagegenProfile), {'cancelled': true});
    reply({'pages': [jpeg()], 'originals': [jpeg()], 'processing': 'imagegen'});
    expect((await scanner.scan(profile: imagegenProfile))['originals'], hasLength(1));
  });

}
