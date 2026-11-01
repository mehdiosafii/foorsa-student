// The Android guided camera's pieces: the grid it reads, the page it finds,
// where it focuses, the photo it hands over, and the worker that does the
// pixel work off the UI isolate.
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/guided_scanner/camera_luma.dart';
import 'package:foorsa_student/src/guided_scanner/guided_scan_page.dart';
import 'package:foorsa_student/src/guided_scanner/live_text_reader.dart';
import 'package:foorsa_student/src/guided_scanner/scan_document_profile.dart';
import 'package:foorsa_student/src/guided_scanner/scan_frame_processor.dart';
import 'package:foorsa_student/src/guided_scanner/scan_guidance.dart';
import 'package:foorsa_student/src/guided_scanner/scan_page_segment.dart';
import 'package:foorsa_student/src/guided_scanner/scan_photo.dart';
import 'package:foorsa_student/src/guided_scanner/scan_text_reading.dart';

import 'support/camera_scene.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the photo', () {
    test('is taken at the sensor\'s full resolution first, on Android only', () {
      // Before 31 Oct 2026 the camera opened at veryHigh (1920×1080) for its
      // image stream, and the plugin takes the still at that same resolution.
      expect(guidedScanResolutions.first, ResolutionPreset.max);
      expect(guidedScanResolutions, containsAllInOrder([ResolutionPreset.veryHigh, ResolutionPreset.high]));
      expect(guidedScanIosResolutions, isNot(contains(ResolutionPreset.max)));
    });

    test('is made upright and bounded to 8 MP on the phone, and only a JPEG comes back', () async {
      expect(ScanPhotoChannel.maximumEdge, 3264);
      expect(ScanPhotoChannel.quality, inInclusiveRange(90, 95));
      final jpeg = Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3, 0xff, 0xd9]);
      final ready = ScanPhotoChannel.parse({'bytes': jpeg, 'width': 2448, 'height': 3264, 'reencoded': true})!;
      expect([ready.width, ready.height, ready.reencoded], [2448, 3264, true]);
      expect(ScanPhotoChannel.parse({'error': 'memory'}), isNull);
      expect(ScanPhotoChannel.parse({'bytes': Uint8List.fromList([1, 2, 3, 4]), 'width': 1, 'height': 1}), isNull);
      expect(ScanPhotoChannel.parse({'bytes': jpeg, 'width': 0, 'height': 3}), isNull);
      expect(ScanPhotoChannel.parse(null), isNull);
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      Map<Object?, Object?>? sent;
      messenger.setMockMethodCallHandler(ScanPhotoChannel.channel, (call) async {
        sent = call.arguments as Map;
        return {'bytes': jpeg, 'width': 2448, 'height': 3264, 'reencoded': false};
      });
      final photo = await ScanPhotoChannel().prepare('/tmp/CAP1.jpg');
      expect(photo!.bytes, jpeg);
      expect(sent, {'path': '/tmp/CAP1.jpg', 'maxEdge': 3264, 'quality': ScanPhotoChannel.quality});
      // A build without the channel: the camera's own file goes as it is.
      messenger.setMockMethodCallHandler(ScanPhotoChannel.channel, null);
      expect(await ScanPhotoChannel().prepare('/tmp/CAP1.jpg'), isNull);
    });

    test('is focused on the middle of the page found, in the full camera image', () {
      // The whole 4:3 photo on screen: the preview is the image.
      final whole = guidedScanFocusPoint(const Rect.fromLTRB(0.2, 0.1, 0.6, 0.5),
          sensorWidth: 1440, sensorHeight: 1080, viewportAspect: 0.75);
      expect(whole.dx, closeTo(0.4, 1e-9));
      expect(whole.dy, closeTo(0.3, 1e-9));
      // A preview cropped to cover a tall screen shows the image's middle.
      final covered = guidedScanFocusPoint(const Rect.fromLTRB(0, 0, 1, 1),
          sensorWidth: 1920, sensorHeight: 1080, viewportAspect: 0.45);
      expect(covered, const Offset(0.5, 0.5));
      final corner = guidedScanFocusPoint(const Rect.fromLTRB(0, 0, 0.0001, 0.0001),
          sensorWidth: 1920, sensorHeight: 1080, viewportAspect: 0.45);
      expect(corner.dx, greaterThan(0.09));
      expect(corner.dy, closeTo(0, 1e-3));
      // No page found: the middle of the view.
      expect(guidedScanFocusPoint(null, sensorWidth: 1440, sensorHeight: 1080), const Offset(0.5, 0.5));
    });
  });

  group('the grid', () {
    ScanLumaPlane plane(int Function(int x, int y) value, {int width = 64, int height = 48, int stride = 64}) {
      final bytes = Uint8List(stride * height);
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          bytes[y * stride + x] = value(x, y);
        }
      }
      return ScanLumaPlane(bytes: bytes, width: width, height: height, rowStride: stride);
    }

    test('averages the pixels of each cell instead of reading one', () {
      // A 1-pixel checkerboard reads as its mean, not as whichever pixel a
      // cell lands on.
      final checker = plane((x, y) => (x + y).isEven ? 40 : 200, width: 1440, height: 1080, stride: 1440);
      final grid = sampleScanLuma(checker)!;
      final values = grid.pixels.toSet();
      expect(values.every((v) => (v - 120).abs() <= 25), isTrue, reason: '$values');
    });

    test('turns a buffer mounted either way upright', () {
      // A bright band along the sensor's first columns is the upright image's
      // top on a 90° camera and its bottom on a 270° one.
      final band = plane((x, y) => x < 8 ? 250 : 20, width: 160, height: 120, stride: 160);
      final ninety = sampleScanLuma(band, targetWidth: 40, targetHeight: 40)!;
      final twoSeventy = sampleScanLuma(band, targetWidth: 40, targetHeight: 40, sensorOrientation: 270)!;
      expect(ninety.value(20, 0), greaterThan(200));
      expect(ninety.value(20, 39), lessThan(60));
      expect(twoSeventy.value(20, 39), greaterThan(200));
      expect(twoSeventy.value(20, 0), lessThan(60));
    });

    test('refuses a plane smaller than its strides say', () {
      expect(sampleScanLuma(ScanLumaPlane(bytes: Uint8List(100), width: 640, height: 480, rowStride: 640)), isNull);
    });
  });

  test('the crop ML Kit reads maps back the same way on a camera mounted the other way round', () {
    for (final orientation in [90, 270]) {
      final crop = LiveTextCrop.forPage(const Rect.fromLTRB(0.1, 0.25, 0.9, 0.75),
          sensorWidth: 1920, sensorHeight: 1080, sensorOrientation: orientation,
          turns: const ScanTextTurnPolicy.landscape(upsideDown: false))!;
      // Upright the crop is portrait, read a quarter turned: ML Kit reads the
      // sensor crop as it is on a 90° camera, and half turned on a 270° one.
      expect(crop.rotation, orientation == 90 ? 0 : 180);
      final page = ScanTextGeometry.bounds(crop.page)!;
      expect(page.minX, closeTo(0.046, 0.005), reason: '$orientation');
      expect(page.maxX, closeTo(0.954, 0.005), reason: '$orientation');
      expect(page.minY, closeTo(0.046, 0.005), reason: '$orientation');
      expect(page.maxY, closeTo(0.954, 0.005), reason: '$orientation');
    }
  });

  test('a page held at a slant is found as its four corners', () {
    final profile = GuidedDocumentProfile.fromPortal({'documentKey': 'transcript'});
    final frames = SensorFrames(CameraScene(page: Rect.fromCenter(center: const Offset(0.5, 0.5), width: 0.62, height: 0.62 * 0.75 / 0.707),
        tiltDegrees: 12), viewportAspect: 0.75, sensorWidth: 1440, sensorHeight: 1080);
    final grid = sampleScanLuma(frames.nextPlane(), viewportAspect: 0.75)!;
    final segment = ScanPageSegmenter.find(grid, aspect: 0.75, profile: profile, guides: profile.candidateGuides(0.75));
    final page = segment.page!;
    // Its top edge falls to the right by about tan 12° of its width.
    final top = page.corners[1] - page.corners[0];
    final slope = math.atan2(top.dy, top.dx * 0.75) * 180 / math.pi;
    expect(slope, closeTo(12, 2.5));
    expect(page.fill, greaterThan(0.9));
    // The guide's straight borders do not see it; the analysis does.
    final analysis = const ScanFrameAnalyzer().analyse(grid, GuidedDocumentKind.page,
        profile: profile, viewportAspect: 0.75);
    expect(analysis.bounds, isNotNull);
    expect(analysis.corners, hasLength(4));
  });

  test('a white desk is the background, not a page running out of view', () {
    final grid = sampleScanLuma(SensorFrames(CameraScene(page: const Rect.fromLTRB(0.2, 0.2, 0.8, 0.8), background: 214),
        viewportAspect: 0.75, sensorWidth: 1440, sensorHeight: 1080).nextPlane(), viewportAspect: 0.75)!;
    final segment = ScanPageSegmenter.find(grid, aspect: 0.75);
    expect(segment.clipped, isFalse);
  });

  test('a page larger than the view is reported as running out of it', () {
    final grid = sampleScanLuma(SensorFrames(CameraScene(page: const Rect.fromLTRB(-0.1, 0.1, 0.9, 0.9)),
        viewportAspect: 0.75, sensorWidth: 1440, sensorHeight: 1080).nextPlane(), viewportAspect: 0.75)!;
    final segment = ScanPageSegmenter.find(grid, aspect: 0.75);
    expect(segment.page, isNull);
    expect(segment.clipped, isTrue);
  });

  test('the guide uses a 3:4 view\'s height, and a tall view\'s as before', () {
    final transcript = GuidedDocumentProfile.fromPortal({'documentKey': 'transcript'});
    final tall = transcript.guide(0.5);
    expect(tall.height, closeTo(0.528, 0.002));
    final whole = transcript.guide(0.75);
    expect(whole.width, closeTo(0.75, 1e-9));
    expect(whole.height, closeTo(0.75 * 0.75 / 0.71, 1e-6));
    expect(whole.top, greaterThan(0.035));
    expect(whole.bottom, lessThan(0.965));
  });

  test('the worker isolate answers what the inline work answers', () async {
    final worker = await ScanFrameWorker.start();
    expect(worker, isNotNull);
    final profile = GuidedDocumentProfile.fromPortal({'documentKey': 'identity'});
    final frames = SensorFrames(CameraScene(page: profile.guide(0.75)), viewportAspect: 0.75,
        sensorWidth: 1440, sensorHeight: 1080);
    final plane = frames.nextPlane();
    final job = ScanFrameJob(plane: plane, profile: profile, viewportAspect: 0.75, readText: true,
        turns: const ScanTextTurnPolicy.landscape(upsideDown: false));
    final inline = ScanFrameProcessor().process(job)!;
    final remote = (await worker!.process(job))!;
    expect(remote.analysis.bounds, inline.analysis.bounds);
    expect(remote.analysis.hint, inline.analysis.hint);
    expect(remote.textLuma, inline.textLuma);
    expect(remote.textCrop!.rotation, inline.textCrop!.rotation);
    worker.close();
    await expectLater(worker.process(job), throwsStateError);
  });
}
