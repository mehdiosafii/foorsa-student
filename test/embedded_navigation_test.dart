import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/embedded_navigation.dart';

void main() {
  test('embedded YouTube players stay inside the app', () {
    expect(
        isEmbeddedWebNavigation(
          Uri.parse('https://www.youtube-nocookie.com/embed/Ak6FvRBhaw8'),
          isForMainFrame: false,
        ),
        isTrue);
  });

  test('top-level links and unknown frames still use the external-link policy',
      () {
    final uri = Uri.parse('https://www.youtube.com/watch?v=Ak6FvRBhaw8');
    expect(isEmbeddedWebNavigation(uri, isForMainFrame: true), isFalse);
    expect(isEmbeddedWebNavigation(uri, isForMainFrame: null), isFalse);
  });

  test('iframe custom schemes do not bypass the external-link policy', () {
    for (final url in [
      'youtube://video/Ak6FvRBhaw8',
      'tel:123',
      'file:///tmp/video'
    ]) {
      expect(isEmbeddedWebNavigation(Uri.parse(url), isForMainFrame: false),
          isFalse);
    }
  });

  test('a picture or a PDF of the portal\'s own is for the app\'s viewer', () {
    // Under every paper's help: "Tap the sample to view it full size".
    final sample = previewableFile(Uri.parse(
        'https://student.foorsa.ma/document-samples/v1/passport-c5d1e54f326b.webp'));
    expect(sample?.name, 'passport-c5d1e54f326b.webp');
    expect(sample?.mime, 'image/webp');
    expect(previewableFile(Uri.parse('https://student.foorsa.ma/x/Photo.JPG'))?.mime, 'image/jpeg');
    expect(previewableFile(Uri.parse('https://student.foorsa.ma/x/a.jpeg?t=abc'))?.mime, 'image/jpeg');
    expect(previewableFile(Uri.parse('https://student.foorsa.ma/x/a.png#top'))?.mime, 'image/png');
    expect(previewableFile(Uri.parse('https://student.foorsa.ma/forms/medical-form.pdf'))?.mime, 'application/pdf');
  });

  test('a page of the portal still loads in the web view', () {
    for (final url in [
      'https://student.foorsa.ma/',
      'https://student.foorsa.ma/documents',
      'https://student.foorsa.ma/documents?paper=passport',
      'https://student.foorsa.ma/privacy-policy.html',
      'https://student.foorsa.ma/android',
      'https://student.foorsa.ma/downloads/android/apk/foorsa-student-1.2.40-71.apk',
      'https://student.foorsa.ma/folder.v2/',
      'https://student.foorsa.ma/.webp',
      'https://student.foorsa.ma/name.',
      'file:///tmp/picture.png',
      'tel:123.png',
    ]) {
      expect(previewableFile(Uri.parse(url)), isNull, reason: url);
    }
  });

  test('a new window is a viewer for a file, the web view for a page', () {
    final shell = File('lib/src/shell_page.dart').readAsStringSync();
    final start = shell.indexOf('onCreateWindow: (controller, action) async {');
    expect(start, isNonNegative);
    final handler = shell.substring(start, shell.indexOf('shouldOverrideUrlLoading:', start));
    final viewer = handler.indexOf('_previewFile(uri.toString(), file.name, file.mime)');
    final load = handler.indexOf('controller.loadUrl(');
    expect(handler, contains('_isInternal(uri) ? previewableFile(uri) : null'),
        reason: 'only the portal\'s own files: another site\'s still leave the app');
    expect(viewer, isNonNegative);
    expect(load, greaterThan(viewer), reason: 'the file is taken before the page is loaded');
    expect(handler, contains('_openExternally(uri);'));
  });
}
