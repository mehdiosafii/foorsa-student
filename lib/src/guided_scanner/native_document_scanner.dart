import 'dart:convert';

import 'package:flutter/services.dart';

/// System scans are already cropped and filtered. Preserve that marker and
/// every page so the portal never crops twice or silently keeps only page one.
class NativeDocumentScanner {
  static const channel = MethodChannel('foorsa/document_scanner');

  Future<Map<String, dynamic>> scan() async {
    try {
      final response = await channel.invokeMapMethod<String, dynamic>('scan');
      if (response?['unsupported'] == true) return {'unsupported': true};
      if (response?['cancelled'] == true) return {'cancelled': true};
      if (response?['error'] is String) return {'error': response!['error']};
      final pages = response?['pages'];
      if (pages is! List ||
          pages.isEmpty ||
          pages.length > 20 ||
          pages.any((page) => page is! Uint8List || page.isEmpty)) {
        return {
          'error': 'The scanned pages could not be prepared. Please try again.'
        };
      }
      return {
        'processed': true,
        'engine': 'visionkit',
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
      return {'unsupported': true};
    } catch (_) {
      // A failed scan is not permission to open a different camera silently.
      return {
        'error': 'The document camera could not finish. Please try again.'
      };
    }
  }
}
