/// Live text reading and the right-document gate (custom-live-v12).
///
/// While the camera is open the page is read a few times a second, on the
/// phone: ML Kit's bundled Latin model on Android (live_text_reader.dart),
/// Vision on iPhone. This file mirrors ios/Runner/ScannerTextReading.swift
/// rule for rule. What one frame read becomes votes, a passport's or an ID
/// card's machine-readable lines are held to their ICAO 9303 check digits,
/// and the reading decides whether the paper in view is the one the step
/// asked for. Nothing here touches the camera or the network, and nothing
/// read is ever logged.
library;

import 'dart:math' as math;
import 'dart:ui' show Rect;

import '../app_language.dart';
import 'scan_document_profile.dart';

/// Which rules decide that the paper in view is the right one.
enum ScanPaperKind {
  passport('passport'),
  idCard('id_card'),
  paper('paper');

  const ScanPaperKind(this.wireName);
  final String wireName;
}

/// The side of an ID card a step asks for. Without one, either side will do.
enum ScanCardSide { front, back }

/// Papers that may carry machine-readable lines of their own.
const papersThatMayCarryMachineLines = <String>{
  'visa_documents', 'drive_files', 'previous_chinese_universities',
};

extension GuidedDocumentProfileReading on GuidedDocumentProfile {
  ScanPaperKind get paperKind => switch (layout) {
        GuidedScanLayout.passport => ScanPaperKind.passport,
        GuidedScanLayout.card => ScanPaperKind.idCard,
        _ => ScanPaperKind.paper,
      };

  ScanCardSide? get cardSide => switch (side) {
        'front' => ScanCardSide.front,
        'back' => ScanCardSide.back,
        _ => null,
      };

  /// A passport or an ID card in a diploma's step is the wrong paper.
  bool get rejectsIdentityPapers => paperKind == ScanPaperKind.paper &&
      !papersThatMayCarryMachineLines.contains(documentKey);
}

// ── Machine-readable zone (ICAO 9303) ──────────────────────────────────────

enum ScanMrzField { alpha, digit, alphanumeric, sex }

enum ScanMrzFormat {
  /// Two lines of 44: passports.
  td3('TD3', 44, 2, [1]),

  /// Three lines of 30: ID cards.
  td1('TD1', 30, 3, [0, 1]);

  const ScanMrzFormat(this.wireName, this.lineLength, this.lineCount, this.protectedLines);
  final String wireName;
  final int lineLength;
  final int lineCount;

  /// Lines covered by check digits. A read that disagrees there is another paper.
  final List<int> protectedLines;

  /// What each position holds, line by line (ICAO 9303 parts 4 and 5).
  List<List<ScanMrzField>> get fields {
    switch (this) {
      case ScanMrzFormat.td3:
        final second = List.filled(44, ScanMrzField.alphanumeric);
        second[9] = ScanMrzField.digit;
        for (var i = 10; i < 13; i++) {
          second[i] = ScanMrzField.alpha;
        }
        for (var i = 13; i < 20; i++) {
          second[i] = ScanMrzField.digit;
        }
        second[20] = ScanMrzField.sex;
        for (var i = 21; i < 28; i++) {
          second[i] = ScanMrzField.digit;
        }
        second[42] = ScanMrzField.digit;
        second[43] = ScanMrzField.digit;
        return [List.filled(44, ScanMrzField.alpha), second];
      case ScanMrzFormat.td1:
        final first = List.filled(30, ScanMrzField.alphanumeric);
        for (var i = 0; i < 5; i++) {
          first[i] = ScanMrzField.alpha;
        }
        first[14] = ScanMrzField.digit;
        final second = List.filled(30, ScanMrzField.alphanumeric);
        for (var i = 0; i < 7; i++) {
          second[i] = ScanMrzField.digit;
        }
        second[7] = ScanMrzField.sex;
        for (var i = 8; i < 15; i++) {
          second[i] = ScanMrzField.digit;
        }
        for (var i = 15; i < 18; i++) {
          second[i] = ScanMrzField.alpha;
        }
        second[29] = ScanMrzField.digit;
        return [first, second, List.filled(30, ScanMrzField.alpha)];
    }
  }
}

List<int> _codes(String text) => text.codeUnits;

Map<int, int> _pairs(String keys, String values) =>
    {for (var i = 0; i < keys.length; i++) keys.codeUnitAt(i): values.codeUnitAt(i)};

bool _sameLine(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

abstract final class ScanMrz {
  static const filler = 0x3C; // <
  static const zero = 0x30;
  static const _weights = [7, 3, 1];
  static final _sexes = _codes('MFX<').toSet();
  static final _digitLookAlikes = _pairs('OQDILZSBG', '000112586');
  static final _letterLookAlikes = _pairs('012586', 'OIZSBG');
  static final _misreadFillers = _codes('KCELX').toSet();

  /// Look-alikes only a check digit can tell apart, in mixed fields.
  static final Map<int, List<int>> mixedLookAlikes = () {
    final table = <int, List<int>>{};
    const digits = '000112568', letters = 'ODQILZSGB';
    for (var i = 0; i < digits.length; i++) {
      final digit = digits.codeUnitAt(i), letter = letters.codeUnitAt(i);
      table.putIfAbsent(digit, () => []).add(letter);
      table.putIfAbsent(letter, () => []).add(digit);
    }
    return table;
  }();

  static bool isLetter(int c) => c >= 0x41 && c <= 0x5A;
  static bool isDigit(int c) => c >= 0x30 && c <= 0x39;
  static bool isSex(int c) => _sexes.contains(c);
  static bool isLetterOrFiller(int c) => isLetter(c) || c == filler;
  static int digitLookAlike(int c) => _digitLookAlikes[c] ?? c;

  /// ICAO 9303 value of a character: digits, A–Z as 10–35, the filler 0.
  static int? value(int c) {
    if (isDigit(c)) return c - 0x30;
    if (isLetter(c)) return c - 0x41 + 10;
    return c == filler ? 0 : null;
  }

  /// Weights 7, 3, 1 repeating; the sum modulo 10.
  static int? checkDigit(Iterable<int> field) {
    var sum = 0;
    var index = 0;
    for (final c in field) {
      final v = value(c);
      if (v == null) return null;
      sum += v * _weights[index % 3];
      index++;
    }
    return sum % 10;
  }

  static bool passes(Iterable<int> field, int check) {
    if (!isDigit(check)) return false;
    final digit = checkDigit(field);
    return digit != null && digit == check - 0x30;
  }

  /// YYMMDD with a real month and day.
  static bool isDate(List<int> d) {
    if (d.length != 6 || !d.every(isDigit)) return false;
    final month = (d[2] - 0x30) * 10 + d[3] - 0x30;
    final day = (d[4] - 0x30) * 10 + d[5] - 0x30;
    return month >= 1 && month <= 12 && day >= 1 && day <= 31;
  }

  static bool datePasses(List<int> line, int start, int end, int check) =>
      isDate(line.sublist(start, end)) && passes(line.sublist(start, end), line[check]);

  /// One read line in the MRZ alphabet: upper-cased, spaces gone, look-alike
  /// chevrons turned into fillers. Anything else is counted as dropped.
  static ({List<int> characters, int dropped}) normalize(String text) {
    final characters = <int>[];
    var dropped = 0;
    for (final value in text.toUpperCase().runes) {
      if ((value >= 0x41 && value <= 0x5A) || (value >= 0x30 && value <= 0x39) || value == 0x3C) {
        characters.add(value);
      } else if (value == 0x20 || value == 0x09) {
        continue;
      } else if (value == 0xAB || value == 0x226A) {
        // « and ≪: a pair of fillers read as one glyph.
        characters
          ..add(filler)
          ..add(filler);
      } else if (const [0x2039, 0x2264, 0x2329, 0x3008, 0xFF1C].contains(value)) {
        characters.add(filler);
      } else {
        dropped++;
      }
    }
    return (characters: characters, dropped: dropped);
  }

  /// Puts each position in its own alphabet: an O in a date is a zero, a
  /// zero in a name an O. Fields holding both are left to their check digit.
  static List<int> conform(List<int> line, List<ScanMrzField> fields) {
    final out = List<int>.of(line);
    for (var i = 0; i < out.length && i < fields.length; i++) {
      switch (fields[i]) {
        case ScanMrzField.digit:
          out[i] = _digitLookAlikes[out[i]] ?? out[i];
        case ScanMrzField.alpha:
          out[i] = _letterLookAlikes[out[i]] ?? out[i];
        case ScanMrzField.alphanumeric:
        case ScanMrzField.sex:
          break;
      }
    }
    return clearMisreadFillerRuns(out, fields);
  }

  /// No name or number repeats a letter three times: such a run is a filler
  /// run the OCR engine misread.
  static List<int> clearMisreadFillerRuns(List<int> line, List<ScanMrzField> fields) {
    final out = List<int>.of(line);
    var start = 0;
    while (start < out.length) {
      var end = start + 1;
      while (end < out.length && out[end] == out[start]) {
        end++;
      }
      var textFields = true;
      for (var i = start; i < end; i++) {
        if (i >= fields.length ||
            (fields[i] != ScanMrzField.alpha && fields[i] != ScanMrzField.alphanumeric)) {
          textFields = false;
        }
      }
      if (end - start >= 3 && _misreadFillers.contains(out[start]) && textFields) {
        for (var i = start; i < end; i++) {
          out[i] = filler;
        }
      }
      start = end;
    }
    return out;
  }

  /// The ways a read line may have gained or lost characters. OCR most often
  /// adds or drops one inside a filler run; lines further off are not lines
  /// of this format.
  static List<List<int>> lengthVariants(List<int> line, int length) {
    final delta = line.length - length;
    if (delta == 0) return [line];
    if (delta.abs() > 2 || length <= 0) return [];
    final variants = <List<int>>[];
    final seen = <String>{};
    void keep(List<int> variant) {
      if (variant.length == length && seen.add(String.fromCharCodes(variant))) variants.add(variant);
    }

    final gaps = [
      for (var i = 0; i <= line.length; i++)
        if (i == line.length || line[i] == filler || (i > 0 && line[i - 1] == filler)) i,
    ];
    switch (delta) {
      case 1:
        for (var i = 0; i < line.length; i++) {
          keep(List.of(line)..removeAt(i));
        }
      case 2:
        final fillers = [for (var i = 0; i < line.length; i++) if (line[i] == filler) i];
        for (var n = 0; n < fillers.length; n++) {
          for (var m = n + 1; m < fillers.length; m++) {
            keep(List.of(line)
              ..removeAt(fillers[m])
              ..removeAt(fillers[n]));
          }
        }
      case -1:
        for (final index in gaps) {
          keep(List.of(line)..insert(index, filler));
        }
      case -2:
        for (var n = 0; n < gaps.length; n++) {
          for (var m = n; m < gaps.length; m++) {
            keep(List.of(line)
              ..insert(gaps[m], filler)
              ..insert(gaps[n], filler));
          }
        }
    }
    return variants;
  }

  /// A names line can only gain or lose fillers at its end, where no check
  /// digit can tell.
  static List<int>? padded(List<int> line, int length) {
    if ((line.length - length).abs() > 3) return null;
    final out = List<int>.of(line);
    while (out.length > length && out.last == filler) {
      out.removeLast();
    }
    while (out.length < length) {
      out.add(filler);
    }
    return out.length == length ? out : null;
  }

  static List<int> td3Composite(List<int> line) =>
      [...line.sublist(0, 10), ...line.sublist(13, 20), ...line.sublist(21, 43)];

  static List<int> td1Composite(List<int> first, List<int> second) => [
        ...first.sublist(5, 30), ...second.sublist(0, 7),
        ...second.sublist(8, 15), ...second.sublist(18, 29),
      ];

  /// Passport line two: how many of its four check digits pass.
  static int td3LineTwoScore(List<int> line) {
    if (line.length != 44) return 0;
    var score = 0;
    if (passes(line.sublist(0, 9), line[9])) score++;
    if (datePasses(line, 13, 19, 19)) score++;
    if (datePasses(line, 21, 27, 27)) score++;
    if (passes(td3Composite(line), line[43])) score++;
    return score;
  }

  /// ID card line two: dates and their check digits where they belong.
  static bool td1LineTwoShape(List<int> line) =>
      line.length == 30 && line.sublist(0, 7).every(isDigit) &&
      line.sublist(8, 15).every(isDigit) && isSex(line[7]) &&
      line.sublist(15, 18).every(isLetterOrFiller) && isDigit(line[29]);

  static int td1LineTwoScore(List<int> line) {
    if (line.length != 30) return 0;
    return (datePasses(line, 0, 6, 6) ? 1 : 0) + (datePasses(line, 8, 14, 14) ? 1 : 0);
  }

  /// ICAO 9303-5 4.2.4: a document number longer than nine characters goes
  /// on in the optional data, with its check digit after it.
  static ({List<int> number, int check})? extendedDocumentNumber(List<int> first) {
    if (first.length != 30 || first[14] != filler) return null;
    var end = 15;
    while (end < 30 && first[end] != filler) {
      end++;
    }
    if (end - 15 < 2) return null;
    return (number: [...first.sublist(5, 14), ...first.sublist(15, end - 1)], check: first[end - 1]);
  }

  /// The field's look-alike variants its check digit accepts, fewest changes
  /// first: the line as read when it passes, else every single substitution
  /// that passes, else every double. Empty when nothing passes.
  static List<List<int>> acceptedVariants(List<int> line, int start, int end, int check) {
    if (passes(line.sublist(start, end), line[check])) return [line];
    final positions = [for (var i = start; i < end; i++) if (mixedLookAlikes.containsKey(line[i])) i];
    final singles = <List<int>>[];
    for (final position in positions) {
      for (final alternative in mixedLookAlikes[line[position]]!) {
        final variant = List<int>.of(line);
        variant[position] = alternative;
        if (passes(variant.sublist(start, end), variant[check])) singles.add(variant);
      }
    }
    if (singles.isNotEmpty) return singles;
    final doubles = <List<int>>[];
    for (var n = 0; n < positions.length; n++) {
      for (var m = n + 1; m < positions.length; m++) {
        for (final a in mixedLookAlikes[line[positions[n]]]!) {
          for (final b in mixedLookAlikes[line[positions[m]]]!) {
            final variant = List<int>.of(line);
            variant[positions[n]] = a;
            variant[positions[m]] = b;
            if (passes(variant.sublist(start, end), variant[check])) doubles.add(variant);
          }
        }
      }
    }
    return doubles;
  }
}

/// A complete reading, after look-alike repairs. `valid`: every check digit
/// passed, the dates are real dates and the lines have their format's shape.
class ScanMrzResult {
  const ScanMrzResult(this.format, this.lines, {required this.valid});
  final ScanMrzFormat format;
  final List<List<int>> lines;
  final bool valid;

  List<String> get text => [for (final line in lines) String.fromCharCodes(line)];
}

abstract final class ScanMrzValidator {
  /// `tallies` are the votes behind `lines` (ScanMrzVotes.counts): when two
  /// look-alike repairs satisfy a check digit equally, a character that other
  /// reads actually saw decides. Without them such a tie stays invalid.
  static ScanMrzResult validate(List<List<int>> lines, ScanMrzFormat format,
      {List<List<List<int>>>? tallies}) {
    if (lines.length != format.lineCount || lines.any((line) => line.length != format.lineLength)) {
      return ScanMrzResult(format, lines, valid: false);
    }
    return switch (format) {
      ScanMrzFormat.td3 => _validateTD3(lines, tallies != null && tallies.length > 1 ? tallies[1] : null),
      ScanMrzFormat.td1 => _validateTD1(lines, tallies != null && tallies.isNotEmpty ? tallies[0] : null),
    };
  }

  /// The repaired line with the fewest changes; among those, the one whose
  /// changes the reads saw most. Null when there is none, or a tie remains.
  static List<int>? _unique(List<List<int>> candidates, List<int> original, List<List<int>>? tally) {
    List<int>? best;
    var bestCost = 1 << 30;
    var bestSupport = -1;
    var tied = false;
    for (final candidate in candidates) {
      var cost = 0;
      var support = 0;
      for (var i = 0; i < candidate.length && i < original.length; i++) {
        if (candidate[i] == original[i]) continue;
        cost++;
        final symbol = ScanMrzVotes.symbol(candidate[i]);
        if (tally != null && i < tally.length && symbol != null) support += tally[i][symbol];
      }
      if (cost < bestCost || (cost == bestCost && support > bestSupport)) {
        best = candidate;
        bestCost = cost;
        bestSupport = support;
        tied = false;
      } else if (cost == bestCost && support == bestSupport && !_sameLine(candidate, best!)) {
        tied = true;
      }
    }
    return tied ? null : best;
  }

  static ScanMrzResult _validateTD3(List<List<int>> lines, List<List<int>>? tally) {
    final first = lines[0], second = lines[1];
    final shaped = first[0] == 0x50 && ScanMrz.isLetter(first[5]) &&
        first.sublist(2, 5).every(ScanMrz.isLetterOrFiller) &&
        second.sublist(10, 13).every(ScanMrz.isLetterOrFiller) &&
        ScanMrz.isSex(second[20]) &&
        ScanMrz.datePasses(second, 13, 19, 19) &&
        ScanMrz.datePasses(second, 21, 27, 27);
    if (!shaped) return ScanMrzResult(ScanMrzFormat.td3, lines, valid: false);
    final candidates = <List<int>>[];
    for (final document in ScanMrz.acceptedVariants(second, 0, 9, 9)) {
      final personalEmpty = document.sublist(28, 42).every((c) => c == ScanMrz.filler);
      final List<List<int>> personals;
      if (personalEmpty) {
        // An unused personal number may carry a filler or a zero as its check.
        personals = document[42] == ScanMrz.filler || document[42] == ScanMrz.zero ? [document] : [];
      } else {
        personals = ScanMrz.acceptedVariants(document, 28, 42, 42);
      }
      candidates.addAll(personals.where((line) => ScanMrz.passes(ScanMrz.td3Composite(line), line[43])));
    }
    final repaired = _unique(candidates, second, tally);
    if (repaired == null) return ScanMrzResult(ScanMrzFormat.td3, lines, valid: false);
    return ScanMrzResult(ScanMrzFormat.td3, [first, repaired], valid: true);
  }

  static ScanMrzResult _validateTD1(List<List<int>> lines, List<List<int>>? tally) {
    final first = lines[0], second = lines[1], third = lines[2];
    final shaped = _codes('IAC').contains(first[0]) && ScanMrz.isLetter(third[0]) &&
        first.sublist(2, 5).every(ScanMrz.isLetterOrFiller) &&
        second.sublist(15, 18).every(ScanMrz.isLetterOrFiller) &&
        ScanMrz.isSex(second[7]) &&
        ScanMrz.datePasses(second, 0, 6, 6) &&
        ScanMrz.datePasses(second, 8, 14, 14);
    if (!shaped) return ScanMrzResult(ScanMrzFormat.td1, lines, valid: false);
    final extended = ScanMrz.extendedDocumentNumber(first);
    final documents = extended != null
        ? (ScanMrz.passes(extended.number, extended.check) ? [first] : <List<int>>[])
        : ScanMrz.acceptedVariants(first, 5, 14, 14);
    final candidates = documents
        .where((line) => ScanMrz.passes(ScanMrz.td1Composite(line, second), second[29]))
        .toList();
    final repaired = _unique(candidates, first, tally);
    if (repaired == null) return ScanMrzResult(ScanMrzFormat.td1, lines, valid: false);
    return ScanMrzResult(ScanMrzFormat.td1, [repaired, second, third], valid: true);
  }
}

/// What a valid machine-readable zone says, for the portal's review.
class ScanMrzFields {
  const ScanMrzFields({
    required this.issuingState,
    required this.surname,
    required this.givenNames,
    required this.documentNumber,
    required this.nationality,
    required this.birthDate,
    required this.sex,
    required this.expiryDate,
    required this.personalNumber,
  });

  final String issuingState;
  final String surname;
  final String givenNames;
  final String documentNumber;
  final String nationality;

  /// YYMMDD as printed.
  final String birthDate;
  final String sex;

  /// YYMMDD as printed.
  final String expiryDate;
  final String personalNumber;

  static ScanMrzFields? fromResult(ScanMrzResult result) {
    if (!result.valid) return null;
    switch (result.format) {
      case ScanMrzFormat.td3:
        final first = result.lines[0], second = result.lines[1];
        final names = ScanMrzFields.names(first.sublist(5, 44));
        return ScanMrzFields(
          issuingState: text(first.sublist(2, 5)),
          surname: names.surname,
          givenNames: names.givenNames,
          documentNumber: text(second.sublist(0, 9)),
          nationality: text(second.sublist(10, 13)),
          birthDate: text(second.sublist(13, 19)),
          sex: text(second.sublist(20, 21)),
          expiryDate: text(second.sublist(21, 27)),
          personalNumber: text(second.sublist(28, 42)),
        );
      case ScanMrzFormat.td1:
        final first = result.lines[0], second = result.lines[1], third = result.lines[2];
        final names = ScanMrzFields.names(third.sublist(0, 30));
        final extended = ScanMrz.extendedDocumentNumber(first);
        final optional = text(first.sublist(15, 30));
        return ScanMrzFields(
          issuingState: text(first.sublist(2, 5)),
          surname: names.surname,
          givenNames: names.givenNames,
          documentNumber: extended != null ? text(extended.number) : text(first.sublist(5, 14)),
          nationality: text(second.sublist(15, 18)),
          birthDate: text(second.sublist(0, 6)),
          sex: text(second.sublist(7, 8)),
          expiryDate: text(second.sublist(8, 14)),
          personalNumber: extended != null || optional.isEmpty ? text(second.sublist(18, 29)) : optional,
        );
    }
  }

  /// A field without its fillers; fillers inside it read as spaces.
  static String text(List<int> field) =>
      String.fromCharCodes(field).split('<').where((part) => part.isNotEmpty).join(' ');

  /// SURNAME<<GIVEN<NAMES: a double filler ends the surname.
  static ({String surname, String givenNames}) names(List<int> field) {
    final parts = String.fromCharCodes(field).split('<<');
    String words(String value) => value.split('<').where((part) => part.isNotEmpty).join(' ');
    return (surname: words(parts.first), givenNames: words(parts.skip(1).join('<')));
  }

  /// YYYY-MM-DD. A birth year past `referenceYear` is last century; expiry
  /// years from 70 are too.
  static String? isoDate(String yymmdd, {required bool birth, required int referenceYear}) {
    if (yymmdd.length != 6 || !yymmdd.codeUnits.every(ScanMrz.isDigit)) return null;
    final year = int.parse(yymmdd.substring(0, 2));
    final month = yymmdd.substring(2, 4), day = yymmdd.substring(4, 6);
    final century = birth ? (2000 + year > referenceYear ? 1900 : 2000) : (year >= 70 ? 1900 : 2000);
    return '${(century + year).toString().padLeft(4, '0')}-$month-$day';
  }

  Map<String, String> toMap({required int referenceYear}) {
    final fields = <String, String>{};
    void put(String key, String? value) {
      if (value != null && value.isNotEmpty) fields[key] = value;
    }

    put('surname', surname);
    put('givenNames', givenNames);
    put('documentNumber', documentNumber);
    put('nationality', nationality);
    put('issuingState', issuingState);
    put('birthDate', isoDate(birthDate, birth: true, referenceYear: referenceYear));
    put('sex', sex);
    put('expiryDate', isoDate(expiryDate, birth: false, referenceYear: referenceYear));
    put('personalNumber', personalNumber);
    return fields;
  }
}

/// Character votes across frames, position by position, so one bad frame
/// cannot block a reading and one lucky frame cannot make it.
class ScanMrzVotes {
  ScanMrzVotes(this.format)
      : counts = List.generate(format.lineCount,
            (_) => List.generate(format.lineLength, (_) => List.filled(symbols, 0)));

  static const symbols = 37;
  static const maximumReads = 8;

  final ScanMrzFormat format;
  final List<List<List<int>>> counts;
  final List<List<List<int>?>> reads = [];

  static int? symbol(int c) {
    if (ScanMrz.isLetter(c)) return c - 0x41;
    if (ScanMrz.isDigit(c)) return c - 0x30 + 26;
    return c == ScanMrz.filler ? 36 : null;
  }

  static int character(int symbol) {
    if (symbol < 26) return 0x41 + symbol;
    if (symbol < 36) return 0x30 + symbol - 26;
    return ScanMrz.filler;
  }

  void add(List<List<int>?> lines) {
    if (lines.length != format.lineCount) return;
    var added = false;
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      if (line == null || line.length != format.lineLength) continue;
      for (var position = 0; position < line.length; position++) {
        final s = symbol(line[position]);
        if (s != null) counts[index][position][s]++;
      }
      added = true;
    }
    if (!added) return;
    reads.add(lines);
    if (reads.length > maximumReads) reads.removeAt(0);
  }

  /// The most voted character at each position; the earlier symbol wins a tie.
  List<List<int>?> get consensus => [
        for (final positions in counts)
          if (!positions.any((tally) => tally.any((count) => count > 0)))
            null
          else
            [
              for (final tally in positions)
                () {
                  var best = 0;
                  for (var s = 1; s < symbols; s++) {
                    if (tally[s] > tally[best]) best = s;
                  }
                  return character(best);
                }(),
            ],
      ];

  /// Share of check-covered positions where `lines` differ from the consensus.
  double? disagreement(List<List<int>?> lines) {
    final consensus = this.consensus;
    var compared = 0, differing = 0;
    for (final index in format.protectedLines) {
      if (index >= lines.length) continue;
      final mine = lines[index], theirs = consensus[index];
      if (mine == null || theirs == null) continue;
      for (var i = 0; i < math.min(mine.length, theirs.length); i++) {
        compared++;
        if (mine[i] != theirs[i]) differing++;
      }
    }
    return compared == 0 ? null : differing / compared;
  }

  /// Recent reads that agree with `lines` on every check-covered line they
  /// read, within two characters a line.
  int supportingReads(List<List<int>> lines) => reads.where((read) {
        var compared = false;
        for (final index in format.protectedLines) {
          if (index >= read.length || index >= lines.length) continue;
          final mine = read[index];
          if (mine == null) continue;
          compared = true;
          var differences = 0;
          for (var i = 0; i < math.min(mine.length, lines[index].length); i++) {
            if (mine[i] != lines[index][i]) differences++;
          }
          if (differences > 2) return false;
        }
        return compared;
      }).length;
}

// ── What one frame read ─────────────────────────────────────────────────────

/// A normalized box, origin bottom-left (Vision's convention, kept on Android
/// too so both platforms share these rules unchanged).
class TextBox {
  const TextBox(this.minX, this.minY, this.maxX, this.maxY);
  const TextBox.fromSize(double x, double y, double width, double height)
      : this(x, y, x + width, y + height);

  final double minX;
  final double minY;
  final double maxX;
  final double maxY;

  double get width => maxX - minX;
  double get height => maxY - minY;
  double get midX => (minX + maxX) / 2;
  double get midY => (minY + maxY) / 2;

  TextBox union(TextBox other) => TextBox(math.min(minX, other.minX), math.min(minY, other.minY),
      math.max(maxX, other.maxX), math.max(maxY, other.maxY));

  @override
  bool operator ==(Object other) =>
      other is TextBox && other.minX == minX && other.minY == minY && other.maxX == maxX && other.maxY == maxY;

  @override
  int get hashCode => Object.hash(minX, minY, maxX, maxY);

  @override
  String toString() => 'TextBox($minX, $minY, $maxX, $maxY)';
}

/// One piece of text a frame read: its readings, best first, and where it is.
class ScanTextObservation {
  ScanTextObservation({required List<String> candidates, required this.box, required this.pageBox})
      : candidates = List.unmodifiable(candidates.take(3));

  /// The page box from the reading box when the crop was only turned.
  factory ScanTextObservation.turned({required List<String> candidates, required TextBox box, required int quarterTurns}) =>
      ScanTextObservation(candidates: candidates, box: box, pageBox: ScanQuarterTurn.undoBox(quarterTurns, box));

  final List<String> candidates;

  /// Normalized in the image that was read, origin bottom-left.
  final TextBox box;

  /// The same box in the unturned page crop, normalized, origin bottom-left.
  final TextBox pageBox;
}

/// Everything one live read saw, before any judgement.
class ScanTextFrame {
  ScanTextFrame({
    required List<ScanTextObservation> lines,
    List<ScanTextObservation> regions = const [],
    required int quarterTurns,
    required this.page,
    required this.readingWidth,
    required this.readingHeight,
  })  : lines = List.unmodifiable(lines.take(maximumLines)),
        regions = List.unmodifiable(regions.take(maximumRegions)),
        quarterTurns = ScanQuarterTurn.normalized(quarterTurns);

  static const maximumLines = 120;
  static const maximumRegions = 200;

  final List<ScanTextObservation> lines;

  /// Text found without being read (any script).
  final List<ScanTextObservation> regions;

  /// The page crop was turned counterclockwise this many quarter turns before it was read.
  final int quarterTurns;

  /// The page's corners in the crop, normalized, origin bottom-left.
  final List<math.Point<double>> page;

  /// Pixel size of the image that was read.
  final double readingWidth;
  final double readingHeight;
}

/// Quarter turns of a normalized image, origin bottom-left, counterclockwise.
abstract final class ScanQuarterTurn {
  static int normalized(int turns) => ((turns % 4) + 4) % 4;

  static math.Point<double> apply(int turns, math.Point<double> p) => switch (normalized(turns)) {
        1 => math.Point(1 - p.y, p.x),
        2 => math.Point(1 - p.x, 1 - p.y),
        3 => math.Point(p.y, 1 - p.x),
        _ => p,
      };

  static math.Point<double> undo(int turns, math.Point<double> p) => apply(4 - normalized(turns), p);

  static TextBox undoBox(int turns, TextBox box) {
    final a = undo(turns, math.Point(box.minX, box.minY));
    final b = undo(turns, math.Point(box.maxX, box.maxY));
    return TextBox(math.min(a.x, b.x), math.min(a.y, b.y), math.max(a.x, b.x), math.max(a.y, b.y));
  }
}

/// Which way the next read holds the page.
class ScanTextTurnPolicy {
  /// Passports and cards are read long side across, upright or upside down.
  const ScanTextTurnPolicy.landscape({required bool upsideDown})
      : _landscape = true,
        _upsideDown = upsideDown,
        _turns = 0;

  /// Other papers are read as seen, or turned this many quarter turns.
  const ScanTextTurnPolicy.fixed(int turns)
      : _landscape = false,
        _upsideDown = false,
        _turns = turns;

  final bool _landscape;
  final bool _upsideDown;
  final int _turns;

  bool get isLandscape => _landscape;
  bool get upsideDown => _upsideDown;

  int quarterTurns(double width, double height) =>
      _landscape ? (width >= height ? 0 : 1) + (_upsideDown ? 2 : 0) : ScanQuarterTurn.normalized(_turns);

  @override
  bool operator ==(Object other) =>
      other is ScanTextTurnPolicy && other._landscape == _landscape &&
      other._upsideDown == _upsideDown && ScanQuarterTurn.normalized(other._turns) == ScanQuarterTurn.normalized(_turns);

  @override
  int get hashCode => Object.hash(_landscape, _upsideDown, ScanQuarterTurn.normalized(_turns));

  @override
  String toString() => _landscape ? 'landscape(upsideDown: $_upsideDown)' : 'fixed($_turns)';
}

abstract final class ScanTextGeometry {
  /// The page is read with a margin, so text that runs past its edge shows.
  static const cropExpansion = 0.10;

  static TextBox? bounds(List<math.Point<double>> points) {
    if (points.isEmpty) return null;
    final minX = points.map((p) => p.x).reduce(math.min), maxX = points.map((p) => p.x).reduce(math.max);
    final minY = points.map((p) => p.y).reduce(math.min), maxY = points.map((p) => p.y).reduce(math.max);
    return maxX > minX && maxY > minY ? TextBox(minX, minY, maxX, maxY) : null;
  }

  /// Share of `box` that lies inside `area`.
  static double overlapShare(TextBox box, TextBox area) {
    final width = math.max(0.0, math.min(box.maxX, area.maxX) - math.max(box.minX, area.minX));
    final height = math.max(0.0, math.min(box.maxY, area.maxY) - math.max(box.minY, area.minY));
    final own = box.width * box.height;
    return own > 0 ? width * height / own : 0;
  }

  /// How far `box` reaches past `area`, as a share of the area's size.
  static double overhang(TextBox box, TextBox area) {
    if (area.width <= 0 || area.height <= 0) return 0;
    final horizontal = math.max(0.0, math.max(area.minX - box.minX, box.maxX - area.maxX)) / area.width;
    final vertical = math.max(0.0, math.max(area.minY - box.minY, box.maxY - area.maxY)) / area.height;
    return math.max(horizontal, vertical);
  }

  /// Text that reaches the crop's border goes on beyond what was read.
  static bool touchesBorder(TextBox box, {double margin = 0.006}) =>
      box.minX <= margin || box.minY <= margin || box.maxX >= 1 - margin || box.maxY >= 1 - margin;
}

/// A row of text that looks like machine-readable characters.
class ScanMachineRow {
  const ScanMachineRow(this.texts, this.box, this.pageBox);

  /// Readings in the MRZ alphabet, best first.
  final List<List<int>> texts;
  final TextBox box;
  final TextBox pageBox;
}

int _topFirst(TextBox a, TextBox b) {
  final vertical = b.midY.compareTo(a.midY);
  return vertical != 0 ? vertical : a.minX.compareTo(b.minX);
}

abstract final class ScanMrzReader {
  /// Rows of machine-like text, top first. Pieces of one row are joined.
  static List<ScanMachineRow> machineRows(List<ScanTextObservation> lines) {
    final sorted = lines
        .where((line) => line.candidates.isNotEmpty && line.box.width > 0 && line.box.height > 0)
        .toList()
      ..sort((a, b) => _topFirst(a.box, b.box));
    final groups = <List<ScanTextObservation>>[];
    for (final line in sorted) {
      if (groups.isNotEmpty && _belongsToRow(line, groups.last)) {
        groups.last.add(line);
      } else {
        groups.add([line]);
      }
    }
    final rows = <ScanMachineRow>[];
    for (final group in groups) {
      final members = List.of(group)..sort((a, b) => a.box.minX.compareTo(b.box.minX));
      List<List<int>> texts;
      int dropped;
      if (members.length == 1) {
        final readings = members.first.candidates.map(ScanMrz.normalize).toList();
        texts = [for (final reading in readings) reading.characters];
        dropped = readings.isEmpty ? 0 : readings.first.dropped;
      } else {
        final readings = [for (final member in members) ScanMrz.normalize(member.candidates.first)];
        texts = [
          [for (final reading in readings) ...reading.characters],
        ];
        dropped = readings.fold(0, (sum, reading) => sum + reading.dropped);
      }
      if (texts.isEmpty) continue;
      final best = texts.first;
      if (best.length < 24 || dropped > math.max(2, best.length ~/ 8)) continue;
      final fillers = best.where((c) => c == ScanMrz.filler).length;
      final digits = best.where(ScanMrz.isDigit).length;
      if (fillers < 2 && digits * 3 < best.length) continue;
      final box = members.skip(1).fold(members.first.box, (TextBox all, member) => all.union(member.box));
      final pageBox = members.skip(1).fold(members.first.pageBox, (TextBox all, member) => all.union(member.pageBox));
      rows.add(ScanMachineRow(texts, box, pageBox));
    }
    return rows;
  }

  static bool _belongsToRow(ScanTextObservation line, List<ScanTextObservation> group) {
    final height = group.map((member) => member.box.height).reduce(math.max);
    final middle = group.map((member) => member.box.midY).reduce((a, b) => a + b) / group.length;
    if ((line.box.midY - middle).abs() > math.max(height, line.box.height) * 0.6) return false;
    return group.every((member) {
      final overlap = math.min(member.box.maxX, line.box.maxX) - math.max(member.box.minX, line.box.minX);
      return overlap <= math.min(member.box.width, line.box.width) * 0.3;
    });
  }

  static bool adjacent(ScanMachineRow upper, ScanMachineRow lower) {
    final height = math.max(upper.box.height, lower.box.height);
    final gap = upper.box.minY - lower.box.maxY;
    final overlap = math.min(upper.box.maxX, lower.box.maxX) - math.max(upper.box.minX, lower.box.minX);
    return gap >= -height * 0.5 && gap <= height * 2.5 &&
        overlap >= math.min(upper.box.width, lower.box.width) * 0.5;
  }

  /// A passport's lines in one frame: line two must pass two of its four
  /// check digits as read, or three after a length repair; line one, when
  /// the row above is read, must begin with P.
  static List<List<int>?>? td3(List<ScanMachineRow> rows) {
    final fields = ScanMrzFormat.td3.fields;
    int? bestIndex;
    List<int>? bestLine;
    var bestScore = -1;
    for (var index = 0; index < rows.length; index++) {
      for (final text in rows[index].texts) {
        for (final variant in ScanMrz.lengthVariants(text, 44)) {
          final line = ScanMrz.conform(variant, fields[1]);
          final score = ScanMrz.td3LineTwoScore(line);
          if (score < (text.length == 44 ? 2 : 3)) continue;
          if (score > bestScore) {
            bestIndex = index;
            bestLine = line;
            bestScore = score;
          }
        }
      }
    }
    if (bestIndex == null || bestLine == null) return null;
    List<int>? first;
    if (bestIndex > 0 && adjacent(rows[bestIndex - 1], rows[bestIndex])) {
      for (final text in rows[bestIndex - 1].texts) {
        final padded = ScanMrz.padded(text, 44);
        if (padded == null) continue;
        final line = ScanMrz.conform(padded, fields[0]);
        if (line[0] == 0x50 && ScanMrz.isLetter(line[5])) {
          first = line;
          break;
        }
      }
    }
    return [first, bestLine];
  }

  /// An ID card's lines in one frame, found from line two (its dates).
  static List<List<int>?>? td1(List<ScanMachineRow> rows) {
    final fields = ScanMrzFormat.td1.fields;
    int? bestIndex;
    List<int>? bestLine;
    var bestScore = -1;
    for (var index = 0; index < rows.length; index++) {
      for (final text in rows[index].texts) {
        for (final variant in ScanMrz.lengthVariants(text, 30)) {
          final line = ScanMrz.conform(variant, fields[1]);
          if (!ScanMrz.td1LineTwoShape(line)) continue;
          final score = ScanMrz.td1LineTwoScore(line);
          if (score < (text.length == 30 ? 1 : 2)) continue;
          if (score > bestScore) {
            bestIndex = index;
            bestLine = line;
            bestScore = score;
          }
        }
      }
    }
    if (bestIndex == null || bestLine == null) return null;
    List<int>? first;
    List<int>? third;
    if (bestIndex > 0 && adjacent(rows[bestIndex - 1], rows[bestIndex])) {
      first = _td1LineOne(rows[bestIndex - 1].texts, fields[0]);
    }
    if (bestIndex + 1 < rows.length && adjacent(rows[bestIndex], rows[bestIndex + 1])) {
      for (final text in rows[bestIndex + 1].texts) {
        final padded = ScanMrz.padded(text, 30);
        if (padded == null) continue;
        final line = ScanMrz.conform(padded, fields[2]);
        if (ScanMrz.isLetter(line[0])) {
          third = line;
          break;
        }
      }
    }
    return [first, bestLine, third];
  }

  static List<int>? _td1LineOne(List<List<int>> texts, List<ScanMrzField> fields) {
    for (final text in texts) {
      for (final variant in ScanMrz.lengthVariants(text, 30)) {
        final line = ScanMrz.conform(variant, fields);
        if (!_codes('IAC').contains(line[0])) continue;
        if (text.length == 30) return line;
        final extended = ScanMrz.extendedDocumentNumber(line);
        final numberPasses = extended != null
            ? ScanMrz.passes(extended.number, extended.check)
            : ScanMrz.passes(line.sublist(5, 14), line[14]);
        if (numberPasses) return line;
      }
    }
    return null;
  }
}

/// The front of an ID card: its number and the words printed on it.
abstract final class ScanCardFront {
  static const keywords = ['ROYAUME', 'MAROC', 'MOROCCO', 'NATIONALE', 'IDENTIT', 'TUNISIE', 'PUBLIQUE'];

  static bool hasKeyword(List<String> texts) => texts.any((text) {
        final upper = text.toUpperCase();
        return keywords.any(upper.contains);
      });

  /// Card numbers on the front: a Moroccan CIN (one or two letters, then
  /// five to seven digits) or eight digits (a Tunisian card).
  static List<String> numbers(List<String> texts) {
    final found = <String>[];
    for (final text in texts) {
      final tokens = text.toUpperCase().split(RegExp('[^A-Z0-9]+')).where((token) => token.isNotEmpty)
          .map((token) => token.codeUnits).toList();
      final candidates = [...tokens];
      for (var i = 0; i + 1 < tokens.length; i++) {
        final letters = tokens[i], digits = tokens[i + 1];
        if (letters.isNotEmpty && letters.length <= 2 && letters.every(ScanMrz.isLetter) &&
            digits.length >= 5 && digits.length <= 7 && digits.every(ScanMrz.isDigit)) {
          candidates.add([...letters, ...digits]);
        }
      }
      for (final candidate in candidates) {
        final number = cardNumber(candidate);
        if (number != null && !found.contains(number)) found.add(number);
      }
    }
    return found;
  }

  static String? cardNumber(List<int> token) {
    if (token.length < 6 || token.length > 9) return null;
    if (token.every(ScanMrz.isDigit)) return token.length == 8 ? String.fromCharCodes(token) : null;
    var prefix = 0;
    while (prefix < 2 && ScanMrz.isLetter(token[prefix])) {
      prefix++;
    }
    if (prefix < 1) return null;
    final rest = token.sublist(prefix).map(ScanMrz.digitLookAlike).toList();
    if (rest.length < 5 || rest.length > 7 || !rest.every(ScanMrz.isDigit)) return null;
    return String.fromCharCodes([...token.sublist(0, prefix), ...rest]);
  }
}

class ScanTextLayoutSummary {
  const ScanTextLayoutSummary({required this.textRows, required this.readableLines, required this.cutRows});

  /// Rows of text inside the page, read or only found.
  final int textRows;

  /// Read lines inside the page with at least four Latin letters.
  final int readableLines;

  /// Lines of text that run past the page's detected edge or the frame.
  final int cutRows;

  static const empty = ScanTextLayoutSummary(textRows: 0, readableLines: 0, cutRows: 0);
}

abstract final class ScanTextLayout {
  static const insideShare = 0.85;
  static const cutMinimumShare = 0.25;

  /// About half a character of a page's printed line.
  static const cutOverhang = 0.012;
  static const minimumRowWidth = 0.06;

  static ScanTextLayoutSummary summarize(List<ScanTextObservation> lines,
      List<ScanTextObservation> regions, List<math.Point<double>> page) {
    final pageBounds = ScanTextGeometry.bounds(page);
    if (pageBounds == null) return ScanTextLayoutSummary.empty;
    final inside = <TextBox>[];
    var readable = 0;
    var cut = 0;
    for (final element in [...lines, ...regions]) {
      final share = ScanTextGeometry.overlapShare(element.pageBox, pageBounds);
      // Text partly on the page that reaches past its edge, or to the frame,
      // goes on where the camera cannot see it. A sliver past the edge is the
      // outline's own jitter.
      final runsOff = ScanTextGeometry.overhang(element.pageBox, pageBounds) >= cutOverhang ||
          ScanTextGeometry.touchesBorder(element.pageBox);
      if (share >= cutMinimumShare && runsOff && isLineLike(element)) {
        cut++;
      } else if (share >= insideShare) {
        inside.add(element.box);
        if (element.candidates.isNotEmpty && letters(element.candidates.first) >= 4) readable++;
      }
    }
    return ScanTextLayoutSummary(textRows: rows(inside), readableLines: readable, cutRows: cut);
  }

  static int letters(String text) =>
      text.codeUnits.where((c) => (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A)).length;

  /// Read text of three characters or more, or a found region shaped like a word.
  static bool isLineLike(ScanTextObservation element) {
    if (element.candidates.isNotEmpty) {
      return element.candidates.first.replaceAll(RegExp(r'\s'), '').runes.length >= 3;
    }
    return element.box.width >= element.box.height * 1.5;
  }

  /// Boxes that share most of their height make one row.
  static int rows(List<TextBox> boxes) {
    final sorted = boxes.where((box) => box.height > 0).toList()..sort(_topFirst);
    final rows = <TextBox>[];
    for (final box in sorted) {
      if (rows.isNotEmpty) {
        final last = rows.last;
        final overlap = math.min(last.maxY, box.maxY) - math.max(last.minY, box.minY);
        if (overlap >= math.min(last.height, box.height) * 0.5) {
          rows[rows.length - 1] = last.union(box);
          continue;
        }
      }
      rows.add(box);
    }
    return rows.where((row) => row.width >= minimumRowWidth).length;
  }
}

/// What one frame says, in the terms the gate decides on.
class ScanTextFrameSummary {
  const ScanTextFrameSummary({
    required this.quarterTurns,
    required this.td3,
    required this.td1,
    required this.machineRows,
    required this.machineRowHeight,
    required this.machineRowsCut,
    required this.layout,
    required this.cardNumbers,
    required this.cardKeyword,
    required this.pageLongSide,
    required this.lines,
  });

  final int quarterTurns;
  final List<List<int>?>? td3;
  final List<List<int>?>? td1;
  final int machineRows;

  /// Median height of the machine-like rows, in pixels of the image read.
  final double? machineRowHeight;
  final bool machineRowsCut;
  final ScanTextLayoutSummary layout;
  final List<String> cardNumbers;
  final bool cardKeyword;

  /// The page's long side, in pixels of the image read.
  final double pageLongSide;

  /// Read lines inside the page, top first, cleaned and bounded.
  final List<String> lines;
}

abstract final class ScanTextFrameAnalysis {
  static const maximumLines = 24;
  static const maximumLineLength = 120;

  static ScanTextFrameSummary summarize(ScanTextFrame frame) {
    final rows = ScanMrzReader.machineRows(frame.lines);
    final pageBounds = ScanTextGeometry.bounds(frame.page);
    final heights = rows.map((row) => row.box.height * frame.readingHeight).toList()..sort();
    final insideLines = frame.lines
        .where((line) => pageBounds != null && ScanTextGeometry.overlapShare(line.pageBox, pageBounds) >= 0.5)
        .toList()
      ..sort((a, b) {
        final vertical = b.box.maxY.compareTo(a.box.maxY);
        return vertical != 0 ? vertical : a.box.minX.compareTo(b.box.minX);
      });
    final texts = [for (final line in insideLines) if (line.candidates.isNotEmpty) line.candidates.first];
    final cut = rows.any((row) =>
        ScanTextGeometry.touchesBorder(row.pageBox) ||
        (pageBounds != null && ScanTextGeometry.overhang(row.pageBox, pageBounds) >= ScanTextLayout.cutOverhang));
    return ScanTextFrameSummary(
      quarterTurns: frame.quarterTurns,
      td3: ScanMrzReader.td3(rows),
      td1: ScanMrzReader.td1(rows),
      machineRows: rows.length,
      machineRowHeight: heights.isEmpty ? null : heights[heights.length ~/ 2],
      machineRowsCut: cut,
      layout: ScanTextLayout.summarize(frame.lines, frame.regions, frame.page),
      cardNumbers: ScanCardFront.numbers(texts),
      cardKeyword: ScanCardFront.hasKeyword(texts),
      pageLongSide: math.max(frame.readingWidth, frame.readingHeight) / (1 + ScanTextGeometry.cropExpansion),
      lines: texts.map(clean).whereType<String>().take(maximumLines).toList(),
    );
  }

  /// One line for the portal: no control characters, single spaces, bounded.
  static String? clean(String text) {
    final words = text
        // Control and format characters (Cc, Cf: tabs, RTL marks), as the
        // iPhone's CharacterSet.controlCharacters.
        .replaceAll(RegExp(r'[\p{Cc}\p{Cf}]', unicode: true), ' ')
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .join(' ');
    final line = String.fromCharCodes(words.runes.take(maximumLineLength));
    return line.isEmpty ? null : line;
  }
}

// ── The right-document gate ─────────────────────────────────────────────────

class ScanTextCopy {
  const ScanTextCopy(this.title, this.detail, this.compact);
  final String title;
  final String detail;

  /// Shown instead of the detail when space is short.
  final String compact;
}

enum ScanTextGuidance {
  reading,
  showMachineLines,
  moveCloserMachineLines,
  glareOnMachineLines,
  showWholeMachineLines,
  differentPaper,
  turnCardToFront,
  turnCardToBack,
  showCardDetails,
  glareOnText,
  moveCloserText,
  showPrintedText,
  textRunsPastEdge;

  /// Holding still is what helps now.
  bool get asksToHold => this == ScanTextGuidance.reading;

  /// The reading saw the wrong paper, or the wrong side of a card: the student
  /// has to act, so a clear page is not taken for it. Every other guidance is
  /// the reading still looking, which a clear page does not wait on for long.
  bool get holdsCapture => this == ScanTextGuidance.differentPaper ||
      this == ScanTextGuidance.turnCardToFront || this == ScanTextGuidance.turnCardToBack;

  /// What the camera says while it reads, in [language].
  ScanTextCopy copy(ScanPaperKind kind,
          [AppLanguage language = AppLanguage.en]) =>
      switch (language) {
        AppLanguage.en => _english(kind),
        AppLanguage.fr => _french(kind),
        AppLanguage.ar => _arabic(kind),
      };

  ScanTextCopy _english(ScanPaperKind kind) => switch (this) {
        ScanTextGuidance.reading => switch (kind) {
            ScanPaperKind.passport => const ScanTextCopy('Hold still', 'Reading the two lines at the bottom…', 'Reading…'),
            ScanPaperKind.idCard => const ScanTextCopy('Hold still', 'Reading the card…', 'Reading…'),
            ScanPaperKind.paper => const ScanTextCopy('Hold still', 'Reading the page…', 'Reading…'),
          },
        ScanTextGuidance.showMachineLines => kind == ScanPaperKind.idCard
            ? const ScanTextCopy('Show the back of the card',
                'Show the back with the three lines at the bottom.', 'Three bottom lines.')
            : const ScanTextCopy('Show the photo page',
                'Show the photo page with the two lines at the bottom.', 'Two bottom lines.'),
        ScanTextGuidance.moveCloserMachineLines => ScanTextCopy(
            'Move closer',
            kind == ScanPaperKind.idCard
                ? 'Move closer — the lines on the card are too small.'
                : 'Move closer — the bottom lines are too small.',
            'Move closer.'),
        ScanTextGuidance.glareOnMachineLines => const ScanTextCopy('Glare on the bottom lines',
            'Tilt the page slightly to move the reflection.', 'Tilt slightly.'),
        ScanTextGuidance.showWholeMachineLines => kind == ScanPaperKind.idCard
            ? const ScanTextCopy('Show the three bottom lines',
                'Keep the three lines on the back of the card fully in view.', 'All three lines.')
            : const ScanTextCopy('Show both bottom lines',
                'Keep the two lines at the bottom of the photo page fully in view.', 'Both bottom lines.'),
        ScanTextGuidance.differentPaper => ScanTextCopy(
            'This looks like a different paper',
            switch (kind) {
              ScanPaperKind.passport => 'Show your passport’s photo page.',
              ScanPaperKind.idCard => 'Show the ID card.',
              ScanPaperKind.paper => 'Show the paper this step asks for.',
            },
            'Different paper.'),
        ScanTextGuidance.turnCardToFront =>
          const ScanTextCopy('Turn the card over', 'Show the front of the card, with the photo.', 'Show the front.'),
        ScanTextGuidance.turnCardToBack => const ScanTextCopy(
            'Turn the card over', 'Show the back of the card, with the lines at the bottom.', 'Show the back.'),
        ScanTextGuidance.showCardDetails =>
          const ScanTextCopy('Show the card', 'Keep the card’s printed details in view.', 'Card details.'),
        ScanTextGuidance.glareOnText =>
          const ScanTextCopy('Glare on the card', 'Tilt the card slightly to move the reflection.', 'Tilt slightly.'),
        ScanTextGuidance.moveCloserText =>
          const ScanTextCopy('Move closer', 'Move closer so the text is readable.', 'Move closer.'),
        ScanTextGuidance.showPrintedText =>
          const ScanTextCopy('Show the printed side', 'Show the side of the page with the text.', 'Printed side.'),
        ScanTextGuidance.textRunsPastEdge => const ScanTextCopy(
            'Show the whole page', 'Some text runs past the edge. Fit all of it in view.', 'Whole page.'),
      };

  ScanTextCopy _french(ScanPaperKind kind) => switch (this) {
        ScanTextGuidance.reading => switch (kind) {
            ScanPaperKind.passport => const ScanTextCopy('Ne bougez plus',
                'Lecture des deux lignes du bas…', 'Lecture…'),
            ScanPaperKind.idCard => const ScanTextCopy(
                'Ne bougez plus', 'Lecture de la carte…', 'Lecture…'),
            ScanPaperKind.paper => const ScanTextCopy(
                'Ne bougez plus', 'Lecture de la page…', 'Lecture…'),
          },
        ScanTextGuidance.showMachineLines => kind == ScanPaperKind.idCard
            ? const ScanTextCopy('Montrez le verso de la carte',
                'Montrez le verso, avec les trois lignes du bas.',
                'Trois lignes du bas.')
            : const ScanTextCopy('Montrez la page de la photo',
                'Montrez la page de la photo, avec les deux lignes du bas.',
                'Deux lignes du bas.'),
        ScanTextGuidance.moveCloserMachineLines => ScanTextCopy(
            'Rapprochez-vous',
            kind == ScanPaperKind.idCard
                ? 'Rapprochez-vous, les lignes de la carte sont trop petites.'
                : 'Rapprochez-vous, les lignes du bas sont trop petites.',
            'Rapprochez-vous.'),
        ScanTextGuidance.glareOnMachineLines => const ScanTextCopy(
            'Reflet sur les lignes du bas',
            'Inclinez légèrement la page pour déplacer le reflet.',
            'Inclinez légèrement.'),
        ScanTextGuidance.showWholeMachineLines => kind == ScanPaperKind.idCard
            ? const ScanTextCopy('Montrez les trois lignes du bas',
                'Gardez entièrement visibles les trois lignes au verso de la carte.',
                'Les trois lignes.')
            : const ScanTextCopy('Montrez les deux lignes du bas',
                'Gardez entièrement visibles les deux lignes en bas de la page de la photo.',
                'Les deux lignes.'),
        ScanTextGuidance.differentPaper => ScanTextCopy(
            'Ce document semble différent',
            switch (kind) {
              ScanPaperKind.passport =>
                'Montrez la page de votre passeport avec la photo.',
              ScanPaperKind.idCard => 'Montrez la carte d’identité.',
              ScanPaperKind.paper => 'Montrez le document demandé à cette étape.',
            },
            'Autre document.'),
        ScanTextGuidance.turnCardToFront => const ScanTextCopy(
            'Retournez la carte',
            'Montrez le recto de la carte, avec la photo.',
            'Montrez le recto.'),
        ScanTextGuidance.turnCardToBack => const ScanTextCopy(
            'Retournez la carte',
            'Montrez le verso de la carte, avec les lignes du bas.',
            'Montrez le verso.'),
        ScanTextGuidance.showCardDetails => const ScanTextCopy(
            'Montrez la carte',
            'Gardez visibles les informations imprimées de la carte.',
            'Infos de la carte.'),
        ScanTextGuidance.glareOnText => const ScanTextCopy(
            'Reflet sur la carte',
            'Inclinez légèrement la carte pour déplacer le reflet.',
            'Inclinez légèrement.'),
        ScanTextGuidance.moveCloserText => const ScanTextCopy(
            'Rapprochez-vous',
            'Rapprochez-vous pour que le texte soit lisible.',
            'Rapprochez-vous.'),
        ScanTextGuidance.showPrintedText => const ScanTextCopy(
            'Montrez la face imprimée',
            'Montrez le côté de la page où se trouve le texte.',
            'Face imprimée.'),
        ScanTextGuidance.textRunsPastEdge => const ScanTextCopy(
            'Montrez toute la page',
            'Une partie du texte dépasse du cadre. Faites-la entrer entièrement.',
            'Toute la page.'),
      };

  ScanTextCopy _arabic(ScanPaperKind kind) => switch (this) {
        ScanTextGuidance.reading => switch (kind) {
            ScanPaperKind.passport => const ScanTextCopy(
                'ثبّت الهاتف', 'جارٍ قراءة السطرين في الأسفل…', 'جارٍ القراءة…'),
            ScanPaperKind.idCard => const ScanTextCopy(
                'ثبّت الهاتف', 'جارٍ قراءة البطاقة…', 'جارٍ القراءة…'),
            ScanPaperKind.paper => const ScanTextCopy(
                'ثبّت الهاتف', 'جارٍ قراءة الصفحة…', 'جارٍ القراءة…'),
          },
        ScanTextGuidance.showMachineLines => kind == ScanPaperKind.idCard
            ? const ScanTextCopy('أظهر ظهر البطاقة',
                'أظهر ظهر البطاقة مع الأسطر الثلاثة في الأسفل.',
                'الأسطر الثلاثة في الأسفل.')
            : const ScanTextCopy('أظهر صفحة الصورة',
                'أظهر صفحة الصورة مع السطرين في الأسفل.',
                'السطران في الأسفل.'),
        ScanTextGuidance.moveCloserMachineLines => ScanTextCopy(
            'اقترب أكثر',
            kind == ScanPaperKind.idCard
                ? 'اقترب أكثر، فأسطر البطاقة صغيرة جدًا.'
                : 'اقترب أكثر، فالأسطر في الأسفل صغيرة جدًا.',
            'اقترب أكثر.'),
        ScanTextGuidance.glareOnMachineLines => const ScanTextCopy(
            'انعكاس على الأسطر في الأسفل',
            'أمِل الصفحة قليلًا لإبعاد الانعكاس.',
            'أمِلها قليلًا.'),
        ScanTextGuidance.showWholeMachineLines => kind == ScanPaperKind.idCard
            ? const ScanTextCopy('أظهر الأسطر الثلاثة في الأسفل',
                'اجعل الأسطر الثلاثة على ظهر البطاقة ظاهرة كاملة.',
                'الأسطر الثلاثة كاملة.')
            : const ScanTextCopy('أظهر السطرين في الأسفل',
                'اجعل السطرين أسفل صفحة الصورة ظاهرين كاملين.',
                'السطران كاملان.'),
        ScanTextGuidance.differentPaper => ScanTextCopy(
            'يبدو أنها وثيقة أخرى',
            switch (kind) {
              ScanPaperKind.passport => 'أظهر صفحة الصورة في جواز سفرك.',
              ScanPaperKind.idCard => 'أظهر بطاقة التعريف.',
              ScanPaperKind.paper =>
                'أظهر الوثيقة المطلوبة في هذه الخطوة.',
            },
            'وثيقة أخرى.'),
        ScanTextGuidance.turnCardToFront => const ScanTextCopy(
            'اقلب البطاقة', 'أظهر وجه البطاقة الذي فيه الصورة.', 'أظهر الوجه.'),
        ScanTextGuidance.turnCardToBack => const ScanTextCopy('اقلب البطاقة',
            'أظهر ظهر البطاقة مع الأسطر في الأسفل.', 'أظهر الظهر.'),
        ScanTextGuidance.showCardDetails => const ScanTextCopy('أظهر البطاقة',
            'اجعل البيانات المطبوعة على البطاقة ظاهرة.', 'بيانات البطاقة.'),
        ScanTextGuidance.glareOnText => const ScanTextCopy(
            'انعكاس على البطاقة',
            'أمِل البطاقة قليلًا لإبعاد الانعكاس.',
            'أمِلها قليلًا.'),
        ScanTextGuidance.moveCloserText => const ScanTextCopy('اقترب أكثر',
            'اقترب أكثر ليصبح النص مقروءًا.', 'اقترب أكثر.'),
        ScanTextGuidance.showPrintedText => const ScanTextCopy(
            'أظهر الوجه المطبوع',
            'أظهر وجه الصفحة الذي فيه النص.',
            'الوجه المطبوع.'),
        ScanTextGuidance.textRunsPastEdge => const ScanTextCopy(
            'أظهر الصفحة كاملة',
            'جزء من النص خارج الإطار. أدخله كله في الإطار.',
            'الصفحة كاملة.'),
      };
}

class ScanTextGateStatus {
  const ScanTextGateStatus({required this.passed, required this.allowsCapture, this.guidance});

  const ScanTextGateStatus.waiting(ScanTextGuidance this.guidance)
      : passed = false,
        allowsCapture = false;

  static const passedReading = ScanTextGateStatus(passed: true, allowsCapture: true);
  static const cannotRead = ScanTextGateStatus(passed: false, allowsCapture: true);

  /// The reading says this is the paper the step asked for.
  final bool passed;

  /// Automatic capture may go ahead: the reading passed, or this phone cannot read text at all.
  final bool allowsCapture;
  final ScanTextGuidance? guidance;

  /// How long a clear, steady page waits for the reading before it is taken
  /// anyway (the owner, 30 Oct 2026: "it should be automatic once the shot is
  /// clear"). A passport or a card gives the reading of its lines a little
  /// longer: those lines fill the student's details when the server's reader
  /// cannot answer.
  static Duration clearPageGrace(ScanPaperKind kind) => kind == ScanPaperKind.paper
      ? const Duration(milliseconds: 800) : const Duration(milliseconds: 1500);

  /// Whether a page that has been clear and steady for [clearFor] is taken
  /// now: at once when the reading passed (or the phone cannot read), once the
  /// grace is over while the reading is still looking, and never while it has
  /// seen the wrong paper or the wrong side of a card (the shutter is there for
  /// that).
  bool capturesWhenClear(Duration clearFor, ScanPaperKind kind) {
    if (allowsCapture) return true;
    if (guidance?.holdsCapture == true) return false;
    return clearFor >= clearPageGrace(kind);
  }

  @override
  bool operator ==(Object other) =>
      other is ScanTextGateStatus && other.passed == passed &&
      other.allowsCapture == allowsCapture && other.guidance == guidance;

  @override
  int get hashCode => Object.hash(passed, allowsCapture, guidance);

  @override
  String toString() => 'ScanTextGateStatus(passed: $passed, allowsCapture: $allowsCapture, guidance: $guidance)';
}

/// A page in one preview frame, for [ScanAutoShutter].
enum ScanShutterPage {
  /// No page found in this frame.
  missing,

  /// A page found, not (yet) steady or sharp enough to count toward the hold.
  inView,

  /// The hold is complete.
  steady,
}

/// When a page in view is taken with no tap (the owner, 30 Oct 2026: "it should be automatic
/// once the shot is clear"; on build 54 it still needed the button). Build 54 took a page only
/// after an unbroken run of clear, steady frames: one soft frame, a tremor of the hand or a dim
/// room started the wait over, and the shutter appeared before it ended. Frame by frame, the
/// first way in that is due wins:
/// - steady and read: the hold is complete and the reading passed (or this phone cannot read);
/// - steady: the hold has been complete for the paper's grace ([ScanTextGateStatus.clearPageGrace]),
///   counted from the first time it was, through any frame missed since;
/// - in view: a page has been in view for [inViewLimit], steady or not, sharp or not.
/// Never while the reading has seen the wrong paper or the wrong side of a card: the shutter is
/// there for that. The clocks start over once the page has been out of view for [pageLossReset].
/// The same rule as the iPhone's ScannerAutoShutter (ScannerTextReading.swift).
class ScanAutoShutter {
  static const pageLossReset = Duration(milliseconds: 800);

  /// A page in shadow, glare or dim light has this long to be fixed before it is taken anyway:
  /// a slightly shadowed page beats no page.
  static const lightingGrace = Duration(milliseconds: 1500);

  /// How long a page stays in view before it is taken, steady or not.
  static Duration inViewLimit(ScanPaperKind kind) => kind == ScanPaperKind.paper
      ? const Duration(milliseconds: 2500) : const Duration(milliseconds: 3500);

  DateTime? _inViewSince;
  DateTime? _steadySince;
  DateTime? _lastSeen;

  DateTime? get inViewSince => _inViewSince;
  DateTime? get steadySince => _steadySince;

  /// How long the page has been steady, through any frame missed since; zero before it ever was.
  Duration steadyFor(DateTime now) {
    final since = _steadySince;
    if (since == null || now.isBefore(since)) return Duration.zero;
    return now.difference(since);
  }

  /// One preview frame. True when the page in it is to be taken now.
  bool observe(ScanShutterPage page, DateTime now,
      {required ScanTextGateStatus reading, required ScanPaperKind kind, required bool lightingGood}) {
    if (page == ScanShutterPage.missing) {
      final last = _lastSeen;
      if (last != null && now.difference(last) >= pageLossReset) reset();
      return false;
    }
    _lastSeen = now;
    _inViewSince ??= now;
    if (page == ScanShutterPage.steady) _steadySince ??= now;
    if (reading.guidance?.holdsCapture == true) return false;
    if (page == ScanShutterPage.steady) {
      final steady = steadyFor(now);
      if ((lightingGood || steady >= lightingGrace) && reading.capturesWhenClear(steady, kind)) return true;
    }
    return now.difference(_inViewSince!) >= inViewLimit(kind);
  }

  void reset() {
    _inViewSince = null;
    _steadySince = null;
    _lastSeen = null;
  }
}

/// The reading of one page while it is in view, and the gate on automatic
/// capture: steady is not enough, the paper must also be the right one.
class ScanTextReadingSession {
  ScanTextReadingSession({required this.kind, ScanCardSide? side, bool rejectsIdentityPapers = false})
      : side = kind == ScanPaperKind.idCard ? side : null,
        rejectsIdentityPapers = kind == ScanPaperKind.paper && rejectsIdentityPapers,
        _turnPolicy = initialPolicy(kind);

  factory ScanTextReadingSession.forProfile(GuidedDocumentProfile profile) => ScanTextReadingSession(
      kind: profile.paperKind, side: profile.cardSide, rejectsIdentityPapers: profile.rejectsIdentityPapers);

  static const requiredSupportingReads = 2;
  static const pageLossReset = Duration(milliseconds: 1500);
  static const pageJumpReset = 0.2;
  static const readerFailureLimit = 4;
  static const disagreementReset = 0.3;
  static const minimumPaperRows = 3;

  /// Machine lines shorter than this, in pixels, are too small to read live.
  static const minimumMachineRowHeight = 14.0;
  static const paperTurns = [0, 1, 3];

  /// Below this long side, in pixels of the image read, the print is too small.
  static double minimumPageSide(ScanPaperKind kind) => switch (kind) {
        ScanPaperKind.passport => 800,
        ScanPaperKind.idCard => 560,
        ScanPaperKind.paper => 900,
      };

  static ScanTextTurnPolicy initialPolicy(ScanPaperKind kind) => kind == ScanPaperKind.paper
      ? ScanTextTurnPolicy.fixed(paperTurns.first)
      : const ScanTextTurnPolicy.landscape(upsideDown: false);

  final ScanPaperKind kind;
  final ScanCardSide? side;
  final bool rejectsIdentityPapers;

  int _framesRead = 0;
  bool _readerUnavailable = false;
  ScanTextTurnPolicy _turnPolicy;
  ScanTextFrameSummary? _latest;
  ScanTextFrameSummary? _previous;
  int _consecutiveFailures = 0;
  ScanMrzVotes _td3Votes = ScanMrzVotes(ScanMrzFormat.td3);
  ScanMrzVotes _td1Votes = ScanMrzVotes(ScanMrzFormat.td1);
  int _readsWithText = 0;
  int _readsWithoutText = 0;
  int _readsWithoutMachineRows = 0;
  final Map<String, int> _cardNumberCounts = {};
  bool _cardKeywordSeen = false;
  bool _turnLocked = false;
  int _paperTurnIndex = 0;
  final Map<int, int> _paperTurnScores = {};
  Rect? _lastPage;
  DateTime? _pageMissingSince;

  int get framesRead => _framesRead;
  bool get readerUnavailable => _readerUnavailable;
  ScanTextTurnPolicy get turnPolicy => _turnPolicy;
  ScanTextFrameSummary? get latest => _latest;

  /// Starts the reading over, for another page. Whether this phone can read
  /// text at all is kept.
  void reset() {
    _framesRead = 0;
    _turnPolicy = initialPolicy(kind);
    _latest = null;
    _previous = null;
    _td3Votes = ScanMrzVotes(ScanMrzFormat.td3);
    _td1Votes = ScanMrzVotes(ScanMrzFormat.td1);
    _readsWithText = 0;
    _readsWithoutText = 0;
    _readsWithoutMachineRows = 0;
    _cardNumberCounts.clear();
    _cardKeywordSeen = false;
    _turnLocked = false;
    _paperTurnIndex = 0;
    _paperTurnScores.clear();
    _lastPage = null;
    _pageMissingSince = null;
  }

  /// Follows the page the reading belongs to (its normalized outline). A page
  /// gone for a moment or a jump to another outline starts the reading over;
  /// returns true then.
  bool observePage(Rect? page, DateTime time) {
    if (page == null) {
      _pageMissingSince ??= time;
      final since = _pageMissingSince!;
      if (time.difference(since) >= pageLossReset && (_framesRead > 0 || _lastPage != null)) {
        reset();
        return true;
      }
      return false;
    }
    _pageMissingSince = null;
    final last = _lastPage;
    _lastPage = page;
    if (last != null && _maximumCornerDistance(page, last) > pageJumpReset) {
      reset();
      _lastPage = page;
      return true;
    }
    return false;
  }

  static double _maximumCornerDistance(Rect a, Rect b) => [
        (a.topLeft - b.topLeft).distance,
        (a.topRight - b.topRight).distance,
        (a.bottomRight - b.bottomRight).distance,
        (a.bottomLeft - b.bottomLeft).distance,
      ].reduce(math.max);

  /// A read the text engine could not do at all. Several in a row mean this
  /// phone cannot read text, and automatic capture goes back to steadiness alone.
  void readFailed() {
    _consecutiveFailures++;
    if (_consecutiveFailures >= readerFailureLimit) _readerUnavailable = true;
  }

  /// No text engine on this phone (a build without one).
  void markReaderUnavailable() => _readerUnavailable = true;

  void ingest(ScanTextFrame frame) {
    _consecutiveFailures = 0;
    final summary = ScanTextFrameAnalysis.summarize(frame);
    _framesRead++;
    if (summary.td3 != null) _vote(summary.td3!, ScanMrzFormat.td3);
    if (summary.td1 != null) _vote(summary.td1!, ScanMrzFormat.td1);
    _previous = _latest;
    _latest = summary;
    if (summary.layout.textRows >= minimumPaperRows) {
      if (summary.layout.cutRows == 0) _readsWithText++;
      _readsWithoutText = 0;
    } else {
      _readsWithoutText++;
    }
    _readsWithoutMachineRows = summary.machineRows == 0 ? _readsWithoutMachineRows + 1 : 0;
    for (final number in summary.cardNumbers.toSet()) {
      _cardNumberCounts[number] = (_cardNumberCounts[number] ?? 0) + 1;
    }
    if (summary.cardKeyword) _cardKeywordSeen = true;
    _advanceTurn(summary);
  }

  void _vote(List<List<int>?> lines, ScanMrzFormat format) {
    var votes = format == ScanMrzFormat.td3 ? _td3Votes : _td1Votes;
    final disagreement = votes.disagreement(lines);
    if (votes.reads.length >= 2 && disagreement != null && disagreement > disagreementReset) {
      // Most of the checked characters changed: another paper.
      votes = ScanMrzVotes(format);
    }
    votes.add(lines);
    if (format == ScanMrzFormat.td3) {
      _td3Votes = votes;
    } else {
      _td1Votes = votes;
    }
  }

  void _advanceTurn(ScanTextFrameSummary summary) {
    if (_turnLocked) return;
    switch (kind) {
      case ScanPaperKind.passport:
      case ScanPaperKind.idCard:
        final found = summary.machineRows > 0 ||
            (kind == ScanPaperKind.idCard &&
                (summary.layout.readableLines >= 3 || summary.cardNumbers.isNotEmpty));
        if (found) {
          _turnLocked = true;
        } else if (_turnPolicy.isLandscape) {
          _turnPolicy = ScanTextTurnPolicy.landscape(upsideDown: !_turnPolicy.upsideDown);
        }
      case ScanPaperKind.paper:
        final turns = summary.quarterTurns;
        _paperTurnScores[turns] = math.max(_paperTurnScores[turns] ?? 0, summary.layout.readableLines);
        if (summary.layout.readableLines >= 3) {
          _turnLocked = true;
          _turnPolicy = ScanTextTurnPolicy.fixed(turns);
          return;
        }
        _paperTurnIndex++;
        if (_paperTurnIndex < paperTurns.length) {
          _turnPolicy = ScanTextTurnPolicy.fixed(paperTurns[_paperTurnIndex]);
          return;
        }
        // Nothing Latin read every way: keep the page as seen (Arabic, Chinese).
        _turnLocked = true;
        var best = paperTurns.first;
        for (final turns in paperTurns) {
          if ((_paperTurnScores[turns] ?? 0) > (_paperTurnScores[best] ?? 0)) best = turns;
        }
        _turnPolicy = ScanTextTurnPolicy.fixed(best);
    }
  }

  /// The consensus of a format's votes, repaired and checked, with the
  /// number of reads that agree with it.
  ({ScanMrzResult result, int supporting})? machineReading(ScanMrzFormat format) {
    final votes = format == ScanMrzFormat.td3 ? _td3Votes : _td1Votes;
    final consensus = votes.consensus;
    if (consensus.any((line) => line == null)) return null;
    final result = ScanMrzValidator.validate([for (final line in consensus) line!], format, tallies: votes.counts);
    return (result: result, supporting: votes.supportingReads(result.lines));
  }

  /// A valid reading that at least two reads agree with.
  ScanMrzResult? confirmed(ScanMrzFormat format) {
    final reading = machineReading(format);
    if (reading == null || !reading.result.valid || reading.supporting < requiredSupportingReads) return null;
    return reading.result;
  }

  /// The card number read on the front at least twice.
  String? get frontNumber {
    final seen = _cardNumberCounts.entries.where((entry) => entry.value >= requiredSupportingReads).toList()
      ..sort((a, b) => a.value != b.value ? b.value.compareTo(a.value) : a.key.compareTo(b.key));
    return seen.isEmpty ? null : seen.first.key;
  }

  bool get frontRead {
    final latest = _latest;
    if (frontNumber == null || latest == null) return false;
    return _cardKeywordSeen || latest.layout.readableLines >= 3 || latest.layout.textRows >= 5;
  }

  ScanTextGateStatus status({required bool glare}) {
    if (_readerUnavailable) return ScanTextGateStatus.cannotRead;
    final passport = confirmed(ScanMrzFormat.td3) != null;
    final card = confirmed(ScanMrzFormat.td1) != null;
    switch (kind) {
      case ScanPaperKind.passport:
        if (passport) return ScanTextGateStatus.passedReading;
        if (card) return const ScanTextGateStatus.waiting(ScanTextGuidance.differentPaper);
        return ScanTextGateStatus.waiting(_machineGuidance(glare));
      case ScanPaperKind.idCard:
        if (passport) return const ScanTextGateStatus.waiting(ScanTextGuidance.differentPaper);
        final front = frontRead;
        switch (side) {
          case ScanCardSide.back:
            if (card) return ScanTextGateStatus.passedReading;
            return ScanTextGateStatus.waiting(front ? ScanTextGuidance.turnCardToBack : _machineGuidance(glare));
          case ScanCardSide.front:
            if (front) return ScanTextGateStatus.passedReading;
            return ScanTextGateStatus.waiting(card ? ScanTextGuidance.turnCardToFront : _frontGuidance(glare));
          case null:
            if (card || front) return ScanTextGateStatus.passedReading;
            return ScanTextGateStatus.waiting(
                (_latest?.machineRows ?? 0) > 0 ? _machineGuidance(glare) : _frontGuidance(glare));
        }
      case ScanPaperKind.paper:
        if (rejectsIdentityPapers && (passport || card)) {
          return const ScanTextGateStatus.waiting(ScanTextGuidance.differentPaper);
        }
        return _paperStatus();
    }
  }

  ScanTextGuidance _machineGuidance(bool glare) {
    final latest = _latest;
    if (latest == null) return ScanTextGuidance.reading;
    if (latest.machineRows == 0) {
      if (latest.pageLongSide < minimumPageSide(kind)) return ScanTextGuidance.moveCloserMachineLines;
      if (_readsWithoutMachineRows < 2) return ScanTextGuidance.reading;
      return glare ? ScanTextGuidance.glareOnMachineLines : ScanTextGuidance.showMachineLines;
    }
    final height = latest.machineRowHeight;
    if (height != null && height < minimumMachineRowHeight) return ScanTextGuidance.moveCloserMachineLines;
    if (latest.machineRowsCut) return ScanTextGuidance.showWholeMachineLines;
    return glare ? ScanTextGuidance.glareOnMachineLines : ScanTextGuidance.reading;
  }

  ScanTextGuidance _frontGuidance(bool glare) {
    final latest = _latest;
    if (latest == null) return ScanTextGuidance.reading;
    if (latest.layout.readableLines < 3 && latest.pageLongSide < minimumPageSide(ScanPaperKind.idCard)) {
      return ScanTextGuidance.moveCloserText;
    }
    if (glare) return ScanTextGuidance.glareOnText;
    if (latest.layout.readableLines == 0 && latest.layout.textRows == 0 && _readsWithoutText >= 2) {
      return ScanTextGuidance.showCardDetails;
    }
    return ScanTextGuidance.reading;
  }

  ScanTextGateStatus _paperStatus() {
    final latest = _latest;
    if (latest == null) return const ScanTextGateStatus.waiting(ScanTextGuidance.reading);
    if (latest.layout.cutRows > 0) {
      return ScanTextGateStatus.waiting((_previous?.layout.cutRows ?? 0) > 0
          ? ScanTextGuidance.textRunsPastEdge
          : ScanTextGuidance.reading);
    }
    if (latest.layout.textRows >= minimumPaperRows) {
      return _readsWithText >= requiredSupportingReads
          ? ScanTextGateStatus.passedReading
          : const ScanTextGateStatus.waiting(ScanTextGuidance.reading);
    }
    if (latest.pageLongSide < minimumPageSide(ScanPaperKind.paper)) {
      return const ScanTextGateStatus.waiting(ScanTextGuidance.moveCloserText);
    }
    return ScanTextGateStatus.waiting(
        _readsWithoutText >= 2 ? ScanTextGuidance.showPrintedText : ScanTextGuidance.reading);
  }

  /// What was read, for the portal, returned only with the student's own
  /// capture of this paper. Bounded: machine lines, a few fields and at most
  /// 24 read lines of 120 characters.
  Map<String, Object> liveReading({required String engine, required bool matched, required int referenceYear}) {
    final reading = <String, Object>{
      'version': 1,
      'kind': kind.wireName,
      'matched': matched,
      'engine': engine,
      'frames': _framesRead,
      'mrzValid': false,
      'lines': List<String>.of(_latest?.lines ?? const []),
    };
    ScanMrzFormat? format = switch (kind) {
      ScanPaperKind.passport => ScanMrzFormat.td3,
      ScanPaperKind.idCard => ScanMrzFormat.td1,
      ScanPaperKind.paper => null,
    };
    // What the step asked for first; otherwise a confirmed other paper, so
    // the portal can see what was shown instead.
    if (format != null && machineReading(format) == null) format = null;
    format ??= confirmed(ScanMrzFormat.td3) != null
        ? ScanMrzFormat.td3
        : confirmed(ScanMrzFormat.td1) != null
            ? ScanMrzFormat.td1
            : null;
    final machine = format == null ? null : machineReading(format);
    if (format != null && machine != null) {
      reading['mrzFormat'] = format.wireName;
      reading['mrz'] = machine.result.text;
      reading['mrzValid'] = machine.result.valid;
      final fields = ScanMrzFields.fromResult(machine.result);
      if (fields != null) {
        reading['fields'] = fields.toMap(referenceYear: referenceYear);
        if (kind == ScanPaperKind.idCard && format == ScanMrzFormat.td1) reading['side'] = ScanCardSide.back.name;
      }
    }
    final number = frontNumber;
    if (kind == ScanPaperKind.idCard && !reading.containsKey('side') && frontRead && number != null) {
      reading['side'] = ScanCardSide.front.name;
      reading['fields'] = {'documentNumber': number};
    }
    return reading;
  }
}

// ── What the portal may receive ────────────────────────────────────────────

const _readingKinds = {'passport', 'id_card', 'paper'};
const _readingEngines = {'apple_vision', 'mlkit_latin'};
const _fieldPatterns = <String, String>{
  'surname': r"^[A-Z][A-Z' -]{0,63}$",
  'givenNames': r"^[A-Z][A-Z' -]{0,63}$",
  'documentNumber': r'^[A-Z0-9]{1,24}$',
  'nationality': r'^[A-Z]{1,3}$',
  'issuingState': r'^[A-Z]{1,3}$',
  'birthDate': r'^\d{4}-\d{2}-\d{2}$',
  'expiryDate': r'^\d{4}-\d{2}-\d{2}$',
  'sex': r'^[MFX]$',
  'personalNumber': r'^[A-Z0-9 ]{1,30}$',
};

/// The live reading as the portal may receive it, or null. Every value is
/// checked and bounded; a malformed reading is dropped, never the scan.
Map<String, Object>? sanitizeLiveReading(Object? raw) {
  if (raw is! Map) return null;
  final kind = raw['kind'];
  final engine = raw['engine'];
  if (kind is! String || !_readingKinds.contains(kind)) return null;
  if (engine is! String || !_readingEngines.contains(engine)) return null;
  if (raw['version'] != 1) return null;
  final frames = raw['frames'];
  final reading = <String, Object>{
    'version': 1,
    'kind': kind,
    'engine': engine,
    'matched': raw['matched'] == true,
    'frames': frames is int && frames >= 0 ? math.min(frames, 9999) : 0,
    'mrzValid': false,
    'lines': <String>[],
  };
  final lines = raw['lines'];
  if (lines is List) {
    reading['lines'] = List<String>.unmodifiable(lines
        .whereType<String>()
        .map(ScanTextFrameAnalysis.clean)
        .whereType<String>()
        .take(ScanTextFrameAnalysis.maximumLines));
  }
  final format = raw['mrzFormat'];
  final mrz = raw['mrz'];
  final expected = format == 'TD3' ? (2, 44) : format == 'TD1' ? (3, 30) : null;
  if (expected != null && mrz is List && mrz.length == expected.$1 &&
      mrz.every((line) => line is String && RegExp('^[A-Z0-9<]{${expected.$2}}\$').hasMatch(line))) {
    reading['mrzFormat'] = format as String;
    reading['mrz'] = List<String>.unmodifiable(mrz.cast<String>());
    reading['mrzValid'] = raw['mrzValid'] == true;
  }
  final side = raw['side'];
  if (kind == 'id_card' && (side == 'front' || side == 'back')) reading['side'] = side as String;
  final fields = raw['fields'];
  if (fields is Map) {
    final clean = <String, String>{};
    for (final entry in _fieldPatterns.entries) {
      final value = fields[entry.key];
      if (value is String && RegExp(entry.value).hasMatch(value)) clean[entry.key] = value;
    }
    if (clean.isNotEmpty) reading['fields'] = Map<String, String>.unmodifiable(clean);
  }
  return Map<String, Object>.unmodifiable(reading);
}
