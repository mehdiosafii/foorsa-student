import 'package:flutter/services.dart';

import '../app_language.dart';
import '../bridge_files.dart';
import 'scan_document_profile.dart';
import 'scan_text_reading.dart';

/// The iPhone scanner returns one already-cropped page per invocation. Keep the
/// existing pages envelope so the portal bridge remains wire-compatible.
/// What the scanner bridge tells the portal when a scan cannot be used, in
/// the student's language (the portal shows it as it is).
const _pageNotPrepared = Words(
    'The scanned page could not be prepared. Please try again.',
    'La page scannée n’a pas pu être préparée. Veuillez réessayer.',
    'تعذّر تجهيز الصفحة الممسوحة. يرجى إعادة المحاولة.');
const _originalsNotPrepared = Words(
    'The original photos could not be prepared. Please try again.',
    'Les photos d’origine n’ont pas pu être préparées. Veuillez réessayer.',
    'تعذّر تجهيز الصور الأصلية. يرجى إعادة المحاولة.');
const _unexpectedMode = Words(
    'The camera returned an unexpected capture mode. Please try again.',
    'L’appareil photo a renvoyé un mode de capture inattendu. Veuillez '
        'réessayer.',
    'أعادت الكاميرا وضع التقاط غير متوقع. يرجى إعادة المحاولة.');
const _scannerUnavailable = Words(
    'The iOS document scanner is unavailable in this app build.',
    'Le scanner de documents iOS n’est pas disponible dans cette version de '
        'l’application.',
    'ماسح الوثائق الخاص بـ iOS غير متاح في هذا الإصدار من التطبيق.');
const _cameraCouldNotFinish = Words(
    'The document camera could not finish. Please try again.',
    'L’appareil photo n’a pas pu terminer. Veuillez réessayer.',
    'تعذّر على كاميرا الوثائق إنهاء المسح. يرجى إعادة المحاولة.');

class NativeDocumentScanner {
  static const channel = MethodChannel('foorsa/document_scanner');
  static const maximumOriginalBytes = 8 * 1024 * 1024;
  static const maximumTotalOriginalBytes = 32 * 1024 * 1024;

  static bool _isBoundedJpeg(Object? value) => value is Uint8List &&
      value.length >= 4 && value.length <= maximumOriginalBytes &&
      value[0] == 0xff && value[1] == 0xd8 &&
      value[value.length - 2] == 0xff && value.last == 0xd9;

  Future<Map<String, dynamic>> scan(
      {GuidedDocumentProfile? profile,
      AppLanguage language = AppLanguage.en}) async {
    try {
      final response = await channel.invokeMapMethod<String, dynamic>(
        'scan',
        // The iPhone scanner says its own words in the student's language (ScannerWords).
        {'profile': profile?.toNativeRequest(), 'language': language.code},
      );
      if (response?['unsupported'] == true) return {'unsupported': true};
      if (response?['cancelled'] == true) return {'cancelled': true};
      if (response?['error'] is String) return {'error': response!['error']};
      final pages = response?['pages'];
      if (pages is! List ||
          pages.length != 1 ||
          pages.any((page) => page is! Uint8List || page.isEmpty)) {
        return {'error': _pageNotPrepared.of(language)};
      }
      final imagegen = profile?.outputMode == 'imagegen';
      final originals = response?['originals'];
      if (imagegen &&
          (response?['processing'] != 'imagegen' ||
              !_isBoundedJpeg(pages.single) ||
              originals is! List || originals.isEmpty || originals.length > 6 ||
              originals.any((photo) => !_isBoundedJpeg(photo)) ||
              originals.fold<int>(0, (sum, photo) => sum + (photo as Uint8List).length) >
                  maximumTotalOriginalBytes)) {
        return {'error': _originalsNotPrepared.of(language)};
      }
      // Never accept a mode switch or raw-photo payload from an older request.
      if (!imagegen && (response?['processing'] == 'imagegen' || originals != null)) {
        return {'error': _unexpectedMode.of(language)};
      }
      // What the camera read while the page was in view. Checked and bounded;
      // a malformed reading is dropped, never the scan.
      final liveReading = sanitizeLiveReading(response?['liveReading']);
      // Off the UI isolate (bridge_files.dart): a scan with its originals is
      // tens of megabytes, and encoding them here held the app's frames just
      // as the scanner closed, as picked photos did on Android.
      final originalUrls = <String>[
        if (imagegen)
          for (final photo in originals as List)
            await bridgeDataUrlOffUi('image/jpeg', photo as Uint8List),
      ];
      final pageUrls = <String>[
        for (final page in pages)
          await bridgeDataUrlOffUi('image/jpeg', page as Uint8List),
      ];
      return {
        if (imagegen) 'processing': 'imagegen',
        if (imagegen) 'originals': [
          for (var i = 0; i < originalUrls.length; i++)
            {
              'name': 'scan-original-${i + 1}.jpg',
              'dataUrl': originalUrls[i],
            },
        ],
        'processed': true,
        'engine': response?['engine'] is String
            ? response!['engine']
            : 'avfoundation_vision',
        'scannerBuild': response?['scannerBuild'] is String
            ? response!['scannerBuild']
            : 'custom-live-v4',
        'capabilities': response?['capabilities'] is List
            ? List<String>.unmodifiable(
                (response!['capabilities'] as List).whereType<String>(),
              )
            : const <String>[],
        'burstProcessing': response?['burstProcessing'] is Map
            ? Map<String, dynamic>.unmodifiable(
                Map<String, dynamic>.from(response!['burstProcessing'] as Map),
              )
            : const <String, dynamic>{},
        'files': [
          for (var i = 0; i < pageUrls.length; i++)
            {
              'name': 'scan-page-${i + 1}.jpg',
              'mime': 'image/jpeg',
              'dataUrl': pageUrls[i],
            },
        ],
        if (liveReading != null) 'liveReading': liveReading,
      };
    } on MissingPluginException {
      return {'error': _scannerUnavailable.of(language)};
    } catch (_) {
      // A failed scan is not permission to open a different camera silently.
      return {'error': _cameraCouldNotFinish.of(language)};
    }
  }
}
