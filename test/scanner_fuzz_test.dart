import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/guided_scanner/live_text_reader.dart';
import 'package:foorsa_student/src/guided_scanner/scan_document_profile.dart';
import 'package:foorsa_student/src/guided_scanner/scan_text_reading.dart';

// Random and oversized inputs must never throw anywhere in the scanner's
// pure pipeline: whatever the camera, OCR or portal sends.
const _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789<<<<   oIlKé€\u0000\u{1F600}';

String _text(math.Random r, int max) => String.fromCharCodes(List.generate(
    r.nextInt(max + 1), (_) => _alphabet.runes.elementAt(r.nextInt(_alphabet.runes.length))));

double _coord(math.Random r) => switch (r.nextInt(10)) {
      0 => double.nan,
      1 => -r.nextDouble(),
      2 => 1 + r.nextDouble(),
      3 => double.infinity,
      _ => r.nextDouble(),
    };

Object? _junk(math.Random r, [int depth = 0]) => switch (r.nextInt(depth > 2 ? 6 : 8)) {
      0 => null,
      1 => r.nextInt(1 << 31) - (1 << 30),
      2 => r.nextDouble(),
      3 => _text(r, 60),
      4 => r.nextBool(),
      5 => 'TD3',
      6 => [for (var i = 0; i < r.nextInt(5); i++) _junk(r, depth + 1)],
      _ => {for (var i = 0; i < r.nextInt(5); i++) _text(r, 8): _junk(r, depth + 1)},
    };

ScanTextObservation _obs(math.Random r) => ScanTextObservation.turned(
      candidates: [for (var i = 0; i < r.nextInt(5); i++) _text(r, r.nextBool() ? 44 : 300)],
      box: TextBox(_coord(r), _coord(r), _coord(r), _coord(r)),
      quarterTurns: r.nextInt(9) - 4,
    );

void main() {
  test('frame analysis survives random, broken and oversized frames', () {
    final r = math.Random(1);
    for (var i = 0; i < 3000; i++) {
      final frame = ScanTextFrame(
        lines: [for (var j = 0; j < r.nextInt(i % 50 == 0 ? 400 : 30); j++) _obs(r)],
        regions: [for (var j = 0; j < r.nextInt(20); j++) _obs(r)],
        quarterTurns: r.nextInt(11) - 5,
        page: [for (var j = 0; j < r.nextInt(6); j++) math.Point(_coord(r), _coord(r))],
        readingWidth: _coord(r) * 2000,
        readingHeight: _coord(r) * 2000,
      );
      ScanTextFrameAnalysis.summarize(frame);
    }
  });

  test('MRZ validation and fields survive random lines', () {
    final r = math.Random(2);
    for (var i = 0; i < 20000; i++) {
      final format = ScanMrzFormat.values[r.nextInt(2)];
      final lines = [
        for (var j = 0; j < format.lineCount; j++)
          [for (var k = 0; k < format.lineLength; k++) '0123456789ABCDEFMX<'.codeUnitAt(r.nextInt(19))]
      ];
      final result = ScanMrzValidator.validate(lines, format);
      ScanMrzFields.fromResult(result)?.toMap(referenceYear: 2026);
      final votes = ScanMrzVotes(format)..add(lines);
      votes.consensus;
    }
  });

  test('sanitizers and parsers drop junk without throwing', () {
    final r = math.Random(3);
    for (var i = 0; i < 20000; i++) {
      final raw = _junk(r);
      sanitizeLiveReading(raw);
      sanitizeLiveReading({
        'version': 1, 'kind': 'passport', 'engine': 'vision', 'frames': _junk(r),
        'lines': _junk(r), 'mrzFormat': r.nextBool() ? 'TD3' : 'TD1', 'mrz': _junk(r),
        'fields': _junk(r), 'side': _junk(r),
      });
      LiveTextChannel.parse(raw is Map ? raw.cast<String, Object?>() : null);
      LiveTextChannel.parse({'lines': [for (var j = 0; j < 5; j++) {'text': _junk(r), 'left': _junk(r), 'top': 0, 'right': 1, 'bottom': 1}]});
      GuidedDocumentProfile.fromPortal(raw);
      ScanTextFrameAnalysis.clean(_text(r, 500));
    }
  });

  test('a reading session keeps up with a long run of frames', () {
    final r = math.Random(4);
    final watch = Stopwatch()..start();
    for (var i = 0; i < 2000; i++) {
      ScanTextFrameAnalysis.summarize(ScanTextFrame(
        lines: [for (var j = 0; j < 120; j++) _obs(r)],
        quarterTurns: 0,
        page: const [math.Point(0.1, 0.1), math.Point(0.9, 0.1), math.Point(0.9, 0.9), math.Point(0.1, 0.9)],
        readingWidth: 1500,
        readingHeight: 1060,
      ));
    }
    // Live reading runs per camera frame; a worst-case frame must stay cheap.
    expect(watch.elapsedMilliseconds / 2000, lessThan(50));
  });
}
