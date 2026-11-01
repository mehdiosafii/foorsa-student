// The scanner's lines in the student's language.
//
// The coach's tables stay in English (scan_coach.dart is held word for word
// to the iPhone's ScannerGeometry.swift by test/scan_coach_test.dart, and the
// coach compares what each frame asks for with what is on screen by those
// words), so they are said in French or Arabic only as they are shown:
// ScanGuidancePanel gets [scanCopyIn]'s copy. A line with no translation here
// is shown in English rather than not at all; test/scan_copy_language_test.dart
// fails for any line the coach or the page can show that is missing.
import '../app_language.dart';
import 'scan_text_reading.dart';

/// [copy] as the student reads it, in [language].
ScanTextCopy scanCopyIn(ScanTextCopy copy, AppLanguage language) {
  if (language == AppLanguage.en) return copy;
  return ScanTextCopy(scanLineIn(copy.title, language),
      scanLineIn(copy.detail, language), scanLineIn(copy.compact, language));
}

/// One of the scanner's English lines, in [language]; English when this file
/// does not know it.
String scanLineIn(String english, AppLanguage language) {
  if (language == AppLanguage.en || english.isEmpty) return english;
  return scanLineWords(english)?.of(language) ?? english;
}

/// The three words for one of the scanner's English lines, or null.
Words? scanLineWords(String english) => _lines[english];

/// Whether [english] has its French and Arabic here.
bool scanLineKnown(String english) => english.isEmpty || _lines.containsKey(english);

final Map<String, Words> _lines = _build();

Map<String, Words> _build() {
  final lines = <String, Words>{};
  // What the reading says (scan_text_reading.dart), already written in the
  // three languages, paired line by line.
  for (final guidance in ScanTextGuidance.values) {
    for (final kind in ScanPaperKind.values) {
      final en = guidance.copy(kind);
      final fr = guidance.copy(kind, AppLanguage.fr);
      final ar = guidance.copy(kind, AppLanguage.ar);
      lines.putIfAbsent(en.title, () => Words(en.title, fr.title, ar.title));
      lines.putIfAbsent(en.detail, () => Words(en.detail, fr.detail, ar.detail));
      lines.putIfAbsent(en.compact, () => Words(en.compact, fr.compact, ar.compact));
    }
  }
  // The coach's and the page's own lines win over a reading's that happens to
  // share the English.
  for (final words in _coachAndPage) {
    lines[words.en] = words;
  }
  return lines;
}

const _coachAndPage = <Words>[
  // Framing (scan_coach.dart).
  Words('Front side', 'Le recto', 'الوجه الأمامي'),
  Words('Show the side with the photo.', 'Montrez le côté avec la photo.',
      'أظهر الوجه الذي يحمل الصورة.'),
  Words('The photo side.', 'Le côté photo.', 'وجه الصورة.'),
  Words('Now the back', 'Maintenant le verso', 'والآن الوجه الخلفي'),
  Words('Turn the card over.', 'Retournez la carte.', 'اقلب البطاقة.'),
  Words('Turn it over.', 'Retournez-la.', 'اقلبها.'),
  Words('Find the card', 'Cadrez la carte', 'ضع البطاقة في الإطار'),
  Words('Fit the whole card in view.',
      'Faites entrer toute la carte dans le cadre.',
      'اجعل البطاقة كاملة داخل الإطار.'),
  Words('Whole card in view.', 'Toute la carte.', 'البطاقة كاملة.'),
  Words('Find the page', 'Cadrez la page', 'ضع الصفحة في الإطار'),
  Words('Fit the whole page in view.',
      'Faites entrer toute la page dans le cadre.',
      'اجعل الصفحة كاملة داخل الإطار.'),
  Words('Whole page in view.', 'Toute la page.', 'الصفحة كاملة.'),
  Words('Move back a little', 'Reculez un peu', 'ابتعد قليلًا'),
  Words('Keep all four corners in view.',
      'Gardez les quatre coins dans le cadre.',
      'أبقِ الزوايا الأربع داخل الإطار.'),
  Words('Show all corners.', 'Tous les coins.', 'كل الزوايا.'),
  Words('Let the page fill more of the view.',
      'La page doit remplir davantage le cadre.',
      'اجعل الصفحة تملأ مساحة أكبر من الإطار.'),
  Words('Open the passport flat', 'Ouvrez le passeport à plat',
      'افتح جواز السفر بشكل مسطح'),
  Words('Show the photo page and the page facing it.',
      'Montrez la page de la photo et la page en face.',
      'أظهر صفحة الصورة والصفحة المقابلة لها.'),
  Words('Both pages.', 'Les deux pages.', 'الصفحتان معًا.'),
  Words('Show all four corners', 'Montrez les quatre coins',
      'أظهر الزوايا الأربع'),
  Words('All four corners.', 'Les quatre coins.', 'الزوايا الأربع.'),
  Words('Hold still', 'Ne bougez plus', 'ثبّت الهاتف'),
  Words('Keep the phone steady.', 'Gardez le téléphone immobile.',
      'أبقِ الهاتف ثابتًا.'),
  Words('Hold still.', 'Ne bougez plus.', 'ثبّت الهاتف.'),
  Words('Hold the phone flat', 'Tenez le téléphone à plat',
      'أمسك الهاتف بشكل مستوٍ'),
  Words('Keep it level above the page.',
      'Gardez-le bien parallèle au-dessus de la page.',
      'أبقِه موازيًا فوق الصفحة.'),
  Words('Hold it flat.', 'À plat.', 'بشكل مستوٍ.'),
  Words('Too dark', 'Trop sombre', 'الإضاءة ضعيفة جدًا'),
  Words('Move to a brighter place.', 'Allez dans un endroit plus lumineux.',
      'انتقل إلى مكان أكثر إضاءة.'),
  Words('More light.', 'Plus de lumière.', 'إضاءة أكثر.'),
  Words('Glare on the page', 'Reflet sur la page', 'انعكاس على الصفحة'),
  Words('Tilt the phone slightly.', 'Inclinez légèrement le téléphone.',
      'أمِل الهاتف قليلًا.'),
  Words('Tilt slightly.', 'Inclinez légèrement.', 'أمِله قليلًا.'),
  Words('Shadow on the page', 'Ombre sur la page', 'ظل على الصفحة'),
  Words('Move your hand or the phone.', 'Déplacez votre main ou le téléphone.',
      'حرّك يدك أو الهاتف.'),
  Words('Avoid the shadow.', 'Évitez l’ombre.', 'تجنّب الظل.'),
  Words('Taking the photo.', 'Prise de la photo.', 'جارٍ التقاط الصورة.'),
  Words('Got it', 'C’est bon', 'تم'),
  Words('Preparing your page.', 'Préparation de votre page.',
      'جارٍ تجهيز صفحتك.'),
  Words('Got it.', 'C’est bon.', 'تم.'),
  // The page's own moments (guided_scan_page.dart).
  Words('Try again', 'Réessayez', 'أعد المحاولة'),
  Words('Try again.', 'Réessayez.', 'أعد المحاولة.'),
  Words('The photo was not taken. Hold still and try again.',
      'La photo n’a pas été prise. Ne bougez plus et réessayez.',
      'لم تُلتقط الصورة. ثبّت الهاتف وأعد المحاولة.'),
  Words('Camera unavailable', 'Appareil photo indisponible',
      'الكاميرا غير متاحة'),
  Words('This camera could not open.',
      'Cet appareil photo n’a pas pu s’ouvrir.', 'تعذّر فتح هذه الكاميرا.'),
  Words('Camera unavailable.', 'Appareil photo indisponible.',
      'الكاميرا غير متاحة.'),
  Words('Opening camera…', 'Ouverture de l’appareil photo…',
      'جارٍ فتح الكاميرا…'),
  Words('Tap the shutter', 'Touchez le déclencheur', 'اضغط على زر الالتقاط'),
  Words('Take the photo when the whole page is clear.',
      'Prenez la photo quand toute la page est nette.',
      'التقط الصورة حين تكون الصفحة كلها واضحة.'),
  Words('Tap the shutter.', 'Touchez le déclencheur.',
      'اضغط على زر الالتقاط.'),
];
