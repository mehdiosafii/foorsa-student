// What the Android guided camera tells the crash board when a scan loses its
// automatic capture or its camera (scan_trouble.dart), and the presets it
// opens at once the image stream failed at the maximum (guided_scan_page.dart).
import 'dart:async';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart' show CameraImageData, CameraImageFormat, CameraImagePlane;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/guided_scanner/camera_luma.dart';
import 'package:foorsa_student/src/guided_scanner/guided_scan_page.dart';
import 'package:foorsa_student/src/guided_scanner/scan_trouble.dart';

/// What the server keeps of a report (foorsa-reward, `cleanCrashText`): long
/// numbers, addresses and emails are taken out, so a report must not need them.
bool _survivesTheServer(String text) =>
    !RegExp(r'\d{6,}').hasMatch(text) && !text.contains('://') && !text.contains('@');

CameraImage _frame(ImageFormatGroup group, int raw, {int width = 160, int height = 120, int rowStride = 160, int planes = 1}) =>
    CameraImage.fromPlatformInterface(CameraImageData(
      format: CameraImageFormat(group, raw: raw),
      width: width,
      height: height,
      planes: [
        for (var i = 0; i < planes; i++)
          CameraImagePlane(bytes: Uint8List(width * height), bytesPerRow: rowStride, bytesPerPixel: 1),
      ],
    ));

void main() {
  group('the presets the camera opens at', () {
    test('Android: the maximum first, then a step lower each time it does not open', () {
      expect(guidedScanPresets(android: true),
          [ResolutionPreset.max, ResolutionPreset.veryHigh, ResolutionPreset.high]);
    });

    test('once the stream failed at the maximum: veryHigh first, the maximum only for the shutter', () {
      expect(guidedScanPresets(android: true, streamFailedAtMax: true),
          [ResolutionPreset.veryHigh, ResolutionPreset.max]);
    });

    test('the iPhone keeps its own, whatever happened', () {
      expect(guidedScanPresets(android: false, streamFailedAtMax: true), guidedScanIosResolutions);
    });
  });

  group('an error as the board names it', () {
    test('a camera or platform error by its type and code, never its message', () {
      final camera = scanErrorName(CameraException('IllegalArgumentException', '/data/user/0/ma.foorsa/cache/x.jpg'));
      expect(camera, 'CameraException IllegalArgumentException');
      final platform = scanErrorName(PlatformException(code: 'CameraAccess', message: 'denied for student@example.com'));
      expect(platform, 'PlatformException CameraAccess');
      expect(scanErrorName(TimeoutException('late', const Duration(seconds: 3))), 'TimeoutException');
    });

    test('the page\'s own words, but no other error\'s message', () {
      expect(scanErrorName(StateError('No rear camera')), 'StateError: No rear camera');
      expect(scanErrorName(StateError('Bad path /storage/emulated/0')), 'StateError');
      expect(scanErrorName(const FormatException('passport P<MAR')), 'FormatException');
    });

    test('a code that is not a code is cut short and cleaned', () {
      final name = scanErrorName(CameraException('<script>${'x' * 200}', null));
      expect(name, startsWith('CameraException script'));
      expect(name.length, lessThanOrEqualTo('CameraException '.length + 60));
    });
  });

  group('how the camera opened', () {
    test('the preset and the preview\'s size', () {
      expect(scanCameraNote(ResolutionPreset.max, const Size(1440, 1080)), 'max, preview 1440x1080');
    });

    test('and the presets above it that did not open', () {
      expect(
          scanCameraNote(ResolutionPreset.veryHigh, const Size(1920, 1080),
              skipped: [(ResolutionPreset.max, 'CameraException IllegalArgumentException')]),
          'veryHigh, preview 1920x1080, after max: CameraException IllegalArgumentException');
    });

    test('why it did not open, each error with the presets it stopped', () {
      final error = CameraException('IllegalArgumentException', null);
      expect(
          scanOpenFailure(error, [
            (ResolutionPreset.max, 'CameraException IllegalArgumentException'),
            (ResolutionPreset.veryHigh, 'CameraException IllegalArgumentException'),
            (ResolutionPreset.high, 'CameraException CameraAccessDenied'),
          ]),
          'CameraException IllegalArgumentException at max, veryHigh; CameraException CameraAccessDenied at high');
      expect(scanOpenFailure(StateError('No rear camera'), const []), 'StateError: No rear camera');
    });
  });

  group('the board\'s line', () {
    const camera = 'max, preview 1440x1080';
    final lines = {
      ScanTrouble.streamRetried: scanTroubleReport(ScanTrouble.streamRetried, 'no frame in 4 s', camera: camera),
      ScanTrouble.autoCaptureLost:
          scanTroubleReport(ScanTrouble.autoCaptureLost, 'frame format nv21 (raw 17)', camera: camera),
      ScanTrouble.cameraFailed:
          scanTroubleReport(ScanTrouble.cameraFailed, 'CameraException IllegalArgumentException at max, veryHigh, high'),
      ScanTrouble.cameraApp: scanTroubleReport(ScanTrouble.cameraApp, 'CameraException CameraAccessDenied at max'),
    };

    test('says what was lost, why, and at which preset', () {
      expect(lines[ScanTrouble.streamRetried],
          'Scanner: image stream failed at max, preview 1440x1080 (no frame in 4 s); reopening at veryHigh '
          '(1080p stills) to keep auto-capture');
      expect(lines[ScanTrouble.autoCaptureLost],
          'Scanner: no auto-capture, shutter only (frame format nv21 (raw 17)); camera max, preview 1440x1080');
      expect(lines[ScanTrouble.cameraFailed],
          'Scanner: camera did not open (CameraException IllegalArgumentException at max, veryHigh, high)');
      expect(lines[ScanTrouble.cameraApp],
          'Scanner: student chose the phone camera app (camera did not open: CameraException CameraAccessDenied at max)');
    });

    test('fits the board and keeps every word through the server\'s cleaning', () {
      for (final line in lines.values) {
        expect(line.length, lessThanOrEqualTo(300));
        expect(_survivesTheServer(line), isTrue, reason: line);
      }
      final long = scanTroubleReport(ScanTrouble.autoCaptureLost, 'x' * 400, camera: camera);
      expect(long.length, 300);
    });
  });

  group('a frame the scanner cannot read says why', () {
    test('its format, by name and raw value', () {
      expect(ScanLumaPlane.whyUnreadable(_frame(ImageFormatGroup.nv21, 17)), 'frame format nv21 (raw 17)');
      expect(ScanLumaPlane.fromCameraImage(_frame(ImageFormatGroup.nv21, 17)), isNull);
      expect(ScanLumaPlane.whyUnreadable(_frame(ImageFormatGroup.jpeg, 256)), 'frame format jpeg (raw 256)');
    });

    test('its size and planes, or its strides', () {
      expect(ScanLumaPlane.whyUnreadable(_frame(ImageFormatGroup.yuv420, 35, planes: 0)), 'frame 160x120, 0 planes');
      expect(ScanLumaPlane.whyUnreadable(_frame(ImageFormatGroup.yuv420, 35, rowStride: 0)),
          'frame row stride 0, pixel stride 1');
    });

    test('and nothing for the frames it reads, as before', () {
      final frame = _frame(ImageFormatGroup.yuv420, 35);
      expect(ScanLumaPlane.whyUnreadable(frame), isNull);
      final plane = ScanLumaPlane.fromCameraImage(frame)!;
      expect((plane.width, plane.height, plane.rowStride, plane.pixelStride, plane.bgra), (160, 120, 160, 1, false));
      expect(plane.layout, '160x120, row 160, pixel 1, 18 KB');
    });
  });
}
