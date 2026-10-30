#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

// Pure live text reading tests for custom-live-v12: MRZ check digits, TD1 and
// TD3 parsing, look-alike repair, multi-frame voting, the right-document gate
// and the bounded reading returned to the portal. No camera, Vision or UIKit.
// xcrun swiftc -O ios/Runner/ScannerGeometry.swift ios/Runner/ScannerTextReading.swift \
//   tools/scanner_text_reading_tests.swift -o /tmp/scanner-text-reading-tests
@main
struct ScannerTextReadingTests {
  // ICAO 9303 specimens (part 4, TD3; part 5, TD1).
  static let passportOne = "P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<"
  static let passportTwo = "L898902C36UTO7408122F1204159ZE184226B<<<<<10"
  static let cardOne = "I<UTOD231458907<<<<<<<<<<<<<<<"
  static let cardTwo = "7408122F1204159UTO<<<<<<<<<<<6"
  static let cardThree = "ERIKSSON<<ANNA<MARIA<<<<<<<<<<"
  // Real-shaped samples whose check digits were computed independently.
  static let moroccanOne = "P<MARALAMI<<MOHAMED<YASSINE<<<<<<<<<<<<<<<<<"
  static let moroccanTwo = "AB12345671MAR9903159M3102282<<<<<<<<<<<<<<<8"
  static let otherOne = "P<MARBENNANI<<SARA<<<<<<<<<<<<<<<<<<<<<<<<<<"
  static let otherTwo = "XK98765433MAR0501013F3006302CD987654<<<<<<24"
  static let extendedOne = "I<UTOD23145890<1233<<<<<<<<<<<"
  static let extendedTwo = "7408122F1204159UTO<<<<<<<<<<<2"
  static let cnieOne = "IDMARAA12345678BE123456<<<<<<<"
  static let cnieTwo = "8501019M3001019MAR<<<<<<<<<<<8"
  static let cnieThree = "ALAMI<<MOHAMED<<<<<<<<<<<<<<<<"

  /// The page inside a crop expanded by 10% about its middle.
  static let insetPage = [CGPoint(x: 0.0455, y: 0.9545), CGPoint(x: 0.9545, y: 0.9545),
                          CGPoint(x: 0.9545, y: 0.0455), CGPoint(x: 0.0455, y: 0.0455)]

  static func bytes(_ text: String) -> [UInt8] { Array(text.utf8) }

  static func line(_ text: String, x: CGFloat = 0.08, y: CGFloat, width: CGFloat = 0.84, height: CGFloat = 0.03,
                   turns: Int = 0, alternatives: [String] = []) -> ScannerTextObservation {
    ScannerTextObservation(candidates: [text] + alternatives,
      box: CGRect(x: x, y: y, width: width, height: height), quarterTurns: turns)
  }

  static func region(x: CGFloat, y: CGFloat, width: CGFloat = 0.3, height: CGFloat = 0.025) -> ScannerTextObservation {
    ScannerTextObservation(candidates: [], box: CGRect(x: x, y: y, width: width, height: height), quarterTurns: 0)
  }

  static func frame(_ lines: [ScannerTextObservation], regions: [ScannerTextObservation] = [], turns: Int = 0,
                    size: CGSize = CGSize(width: 1500, height: 1060)) -> ScannerTextFrame {
    ScannerTextFrame(lines: lines, regions: regions, quarterTurns: turns, page: insetPage, readingSize: size)
  }

  static func passportFrame(_ first: String = passportOne, _ second: String = passportTwo,
                            extra: [ScannerTextObservation] = []) -> ScannerTextFrame {
    frame([line("PASSPORT PASSEPORT", y: 0.85), line(first, y: 0.17), line(second, y: 0.11)] + extra)
  }

  static func cardBackFrame(_ lines: [String] = [cardOne, cardTwo, cardThree]) -> ScannerTextFrame {
    frame(lines.enumerated().map { line($0.element, y: 0.30 - CGFloat($0.offset) * 0.09, height: 0.05) },
      size: CGSize(width: 1100, height: 700))
  }

  static func cardFrontFrame(number: String = "BE123456") -> ScannerTextFrame {
    frame([line("ROYAUME DU MAROC", y: 0.85, height: 0.05), line("CARTE NATIONALE D'IDENTITE", y: 0.76, height: 0.05),
      line("MOHAMED", x: 0.4, y: 0.6, width: 0.3, height: 0.05), line("ALAMI", x: 0.4, y: 0.52, width: 0.2, height: 0.05),
      line("Né le 01.01.1970", x: 0.4, y: 0.44, width: 0.4, height: 0.05), line(number, x: 0.6, y: 0.12, width: 0.3, height: 0.05)],
      size: CGSize(width: 1100, height: 700))
  }

  static func paperFrame(lines count: Int = 6, extra: [ScannerTextObservation] = [],
                         size: CGSize = CGSize(width: 1100, height: 1500)) -> ScannerTextFrame {
    frame((0..<count).map { line("Ligne \($0 + 1) du certificat de scolarité", x: 0.12, y: 0.8 - CGFloat($0) * 0.08,
      width: 0.7, height: 0.025) } + extra, size: size)
  }

  static func profile(_ key: String, side: String? = nil) -> FoorsaScannerProfile {
    var source: [String: Any] = ["documentKey": key]
    if let side { source["side"] = side }
    return FoorsaScannerProfile(arguments: ["profile": source])
  }

  static func main() {
    checkDigitsAndNormalization()
    validation()
    extraction()
    voting()
    passportGate()
    cardGate()
    paperGate()
    clearPageCapture()
    autoShutter()
    geometry()
    pageTrackingAndReader()
    liveReading()
    print("PASS: ICAO 9303 check digits, TD3/TD1 parsing and look-alike repair, length repair, multi-frame voting, passport/card/paper right-document gate, clear-page capture, automatic shutter, guidance, turn search, page tracking, reader fallback, bounded live reading")
  }

  static func checkDigitsAndNormalization() {
    let two = bytes(passportTwo)
    precondition(ScannerMRZ.checkDigit(two[0..<9]) == 6)
    precondition(ScannerMRZ.checkDigit(two[13..<19]) == 2)
    precondition(ScannerMRZ.checkDigit(two[21..<27]) == 9)
    precondition(ScannerMRZ.checkDigit(two[28..<42]) == 1)
    precondition(ScannerMRZ.checkDigit(ScannerMRZ.td3Composite(two)) == 0)
    precondition(ScannerMRZ.td3LineTwoScore(two) == 4)
    let card = bytes(cardOne), cardSecond = bytes(cardTwo)
    precondition(ScannerMRZ.checkDigit(card[5..<14]) == 7)
    precondition(ScannerMRZ.checkDigit(ScannerMRZ.td1Composite(card, cardSecond)) == 6)
    precondition(ScannerMRZ.td1LineTwoShape(cardSecond) && ScannerMRZ.td1LineTwoScore(cardSecond) == 2)
    precondition(ScannerMRZ.checkDigit(bytes("<<<<<<")) == 0)
    precondition(ScannerMRZ.checkDigit(bytes("AB-12")) == nil)
    precondition(!ScannerMRZ.passes(bytes("740812"), check: UInt8(ascii: "<")))
    precondition(ScannerMRZ.isDate(bytes("740812")) && !ScannerMRZ.isDate(bytes("741312")) && !ScannerMRZ.isDate(bytes("740800")))

    // Lower case, spaces and chevron look-alikes come back to the MRZ alphabet.
    let normalized = ScannerMRZ.normalize("p<uto eriksson«anna‹maria")
    precondition(normalized.characters == bytes("P<UTOERIKSSON<<ANNA<MARIA") && normalized.dropped == 0)
    precondition(ScannerMRZ.normalize("Né le").dropped == 1)

    // Each position in its own alphabet; a misread filler run cleared.
    let fields = ScannerMRZFormat.td3.fields
    let misread = ScannerMRZ.conform(bytes("L898902C36UT07408I2ZF12O4I59ZE184226B<<<<<1O"), to: fields[1])
    precondition(misread == two)
    let names = ScannerMRZ.conform(bytes("P<UT0ERIKSSON<<ANNA<MARIAKKKKKKKKKKKKKKKKKKK"), to: fields[0])
    precondition(names == bytes(passportOne))
    // A double letter in a name is a name.
    precondition(ScannerMRZ.conform(bytes("P<MARELLA<<LL<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<"), to: fields[0])
      == bytes("P<MARELLA<<LL<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<"))

    // A filler gained or lost is repaired; a line far off the length is not this format.
    let long = Array(passportTwo.utf8.prefix(38)) + [ScannerMRZ.filler] + Array(passportTwo.utf8.dropFirst(38))
    precondition(long.count == 45 && ScannerMRZ.lengthVariants(long, length: 44).contains(two))
    let short = Array(passportTwo.utf8.prefix(38)) + Array(passportTwo.utf8.dropFirst(39))
    precondition(short.count == 43 && ScannerMRZ.lengthVariants(short, length: 44).contains(two))
    let twoShort = Array(passportTwo.utf8.prefix(37)) + Array(passportTwo.utf8.dropFirst(39))
    precondition(ScannerMRZ.lengthVariants(twoShort, length: 44).contains(two))
    precondition(ScannerMRZ.lengthVariants(Array(passportTwo.utf8.prefix(41)), length: 44).isEmpty)
    precondition(ScannerMRZ.padded(bytes("ERIKSSON<<ANNA<MARIA<<<<<<<<"), length: 30) == bytes(cardThree))
    precondition(ScannerMRZ.padded(bytes(cardThree + "<<"), length: 30) == bytes(cardThree))
    precondition(ScannerMRZ.padded(bytes("ERIKSSON<<ANNA<MARIA<<<<<<<<<<XY"), length: 30) == nil)
  }

  static func validation() {
    // Specimens and the real-shaped samples are valid.
    for (lines, format) in [([passportOne, passportTwo], ScannerMRZFormat.td3), ([moroccanOne, moroccanTwo], .td3),
                            ([otherOne, otherTwo], .td3), ([cardOne, cardTwo, cardThree], .td1),
                            ([extendedOne, extendedTwo, cardThree], .td1), ([cnieOne, cnieTwo, cnieThree], .td1)] {
      let result = ScannerMRZValidator.validate(lines.map(bytes), format: format)
      precondition(result.valid && result.text == lines, "\(format) sample must be valid")
    }
    // A look-alike in the alphanumeric document number is repaired by its check digit.
    let lookAlike = ScannerMRZValidator.validate([bytes(passportOne), bytes("L8989O2C36UTO7408122F1204159ZE184226B<<<<<10")],
      format: .td3)
    precondition(lookAlike.valid && lookAlike.text == [passportOne, passportTwo])
    // Z→2 and B→8 both satisfy this personal number's check digit, and the
    // composite weighs the field alike: alone, the reading refuses to guess...
    let personalTwo = bytes("L898902C36UTO7408122F1204159ZE1B4226B<<<<<10")
    precondition(!ScannerMRZValidator.validate([bytes(passportOne), personalTwo], format: .td3).valid)
    // ...and with votes, the character another read actually saw decides.
    var votes = ScannerMRZVotes(format: .td3)
    votes.add([bytes(passportOne), personalTwo])
    votes.add([bytes(passportOne), personalTwo])
    votes.add([bytes(passportOne), bytes(passportTwo)])
    precondition(votes.consensus[1] == personalTwo)
    let repaired = ScannerMRZValidator.validate([bytes(passportOne), personalTwo], format: .td3, tallies: votes.counts)
    precondition(repaired.valid && repaired.text[1] == passportTwo)
    // Any wrong check digit, date or shape keeps the reading invalid.
    for broken in ["L898902C36UTO7408122F1204159ZE184226B<<<<<11", "L898902C36UTO7408123F1204159ZE184226B<<<<<10",
                   "L898902C36UTO7408122F1204158ZE184226B<<<<<10", "L898902C37UTO7408122F1204159ZE184226B<<<<<10",
                   "L898902C36UTO7413122F1204159ZE184226B<<<<<10", "L898902C36UTO7408122Q1204159ZE184226B<<<<<10"] {
      precondition(!ScannerMRZValidator.validate([bytes(passportOne), bytes(broken)], format: .td3).valid)
    }
    precondition(!ScannerMRZValidator.validate([bytes("I<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<"), bytes(passportTwo)],
      format: .td3).valid)
    precondition(!ScannerMRZValidator.validate([bytes(passportOne)], format: .td3).valid)
    precondition(!ScannerMRZValidator.validate([bytes(cardOne), bytes("7408122F1204159UTO<<<<<<<<<<<7"), bytes(cardThree)],
      format: .td1).valid)
    precondition(!ScannerMRZValidator.validate([bytes("P<UTOD231458907<<<<<<<<<<<<<<<"), bytes(cardTwo), bytes(cardThree)],
      format: .td1).valid)
    // An unused personal number may carry a filler or a zero as its check digit, nothing else.
    precondition(ScannerMRZValidator.validate([bytes(moroccanOne), bytes(moroccanTwo)], format: .td3).valid)

    // Fields, with ISO dates and the century from the reference year.
    let fields = ScannerMRZFields(ScannerMRZValidator.validate([bytes(passportOne), bytes(passportTwo)], format: .td3))!
    precondition(fields.surname == "ERIKSSON" && fields.givenNames == "ANNA MARIA")
    precondition(fields.documentNumber == "L898902C3" && fields.nationality == "UTO" && fields.issuingState == "UTO")
    precondition(fields.personalNumber == "ZE184226B" && fields.sex == "F")
    let dictionary = fields.dictionary(referenceYear: 2026)
    precondition(dictionary["birthDate"] == "1974-08-12" && dictionary["expiryDate"] == "2012-04-15")
    precondition(ScannerMRZFields.isoDate("050101", birth: true, referenceYear: 2026) == "2005-01-01")
    precondition(ScannerMRZFields.isoDate("300630", birth: true, referenceYear: 2026) == "1930-06-30")
    precondition(ScannerMRZFields.isoDate("310228", birth: false, referenceYear: 2026) == "2031-02-28")
    let moroccan = ScannerMRZFields(ScannerMRZValidator.validate([bytes(moroccanOne), bytes(moroccanTwo)], format: .td3))!
    precondition(moroccan.givenNames == "MOHAMED YASSINE" && moroccan.personalNumber.isEmpty)
    precondition(moroccan.dictionary(referenceYear: 2026)["personalNumber"] == nil)
    precondition(moroccan.dictionary(referenceYear: 2026)["birthDate"] == "1999-03-15")
    let extended = ScannerMRZFields(ScannerMRZValidator.validate([bytes(extendedOne), bytes(extendedTwo), bytes(cardThree)],
      format: .td1))!
    precondition(extended.documentNumber == "D23145890123" && extended.surname == "ERIKSSON")
    let cnie = ScannerMRZFields(ScannerMRZValidator.validate([bytes(cnieOne), bytes(cnieTwo), bytes(cnieThree)], format: .td1))!
    precondition(cnie.documentNumber == "AA1234567" && cnie.personalNumber == "BE123456" && cnie.issuingState == "MAR")
    precondition(cnie.surname == "ALAMI" && cnie.givenNames == "MOHAMED" && cnie.sex == "M")
    precondition(ScannerMRZFields(ScannerMRZResult(format: .td3, lines: [], valid: false)) == nil)
  }

  static func extraction() {
    // The specimen as Vision might return it: spaces, « for a filler pair, O for zero.
    let noisy = [line("P<UTO ERIKSSON«ANNA<MARIA<<<<<<<<<<<<<<<<<<<", y: 0.17),
                 line("L898902C36UTO74O8122F12O4159ZE184226B<<<<<1O", y: 0.11)]
    let rows = ScannerMRZReader.machineRows(noisy + [line("REPUBLIC OF UTOPIA", y: 0.9)])
    precondition(rows.count == 2)
    let found = ScannerMRZReader.td3(in: rows)
    precondition(found?[0] == bytes(passportOne) && found?[1] == bytes(passportTwo))
    // A line split at its filler run is one row.
    let split = [line(passportOne, y: 0.17),
                 line("L898902C36UTO7408122F12", x: 0.08, y: 0.11, width: 0.42),
                 line("04159ZE184226B<<<<<10", x: 0.52, y: 0.112, width: 0.40)]
    precondition(ScannerMRZReader.td3(in: ScannerMRZReader.machineRows(split))?[1] == bytes(passportTwo))
    // One extra filler in line two is repaired when three checks then pass.
    let extra = String(passportTwo.prefix(38)) + "<" + String(passportTwo.dropFirst(38))
    precondition(ScannerMRZReader.td3(in: ScannerMRZReader.machineRows([line(passportOne, y: 0.17), line(extra, y: 0.11)]))?[1]
      == bytes(passportTwo))
    // Line two alone still counts; a stray line elsewhere is not line one.
    let alone = ScannerMRZReader.td3(in: ScannerMRZReader.machineRows([line(passportOne, y: 0.6), line(passportTwo, y: 0.11)]))
    precondition(alone?[0] == nil && alone?[1] == bytes(passportTwo))
    // An ID card's three lines, and nothing from ordinary text.
    let card = ScannerMRZReader.td1(in: ScannerMRZReader.machineRows(cardBackFrame().lines))
    precondition(card?[0] == bytes(cardOne) && card?[1] == bytes(cardTwo) && card?[2] == bytes(cardThree))
    precondition(ScannerMRZReader.td3(in: ScannerMRZReader.machineRows(cardBackFrame().lines)) == nil)
    precondition(ScannerMRZReader.machineRows(paperFrame().lines).isEmpty)
    // A line two failing three of its four checks is not offered as a vote.
    precondition(ScannerMRZ.td3LineTwoScore(bytes("L898902C36UTO7408123F1204158ZE184226B<<<<<10")) == 1)
    precondition(ScannerMRZReader.td3(in: ScannerMRZReader.machineRows([line(passportOne, y: 0.17),
      line("L898902C36UTO7408123F1204158ZE184226B<<<<<10", y: 0.11)])) == nil)
  }

  static func voting() {
    var votes = ScannerMRZVotes(format: .td3)
    precondition(votes.consensus.allSatisfy { $0 == nil })
    let good: [[UInt8]?] = [bytes(passportOne), bytes(passportTwo)]
    let noisy: [[UInt8]?] = [bytes("P<UTOERIKSSON<<ANNA<MARLA<<<<<<<<<<<<<<<<<<<"), bytes("L898902C36UTO7408122F1204159ZE184226B<<<<<17")]
    votes.add(good)
    votes.add(noisy)
    votes.add(good)
    precondition(votes.consensus[0] == bytes(passportOne) && votes.consensus[1] == bytes(passportTwo))
    precondition(votes.supportingReads(for: [bytes(passportOne), bytes(passportTwo)]) == 3)
    precondition(votes.disagreement(with: [nil, bytes(otherTwo)])! > 0.3)
    precondition(votes.disagreement(with: noisy)! < 0.05)
    // Line two without line one still votes for line two.
    votes.add([nil, bytes(passportTwo)])
    precondition(votes.reads.count == 4)
    votes.add([nil, nil])
    precondition(votes.reads.count == 4)
    for _ in 0..<10 { votes.add(good) }
    precondition(votes.reads.count == ScannerMRZVotes.maximumReads)
    for symbol in 0..<ScannerMRZVotes.symbols {
      precondition(ScannerMRZVotes.symbol(ScannerMRZVotes.character(symbol)) == symbol)
    }
  }

  static func passportGate() {
    let passport = profile("identity")
    precondition(passport.paperKind == .passport && !passport.rejectsIdentityPapers)
    var session = ScannerTextReadingSession(profile: passport)
    precondition(session.status(glare: false) == .waiting(.reading))
    session.ingest(passportFrame())
    // One read is not enough, however clean.
    precondition(session.status(glare: false) == .waiting(.reading))
    session.ingest(passportFrame())
    precondition(session.status(glare: false) == .passedReading)

    // One bad frame does not block it: votes outweigh it.
    session = ScannerTextReadingSession(profile: passport)
    session.ingest(passportFrame(passportOne, "L898902C36UTO7408122F1204159ZE184226B<<<<<17"))
    session.ingest(passportFrame())
    session.ingest(passportFrame())
    precondition(session.status(glare: false).passed)

    // No machine lines: wait one read (the other way up), then guide.
    session = ScannerTextReadingSession(profile: passport)
    precondition(session.turnPolicy == .landscape(upsideDown: false))
    session.ingest(frame([line("REPUBLIC OF UTOPIA", y: 0.8)]))
    precondition(session.status(glare: false) == .waiting(.reading))
    precondition(session.turnPolicy == .landscape(upsideDown: true))
    session.ingest(frame([line("REPUBLIC OF UTOPIA", y: 0.8)], turns: 2))
    precondition(session.status(glare: false) == .waiting(.showMachineLines))
    precondition(session.status(glare: true) == .waiting(.glareOnMachineLines))
    precondition(session.turnPolicy == .landscape(upsideDown: false))
    // Found the right way up: the turn stays.
    session.ingest(passportFrame())
    precondition(session.turnPolicy == .landscape(upsideDown: false))
    session.ingest(frame([line("REPUBLIC OF UTOPIA", y: 0.8)]))
    precondition(session.turnPolicy == .landscape(upsideDown: false))

    // A far page, small machine lines, cut lines, glare: each says what to change.
    session = ScannerTextReadingSession(profile: passport)
    session.ingest(frame([line("REPUBLIC OF UTOPIA", y: 0.8)], size: CGSize(width: 700, height: 495)))
    precondition(session.status(glare: false) == .waiting(.moveCloserMachineLines))
    session = ScannerTextReadingSession(profile: passport)
    session.ingest(frame([line(passportOne, y: 0.17, height: 0.008), line("L898902C36UTO7408122F1204159ZE18", y: 0.11, height: 0.008)]))
    precondition(session.status(glare: false) == .waiting(.moveCloserMachineLines))
    session = ScannerTextReadingSession(profile: passport)
    session.ingest(frame([line(passportOne, y: 0.17), line("L898902C36UTO7408122F1204159ZE18", x: 0.3, y: 0.11, width: 0.7)]))
    precondition(session.status(glare: false) == .waiting(.showWholeMachineLines))
    session = ScannerTextReadingSession(profile: passport)
    session.ingest(frame([line(passportOne, y: 0.17), line("L898902C36UTO7408122F12041", y: 0.11)]))
    precondition(session.status(glare: true) == .waiting(.glareOnMachineLines))
    precondition(session.status(glare: false) == .waiting(.reading))

    // An ID card in the passport step is a different paper.
    session = ScannerTextReadingSession(profile: passport)
    session.ingest(cardBackFrame())
    session.ingest(cardBackFrame())
    precondition(session.status(glare: false) == .waiting(.differentPaper))

    // Another passport's lines replace the first one's votes.
    session = ScannerTextReadingSession(profile: passport)
    session.ingest(passportFrame())
    session.ingest(passportFrame())
    session.ingest(passportFrame(otherOne, otherTwo))
    precondition(session.machineReading(.td3)?.result.text == [otherOne, otherTwo])
    precondition(!session.status(glare: false).passed)
    session.ingest(passportFrame(otherOne, otherTwo))
    precondition(session.status(glare: false).passed)
  }

  static func cardGate() {
    let back = profile("parent_id", side: "back")
    precondition(back.paperKind == .idCard && back.cardSide == .back)
    precondition(profile("parent_id", side: "sideways").cardSide == nil && profile("parent_id").cardSide == nil)
    var session = ScannerTextReadingSession(profile: back)
    session.ingest(cardBackFrame())
    session.ingest(cardBackFrame())
    precondition(session.status(glare: false) == .passedReading)
    // A Moroccan card's back.
    session = ScannerTextReadingSession(profile: back)
    session.ingest(cardBackFrame([cnieOne, cnieTwo, cnieThree]))
    session.ingest(cardBackFrame([cnieOne, cnieTwo, cnieThree]))
    precondition(session.status(glare: false).passed)
    // The front when the back is asked for.
    session = ScannerTextReadingSession(profile: back)
    session.ingest(cardFrontFrame())
    session.ingest(cardFrontFrame())
    precondition(session.status(glare: false) == .waiting(.turnCardToBack))

    let front = profile("parent_id", side: "front")
    session = ScannerTextReadingSession(profile: front)
    session.ingest(cardFrontFrame())
    precondition(session.status(glare: false) == .waiting(.reading))
    session.ingest(cardFrontFrame())
    precondition(session.status(glare: false) == .passedReading && session.frontNumber == "BE123456")
    session = ScannerTextReadingSession(profile: front)
    session.ingest(cardBackFrame())
    session.ingest(cardBackFrame())
    precondition(session.status(glare: false) == .waiting(.turnCardToFront))
    // A passport in the card step.
    session = ScannerTextReadingSession(profile: front)
    session.ingest(passportFrame())
    session.ingest(passportFrame())
    precondition(session.status(glare: false) == .waiting(.differentPaper))
    // An unreadable or far card front says what to change.
    session = ScannerTextReadingSession(profile: front)
    session.ingest(frame([line("MOHAMED", y: 0.5, width: 0.3)], size: CGSize(width: 500, height: 320)))
    precondition(session.status(glare: false) == .waiting(.moveCloserText))
    session = ScannerTextReadingSession(profile: front)
    session.ingest(frame([]))
    session.ingest(frame([]))
    precondition(session.status(glare: false) == .waiting(.showCardDetails))
    precondition(session.status(glare: true) == .waiting(.glareOnText))

    // Without a side, either side is the card.
    let either = profile("parent_id")
    session = ScannerTextReadingSession(profile: either)
    session.ingest(cardBackFrame())
    session.ingest(cardBackFrame())
    precondition(session.status(glare: false).passed)
    session = ScannerTextReadingSession(profile: either)
    session.ingest(cardFrontFrame())
    session.ingest(cardFrontFrame())
    precondition(session.status(glare: false).passed)
    // Machine lines seen but not read yet: guidance for the lines.
    session = ScannerTextReadingSession(profile: either)
    session.ingest(frame([line(cardOne, y: 0.3, width: 0.84, height: 0.006), line("7408122F1204159UTO<<<<<<", y: 0.21, height: 0.006)],
      size: CGSize(width: 1100, height: 700)))
    precondition(session.status(glare: false) == .waiting(.moveCloserMachineLines))

    // A Tunisian card front: eight digits and lines of Arabic print found but not read.
    session = ScannerTextReadingSession(profile: front)
    let arabic = (0..<5).map { region(x: 0.3, y: 0.8 - CGFloat($0) * 0.12, width: 0.5, height: 0.06) }
    let tunisian = frame([line("12345678", x: 0.55, y: 0.15, width: 0.3, height: 0.05)], regions: arabic,
      size: CGSize(width: 1100, height: 700))
    session.ingest(tunisian)
    session.ingest(tunisian)
    precondition(session.status(glare: false).passed && session.frontNumber == "12345678")

    // Card numbers on a front.
    precondition(ScannerCardFront.numbers(in: ["N° BE123456"]) == ["BE123456"])
    precondition(ScannerCardFront.numbers(in: ["BE 123456"]) == ["BE123456"])
    precondition(ScannerCardFront.numbers(in: ["BE12345G"]) == ["BE123456"])
    precondition(ScannerCardFront.numbers(in: ["CAN 123456", "01.01.1970", "Né le 12.03.1985", "ABDELLAH"]).isEmpty)
    precondition(ScannerCardFront.numbers(in: ["12345678"]) == ["12345678"])
    precondition(ScannerCardFront.numbers(in: ["1234567", "123456789"]).isEmpty)
    precondition(ScannerCardFront.hasKeyword(["Royaume du Maroc"]) && !ScannerCardFront.hasKeyword(["MOHAMED"]))
  }

  // The owner, 30 Oct 2026: "it should be automatic once the shot is clear". A
  // clear, steady page no longer waits on the reading for long: only the wrong
  // paper, or the wrong side of a card, keeps it waiting.
  static func clearPageCapture() {
    let passed = ScannerTextGateStatus.passedReading
    precondition(passed.capturesWhenClear(for: 0, kind: .passport))
    precondition(ScannerTextGateStatus.cannotRead.capturesWhenClear(for: 0, kind: .paper))
    for kind in [ScannerPaperKind.passport, .idCard, .paper] {
      let grace = ScannerTextGateStatus.clearPageGrace(for: kind)
      for guidance in [ScannerTextGuidance.reading, .showMachineLines, .moveCloserMachineLines, .glareOnMachineLines,
                       .showWholeMachineLines, .showCardDetails, .glareOnText, .moveCloserText, .showPrintedText,
                       .textRunsPastEdge] {
        let waiting = ScannerTextGateStatus.waiting(guidance)
        precondition(!guidance.holdsCapture)
        precondition(!waiting.capturesWhenClear(for: grace - 0.05, kind: kind))
        precondition(waiting.capturesWhenClear(for: grace, kind: kind))
      }
      for guidance in [ScannerTextGuidance.differentPaper, .turnCardToFront, .turnCardToBack] {
        precondition(guidance.holdsCapture)
        precondition(!ScannerTextGateStatus.waiting(guidance).capturesWhenClear(for: 60, kind: kind))
      }
    }
    // The lines on a passport or a card get a little longer than a paper's rows.
    precondition(ScannerTextGateStatus.clearPageGrace(for: .paper) < ScannerTextGateStatus.clearPageGrace(for: .passport))
    precondition(ScannerTextGateStatus.clearPageGrace(for: .passport) <= 2)
  }

  /// Frames 0.1 s apart from `start`, each with the page state `page(time)`; the time the page was
  /// first taken, or nil when it never was.
  static func takenAt(_ kind: ScannerPaperKind, until end: TimeInterval, start: TimeInterval = 10,
                      reading: ScannerTextGateStatus = .waiting(.reading), lightingGood: Bool = true,
                      shutter: inout ScannerAutoShutter,
                      page: (TimeInterval) -> ScannerAutoShutter.Page) -> TimeInterval? {
    var step = 0
    while Double(step) / 10 <= end + 1e-9 {
      let time = start + Double(step) / 10
      if shutter.observe(page(time), at: time, reading: reading, kind: kind, lightingGood: lightingGood) {
        return time - start
      }
      step += 1
    }
    return nil
  }

  // The owner, 30 Oct 2026, on build 54: the scanner still needed the button. A soft frame or a
  // tremor started the wait over; now the page is taken steady and read, steady for a moment, or
  // in view long enough, and never while the reading sees the wrong paper.
  static func autoShutter() {
    func near(_ value: TimeInterval?, _ expected: TimeInterval) -> Bool {
      value.map { abs($0 - expected) < 0.051 } ?? false
    }
    // Steady and read: at once.
    var shutter = ScannerAutoShutter()
    precondition(near(takenAt(.passport, until: 5, reading: .passedReading, shutter: &shutter) { _ in .steady }, 0))
    shutter = ScannerAutoShutter()
    precondition(near(takenAt(.paper, until: 5, reading: .cannotRead, shutter: &shutter) { _ in .steady }, 0))
    // Steady while the reading still looks: after the paper's grace.
    for kind in [ScannerPaperKind.paper, .passport, .idCard] {
      shutter = ScannerAutoShutter()
      let grace = ScannerTextGateStatus.clearPageGrace(for: kind)
      precondition(near(takenAt(kind, until: 10, shutter: &shutter) { _ in .steady }, grace))
      // A soft frame every third frame no longer starts the grace over.
      shutter = ScannerAutoShutter()
      let flicker = takenAt(kind, until: 10, shutter: &shutter) { time in
        Int(((time - 10) * 10).rounded()) % 3 == 2 ? .inView : .steady
      }
      precondition(flicker.map { $0 <= grace + 0.15 } ?? false)
    }
    // Shadow, glare or dim light: a moment to fix it, then the page is taken anyway.
    shutter = ScannerAutoShutter()
    precondition(near(takenAt(.paper, until: 10, lightingGood: false, shutter: &shutter) { _ in .steady },
      ScannerAutoShutter.lightingGrace))
    // In view, never steady or sharp: taken once its limit is over.
    for kind in [ScannerPaperKind.paper, .passport, .idCard] {
      shutter = ScannerAutoShutter()
      let limit = ScannerAutoShutter.inViewLimit(for: kind)
      precondition(near(takenAt(kind, until: 10, shutter: &shutter) { _ in .inView }, limit))
      precondition(limit <= 3.5)
    }
    // Out of view for a moment keeps the clocks; out of view a while starts them over.
    shutter = ScannerAutoShutter()
    let blink = takenAt(.paper, until: 10, shutter: &shutter) { time in
      (11...11.5).contains(time) ? .missing : .inView
    }
    precondition(near(blink, ScannerAutoShutter.inViewLimit(for: .paper)))
    shutter = ScannerAutoShutter()
    let away = takenAt(.paper, until: 10, shutter: &shutter) { time in
      (11...12).contains(time) ? .missing : .inView
    }
    precondition(near(away, 2.1 + ScannerAutoShutter.inViewLimit(for: .paper)))
    // No page, nothing taken.
    shutter = ScannerAutoShutter()
    precondition(takenAt(.paper, until: 10, reading: .passedReading, shutter: &shutter) { _ in .missing } == nil)
    // The wrong paper, or the wrong side of a card, is never taken, steady or in view.
    for guidance in [ScannerTextGuidance.differentPaper, .turnCardToFront, .turnCardToBack] {
      for page in [ScannerAutoShutter.Page.steady, .inView] {
        shutter = ScannerAutoShutter()
        precondition(takenAt(.idCard, until: 60, reading: .waiting(guidance), shutter: &shutter) { _ in page } == nil)
      }
    }
    // A clock that cannot be read starts everything over.
    shutter = ScannerAutoShutter()
    _ = shutter.observe(.steady, at: 1, reading: .waiting(.reading), kind: .paper, lightingGood: true)
    precondition(shutter.steadySince == 1 && shutter.inViewSince == 1)
    precondition(!shutter.observe(.steady, at: .nan, reading: .passedReading, kind: .paper, lightingGood: true))
    precondition(shutter.steadySince == nil && shutter.inViewSince == nil)
  }

  static func paperGate() {
    let diploma = profile("highest_degree")
    precondition(diploma.paperKind == .paper && diploma.rejectsIdentityPapers)
    precondition(!profile("visa_documents").rejectsIdentityPapers && !profile("drive_files").rejectsIdentityPapers)
    precondition(profile("cv").paperKind == .paper && profile("medical_check").paperKind == .paper)
    var session = ScannerTextReadingSession(profile: diploma)
    precondition(session.turnPolicy == .fixed(0))
    session.ingest(paperFrame())
    precondition(session.status(glare: false) == .waiting(.reading))
    session.ingest(paperFrame())
    precondition(session.status(glare: false) == .passedReading)
    precondition(session.turnPolicy == .fixed(0))

    // Text that runs past the page's detected edge: an inner frame, not the paper.
    let runsOff = line("Université Mohammed V de Rabat, Faculté", x: 0.5, y: 0.5, width: 0.49, height: 0.025)
    session = ScannerTextReadingSession(profile: diploma)
    session.ingest(paperFrame(extra: [runsOff]))
    precondition(session.status(glare: false) == .waiting(.reading))
    session.ingest(paperFrame(extra: [runsOff]))
    precondition(session.status(glare: false) == .waiting(.textRunsPastEdge))
    session.ingest(paperFrame())
    precondition(session.status(glare: false) == .waiting(.reading))
    session.ingest(paperFrame())
    precondition(session.status(glare: false).passed)
    // Text reaching the frame at the crop border is cut too; text wholly outside the page is the table.
    let atFrame = line("Royaume du Maroc — Ministère", x: 0.0, y: 0.6, width: 0.3, height: 0.025)
    precondition(ScannerTextLayout.summarize(lines: paperFrame(extra: [atFrame]).lines, regions: [], page: insetPage).cutRows == 1)
    let outside = line("magazine headline outside", x: 0.955, y: 0.6, width: 0.044, height: 0.02)
    precondition(ScannerTextLayout.summarize(lines: paperFrame(extra: [outside]).lines, regions: [], page: insetPage).cutRows == 0)
    // A sliver past the edge (detector jitter) is not a cut.
    let sliver = line("Signature du directeur", x: 0.6, y: 0.2, width: 0.36, height: 0.025)
    precondition(ScannerTextLayout.summarize(lines: [sliver], regions: [], page: insetPage).cutRows == 0)

    // A far page asks to move closer; a near blank one for the printed side.
    session = ScannerTextReadingSession(profile: diploma)
    session.ingest(paperFrame(lines: 1, size: CGSize(width: 600, height: 800)))
    precondition(session.status(glare: false) == .waiting(.moveCloserText))
    session = ScannerTextReadingSession(profile: diploma)
    session.ingest(paperFrame(lines: 0))
    precondition(session.status(glare: false) == .waiting(.reading))
    session.ingest(paperFrame(lines: 0))
    precondition(session.status(glare: false) == .waiting(.showPrintedText))

    // Arabic or Chinese print is found but not read: it still counts, and the
    // turn search settles on the page as seen.
    session = ScannerTextReadingSession(profile: diploma)
    let print = (0..<5).map { region(x: 0.15, y: 0.8 - CGFloat($0) * 0.1, width: 0.6) }
    session.ingest(frame([], regions: print))
    precondition(session.turnPolicy == .fixed(1))
    session.ingest(frame([], regions: print, turns: 1))
    precondition(session.turnPolicy == .fixed(3))
    session.ingest(frame([], regions: print, turns: 3))
    precondition(session.turnPolicy == .fixed(0))
    precondition(session.status(glare: false).passed)
    // A page read only when turned a quarter keeps that turn.
    session = ScannerTextReadingSession(profile: diploma)
    session.ingest(paperFrame(lines: 0))
    session.ingest(paperFrame(lines: 5).withTurns(1))
    precondition(session.turnPolicy == .fixed(1))

    // A passport in a diploma's step; but a visa step may hold machine lines.
    session = ScannerTextReadingSession(profile: diploma)
    session.ingest(passportFrame(extra: paperFrame().lines))
    session.ingest(passportFrame(extra: paperFrame().lines))
    precondition(session.status(glare: false) == .waiting(.differentPaper))
    session = ScannerTextReadingSession(profile: profile("visa_documents"))
    session.ingest(passportFrame(extra: paperFrame().lines))
    session.ingest(passportFrame(extra: paperFrame().lines))
    precondition(session.status(glare: false).passed)

    // Rows: words of one line are one row; narrow specks are not rows.
    precondition(ScannerTextLayout.rows([CGRect(x: 0.1, y: 0.5, width: 0.2, height: 0.03),
      CGRect(x: 0.35, y: 0.505, width: 0.2, height: 0.03), CGRect(x: 0.1, y: 0.4, width: 0.3, height: 0.03),
      CGRect(x: 0.5, y: 0.2, width: 0.02, height: 0.02)]) == 2)
  }

  static func geometry() {
    // The crop is the page expanded about its middle; the page sits inset in it.
    let page = ScannerQuadrilateral(topLeft: CGPoint(x: 0.2, y: 0.8), topRight: CGPoint(x: 0.8, y: 0.8),
      bottomRight: CGPoint(x: 0.8, y: 0.3), bottomLeft: CGPoint(x: 0.2, y: 0.3))
    let inside = ScannerTextGeometry.pageInCrop(page: page, crop: page.expanded(by: ScannerTextGeometry.cropExpansion))!
    let inset = 0.05 / 1.1
    for (point, expected) in zip(inside, [CGPoint(x: inset, y: 1 - inset), CGPoint(x: 1 - inset, y: 1 - inset),
                                          CGPoint(x: 1 - inset, y: inset), CGPoint(x: inset, y: inset)]) {
      precondition(abs(point.x - expected.x) < 1e-9 && abs(point.y - expected.y) < 1e-9)
    }
    // A page in perspective: the crop's own corners are the unit square, the page stays inside it.
    let tilted = ScannerQuadrilateral(topLeft: CGPoint(x: 0.25, y: 0.82), topRight: CGPoint(x: 0.75, y: 0.80),
      bottomRight: CGPoint(x: 0.85, y: 0.18), bottomLeft: CGPoint(x: 0.12, y: 0.20))
    let crop = tilted.expanded(by: ScannerTextGeometry.cropExpansion)
    let square = ScannerTextGeometry.pageInCrop(page: crop, crop: crop)!
    for (point, expected) in zip(square, [CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 0)]) {
      precondition(abs(point.x - expected.x) < 1e-9 && abs(point.y - expected.y) < 1e-9)
    }
    let tiltedPage = ScannerTextGeometry.pageInCrop(page: tilted, crop: crop)!
    precondition(tiltedPage.allSatisfy { $0.x > 0.01 && $0.x < 0.99 && $0.y > 0.01 && $0.y < 0.99 })
    let homography = ScannerHomography(unitSquareTo: [tilted.bottomLeft, tilted.bottomRight, tilted.topRight, tilted.topLeft])!
    let middle = homography.map(CGPoint(x: 0.5, y: 0.5))!
    let back = homography.inverted()!.map(middle)!
    precondition(abs(back.x - 0.5) < 1e-9 && abs(back.y - 0.5) < 1e-9)
    precondition(ScannerHomography(unitSquareTo: [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 2, y: 2),
      CGPoint(x: 3, y: 3)]) == nil || ScannerHomography(unitSquareTo: [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1),
      CGPoint(x: 2, y: 2), CGPoint(x: 3, y: 3)])?.inverted() == nil)

    // Quarter turns round-trip, and a turned box comes back to the page's own frame.
    let point = CGPoint(x: 0.2, y: 0.7)
    for turns in -1...5 {
      let there = ScannerQuarterTurn.apply(turns, point)
      let again = ScannerQuarterTurn.undo(turns, there)
      precondition(abs(again.x - point.x) < 1e-12 && abs(again.y - point.y) < 1e-12)
    }
    precondition(ScannerQuarterTurn.apply(1, CGPoint(x: 1, y: 0.5)) == CGPoint(x: 0.5, y: 1))
    precondition(ScannerQuarterTurn.apply(3, CGPoint(x: 1, y: 0.5)) == CGPoint(x: 0.5, y: 0))
    let turned = ScannerQuarterTurn.undo(1, CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.1))
    precondition(abs(turned.minX - 0.2) < 1e-12 && abs(turned.maxX - 0.3) < 1e-12)
    precondition(abs(turned.minY - 0.6) < 1e-12 && abs(turned.maxY - 0.9) < 1e-12)
    precondition(ScannerTextTurnPolicy.landscape(upsideDown: false).quarterTurns(width: 1500, height: 1000) == 0)
    precondition(ScannerTextTurnPolicy.landscape(upsideDown: false).quarterTurns(width: 1000, height: 1500) == 1)
    precondition(ScannerTextTurnPolicy.landscape(upsideDown: true).quarterTurns(width: 1500, height: 1000) == 2)
    precondition(ScannerTextTurnPolicy.landscape(upsideDown: true).quarterTurns(width: 1000, height: 1500) == 3)
    precondition(ScannerTextTurnPolicy.fixed(-1).quarterTurns(width: 1, height: 1) == 3)
    precondition(ScannerTextGeometry.overhang(of: CGRect(x: 0.5, y: 0.5, width: 0.6, height: 0.1),
      beyond: CGRect(x: 0, y: 0, width: 1, height: 1)) > 0.09)
    precondition(ScannerTextReadSettings.settings(for: .passport).languages == ["en-US"])
    precondition(!ScannerTextReadSettings.settings(for: .passport).detectsRegions)
    precondition(ScannerTextReadSettings.settings(for: .paper).detectsRegions)
  }

  static func pageTrackingAndReader() {
    let page = ScannerQuadrilateral(topLeft: CGPoint(x: 0.2, y: 0.8), topRight: CGPoint(x: 0.8, y: 0.8),
      bottomRight: CGPoint(x: 0.8, y: 0.3), bottomLeft: CGPoint(x: 0.2, y: 0.3))
    var session = ScannerTextReadingSession(profile: profile("identity"))
    precondition(!session.observePage(page, at: 0))
    session.ingest(passportFrame())
    // A short miss keeps the votes; a page gone for 1.5 s starts over.
    precondition(!session.observePage(nil, at: 0.2) && !session.observePage(nil, at: 1.0))
    precondition(session.framesRead == 1)
    precondition(session.observePage(nil, at: 1.8) && session.framesRead == 0)
    precondition(!session.observePage(nil, at: 4.0))
    // A jump to a different outline starts over too; drift does not.
    precondition(!session.observePage(page, at: 5))
    session.ingest(passportFrame())
    let drifted = ScannerQuadrilateral(topLeft: CGPoint(x: 0.22, y: 0.8), topRight: CGPoint(x: 0.82, y: 0.8),
      bottomRight: CGPoint(x: 0.82, y: 0.3), bottomLeft: CGPoint(x: 0.22, y: 0.3))
    precondition(!session.observePage(drifted, at: 5.1) && session.framesRead == 1)
    let elsewhere = ScannerQuadrilateral(topLeft: CGPoint(x: 0.5, y: 0.95), topRight: CGPoint(x: 0.95, y: 0.95),
      bottomRight: CGPoint(x: 0.95, y: 0.55), bottomLeft: CGPoint(x: 0.5, y: 0.55))
    precondition(session.observePage(elsewhere, at: 5.2) && session.framesRead == 0)

    // A phone whose text engine keeps failing falls back to steadiness alone.
    session = ScannerTextReadingSession(profile: profile("identity"))
    for _ in 0..<(ScannerTextReadingSession.readerFailureLimit - 1) { session.readFailed() }
    precondition(!session.status(glare: false).allowsCapture)
    session.ingest(frame([]))
    for _ in 0..<(ScannerTextReadingSession.readerFailureLimit - 1) { session.readFailed() }
    precondition(!session.readerUnavailable)
    session.readFailed()
    precondition(session.readerUnavailable && session.status(glare: false) == .cannotRead)
    session.reset()
    precondition(session.readerUnavailable)

    // Every guidance has words for every kind of paper.
    let all: [ScannerTextGuidance] = [.reading, .showMachineLines, .moveCloserMachineLines, .glareOnMachineLines,
      .showWholeMachineLines, .differentPaper, .turnCardToFront, .turnCardToBack, .showCardDetails, .glareOnText,
      .moveCloserText, .showPrintedText, .textRunsPastEdge]
    for guidance in all {
      for kind in [ScannerPaperKind.passport, .idCard, .paper] {
        let copy = guidance.copy(for: kind)
        precondition(!copy.title.isEmpty && !copy.detail.isEmpty && !copy.compact.isEmpty)
      }
    }
    precondition(ScannerTextGuidance.showMachineLines.copy(for: .passport).detail
      == "Show the photo page with the two lines at the bottom.")
    precondition(ScannerTextGuidance.moveCloserMachineLines.copy(for: .passport).detail
      == "Move closer — the bottom lines are too small.")
    precondition(ScannerTextGuidance.differentPaper.copy(for: .paper).title == "This looks like a different paper")
  }

  static func liveReading() {
    var session = ScannerTextReadingSession(profile: profile("identity"))
    session.ingest(passportFrame())
    session.ingest(passportFrame())
    let reading = session.liveReading(engine: "apple_vision", matched: true, referenceYear: 2026)
    precondition(reading["version"] as? Int == 1 && reading["kind"] as? String == "passport")
    precondition(reading["matched"] as? Bool == true && reading["engine"] as? String == "apple_vision")
    precondition(reading["frames"] as? Int == 2 && reading["mrzFormat"] as? String == "TD3")
    precondition(reading["mrz"] as? [String] == [passportOne, passportTwo] && reading["mrzValid"] as? Bool == true)
    let fields = reading["fields"] as? [String: String]
    precondition(fields?["surname"] == "ERIKSSON" && fields?["documentNumber"] == "L898902C3")
    precondition(fields?["birthDate"] == "1974-08-12" && fields?["expiryDate"] == "2012-04-15")
    precondition((reading["lines"] as? [String])?.first == "PASSPORT PASSEPORT")
    precondition(reading["side"] == nil)

    // Unconfirmed machine lines are returned as read, never as fields.
    session = ScannerTextReadingSession(profile: profile("identity"))
    session.ingest(passportFrame(passportOne, "L898902C36UTO7408122F1204159ZE184226B<<<<<17"))
    let unverified = session.liveReading(engine: "apple_vision", matched: false, referenceYear: 2026)
    precondition(unverified["mrzValid"] as? Bool == false && unverified["fields"] == nil)
    precondition((unverified["mrz"] as? [String])?.count == 2)

    // Nothing read yet: the shape is still there, empty.
    let empty = ScannerTextReadingSession(profile: profile("transcript")).liveReading(engine: "apple_vision",
      matched: false, referenceYear: 2026)
    precondition(empty["mrz"] == nil && (empty["lines"] as? [String])?.isEmpty == true && empty["frames"] as? Int == 0)

    // A card's side is what was read: the back's fields, or the front's number.
    session = ScannerTextReadingSession(profile: profile("parent_id"))
    session.ingest(cardBackFrame([cnieOne, cnieTwo, cnieThree]))
    session.ingest(cardBackFrame([cnieOne, cnieTwo, cnieThree]))
    let backReading = session.liveReading(engine: "apple_vision", matched: true, referenceYear: 2026)
    precondition(backReading["side"] as? String == "back" && backReading["mrzFormat"] as? String == "TD1")
    precondition((backReading["fields"] as? [String: String])?["personalNumber"] == "BE123456")
    session = ScannerTextReadingSession(profile: profile("parent_id", side: "front"))
    session.ingest(cardFrontFrame())
    session.ingest(cardFrontFrame())
    let frontReading = session.liveReading(engine: "apple_vision", matched: true, referenceYear: 2026)
    precondition(frontReading["side"] as? String == "front" && frontReading["mrz"] == nil)
    precondition(frontReading["fields"] as? [String: String] == ["documentNumber": "BE123456"])

    // A passport shown in a diploma's step is named in the reading.
    session = ScannerTextReadingSession(profile: profile("highest_degree"))
    session.ingest(passportFrame())
    session.ingest(passportFrame())
    let foreign = session.liveReading(engine: "apple_vision", matched: false, referenceYear: 2026)
    precondition(foreign["mrzFormat"] as? String == "TD3" && foreign["kind"] as? String == "paper")

    // Lines are bounded, cleaned of control characters and ordered top first.
    session = ScannerTextReadingSession(profile: profile("transcript"))
    let many = (0..<40).map { line("Line\t\($0)\n" + String(repeating: "x", count: 200), x: 0.1,
      y: 0.9 - CGFloat($0) * 0.02, width: 0.8, height: 0.015) }
    session.ingest(frame(many))
    let lines = session.liveReading(engine: "apple_vision", matched: false, referenceYear: 2026)["lines"] as! [String]
    precondition(lines.count == ScannerTextFrameAnalysis.maximumLines)
    precondition(lines.allSatisfy { $0.count <= ScannerTextFrameAnalysis.maximumLineLength && !$0.contains("\t") && !$0.contains("\n") })
    precondition(lines[0].hasPrefix("Line 0 ") && lines[1].hasPrefix("Line 1 "))
    precondition(ScannerTextFrameAnalysis.clean(" \u{0007} ") == nil)
  }
}

private extension ScannerTextFrame {
  func withTurns(_ turns: Int) -> ScannerTextFrame {
    ScannerTextFrame(lines: lines.map { ScannerTextObservation(candidates: $0.candidates, box: $0.box, quarterTurns: turns) },
      regions: regions, quarterTurns: turns, page: page, readingSize: readingSize)
  }
}
