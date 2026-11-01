// The Android guided camera, run end to end with a camera that hands back
// stills: the shutter, the second still, the choice of the sharper, the photo
// made ready, and the other still deleted (guided_scan_page.dart). The phone's
// own camera, focus and pixels are what only a phone can show.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/guided_scanner/guided_scan_page.dart';
import 'package:foorsa_student/src/guided_scanner/scan_document_profile.dart';

import 'support/printed_page.dart';

/// A camera that opens, never streams a frame (so nothing is taken without
/// the shutter), and hands back the stills it is given, in turn.
class _FakeCamera extends CameraPlatform {
  _FakeCamera(this.stills);
  final List<String> stills;
  final taken = <String>[];
  final focused = <math.Point<double>?>[];

  @override
  Future<List<CameraDescription>> availableCameras() async => const [
        CameraDescription(name: 'back', lensDirection: CameraLensDirection.back, sensorOrientation: 90),
      ];

  @override
  Future<int> createCameraWithSettings(CameraDescription description, MediaSettings settings) async => 1;

  @override
  Future<void> initializeCamera(int cameraId, {ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown}) async {}

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) => Stream.value(const CameraInitializedEvent(
      1, 1440, 1080, ExposureMode.auto, true, FocusMode.auto, true));

  @override
  // Streams that stay open and say nothing, as a camera that works does (the
  // controller waits on their first event).
  @override
  Stream<CameraClosingEvent> onCameraClosing(int cameraId) => StreamController<CameraClosingEvent>().stream;

  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) => StreamController<CameraErrorEvent>().stream;

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() => const Stream.empty();

  @override
  Future<void> lockCaptureOrientation(int cameraId, DeviceOrientation orientation) async {}

  @override
  bool supportsImageStreaming() => true;

  @override
  Stream<CameraImageData> onStreamedFrameAvailable(int cameraId, {CameraImageStreamOptions? options}) =>
      const Stream.empty();

  @override
  Future<void> setFocusPoint(int cameraId, math.Point<double>? point) async => focused.add(point);

  @override
  Future<void> setFlashMode(int cameraId, FlashMode mode) async {}

  @override
  Future<XFile> takePicture(int cameraId) async {
    final path = stills[taken.length];
    taken.add(path);
    return XFile(path);
  }

  @override
  Widget buildPreview(int cameraId) => const ColoredBox(key: ValueKey('camera-preview'), color: Color(0xFF203040));

  @override
  Future<void> dispose(int cameraId) async {}
}

/// The middle of a still as ScanPhoto.kt samples it: printed rows, crisp or
/// streaked by a hand that moved (support/printed_page.dart).
final _page = printedPage(width: 300, height: 240);
Uint8List _print({required bool shaken}) =>
    shaken ? streak(_page.luma, _page.width, _page.height, 8) : _page.luma;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late Map<String, bool> shakenByPath;
  late List<String> prepared;
  late bool sampling;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('guided-scan');
    shakenByPath = {};
    prepared = [];
    sampling = true;
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('foorsa/scan_photo'), (call) async {
      final path = (call.arguments as Map)['path'] as String;
      if (call.method == 'sample') {
        if (!sampling) return {'error': 'failed'};
        return {'luma': _print(shaken: shakenByPath[path]!), 'width': 300, 'height': 240};
      }
      prepared.add(path);
      return {
        'bytes': Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]),
        'width': 2448,
        'height': 3264,
        'reencoded': true,
      };
    });
    messenger.setMockMethodCallHandler(const MethodChannel('foorsa/live_text'), (call) async => null);
  });

  tearDown(() async {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('foorsa/scan_photo'), null);
    messenger.setMockMethodCallHandler(const MethodChannel('foorsa/live_text'), null);
    await dir.delete(recursive: true);
  });

  /// Two stills on disk; [shaken] names which of them a hand moved.
  Future<List<String>> stills(List<bool> shaken) async {
    final paths = <String>[];
    for (var i = 0; i < shaken.length; i++) {
      final file = File('${dir.path}/still-$i.jpg')..writeAsBytesSync([0xff, 0xd8, i]);
      shakenByPath[file.path] = shaken[i];
      paths.add(file.path);
    }
    return paths;
  }

  /// Opens the Android scanner, taps the shutter, and returns what it handed back.
  Future<GuidedScanResult?> scan(WidgetTester tester, _FakeCamera camera) async {
    CameraPlatform.instance = camera;
    GuidedScanResult? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => TextButton(
        onPressed: () async {
          result = await Navigator.of(context).push<GuidedScanResult>(MaterialPageRoute(
            builder: (_) => GuidedScanPage(
                profile: GuidedDocumentProfile.fromPortal({'documentKey': 'transcript'}), android: true),
          ));
        },
        child: const Text('open'),
      )),
    ));
    await tester.tap(find.text('open'));
    await tester.runAsync(() async {
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        // The camera is open once its preview is up.
        if (find.byKey(const ValueKey('camera-preview')).evaluate().isNotEmpty) break;
      }
      expect(find.byKey(const ValueKey('camera-preview')), findsOneWidget, reason: 'the camera opened');
      // The panel's old line fades out over 180 ms.
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Opening camera…'), findsNothing);
      for (var i = 0; i < 1; i++) {
      }
    });
    await tester.tap(find.bySemanticsLabel('Take photo manually'));
    await tester.runAsync(() async {
      for (var i = 0; i < 100 && result == null; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    return result;
  }

  testWidgets('a shaken first still gives way to the steady second, and is deleted', (tester) async {
    final paths = await stills([true, false]);
    final camera = _FakeCamera(paths);
    final result = await scan(tester, camera);
    expect(camera.taken, paths, reason: 'two stills, one after the other');
    expect(camera.focused, isNotEmpty, reason: 'the page is focused on before the first');
    expect(result?.file?.path, paths[1]);
    expect(result?.bytes, isNotNull, reason: 'the kept still is made ready for the portal');
    expect(prepared, [paths[1]]);
    expect(File(paths[0]).existsSync(), isFalse, reason: 'the shaken still is not kept');
  });

  testWidgets('a steady first still is kept over a shaken second', (tester) async {
    final paths = await stills([false, true]);
    final camera = _FakeCamera(paths);
    final result = await scan(tester, camera);
    expect(camera.taken, paths);
    expect(result?.file?.path, paths[0]);
    expect(prepared, [paths[0]]);
    expect(File(paths[1]).existsSync(), isFalse);
  });

  testWidgets('a phone that cannot measure a still keeps its first, as before', (tester) async {
    sampling = false;
    final paths = await stills([true, false]);
    final camera = _FakeCamera(paths);
    final result = await scan(tester, camera);
    expect(camera.taken, [paths[0]], reason: 'no second still without a way to compare');
    expect(result?.file?.path, paths[0]);
  });
}
