import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/guided_scanner/live_text_reader.dart';
import 'package:foorsa_student/src/guided_scanner/scan_guidance.dart';
import 'package:foorsa_student/src/guided_scanner/scan_text_reading.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the crop ML Kit reads', () {
    test('a landscape buffer is cropped round the page, with a margin, in even pixels', () {
      final crop = LiveTextCrop.forPage(const Rect.fromLTRB(0.1, 0.25, 0.9, 0.75),
          sensorWidth: 1920, sensorHeight: 1080,
          turns: const ScanTextTurnPolicy.landscape(upsideDown: false))!;
      // Upright x 0.06–0.94 and y 0.225–0.775 after the 10% margin: sensor
      // x 432–1488, y 64.8–1015.2, widened to even pixels, never narrowed.
      expect(crop.x0, inInclusiveRange(430, 432));
      expect(crop.y0, inInclusiveRange(62, 64));
      expect(crop.x0 + crop.width, inInclusiveRange(1488, 1490));
      expect(crop.y0 + crop.height, inInclusiveRange(1016, 1018));
      expect(crop.x0.isEven && crop.y0.isEven && crop.width.isEven && crop.height.isEven, isTrue);
      // The upright crop is portrait, so the landscape rule turns it a quarter:
      // ML Kit then reads the sensor crop as it is.
      expect(crop.quarterTurns, 1);
      expect(crop.rotation, 0);
      expect(crop.readingWidth, crop.width);
      expect(crop.readingHeight, crop.height);
      // The page inside the crop actually taken, y up: exactly where the
      // even-pixel crop puts it, and close to the 10% margin either way.
      final page = ScanTextGeometry.bounds(crop.page)!;
      final cropLeft = 1 - (crop.y0 + crop.height) / 1080, spanX = crop.height / 1080;
      final cropTop = crop.x0 / 1920, spanY = crop.width / 1920;
      expect(page.minX, closeTo((0.1 - cropLeft) / spanX, 1e-9));
      expect(page.maxX, closeTo((0.9 - cropLeft) / spanX, 1e-9));
      expect(page.minY, closeTo(1 - (0.75 - cropTop) / spanY, 1e-9));
      expect(page.maxY, closeTo(1 - (0.25 - cropTop) / spanY, 1e-9));
      expect(page.minX, closeTo(0.046, 0.005));
      expect(page.maxX, closeTo(0.954, 0.005));
      expect(page.minY, closeTo(0.046, 0.005));
      expect(page.maxY, closeTo(0.954, 0.005));
      // Without a turn policy the crop is read as it stands upright.
      final asSeen = LiveTextCrop.forPage(const Rect.fromLTRB(0.1, 0.25, 0.9, 0.75),
          sensorWidth: 1920, sensorHeight: 1080)!;
      expect(asSeen.quarterTurns, 0);
      expect(asSeen.rotation, 90);
      expect(asSeen.readingWidth, asSeen.height);
    });

    test('an upright page needs no turn beyond the sensor quarter', () {
      final crop = LiveTextCrop.forPage(const Rect.fromLTRB(0.05, 0.3, 0.95, 0.6),
          sensorWidth: 1920, sensorHeight: 1080, turns: const ScanTextTurnPolicy.landscape(upsideDown: false))!;
      expect(crop.quarterTurns, 0);
      expect(crop.rotation, 90);
      expect(crop.readingWidth, crop.height);
      final upsideDown = LiveTextCrop.forPage(const Rect.fromLTRB(0.05, 0.3, 0.95, 0.6),
          sensorWidth: 1920, sensorHeight: 1080, turns: const ScanTextTurnPolicy.landscape(upsideDown: true))!;
      expect(upsideDown.quarterTurns, 2);
      expect(upsideDown.rotation, 270);
      final portraitBuffer = LiveTextCrop.forPage(const Rect.fromLTRB(0.1, 0.1, 0.9, 0.9),
          sensorWidth: 1080, sensorHeight: 1920)!;
      expect(portraitBuffer.rotation, 0);
      expect(LiveTextCrop.forPage(const Rect.fromLTRB(0.5, 0.5, 0.51, 0.51), sensorWidth: 1920, sensorHeight: 1080),
          isNull);
      expect(LiveTextCrop.forPage(const Rect.fromLTRB(0.1, 0.1, 0.9, 0.9), sensorWidth: 16, sensorHeight: 16), isNull);
    });

    test('the viewport crop is the one the luma analyzer used', () {
      // A tall viewport over a 16:9 buffer shows its middle only.
      final full = LiveTextCrop.forPage(const Rect.fromLTRB(0.2, 0.2, 0.8, 0.8),
          sensorWidth: 1920, sensorHeight: 1080)!;
      final cropped = LiveTextCrop.forPage(const Rect.fromLTRB(0.2, 0.2, 0.8, 0.8),
          sensorWidth: 1920, sensorHeight: 1080, viewportAspect: 0.45)!;
      expect(cropped.height, lessThan(full.height));
      expect(cropped.width, full.width);
    });

    test('lines map back onto the page in the shared terms, however the crop is turned', () {
      const policies = [
        ScanTextTurnPolicy.fixed(0), ScanTextTurnPolicy.fixed(1), ScanTextTurnPolicy.fixed(2),
        ScanTextTurnPolicy.fixed(3), ScanTextTurnPolicy.landscape(upsideDown: false),
        ScanTextTurnPolicy.landscape(upsideDown: true),
      ];
      for (final (sensorWidth, sensorHeight) in [(1920, 1080), (1080, 1920)]) {
        for (var i = 0; i < policies.length; i++) {
          final crop = LiveTextCrop.forPage(const Rect.fromLTRB(0.1, 0.25, 0.9, 0.75),
              sensorWidth: sensorWidth, sensorHeight: sensorHeight, turns: policies[i])!;
          // A line across the middle of the upright crop, as ML Kit reports it
          // in the image it read: the upright crop turned counterclockwise.
          const upright = TextBox(0.2, 0.5, 0.8, 0.52);
          final readingA = ScanQuarterTurn.apply(crop.quarterTurns, math.Point(upright.minX, upright.minY));
          final readingB = ScanQuarterTurn.apply(crop.quarterTurns, math.Point(upright.maxX, upright.maxY));
          final w = crop.readingWidth.toDouble(), h = crop.readingHeight.toDouble();
          final left = math.min(readingA.x, readingB.x) * w, right = math.max(readingA.x, readingB.x) * w;
          final top = (1 - math.max(readingA.y, readingB.y)) * h, bottom = (1 - math.min(readingA.y, readingB.y)) * h;
          final frame = crop.frame([
            LiveTextLine('Royaume du Maroc', left, top, right, bottom),
            const LiveTextLine('empty box', 10, 10, 10, 20),
          ]);
          final where = '$sensorWidth x $sensorHeight, policy $i';
          expect(frame.lines, hasLength(1), reason: where);
          final pageBox = frame.lines.single.pageBox;
          expect(pageBox.minX, closeTo(upright.minX, 1e-9), reason: where);
          expect(pageBox.maxX, closeTo(upright.maxX, 1e-9), reason: where);
          expect(pageBox.minY, closeTo(upright.minY, 1e-9), reason: where);
          expect(pageBox.maxY, closeTo(upright.maxY, 1e-9), reason: where);
          expect(frame.quarterTurns, crop.quarterTurns, reason: where);
          expect(frame.readingWidth, w, reason: where);
          // ML Kit turns the sensor crop clockwise by `rotation` to read it;
          // that image is the upright crop turned `quarterTurns` the other way.
          final uprightWidth = sensorWidth > sensorHeight ? crop.height : crop.width;
          final uprightHeight = sensorWidth > sensorHeight ? crop.width : crop.height;
          final odd = crop.quarterTurns.isOdd;
          expect(crop.readingWidth, odd ? uprightHeight : uprightWidth, reason: where);
          expect(crop.readingHeight, odd ? uprightWidth : uprightHeight, reason: where);
        }
      }
    });

    test('the luminance is copied row by row, whatever the stride', () {
      final crop = LiveTextCrop.forPage(const Rect.fromLTRB(0.1, 0.1, 0.9, 0.9),
          sensorWidth: 64, sensorHeight: 48)!;
      const stride = 80;
      final plane = Uint8List(stride * 48);
      for (var y = 0; y < 48; y++) {
        for (var x = 0; x < 64; x++) {
          plane[y * stride + x] = (x + y * 3) % 256;
        }
      }
      final luma = crop.extract(plane, rowStride: stride)!;
      expect(luma, hasLength(crop.width * crop.height));
      expect(luma[0], (crop.x0 + crop.y0 * 3) % 256);
      expect(luma[crop.width + 1], (crop.x0 + 1 + (crop.y0 + 1) * 3) % 256);
      final strided = Uint8List(stride * 2 * 48);
      for (var y = 0; y < 48; y++) {
        for (var x = 0; x < 64; x++) {
          strided[y * stride * 2 + x * 2] = (x + y * 3) % 256;
        }
      }
      expect(crop.extract(strided, rowStride: stride * 2, pixelStride: 2), luma);
      expect(crop.extract(Uint8List(10), rowStride: stride), isNull);
      expect(crop.extract(plane, rowStride: 0), isNull);
    });
  });

  group('the channel to ML Kit', () {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(() => messenger.setMockMethodCallHandler(LiveTextChannel.channel, null));
    final crop = LiveTextCrop.forPage(const Rect.fromLTRB(0.1, 0.25, 0.9, 0.75),
        sensorWidth: 1920, sensorHeight: 1080)!;

    test('sends the crop and parses lines, bounded', () async {
      Map<Object?, Object?>? sent;
      messenger.setMockMethodCallHandler(LiveTextChannel.channel, (call) async {
        expect(call.method, 'read');
        sent = call.arguments as Map;
        return {
          'width': crop.readingWidth,
          'height': crop.readingHeight,
          'lines': [
            {'text': 'P<UTOERIKSSON<<ANNA', 'left': 10, 'top': 20, 'right': 300, 'bottom': 40},
            {'text': 'x' * 500, 'left': 1, 'top': 2, 'right': 3, 'bottom': 4},
            {'text': 'no box'},
            'garbage',
          ],
        };
      });
      final result = await LiveTextChannel().read(Uint8List(crop.width * crop.height), crop);
      expect(sent!['width'], crop.width);
      expect(sent!['height'], crop.height);
      expect(sent!['rotation'], crop.rotation);
      expect((sent!['luma'] as Uint8List).length, crop.width * crop.height);
      expect(result.status, LiveTextReadStatus.read);
      expect(result.lines, hasLength(2));
      expect(result.lines.first.text, 'P<UTOERIKSSON<<ANNA');
      expect(result.lines.last.text, hasLength(LiveTextChannel.maximumTextLength));
    });

    test('busy, errors and a build without the reader are told apart', () async {
      messenger.setMockMethodCallHandler(LiveTextChannel.channel, (_) async => {'busy': true});
      expect((await LiveTextChannel().read(Uint8List(4), crop)).status, LiveTextReadStatus.busy);
      messenger.setMockMethodCallHandler(LiveTextChannel.channel, (_) async => {'error': 'recognition_failed'});
      expect((await LiveTextChannel().read(Uint8List(4), crop)).status, LiveTextReadStatus.failed);
      messenger.setMockMethodCallHandler(LiveTextChannel.channel,
          (_) async => throw PlatformException(code: 'boom'));
      expect((await LiveTextChannel().read(Uint8List(4), crop)).status, LiveTextReadStatus.failed);
      messenger.setMockMethodCallHandler(LiveTextChannel.channel, null);
      expect((await LiveTextChannel().read(Uint8List(4), crop)).status, LiveTextReadStatus.unavailable);
      expect(LiveTextChannel.parse(null).status, LiveTextReadStatus.failed);
      expect(LiveTextChannel.parse({'lines': 'nope'}).status, LiveTextReadStatus.failed);
      await LiveTextChannel().close();
    });

    test('what ML Kit reads off a passport passes the same gate as on the iPhone', () {
      final reading = ScanTextReadingSession(kind: ScanPaperKind.passport);
      final passport = LiveTextCrop.forPage(const Rect.fromLTRB(0.05, 0.3, 0.95, 0.6),
          sensorWidth: 1920, sensorHeight: 1080)!;
      expect(passport.quarterTurns, 0);
      final w = passport.readingWidth.toDouble(), h = passport.readingHeight.toDouble();
      // The two lines at the bottom of the photo page, in ML Kit's pixels.
      final lines = [
        LiveTextLine('P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<', 0.08 * w, 0.80 * h, 0.92 * w, 0.83 * h),
        LiveTextLine('L898902C36UTO7408122F1204159ZE184226B<<<<<10', 0.08 * w, 0.86 * h, 0.92 * w, 0.89 * h),
      ];
      reading.ingest(passport.frame(lines));
      reading.ingest(passport.frame(lines));
      expect(reading.status(glare: false).passed, isTrue);
    });
  });

  test('the steadiness hold can stay ready for the reading to decide', () {
    final gate = ScanAutoCaptureGate();
    const ready = ScanFrameAnalysis(hint: ScanHint.ready, bounds: Rect.fromLTRB(0.1, 0.2, 0.9, 0.8),
        edgeSupport: 1, motion: 0, brightness: 200, sharpness: 80, contrast: 120);
    const moving = ScanFrameAnalysis(hint: ScanHint.holdSteady, bounds: Rect.fromLTRB(0.1, 0.2, 0.9, 0.8),
        edgeSupport: 1, motion: 20, brightness: 200, sharpness: 80, contrast: 120);
    final start = DateTime(2026, 10, 30);
    DateTime at(int ms) => start.add(Duration(milliseconds: ms));
    expect(gate.observe(ready, at(0)), isFalse);
    expect(gate.observe(ready, at(230)), isFalse);
    expect(gate.observe(ready, at(460)), isFalse);
    expect(gate.observe(ready, at(690)), isTrue);
    // No latch: still ready on the next steady frame, until the page moves.
    expect(gate.observe(ready, at(920)), isTrue);
    expect(gate.observe(moving, at(1150)), isFalse);
    expect(gate.observe(ready, at(1380)), isFalse);
    // The one-shot form is unchanged.
    final once = ScanAutoCaptureGate();
    expect([for (var i = 0; i < 6; i++) once.consume(ready, at(i * 230))], [false, false, false, true, false, false]);
    expect(once.progress, 1);
  });
}
