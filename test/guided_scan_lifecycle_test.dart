// The Android guided camera when the phone does something else in the middle
// of a scan: the back button during the photo, a call or the lock during the
// focus wait, the page closed while frames are streaming. The stress test of
// 11 Nov 2026 found each of them broken (guided_scan_page.dart says how).
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/guided_scanner/guided_scan_page.dart';
import 'package:foorsa_student/src/guided_scanner/scan_document_profile.dart';

/// A camera whose focus and stills answer when the test says, and whose frame
/// stream says when it is listened to and let go.
class _FakeCamera extends CameraPlatform {
  _FakeCamera(this.path);
  final String path;
  int created = 0;
  int disposed = 0;
  int pictures = 0;
  int focusCalls = 0;
  final log = <String>[];
  Completer<void>? focus;
  Completer<XFile>? picture;

  @override
  Future<List<CameraDescription>> availableCameras() async => const [
        CameraDescription(name: 'back', lensDirection: CameraLensDirection.back, sensorOrientation: 90),
      ];

  @override
  Future<int> createCameraWithSettings(CameraDescription description, MediaSettings settings) async => ++created;

  @override
  Future<void> initializeCamera(int cameraId, {ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown}) async {}

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) => Stream.value(CameraInitializedEvent(
      cameraId, 1440, 1080, ExposureMode.auto, true, FocusMode.auto, true));

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
      StreamController<CameraImageData>(
          onListen: () => log.add('frames on #$cameraId'), onCancel: () => log.add('frames off #$cameraId')).stream;

  @override
  Future<void> setFocusPoint(int cameraId, math.Point<double>? point) {
    focusCalls++;
    return focus?.future ?? Future<void>.value();
  }

  @override
  Future<void> setFlashMode(int cameraId, FlashMode mode) async {}

  @override
  Future<XFile> takePicture(int cameraId) {
    pictures++;
    return picture?.future ?? Future<XFile>.value(XFile(path));
  }

  @override
  Widget buildPreview(int cameraId) => const ColoredBox(key: ValueKey('camera-preview'), color: Color(0xFF203040));

  @override
  Future<void> dispose(int cameraId) async {
    disposed++;
    log.add('camera #$cameraId released');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late String still;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('guided-scan-life');
    still = (File('${dir.path}/still.jpg')..writeAsBytesSync([0xff, 0xd8, 1])).path;
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('foorsa/scan_photo'), (call) async {
      // A phone that cannot measure a still keeps its first; the photo is made ready.
      if (call.method == 'sample') return {'error': 'failed'};
      return {'bytes': Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]), 'width': 2448, 'height': 3264, 'reencoded': true};
    });
    messenger.setMockMethodCallHandler(const MethodChannel('foorsa/live_text'), (call) async => null);
  });

  tearDown(() async {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('foorsa/scan_photo'), null);
    messenger.setMockMethodCallHandler(const MethodChannel('foorsa/live_text'), null);
    await dir.delete(recursive: true);
  });

  /// Lets the page's own awaits (files, channels) run between frames.
  Future<void> steps(WidgetTester tester, int count, {int ms = 50}) async {
    await tester.runAsync(() async {
      for (var i = 0; i < count; i++) {
        await tester.pump(Duration(milliseconds: ms));
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });
  }

  /// The portal's page with the scanner opened over it; [results] takes what the scanner hands back.
  Future<void> open(WidgetTester tester, _FakeCamera camera, List<GuidedScanResult?> results) async {
    CameraPlatform.instance = camera;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => TextButton(
        onPressed: () async {
          results.add(await Navigator.of(context).push<GuidedScanResult>(MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => GuidedScanPage(
                profile: GuidedDocumentProfile.fromPortal({'documentKey': 'transcript'}), android: true),
          )));
        },
        child: const Text('Portal'),
      )),
    ));
    await tester.tap(find.text('Portal'));
    await tester.runAsync(() async {
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        if (find.byKey(const ValueKey('camera-preview')).evaluate().isNotEmpty) break;
      }
    });
    expect(find.byKey(const ValueKey('camera-preview')), findsOneWidget, reason: 'the camera opened');
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('the back button during the photo closes the scanner only, and the photo is not kept', (tester) async {
    final camera = _FakeCamera(still)..picture = Completer<XFile>();
    final results = <GuidedScanResult?>[];
    await open(tester, camera, results);
    await tester.tap(find.bySemanticsLabel('Take photo manually'));
    await steps(tester, 6, ms: 20);
    expect(camera.pictures, 1, reason: 'the still is being taken');

    // Android's back button: the scanner starts to slide away.
    unawaited(tester.binding.handlePopRoute());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    // The still lands while it slides.
    camera.picture!.complete(XFile(still));
    await steps(tester, 60, ms: 50);

    expect(results, [null], reason: 'the scan was cancelled, once');
    expect(find.byType(GuidedScanPage), findsNothing);
    expect(find.text('Portal'), findsOneWidget, reason: 'the page under the scanner is still there');
    expect(File(still).existsSync(), isFalse, reason: 'a paper photographed and not sent is deleted');
  });

  testWidgets('a call during the focus wait: back in the app, the camera opens again', (tester) async {
    final camera = _FakeCamera(still)..focus = Completer<void>();
    final results = <GuidedScanResult?>[];
    await open(tester, camera, results);
    expect(camera.created, 1);
    await tester.tap(find.bySemanticsLabel('Take photo manually'));
    await steps(tester, 4, ms: 20);
    expect(camera.focusCalls, 1, reason: 'the photo waits on the focus');

    // A call comes in, the shade is pulled, or the screen locks.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await steps(tester, 4, ms: 20);
    camera.focus!.complete();
    await steps(tester, 10, ms: 50);
    expect(camera.pictures, 0, reason: 'no photo is taken with the camera let go');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await steps(tester, 40, ms: 100);

    expect(camera.created, 2, reason: 'a new camera for the student who came back');
    expect(find.byKey(const ValueKey('camera-preview')), findsOneWidget);
    expect(find.text('Taking the photo.'), findsNothing);
    final close = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.close));
    expect(close.onPressed, isNotNull, reason: 'the page can be closed');
    // And a photo can be taken.
    camera.focus = null;
    await tester.tap(find.bySemanticsLabel('Take photo manually'));
    await steps(tester, 60, ms: 50);
    expect(results.single, isNotNull);
    expect(results.single!.file, isNotNull);
  });

  testWidgets('closing the scanner ends its frame stream before the camera is released', (tester) async {
    final camera = _FakeCamera(still);
    final results = <GuidedScanResult?>[];
    await open(tester, camera, results);
    await steps(tester, 10, ms: 50);
    expect(camera.log, contains('frames on #1'));
    await tester.tap(find.widgetWithIcon(IconButton, Icons.close));
    await steps(tester, 40, ms: 50);
    expect(find.byType(GuidedScanPage), findsNothing);
    expect(camera.log.indexOf('frames off #1'), greaterThanOrEqualTo(0), reason: 'the stream is let go');
    expect(camera.log.indexOf('frames off #1'), lessThan(camera.log.indexOf('camera #1 released')));
  });
}
