import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/app_language.dart';
import 'package:foorsa_student/src/guided_scanner/guided_scan_page.dart';
import 'package:foorsa_student/src/guided_scanner/scan_document_profile.dart';
import 'package:foorsa_student/src/guided_scanner/scan_guidance_view.dart';

/// The guided camera's own screen on every phone it opens on, held upright
/// and on its side (a passport open on both pages is wider than tall, and a
/// student turns the phone to it), with the phone's text set larger, in the
/// three languages, with a camera that works and one that does not.
///
/// The owner's stress test, 12 Nov 2026. A case fails when Flutter reports
/// that something does not fit, when the shutter or the way out is not wholly
/// on the screen, or when what the top of the screen says runs into the
/// guidance at its foot.

const _phones = <(String, Size, FakeViewPadding)>[
  ('the first iPhone SE', Size(320, 568), FakeViewPadding(top: 20)),
  ('a small Android', Size(360, 640), FakeViewPadding(top: 24)),
  ('an iPhone 14', Size(390, 844), FakeViewPadding(top: 47, bottom: 34)),
  ('a large Android', Size(412, 915), FakeViewPadding(top: 32, bottom: 16)),
  ('a small Android on its side', Size(640, 360), FakeViewPadding(left: 24)),
  (
    'an iPhone 14 on its side',
    Size(844, 390),
    FakeViewPadding(left: 47, right: 47, bottom: 21)
  ),
  ('a tablet', Size(768, 1024), FakeViewPadding(top: 24, bottom: 20)),
];
const _scales = [1.0, 1.3, 2.0];

/// A camera that opens and shows a still picture, or one the phone does not
/// have.
class _Camera extends CameraPlatform {
  _Camera({required this.works});
  final bool works;

  @override
  Future<List<CameraDescription>> availableCameras() async => works
      ? const [
          CameraDescription(
              name: 'back',
              lensDirection: CameraLensDirection.back,
              sensorOrientation: 90),
        ]
      : const [];

  @override
  Future<int> createCameraWithSettings(
          CameraDescription description, MediaSettings settings) async =>
      1;

  @override
  Future<void> initializeCamera(int cameraId,
      {ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown}) async {}

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      Stream.value(const CameraInitializedEvent(
          1, 1440, 1080, ExposureMode.auto, true, FocusMode.auto, true));

  @override
  Stream<CameraClosingEvent> onCameraClosing(int cameraId) =>
      StreamController<CameraClosingEvent>().stream;

  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) =>
      StreamController<CameraErrorEvent>().stream;

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream.empty();

  @override
  Future<void> lockCaptureOrientation(
      int cameraId, DeviceOrientation orientation) async {}

  @override
  bool supportsImageStreaming() => true;

  @override
  Stream<CameraImageData> onStreamedFrameAvailable(int cameraId,
          {CameraImageStreamOptions? options}) =>
      const Stream.empty();

  @override
  Future<void> setFocusPoint(int cameraId, math.Point<double>? point) async {}

  @override
  Future<void> setFlashMode(int cameraId, FlashMode mode) async {}

  @override
  Widget buildPreview(int cameraId) => const ColoredBox(
      key: ValueKey('camera-preview'), color: Color(0xFF203040));

  @override
  Future<void> dispose(int cameraId) async {}
}

/// The fonts a phone draws with (see native_layout_sweep_test.dart).
Future<({bool latin, bool arabic})> _loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return (latin: false, arabic: false);
  final dir = Directory('$root/bin/cache/artifacts/material_fonts');
  if (!dir.existsSync()) return (latin: false, arabic: false);
  Future<ByteData> bytes(String path) async =>
      ByteData.sublistView(await File(path).readAsBytes());
  await (FontLoader('Roboto')
        ..addFont(bytes('${dir.path}/Roboto-Regular.ttf'))
        ..addFont(bytes('${dir.path}/Roboto-Medium.ttf'))
        ..addFont(bytes('${dir.path}/Roboto-Bold.ttf')))
      .load();
  await (FontLoader('MaterialIcons')
        ..addFont(bytes('${dir.path}/MaterialIcons-Regular.otf')))
      .load();
  final naskh = File(
      '$root/engine/src/flutter/txt/third_party/fonts/NotoNaskhArabic-Regular.ttf');
  if (!naskh.existsSync()) return (latin: true, arabic: false);
  await (FontLoader('NotoNaskhArabic')..addFont(bytes(naskh.path))).load();
  return (latin: true, arabic: true);
}

const _takePhoto = Words('Take photo manually', 'Prendre la photo manuellement',
    'التقاط الصورة يدويًا');
const _close =
    Words('Close scanner', 'Fermer le scanner', 'إغلاق الماسح الضوئي');

String? _offScreen(WidgetTester tester, Finder finder, Size size, String what) {
  if (finder.evaluate().isEmpty) return '$what is not there';
  final rect = tester.getRect(finder.first);
  if (rect.left < -0.5 ||
      rect.top < -0.5 ||
      rect.right > size.width + 0.5 ||
      rect.bottom > size.height + 0.5) {
    return '$what is off the screen: ${rect.left.round()},${rect.top.round()} '
        'to ${rect.right.round()},${rect.bottom.round()}';
  }
  return null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel('foorsa/scan_photo'), (call) async => null);
    messenger.setMockMethodCallHandler(
        const MethodChannel('foorsa/live_text'), (call) async => null);
  });
  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel('foorsa/scan_photo'), null);
    messenger.setMockMethodCallHandler(
        const MethodChannel('foorsa/live_text'), null);
  });

  for (final works in [true, false]) {
    for (final language in AppLanguage.values) {
      testWidgets(
          'the scanner fits on every phone, ${language.code}, '
          '${works ? 'camera open' : 'no camera'}', (tester) async {
        final fonts = await tester.runAsync(_loadFonts);
        if (fonts == null || !fonts.latin) {
          markTestSkipped('The Flutter SDK\'s fonts are not here.');
          return;
        }
        if (language == AppLanguage.ar && !fonts.arabic) {
          markTestSkipped('No Arabic font in this Flutter SDK.');
          return;
        }
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearAllTestValues);
        CameraPlatform.instance = _Camera(works: works);
        final problems = <String>[];
        var looked = 0;
        for (final (phone, size, padding) in _phones) {
          for (final scale in _scales) {
            for (final request in const [
              {'documentKey': 'identity'},
              {'documentKey': 'transcript'},
              {'documentKey': 'medical_check'},
            ]) {
              tester.view.devicePixelRatio = 1;
              tester.view.physicalSize = size;
              tester.view.padding = padding;
              tester.platformDispatcher.textScaleFactorTestValue = scale;
              // In the student's language, as the shell asks for it.
              final profile =
                  GuidedDocumentProfile.fromPortal(request, language);
              final where = '$phone (${size.width.toInt()}x'
                  '${size.height.toInt()}), text x$scale, '
                  '${request['documentKey']}';
              await tester.pumpWidget(MaterialApp(
                theme: ThemeData(
                    useMaterial3: true,
                    fontFamily: 'Roboto',
                    fontFamilyFallback: const ['NotoNaskhArabic']),
                builder: (context, page) => AppLanguageScope(
                    language: language, child: page ?? const SizedBox()),
                home: GuidedScanPage(profile: profile, android: true),
              ));
              await tester.runAsync(() async {
                for (var i = 0; i < 40; i++) {
                  await tester.pump(const Duration(milliseconds: 50));
                  await Future<void>.delayed(const Duration(milliseconds: 5));
                  if (works &&
                      find
                          .byKey(const ValueKey('camera-preview'))
                          .evaluate()
                          .isNotEmpty) {
                    break;
                  }
                  if (!works && i > 6) break;
                }
              });
              await tester.pump(const Duration(milliseconds: 400));
              looked++;
              var said = tester.takeException()?.toString().split('\n').first;
              said ??= _offScreen(
                  tester,
                  find.bySemanticsLabel(_takePhoto.of(language)),
                  size,
                  'the shutter');
              said ??= _offScreen(
                  tester, find.byTooltip(_close.of(language)), size, 'Close');
              if (said == null) {
                // What the top says ends above the guidance at the foot.
                final room = find.byKey(const ValueKey('scan-instruction'));
                final words = find.text(profile.instruction);
                final panel = find.byType(ScanGuidancePanel);
                if (room.evaluate().isEmpty || words.evaluate().isEmpty) {
                  said = 'the instruction is not there';
                } else {
                  final box = tester.getRect(room);
                  final text = tester.getRect(words.first);
                  final guide = tester.getRect(panel.first);
                  if (box.bottom > guide.top + 0.5) {
                    said = 'the instruction\'s room runs '
                        '${(box.bottom - guide.top).round()} points into the '
                        'guidance';
                  } else if (size.height > size.width &&
                      scale <= 1.3 &&
                      text.bottom > box.bottom + 0.5) {
                    // An upright phone has room for all of it.
                    said = 'the instruction is cut short by '
                        '${(text.bottom - box.bottom).round()} points';
                  }
                }
              }
              if (said != null) problems.add('$where: $said');
              await tester.pumpWidget(const SizedBox());
              await tester.runAsync(
                  () => Future<void>.delayed(const Duration(milliseconds: 5)));
              await tester.pump(const Duration(milliseconds: 300));
              tester.takeException();
            }
          }
        }
        expect(looked, _phones.length * _scales.length * 3);
        expect(problems, isEmpty, reason: problems.join('\n'));
      });
    }
  }
}
