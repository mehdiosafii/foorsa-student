import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/guided_scanner/scan_guidance.dart';

ScanLumaGrid preview(
  GuidedDocumentKind kind, {
  bool addText = true,
  int background = 24,
  int paper = 236,
  int ink = 24,
  int dx = 0,
  int dy = 0,
}) {
  const width = 120;
  const height = 160;
  final guide = kind.guide;
  final left = (guide.left * width).round() + dx;
  final right = (guide.right * width).round() + dx;
  final top = (guide.top * height).round() + dy;
  final bottom = (guide.bottom * height).round() + dy;
  final data = Uint8List(width * height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final onPage = x >= left && x <= right && y >= top && y <= bottom;
      final isText = addText && x > left + 7 && x < right - 7
          && y > top + 7 && y < bottom - 7 && (y - top) % 9 < 2;
      data[y * width + x] =
          onPage ? (isText ? ink : paper) : background;
    }
  }
  return ScanLumaGrid(width, height, data);
}

void main() {
  const analyzer = ScanFrameAnalyzer();

  test('uses the appropriate frame for each document type', () {
    expect(GuidedDocumentKindInfo.fromPortal('passport'),
        GuidedDocumentKind.passport);
    expect(GuidedDocumentKindInfo.fromPortal('id_card'),
        GuidedDocumentKind.idCard);
    expect(GuidedDocumentKindInfo.fromPortal('other'),
        GuidedDocumentKind.page);
    expect(GuidedDocumentKind.passport.guide.width,
        greaterThan(GuidedDocumentKind.page.guide.width));
  });

  for (final kind in GuidedDocumentKind.values) {
    test('detects complete, sharply printed ${kind.label} inside guide', () {
      final image = preview(kind);
      final analysis = analyzer.analyse(image, kind, previous: image);
      expect(analysis.hint, ScanHint.ready);
      expect(analysis.bounds, isNotNull);
      expect(analysis.sharpness, greaterThan(24));
      expect(analysis.contrast, greaterThan(32));
    });

    test('does not capture a featureless page for ${kind.label}', () {
      final image = preview(kind, addText: false);
      final analysis = analyzer.analyse(image, kind, previous: image);
      expect(analysis.hint, ScanHint.focus);
      expect(analysis.autoReady, isFalse);
    });
  }

  test('requires visible edges rather than camera quality alone', () {
    final image = ScanLumaGrid(120, 160, Uint8List.fromList(
      List<int>.filled(120 * 160, 220),
    ));
    expect(analyzer.analyse(image, GuidedDocumentKind.page).hint,
        ScanHint.position);
  });

  test('suggests better lighting when paper is nearly dark', () {
    final image = preview(
      GuidedDocumentKind.page, background: 2, paper: 62, ink: 8,
    );
    final analysis = analyzer.analyse(
      image, GuidedDocumentKind.page, previous: image,
    );
    expect(analysis.hint, ScanHint.brighten);
  });

  test('does not auto-fire on the first preview frame', () {
    final image = preview(GuidedDocumentKind.page);
    final analysis = analyzer.analyse(image, GuidedDocumentKind.page);
    expect(analysis.hint, ScanHint.holdSteady);
  });

  test('motion and shifts inhibit auto capture', () {
    final stable = preview(GuidedDocumentKind.page);
    final moved = preview(GuidedDocumentKind.page, dx: 6);
    final analysis = analyzer.analyse(
      moved, GuidedDocumentKind.page, previous: stable,
    );
    expect(analysis.autoReady, isFalse);
  });

  test('requires four stable good frames held over 650 ms', () {
    final gate = ScanAutoCaptureGate();
    final image = preview(GuidedDocumentKind.page);
    final good = analyzer.analyse(
      image, GuidedDocumentKind.page, previous: image,
    );
    final start = DateTime.utc(2026, 10, 16);
    expect(gate.consume(good, start), isFalse);
    expect(gate.consume(good, start.add(const Duration(milliseconds: 230))),
        isFalse);
    expect(gate.consume(good, start.add(const Duration(milliseconds: 460))),
        isFalse);
    expect(gate.consume(good, start.add(const Duration(milliseconds: 690))),
        isTrue);
    expect(gate.consume(good, start.add(const Duration(seconds: 3))), isFalse);
    expect(gate.progress, 1);
  });

  test('a non-ready frame resets the hold timer', () {
    final gate = ScanAutoCaptureGate();
    final image = preview(GuidedDocumentKind.page);
    final good = analyzer.analyse(
      image, GuidedDocumentKind.page, previous: image,
    );
    final bad = analyzer.analyse(image, GuidedDocumentKind.page);
    final start = DateTime.utc(2026, 10, 16);
    expect(gate.consume(good, start), isFalse);
    expect(gate.consume(good, start.add(const Duration(milliseconds: 230))),
        isFalse);
    expect(gate.consume(bad, start.add(const Duration(milliseconds: 460))),
        isFalse);
    expect(gate.progress, 0);
    expect(gate.consume(good, start.add(const Duration(milliseconds: 690))),
        isFalse);
    expect(gate.consume(good, start.add(const Duration(milliseconds: 920))),
        isFalse);
  });

  test('invalid buffer never reports ready', () {
    final image = ScanLumaGrid(120, 160, Uint8List(4));
    expect(image.valid, isFalse);
    expect(analyzer.analyse(image, GuidedDocumentKind.page).autoReady, isFalse);
  });
}
