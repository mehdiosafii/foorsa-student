// The iPhone scanner says its words in the student's language (ScannerWords in
// ios/Runner/ScannerGeometry.swift). Its guidance tables stay English, held word for word to
// Android's (scan_coach_test.dart), so the Swift table must say each of their lines exactly as
// Android does (scan_copy_language.dart), and know every line the iPhone scanner can show.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/app_language.dart';
import 'package:foorsa_student/src/guided_scanner/scan_copy_language.dart';

final _literal = RegExp(r'"((?:[^"\\]|\\.)*)"');

/// The source without comments and without `#if SCANNER_DIAGNOSTICS` blocks (the diagnostics
/// build draws English test lines that no student sees).
List<String> _shownSource(String path) {
  final out = <String>[];
  var skipping = 0;
  for (final line in File(path).readAsLinesSync()) {
    final trimmed = line.trimLeft();
    if (skipping > 0) {
      if (trimmed.startsWith('#if')) skipping++;
      if (trimmed.startsWith('#endif')) skipping--;
      continue;
    }
    if (trimmed.startsWith('#if SCANNER_DIAGNOSTICS')) {
      skipping = 1;
      continue;
    }
    if (trimmed.startsWith('//')) continue;
    out.add(line);
  }
  return out;
}

/// The English words a line of Swift can show: a capitalised word or a sentence.
Iterable<String> _words(Iterable<String> lines) sync* {
  for (final line in lines) {
    for (final m in _literal.allMatches(line)) {
      final value = m[1]!;
      if (value.contains(r'\(')) continue; // an interpolation, built from translated parts
      if (!RegExp('[A-Z][a-z]').hasMatch(value)) continue;
      if (!value.contains(' ') && !RegExp(r'^[A-Z][a-z]+$').hasMatch(value)) continue;
      yield value;
    }
  }
}

void main() {
  final geometry = File('ios/Runner/ScannerGeometry.swift').readAsStringSync();
  final marker = geometry.indexOf("// MARK: - The scanner's words in the student's language");
  final entry = RegExp(r'^\s*"((?:[^"\\]|\\.)*)": \("((?:[^"\\]|\\.)*)", "((?:[^"\\]|\\.)*)"\),$',
      multiLine: true);
  final table = <String, (String, String)>{};
  final keys = <String>[];
  for (final m in entry.allMatches(geometry.substring(marker))) {
    keys.add(m[1]!);
    table[m[1]!] = (m[2]!, m[3]!);
  }

  test('the table is there, once per line (a repeated key would crash the app)', () {
    expect(marker, isNonNegative);
    expect(table.length, greaterThan(100));
    expect(keys.toSet().length, keys.length);
  });

  test('every guidance line says what Android says', () {
    for (final english in table.keys) {
      final android = scanLineWords(english);
      if (android == null) continue;
      expect((android.of(AppLanguage.fr), android.of(AppLanguage.ar)), table[english], reason: english);
    }
  });

  test('every line of the guidance tables is in the table', () {
    final lines = [
      ..._shownSource('ios/Runner/ScannerGeometry.swift').takeWhile((l) => !l.contains('enum ScannerWords')),
      ..._shownSource('ios/Runner/ScannerTextReading.swift'),
    ];
    final missing = _words(lines).where((w) => !table.containsKey(w)).toSet();
    expect(missing, isEmpty);
  });

  test('every line the scanner screen and its entry show is in the table', () {
    // Words the screen compares titles with and never shows.
    const comparedOnly = {'Tilt', 'Glare', 'Scan ready', 'Photos ready', 'More light needed'};
    final lines = [
      ..._shownSource('ios/Runner/FoorsaScannerViewController.swift'),
      ..._shownSource('ios/Runner/DocumentScanner.swift'),
    ];
    final words = _words(lines).where((w) => !comparedOnly.contains(w)).toSet();
    expect(words.length, greaterThan(40), reason: 'the screen was read');
    expect(words.where((w) => !table.containsKey(w)).toList(), isEmpty);
  });

  test('every shown string goes through ScannerWords.say', () {
    final screen = File('ios/Runner/FoorsaScannerViewController.swift').readAsStringSync();
    expect(screen, contains('titleLabel.text = ScannerWords.say(titleLabel.text ?? "")'));
    expect(screen, contains('detailLabel.text = ScannerWords.say(detailLabel.text ?? "")'));
    expect(screen, contains('completion(["error": ScannerWords.say(message)])'));
    expect(screen, isNot(contains('setTitle("')));
    expect(RegExp(r'accessibility(Label|Hint|Value) = "[A-Z]').hasMatch(screen), isFalse);
    expect(RegExp(r'announcement, argument: "[A-Z]').hasMatch(screen), isFalse);
    final entry = File('ios/Runner/DocumentScanner.swift').readAsStringSync();
    expect(entry, contains('ScannerWords.use((call.arguments as? [String: Any])?["language"])'));
    expect(RegExp(r'\["error": "').hasMatch(entry), isFalse);
  });

  test('the app sends the language with each scan', () {
    final dart = File('lib/src/guided_scanner/native_document_scanner.dart').readAsStringSync();
    expect(dart, contains("'language': language.code"));
  });

  test('French is French and Arabic is Arabic, with Arabic punctuation', () {
    for (final MapEntry(key: english, value: (fr, ar)) in table.entries) {
      expect(fr.trim(), isNotEmpty, reason: english);
      expect(fr, isNot(english), reason: 'untranslated: $english');
      // Latin letters in Arabic only for the app's own name.
      expect(RegExp('[A-Za-z]').hasMatch(ar.replaceAll('Foorsa Student', '')), isFalse, reason: ar);
      expect(ar.contains(','), isFalse, reason: ar);
      expect(RegExp(r'[؀-ۿ]').hasMatch(ar), isTrue, reason: ar);
    }
  });
}
