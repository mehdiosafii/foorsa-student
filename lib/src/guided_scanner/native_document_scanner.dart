import 'dart:convert';

import 'package:flutter/services.dart';

import 'scan_document_profile.dart';

/// The iPhone scanner returns one already-cropped page per invocation. Keep the
/// existing pages envelope so the portal bridge remains wire-compatible.
class NativeDocumentScanner {
  static const channel = MethodChannel('foorsa/document_scanner');

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
      return {
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
