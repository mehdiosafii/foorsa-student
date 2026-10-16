/// Foorsa document-aware camera guidance.
///
/// The portal sends a small capture profile based on its actual document
/// requirements. This native allowlist is the safe, offline fallback when the
/// portal is old: no personal details, OCR data or uploaded bytes are required
/// to select the frame.
library;

import 'dart:ui';

enum GuidedScanLayout { passport, card, portrait, adaptive }

const _allowedZones = <String>{
  'passport_photo', 'passport_mrz', 'holder_identity',
  'grades_table', 'signature_stamp', 'dates',
  'letterhead', 'account_balance', 'medical_fields', 'entire_page',
};

const _folderLayouts = <String, GuidedScanLayout>{
  'identity': GuidedScanLayout.passport,
  'parent_id': GuidedScanLayout.card,
  'highest_degree': GuidedScanLayout.adaptive,
  'last_year_degree': GuidedScanLayout.adaptive,
  'transcript': GuidedScanLayout.adaptive,
  'last_year_transcript': GuidedScanLayout.adaptive,
  'medical_check': GuidedScanLayout.portrait,
  'criminal_record': GuidedScanLayout.adaptive,
  'bank_statement': GuidedScanLayout.adaptive,
  'english_test': GuidedScanLayout.adaptive,
  'recommendation_letter': GuidedScanLayout.portrait,
  'study_plan': GuidedScanLayout.portrait,
  'research_proposal': GuidedScanLayout.portrait,
  'cv': GuidedScanLayout.portrait,
  'birth_certificate': GuidedScanLayout.adaptive,
  'contract': GuidedScanLayout.portrait,
  'receipts': GuidedScanLayout.adaptive,
  'admissions': GuidedScanLayout.adaptive,
  'universities_notices': GuidedScanLayout.adaptive,
  'visa_documents': GuidedScanLayout.adaptive,
  'application_form': GuidedScanLayout.portrait,
  'authorizations': GuidedScanLayout.portrait,
  'introduction_video': GuidedScanLayout.portrait,
  'csca': GuidedScanLayout.adaptive,
  'previous_chinese_universities': GuidedScanLayout.adaptive,
  'publications': GuidedScanLayout.portrait,
  'supervisor_acceptance': GuidedScanLayout.adaptive,
  'drive_files': GuidedScanLayout.adaptive,
};

class GuidedDocumentProfile {
  const GuidedDocumentProfile({
    required this.documentKey,
    required this.title,
    required this.instruction,
    required this.layout,
    required this.zones,
    required this.pages,
  });

  final String documentKey;
  final String title;
  final String instruction;
  final GuidedScanLayout layout;
  final List<String> zones;
  final String pages;

  /// Small, non-sensitive hints for the native camera. Native code still
  /// validates every value and falls back to a general page guide.
  Map<String, Object> toNativeRequest() => {
    'documentKey': documentKey,
    'title': title,
    'instruction': instruction,
    'layout': layout.name,
    'pages': pages,
  };

  bool get acceptsLandscape =>
      layout == GuidedScanLayout.adaptive ||
      layout == GuidedScanLayout.card ||
      layout == GuidedScanLayout.passport;

  bool get acceptsPortrait =>
      layout == GuidedScanLayout.adaptive ||
      layout == GuidedScanLayout.portrait;

  /// These are deliberately wide: the guide suggests positioning but must
  /// not reject different Moroccan documents or Chinese university forms.
  List<double> get expectedAspectRatios => switch (layout) {
    GuidedScanLayout.passport => [1.42],
    GuidedScanLayout.card => [1.585],
    GuidedScanLayout.portrait => [0.71],
    GuidedScanLayout.adaptive => [0.71, 1.42],
  };

  static GuidedDocumentProfile fromPortal(Object? request) {
    if (request is GuidedDocumentProfile) return request;
    Map<dynamic, dynamic>? details;
    var key = '';
    if (request is Map) {
      details = request;
      key = (request['documentKey'] ?? '').toString().trim().toLowerCase();
    } else if (request is String) {
      key = request.trim().toLowerCase();
      key = switch (key) {
        'passport' => 'identity',
        'id_card' => 'parent_id',
        'page' => 'drive_files',
        _ => key,
      };
    }
    // Unknown/unsupported types are generic, never guessed to be passports.
    if (!_folderLayouts.containsKey(key)) key = 'drive_files';
    final layout = _folderLayouts[key]!;
    final title = _safeLabel(details?['title'], 70) ??
      (key == 'identity' ? 'Passport'
        : key == 'parent_id' ? 'Parent ID card' : 'document');
    final instruction = _safeLabel(details?['instruction'], 200) ??
      (key == 'identity'
        ? 'Include the portrait and both machine-readable lines.'
        : key == 'parent_id'
          ? 'Include every corner and both sides if requested.'
          : 'Keep all printed details, stamps and signatures visible.');
    final fallbackZones = key == 'identity'
      ? ['passport_photo', 'passport_mrz']
      : key == 'parent_id'
        ? ['holder_identity']
        : ['entire_page'];
    var zones = fallbackZones;
    final suppliedZones = details?['zones'];
    if (suppliedZones is List) {
      final validZones = suppliedZones.whereType<String>()
        .where(_allowedZones.contains).take(8).toList();
      if (validZones.isNotEmpty) zones = validZones;
    }
    final requestedPages = details?['pages']?.toString();
    final pages = ['one', 'multiple', 'two_page_form'].contains(requestedPages)
      ? requestedPages!
      : key == 'medical_check' ? 'two_page_form' : 'one';

    return GuidedDocumentProfile(
      documentKey: key, title: title,
      instruction: instruction, layout: layout,
      zones: List.unmodifiable(zones), pages: pages,
    );
  }

  static String? _safeLabel(Object? source, int maximum) {
    if (source is! String) return null;
    final text = source.trim();
    return text.isNotEmpty && text.length <= maximum &&
      !text.contains('\n') && !text.contains('\r') ? text : null;
  }

  /// The camera crop is normalized to the visible preview. A document's
  /// physical aspect ratio is converted using the viewport's real aspect
  /// ratio; screen pixel dimensions are never assumed to be 9:19.
  Rect _guideForAspect(double ratio, double viewportAspect) {
    final safeAspect = viewportAspect > 0.25 && viewportAspect < 1.3
      ? viewportAspect : 0.5;
    var width = ratio > 1 ? 0.83 : 0.75;
    var height = width * safeAspect / ratio;
    if (height > 0.57) {
      width *= 0.57 / height;
      height = 0.57;
    }
    return Rect.fromCenter(
      center: const Offset(0.5, 0.47),
      width: width, height: height,
    );
  }

  Rect guide(double viewportAspect) =>
    _guideForAspect(expectedAspectRatios.first, viewportAspect);

  /// Flexible documents can be photographed in portrait OR landscape
  /// depending on how a university actually issues them.
  List<Rect> candidateGuides(double viewportAspect) =>
    expectedAspectRatios.map((ratio) =>
      _guideForAspect(ratio, viewportAspect)).toList(growable: false);

  /// A legitimate diploma might be A4 portrait or landscape, a bank balance
  /// certificate may be a small horizontal paper. Do not require exact size.
  bool supportsRatio(double ratio) {
    if (ratio <= 0 || !ratio.isFinite) return false;
    return switch (layout) {
      GuidedScanLayout.passport => ratio >= 1.14 && ratio <= 1.84,
      GuidedScanLayout.card => ratio >= 1.27 && ratio <= 2.00,
      GuidedScanLayout.portrait => ratio >= 0.50 && ratio <= 1.12,
      GuidedScanLayout.adaptive =>
        (ratio >= 0.49 && ratio <= 1.12) ||
        (ratio >= 1.14 && ratio <= 2.10),
    };
  }

  String get pagesHint => switch (pages) {
    'two_page_form' => 'After this photo, add page 2 in the scanner.',
    'multiple' => 'Add any remaining pages in the scanner.',
    _ => '',
  };
}
