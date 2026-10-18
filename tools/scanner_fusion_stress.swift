import CoreGraphics
import Foundation

@main
struct ScannerFusionStress {
  static func main() throws {
    let arguments = CommandLine.arguments
    guard (6...8).contains(arguments.count) else {
      FileHandle.standardError.write(Data(
        "usage: scanner-fusion-stress <document-key> <output.jpg|-> <frame1> <frame2> <frame3> [frame4] [frame5]\n".utf8
      ))
      Foundation.exit(64)
    }
    let profile = FoorsaScannerProfile(arguments: [
      "profile": ["documentKey": arguments[1]],
    ])
    let processor = ScannerImageProcessor()
    let started = CFAbsoluteTimeGetCurrent()
    let candidates = try arguments.dropFirst(3).map { path -> ScannerProcessedCandidate in
      let data = try Data(contentsOf: URL(fileURLWithPath: path))
      guard let candidate = processor.process(photoData: data, profile: profile) else {
        throw StressError.rejected(path)
      }
      return candidate
    }
    guard let resolution = processor.resolveBurst(candidates, profile: profile) else {
      throw StressError.noResolution
    }
    if arguments[2] != "-" {
      try resolution.candidate.jpeg.write(
        to: URL(fileURLWithPath: arguments[2]),
        options: .atomic
      )
    }
    let image = resolution.candidate.correctedImage
    var report: [String: Any] = [
      "mode": resolution.mode.rawValue,
      "framesConsidered": resolution.framesConsidered,
      "framesUsed": resolution.framesUsed,
      "fallbackReason": resolution.fallbackReason?.rawValue ?? NSNull(),
      "alignmentModels": resolution.alignmentModels.map(\.rawValue),
      "bytes": resolution.candidate.jpeg.count,
      "width": image?.width ?? 0,
      "height": image?.height ?? 0,
      "sharpness": resolution.candidate.sharpness,
      "milliseconds": (CFAbsoluteTimeGetCurrent() - started) * 1_000,
    ]
    if let lighting = resolution.lighting {
      report["lighting"] = [
        "shadowCorrectionApplied": lighting.shadowCorrectionApplied,
        "glarePixelsReplacedFraction": lighting.glarePixelsReplacedFraction,
        "unresolvedGlareFraction": lighting.unresolvedGlareFraction,
        "needsDifferentAngle": lighting.needsDifferentAngle,
      ]
    }
    let json = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    FileHandle.standardOutput.write(json)
    FileHandle.standardOutput.write(Data("\n".utf8))
  }
}

private enum StressError: LocalizedError {
  case rejected(String)
  case noResolution

  var errorDescription: String? {
    switch self {
    case let .rejected(path): return "The scanner rejected frame: \(path)"
    case .noResolution: return "The burst produced no usable output."
    }
  }
}
