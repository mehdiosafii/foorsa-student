// The Android guided camera when its automatic capture or its camera fails
// (guided_scan_page.dart, scan_trouble.dart): a stream that fails only at the
// sensor's maximum reopens a step lower and keeps automatic capture; any other
// loss leaves the shutter and a reason on the crash board, once a scan.
//
// The owner, 1 Nov 2026, on an Android 17 phone: "In Android the scanning
// didn't show the auto scanning interface", and the board said nothing.
// What a real phone's CameraX does is what only a phone can show; these
// tests hold what the page does with each answer.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/guided_scanner/guided_scan_page.dart';
import 'package:foorsa_student/src/guided_scanner/scan_document_profile.dart';

/// What the image stream does at one preset.
enum _Stream {
  /// A frame for each ask, as a camera that works.
  frames,

  /// No frame ever: on Android, a stream whose camera side failed after
  /// startImageStream had returned.
  silent,

  /// startImageStream throws.
  throws,
}

/// The camera at one preset.
class _At {
  const _At({this.opens = true, this.stream = _Stream.frames, this.format = ImageFormatGroup.yuv420,
      this.framesBeforeSilence, this.lostAsks = const {}});
  final bool opens;
  final _Stream stream;
  final ImageFormatGroup format;

  /// Frames sent before the stream goes silent; null for no limit.
  final int? framesBeforeSilence;

  /// The asks (counted from 1) whose frame never comes, the stream working
  /// before and after.
  final Set<int> lostAsks;
}

/// A camera that answers each preset as [at] says (a working camera
/// otherwise), records what it was asked, and hands back [stills] in turn.
class _FakeCamera extends CameraPlatform {
  _FakeCamera(this.at, {this.stills = const []});
  final Map<ResolutionPreset, _At> at;
  final List<String> stills;
  final opened = <ResolutionPreset>[];
  final framesSent = <ResolutionPreset, int>{};
  final _asks = <ResolutionPreset, int>{};
  final _presets = <int, ResolutionPreset>{};
  final _streams = <StreamController<CameraImageData>>[];
  int _ids = 0;
  int _taken = 0;

  _At _of(int cameraId) => at[_presets[cameraId]] ?? const _At();

  @override
  Future<List<CameraDescription>> availableCameras() async => const [
        CameraDescription(name: 'back', lensDirection: CameraLensDirection.back, sensorOrientation: 90),
      ];

  @override
  Future<int> createCameraWithSettings(CameraDescription description, MediaSettings settings) async {
    final id = ++_ids;
    _presets[id] = settings.resolutionPreset!;
    return id;
  }

  @override
  Future<void> initializeCamera(int cameraId, {ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown}) async {
    opened.add(_presets[cameraId]!);
    if (!_of(cameraId).opens) {
      // As CameraX refuses a set of use cases it cannot bind.
      throw PlatformException(code: 'IllegalArgumentException', message: 'No supported surface combination');
    }
  }

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) {
    final wide = _presets[cameraId] == ResolutionPreset.max ? 1440.0 : 1920.0;
    return Stream.value(CameraInitializedEvent(cameraId, wide, 1080, ExposureMode.auto, true, FocusMode.auto, true));
  }

  // Streams that stay open and say nothing, as a camera that works does.
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
  Stream<CameraImageData> onStreamedFrameAvailable(int cameraId, {CameraImageStreamOptions? options}) {
    final at = _of(cameraId);
    final preset = _presets[cameraId]!;
    if (at.stream == _Stream.throws) {
      throw PlatformException(code: 'IllegalStateException', message: 'ImageAnalysis not bound');
    }
    final sent = framesSent[preset] ?? 0;
    final limit = at.framesBeforeSilence;
    final ask = _asks[preset] = (_asks[preset] ?? 0) + 1;
    final controller = StreamController<CameraImageData>();
    _streams.add(controller);
    if (at.stream == _Stream.frames && (limit == null || sent < limit) && !at.lostAsks.contains(ask)) {
      controller.onListen = () {
        framesSent[preset] = sent + 1;
        controller.add(_frame(at.format));
      };
    }
    return controller.stream;
  }

  CameraImageData _frame(ImageFormatGroup format) => CameraImageData(
        format: CameraImageFormat(format, raw: format == ImageFormatGroup.yuv420 ? 35 : 17),
        width: 160,
        height: 120,
        // A plain grey Y plane: no page, so nothing is taken by itself.
        planes: [CameraImagePlane(bytes: Uint8List(160 * 120)..fillRange(0, 160 * 120, 90), bytesPerRow: 160, bytesPerPixel: 1)],
      );

  @override
  Future<void> setFocusPoint(int cameraId, math.Point<double>? point) async {}

  @override
  Future<void> setFlashMode(int cameraId, FlashMode mode) async {}

  @override
  Future<XFile> takePicture(int cameraId) async => XFile(stills[_taken++]);

  @override
  Widget buildPreview(int cameraId) => const ColoredBox(key: ValueKey('camera-preview'), color: Color(0xFF203040));

  @override
  Future<void> dispose(int cameraId) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<String> reports;
  late Directory dir;

  setUp(() async {
    reports = [];
    dir = await Directory.systemTemp.createTemp('guided-scan-stream');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('foorsa/scan_photo'), (call) async {
      // A phone that cannot measure a still keeps its first.
      if (call.method == 'sample') return {'error': 'failed'};
      return {'bytes': Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0]), 'width': 2448, 'height': 3264, 'reencoded': true};
    });
    messenger.setMockMethodCallHandler(const MethodChannel('foorsa/live_text'), (call) async => null);
  });

  tearDown(() async {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('foorsa/scan_photo'), null);
    messenger.setMockMethodCallHandler(const MethodChannel('foorsa/live_text'), null);
    await dir.delete(recursive: true);
  });

  /// Lets [fake] time go by, with the real event loop turning between steps
  /// (the frame worker is an isolate).
  Future<void> wait(WidgetTester tester, Duration fake, {bool Function()? until}) async {
    await tester.runAsync(() async {
      for (var i = 0; i < fake.inMilliseconds ~/ 50; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        await Future<void>.delayed(const Duration(milliseconds: 4));
        if (until?.call() == true) break;
      }
    });
  }

  /// Opens the Android scanner on [camera]; [done] receives what it hands back.
  Future<void> open(WidgetTester tester, _FakeCamera camera, void Function(GuidedScanResult?) done) async {
    CameraPlatform.instance = camera;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => TextButton(
        onPressed: () async {
          done(await Navigator.of(context).push<GuidedScanResult>(MaterialPageRoute(
            builder: (_) => GuidedScanPage(
                profile: GuidedDocumentProfile.fromPortal({'documentKey': 'transcript'}),
                android: true, reportTrouble: reports.add),
          )));
        },
        child: const Text('open'),
      )),
    ));
    await tester.tap(find.text('open'));
    // The page is built on the test's clock, so its timers (the frame wait)
    // run on the time [wait] lets go by.
    await tester.pump();
    await wait(tester, const Duration(seconds: 2),
        until: () => find.byKey(const ValueKey('camera-preview')).evaluate().isNotEmpty);
    expect(find.byKey(const ValueKey('camera-preview')), findsOneWidget, reason: 'the camera opened');
  }

  /// Closes the scanner, as the student does, and lets the camera go.
  Future<void> close(WidgetTester tester) async {
    if (find.byTooltip('Close scanner').evaluate().isEmpty) return;
    await tester.tap(find.byTooltip('Close scanner'));
    await wait(tester, const Duration(seconds: 1));
  }

  /// Whether the page still offers automatic capture: its switch enabled and
  /// no "Tap the shutter".
  bool autoCapture(WidgetTester tester) {
    final toggle = tester.widget<TextButton>(find.ancestor(of: find.text('Auto on'), matching: find.byWidgetPredicate((w) => w is TextButton)));
    return toggle.onPressed != null && find.text('Tap the shutter').evaluate().isEmpty;
  }

  testWidgets('a camera that works: frames, auto-capture, and nothing on the board', (tester) async {
    final camera = _FakeCamera({});
    await open(tester, camera, (_) {});
    await wait(tester, const Duration(seconds: 6));
    expect(camera.opened, [ResolutionPreset.max]);
    expect(camera.framesSent[ResolutionPreset.max], greaterThan(3), reason: 'a frame each ask');
    expect(autoCapture(tester), isTrue);
    expect(reports, isEmpty);
    await close(tester);
  });

  testWidgets('a stream that sends nothing at the maximum reopens at veryHigh and keeps auto-capture', (tester) async {
    final camera = _FakeCamera({ResolutionPreset.max: const _At(stream: _Stream.silent)});
    await open(tester, camera, (_) {});
    // Not before the wait: a frame can be slow on a cheap phone.
    await wait(tester, guidedScanFrameWait - const Duration(milliseconds: 500));
    expect(camera.opened, [ResolutionPreset.max]);
    expect(reports, isEmpty);
    await wait(tester, const Duration(seconds: 4));
    expect(camera.opened, [ResolutionPreset.max, ResolutionPreset.veryHigh]);
    expect(camera.framesSent[ResolutionPreset.veryHigh], greaterThan(3), reason: 'frames again, a step lower');
    expect(autoCapture(tester), isTrue);
    expect(reports, [
      'Scanner: image stream failed at max, preview 1440x1080 (no frame in 4 s); reopening at veryHigh '
          '(1080p stills) to keep auto-capture',
    ]);
    await close(tester);
  });

  testWidgets('a stream that throws at the maximum reopens at veryHigh too', (tester) async {
    final camera = _FakeCamera({ResolutionPreset.max: const _At(stream: _Stream.throws)});
    await open(tester, camera, (_) {});
    await wait(tester, const Duration(seconds: 3));
    expect(camera.opened, [ResolutionPreset.max, ResolutionPreset.veryHigh]);
    expect(autoCapture(tester), isTrue);
    expect(reports, hasLength(1));
    expect(reports.single, contains('image stream failed at max, preview 1440x1080 '
        '(startImageStream threw CameraException IllegalStateException)'));
    await close(tester);
  });

  testWidgets('a stream that fails at every preset: one reopen, then the shutter, and both on the board', (tester) async {
    final paths = [File('${dir.path}/still.jpg')..writeAsBytesSync([0xff, 0xd8])].map((f) => f.path).toList();
    final camera = _FakeCamera({
      ResolutionPreset.max: const _At(stream: _Stream.silent),
      ResolutionPreset.veryHigh: const _At(stream: _Stream.silent),
      ResolutionPreset.high: const _At(stream: _Stream.silent),
    }, stills: paths);
    GuidedScanResult? result;
    await open(tester, camera, (r) => result = r);
    await wait(tester, const Duration(seconds: 10));
    expect(camera.opened, [ResolutionPreset.max, ResolutionPreset.veryHigh], reason: 'reopened once, not twice');
    expect(find.text('Tap the shutter'), findsOneWidget);
    expect(reports, [
      contains('image stream failed at max, preview 1440x1080 (no frame in 4 s)'),
      'Scanner: no auto-capture, shutter only (no frame in 4 s); camera veryHigh, preview 1920x1080',
    ]);

    // The shutter still takes the page.
    await tester.tap(find.bySemanticsLabel('Take photo manually'));
    await wait(tester, const Duration(seconds: 5), until: () => result != null);
    await wait(tester, const Duration(seconds: 1));
    expect(result?.file?.path, paths.single);
    expect(reports, hasLength(2));
  });

  testWidgets('a scan reports each loss once, however often the camera reopens', (tester) async {
    final camera = _FakeCamera({
      ResolutionPreset.max: const _At(stream: _Stream.silent),
      ResolutionPreset.veryHigh: const _At(stream: _Stream.silent),
    });
    await open(tester, camera, (_) {});
    await wait(tester, const Duration(seconds: 10));
    expect(reports, hasLength(2));
    // The student leaves the app and comes back: the camera reopens, at
    // veryHigh again, and its stream fails again.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await wait(tester, const Duration(milliseconds: 500));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await wait(tester, const Duration(seconds: 6));
    expect(camera.opened, [ResolutionPreset.max, ResolutionPreset.veryHigh, ResolutionPreset.veryHigh]);
    expect(find.text('Tap the shutter'), findsOneWidget);
    expect(reports, hasLength(2), reason: 'nothing new on the board');
    await close(tester);
  });

  testWidgets('frames that stop after a few at the maximum keep the maximum: the shutter, and why', (tester) async {
    final camera = _FakeCamera({ResolutionPreset.max: const _At(framesBeforeSilence: 3)});
    await open(tester, camera, (_) {});
    // The fourth frame does not come in 4 s, nor the one asked for again.
    await wait(tester, const Duration(seconds: 6));
    expect(reports, isEmpty, reason: 'one late frame is asked for again first');
    await wait(tester, const Duration(seconds: 4));
    expect(camera.opened, [ResolutionPreset.max], reason: 'the stream worked at the maximum: no 1080p stills for it');
    expect(find.text('Tap the shutter'), findsOneWidget);
    expect(reports, ['Scanner: no auto-capture, shutter only (frames stopped after 3); camera max, preview 1440x1080']);
    await close(tester);
  });

  testWidgets('one frame lost between asks is asked for again: auto-capture stays, nothing on the board', (tester) async {
    final camera = _FakeCamera({ResolutionPreset.max: const _At(lostAsks: {4})});
    await open(tester, camera, (_) {});
    await wait(tester, const Duration(seconds: 8));
    expect(camera.opened, [ResolutionPreset.max]);
    expect(camera.framesSent[ResolutionPreset.max], greaterThan(6), reason: 'frames again after the lost one');
    expect(autoCapture(tester), isTrue);
    expect(reports, isEmpty);
    await close(tester);
  });

  testWidgets('frames the scanner cannot read: the shutter, the format on the board, no reopen', (tester) async {
    final camera = _FakeCamera({ResolutionPreset.max: const _At(format: ImageFormatGroup.nv21)});
    await open(tester, camera, (_) {});
    await wait(tester, const Duration(seconds: 2));
    expect(camera.opened, [ResolutionPreset.max]);
    expect(camera.framesSent[ResolutionPreset.max], 1, reason: 'no frame asked for after it');
    expect(find.text('Tap the shutter'), findsOneWidget);
    expect(reports, ['Scanner: no auto-capture, shutter only (frame format nv21 (raw 17)); camera max, preview 1440x1080']);
    await close(tester);
  });

  testWidgets('a camera that opens only lower says so with any later report', (tester) async {
    final camera = _FakeCamera({
      ResolutionPreset.max: const _At(opens: false),
      ResolutionPreset.veryHigh: const _At(stream: _Stream.silent),
    });
    await open(tester, camera, (_) {});
    await wait(tester, const Duration(seconds: 5));
    expect(camera.opened, [ResolutionPreset.max, ResolutionPreset.veryHigh]);
    expect(reports, [
      'Scanner: no auto-capture, shutter only (no frame in 4 s); camera veryHigh, preview 1920x1080, '
          'after max: CameraException IllegalArgumentException',
    ]);
    await close(tester);
  });

  testWidgets('a camera that never opens: why, then the camera app the student chose', (tester) async {
    final camera = _FakeCamera({
      for (final preset in guidedScanResolutions) preset: const _At(opens: false),
    });
    CameraPlatform.instance = camera;
    GuidedScanResult? result;
    var returned = false;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => TextButton(
        onPressed: () async {
          result = await Navigator.of(context).push<GuidedScanResult>(MaterialPageRoute(
            builder: (_) => GuidedScanPage(
                profile: GuidedDocumentProfile.fromPortal({'documentKey': 'transcript'}),
                android: true, reportTrouble: reports.add),
          ));
          returned = true;
        },
        child: const Text('open'),
      )),
    ));
    await tester.tap(find.text('open'));
    // The page is built on the test's clock, so its timers (the frame wait)
    // run on the time [wait] lets go by.
    await tester.pump();
    await wait(tester, const Duration(seconds: 2), until: () => find.text('Camera app').evaluate().isNotEmpty);
    expect(camera.opened, guidedScanResolutions);
    expect(reports, [
      'Scanner: camera did not open (CameraException IllegalArgumentException at max, veryHigh, high)',
    ]);

    await tester.tap(find.text('Camera app'));
    await wait(tester, const Duration(seconds: 2), until: () => returned);
    await wait(tester, const Duration(seconds: 1));
    expect(result?.useLegacyCamera, isTrue);
    expect(reports.last,
        'Scanner: student chose the phone camera app (camera did not open: '
        'CameraException IllegalArgumentException at max, veryHigh, high)');
    expect(reports, hasLength(2));
  });
}
