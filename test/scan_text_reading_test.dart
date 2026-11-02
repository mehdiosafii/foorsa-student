import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/guided_scanner/scan_document_profile.dart';
import 'package:foorsa_student/src/guided_scanner/scan_text_reading.dart';

// Mirrors tools/scanner_text_reading_tests.swift: the Android reading must
// decide exactly as the iPhone's does.

// ICAO 9303 specimens (part 4, TD3; part 5, TD1).
const passportOne = 'P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<';
const passportTwo = 'L898902C36UTO7408122F1204159ZE184226B<<<<<10';
const cardOne = 'I<UTOD231458907<<<<<<<<<<<<<<<';
const cardTwo = '7408122F1204159UTO<<<<<<<<<<<6';
const cardThree = 'ERIKSSON<<ANNA<MARIA<<<<<<<<<<';
// Real-shaped samples whose check digits were computed independently.
const moroccanOne = 'P<MARALAMI<<MOHAMED<YASSINE<<<<<<<<<<<<<<<<<';
const moroccanTwo = 'AB12345671MAR9903159M3102282<<<<<<<<<<<<<<<8';
const otherOne = 'P<MARBENNANI<<SARA<<<<<<<<<<<<<<<<<<<<<<<<<<';
const otherTwo = 'XK98765433MAR0501013F3006302CD987654<<<<<<24';
const extendedOne = 'I<UTOD23145890<1233<<<<<<<<<<<';
const extendedTwo = '7408122F1204159UTO<<<<<<<<<<<2';
const cnieOne = 'IDMARAA12345678BE123456<<<<<<<';
const cnieTwo = '8501019M3001019MAR<<<<<<<<<<<8';
const cnieThree = 'ALAMI<<MOHAMED<<<<<<<<<<<<<<<<';

const insetPage = [
  math.Point(0.0455, 0.9545), math.Point(0.9545, 0.9545),
  math.Point(0.9545, 0.0455), math.Point(0.0455, 0.0455),
];

List<int> bytes(String text) => text.codeUnits;

ScanTextObservation line(String text,
        {double x = 0.08, required double y, double width = 0.84, double height = 0.03, int turns = 0}) =>
    ScanTextObservation.turned(
        candidates: [text], box: TextBox.fromSize(x, y, width, height), quarterTurns: turns);

ScanTextObservation region(double x, double y, {double width = 0.3, double height = 0.025}) =>
    ScanTextObservation.turned(candidates: const [], box: TextBox.fromSize(x, y, width, height), quarterTurns: 0);

ScanTextFrame frame(List<ScanTextObservation> lines,
        {List<ScanTextObservation> regions = const [], int turns = 0, double width = 1500, double height = 1060}) =>
    ScanTextFrame(lines: lines, regions: regions, quarterTurns: turns, page: insetPage,
        readingWidth: width, readingHeight: height);

ScanTextFrame passportFrame([String first = passportOne, String second = passportTwo,
        List<ScanTextObservation> extra = const []]) =>
    frame([line('PASSPORT PASSEPORT', y: 0.85), line(first, y: 0.17), line(second, y: 0.11), ...extra]);

ScanTextFrame cardBackFrame([List<String> lines = const [cardOne, cardTwo, cardThree]]) => frame(
    [for (var i = 0; i < lines.length; i++) line(lines[i], y: 0.30 - i * 0.09, height: 0.05)],
    width: 1100, height: 700);

ScanTextFrame cardFrontFrame([String number = 'BE123456']) => frame([
      line('ROYAUME DU MAROC', y: 0.85, height: 0.05),
      line("CARTE NATIONALE D'IDENTITE", y: 0.76, height: 0.05),
      line('MOHAMED', x: 0.4, y: 0.6, width: 0.3, height: 0.05),
      line('ALAMI', x: 0.4, y: 0.52, width: 0.2, height: 0.05),
      line('Né le 01.01.1970', x: 0.4, y: 0.44, width: 0.4, height: 0.05),
      line(number, x: 0.6, y: 0.12, width: 0.3, height: 0.05),
    ], width: 1100, height: 700);

ScanTextFrame paperFrame({int lines = 6, List<ScanTextObservation> extra = const [],
        double width = 1100, double height = 1500, int turns = 0}) =>
    frame([
      for (var i = 0; i < lines; i++)
        line('Ligne ${i + 1} du certificat de scolarité', x: 0.12, y: 0.8 - i * 0.08, width: 0.7,
            height: 0.025, turns: turns),
      ...extra,
    ], width: width, height: height, turns: turns);

GuidedDocumentProfile profile(String key, {String? side}) =>
    GuidedDocumentProfile.fromPortal({'documentKey': key, if (side != null) 'side': side});

ScanTextReadingSession session(String key, {String? side}) =>
    ScanTextReadingSession.forProfile(profile(key, side: side));

void main() {
  group('machine-readable zone', () {
    test('check digits follow ICAO 9303', () {
      final two = bytes(passportTwo);
      expect(ScanMrz.checkDigit(two.sublist(0, 9)), 6);
      expect(ScanMrz.checkDigit(two.sublist(13, 19)), 2);
      expect(ScanMrz.checkDigit(two.sublist(21, 27)), 9);
      expect(ScanMrz.checkDigit(two.sublist(28, 42)), 1);
      expect(ScanMrz.checkDigit(ScanMrz.td3Composite(two)), 0);
      expect(ScanMrz.td3LineTwoScore(two), 4);
      expect(ScanMrz.checkDigit(bytes(cardOne).sublist(5, 14)), 7);
      expect(ScanMrz.checkDigit(ScanMrz.td1Composite(bytes(cardOne), bytes(cardTwo))), 6);
      expect(ScanMrz.td1LineTwoShape(bytes(cardTwo)), isTrue);
      expect(ScanMrz.td1LineTwoScore(bytes(cardTwo)), 2);
      expect(ScanMrz.checkDigit(bytes('<<<<<<')), 0);
      expect(ScanMrz.checkDigit(bytes('AB-12')), isNull);
      expect(ScanMrz.passes(bytes('740812'), 0x3C), isFalse);
      expect(ScanMrz.isDate(bytes('740812')), isTrue);
      expect(ScanMrz.isDate(bytes('741312')), isFalse);
      expect(ScanMrz.isDate(bytes('740800')), isFalse);
    });

    test('reads come back to the MRZ alphabet, position by position', () {
      final normalized = ScanMrz.normalize('p<uto eriksson«anna‹maria');
      expect(String.fromCharCodes(normalized.characters), 'P<UTOERIKSSON<<ANNA<MARIA');
      expect(normalized.dropped, 0);
      expect(ScanMrz.normalize('Né le').dropped, 1);
      final fields = ScanMrzFormat.td3.fields;
      expect(String.fromCharCodes(ScanMrz.conform(bytes('L898902C36UT07408I2ZF12O4I59ZE184226B<<<<<1O'), fields[1])),
          passportTwo);
      expect(String.fromCharCodes(ScanMrz.conform(bytes('P<UT0ERIKSSON<<ANNA<MARIAKKKKKKKKKKKKKKKKKKK'), fields[0])),
          passportOne);
      const doubled = 'P<MARELLA<<LL<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<';
      expect(String.fromCharCodes(ScanMrz.conform(bytes(doubled), fields[0])), doubled);
    });

    test('a filler gained or lost is repaired; a line far off is not this format', () {
      final two = bytes(passportTwo);
      final long = [...two.sublist(0, 38), 0x3C, ...two.sublist(38)];
      expect(ScanMrz.lengthVariants(long, 44).map(String.fromCharCodes), contains(passportTwo));
      final short = [...two.sublist(0, 38), ...two.sublist(39)];
      expect(ScanMrz.lengthVariants(short, 44).map(String.fromCharCodes), contains(passportTwo));
      final twoShort = [...two.sublist(0, 37), ...two.sublist(39)];
      expect(ScanMrz.lengthVariants(twoShort, 44).map(String.fromCharCodes), contains(passportTwo));
      expect(ScanMrz.lengthVariants(two.sublist(0, 41), 44), isEmpty);
      expect(String.fromCharCodes(ScanMrz.padded(bytes('ERIKSSON<<ANNA<MARIA<<<<<<<<'), 30)!), cardThree);
      expect(String.fromCharCodes(ScanMrz.padded(bytes('$cardThree<<'), 30)!), cardThree);
      expect(ScanMrz.padded(bytes('ERIKSSON<<ANNA<MARIA<<<<<<<<<<XY'), 30), isNull);
    });

    test('specimens and real-shaped samples validate; broken ones never do', () {
      for (final (lines, format) in [
        ([passportOne, passportTwo], ScanMrzFormat.td3),
        ([moroccanOne, moroccanTwo], ScanMrzFormat.td3),
        ([otherOne, otherTwo], ScanMrzFormat.td3),
        ([cardOne, cardTwo, cardThree], ScanMrzFormat.td1),
        ([extendedOne, extendedTwo, cardThree], ScanMrzFormat.td1),
        ([cnieOne, cnieTwo, cnieThree], ScanMrzFormat.td1),
      ]) {
        final result = ScanMrzValidator.validate(lines.map(bytes).toList(), format);
        expect(result.valid, isTrue, reason: '$lines');
        expect(result.text, lines);
      }
      final lookAlike = ScanMrzValidator.validate(
          [bytes(passportOne), bytes('L8989O2C36UTO7408122F1204159ZE184226B<<<<<10')], ScanMrzFormat.td3);
      expect(lookAlike.valid, isTrue);
      expect(lookAlike.text, [passportOne, passportTwo]);
      for (final broken in [
        'L898902C36UTO7408122F1204159ZE184226B<<<<<11', 'L898902C36UTO7408123F1204159ZE184226B<<<<<10',
        'L898902C36UTO7408122F1204158ZE184226B<<<<<10', 'L898902C37UTO7408122F1204159ZE184226B<<<<<10',
        'L898902C36UTO7413122F1204159ZE184226B<<<<<10', 'L898902C36UTO7408122Q1204159ZE184226B<<<<<10',
      ]) {
        expect(ScanMrzValidator.validate([bytes(passportOne), bytes(broken)], ScanMrzFormat.td3).valid, isFalse,
            reason: broken);
      }
      expect(ScanMrzValidator.validate([bytes('I<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<'), bytes(passportTwo)],
          ScanMrzFormat.td3).valid, isFalse);
      expect(ScanMrzValidator.validate([bytes(passportOne)], ScanMrzFormat.td3).valid, isFalse);
      expect(ScanMrzValidator.validate([bytes(cardOne), bytes('7408122F1204159UTO<<<<<<<<<<<7'), bytes(cardThree)],
          ScanMrzFormat.td1).valid, isFalse);
      expect(ScanMrzValidator.validate([bytes('P<UTOD231458907<<<<<<<<<<<<<<<'), bytes(cardTwo), bytes(cardThree)],
          ScanMrzFormat.td1).valid, isFalse);
    });

    test('a look-alike tie is refused alone and settled by what other reads saw', () {
      final personalTwo = bytes('L898902C36UTO7408122F1204159ZE1B4226B<<<<<10');
      expect(ScanMrzValidator.validate([bytes(passportOne), personalTwo], ScanMrzFormat.td3).valid, isFalse);
      final votes = ScanMrzVotes(ScanMrzFormat.td3)
        ..add([bytes(passportOne), personalTwo])
        ..add([bytes(passportOne), personalTwo])
        ..add([bytes(passportOne), bytes(passportTwo)]);
      expect(String.fromCharCodes(votes.consensus[1]!), String.fromCharCodes(personalTwo));
      final repaired = ScanMrzValidator.validate([bytes(passportOne), personalTwo], ScanMrzFormat.td3,
          tallies: votes.counts);
      expect(repaired.valid, isTrue);
      expect(repaired.text[1], passportTwo);
    });

    test('fields come with ISO dates and the century from the reference year', () {
      final fields = ScanMrzFields.fromResult(
          ScanMrzValidator.validate([bytes(passportOne), bytes(passportTwo)], ScanMrzFormat.td3))!;
      expect(fields.surname, 'ERIKSSON');
      expect(fields.givenNames, 'ANNA MARIA');
      expect(fields.documentNumber, 'L898902C3');
      expect(fields.personalNumber, 'ZE184226B');
      final map = fields.toMap(referenceYear: 2026);
      expect(map['birthDate'], '1974-08-12');
      expect(map['expiryDate'], '2012-04-15');
      expect(map['issuingState'], 'UTO');
      expect(ScanMrzFields.isoDate('050101', birth: true, referenceYear: 2026), '2005-01-01');
      expect(ScanMrzFields.isoDate('300630', birth: true, referenceYear: 2026), '1930-06-30');
      expect(ScanMrzFields.isoDate('310228', birth: false, referenceYear: 2026), '2031-02-28');
      final moroccan = ScanMrzFields.fromResult(
          ScanMrzValidator.validate([bytes(moroccanOne), bytes(moroccanTwo)], ScanMrzFormat.td3))!;
      expect(moroccan.givenNames, 'MOHAMED YASSINE');
      expect(moroccan.toMap(referenceYear: 2026).containsKey('personalNumber'), isFalse);
      expect(moroccan.toMap(referenceYear: 2026)['birthDate'], '1999-03-15');
      final extended = ScanMrzFields.fromResult(ScanMrzValidator.validate(
          [bytes(extendedOne), bytes(extendedTwo), bytes(cardThree)], ScanMrzFormat.td1))!;
      expect(extended.documentNumber, 'D23145890123');
      final cnie = ScanMrzFields.fromResult(ScanMrzValidator.validate(
          [bytes(cnieOne), bytes(cnieTwo), bytes(cnieThree)], ScanMrzFormat.td1))!;
      expect(cnie.documentNumber, 'AA1234567');
      expect(cnie.personalNumber, 'BE123456');
      expect(cnie.surname, 'ALAMI');
      expect(cnie.givenNames, 'MOHAMED');
      expect(ScanMrzFields.fromResult(const ScanMrzResult(ScanMrzFormat.td3, [], valid: false)), isNull);
    });

    test('lines are found in what the camera read, noise and all', () {
      final noisy = [
        line('P<UTO ERIKSSON«ANNA<MARIA<<<<<<<<<<<<<<<<<<<', y: 0.17),
        line('L898902C36UTO74O8122F12O4159ZE184226B<<<<<1O', y: 0.11),
      ];
      final rows = ScanMrzReader.machineRows([...noisy, line('REPUBLIC OF UTOPIA', y: 0.9)]);
      expect(rows, hasLength(2));
      final found = ScanMrzReader.td3(rows)!;
      expect(String.fromCharCodes(found[0]!), passportOne);
      expect(String.fromCharCodes(found[1]!), passportTwo);
      final split = [
        line(passportOne, y: 0.17),
        line('L898902C36UTO7408122F12', x: 0.08, y: 0.11, width: 0.42),
        line('04159ZE184226B<<<<<10', x: 0.52, y: 0.112, width: 0.40),
      ];
      expect(String.fromCharCodes(ScanMrzReader.td3(ScanMrzReader.machineRows(split))![1]!), passportTwo);
      final extra = '${passportTwo.substring(0, 38)}<${passportTwo.substring(38)}';
      expect(String.fromCharCodes(ScanMrzReader.td3(
          ScanMrzReader.machineRows([line(passportOne, y: 0.17), line(extra, y: 0.11)]))![1]!), passportTwo);
      final alone = ScanMrzReader.td3(ScanMrzReader.machineRows([line(passportOne, y: 0.6), line(passportTwo, y: 0.11)]))!;
      expect(alone[0], isNull);
      expect(String.fromCharCodes(alone[1]!), passportTwo);
      final card = ScanMrzReader.td1(ScanMrzReader.machineRows(cardBackFrame().lines))!;
      expect(card.map((line) => String.fromCharCodes(line!)), [cardOne, cardTwo, cardThree]);
      expect(ScanMrzReader.td3(ScanMrzReader.machineRows(cardBackFrame().lines)), isNull);
      expect(ScanMrzReader.machineRows(paperFrame().lines), isEmpty);
      expect(ScanMrz.td3LineTwoScore(bytes('L898902C36UTO7408123F1204158ZE184226B<<<<<10')), 1);
      expect(ScanMrzReader.td3(ScanMrzReader.machineRows(
          [line(passportOne, y: 0.17), line('L898902C36UTO7408123F1204158ZE184226B<<<<<10', y: 0.11)])), isNull);
    });

    test('votes outweigh one bad read and follow a new paper', () {
      final votes = ScanMrzVotes(ScanMrzFormat.td3);
      expect(votes.consensus.every((line) => line == null), isTrue);
      final good = [bytes(passportOne), bytes(passportTwo)];
      final noisy = [bytes('P<UTOERIKSSON<<ANNA<MARLA<<<<<<<<<<<<<<<<<<<'),
        bytes('L898902C36UTO7408122F1204159ZE184226B<<<<<17')];
      votes
        ..add(good)
        ..add(noisy)
        ..add(good);
      expect(String.fromCharCodes(votes.consensus[0]!), passportOne);
      expect(String.fromCharCodes(votes.consensus[1]!), passportTwo);
      expect(votes.supportingReads(good), 3);
      expect(votes.disagreement([null, bytes(otherTwo)])!, greaterThan(0.3));
      expect(votes.disagreement(noisy)!, lessThan(0.05));
      votes.add([null, bytes(passportTwo)]);
      expect(votes.reads, hasLength(4));
      votes.add([null, null]);
      expect(votes.reads, hasLength(4));
      for (var i = 0; i < 10; i++) {
        votes.add(good);
      }
      expect(votes.reads, hasLength(ScanMrzVotes.maximumReads));
      for (var s = 0; s < ScanMrzVotes.symbols; s++) {
        expect(ScanMrzVotes.symbol(ScanMrzVotes.character(s)), s);
      }
    });
  });

  group('the right-document gate', () {
    test('a passport passes on two agreeing reads, not one', () {
      expect(profile('identity').paperKind, ScanPaperKind.passport);
      var reading = session('identity');
      expect(reading.status(glare: false), const ScanTextGateStatus.waiting(ScanTextGuidance.reading));
      reading.ingest(passportFrame());
      expect(reading.status(glare: false), const ScanTextGateStatus.waiting(ScanTextGuidance.reading));
      reading.ingest(passportFrame());
      expect(reading.status(glare: false), ScanTextGateStatus.passedReading);

      reading = session('identity')
        ..ingest(passportFrame(passportOne, 'L898902C36UTO7408122F1204159ZE184226B<<<<<17'))
        ..ingest(passportFrame())
        ..ingest(passportFrame());
      expect(reading.status(glare: false).passed, isTrue);
    });

    test('a passport without readable lines says what to change', () {
      var reading = session('identity');
      // Open at its photo page, both pages one above the other (the owner, 1 Nov
      // 2026): read as seen first, then upside down, then a quarter turn either way.
      expect(reading.turnPolicy, const ScanTextTurnPolicy.fixed(0));
      reading.ingest(frame([line('REPUBLIC OF UTOPIA', y: 0.8)]));
      expect(reading.status(glare: false).guidance, ScanTextGuidance.reading);
      expect(reading.turnPolicy, const ScanTextTurnPolicy.fixed(2));
      reading.ingest(frame([line('REPUBLIC OF UTOPIA', y: 0.8)], turns: 2));
      expect(reading.status(glare: false).guidance, ScanTextGuidance.showMachineLines);
      expect(reading.status(glare: true).guidance, ScanTextGuidance.glareOnMachineLines);
      expect(reading.turnPolicy, const ScanTextTurnPolicy.fixed(1));
      reading.ingest(frame([line('REPUBLIC OF UTOPIA', y: 0.8)], turns: 1));
      expect(reading.turnPolicy, const ScanTextTurnPolicy.fixed(3));
      // Round again: the student may turn the passport.
      reading.ingest(frame([line('REPUBLIC OF UTOPIA', y: 0.8)], turns: 3));
      expect(reading.turnPolicy, const ScanTextTurnPolicy.fixed(0));
      reading.ingest(passportFrame());
      expect(reading.turnPolicy, const ScanTextTurnPolicy.fixed(0));
      reading.ingest(frame([line('REPUBLIC OF UTOPIA', y: 0.8)]));
      expect(reading.turnPolicy, const ScanTextTurnPolicy.fixed(0));

      // Found, it is kept the way its two lines were read: here a photo page
      // alone, held sideways.
      reading = session('identity')
        ..ingest(frame([line('REPUBLIC OF UTOPIA', y: 0.8)]))
        ..ingest(frame([line('REPUBLIC OF UTOPIA', y: 0.8)], turns: 2))
        ..ingest(frame([line('PASSPORT PASSEPORT', y: 0.85), line(passportOne, y: 0.17), line(passportTwo, y: 0.11)],
            turns: 1));
      expect(reading.turnPolicy, const ScanTextTurnPolicy.fixed(1));
      reading.ingest(frame([line('REPUBLIC OF UTOPIA', y: 0.8)], turns: 1));
      expect(reading.turnPolicy, const ScanTextTurnPolicy.fixed(1));

      reading = session('identity')..ingest(frame([line('REPUBLIC OF UTOPIA', y: 0.8)], width: 700, height: 495));
      expect(reading.status(glare: false).guidance, ScanTextGuidance.moveCloserMachineLines);
      reading = session('identity')
        ..ingest(frame([line(passportOne, y: 0.17, height: 0.008),
          line('L898902C36UTO7408122F1204159ZE18', y: 0.11, height: 0.008)]));
      expect(reading.status(glare: false).guidance, ScanTextGuidance.moveCloserMachineLines);
      reading = session('identity')
        ..ingest(frame([line(passportOne, y: 0.17), line('L898902C36UTO7408122F1204159ZE18', x: 0.3, y: 0.11, width: 0.7)]));
      expect(reading.status(glare: false).guidance, ScanTextGuidance.showWholeMachineLines);
      reading = session('identity')
        ..ingest(frame([line(passportOne, y: 0.17), line('L898902C36UTO7408122F12041', y: 0.11)]));
      expect(reading.status(glare: true).guidance, ScanTextGuidance.glareOnMachineLines);
      expect(reading.status(glare: false).guidance, ScanTextGuidance.reading);
    });

    test('an ID card in the passport step is a different paper; a new passport replaces the votes', () {
      var reading = session('identity')
        ..ingest(cardBackFrame())
        ..ingest(cardBackFrame());
      expect(reading.status(glare: false).guidance, ScanTextGuidance.differentPaper);
      reading = session('identity')
        ..ingest(passportFrame())
        ..ingest(passportFrame())
        ..ingest(passportFrame(otherOne, otherTwo));
      expect(reading.machineReading(ScanMrzFormat.td3)!.result.text, [otherOne, otherTwo]);
      expect(reading.status(glare: false).passed, isFalse);
      reading.ingest(passportFrame(otherOne, otherTwo));
      expect(reading.status(glare: false).passed, isTrue);
    });

    test('a card follows the side the step asks for', () {
      expect(profile('parent_id', side: 'back').cardSide, ScanCardSide.back);
      expect(profile('parent_id', side: 'sideways').cardSide, isNull);
      expect(profile('parent_id').cardSide, isNull);
      var reading = session('parent_id', side: 'back')
        ..ingest(cardBackFrame())
        ..ingest(cardBackFrame());
      expect(reading.status(glare: false), ScanTextGateStatus.passedReading);
      reading = session('parent_id', side: 'back')
        ..ingest(cardBackFrame([cnieOne, cnieTwo, cnieThree]))
        ..ingest(cardBackFrame([cnieOne, cnieTwo, cnieThree]));
      expect(reading.status(glare: false).passed, isTrue);
      reading = session('parent_id', side: 'back')
        ..ingest(cardFrontFrame())
        ..ingest(cardFrontFrame());
      expect(reading.status(glare: false).guidance, ScanTextGuidance.turnCardToBack);

      reading = session('parent_id', side: 'front')..ingest(cardFrontFrame());
      expect(reading.status(glare: false).guidance, ScanTextGuidance.reading);
      reading.ingest(cardFrontFrame());
      expect(reading.status(glare: false), ScanTextGateStatus.passedReading);
      expect(reading.frontNumber, 'BE123456');
      reading = session('parent_id', side: 'front')
        ..ingest(cardBackFrame())
        ..ingest(cardBackFrame());
      expect(reading.status(glare: false).guidance, ScanTextGuidance.turnCardToFront);
      reading = session('parent_id', side: 'front')
        ..ingest(passportFrame())
        ..ingest(passportFrame());
      expect(reading.status(glare: false).guidance, ScanTextGuidance.differentPaper);
      reading = session('parent_id', side: 'front')
        ..ingest(frame([line('MOHAMED', y: 0.5, width: 0.3)], width: 500, height: 320));
      expect(reading.status(glare: false).guidance, ScanTextGuidance.moveCloserText);
      reading = session('parent_id', side: 'front')
        ..ingest(frame(const []))
        ..ingest(frame(const []));
      expect(reading.status(glare: false).guidance, ScanTextGuidance.showCardDetails);
      expect(reading.status(glare: true).guidance, ScanTextGuidance.glareOnText);
    });

    // The owner, 2 Nov 2026: the back "needs me clicking the capture button". The front seen a moment
    // before, or the card's number inside the back's own lines, no longer passes for the front.
    test('a back is taken by itself once the front is out of view, before its lines are confirmed', () {
      final reading = session('parent_id', side: 'back')
        ..ingest(cardFrontFrame())
        ..ingest(cardFrontFrame());
      expect(reading.status(glare: false).guidance, ScanTextGuidance.turnCardToBack);
      // Turned over: its lines in view, read once (a second read would confirm them).
      reading.ingest(cardBackFrame([cnieOne, cnieTwo, 'ALAMI<<MOHAMED<<<<<<<<<<<<<<<']));
      final status = reading.status(glare: false);
      expect(status.passed, isFalse);
      expect(status.guidance?.holdsCapture, isFalse);
      expect(status.capturesWhenClear(ScanTextGateStatus.clearPageGrace(ScanPaperKind.idCard), ScanPaperKind.idCard), isTrue);
      // An older card whose back has no machine-readable lines: taken on the same grace.
      final older = session('parent_id', side: 'back')
        ..ingest(cardFrontFrame())
        ..ingest(cardFrontFrame())
        ..ingest(frame([
          line('Fils de AHMED', y: 0.7, height: 0.05),
          line('et de FATIMA', y: 0.6, height: 0.05),
          line('Adresse 12 RUE 4 HAY SALAM', y: 0.5, height: 0.05),
        ], width: 1100, height: 700));
      expect(older.status(glare: false).guidance?.holdsCapture, isFalse);
    });

    test('the number in a back’s machine-readable lines is not a front’s', () {
      expect(ScanCardFront.numbers(['IDMARAA12345678 BE123456<<<<<<<']), isEmpty);
      expect(ScanCardFront.numbers(['IDMARAA12345678 BE123456«««««««']), isEmpty);
      expect(ScanCardFront.numbers(['N° BE123456']), ['BE123456']);
      expect(ScanCardFront.machineLike('ROYAUME DU MAROC'), isFalse);
      final spaced = cnieOne.replaceFirst('BE', ' BE');
      final reading = session('parent_id', side: 'back')
        ..ingest(cardBackFrame([spaced, cnieTwo, 'ALAMI<<MOHAMED<<<<<<<<<<<<<<<']))
        ..ingest(cardBackFrame([spaced, cnieTwo, 'ALAMI<<MOHAMEO<<<<<<<<<<<<<<<']));
      expect(reading.frontNumber, isNull);
      expect(reading.status(glare: false).guidance, isNot(ScanTextGuidance.turnCardToBack));
    });

    test('a front asked for after the back was seen is held only while the back is in view', () {
      final reading = session('parent_id', side: 'front')
        ..ingest(cardBackFrame())
        ..ingest(cardBackFrame());
      expect(reading.status(glare: false).guidance, ScanTextGuidance.turnCardToFront);
      // Turned over, its number not read yet: no longer held.
      reading.ingest(frame([
        line('ROYAUME DU MAROC', y: 0.85, height: 0.05),
        line('MOHAMED', x: 0.4, y: 0.6, width: 0.3, height: 0.05),
      ], width: 1100, height: 700));
      expect(reading.status(glare: false).guidance?.holdsCapture, isFalse);
      reading
        ..ingest(cardFrontFrame())
        ..ingest(cardFrontFrame());
      expect(reading.status(glare: false), ScanTextGateStatus.passedReading);
    });

    test('without a side either side is the card, Tunisian fronts included', () {
      var reading = session('parent_id')
        ..ingest(cardBackFrame())
        ..ingest(cardBackFrame());
      expect(reading.status(glare: false).passed, isTrue);
      reading = session('parent_id')
        ..ingest(cardFrontFrame())
        ..ingest(cardFrontFrame());
      expect(reading.status(glare: false).passed, isTrue);
      reading = session('parent_id')
        ..ingest(frame([line(cardOne, y: 0.3, height: 0.006), line('7408122F1204159UTO<<<<<<', y: 0.21, height: 0.006)],
            width: 1100, height: 700));
      expect(reading.status(glare: false).guidance, ScanTextGuidance.moveCloserMachineLines);
      final arabic = [for (var i = 0; i < 5; i++) region(0.3, 0.8 - i * 0.12, width: 0.5, height: 0.06)];
      final tunisian = frame([line('12345678', x: 0.55, y: 0.15, width: 0.3, height: 0.05)],
          regions: arabic, width: 1100, height: 700);
      reading = session('parent_id', side: 'front')
        ..ingest(tunisian)
        ..ingest(tunisian);
      expect(reading.status(glare: false).passed, isTrue);
      expect(reading.frontNumber, '12345678');
    });

    test('card numbers are read off a front', () {
      expect(ScanCardFront.numbers(['N° BE123456']), ['BE123456']);
      expect(ScanCardFront.numbers(['BE 123456']), ['BE123456']);
      expect(ScanCardFront.numbers(['BE12345G']), ['BE123456']);
      expect(ScanCardFront.numbers(['CAN 123456', '01.01.1970', 'Né le 12.03.1985', 'ABDELLAH']), isEmpty);
      expect(ScanCardFront.numbers(['12345678']), ['12345678']);
      expect(ScanCardFront.numbers(['1234567', '123456789']), isEmpty);
      expect(ScanCardFront.hasKeyword(['Royaume du Maroc']), isTrue);
      expect(ScanCardFront.hasKeyword(['MOHAMED']), isFalse);
    });

    test('a paper needs lines inside the page and none running past its edge', () {
      expect(profile('highest_degree').rejectsIdentityPapers, isTrue);
      expect(profile('visa_documents').rejectsIdentityPapers, isFalse);
      expect(profile('drive_files').rejectsIdentityPapers, isFalse);
      var reading = session('highest_degree');
      expect(reading.turnPolicy, const ScanTextTurnPolicy.fixed(0));
      reading.ingest(paperFrame());
      expect(reading.status(glare: false).guidance, ScanTextGuidance.reading);
      reading.ingest(paperFrame());
      expect(reading.status(glare: false), ScanTextGateStatus.passedReading);

      final runsOff = line('Université Mohammed V de Rabat, Faculté', x: 0.5, y: 0.5, width: 0.49, height: 0.025);
      reading = session('highest_degree')..ingest(paperFrame(extra: [runsOff]));
      expect(reading.status(glare: false).guidance, ScanTextGuidance.reading);
      reading.ingest(paperFrame(extra: [runsOff]));
      expect(reading.status(glare: false).guidance, ScanTextGuidance.textRunsPastEdge);
      reading.ingest(paperFrame());
      expect(reading.status(glare: false).guidance, ScanTextGuidance.reading);
      reading.ingest(paperFrame());
      expect(reading.status(glare: false).passed, isTrue);

      final atFrame = line('Royaume du Maroc — Ministère', x: 0, y: 0.6, width: 0.3, height: 0.025);
      expect(ScanTextLayout.summarize(paperFrame(extra: [atFrame]).lines, const [], insetPage).cutRows, 1);
      final outside = line('magazine headline outside', x: 0.955, y: 0.6, width: 0.044, height: 0.02);
      expect(ScanTextLayout.summarize(paperFrame(extra: [outside]).lines, const [], insetPage).cutRows, 0);
      final sliver = line('Signature du directeur', x: 0.6, y: 0.2, width: 0.36, height: 0.025);
      expect(ScanTextLayout.summarize([sliver], const [], insetPage).cutRows, 0);
    });

    test('a far or blank paper says what to change', () {
      var reading = session('highest_degree')..ingest(paperFrame(lines: 1, width: 600, height: 800));
      expect(reading.status(glare: false).guidance, ScanTextGuidance.moveCloserText);
      reading = session('highest_degree')..ingest(paperFrame(lines: 0));
      expect(reading.status(glare: false).guidance, ScanTextGuidance.reading);
      reading.ingest(paperFrame(lines: 0));
      expect(reading.status(glare: false).guidance, ScanTextGuidance.showPrintedText);
    });

    test('print found but not read counts, and the turn search settles', () {
      final reading = session('highest_degree');
      final print = [for (var i = 0; i < 5; i++) region(0.15, 0.8 - i * 0.1, width: 0.6)];
      reading.ingest(frame(const [], regions: print));
      expect(reading.turnPolicy, const ScanTextTurnPolicy.fixed(1));
      reading.ingest(frame(const [], regions: print, turns: 1));
      expect(reading.turnPolicy, const ScanTextTurnPolicy.fixed(3));
      reading.ingest(frame(const [], regions: print, turns: 3));
      expect(reading.turnPolicy, const ScanTextTurnPolicy.fixed(0));
      expect(reading.status(glare: false).passed, isTrue);
      final turned = session('highest_degree')
        ..ingest(paperFrame(lines: 0))
        ..ingest(paperFrame(lines: 5, turns: 1));
      expect(turned.turnPolicy, const ScanTextTurnPolicy.fixed(1));
    });

    test('a passport in a diploma step is refused, not in a visa step', () {
      final lines = paperFrame().lines;
      var reading = session('highest_degree')
        ..ingest(passportFrame(passportOne, passportTwo, lines))
        ..ingest(passportFrame(passportOne, passportTwo, lines));
      expect(reading.status(glare: false).guidance, ScanTextGuidance.differentPaper);
      reading = session('visa_documents')
        ..ingest(passportFrame(passportOne, passportTwo, lines))
        ..ingest(passportFrame(passportOne, passportTwo, lines));
      expect(reading.status(glare: false).passed, isTrue);
      expect(ScanTextLayout.rows([
        const TextBox.fromSize(0.1, 0.5, 0.2, 0.03), const TextBox.fromSize(0.35, 0.505, 0.2, 0.03),
        const TextBox.fromSize(0.1, 0.4, 0.3, 0.03), const TextBox.fromSize(0.5, 0.2, 0.02, 0.02),
      ]), 2);
    });

    test('quarter turns round-trip and the landscape rule turns a portrait crop', () {
      const point = math.Point(0.2, 0.7);
      for (var turns = -1; turns <= 5; turns++) {
        final again = ScanQuarterTurn.undo(turns, ScanQuarterTurn.apply(turns, point));
        expect((again.x - point.x).abs(), lessThan(1e-12));
        expect((again.y - point.y).abs(), lessThan(1e-12));
      }
      expect(ScanQuarterTurn.apply(1, const math.Point(1, 0.5)), const math.Point(0.5, 1));
      expect(ScanQuarterTurn.apply(3, const math.Point(1, 0.5)), const math.Point(0.5, 0));
      final turned = ScanQuarterTurn.undoBox(1, const TextBox.fromSize(0.1, 0.2, 0.3, 0.1));
      expect(turned.minX, closeTo(0.2, 1e-12));
      expect(turned.maxX, closeTo(0.3, 1e-12));
      expect(turned.minY, closeTo(0.6, 1e-12));
      expect(turned.maxY, closeTo(0.9, 1e-12));
      expect(const ScanTextTurnPolicy.landscape(upsideDown: false).quarterTurns(1500, 1000), 0);
      expect(const ScanTextTurnPolicy.landscape(upsideDown: false).quarterTurns(1000, 1500), 1);
      expect(const ScanTextTurnPolicy.landscape(upsideDown: true).quarterTurns(1500, 1000), 2);
      expect(const ScanTextTurnPolicy.landscape(upsideDown: true).quarterTurns(1000, 1500), 3);
      expect(const ScanTextTurnPolicy.fixed(-1).quarterTurns(1, 1), 3);
    });

    test('the reading follows its page and steps aside on a phone that cannot read', () {
      const page = Rect.fromLTRB(0.2, 0.2, 0.8, 0.7);
      final start = DateTime(2026, 10, 30, 12);
      DateTime at(int milliseconds) => start.add(Duration(milliseconds: milliseconds));
      var reading = session('identity');
      expect(reading.observePage(page, at(0)), isFalse);
      reading.ingest(passportFrame());
      expect(reading.observePage(null, at(200)), isFalse);
      expect(reading.observePage(null, at(1000)), isFalse);
      expect(reading.framesRead, 1);
      expect(reading.observePage(null, at(1800)), isTrue);
      expect(reading.framesRead, 0);
      expect(reading.observePage(null, at(4000)), isFalse);
      expect(reading.observePage(page, at(5000)), isFalse);
      reading.ingest(passportFrame());
      expect(reading.observePage(const Rect.fromLTRB(0.22, 0.2, 0.82, 0.7), at(5100)), isFalse);
      expect(reading.framesRead, 1);
      expect(reading.observePage(const Rect.fromLTRB(0.5, 0.05, 0.95, 0.45), at(5200)), isTrue);
      expect(reading.framesRead, 0);

      reading = session('identity');
      for (var i = 0; i < ScanTextReadingSession.readerFailureLimit - 1; i++) {
        reading.readFailed();
      }
      expect(reading.status(glare: false).allowsCapture, isFalse);
      reading.ingest(frame(const []));
      for (var i = 0; i < ScanTextReadingSession.readerFailureLimit - 1; i++) {
        reading.readFailed();
      }
      expect(reading.readerUnavailable, isFalse);
      reading.readFailed();
      expect(reading.readerUnavailable, isTrue);
      expect(reading.status(glare: false), ScanTextGateStatus.cannotRead);
      reading.reset();
      expect(reading.readerUnavailable, isTrue);
      expect((session('cv')..markReaderUnavailable()).status(glare: false).allowsCapture, isTrue);
    });

    test('every guidance has words, the same as on the iPhone', () {
      for (final guidance in ScanTextGuidance.values) {
        for (final kind in ScanPaperKind.values) {
          final copy = guidance.copy(kind);
          expect(copy.title, isNotEmpty);
          expect(copy.detail, isNotEmpty);
          expect(copy.compact, isNotEmpty);
        }
      }
      expect(ScanTextGuidance.showMachineLines.copy(ScanPaperKind.passport).detail,
          'Show the photo page with the two lines at the bottom.');
      expect(ScanTextGuidance.moveCloserMachineLines.copy(ScanPaperKind.passport).detail,
          'Move closer — the bottom lines are too small.');
      expect(ScanTextGuidance.differentPaper.copy(ScanPaperKind.paper).title, 'This looks like a different paper');
    });
  });

  // The owner, 30 Oct 2026: "it should be automatic once the shot is clear". A clear, steady page
  // no longer waits on the reading for long: only the wrong paper, or the wrong side of a card,
  // keeps it waiting (the iPhone's ScannerTextGateStatus.capturesWhenClear says the same).
  group('a clear page is taken without a tap', () {
    test('at once when the reading passed, or the phone cannot read', () {
      expect(ScanTextGateStatus.passedReading.capturesWhenClear(Duration.zero, ScanPaperKind.passport), isTrue);
      expect(ScanTextGateStatus.cannotRead.capturesWhenClear(Duration.zero, ScanPaperKind.paper), isTrue);
    });

    test('after a short moment while the reading is still looking', () {
      const looking = [
        ScanTextGuidance.reading, ScanTextGuidance.showMachineLines, ScanTextGuidance.moveCloserMachineLines,
        ScanTextGuidance.glareOnMachineLines, ScanTextGuidance.showWholeMachineLines, ScanTextGuidance.showCardDetails,
        ScanTextGuidance.glareOnText, ScanTextGuidance.moveCloserText, ScanTextGuidance.showPrintedText,
        ScanTextGuidance.textRunsPastEdge,
      ];
      for (final kind in ScanPaperKind.values) {
        final grace = ScanTextGateStatus.clearPageGrace(kind);
        for (final guidance in looking) {
          final waiting = ScanTextGateStatus.waiting(guidance);
          expect(guidance.holdsCapture, isFalse);
          expect(waiting.capturesWhenClear(grace - const Duration(milliseconds: 50), kind), isFalse, reason: '$kind $guidance');
          expect(waiting.capturesWhenClear(grace, kind), isTrue, reason: '$kind $guidance');
        }
      }
      // A passport's or a card's lines get a little longer than a paper's rows, and never long.
      expect(ScanTextGateStatus.clearPageGrace(ScanPaperKind.paper) < ScanTextGateStatus.clearPageGrace(ScanPaperKind.passport), isTrue);
      expect(ScanTextGateStatus.clearPageGrace(ScanPaperKind.idCard) <= const Duration(seconds: 2), isTrue);
    });

    test('never while the reading sees the wrong paper or the wrong side of a card', () {
      for (final guidance in [ScanTextGuidance.differentPaper, ScanTextGuidance.turnCardToFront, ScanTextGuidance.turnCardToBack]) {
        expect(guidance.holdsCapture, isTrue);
        for (final kind in ScanPaperKind.values) {
          expect(ScanTextGateStatus.waiting(guidance).capturesWhenClear(const Duration(minutes: 1), kind), isFalse);
        }
      }
    });
  });

  // The owner, 30 Oct 2026, on build 54: the scanner still needed the button. A soft frame or a
  // tremor started the wait over; now the page is taken steady and read, steady for a moment, or
  // in view long enough, and never while the reading sees the wrong paper.
  group('the automatic shutter', () {
    final start = DateTime(2026, 10, 30, 20);

    /// Frames 100 ms apart for [end]; how long after [start] the page was taken, or null.
    Duration? takenAt(ScanPaperKind kind, Duration end, ScanShutterPage Function(Duration at) page,
        {ScanTextGateStatus reading = const ScanTextGateStatus.waiting(ScanTextGuidance.reading),
        bool lightingGood = true}) {
      final shutter = ScanAutoShutter();
      for (var at = Duration.zero; at <= end; at += const Duration(milliseconds: 100)) {
        if (shutter.observe(page(at), start.add(at), reading: reading, kind: kind, lightingGood: lightingGood)) {
          return at;
        }
      }
      return null;
    }

    test('a steady page the reading passed is taken at once', () {
      expect(takenAt(ScanPaperKind.passport, const Duration(seconds: 5), (_) => ScanShutterPage.steady,
          reading: ScanTextGateStatus.passedReading), Duration.zero);
      expect(takenAt(ScanPaperKind.paper, const Duration(seconds: 5), (_) => ScanShutterPage.steady,
          reading: ScanTextGateStatus.cannotRead), Duration.zero);
    });

    test('a steady page the reading still looks at is taken after its grace, soft frames or not', () {
      for (final kind in ScanPaperKind.values) {
        final grace = ScanTextGateStatus.clearPageGrace(kind);
        expect(takenAt(kind, const Duration(seconds: 10), (_) => ScanShutterPage.steady), grace, reason: '$kind');
        // A soft frame every third frame no longer starts the grace over.
        final flicker = takenAt(kind, const Duration(seconds: 10),
            (at) => (at.inMilliseconds ~/ 100) % 3 == 2 ? ScanShutterPage.inView : ScanShutterPage.steady);
        expect(flicker, isNotNull, reason: '$kind');
        expect(flicker! <= grace + const Duration(milliseconds: 150), isTrue, reason: '$kind $flicker');
      }
    });

    test('shadow, glare or dim light get a moment, then the page is taken anyway', () {
      expect(takenAt(ScanPaperKind.paper, const Duration(seconds: 10), (_) => ScanShutterPage.steady,
          lightingGood: false), ScanAutoShutter.lightingGrace);
    });

    test('a page in view, never steady or sharp, is taken once its limit is over', () {
      for (final kind in ScanPaperKind.values) {
        expect(takenAt(kind, const Duration(seconds: 10), (_) => ScanShutterPage.inView),
            ScanAutoShutter.inViewLimit(kind), reason: '$kind');
        expect(ScanAutoShutter.inViewLimit(kind) <= const Duration(milliseconds: 3500), isTrue);
      }
    });

    test('out of view for a moment keeps the clocks; out of view a while starts them over', () {
      bool between(Duration at, int from, int to) => at.inMilliseconds >= from && at.inMilliseconds <= to;
      expect(takenAt(ScanPaperKind.paper, const Duration(seconds: 10),
          (at) => between(at, 1000, 1500) ? ScanShutterPage.missing : ScanShutterPage.inView),
          ScanAutoShutter.inViewLimit(ScanPaperKind.paper));
      expect(takenAt(ScanPaperKind.paper, const Duration(seconds: 10),
          (at) => between(at, 1000, 2000) ? ScanShutterPage.missing : ScanShutterPage.inView),
          const Duration(milliseconds: 2100) + ScanAutoShutter.inViewLimit(ScanPaperKind.paper));
    });

    test('no page, nothing taken', () {
      expect(takenAt(ScanPaperKind.paper, const Duration(seconds: 10), (_) => ScanShutterPage.missing,
          reading: ScanTextGateStatus.passedReading), isNull);
    });

    test('the wrong paper, or the wrong side of a card, is never taken', () {
      for (final guidance in [ScanTextGuidance.differentPaper, ScanTextGuidance.turnCardToFront, ScanTextGuidance.turnCardToBack]) {
        for (final page in [ScanShutterPage.steady, ScanShutterPage.inView]) {
          expect(takenAt(ScanPaperKind.idCard, const Duration(minutes: 1), (_) => page,
              reading: ScanTextGateStatus.waiting(guidance)), isNull, reason: '$guidance $page');
        }
      }
    });

    test('the same clocks as the iPhone', () {
      expect(ScanTextGateStatus.clearPageGrace(ScanPaperKind.paper), const Duration(milliseconds: 800));
      expect(ScanTextGateStatus.clearPageGrace(ScanPaperKind.passport), const Duration(milliseconds: 1500));
      expect(ScanAutoShutter.pageLossReset, const Duration(milliseconds: 800));
      expect(ScanAutoShutter.inViewLimit(ScanPaperKind.paper), const Duration(milliseconds: 2500));
      expect(ScanAutoShutter.inViewLimit(ScanPaperKind.idCard), const Duration(milliseconds: 3500));
    });
  });

  group('the live reading returned with the capture', () {
    test('a confirmed passport returns its lines and fields', () {
      final reading = session('identity')
        ..ingest(passportFrame())
        ..ingest(passportFrame());
      final live = reading.liveReading(engine: 'mlkit_latin', matched: true, referenceYear: 2026);
      expect(live['version'], 1);
      expect(live['kind'], 'passport');
      expect(live['matched'], isTrue);
      expect(live['frames'], 2);
      expect(live['mrzFormat'], 'TD3');
      expect(live['mrz'], [passportOne, passportTwo]);
      expect(live['mrzValid'], isTrue);
      final fields = live['fields'] as Map;
      expect(fields['surname'], 'ERIKSSON');
      expect(fields['birthDate'], '1974-08-12');
      expect((live['lines'] as List).first, 'PASSPORT PASSEPORT');
      expect(live.containsKey('side'), isFalse);
      expect(sanitizeLiveReading(live), live);
    });

    test('unconfirmed lines come as read, never as fields; nothing read keeps the shape', () {
      final reading = session('identity')
        ..ingest(passportFrame(passportOne, 'L898902C36UTO7408122F1204159ZE184226B<<<<<17'));
      final live = reading.liveReading(engine: 'mlkit_latin', matched: false, referenceYear: 2026);
      expect(live['mrzValid'], isFalse);
      expect(live.containsKey('fields'), isFalse);
      expect(live['mrz'], hasLength(2));
      final empty = session('transcript').liveReading(engine: 'mlkit_latin', matched: false, referenceYear: 2026);
      expect(empty.containsKey('mrz'), isFalse);
      expect(empty['lines'], isEmpty);
      expect(empty['frames'], 0);
    });

    test('a card names the side it read', () {
      var reading = session('parent_id')
        ..ingest(cardBackFrame([cnieOne, cnieTwo, cnieThree]))
        ..ingest(cardBackFrame([cnieOne, cnieTwo, cnieThree]));
      var live = reading.liveReading(engine: 'mlkit_latin', matched: true, referenceYear: 2026);
      expect(live['side'], 'back');
      expect(live['mrzFormat'], 'TD1');
      expect((live['fields'] as Map)['personalNumber'], 'BE123456');
      reading = session('parent_id', side: 'front')
        ..ingest(cardFrontFrame())
        ..ingest(cardFrontFrame());
      live = reading.liveReading(engine: 'mlkit_latin', matched: true, referenceYear: 2026);
      expect(live['side'], 'front');
      expect(live.containsKey('mrz'), isFalse);
      expect(live['fields'], {'documentNumber': 'BE123456'});
      reading = session('highest_degree')
        ..ingest(passportFrame())
        ..ingest(passportFrame());
      live = reading.liveReading(engine: 'mlkit_latin', matched: false, referenceYear: 2026);
      expect(live['mrzFormat'], 'TD3');
      expect(live['kind'], 'paper');
    });

    test('lines are bounded, cleaned and top first', () {
      final reading = session('transcript')
        ..ingest(frame([
          for (var i = 0; i < 40; i++)
            line('Line\t$i\n${'x' * 200}', x: 0.1, y: 0.9 - i * 0.02, width: 0.8, height: 0.015),
        ]));
      final lines = reading.liveReading(engine: 'mlkit_latin', matched: false, referenceYear: 2026)['lines'] as List;
      expect(lines, hasLength(ScanTextFrameAnalysis.maximumLines));
      for (final value in lines.cast<String>()) {
        expect(value.length, lessThanOrEqualTo(ScanTextFrameAnalysis.maximumLineLength));
        expect(value.contains('\t') || value.contains('\n'), isFalse);
      }
      expect(lines[0], startsWith('Line 0 '));
      expect(lines[1], startsWith('Line 1 '));
      expect(ScanTextFrameAnalysis.clean(' \u0007 '), isNull);
    });

    test('the portal receives only checked, bounded values', () {
      expect(sanitizeLiveReading(null), isNull);
      expect(sanitizeLiveReading('passport'), isNull);
      expect(sanitizeLiveReading({'version': 1, 'kind': 'visa', 'engine': 'apple_vision'}), isNull);
      expect(sanitizeLiveReading({'version': 1, 'kind': 'paper', 'engine': 'cloud_ocr'}), isNull);
      expect(sanitizeLiveReading({'version': 2, 'kind': 'paper', 'engine': 'apple_vision'}), isNull);
      final clean = sanitizeLiveReading({
        'version': 1, 'kind': 'id_card', 'engine': 'apple_vision', 'matched': 'yes', 'frames': -3,
        'mrzFormat': 'TD3', 'mrz': [passportOne, 'L898902C36UTO7408122F1204159ZE184226B<<<<<1'],
        'mrzValid': true, 'side': 'top',
        'lines': ['ok', 42, 'two\nlines', 'x' * 500, ...List.filled(30, 'more')],
        'fields': {'surname': 'ERIKSSON', 'birthDate': '74-08-12', 'documentNumber': '<script>', 'extra': 'no'},
        'unknown': {'nested': true},
      })!;
      expect(clean['matched'], isFalse);
      expect(clean['frames'], 0);
      expect(clean.containsKey('mrz'), isFalse);
      expect(clean['mrzValid'], isFalse);
      expect(clean.containsKey('side'), isFalse);
      expect(clean.containsKey('unknown'), isFalse);
      expect(clean['fields'], {'surname': 'ERIKSSON'});
      final lines = (clean['lines'] as List).cast<String>();
      expect(lines.first, 'ok');
      expect(lines[1], 'two lines');
      expect(lines[2].length, ScanTextFrameAnalysis.maximumLineLength);
      expect(lines, hasLength(ScanTextFrameAnalysis.maximumLines));
      final card = sanitizeLiveReading({
        'version': 1, 'kind': 'id_card', 'engine': 'mlkit_latin', 'matched': true, 'frames': 4,
        'mrzFormat': 'TD1', 'mrz': [cnieOne, cnieTwo, cnieThree], 'mrzValid': true, 'side': 'back',
      })!;
      expect(card['mrz'], [cnieOne, cnieTwo, cnieThree]);
      expect(card['side'], 'back');
      expect(card['frames'], 4);
    });
  });
}
