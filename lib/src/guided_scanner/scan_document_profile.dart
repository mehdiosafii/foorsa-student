/// Foorsa document-aware camera guidance.
///
/// The portal sends a small capture profile based on its actual document
/// requirements. This native allowlist is the safe, offline fallback when the
/// portal is old: no personal details, OCR data or uploaded bytes are required
/// to select the frame.
library;

import 'dart:ui';

import '../app_language.dart';

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
    this.outputMode,
    this.side,
  });

  final String documentKey;
  final String title;
  final String instruction;
  final GuidedScanLayout layout;
  final List<String> zones;
  final String pages;
  final String? outputMode;

  /// The side of a card this capture is for, 'front' or 'back', when the
  /// portal says. Older portals send none, and either side is accepted.
  final String? side;

  /// What the guide draws inside its outline: the portal's zones, and for a
  /// card the side this capture asks for (the owner, 2 Nov 2026: "id don't
  /// have framing like passport does meanwhile both needs so"): its photo on
  /// the front, its three machine-readable lines on the back. Hints only, as
  /// the passport's are.
  List<String> get guideZones => layout != GuidedScanLayout.card
      ? zones
      : [...zones, side == 'back' ? 'card_mrz' : 'card_photo'];

  /// Small, non-sensitive hints for the native camera. Native code still
  /// validates every value and falls back to a general page guide.
  Map<String, Object> toNativeRequest() => {
    'documentKey': documentKey,
    'title': title,
    'instruction': instruction,
    'layout': layout.name,
    'pages': pages,
    if (outputMode == 'imagegen') 'outputMode': 'imagegen',
    if (side != null) 'side': side!,
  };

  bool get acceptsLandscape => true;

  bool get acceptsPortrait => true;

  /// These are deliberately wide: the guide suggests positioning but must
  /// not reject different Moroccan documents or Chinese university forms.
  ///
  /// A passport is asked for open at its photo page, both pages in one photo
  /// (the owner, 1 Nov 2026: the page facing the photo page carries the
  /// passport number), so the guide drawn first is the open booklet held
  /// upright: two pages one above the other, 125 by 176 mm. Until then the
  /// guide was the photo page alone, and the portal's guide and the camera's
  /// frame asked for two different shots. The photo page alone, or the
  /// booklet turned on the desk, is 1.42 and is still found.
  List<double> get expectedAspectRatios => documentKey == 'receipts'
    ? [0.71, 1.42, 0.35, 2.85]
    : switch (layout) {
      GuidedScanLayout.passport => [0.71, 1.42],
      GuidedScanLayout.card => [1.585, 0.63],
      GuidedScanLayout.portrait => [0.71, 1.42],
      GuidedScanLayout.adaptive => [0.71, 1.42],
    };

  /// The profile the portal asked for. What the portal does not say is said
  /// in [language].
  static GuidedDocumentProfile fromPortal(Object? request,
      [AppLanguage language = AppLanguage.en]) {
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
      (key == 'identity' ? _passport
        : key == 'parent_id' ? _parentCard : _document).of(language);
    final instruction = _safeLabel(details?['instruction'], 200) ??
      (key == 'identity'
        ? _passportHow
        : key == 'parent_id'
          ? _parentCardHow
          : _documentHow).of(language);
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
    final side = details?['side'];
    final requestedSide = side is String ? side.trim().toLowerCase() : null;

    return GuidedDocumentProfile(
      documentKey: key, title: title,
      instruction: instruction, layout: layout,
      zones: List.unmodifiable(zones), pages: pages,
      outputMode: details?['outputMode'] == 'imagegen' ? 'imagegen' : null,
      side: requestedSide == 'front' || requestedSide == 'back'
        ? requestedSide : null,
    );
  }

  static const _passport = Words('Passport', 'Passeport', 'جواز السفر');
  static const _parentCard = Words('Parent ID card',
      'Carte d’identité du parent', 'بطاقة تعريف أحد الوالدين');
  static const _document = Words('document', 'document', 'وثيقة');
  static const _passportHow = Words(
      'Open it at the photo page: both pages, the two lines at the bottom too.',
      'Ouvrez-le à la page photo : les deux pages, avec les deux lignes du bas.',
      'افتحه على صفحة الصورة: الصفحتان معًا، مع السطرين في الأسفل.');
  static const _parentCardHow = Words(
      'Include every corner and both sides if requested.',
      'Incluez chaque coin, et les deux faces si elles sont demandées.',
      'أظهر كل الزوايا، والوجهين إذا طُلب ذلك.');
  static const _documentHow = Words(
      'Keep all printed details, stamps and signatures visible.',
      'Gardez visibles tous les détails imprimés, les cachets et les '
          'signatures.',
      'اجعل كل البيانات المطبوعة والأختام والتوقيعات ظاهرة.');

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
    // The open passport is as wide as its photo page, and its two lines must
    // stay as large as they were in the photo page's guide to be read live:
    // it takes as much of the width as the height allows.
    var width = ratio > 1 ? 0.83
      : layout == GuidedScanLayout.passport ? 0.86 : 0.75;
    var height = width * safeAspect / ratio;
    // A tall viewport (a preview covering the whole screen) keeps the guide
    // to 57% of its height. A wider one (the 3:4 photo shown whole on
    // Android, since 31 Oct 2026) lets a portrait page take its full width,
    // so it lands on as many of the camera's pixels as it can.
    final maximumHeight = (0.57 + (safeAspect - 0.5) * 1.1).clamp(0.57, 0.84);
    if (height > maximumHeight) {
      width *= maximumHeight / height;
      height = maximumHeight;
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
    final shape = ratio >= 1 ? ratio : 1 / ratio;
    return switch (layout) {
      GuidedScanLayout.passport => shape >= 1.14 && shape <= 1.84,
      GuidedScanLayout.card => shape >= 1.27 && shape <= 2.00,
      GuidedScanLayout.portrait => shape <= 2.00,
      GuidedScanLayout.adaptive =>
        shape <= (documentKey == 'receipts' ? 3.20 : 2.10),
    };
  }

  String get pagesHint => pagesHintIn(AppLanguage.en);

  /// What comes after this photo, in the student's language.
  String pagesHintIn(AppLanguage language) => switch (pages) {
    'two_page_form' => const Words(
        'After this photo, add page 2 from the review screen.',
        'Après cette photo, ajoutez la page 2 depuis l’écran de vérification.',
        'بعد هذه الصورة، أضف الصفحة 2 من شاشة المراجعة.').of(language),
    'multiple' => const Words(
        'Add any remaining pages from the review screen.',
        'Ajoutez les pages restantes depuis l’écran de vérification.',
        'أضف الصفحات المتبقية من شاشة المراجعة.').of(language),
    _ => '',
  };
}
