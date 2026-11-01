#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

// MARK: - Live text reading (custom-live-v12)
//
// While the camera is open the page is read a few times a second, on the
// phone: Vision on iPhone (ScannerLiveTextReader.swift), ML Kit's bundled
// Latin model on Android (lib/src/guided_scanner/scan_text_reading.dart
// mirrors every rule here). These types are pure. What one frame read becomes
// votes, a passport's or an ID card's machine-readable lines are held to their
// ICAO 9303 check digits, and the reading decides whether the paper in view is
// the one the step asked for. Nothing here touches the camera, Vision, a file
// or the network, and nothing read is ever logged.

/// Which rules decide that the paper in view is the right one.
enum ScannerPaperKind: String {
  case passport
  case idCard = "id_card"
  case paper
}

/// The side of an ID card a step asks for. Without one, either side will do.
enum ScannerCardSide: String {
  case front
  case back
}

extension FoorsaScannerProfile {
  /// Papers that may carry a passport's or an ID card's machine-readable
  /// lines of their own: a visa, a residence permit, "other documents".
  static let papersThatMayCarryMachineLines: Set<String> = [
    "visa_documents", "drive_files", "previous_chinese_universities",
  ]

  var paperKind: ScannerPaperKind {
    switch layout {
    case .passport: return .passport
    case .card: return .idCard
    case .portrait, .adaptive: return .paper
    }
  }

  var cardSide: ScannerCardSide? { side.flatMap(ScannerCardSide.init(rawValue:)) }

  /// A passport or an ID card in a diploma's step is the wrong paper.
  var rejectsIdentityPapers: Bool {
    paperKind == .paper && !Self.papersThatMayCarryMachineLines.contains(documentKey)
  }
}

/// How one live read is set up for a kind of paper.
struct ScannerTextReadSettings: Equatable {
  let languages: [String]
  /// Relative to the height of the image read: the machine lines of a
  /// passport page are about a fortieth of it, ordinary print a hundredth.
  let minimumTextHeight: Float
  /// Script-blind text regions, so Arabic or Chinese print counts as text too.
  let detectsRegions: Bool

  static func settings(for kind: ScannerPaperKind) -> ScannerTextReadSettings {
    switch kind {
    case .passport:
      return ScannerTextReadSettings(languages: ["en-US"], minimumTextHeight: 0.012, detectsRegions: false)
    case .idCard:
      return ScannerTextReadSettings(languages: ["en-US", "fr-FR"], minimumTextHeight: 0.012, detectsRegions: true)
    case .paper:
      return ScannerTextReadSettings(languages: ["fr-FR", "en-US"], minimumTextHeight: 0.006, detectsRegions: true)
    }
  }
}

// MARK: Machine-readable zone (ICAO 9303)

enum ScannerMRZField: Equatable {
  case alpha
  case digit
  case alphanumeric
  case sex
}

enum ScannerMRZFormat: String {
  /// Two lines of 44: passports.
  case td3 = "TD3"
  /// Three lines of 30: ID cards.
  case td1 = "TD1"

  var lineLength: Int { self == .td3 ? 44 : 30 }
  var lineCount: Int { self == .td3 ? 2 : 3 }
  /// Lines covered by check digits. A read that disagrees there is another paper.
  var protectedLines: [Int] { self == .td3 ? [1] : [0, 1] }

  /// What each position holds, line by line (ICAO 9303 parts 4 and 5).
  var fields: [[ScannerMRZField]] {
    switch self {
    case .td3:
      var second = [ScannerMRZField](repeating: .alphanumeric, count: 44)
      second[9] = .digit
      for index in 10..<13 { second[index] = .alpha }
      for index in 13..<20 { second[index] = .digit }
      second[20] = .sex
      for index in 21..<28 { second[index] = .digit }
      second[42] = .digit
      second[43] = .digit
      return [[ScannerMRZField](repeating: .alpha, count: 44), second]
    case .td1:
      var first = [ScannerMRZField](repeating: .alphanumeric, count: 30)
      for index in 0..<5 { first[index] = .alpha }
      first[14] = .digit
      var second = [ScannerMRZField](repeating: .alphanumeric, count: 30)
      for index in 0..<7 { second[index] = .digit }
      second[7] = .sex
      for index in 8..<15 { second[index] = .digit }
      for index in 15..<18 { second[index] = .alpha }
      second[29] = .digit
      return [first, second, [ScannerMRZField](repeating: .alpha, count: 30)]
    }
  }
}

enum ScannerMRZ {
  static let filler = UInt8(ascii: "<")
  static let zero = UInt8(ascii: "0")
  private static let weights = [7, 3, 1]
  private static let sexes = Set("MFX<".utf8)
  private static let digitLookAlikes = Dictionary(uniqueKeysWithValues: zip("OQDILZSBG".utf8, "000112586".utf8))
  private static let letterLookAlikes = Dictionary(uniqueKeysWithValues: zip("012586".utf8, "OIZSBG".utf8))
  /// Look-alikes only a check digit can tell apart, in fields that hold letters and digits.
  static let mixedLookAlikes: [UInt8: [UInt8]] = {
    var table: [UInt8: [UInt8]] = [:]
    for (digit, letter) in zip("000112568".utf8, "ODQILZSGB".utf8) {
      table[digit, default: []].append(letter)
      table[letter, default: []].append(digit)
    }
    return table
  }()
  /// Letters an OCR engine writes for a long run of fillers.
  private static let misreadFillers = Set("KCELX".utf8)

  static func isLetter(_ c: UInt8) -> Bool { c >= 0x41 && c <= 0x5A }
  static func isDigit(_ c: UInt8) -> Bool { c >= 0x30 && c <= 0x39 }
  static func isSex(_ c: UInt8) -> Bool { sexes.contains(c) }
  static func isLetterOrFiller(_ c: UInt8) -> Bool { isLetter(c) || c == filler }
  static func digitLookAlike(_ c: UInt8) -> UInt8 { digitLookAlikes[c] ?? c }

  /// ICAO 9303 value of a character: digits, A–Z as 10–35, the filler 0.
  static func value(_ c: UInt8) -> Int? {
    if isDigit(c) { return Int(c) - 0x30 }
    if isLetter(c) { return Int(c) - 0x41 + 10 }
    return c == filler ? 0 : nil
  }

  /// Weights 7, 3, 1 repeating; the sum modulo 10.
  static func checkDigit<S: Sequence>(_ field: S) -> Int? where S.Element == UInt8 {
    var sum = 0
    for (index, c) in field.enumerated() {
      guard let value = value(c) else { return nil }
      sum += value * weights[index % 3]
    }
    return sum % 10
  }

  static func passes<S: Sequence>(_ field: S, check: UInt8) -> Bool where S.Element == UInt8 {
    guard isDigit(check), let digit = checkDigit(field) else { return false }
    return digit == Int(check) - 0x30
  }

  /// YYMMDD with a real month and day.
  static func isDate<C: Collection>(_ field: C) -> Bool where C.Element == UInt8 {
    let d = Array(field)
    guard d.count == 6, d.allSatisfy(isDigit) else { return false }
    let month = (Int(d[2]) - 0x30) * 10 + Int(d[3]) - 0x30
    let day = (Int(d[4]) - 0x30) * 10 + Int(d[5]) - 0x30
    return (1...12).contains(month) && (1...31).contains(day)
  }

  static func datePasses(_ line: [UInt8], date: Range<Int>, check: Int) -> Bool {
    isDate(line[date]) && passes(line[date], check: line[check])
  }

  /// One read line in the MRZ alphabet: upper-cased, spaces gone, look-alike
  /// chevrons turned into fillers. Anything else is counted as dropped.
  static func normalize(_ text: String) -> (characters: [UInt8], dropped: Int) {
    var characters: [UInt8] = []
    var dropped = 0
    for scalar in text.uppercased().unicodeScalars {
      let value = scalar.value
      if (0x41...0x5A).contains(value) || (0x30...0x39).contains(value) || value == 0x3C {
        characters.append(UInt8(value))
      } else if value == 0x20 || value == 0x09 {
        continue
      } else if value == 0xAB || value == 0x226A {
        // « and ≪: a pair of fillers read as one glyph.
        characters.append(filler)
        characters.append(filler)
      } else if [0x2039, 0x2264, 0x2329, 0x3008, 0xFF1C].contains(value) {
        characters.append(filler)
      } else {
        dropped += 1
      }
    }
    return (characters, dropped)
  }

  /// Puts each position in its own alphabet: an O in a date is a zero, a
  /// zero in a name an O. Fields holding both are left to their check digit.
  static func conform(_ line: [UInt8], to fields: [ScannerMRZField]) -> [UInt8] {
    var out = line
    for index in out.indices where index < fields.count {
      switch fields[index] {
      case .digit: out[index] = digitLookAlikes[out[index]] ?? out[index]
      case .alpha: out[index] = letterLookAlikes[out[index]] ?? out[index]
      case .alphanumeric, .sex: break
      }
    }
    return clearMisreadFillerRuns(out, fields: fields)
  }

  /// No name or number repeats a letter three times: such a run is a filler
  /// run the OCR engine misread.
  static func clearMisreadFillerRuns(_ line: [UInt8], fields: [ScannerMRZField]) -> [UInt8] {
    var out = line
    var start = 0
    while start < out.count {
      var end = start + 1
      while end < out.count, out[end] == out[start] { end += 1 }
      if end - start >= 3, misreadFillers.contains(out[start]),
         (start..<end).allSatisfy({ $0 < fields.count && (fields[$0] == .alpha || fields[$0] == .alphanumeric) }) {
        for index in start..<end { out[index] = filler }
      }
      start = end
    }
    return out
  }

  /// The ways a read line may have gained or lost characters. OCR most often
  /// adds or drops one inside a filler run; lines further off are not lines
  /// of this format.
  static func lengthVariants(_ line: [UInt8], length: Int) -> [[UInt8]] {
    let delta = line.count - length
    if delta == 0 { return [line] }
    guard abs(delta) <= 2, length > 0 else { return [] }
    var variants: [[UInt8]] = []
    var seen = Set<[UInt8]>()
    func keep(_ variant: [UInt8]) {
      if variant.count == length, seen.insert(variant).inserted { variants.append(variant) }
    }
    let gaps = (0...line.count).filter { index in
      index == line.count || line[index] == filler || (index > 0 && line[index - 1] == filler)
    }
    switch delta {
    case 1:
      for index in line.indices {
        var variant = line
        variant.remove(at: index)
        keep(variant)
      }
    case 2:
      let fillers = line.indices.filter { line[$0] == filler }
      for (n, first) in fillers.enumerated() {
        for second in fillers[(n + 1)...] {
          var variant = line
          variant.remove(at: second)
          variant.remove(at: first)
          keep(variant)
        }
      }
    case -1:
      for index in gaps {
        var variant = line
        variant.insert(filler, at: index)
        keep(variant)
      }
    case -2:
      for (n, first) in gaps.enumerated() {
        for second in gaps[n...] {
          var variant = line
          variant.insert(filler, at: second)
          variant.insert(filler, at: first)
          keep(variant)
        }
      }
    default:
      break
    }
    return variants
  }

  /// A names line can only gain or lose fillers at its end, where no check
  /// digit can tell.
  static func padded(_ line: [UInt8], length: Int) -> [UInt8]? {
    guard abs(line.count - length) <= 3 else { return nil }
    var out = line
    while out.count > length, out.last == filler { out.removeLast() }
    while out.count < length { out.append(filler) }
    return out.count == length ? out : nil
  }

  static func td3Composite(_ line: [UInt8]) -> [UInt8] {
    Array(line[0..<10]) + Array(line[13..<20]) + Array(line[21..<43])
  }

  static func td1Composite(_ first: [UInt8], _ second: [UInt8]) -> [UInt8] {
    Array(first[5..<30]) + Array(second[0..<7]) + Array(second[8..<15]) + Array(second[18..<29])
  }

  /// Passport line two: how many of its four check digits pass.
  static func td3LineTwoScore(_ line: [UInt8]) -> Int {
    guard line.count == 44 else { return 0 }
    var score = 0
    if passes(line[0..<9], check: line[9]) { score += 1 }
    if datePasses(line, date: 13..<19, check: 19) { score += 1 }
    if datePasses(line, date: 21..<27, check: 27) { score += 1 }
    if passes(td3Composite(line), check: line[43]) { score += 1 }
    return score
  }

  /// ID card line two: dates and their check digits where they belong.
  static func td1LineTwoShape(_ line: [UInt8]) -> Bool {
    line.count == 30 && line[0..<7].allSatisfy(isDigit) && line[8..<15].allSatisfy(isDigit)
      && isSex(line[7]) && line[15..<18].allSatisfy(isLetterOrFiller) && isDigit(line[29])
  }

  static func td1LineTwoScore(_ line: [UInt8]) -> Int {
    guard line.count == 30 else { return 0 }
    return (datePasses(line, date: 0..<6, check: 6) ? 1 : 0) + (datePasses(line, date: 8..<14, check: 14) ? 1 : 0)
  }

  /// ICAO 9303-5 4.2.4: a document number longer than nine characters goes
  /// on in the optional data, with its check digit after it.
  static func extendedDocumentNumber(_ first: [UInt8]) -> (number: [UInt8], check: UInt8)? {
    guard first.count == 30, first[14] == filler else { return nil }
    var end = 15
    while end < 30, first[end] != filler { end += 1 }
    guard end - 15 >= 2 else { return nil }
    return (Array(first[5..<14]) + Array(first[15..<(end - 1)]), first[end - 1])
  }

  /// The field's look-alike variants its check digit accepts, fewest changes
  /// first: the line as read when it passes, else every single substitution
  /// that passes, else every double. Empty when nothing passes.
  static func acceptedVariants(_ line: [UInt8], field: Range<Int>, check: Int) -> [[UInt8]] {
    if passes(line[field], check: line[check]) { return [line] }
    let positions = field.filter { mixedLookAlikes[line[$0]] != nil }
    var singles: [[UInt8]] = []
    for position in positions {
      for alternative in mixedLookAlikes[line[position]] ?? [] {
        var variant = line
        variant[position] = alternative
        if passes(variant[field], check: variant[check]) { singles.append(variant) }
      }
    }
    if !singles.isEmpty { return singles }
    var doubles: [[UInt8]] = []
    for (n, first) in positions.enumerated() {
      for second in positions[(n + 1)...] {
        for a in mixedLookAlikes[line[first]] ?? [] {
          for b in mixedLookAlikes[line[second]] ?? [] {
            var variant = line
            variant[first] = a
            variant[second] = b
            if passes(variant[field], check: variant[check]) { doubles.append(variant) }
          }
        }
      }
    }
    return doubles
  }
}

/// A complete reading, after look-alike repairs. `valid`: every check digit
/// passed, the dates are real dates and the lines have their format's shape.
struct ScannerMRZResult: Equatable {
  let format: ScannerMRZFormat
  let lines: [[UInt8]]
  let valid: Bool

  var text: [String] { lines.map { String(decoding: $0, as: UTF8.self) } }
}

enum ScannerMRZValidator {
  /// `tallies` are the votes behind `lines` (ScannerMRZVotes.counts): when two
  /// look-alike repairs satisfy a check digit equally, a character that other
  /// reads actually saw decides. Without them such a tie stays invalid.
  static func validate(_ lines: [[UInt8]], format: ScannerMRZFormat,
                       tallies: [[[Int]]]? = nil) -> ScannerMRZResult {
    guard lines.count == format.lineCount, lines.allSatisfy({ $0.count == format.lineLength }) else {
      return ScannerMRZResult(format: format, lines: lines, valid: false)
    }
    switch format {
    case .td3: return validateTD3(lines, tally: tallies.flatMap { $0.count > 1 ? $0[1] : nil })
    case .td1: return validateTD1(lines, tally: tallies?.first)
    }
  }

  /// The repaired line with the fewest changes; among those, the one whose
  /// changes the reads saw most. Nil when there is none, or a tie remains:
  /// the field's check digit and the composite weigh a field's characters
  /// alike, so they cannot choose between two look-alikes.
  private static func unique(_ candidates: [[UInt8]], from original: [UInt8], tally: [[Int]]?) -> [UInt8]? {
    var best: [UInt8]?
    var bestCost = Int.max
    var bestSupport = -1
    var tied = false
    for candidate in candidates {
      var cost = 0
      var support = 0
      for index in candidate.indices where index < original.count && candidate[index] != original[index] {
        cost += 1
        if let tally, index < tally.count, let symbol = ScannerMRZVotes.symbol(candidate[index]) {
          support += tally[index][symbol]
        }
      }
      if cost < bestCost || (cost == bestCost && support > bestSupport) {
        best = candidate
        bestCost = cost
        bestSupport = support
        tied = false
      } else if cost == bestCost, support == bestSupport, candidate != best {
        tied = true
      }
    }
    return tied ? nil : best
  }

  private static func validateTD3(_ lines: [[UInt8]], tally: [[Int]]?) -> ScannerMRZResult {
    let first = lines[0], second = lines[1]
    let shaped = first[0] == UInt8(ascii: "P") && ScannerMRZ.isLetter(first[5])
      && first[2..<5].allSatisfy(ScannerMRZ.isLetterOrFiller)
      && second[10..<13].allSatisfy(ScannerMRZ.isLetterOrFiller)
      && ScannerMRZ.isSex(second[20])
      && ScannerMRZ.datePasses(second, date: 13..<19, check: 19)
      && ScannerMRZ.datePasses(second, date: 21..<27, check: 27)
    guard shaped else { return ScannerMRZResult(format: .td3, lines: lines, valid: false) }
    var candidates: [[UInt8]] = []
    for document in ScannerMRZ.acceptedVariants(second, field: 0..<9, check: 9) {
      let personalEmpty = document[28..<42].allSatisfy { $0 == ScannerMRZ.filler }
      let personals: [[UInt8]]
      if personalEmpty {
        // An unused personal number may carry a filler or a zero as its check.
        personals = document[42] == ScannerMRZ.filler || document[42] == ScannerMRZ.zero ? [document] : []
      } else {
        personals = ScannerMRZ.acceptedVariants(document, field: 28..<42, check: 42)
      }
      candidates += personals.filter { ScannerMRZ.passes(ScannerMRZ.td3Composite($0), check: $0[43]) }
    }
    guard let repaired = unique(candidates, from: second, tally: tally) else {
      return ScannerMRZResult(format: .td3, lines: lines, valid: false)
    }
    return ScannerMRZResult(format: .td3, lines: [first, repaired], valid: true)
  }

  private static func validateTD1(_ lines: [[UInt8]], tally: [[Int]]?) -> ScannerMRZResult {
    let first = lines[0], second = lines[1], third = lines[2]
    let shaped = Set("IAC".utf8).contains(first[0]) && ScannerMRZ.isLetter(third[0])
      && first[2..<5].allSatisfy(ScannerMRZ.isLetterOrFiller)
      && second[15..<18].allSatisfy(ScannerMRZ.isLetterOrFiller)
      && ScannerMRZ.isSex(second[7])
      && ScannerMRZ.datePasses(second, date: 0..<6, check: 6)
      && ScannerMRZ.datePasses(second, date: 8..<14, check: 14)
    guard shaped else { return ScannerMRZResult(format: .td1, lines: lines, valid: false) }
    let documents: [[UInt8]]
    if let extended = ScannerMRZ.extendedDocumentNumber(first) {
      documents = ScannerMRZ.passes(extended.number, check: extended.check) ? [first] : []
    } else {
      documents = ScannerMRZ.acceptedVariants(first, field: 5..<14, check: 14)
    }
    let candidates = documents.filter { ScannerMRZ.passes(ScannerMRZ.td1Composite($0, second), check: second[29]) }
    guard let repaired = unique(candidates, from: first, tally: tally) else {
      return ScannerMRZResult(format: .td1, lines: lines, valid: false)
    }
    return ScannerMRZResult(format: .td1, lines: [repaired, second, third], valid: true)
  }
}

/// What a valid machine-readable zone says, for the portal's review.
struct ScannerMRZFields: Equatable {
  let issuingState: String
  let surname: String
  let givenNames: String
  let documentNumber: String
  let nationality: String
  /// YYMMDD as printed.
  let birthDate: String
  let sex: String
  /// YYMMDD as printed.
  let expiryDate: String
  let personalNumber: String

  init?(_ result: ScannerMRZResult) {
    guard result.valid else { return nil }
    switch result.format {
    case .td3:
      let first = result.lines[0], second = result.lines[1]
      let names = Self.names(first[5..<44])
      issuingState = Self.text(first[2..<5])
      surname = names.surname
      givenNames = names.givenNames
      documentNumber = Self.text(second[0..<9])
      nationality = Self.text(second[10..<13])
      birthDate = Self.text(second[13..<19])
      sex = Self.text(second[20..<21])
      expiryDate = Self.text(second[21..<27])
      personalNumber = Self.text(second[28..<42])
    case .td1:
      let first = result.lines[0], second = result.lines[1], third = result.lines[2]
      let names = Self.names(third[0..<30])
      issuingState = Self.text(first[2..<5])
      surname = names.surname
      givenNames = names.givenNames
      nationality = Self.text(second[15..<18])
      birthDate = Self.text(second[0..<6])
      sex = Self.text(second[7..<8])
      expiryDate = Self.text(second[8..<14])
      if let extended = ScannerMRZ.extendedDocumentNumber(first) {
        documentNumber = Self.text(extended.number[...])
        personalNumber = Self.text(second[18..<29])
      } else {
        documentNumber = Self.text(first[5..<14])
        let optional = Self.text(first[15..<30])
        personalNumber = optional.isEmpty ? Self.text(second[18..<29]) : optional
      }
    }
  }

  /// A field without its fillers; fillers inside it read as spaces.
  static func text(_ field: ArraySlice<UInt8>) -> String {
    String(decoding: field, as: UTF8.self)
      .split(separator: "<").joined(separator: " ")
  }

  /// SURNAME<<GIVEN<NAMES: a double filler ends the surname.
  static func names(_ field: ArraySlice<UInt8>) -> (surname: String, givenNames: String) {
    let parts = String(decoding: field, as: UTF8.self).components(separatedBy: "<<")
    let surname = (parts.first ?? "").split(separator: "<").joined(separator: " ")
    let given = parts.dropFirst().joined(separator: "<").split(separator: "<").joined(separator: " ")
    return (surname, given)
  }

  /// YYYY-MM-DD. A birth year past `referenceYear` is last century; expiry
  /// years from 70 are too.
  static func isoDate(_ yymmdd: String, birth: Bool, referenceYear: Int) -> String? {
    let digits = Array(yymmdd.utf8)
    guard digits.count == 6, digits.allSatisfy(ScannerMRZ.isDigit) else { return nil }
    func number(_ range: Range<Int>) -> Int { range.reduce(0) { $0 * 10 + Int(digits[$1]) - 0x30 } }
    let year = number(0..<2), month = number(2..<4), day = number(4..<6)
    let century: Int
    if birth {
      century = 2000 + year > referenceYear ? 1900 : 2000
    } else {
      century = year >= 70 ? 1900 : 2000
    }
    return String(format: "%04d-%02d-%02d", century + year, month, day)
  }

  func dictionary(referenceYear: Int) -> [String: String] {
    var fields: [String: String] = [:]
    func put(_ key: String, _ value: String?) {
      if let value, !value.isEmpty { fields[key] = value }
    }
    put("surname", surname)
    put("givenNames", givenNames)
    put("documentNumber", documentNumber)
    put("nationality", nationality)
    put("issuingState", issuingState)
    put("birthDate", Self.isoDate(birthDate, birth: true, referenceYear: referenceYear))
    put("sex", sex)
    put("expiryDate", Self.isoDate(expiryDate, birth: false, referenceYear: referenceYear))
    put("personalNumber", personalNumber)
    return fields
  }
}

/// Character votes across frames, position by position, so one bad frame
/// cannot block a reading and one lucky frame cannot make it.
struct ScannerMRZVotes {
  static let symbols = 37
  static let maximumReads = 8

  let format: ScannerMRZFormat
  private(set) var counts: [[[Int]]]
  private(set) var reads: [[[UInt8]?]] = []

  init(format: ScannerMRZFormat) {
    self.format = format
    counts = Array(repeating: Array(repeating: Array(repeating: 0, count: Self.symbols),
      count: format.lineLength), count: format.lineCount)
  }

  static func symbol(_ c: UInt8) -> Int? {
    if ScannerMRZ.isLetter(c) { return Int(c) - 0x41 }
    if ScannerMRZ.isDigit(c) { return Int(c) - 0x30 + 26 }
    return c == ScannerMRZ.filler ? 36 : nil
  }

  static func character(_ symbol: Int) -> UInt8 {
    if symbol < 26 { return UInt8(0x41 + symbol) }
    if symbol < 36 { return UInt8(0x30 + symbol - 26) }
    return ScannerMRZ.filler
  }

  mutating func add(_ lines: [[UInt8]?]) {
    guard lines.count == format.lineCount else { return }
    var added = false
    for (index, line) in lines.enumerated() {
      guard let line, line.count == format.lineLength else { continue }
      for (position, c) in line.enumerated() {
        if let symbol = Self.symbol(c) { counts[index][position][symbol] += 1 }
      }
      added = true
    }
    guard added else { return }
    reads.append(lines)
    if reads.count > Self.maximumReads { reads.removeFirst() }
  }

  /// The most voted character at each position; the earlier symbol wins a tie.
  var consensus: [[UInt8]?] {
    counts.map { positions -> [UInt8]? in
      guard positions.contains(where: { tally in tally.contains { $0 > 0 } }) else { return nil }
      return positions.map { tally in
        var best = 0
        for symbol in 1..<Self.symbols where tally[symbol] > tally[best] { best = symbol }
        return Self.character(best)
      }
    }
  }

  /// Share of check-covered positions where `lines` differ from the consensus.
  func disagreement(with lines: [[UInt8]?]) -> Double? {
    let consensus = self.consensus
    var compared = 0, differing = 0
    for index in format.protectedLines where index < lines.count {
      guard let mine = lines[index], let theirs = consensus[index] else { continue }
      for (a, b) in zip(mine, theirs) {
        compared += 1
        if a != b { differing += 1 }
      }
    }
    return compared == 0 ? nil : Double(differing) / Double(compared)
  }

  /// Recent reads that agree with `lines` on every check-covered line they
  /// read, within two characters a line.
  func supportingReads(for lines: [[UInt8]]) -> Int {
    reads.filter { read in
      var compared = false
      for index in format.protectedLines where index < read.count && index < lines.count {
        guard let mine = read[index] else { continue }
        compared = true
        if zip(mine, lines[index]).filter({ $0 != $1 }).count > 2 { return false }
      }
      return compared
    }.count
  }
}

// MARK: What one frame read

/// One piece of text a frame read: its readings, best first, and where it is.
struct ScannerTextObservation: Equatable {
  let candidates: [String]
  /// Normalized in the image that was read, origin bottom-left (Vision's convention).
  let box: CGRect
  /// The same box in the unturned page crop, normalized, origin bottom-left.
  let pageBox: CGRect

  init(candidates: [String], box: CGRect, pageBox: CGRect) {
    self.candidates = Array(candidates.prefix(3))
    self.box = box
    self.pageBox = pageBox
  }

  init(candidates: [String], box: CGRect, quarterTurns: Int) {
    self.init(candidates: candidates, box: box, pageBox: ScannerQuarterTurn.undo(quarterTurns, box))
  }
}

/// Everything one live read saw, before any judgement.
struct ScannerTextFrame {
  static let maximumLines = 120
  static let maximumRegions = 200

  let lines: [ScannerTextObservation]
  /// Text found without being read (any script).
  let regions: [ScannerTextObservation]
  /// The page crop was turned counterclockwise this many quarter turns before it was read.
  let quarterTurns: Int
  /// The page's corners in the crop, normalized, origin bottom-left.
  let page: [CGPoint]
  /// Pixel size of the image that was read.
  let readingSize: CGSize

  init(lines: [ScannerTextObservation], regions: [ScannerTextObservation], quarterTurns: Int,
       page: [CGPoint], readingSize: CGSize) {
    self.lines = Array(lines.prefix(Self.maximumLines))
    self.regions = Array(regions.prefix(Self.maximumRegions))
    self.quarterTurns = ScannerQuarterTurn.normalized(quarterTurns)
    self.page = page
    self.readingSize = readingSize
  }
}

/// Quarter turns of a normalized image, origin bottom-left, counterclockwise.
enum ScannerQuarterTurn {
  static func normalized(_ turns: Int) -> Int { ((turns % 4) + 4) % 4 }

  /// A point of the unturned image, in the turned image.
  static func apply(_ turns: Int, _ point: CGPoint) -> CGPoint {
    switch normalized(turns) {
    case 1: return CGPoint(x: 1 - point.y, y: point.x)
    case 2: return CGPoint(x: 1 - point.x, y: 1 - point.y)
    case 3: return CGPoint(x: point.y, y: 1 - point.x)
    default: return point
    }
  }

  /// A point of the turned image, back in the unturned one.
  static func undo(_ turns: Int, _ point: CGPoint) -> CGPoint {
    apply(4 - normalized(turns), point)
  }

  static func undo(_ turns: Int, _ rect: CGRect) -> CGRect {
    let a = undo(turns, CGPoint(x: rect.minX, y: rect.minY))
    let b = undo(turns, CGPoint(x: rect.maxX, y: rect.maxY))
    return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
  }
}

/// Which way the next read holds the page.
enum ScannerTextTurnPolicy: Equatable {
  /// Passports and cards are read long side across, upright or upside down.
  case landscape(upsideDown: Bool)
  /// Other papers are read as seen, or turned this many quarter turns.
  case fixed(Int)

  func quarterTurns(width: CGFloat, height: CGFloat) -> Int {
    switch self {
    case let .landscape(upsideDown):
      return (width >= height ? 0 : 1) + (upsideDown ? 2 : 0)
    case let .fixed(turns):
      return ScannerQuarterTurn.normalized(turns)
    }
  }
}

/// A projective map from the unit square, the shape Core Image's perspective
/// correction gives a page.
struct ScannerHomography {
  private let m: [Double]

  private init(matrix: [Double]) { m = matrix }

  /// (0,0), (1,0), (1,1), (0,1) to the four corners, in order.
  init?(unitSquareTo corners: [CGPoint]) {
    guard corners.count == 4 else { return nil }
    let x0 = Double(corners[0].x), y0 = Double(corners[0].y)
    let x1 = Double(corners[1].x), y1 = Double(corners[1].y)
    let x2 = Double(corners[2].x), y2 = Double(corners[2].y)
    let x3 = Double(corners[3].x), y3 = Double(corners[3].y)
    let sx = x0 - x1 + x2 - x3, sy = y0 - y1 + y2 - y3
    let a, b, c, d, e, f, g, h: Double
    if abs(sx) < 1e-12 && abs(sy) < 1e-12 {
      a = x1 - x0; b = x2 - x1; c = x0
      d = y1 - y0; e = y2 - y1; f = y0
      g = 0; h = 0
    } else {
      let dx1 = x1 - x2, dx2 = x3 - x2, dy1 = y1 - y2, dy2 = y3 - y2
      let determinant = dx1 * dy2 - dx2 * dy1
      guard abs(determinant) > 1e-12 else { return nil }
      g = (sx * dy2 - dx2 * sy) / determinant
      h = (dx1 * sy - sx * dy1) / determinant
      a = x1 - x0 + g * x1; b = x3 - x0 + h * x3; c = x0
      d = y1 - y0 + g * y1; e = y3 - y0 + h * y3; f = y0
    }
    m = [a, b, c, d, e, f, g, h, 1]
  }

  func inverted() -> ScannerHomography? {
    let a = m[0], b = m[1], c = m[2], d = m[3], e = m[4], f = m[5], g = m[6], h = m[7], i = m[8]
    let c11 = e * i - f * h, c12 = -(d * i - f * g), c13 = d * h - e * g
    let determinant = a * c11 + b * c12 + c * c13
    guard abs(determinant) > 1e-12 else { return nil }
    let adjugate = [c11, -(b * i - c * h), b * f - c * e,
                    c12, a * i - c * g, -(a * f - c * d),
                    c13, -(a * h - b * g), a * e - b * d]
    return ScannerHomography(matrix: adjugate.map { $0 / determinant })
  }

  func map(_ point: CGPoint) -> CGPoint? {
    let x = Double(point.x), y = Double(point.y)
    let w = m[6] * x + m[7] * y + m[8]
    guard abs(w) > 1e-12 else { return nil }
    let mapped = CGPoint(x: (m[0] * x + m[1] * y + m[2]) / w, y: (m[3] * x + m[4] * y + m[5]) / w)
    return mapped.x.isFinite && mapped.y.isFinite ? mapped : nil
  }
}

enum ScannerTextGeometry {
  /// The page is read with a margin, so text that runs past its edge shows.
  static let cropExpansion: CGFloat = 0.10

  /// The page's corners (top left, top right, bottom right, bottom left) in
  /// the perspective-corrected crop of `crop`, normalized, origin bottom-left.
  static func pageInCrop(page: ScannerQuadrilateral, crop: ScannerQuadrilateral) -> [CGPoint]? {
    guard let toCrop = ScannerHomography(unitSquareTo: [crop.bottomLeft, crop.bottomRight,
      crop.topRight, crop.topLeft])?.inverted() else { return nil }
    let corners = page.points.compactMap { toCrop.map($0) }
    return corners.count == 4 ? corners : nil
  }

  static func bounds(_ points: [CGPoint]) -> CGRect? {
    guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
          let minY = points.map(\.y).min(), let maxY = points.map(\.y).max(),
          maxX > minX, maxY > minY else { return nil }
    return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
  }

  static func union(_ a: CGRect, _ b: CGRect) -> CGRect {
    let minX = min(a.minX, b.minX), minY = min(a.minY, b.minY)
    return CGRect(x: minX, y: minY, width: max(a.maxX, b.maxX) - minX, height: max(a.maxY, b.maxY) - minY)
  }

  /// Share of `box` that lies inside `area`.
  static func overlapShare(of box: CGRect, in area: CGRect) -> CGFloat {
    let width = max(0, min(box.maxX, area.maxX) - max(box.minX, area.minX))
    let height = max(0, min(box.maxY, area.maxY) - max(box.minY, area.minY))
    let own = box.width * box.height
    return own > 0 ? width * height / own : 0
  }

  /// How far `box` reaches past `area`, as a share of the area's size.
  static func overhang(of box: CGRect, beyond area: CGRect) -> CGFloat {
    guard area.width > 0, area.height > 0 else { return 0 }
    let horizontal = max(0, area.minX - box.minX, box.maxX - area.maxX) / area.width
    let vertical = max(0, area.minY - box.minY, box.maxY - area.maxY) / area.height
    return max(horizontal, vertical)
  }

  /// Reading order: higher first, then from the left (origin bottom-left).
  static func topFirst(_ a: CGRect, _ b: CGRect) -> Bool {
    a.midY != b.midY ? a.midY > b.midY : a.minX < b.minX
  }

  /// Text that reaches the crop's border goes on beyond what was read.
  static func touchesBorder(_ box: CGRect, margin: CGFloat = 0.006) -> Bool {
    box.minX <= margin || box.minY <= margin || box.maxX >= 1 - margin || box.maxY >= 1 - margin
  }
}

/// A row of text that looks like machine-readable characters.
struct ScannerMachineRow {
  /// Readings in the MRZ alphabet, best first.
  let texts: [[UInt8]]
  let box: CGRect
  let pageBox: CGRect
}

enum ScannerMRZReader {
  /// Rows of machine-like text, top first. Pieces of one row are joined:
  /// an OCR engine can split a line at a long filler run.
  static func machineRows(_ lines: [ScannerTextObservation]) -> [ScannerMachineRow] {
    let sorted = lines.filter { !$0.candidates.isEmpty && $0.box.width > 0 && $0.box.height > 0 }
      .sorted { ScannerTextGeometry.topFirst($0.box, $1.box) }
    var groups: [[ScannerTextObservation]] = []
    for line in sorted {
      if let group = groups.last, belongsToRow(line, group) {
        groups[groups.count - 1].append(line)
      } else {
        groups.append([line])
      }
    }
    var rows: [ScannerMachineRow] = []
    for group in groups {
      let members = group.sorted { $0.box.minX < $1.box.minX }
      var texts: [[UInt8]]
      var dropped: Int
      if members.count == 1 {
        let readings = members[0].candidates.map { ScannerMRZ.normalize($0) }
        texts = readings.map { $0.characters }
        dropped = readings.first?.dropped ?? 0
      } else {
        let readings = members.map { ScannerMRZ.normalize($0.candidates[0]) }
        texts = [readings.flatMap { $0.characters }]
        dropped = readings.reduce(0) { $0 + $1.dropped }
      }
      guard let best = texts.first, best.count >= 24, dropped <= max(2, best.count / 8) else { continue }
      let fillers = best.filter { $0 == ScannerMRZ.filler }.count
      let digits = best.filter { ScannerMRZ.isDigit($0) }.count
      guard fillers >= 2 || digits * 3 >= best.count else { continue }
      let box = members.dropFirst().reduce(members[0].box) { ScannerTextGeometry.union($0, $1.box) }
      let pageBox = members.dropFirst().reduce(members[0].pageBox) { ScannerTextGeometry.union($0, $1.pageBox) }
      rows.append(ScannerMachineRow(texts: texts, box: box, pageBox: pageBox))
    }
    return rows
  }

  private static func belongsToRow(_ line: ScannerTextObservation, _ group: [ScannerTextObservation]) -> Bool {
    let height = group.map(\.box.height).max() ?? 0
    let middle = group.map(\.box.midY).reduce(0, +) / CGFloat(group.count)
    guard abs(line.box.midY - middle) <= max(height, line.box.height) * 0.6 else { return false }
    return group.allSatisfy { member in
      let overlap = min(member.box.maxX, line.box.maxX) - max(member.box.minX, line.box.minX)
      return overlap <= min(member.box.width, line.box.width) * 0.3
    }
  }

  static func adjacent(_ upper: ScannerMachineRow, _ lower: ScannerMachineRow) -> Bool {
    let height = max(upper.box.height, lower.box.height)
    let gap = upper.box.minY - lower.box.maxY
    let overlap = min(upper.box.maxX, lower.box.maxX) - max(upper.box.minX, lower.box.minX)
    return gap >= -height * 0.5 && gap <= height * 2.5
      && overlap >= min(upper.box.width, lower.box.width) * 0.5
  }

  /// A passport's lines in one frame: line two must pass two of its four
  /// check digits as read, or three after a length repair; line one, when
  /// the row above is read, must begin with P.
  static func td3(in rows: [ScannerMachineRow]) -> [[UInt8]?]? {
    let fields = ScannerMRZFormat.td3.fields
    var best: (index: Int, line: [UInt8], score: Int)?
    for (index, row) in rows.enumerated() {
      for text in row.texts {
        for variant in ScannerMRZ.lengthVariants(text, length: 44) {
          let line = ScannerMRZ.conform(variant, to: fields[1])
          let score = ScannerMRZ.td3LineTwoScore(line)
          guard score >= (text.count == 44 ? 2 : 3) else { continue }
          if best.map({ score > $0.score }) ?? true { best = (index, line, score) }
        }
      }
    }
    guard let found = best else { return nil }
    var first: [UInt8]?
    if found.index > 0, adjacent(rows[found.index - 1], rows[found.index]) {
      for text in rows[found.index - 1].texts {
        guard let padded = ScannerMRZ.padded(text, length: 44) else { continue }
        let line = ScannerMRZ.conform(padded, to: fields[0])
        if line[0] == UInt8(ascii: "P"), ScannerMRZ.isLetter(line[5]) {
          first = line
          break
        }
      }
    }
    return [first, found.line]
  }

  /// An ID card's lines in one frame, found from line two (its dates).
  static func td1(in rows: [ScannerMachineRow]) -> [[UInt8]?]? {
    let fields = ScannerMRZFormat.td1.fields
    var best: (index: Int, line: [UInt8], score: Int)?
    for (index, row) in rows.enumerated() {
      for text in row.texts {
        for variant in ScannerMRZ.lengthVariants(text, length: 30) {
          let line = ScannerMRZ.conform(variant, to: fields[1])
          guard ScannerMRZ.td1LineTwoShape(line) else { continue }
          let score = ScannerMRZ.td1LineTwoScore(line)
          guard score >= (text.count == 30 ? 1 : 2) else { continue }
          if best.map({ score > $0.score }) ?? true { best = (index, line, score) }
        }
      }
    }
    guard let found = best else { return nil }
    var first: [UInt8]?
    var third: [UInt8]?
    if found.index > 0, adjacent(rows[found.index - 1], rows[found.index]) {
      first = td1LineOne(rows[found.index - 1].texts, fields: fields[0])
    }
    if found.index + 1 < rows.count, adjacent(rows[found.index], rows[found.index + 1]) {
      for text in rows[found.index + 1].texts {
        guard let padded = ScannerMRZ.padded(text, length: 30) else { continue }
        let line = ScannerMRZ.conform(padded, to: fields[2])
        if ScannerMRZ.isLetter(line[0]) {
          third = line
          break
        }
      }
    }
    return [first, found.line, third]
  }

  private static func td1LineOne(_ texts: [[UInt8]], fields: [ScannerMRZField]) -> [UInt8]? {
    for text in texts {
      for variant in ScannerMRZ.lengthVariants(text, length: 30) {
        let line = ScannerMRZ.conform(variant, to: fields)
        guard Set("IAC".utf8).contains(line[0]) else { continue }
        if text.count == 30 { return line }
        let numberPasses = ScannerMRZ.extendedDocumentNumber(line).map { ScannerMRZ.passes($0.number, check: $0.check) }
          ?? ScannerMRZ.passes(line[5..<14], check: line[14])
        if numberPasses { return line }
      }
    }
    return nil
  }
}

/// The front of an ID card: its number and the words printed on it.
enum ScannerCardFront {
  static let keywords = ["ROYAUME", "MAROC", "MOROCCO", "NATIONALE", "IDENTIT", "TUNISIE", "PUBLIQUE"]

  static func hasKeyword(_ texts: [String]) -> Bool {
    texts.contains { text in
      let upper = text.uppercased()
      return keywords.contains { upper.contains($0) }
    }
  }

  /// Card numbers on the front: a Moroccan CIN (one or two letters, then
  /// five to seven digits) or eight digits (a Tunisian card).
  static func numbers(in texts: [String]) -> [String] {
    var found: [String] = []
    for text in texts {
      let tokens = text.uppercased()
        .split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }
        .map { Array(String($0).utf8) }
      var candidates = tokens
      for index in tokens.indices.dropLast() {
        let letters = tokens[index], digits = tokens[index + 1]
        if (1...2).contains(letters.count), letters.allSatisfy(ScannerMRZ.isLetter),
           (5...7).contains(digits.count), digits.allSatisfy(ScannerMRZ.isDigit) {
          candidates.append(letters + digits)
        }
      }
      for candidate in candidates {
        if let number = cardNumber(candidate), !found.contains(number) { found.append(number) }
      }
    }
    return found
  }

  static func cardNumber(_ token: [UInt8]) -> String? {
    guard (6...9).contains(token.count) else { return nil }
    if token.allSatisfy(ScannerMRZ.isDigit) {
      return token.count == 8 ? String(decoding: token, as: UTF8.self) : nil
    }
    var prefix = 0
    while prefix < 2, ScannerMRZ.isLetter(token[prefix]) { prefix += 1 }
    guard prefix >= 1 else { return nil }
    let rest = token[prefix...].map { ScannerMRZ.digitLookAlike($0) }
    guard (5...7).contains(rest.count), rest.allSatisfy(ScannerMRZ.isDigit) else { return nil }
    return String(decoding: Array(token[..<prefix]) + rest, as: UTF8.self)
  }
}

struct ScannerTextLayoutSummary: Equatable {
  /// Rows of text inside the page, read or only found.
  let textRows: Int
  /// Read lines inside the page with at least four Latin letters.
  let readableLines: Int
  /// Lines of text that run past the page's detected edge or the frame.
  let cutRows: Int

  static let empty = ScannerTextLayoutSummary(textRows: 0, readableLines: 0, cutRows: 0)
}

enum ScannerTextLayout {
  static let insideShare: CGFloat = 0.85
  static let cutMinimumShare: CGFloat = 0.25
  /// About half a character of a page's printed line.
  static let cutOverhang: CGFloat = 0.012
  static let minimumRowWidth: CGFloat = 0.06

  static func summarize(lines: [ScannerTextObservation], regions: [ScannerTextObservation],
                        page: [CGPoint]) -> ScannerTextLayoutSummary {
    guard let pageBounds = ScannerTextGeometry.bounds(page) else { return .empty }
    var inside: [CGRect] = []
    var readable = 0
    var cut = 0
    for element in lines + regions {
      let share = ScannerTextGeometry.overlapShare(of: element.pageBox, in: pageBounds)
      // Text partly on the page that reaches past its edge, or to the frame,
      // goes on where the camera cannot see it. A sliver past the edge is the
      // outline's own jitter.
      let runsOff = ScannerTextGeometry.overhang(of: element.pageBox, beyond: pageBounds) >= cutOverhang
        || ScannerTextGeometry.touchesBorder(element.pageBox)
      if share >= cutMinimumShare, runsOff, isLineLike(element) {
        cut += 1
      } else if share >= insideShare {
        inside.append(element.box)
        if let text = element.candidates.first, letters(text) >= 4 { readable += 1 }
      }
    }
    return ScannerTextLayoutSummary(textRows: rows(inside), readableLines: readable, cutRows: cut)
  }

  static func letters(_ text: String) -> Int {
    text.unicodeScalars.filter { (0x41...0x5A).contains($0.value) || (0x61...0x7A).contains($0.value) }.count
  }

  /// Read text of three characters or more, or a found region shaped like a word.
  static func isLineLike(_ element: ScannerTextObservation) -> Bool {
    if let text = element.candidates.first {
      return text.filter { !$0.isWhitespace }.count >= 3
    }
    return element.box.width >= element.box.height * 1.5
  }

  /// Boxes that share most of their height make one row.
  static func rows(_ boxes: [CGRect]) -> Int {
    var rows: [CGRect] = []
    for box in boxes.filter({ $0.height > 0 }).sorted(by: ScannerTextGeometry.topFirst) {
      if let last = rows.last {
        let overlap = min(last.maxY, box.maxY) - max(last.minY, box.minY)
        if overlap >= min(last.height, box.height) * 0.5 {
          rows[rows.count - 1] = ScannerTextGeometry.union(last, box)
          continue
        }
      }
      rows.append(box)
    }
    return rows.filter { $0.width >= minimumRowWidth }.count
  }
}

/// What one frame says, in the terms the gate decides on.
struct ScannerTextFrameSummary {
  let quarterTurns: Int
  let td3: [[UInt8]?]?
  let td1: [[UInt8]?]?
  let machineRows: Int
  /// Median height of the machine-like rows, in pixels of the image read.
  let machineRowHeight: CGFloat?
  let machineRowsCut: Bool
  let layout: ScannerTextLayoutSummary
  let cardNumbers: [String]
  let cardKeyword: Bool
  /// The page's long side, in pixels of the image read.
  let pageLongSide: CGFloat
  /// Read lines inside the page, top first, cleaned and bounded.
  let lines: [String]
}

enum ScannerTextFrameAnalysis {
  static let maximumLines = 24
  static let maximumLineLength = 120

  static func summarize(_ frame: ScannerTextFrame) -> ScannerTextFrameSummary {
    let rows = ScannerMRZReader.machineRows(frame.lines)
    let pageBounds = ScannerTextGeometry.bounds(frame.page)
    let heights = rows.map { $0.box.height * frame.readingSize.height }.sorted()
    let insideLines = frame.lines.filter { line in
      pageBounds.map { ScannerTextGeometry.overlapShare(of: line.pageBox, in: $0) >= 0.5 } ?? false
    }.sorted { $0.box.maxY != $1.box.maxY ? $0.box.maxY > $1.box.maxY : $0.box.minX < $1.box.minX }
    let texts = insideLines.compactMap { $0.candidates.first }
    let cut = rows.contains { row in
      ScannerTextGeometry.touchesBorder(row.pageBox)
        || pageBounds.map { ScannerTextGeometry.overhang(of: row.pageBox, beyond: $0) >= ScannerTextLayout.cutOverhang } ?? false
    }
    return ScannerTextFrameSummary(
      quarterTurns: frame.quarterTurns,
      td3: ScannerMRZReader.td3(in: rows),
      td1: ScannerMRZReader.td1(in: rows),
      machineRows: rows.count,
      machineRowHeight: heights.isEmpty ? nil : heights[heights.count / 2],
      machineRowsCut: cut,
      layout: ScannerTextLayout.summarize(lines: frame.lines, regions: frame.regions, page: frame.page),
      cardNumbers: ScannerCardFront.numbers(in: texts),
      cardKeyword: ScannerCardFront.hasKeyword(texts),
      pageLongSide: max(frame.readingSize.width, frame.readingSize.height) / (1 + ScannerTextGeometry.cropExpansion),
      lines: Array(texts.compactMap(clean).prefix(maximumLines)))
  }

  /// One line for the portal: no control characters, single spaces, bounded.
  static func clean(_ text: String) -> String? {
    let words = text.unicodeScalars
      .map { CharacterSet.controlCharacters.contains($0) ? " " : String($0) }
      .joined()
      .split(whereSeparator: { $0.isWhitespace })
    let line = String(words.joined(separator: " ").prefix(maximumLineLength))
    return line.isEmpty ? nil : line
  }
}

// MARK: The right-document gate

enum ScannerTextGuidance: String, Equatable {
  case reading
  case showMachineLines
  case moveCloserMachineLines
  case glareOnMachineLines
  case showWholeMachineLines
  case differentPaper
  case turnCardToFront
  case turnCardToBack
  case showCardDetails
  case glareOnText
  case moveCloserText
  case showPrintedText
  case textRunsPastEdge

  /// Holding still is what helps now.
  var asksToHold: Bool { self == .reading }

  /// The reading saw the wrong paper, or the wrong side of a card: the student
  /// has to act, so a clear page is not taken for it. Every other guidance is
  /// the reading still looking, which a clear page does not wait on for long.
  var holdsCapture: Bool { self == .differentPaper || self == .turnCardToFront || self == .turnCardToBack }

  func copy(for kind: ScannerPaperKind) -> ScannerGuidanceCopy {
    switch self {
    case .reading:
      switch kind {
      case .passport:
        return ScannerGuidanceCopy(title: "Hold still", detail: "Reading the two lines at the bottom…", compact: "Reading…")
      case .idCard:
        return ScannerGuidanceCopy(title: "Hold still", detail: "Reading the card…", compact: "Reading…")
      case .paper:
        return ScannerGuidanceCopy(title: "Hold still", detail: "Reading the page…", compact: "Reading…")
      }
    case .showMachineLines:
      return kind == .idCard
        ? ScannerGuidanceCopy(title: "Show the back of the card",
            detail: "Show the back with the three lines at the bottom.", compact: "Three bottom lines.")
        : ScannerGuidanceCopy(title: "Show the photo page",
            detail: "Show the photo page with the two lines at the bottom.", compact: "Two bottom lines.")
    case .moveCloserMachineLines:
      return ScannerGuidanceCopy(title: "Move closer", detail: kind == .idCard
        ? "Move closer — the lines on the card are too small."
        : "Move closer — the bottom lines are too small.", compact: "Move closer.")
    case .glareOnMachineLines:
      return ScannerGuidanceCopy(title: "Glare on the bottom lines", detail: "Tilt the phone slightly.",
        compact: "Tilt slightly.")
    case .showWholeMachineLines:
      return kind == .idCard
        ? ScannerGuidanceCopy(title: "Show the three bottom lines",
            detail: "Keep the three lines on the back of the card fully in view.", compact: "All three lines.")
        : ScannerGuidanceCopy(title: "Show both bottom lines",
            detail: "Keep the two lines at the bottom of the photo page fully in view.", compact: "Both bottom lines.")
    case .differentPaper:
      let detail: String
      switch kind {
      case .passport: detail = "Show your passport’s photo page."
      case .idCard: detail = "Show the ID card."
      case .paper: detail = "Show the paper this step asks for."
      }
      return ScannerGuidanceCopy(title: "This looks like a different paper", detail: detail, compact: "Different paper.")
    case .turnCardToFront:
      return ScannerGuidanceCopy(title: "Turn the card over", detail: "Show the front of the card, with the photo.",
        compact: "Show the front.")
    case .turnCardToBack:
      return ScannerGuidanceCopy(title: "Turn the card over",
        detail: "Show the back of the card, with the lines at the bottom.", compact: "Show the back.")
    case .showCardDetails:
      return ScannerGuidanceCopy(title: "Show the card", detail: "Keep the card’s printed details in view.",
        compact: "Card details.")
    case .glareOnText:
      return ScannerGuidanceCopy(title: "Glare on the card", detail: "Tilt the phone slightly.",
        compact: "Tilt slightly.")
    case .moveCloserText:
      return ScannerGuidanceCopy(title: "Move closer", detail: "Move closer so the text is readable.",
        compact: "Move closer.")
    case .showPrintedText:
      return ScannerGuidanceCopy(title: "Show the printed side", detail: "Show the side of the page with the text.",
        compact: "Printed side.")
    case .textRunsPastEdge:
      return ScannerGuidanceCopy(title: "Show all four corners", detail: "Some text runs past the edge of the view.",
        compact: "All four corners.")
    }
  }
}

struct ScannerTextGateStatus: Equatable {
  /// The reading says this is the paper the step asked for.
  let passed: Bool
  /// Automatic capture may go ahead: the reading passed, or this phone cannot read text at all.
  let allowsCapture: Bool
  let guidance: ScannerTextGuidance?

  static let passedReading = ScannerTextGateStatus(passed: true, allowsCapture: true, guidance: nil)
  static let cannotRead = ScannerTextGateStatus(passed: false, allowsCapture: true, guidance: nil)

  static func waiting(_ guidance: ScannerTextGuidance) -> ScannerTextGateStatus {
    ScannerTextGateStatus(passed: false, allowsCapture: false, guidance: guidance)
  }

  /// How long a clear, steady page waits for the reading before it is taken
  /// anyway (the owner, 30 Oct 2026: "it should be automatic once the shot is
  /// clear"). A passport or a card gives the reading of its lines a little
  /// longer: those lines fill the student's details when the server's reader
  /// cannot answer.
  static func clearPageGrace(for kind: ScannerPaperKind) -> TimeInterval {
    kind == .paper ? 0.8 : 1.5
  }

  /// Whether a page that has been clear and steady for `clearFor` seconds is
  /// taken now: at once when the reading passed (or the phone cannot read),
  /// once the grace is over while the reading is still looking, and never
  /// while it has seen the wrong paper or the wrong side of a card (the
  /// shutter that appears after a few seconds is there for that).
  func capturesWhenClear(for clearFor: TimeInterval, kind: ScannerPaperKind) -> Bool {
    if allowsCapture { return true }
    if guidance?.holdsCapture == true { return false }
    return clearFor >= Self.clearPageGrace(for: kind)
  }
}

/// When a page in view is taken with no tap (the owner, 30 Oct 2026: "it should be automatic
/// once the shot is clear"; on build 54 it still needed the button). Build 54 took a page only
/// after an unbroken run of clear, steady frames: one soft frame, a tremor of the hand or a dim
/// room started the wait over, and the shutter appeared before it ended. Frame by frame, the
/// first way in that is due wins:
/// - steady and read: the hold is complete and the reading passed (or this phone cannot read);
/// - steady: the hold has been complete for the paper's grace (`clearPageGrace`), counted from
///   the first time it was, through any frame missed since;
/// - in view: a whole page has been in view for `inViewLimit`, steady or not, sharp or not.
///   The camera's own focus wait and the photo checks still judge every photo.
/// Never while the reading has seen the wrong paper or the wrong side of a card: the shutter
/// that appears after a few seconds is there for that. The clocks start over once the page has
/// been out of view for `pageLossReset`.
struct ScannerAutoShutter {
  enum Page: Equatable {
    /// No whole page in this frame: none, or one cut off, too small or the wrong shape.
    case missing
    /// A whole page, not (yet) steady or sharp enough to count toward the hold.
    case inView
    /// The hold is complete.
    case steady
  }

  static let pageLossReset: TimeInterval = 0.8
  /// A page in shadow, glare or dim light has this long to be fixed before it is taken anyway:
  /// a slightly shadowed page beats no page.
  static let lightingGrace: TimeInterval = 1.5

  /// How long a whole page stays in view before it is taken, steady or not.
  static func inViewLimit(for kind: ScannerPaperKind) -> TimeInterval {
    kind == .paper ? 2.5 : 3.5
  }

  private(set) var inViewSince: TimeInterval?
  private(set) var steadySince: TimeInterval?
  private var lastSeen: TimeInterval?

  /// How long the page has been steady, through any frame missed since; 0 before it ever was.
  func steadyFor(at time: TimeInterval) -> TimeInterval {
    steadySince.map { max(0, time - $0) } ?? 0
  }

  /// One preview frame. True when the page in it is to be taken now.
  mutating func observe(_ page: Page, at time: TimeInterval, reading: ScannerTextGateStatus,
                        kind: ScannerPaperKind, lightingGood: Bool) -> Bool {
    guard time.isFinite else {
      reset()
      return false
    }
    guard page != .missing else {
      if let lastSeen, time - lastSeen >= Self.pageLossReset { reset() }
      return false
    }
    lastSeen = time
    if inViewSince == nil { inViewSince = time }
    if page == .steady, steadySince == nil { steadySince = time }
    if reading.guidance?.holdsCapture == true { return false }
    if page == .steady {
      let steady = steadyFor(at: time)
      if (lightingGood || steady >= Self.lightingGrace) && reading.capturesWhenClear(for: steady, kind: kind) {
        return true
      }
    }
    return time - (inViewSince ?? time) >= Self.inViewLimit(for: kind)
  }

  mutating func reset() {
    inViewSince = nil
    steadySince = nil
    lastSeen = nil
  }
}

/// The reading of one page while it is in view, and the gate on automatic
/// capture: steady is not enough, the paper must also be the right one.
struct ScannerTextReadingSession {
  static let requiredSupportingReads = 2
  static let pageLossReset: TimeInterval = 1.5
  static let pageJumpReset: CGFloat = 0.2
  static let readerFailureLimit = 4
  static let disagreementReset = 0.3
  static let minimumPaperRows = 3
  /// Machine lines shorter than this, in pixels, are too small to read live.
  static let minimumMachineRowHeight: CGFloat = 14
  static let paperTurns = [0, 1, 3]

  /// Below this long side, in pixels of the image read, the print is too small.
  static func minimumPageSide(for kind: ScannerPaperKind) -> CGFloat {
    switch kind {
    case .passport: return 800
    case .idCard: return 560
    case .paper: return 900
    }
  }

  static func initialPolicy(for kind: ScannerPaperKind) -> ScannerTextTurnPolicy {
    kind == .paper ? .fixed(paperTurns[0]) : .landscape(upsideDown: false)
  }

  let kind: ScannerPaperKind
  let side: ScannerCardSide?
  let rejectsIdentityPapers: Bool
  let settings: ScannerTextReadSettings
  private(set) var framesRead = 0
  private(set) var readerUnavailable = false
  private(set) var turnPolicy: ScannerTextTurnPolicy
  private(set) var latest: ScannerTextFrameSummary?
  private var previous: ScannerTextFrameSummary?
  private var consecutiveFailures = 0
  private var td3Votes = ScannerMRZVotes(format: .td3)
  private var td1Votes = ScannerMRZVotes(format: .td1)
  private var readsWithText = 0
  private var readsWithoutText = 0
  private var readsWithoutMachineRows = 0
  private var cardNumberCounts: [String: Int] = [:]
  private var cardKeywordSeen = false
  private var turnLocked = false
  private var paperTurnIndex = 0
  private var paperTurnScores: [Int: Int] = [:]
  private var lastPage: ScannerQuadrilateral?
  private var pageMissingSince: TimeInterval?

  init(kind: ScannerPaperKind, side: ScannerCardSide? = nil, rejectsIdentityPapers: Bool = false) {
    self.kind = kind
    self.side = kind == .idCard ? side : nil
    self.rejectsIdentityPapers = kind == .paper && rejectsIdentityPapers
    settings = ScannerTextReadSettings.settings(for: kind)
    turnPolicy = Self.initialPolicy(for: kind)
  }

  init(profile: FoorsaScannerProfile) {
    self.init(kind: profile.paperKind, side: profile.cardSide, rejectsIdentityPapers: profile.rejectsIdentityPapers)
  }

  /// Starts the reading over, for another page. Whether this phone can read
  /// text at all is kept.
  mutating func reset() {
    framesRead = 0
    turnPolicy = Self.initialPolicy(for: kind)
    latest = nil
    previous = nil
    td3Votes = ScannerMRZVotes(format: .td3)
    td1Votes = ScannerMRZVotes(format: .td1)
    readsWithText = 0
    readsWithoutText = 0
    readsWithoutMachineRows = 0
    cardNumberCounts = [:]
    cardKeywordSeen = false
    turnLocked = false
    paperTurnIndex = 0
    paperTurnScores = [:]
    lastPage = nil
    pageMissingSince = nil
  }

  /// Follows the page the reading belongs to. A page gone for a moment or a
  /// jump to another outline starts the reading over; returns true then.
  mutating func observePage(_ quadrilateral: ScannerQuadrilateral?, at time: TimeInterval) -> Bool {
    guard let quadrilateral else {
      if pageMissingSince == nil { pageMissingSince = time }
      if let since = pageMissingSince, time - since >= Self.pageLossReset, framesRead > 0 || lastPage != nil {
        reset()
        return true
      }
      return false
    }
    pageMissingSince = nil
    defer { lastPage = quadrilateral }
    if let lastPage, quadrilateral.maximumCornerDistance(to: lastPage) > Self.pageJumpReset {
      reset()
      return true
    }
    return false
  }

  /// A read the text engine could not do at all. Several in a row mean this
  /// phone cannot read text, and automatic capture goes back to steadiness alone.
  mutating func readFailed() {
    consecutiveFailures += 1
    if consecutiveFailures >= Self.readerFailureLimit { readerUnavailable = true }
  }

  mutating func ingest(_ frame: ScannerTextFrame) {
    consecutiveFailures = 0
    let summary = ScannerTextFrameAnalysis.summarize(frame)
    framesRead += 1
    if let lines = summary.td3 { vote(lines, format: .td3) }
    if let lines = summary.td1 { vote(lines, format: .td1) }
    previous = latest
    latest = summary
    if summary.layout.textRows >= Self.minimumPaperRows {
      if summary.layout.cutRows == 0 { readsWithText += 1 }
      readsWithoutText = 0
    } else {
      readsWithoutText += 1
    }
    readsWithoutMachineRows = summary.machineRows == 0 ? readsWithoutMachineRows + 1 : 0
    for number in Set(summary.cardNumbers) { cardNumberCounts[number, default: 0] += 1 }
    if summary.cardKeyword { cardKeywordSeen = true }
    advanceTurn(after: summary)
  }

  private mutating func vote(_ lines: [[UInt8]?], format: ScannerMRZFormat) {
    var votes = format == .td3 ? td3Votes : td1Votes
    if votes.reads.count >= 2, let disagreement = votes.disagreement(with: lines),
       disagreement > Self.disagreementReset {
      // Most of the checked characters changed: another paper.
      votes = ScannerMRZVotes(format: format)
    }
    votes.add(lines)
    if format == .td3 { td3Votes = votes } else { td1Votes = votes }
  }

  private mutating func advanceTurn(after summary: ScannerTextFrameSummary) {
    guard !turnLocked else { return }
    switch kind {
    case .passport, .idCard:
      let found = summary.machineRows > 0 || (kind == .idCard
        && (summary.layout.readableLines >= 3 || !summary.cardNumbers.isEmpty))
      if found {
        turnLocked = true
      } else if case let .landscape(upsideDown) = turnPolicy {
        turnPolicy = .landscape(upsideDown: !upsideDown)
      }
    case .paper:
      let turns = summary.quarterTurns
      paperTurnScores[turns] = max(paperTurnScores[turns] ?? 0, summary.layout.readableLines)
      if summary.layout.readableLines >= 3 {
        turnLocked = true
        turnPolicy = .fixed(turns)
        return
      }
      paperTurnIndex += 1
      if paperTurnIndex < Self.paperTurns.count {
        turnPolicy = .fixed(Self.paperTurns[paperTurnIndex])
        return
      }
      // Nothing Latin read every way: keep the page as seen (Arabic, Chinese).
      turnLocked = true
      var best = Self.paperTurns[0]
      for turns in Self.paperTurns where (paperTurnScores[turns] ?? 0) > (paperTurnScores[best] ?? 0) { best = turns }
      turnPolicy = .fixed(best)
    }
  }

  /// The consensus of a format's votes, repaired and checked, with the
  /// number of reads that agree with it.
  func machineReading(_ format: ScannerMRZFormat) -> (result: ScannerMRZResult, supporting: Int)? {
    let votes = format == .td3 ? td3Votes : td1Votes
    let consensus = votes.consensus
    guard consensus.allSatisfy({ $0 != nil }) else { return nil }
    let result = ScannerMRZValidator.validate(consensus.compactMap { $0 }, format: format, tallies: votes.counts)
    return (result, votes.supportingReads(for: result.lines))
  }

  /// A valid reading that at least two reads agree with.
  func confirmed(_ format: ScannerMRZFormat) -> ScannerMRZResult? {
    guard let reading = machineReading(format), reading.result.valid,
          reading.supporting >= Self.requiredSupportingReads else { return nil }
    return reading.result
  }

  /// The card number read on the front at least twice.
  var frontNumber: String? {
    cardNumberCounts.filter { $0.value >= Self.requiredSupportingReads }
      .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
      .first?.key
  }

  var frontRead: Bool {
    guard frontNumber != nil, let latest else { return false }
    return cardKeywordSeen || latest.layout.readableLines >= 3 || latest.layout.textRows >= 5
  }

  func status(glare: Bool) -> ScannerTextGateStatus {
    if readerUnavailable { return .cannotRead }
    let passport = confirmed(.td3) != nil
    let card = confirmed(.td1) != nil
    switch kind {
    case .passport:
      if passport { return .passedReading }
      if card { return .waiting(.differentPaper) }
      return .waiting(machineGuidance(glare: glare))
    case .idCard:
      if passport { return .waiting(.differentPaper) }
      let front = frontRead
      switch side {
      case .back?:
        if card { return .passedReading }
        return .waiting(front ? .turnCardToBack : machineGuidance(glare: glare))
      case .front?:
        if front { return .passedReading }
        return .waiting(card ? .turnCardToFront : frontGuidance(glare: glare))
      case nil:
        if card || front { return .passedReading }
        return .waiting((latest?.machineRows ?? 0) > 0 ? machineGuidance(glare: glare) : frontGuidance(glare: glare))
      }
    case .paper:
      if rejectsIdentityPapers, passport || card { return .waiting(.differentPaper) }
      return paperStatus()
    }
  }

  private func machineGuidance(glare: Bool) -> ScannerTextGuidance {
    guard let latest else { return .reading }
    if latest.machineRows == 0 {
      if latest.pageLongSide < Self.minimumPageSide(for: kind) { return .moveCloserMachineLines }
      guard readsWithoutMachineRows >= 2 else { return .reading }
      return glare ? .glareOnMachineLines : .showMachineLines
    }
    if let height = latest.machineRowHeight, height < Self.minimumMachineRowHeight { return .moveCloserMachineLines }
    if latest.machineRowsCut { return .showWholeMachineLines }
    return glare ? .glareOnMachineLines : .reading
  }

  private func frontGuidance(glare: Bool) -> ScannerTextGuidance {
    guard let latest else { return .reading }
    if latest.layout.readableLines < 3, latest.pageLongSide < Self.minimumPageSide(for: .idCard) {
      return .moveCloserText
    }
    if glare { return .glareOnText }
    if latest.layout.readableLines == 0, latest.layout.textRows == 0, readsWithoutText >= 2 { return .showCardDetails }
    return .reading
  }

  private func paperStatus() -> ScannerTextGateStatus {
    guard let latest else { return .waiting(.reading) }
    if latest.layout.cutRows > 0 {
      return .waiting((previous?.layout.cutRows ?? 0) > 0 ? .textRunsPastEdge : .reading)
    }
    if latest.layout.textRows >= Self.minimumPaperRows {
      return readsWithText >= Self.requiredSupportingReads ? .passedReading : .waiting(.reading)
    }
    if latest.pageLongSide < Self.minimumPageSide(for: .paper) { return .waiting(.moveCloserText) }
    return .waiting(readsWithoutText >= 2 ? .showPrintedText : .reading)
  }

  /// What was read, for the portal, returned only with the student's own
  /// capture of this paper. Bounded: machine lines, a few fields and at most
  /// 24 read lines of 120 characters.
  func liveReading(engine: String, matched: Bool, referenceYear: Int) -> [String: Any] {
    var reading: [String: Any] = [
      "version": 1,
      "kind": kind.rawValue,
      "matched": matched,
      "engine": engine,
      "frames": framesRead,
      "mrzValid": false,
      "lines": latest?.lines ?? [],
    ]
    var format: ScannerMRZFormat?
    switch kind {
    case .passport: format = .td3
    case .idCard: format = .td1
    case .paper: format = nil
    }
    // What the step asked for first; otherwise a confirmed other paper, so
    // the portal can see what was shown instead.
    if let asked = format, machineReading(asked) == nil { format = nil }
    if format == nil {
      format = confirmed(.td3) != nil ? .td3 : confirmed(.td1) != nil ? .td1 : nil
    }
    if let format, let machine = machineReading(format) {
      reading["mrzFormat"] = format.rawValue
      reading["mrz"] = machine.result.text
      reading["mrzValid"] = machine.result.valid
      if let fields = ScannerMRZFields(machine.result) {
        reading["fields"] = fields.dictionary(referenceYear: referenceYear)
        if kind == .idCard, format == .td1 { reading["side"] = ScannerCardSide.back.rawValue }
      }
    }
    if kind == .idCard, reading["side"] == nil, frontRead, let number = frontNumber {
      reading["side"] = ScannerCardSide.front.rawValue
      reading["fields"] = ["documentNumber": number]
    }
    return reading
  }
}
