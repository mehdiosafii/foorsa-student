// Every line the scanner can show has its French and Arabic
// (scan_copy_language.dart): the coach's tables, the page's own moments and
// what the reading says. The coach stays in English, held to the iPhone's
// words, and is translated only as it is shown.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/app_language.dart';
import 'package:foorsa_student/src/guided_scanner/scan_coach.dart';
import 'package:foorsa_student/src/guided_scanner/scan_copy_language.dart';
import 'package:foorsa_student/src/guided_scanner/scan_text_reading.dart';

/// Every `ScanTextCopy('…', '…', '…')` written in [path], and the photo's
/// own error line.
List<String> _linesIn(String path) {
  final source = File(path).readAsStringSync();
  final literal = RegExp(r"ScanTextCopy\(\s*'((?:[^'\\]|\\.)*)'\s*,\s*'((?:[^'\\]|\\.)*)'\s*,\s*'((?:[^'\\]|\\.)*)'\s*\)");
  final error = RegExp(r"_captureError = '((?:[^'\\]|\\.)*)'");
  return [
    for (final m in literal.allMatches(source)) ...[m[1]!, m[2]!, m[3]!],
    for (final m in error.allMatches(source)) m[1]!,
  ].map((line) => line.replaceAll(r"\'", "'")).toList();
}

void main() {
  test('the coach and the page show no line without its French and Arabic', () {
    final lines = {
      ..._linesIn('lib/src/guided_scanner/scan_coach.dart'),
      ..._linesIn('lib/src/guided_scanner/guided_scan_page.dart'),
    };
    expect(lines.length, greaterThan(30), reason: 'the tables were read');
    final missing = lines.where((line) => !scanLineKnown(line)).toList();
    expect(missing, isEmpty);
  });

  test('what the reading says is the same in the panel as in its own tables', () {
    for (final guidance in ScanTextGuidance.values) {
      for (final kind in ScanPaperKind.values) {
        for (final language in AppLanguage.values) {
          final own = guidance.copy(kind, language);
          final shown = scanCopyIn(guidance.copy(kind), language);
          // The coach's own word wins where the two share the English, so
          // only the reading's own lines are compared.
          if (scanLineWords(guidance.copy(kind).detail)?.of(language) == own.detail) {
            expect(shown.detail, own.detail);
          }
        }
      }
    }
  });

  test('English is unchanged, French and Arabic are in their own language', () {
    const copy = scanGotIt;
    expect(scanCopyIn(copy, AppLanguage.en), copy);
    final fr = scanCopyIn(copy, AppLanguage.fr);
    expect(fr.title, 'C’est bon');
    expect(fr.detail, 'Préparation de votre page.');
    final ar = scanCopyIn(scanTakingPhoto, AppLanguage.ar);
    expect(ar.title, 'ثبّت الهاتف');
    expect(ar.detail, 'جارٍ التقاط الصورة.');
    // No Latin letters in an Arabic line, and Arabic punctuation only.
    final arabicLines = {
      ..._linesIn('lib/src/guided_scanner/scan_coach.dart'),
      ..._linesIn('lib/src/guided_scanner/guided_scan_page.dart'),
    }.where((line) => line.isNotEmpty).map((line) => scanLineIn(line, AppLanguage.ar));
    for (final line in arabicLines) {
      expect(RegExp('[A-Za-z]').hasMatch(line), isFalse, reason: line);
      expect(line.contains(','), isFalse, reason: line);
    }
  });

  test('a line this file does not know is shown in English, not dropped', () {
    expect(scanLineIn('Some new line', AppLanguage.fr), 'Some new line');
    expect(scanLineIn('', AppLanguage.ar), '');
  });
}
