// The live guidance of the guided camera (the owner, 1 Nov 2026: "let's guide
// the student to take the perfect picture while taking the picture so the
// work is easier for ai"): one instruction at a time, in priority order, held
// long enough to be read, in the same words on the iPhone and on Android.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/guided_scanner/camera_luma.dart';
import 'package:foorsa_student/src/guided_scanner/scan_coach.dart';
import 'package:foorsa_student/src/guided_scanner/scan_document_profile.dart';
import 'package:foorsa_student/src/guided_scanner/scan_frame_loop.dart';
import 'package:foorsa_student/src/guided_scanner/scan_guidance.dart';
import 'package:foorsa_student/src/guided_scanner/scan_text_reading.dart';

import 'support/camera_scene.dart';

GuidedDocumentProfile profile(String key, {String? side}) =>
    GuidedDocumentProfile.fromPortal({'documentKey': key, if (side != null) 'side': side});

const page = Rect.fromLTRB(0.12, 0.1, 0.88, 0.9);
const square = [Offset(0.12, 0.1), Offset(0.88, 0.1), Offset(0.88, 0.9), Offset(0.12, 0.9)];

/// A page found with the given hint, at [corners] (a square page by default).
ScanFrameAnalysis frame(ScanHint hint, {List<Offset> corners = square, bool shadow = false, bool found = true}) =>
    ScanFrameAnalysis(
      hint: hint, bounds: found ? page : null, edgeSupport: found ? 1 : 0, motion: 2,
      brightness: 180, sharpness: 400, contrast: 120, corners: found ? corners : null, shadow: shadow,
    );

/// A page held under a phone tilted towards it: its far (top) edge short.
const slanted = [Offset(0.27, 0.12), Offset(0.73, 0.12), Offset(0.9, 0.88), Offset(0.1, 0.88)];

String title(ScanGuidance guidance) => guidance.copy.title;

void main() {
  final transcript = profile('transcript');
  final passport = profile('identity');

  group('one instruction, in priority order', () {
    ScanGuidance guide(ScanFrameAnalysis? analysis, {ScanTextGateStatus? reading, GuidedDocumentProfile? of,
            bool textPage = false}) =>
        scanGuidanceFor(analysis, reading, profile: of ?? transcript, aspect: 0.75, textPage: textPage);

    test('first the page: found, whole, close enough, the right shape, sharp', () {
      expect(guide(null).copy, const ScanTextCopy('Find the page', 'Fit the whole page in view.', 'Whole page in view.'));
      expect(guide(null).state, ScanOutlineState.searching);
      expect(guide(frame(ScanHint.position, found: false)).state, ScanOutlineState.searching);
      expect(title(guide(frame(ScanHint.moveBack, found: false))), 'Move back a little');
      expect(guide(frame(ScanHint.moveBack, found: false)).copy.detail, 'Keep all four corners in view.');
      expect(title(guide(frame(ScanHint.moveCloser, found: false))), 'Move closer');
      expect(title(guide(frame(ScanHint.position))), 'Show all four corners');
      expect(title(guide(frame(ScanHint.focus))), 'Hold still');
      expect(guide(frame(ScanHint.holdSteady)).copy.detail, 'Keep the phone steady.');
      for (final hint in [ScanHint.moveBack, ScanHint.moveCloser, ScanHint.position, ScanHint.focus]) {
        expect(guide(frame(hint)).state, ScanOutlineState.adjusting, reason: '$hint');
      }
    });

    test('a passport asks for its photo page and its two lines, a card for the side the step asks for', () {
      expect(guide(null, of: passport).copy.detail, 'Show the photo page with the two lines at the bottom.');
      expect(title(guide(frame(ScanHint.position), of: passport)), 'Open the passport flat');
      expect(title(guide(null, of: profile('parent_id', side: 'front'))), 'Front side');
      expect(title(guide(null, of: profile('parent_id', side: 'back'))), 'Now the back');
      expect(title(guide(null, of: profile('parent_id'))), 'Find the card');
    });

    test('then the phone held flat above the page, before anything about the light', () {
      final tilted = guide(frame(ScanHint.brighten, corners: slanted));
      expect(tilted.copy, const ScanTextCopy('Hold the phone flat', 'Keep it level above the page.', 'Hold it flat.'));
      expect(tilted.state, ScanOutlineState.adjusting);
      // A page turned on the desk is held flat: only the phone's slant is asked about.
      List<Offset> turn(List<Offset> corners, double degrees, double aspect) {
        final angle = degrees * math.pi / 180, c = const Offset(0.5, 0.5);
        return [
          for (final p in corners)
            Offset(c.dx + ((p.dx - c.dx) * aspect * math.cos(angle) - (p.dy - c.dy) * math.sin(angle)) / aspect,
                c.dy + (p.dx - c.dx) * aspect * math.sin(angle) + (p.dy - c.dy) * math.cos(angle)),
        ];
      }
      const small = [Offset(0.3, 0.3), Offset(0.7, 0.3), Offset(0.7, 0.7), Offset(0.3, 0.7)];
      final turned = turn(small, 25, 0.75);
      expect(scanPageHeldFlat(square, 0.75), isTrue);
      expect(scanPageHeldFlat(slanted, 0.75), isFalse);
      expect(scanPageHeldFlat(null, 0.75), isTrue);
      expect(scanPageHeldFlat(turned, 0.75), isTrue, reason: '$turned');
    });

    test('then the light: too dark, glare, shadow', () {
      expect(guide(frame(ScanHint.brighten)).copy, const ScanTextCopy('Too dark', 'Move to a brighter place.', 'More light.'));
      expect(guide(frame(ScanHint.reduceGlare)).copy, const ScanTextCopy('Glare on the page', 'Tilt the phone slightly.', 'Tilt slightly.'));
      expect(guide(frame(ScanHint.ready, shadow: true)).copy,
          const ScanTextCopy('Shadow on the page', 'Move your hand or the phone.', 'Avoid the shadow.'));
    });

    test('then what the reading still needs, then holding still for the photo', () {
      final good = frame(ScanHint.ready);
      expect(guide(good, of: passport, reading: const ScanTextGateStatus.waiting(ScanTextGuidance.showMachineLines)).copy,
          ScanTextGuidance.showMachineLines.copy(ScanPaperKind.passport));
      final reading = guide(good, reading: const ScanTextGateStatus.waiting(ScanTextGuidance.reading));
      expect(reading.copy.detail, 'Reading the page…');
      expect(reading.state, ScanOutlineState.holding);
      final taking = guide(good, reading: ScanTextGateStatus.passedReading);
      expect(taking.copy, const ScanTextCopy('Hold still', 'Taking the photo.', 'Taking the photo.'));
      expect(taking.state, ScanOutlineState.holding);
      expect(guide(good).copy, taking.copy);
      // A page found by its text alone is in view.
      expect(guide(frame(ScanHint.position, found: false), reading: ScanTextGateStatus.passedReading, textPage: true).state,
          ScanOutlineState.holding);
    });

    test('the page and the light come before the reading, however sure the reading is', () {
      const wrong = ScanTextGateStatus.waiting(ScanTextGuidance.differentPaper);
      expect(title(guide(frame(ScanHint.moveBack, found: false), reading: wrong)), 'Move back a little');
      expect(title(guide(frame(ScanHint.ready, corners: slanted), reading: wrong)), 'Hold the phone flat');
      expect(title(guide(frame(ScanHint.reduceGlare), reading: wrong)), 'Glare on the page');
      expect(title(guide(frame(ScanHint.ready), reading: wrong)), 'This looks like a different paper');
    });

    test('every line is short enough for a phone held in one hand', () {
      for (final layout in GuidedScanLayout.values) {
        for (final side in [null, 'front', 'back']) {
          for (final framing in ScanFraming.values) {
            for (final lighting in ScanLighting.values) {
              for (final flat in [true, false]) {
                final copy = scanLiveGuidance(framing: framing, lighting: lighting, layout: layout, side: side, flat: flat);
                expect(copy.title.length, inInclusiveRange(1, 26), reason: copy.title);
                expect(copy.detail.length, inInclusiveRange(1, 64), reason: copy.detail);
                expect(copy.compact.length, inInclusiveRange(1, 22), reason: copy.compact);
              }
            }
          }
        }
      }
    });
  });

  group('held long enough to be read', () {
    final t0 = DateTime(2026, 11, 1, 10);
    DateTime at(int ms) => t0.add(Duration(milliseconds: ms));
    const find = ScanGuidance(ScanTextCopy('Find the page', 'Fit the whole page in view.', 'Whole page in view.'),
        ScanOutlineState.searching);
    const closer = ScanGuidance(ScanTextCopy('Move closer', 'Let the page fill more of the view.', 'Move closer.'),
        ScanOutlineState.adjusting);
    const reading = ScanGuidance(ScanTextCopy('Hold still', 'Reading the page…', 'Reading…'), ScanOutlineState.holding);
    const taking = ScanGuidance(scanTakingPhoto, ScanOutlineState.holding);

    test('the first line shows at once and is said', () {
      final coach = ScanGuidanceCoach();
      final first = coach.update(find, at(0));
      expect([first.line, first.changed, first.announce], [find, true, true]);
    });

    test('a new line waits until it has lasted, and the last has been read', () {
      final coach = ScanGuidanceCoach()..update(find, at(0));
      // Asked for since 300 ms: not yet settled.
      expect(coach.update(closer, at(300)).line, find);
      expect(coach.update(closer, at(600)).line, find);
      // Settled, but "Find the page" has not had its second.
      expect(coach.update(closer, at(900)).line, find);
      final shown = coach.update(closer, at(1000));
      expect([shown.line, shown.changed, shown.announce], [closer, true, true]);
    });

    test('a page at the edge of two states does not make the words flicker', () {
      final coach = ScanGuidanceCoach()..update(find, at(0));
      for (var ms = 250; ms <= 5000; ms += 250) {
        final asked = ms % 500 == 0 ? find : closer;
        expect(coach.update(asked, at(ms)).line, find, reason: '$ms ms');
      }
    });

    test('a new line is said once, and only when its words are new', () {
      final coach = ScanGuidanceCoach()..update(reading, at(0));
      coach.update(taking, at(400));
      final next = coach.update(taking, at(1000));
      expect(next.changed, isTrue);
      // "Hold still" again: not said twice.
      expect(next.announce, isFalse);
      expect(coach.update(taking, at(1500)).changed, isFalse);
    });

    test('the photo being taken, and "Got it", show at once', () {
      final coach = ScanGuidanceCoach()..update(find, at(0));
      expect(coach.update(taking, at(100), immediate: true).line, taking);
      final done = coach.update(scanGuidanceDone, at(150));
      expect([done.line, done.announce], [scanGuidanceDone, true]);
      expect(scanGuidanceDone.copy, const ScanTextCopy('Got it', 'Preparing your page.', 'Got it.'));
      coach.reset();
      expect(coach.shown, isNull);
    });
  });

  group('a shadow on the page', () {
    ScanFrameAnalysis analyse(CameraScene scene) {
      final frames = SensorFrames(scene, viewportAspect: 0.75, sensorWidth: 1440, sensorHeight: 1080);
      final grid = sampleScanLuma(frames.nextPlane(), viewportAspect: 0.75)!;
      return const ScanFrameAnalyzer().analyse(grid, GuidedDocumentKind.page, profile: transcript, viewportAspect: 0.75);
    }

    final guide = transcript.guide(0.75);

    test('is seen when a hand or the phone darkens a part of it', () {
      final shaded = analyse(CameraScene(page: guide, shade: const Rect.fromLTRB(0, 0, 0.42, 0.62)));
      expect(shaded.bounds, isNotNull);
      expect(shaded.shadow, isTrue);
      expect(scanLightingOf(shaded), ScanLighting.shadow);
    });

    test('is not an evenly lit page, a page held at a slant on a dark desk, or dark print', () {
      expect(analyse(CameraScene(page: guide)).shadow, isFalse);
      final turned = analyse(CameraScene(page: Rect.fromCenter(center: const Offset(0.5, 0.5), width: 0.62,
          height: 0.62 * 0.75 / 0.707), tiltDegrees: 12));
      expect(turned.bounds, isNotNull);
      expect(turned.shadow, isFalse);
      // A navy band across the top of an even page is print, not shadow.
      final grid = ScanLumaGrid(120, 160, Uint8List.fromList([
        for (var y = 0; y < 160; y++)
          for (var x = 0; x < 120; x++)
            x < 12 || x >= 108 || y < 12 || y >= 148 ? 50 : (y < 52 ? 32 : (x + y).isEven ? 222 : 214),
      ]));
      final corners = [const Offset(12, 12), const Offset(108, 12), const Offset(108, 148), const Offset(12, 148)];
      expect(ScanFrameAnalyzer.shadowOn(grid, corners), isFalse);
      // The same band at half the paper's light reads as a shadow.
      final grey = ScanLumaGrid(120, 160, Uint8List.fromList([
        for (final v in grid.pixels) v == 32 ? 110 : v,
      ]));
      expect(ScanFrameAnalyzer.shadowOn(grey, corners), isTrue);
    });

    test('gets a moment to be fixed before the page is taken anyway', () {
      final loop = GuidedFrameLoop(transcript, canReadText: false);
      final t0 = DateTime(2026, 11, 1, 10);
      var takenAt = -1;
      for (var ms = 0; ms <= 4000 && takenAt < 0; ms += 250) {
        if (loop.observe(frame(ScanHint.ready, shadow: true), t0.add(Duration(milliseconds: ms)), aspect: 0.75)) {
          takenAt = ms;
        }
      }
      // Steady from 750 ms (four frames over 650 ms), then the lighting's grace.
      expect(takenAt, greaterThanOrEqualTo(1500));
      expect(takenAt, lessThanOrEqualTo(ScanAutoShutter.inViewLimit(ScanPaperKind.paper).inMilliseconds));
      final even = GuidedFrameLoop(transcript, canReadText: false);
      var evenAt = -1;
      for (var ms = 0; ms <= 4000 && evenAt < 0; ms += 250) {
        if (even.observe(frame(ScanHint.ready), t0.add(Duration(milliseconds: ms)), aspect: 0.75)) evenAt = ms;
      }
      expect(evenAt, lessThan(takenAt));
    });

    test('and so does a phone held at a slant', () {
      final loop = GuidedFrameLoop(transcript, canReadText: false);
      final even = GuidedFrameLoop(transcript, canReadText: false);
      final t0 = DateTime(2026, 11, 1, 10);
      int when(GuidedFrameLoop loop, ScanFrameAnalysis analysis) {
        for (var ms = 0; ms <= 4000; ms += 250) {
          if (loop.observe(analysis, t0.add(Duration(milliseconds: ms)), aspect: 0.75)) return ms;
        }
        return -1;
      }
      expect(when(loop, frame(ScanHint.ready, corners: slanted)), greaterThan(when(even, frame(ScanHint.ready))));
    });
  });

  // The words are the iPhone's (ScannerGeometry.swift, ScannerTextReading.swift), and these hold
  // each string of one to the other, in the same order, so neither platform can drift alone.
  group('the same words on the iPhone and on Android', () {
    List<String> literals(String source, RegExp pattern) => [
          for (final line in source.split('\n'))
            if (!line.trimLeft().startsWith('//') && !line.trimLeft().startsWith('///'))
              for (final match in pattern.allMatches(line)) match.group(1)!,
        ];
    final dartString = RegExp(r"'((?:[^'\\]|\\.)*)'");
    final swiftString = RegExp(r'"((?:[^"\\]|\\.)*)"');

    /// The text after [start] up to [end] (to the end of [source] without one).
    String block(String source, String start, [String? end]) {
      final from = source.indexOf(start);
      expect(from, isNonNegative, reason: 'missing $start');
      if (end == null) return source.substring(from + start.length);
      final to = source.indexOf(end, from + start.length);
      expect(to, greaterThan(from), reason: 'missing the end of $start');
      return source.substring(from + start.length, to);
    }

    final dartCoach = File('lib/src/guided_scanner/scan_coach.dart').readAsStringSync();
    final swiftGeometry = File('ios/Runner/ScannerGeometry.swift').readAsStringSync();
    final dartReading = File('lib/src/guided_scanner/scan_text_reading.dart').readAsStringSync();
    final swiftReading = File('ios/Runner/ScannerTextReading.swift').readAsStringSync();

    test('the live guidance, line for line', () {
      final android = literals(block(dartCoach, 'ScanTextCopy scanLiveGuidance({', '\n}\n'), dartString);
      final iphone = literals(
          block(swiftGeometry, 'enum ScannerLiveGuidance {', '  /// The calm word once the camera has the photos.'),
          swiftString);
      expect(android, isNotEmpty);
      expect(android, iphone);
      expect(literals(block(dartCoach, 'const scanGotIt = ', ';'), dartString),
          literals(block(swiftGeometry, 'static let gotIt = ', '\n'), swiftString));
    });

    test('what the reading still needs, for every paper', () {
      // The English table (the French and Arabic follow it in the same file).
      final android = block(dartReading, '  ScanTextCopy _english(ScanPaperKind kind) => switch (this) {', '\n      };\n');
      final iphone = block(swiftReading, '  func copy(for kind: ScannerPaperKind) -> ScannerGuidanceCopy {', '\n  }\n}\n');
      // Case by case: the same words for the same guidance.
      for (final guidance in ScanTextGuidance.values) {
        final name = guidance.name;
        final next = ScanTextGuidance.values.indexOf(guidance) + 1 < ScanTextGuidance.values.length
            ? ScanTextGuidance.values[ScanTextGuidance.values.indexOf(guidance) + 1].name : null;
        final androidCase = block(android, 'ScanTextGuidance.$name =>', next == null ? null : 'ScanTextGuidance.$next =>');
        final iphoneCase = block(iphone, 'case .$name:', next == null ? null : 'case .$next:');
        expect(literals(androidCase, dartString)..sort(), literals(iphoneCase, swiftString)..sort(), reason: name);
      }
    });

    test('the same rule for a phone held flat, and the same hold on the words', () {
      expect(swiftGeometry, contains('func isHeldFlat(in imageSize: CGSize) -> Bool'));
      final swiftFlat = block(swiftGeometry, 'func isHeldFlat(in imageSize: CGSize) -> Bool {', '\n  }\n');
      final dartFlat = block(dartCoach, 'bool scanPageHeldFlat(', '\n}\n');
      for (final number in ['0.82', '72', '108']) {
        expect(swiftFlat, contains(number));
        expect(dartFlat, contains(number));
      }
      expect(swiftGeometry, contains('static let minimumDisplay: TimeInterval = 1.0'));
      expect(swiftGeometry, contains('static let settle: TimeInterval = 0.35'));
      expect(ScanGuidanceCoach.minimumDisplay, const Duration(seconds: 1));
      expect(ScanGuidanceCoach.settle, const Duration(milliseconds: 350));
    });
  });
}
