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
    test('detects document-specific ${key} frame without exact placement', () {
      final p = profile(key);
      final guide = p.guide(previewAspect);
      final frame = simulatedDocument(guide, dx: 5, dy: -5);
      final result = analyzer.analyse(
        frame, GuidedDocumentKind.page,
        previous: frame, profile: p, viewportAspect: previewAspect,
      );
      expect(result.hint, ScanHint.ready,
        reason: 'Recognize shifted ${key} without a rigid exact-fit rectangle');
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

  test('card-shaped region cannot be a tiny portrait document', () {
    final p = profile('parent_id');
    expect(p.supportsRatio(0.75), isFalse);
    final target = profile('medical_check').guide(previewAspect);
    final image = simulatedDocument(target);
    final report = analyzer.analyse(
      image, GuidedDocumentKind.idCard, previous: image,
      profile: p, viewportAspect: previewAspect,
    );
    expect(report.autoReady, isFalse);
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
