import 'dart:convert';

import 'package:flutter/services.dart';

import 'scan_document_profile.dart';
import 'scan_text_reading.dart';

/// The iPhone scanner returns one already-cropped page per invocation. Keep the
/// existing pages envelope so the portal bridge remains wire-compatible.
class NativeDocumentScanner {
  static const channel = MethodChannel('foorsa/document_scanner');
  static const maximumOriginalBytes = 8 * 1024 * 1024;
  static const maximumTotalOriginalBytes = 32 * 1024 * 1024;

  static bool _isBoundedJpeg(Object? value) => value is Uint8List &&
      value.length >= 4 && value.length <= maximumOriginalBytes &&
      value[0] == 0xff && value[1] == 0xd8 &&
      value[value.length - 2] == 0xff && value.last == 0xd9;

  Future<Map<String, dynamic>> scan({GuidedDocumentProfile? profile}) async {
    try {
      final response = await channel.invokeMapMethod<String, dynamic>(
        'scan',
        {'profile': profile?.toNativeRequest()},
      );
      if (response?['unsupported'] == true) return {'unsupported': true};
      if (response?['cancelled'] == true) return {'cancelled': true};
      if (response?['error'] is String) return {'error': response!['error']};
      final pages = response?['pages'];
      if (pages is! List ||
          pages.length != 1 ||
          pages.any((page) => page is! Uint8List || page.isEmpty)) {
        return {
          'error': 'The scanned page could not be prepared. Please try again.'
        };
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
        return {'error': 'The original photos could not be prepared. Please try again.'};
      }
      // Never accept a mode switch or raw-photo payload from an older request.
      if (!imagegen && (response?['processing'] == 'imagegen' || originals != null)) {
        return {'error': 'The camera returned an unexpected capture mode. Please try again.'};
      }
      // What the camera read while the page was in view. Checked and bounded;
      // a malformed reading is dropped, never the scan.
      final liveReading = sanitizeLiveReading(response?['liveReading']);
      return {
        if (imagegen) 'processing': 'imagegen',
        if (imagegen) 'originals': [
          for (var i = 0; i < (originals as List).length; i++)
            {
              'name': 'scan-original-${i + 1}.jpg',
              'dataUrl': 'data:image/jpeg;base64,${base64Encode(originals[i] as Uint8List)}',
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
          for (var i = 0; i < pages.length; i++)
            {
              'name': 'scan-page-${i + 1}.jpg',
              'mime': 'image/jpeg',
              'dataUrl':
                  'data:image/jpeg;base64,${base64Encode(pages[i] as Uint8List)}',
            },
        ],
        if (liveReading != null) 'liveReading': liveReading,
      };
    } on MissingPluginException {
      return {
        'error': 'The iOS document scanner is unavailable in this app build.'
      };
    } catch (_) {
      // A failed scan is not permission to open a different camera silently.
      return {
        'error': 'The document camera could not finish. Please try again.'
      };
    }
  }
}
