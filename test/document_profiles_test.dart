import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/guided_scanner/scan_document_profile.dart';
import 'package:foorsa_student/src/guided_scanner/scan_guidance.dart';

const previewAspect = 0.5;

GuidedDocumentProfile profile(String key, {String? hint}) =>
  GuidedDocumentProfile.fromPortal({
    'v': 1,
    'documentKey': key,
    'title': 'Scan ${key.replaceAll('_', ' ')}',
    'instruction': hint ?? 'Include every printed edge and all critical details.',
    'zones': key == 'identity'
      ? ['passport_photo', 'passport_mrz']
      : ['entire_page'],
    'pages': key == 'medical_check' ? 'two_page_form' : 'multiple',
  });

ScanLumaGrid simulatedDocument(
  Rect normalized, {
  int dx = 0,
  int dy = 0,
  bool printing = true,
}) {
  const w = 120, h = 160;
  final left = (normalized.left * w).round() + dx;
  final right = (normalized.right * w).round() + dx;
  final top = (normalized.top * h).round() + dy;
  final bottom = (normalized.bottom * h).round() + dy;
  final pixels = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final inside = x >= left && x <= right && y >= top && y <= bottom;
      final textLine = printing && inside
        && x > left + 7 && x < right - 7
        && y > top + 6 && y < bottom - 6
        && (y - top) % 8 < 2;
      pixels[y * w + x] = inside ? (textLine ? 24 : 237) : 24;
    }
  }
  return ScanLumaGrid(w, h, pixels);
}

void main() {
  const analyzer = ScanFrameAnalyzer();

  test('each document knows its relevant frame and major details', () {
    final passport = profile('identity');
    expect(passport.layout, GuidedScanLayout.passport);
    expect(passport.zones, containsAll(['passport_photo','passport_mrz']));
    expect(passport.guide(previewAspect).width, greaterThan(0.8));

    final parent = profile('parent_id');
    expect(parent.layout, GuidedScanLayout.card);
    expect(parent.supportsRatio(1.59), isTrue);

    final transcript = profile('transcript');
    expect(transcript.layout, GuidedScanLayout.adaptive);
    expect(transcript.candidateGuides(previewAspect), hasLength(2));

    final medical = profile('medical_check');
    expect(medical.pagesHint, contains('page 2'));

    final unknown = profile('foorsa_unrecognized_document');
    expect(unknown.documentKey, 'drive_files');
    expect(unknown.layout, GuidedScanLayout.adaptive);
  });

  test('rejects attempts to override known document shapes with an arbitrary payload', () {
    final request = GuidedDocumentProfile.fromPortal({
      'documentKey': 'identity',
      'layout': 'adaptive',
      'instruction': 'Safe frame guidance',
      'title': 'Passport',
      'zones': ['evil', 'passport_mrz', 'passport_photo'],
      'pages': 'one',
    });
    expect(request.layout, GuidedScanLayout.passport);
    expect(request.zones, ['passport_mrz','passport_photo']);
  });

  for (final key in ['identity','parent_id','medical_check','transcript','highest_degree']) {
    test('detects document-specific $key frame without exact placement', () {
      final p = profile(key);
      final guide = p.guide(previewAspect);
      final frame = simulatedDocument(guide, dx: 5, dy: -5);
      final result = analyzer.analyse(
        frame, GuidedDocumentKind.page,
        previous: frame, profile: p, viewportAspect: previewAspect,
      );
      expect(result.hint, ScanHint.ready,
        reason: 'Recognize shifted $key without a rigid exact-fit rectangle');
      expect(result.bounds, isNotNull);
      expect(result.bounds!.left, isNot(closeTo(guide.left, 0.001)));
    });
  }

  test('adaptive diploma accepts a horizontal form instead of rigid A4', () {
    final p = profile('highest_degree');
    final guide = p.candidateGuides(previewAspect)[1];
    final image = simulatedDocument(guide);
    final report = analyzer.analyse(
      image, GuidedDocumentKind.page, previous: image,
      profile: p, viewportAspect: previewAspect,
    );
    expect(report.autoReady, isTrue);
  });

  test('card profile accepts either rotation but rejects a square', () {
    final p = profile('parent_id');
    expect(p.supportsRatio(1.585), isTrue);
    expect(p.supportsRatio(1 / 1.585), isTrue);
    expect(p.supportsRatio(1.0), isFalse);
    expect(p.acceptsPortrait, isTrue);
    final target = p.candidateGuides(previewAspect)[1];
    final image = simulatedDocument(target);
    final report = analyzer.analyse(
      image, GuidedDocumentKind.idCard, previous: image,
      profile: p, viewportAspect: previewAspect,
    );
    expect(report.autoReady, isTrue);
  });

  test('passport data page and open spread work in both camera rotations', () {
    final p = profile('identity');
    expect(p.candidateGuides(previewAspect), hasLength(2));
    for (final ratio in [125 / 88, 88 / 125, 125 / 176, 176 / 125]) {
      expect(p.supportsRatio(ratio), isTrue, reason: 'passport ratio $ratio');
    }
    for (final guide in p.candidateGuides(previewAspect)) {
      final image = simulatedDocument(guide);
      final report = analyzer.analyse(
        image, GuidedDocumentKind.passport, previous: image,
        profile: p, viewportAspect: previewAspect,
      );
      expect(report.autoReady, isTrue);
    }
  });

  test('landscape letters and elongated receipts use their own shape rules', () {
    final letter = profile('recommendation_letter');
    expect(letter.supportsRatio(1.41), isTrue);
    expect(letter.candidateGuides(previewAspect), hasLength(2));
    final letterImage = simulatedDocument(letter.candidateGuides(previewAspect)[1]);
    expect(analyzer.analyse(
      letterImage, GuidedDocumentKind.page, previous: letterImage,
      profile: letter, viewportAspect: previewAspect,
    ).autoReady, isTrue);

    final receipt = profile('receipts');
    expect(receipt.candidateGuides(previewAspect), hasLength(4));
    for (final ratio in [3.0, 1 / 3.0]) {
      expect(receipt.supportsRatio(ratio), isTrue);
      expect(profile('identity').supportsRatio(ratio), isFalse);
      expect(profile('transcript').supportsRatio(ratio), isFalse);
    }
    expect(receipt.supportsRatio(3.5), isFalse);
    expect(profile('totally-unknown').supportsRatio(3.0), isFalse);
    final tallReceipt = receipt.candidateGuides(previewAspect)[2];
    final image = simulatedDocument(tallReceipt);
    expect(analyzer.analyse(
      image, GuidedDocumentKind.page, previous: image,
      profile: receipt, viewportAspect: previewAspect,
    ).autoReady, isTrue);
  });

  test('invalid shape values and forged layouts fail safely', () {
    final p = profile('parent_id');
    for (final ratio in [0.0, -1.0, double.nan, double.infinity,
      double.negativeInfinity]) {
      expect(p.supportsRatio(ratio), isFalse);
    }
    final unknown = GuidedDocumentProfile.fromPortal({
      'documentKey': 'forged_passport', 'layout': 'passport',
    });
    expect(unknown.documentKey, 'drive_files');
    expect(unknown.layout, GuidedScanLayout.adaptive);
  });

  test('blurry unprinted region cannot trigger automatic shutter', () {
    final p = profile('identity');
    final image = simulatedDocument(p.guide(previewAspect), printing: false);
    final report = analyzer.analyse(
      image, GuidedDocumentKind.passport,
      previous: image, profile: p, viewportAspect: previewAspect,
    );
    expect(report.autoReady, isFalse);
  });

  test('unknown profile or malformed images fail safely', () {
    final p = profile('totally-unknown');
    final report = analyzer.analyse(
      ScanLumaGrid(120,160,Uint8List(20)),
      GuidedDocumentKind.page, profile:p, viewportAspect:previewAspect,
    );
    expect(report.autoReady, isFalse);
  });
}
