import CoreGraphics
import Foundation

struct FoorsaScannerProfile {
  enum Layout: String { case passport, card, portrait, adaptive }

  // Keep this list aligned with the portal's canonical folder keys. A caller's
  // layout hint cannot turn a known paper document into a passport or card.
  private static let folderLayouts: [String: Layout] = [
    "identity": .passport, "parent_id": .card,
    "highest_degree": .adaptive, "last_year_degree": .adaptive,
    "transcript": .adaptive, "last_year_transcript": .adaptive,
    "medical_check": .portrait, "criminal_record": .adaptive,
    "bank_statement": .adaptive, "english_test": .adaptive,
    "recommendation_letter": .portrait, "study_plan": .portrait,
    "research_proposal": .portrait, "cv": .portrait,
    "birth_certificate": .adaptive, "contract": .portrait,
    "receipts": .adaptive, "admissions": .adaptive,
    "universities_notices": .adaptive, "visa_documents": .adaptive,
    "application_form": .portrait, "authorizations": .portrait,
    "introduction_video": .portrait, "csca": .adaptive,
    "previous_chinese_universities": .adaptive,
    "publications": .portrait, "supervisor_acceptance": .adaptive,
    "drive_files": .adaptive,
  ]

  let documentKey: String
  let title: String
  let instruction: String
  let layout: Layout

  // A card contains far less text than a full paper page and can be legible at
  // a smaller camera footprint. Keep corner accuracy and edge margins equal.
  var minimumCaptureArea: CGFloat { layout == .card ? 0.12 : 0.16 }

  init(arguments: Any?) {
    let arguments = arguments as? [String: Any]
    let source = arguments?["profile"] as? [String: Any]
    let rawTitle = (source?["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    let rawInstruction = (source?["instruction"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    title = rawTitle.flatMap { $0.isEmpty || $0.count > 70 ? nil : $0 } ?? "Scan document"
    instruction = rawInstruction.flatMap { $0.isEmpty || $0.count > 200 ? nil : $0 }
      ?? "Keep every corner and all printed details visible."
    let rawKey = (source?["documentKey"] as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    documentKey = Self.folderLayouts[rawKey] == nil ? "drive_files" : rawKey
    if rawKey.isEmpty {
      // Older callers supplied only a layout. Retain that bounded hint.
      layout = Layout(rawValue: source?["layout"] as? String ?? "") ?? .adaptive
    } else {
      layout = Self.folderLayouts[documentKey] ?? .adaptive
    }
  }

  func accepts(aspectRatio ratio: CGFloat) -> Bool {
    guard ratio.isFinite, ratio > 0 else { return false }
    let shape = max(ratio, 1 / ratio)
    switch layout {
    case .passport:
      // Data pages and open spreads can present either side vertically.
      return shape >= 1.14 && shape <= 1.84
    case .card: return shape >= 1.27 && shape <= 2.0
    case .portrait: return shape <= 2.0
    case .adaptive:
      // Receipt slips have longer borders; all other unknown or flexible
      // papers keep the ordinary document range.
      return shape <= (documentKey == "receipts" ? 3.2 : 2.1)
    }
  }
}


struct ScannerQuadrilateral: Equatable {
  let topLeft: CGPoint
  let topRight: CGPoint
  let bottomRight: CGPoint
  let bottomLeft: CGPoint

  var points: [CGPoint] { [topLeft, topRight, bottomRight, bottomLeft] }

  var area: CGFloat {
    let p = points
    let following = Array(p.dropFirst()) + [p[0]]
    return abs(zip(p, following).reduce(CGFloat.zero) {
      $0 + $1.0.x * $1.1.y - $1.1.x * $1.0.y
    }) * 0.5
  }

  var centroid: CGPoint {
    CGPoint(
      x: points.reduce(0) { $0 + $1.x } / 4,
      y: points.reduce(0) { $0 + $1.y } / 4
    )
  }

  func estimatedAspectRatio(in imageSize: CGSize) -> CGFloat {
    guard imageSize.width > 0, imageSize.height > 0 else { return 0 }
    func imagePoint(_ point: CGPoint) -> CGPoint {
      CGPoint(x: point.x * imageSize.width, y: point.y * imageSize.height)
    }
    let topLeft = imagePoint(topLeft)
    let topRight = imagePoint(topRight)
    let bottomRight = imagePoint(bottomRight)
    let bottomLeft = imagePoint(bottomLeft)
    let width = (topLeft.distance(to: topRight) + bottomLeft.distance(to: bottomRight)) / 2
    let height = (topLeft.distance(to: bottomLeft) + topRight.distance(to: bottomRight)) / 2
    return height > 0.001 ? width / height : 0
  }

  func maximumCornerDistance(to other: ScannerQuadrilateral) -> CGFloat {
    zip(points, other.points).map { $0.distance(to: $1) }.max() ?? 1
  }

  func isComplete(minimumArea: CGFloat = 0.16) -> Bool {
    guard area >= minimumArea else { return false }
    return points.allSatisfy { point in
      point.x >= 0.015 && point.x <= 0.985 && point.y >= 0.015 && point.y <= 0.985
    }
  }
}

// The preview shows the entire oriented camera image inside the space left by
// controls. A guide therefore has a predictable camera footprint on tall phones.
struct ScannerPreviewGeometry {
  let previewRect: CGRect
  let guideRect: CGRect

  init(imageSize: CGSize, availableRect: CGRect, guideAspectRatio: CGFloat) {
    guard imageSize.width.isFinite, imageSize.height.isFinite,
          imageSize.width > 0, imageSize.height > 0,
          availableRect.width > 0, availableRect.height > 0,
          guideAspectRatio.isFinite, guideAspectRatio > 0 else {
      previewRect = .zero
      guideRect = .zero
      return
    }
    let scale = min(availableRect.width / imageSize.width,
      availableRect.height / imageSize.height)
    let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    previewRect = CGRect(x: availableRect.midX - size.width / 2,
      y: availableRect.midY - size.height / 2, width: size.width, height: size.height)
    // Five percent on each edge leaves room for imperfect framing. Even a
    // document at 90% of this guide exceeds the unchanged capture-area gate
    // for passport/card/paper guides and 4:3 or 16:9 camera images.
    let width = min(size.width * 0.9, size.height * 0.9 * guideAspectRatio)
    let height = width / guideAspectRatio
    guideRect = CGRect(x: previewRect.midX - width / 2,
      y: previewRect.midY - height / 2, width: width, height: height)
  }
}

enum ScannerAspectFillMapper {
  static func videoRect(imageSize: CGSize, in bounds: CGRect) -> CGRect {
    guard imageSize.width > 0, imageSize.height > 0,
          bounds.width > 0, bounds.height > 0 else { return bounds }
    let scale = max(bounds.width / imageSize.width, bounds.height / imageSize.height)
    let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    return CGRect(
      x: bounds.midX - size.width / 2,
      y: bounds.midY - size.height / 2,
      width: size.width,
      height: size.height
    )
  }

  static func layerPoint(
    fromVisionPoint point: CGPoint,
    imageSize: CGSize,
    in bounds: CGRect
  ) -> CGPoint {
    let videoRect = videoRect(imageSize: imageSize, in: bounds)
    return CGPoint(
      x: videoRect.minX + point.x * videoRect.width,
      y: videoRect.minY + (1 - point.y) * videoRect.height
    )
  }
}

extension CGPoint {
  fileprivate func distance(to other: CGPoint) -> CGFloat {
    hypot(x - other.x, y - other.y)
  }
}

struct ScannerStabilityState: Equatable {
  let progress: CGFloat
  let ready: Bool
}

struct ScannerStabilityTracker {
  static let maximumObservationAge: TimeInterval = 0.65
  private(set) var anchor: ScannerQuadrilateral?
  private(set) var stableSince: TimeInterval?
  private(set) var lastSeen: TimeInterval?
  private var lastProcessingDuration: TimeInterval = 0
  private var consecutiveObservations = 0
  let requiredDuration: TimeInterval
  let minimumArea: CGFloat

  init(requiredDuration: TimeInterval = 0.72, minimumArea: CGFloat = 0.16) {
    self.requiredDuration = requiredDuration
    self.minimumArea = minimumArea
  }

  mutating func observe(
    _ quadrilateral: ScannerQuadrilateral?,
    at time: TimeInterval,
    processingDuration: TimeInterval = 0
  ) -> ScannerStabilityState {
    guard time.isFinite, processingDuration.isFinite,
          processingDuration >= 0, processingDuration <= Self.maximumObservationAge,
          let quadrilateral, quadrilateral.isComplete(minimumArea: minimumArea) else {
      reset()
      return ScannerStabilityState(progress: 0, ready: false)
    }
    // Account for time spent analyzing the previous frame, while retaining a
    // hard ceiling so a camera interruption cannot count as a continuous hold.
    let allowedGap = min(Self.maximumObservationAge, max(0.28, lastProcessingDuration * 1.5 + 0.12))
    defer {
      lastSeen = time
      lastProcessingDuration = processingDuration
    }
    guard let anchor, let stableSince,
          quadrilateral.maximumCornerDistance(to: anchor) <= 0.026,
          abs(quadrilateral.area - anchor.area) <= 0.035,
          lastSeen.map({ time > $0 && time - $0 < allowedGap }) ?? false else {
      self.anchor = quadrilateral
      self.stableSince = time
      consecutiveObservations = 1
      return ScannerStabilityState(progress: 0, ready: false)
    }
    // Slowly follow hand drift while preserving a stable reference window.
    self.anchor = anchor.blended(with: quadrilateral, amount: 0.18)
    consecutiveObservations += 1
    let progress = min(1, CGFloat(consecutiveObservations - 1) / 3,
      max(0, CGFloat((time - stableSince) / requiredDuration)))
    return ScannerStabilityState(progress: progress, ready: progress >= 1)
  }

  mutating func reset() {
    anchor = nil
    stableSince = nil
    lastSeen = nil
    lastProcessingDuration = 0
    consecutiveObservations = 0
  }
}

private extension ScannerQuadrilateral {
  func blended(with other: ScannerQuadrilateral, amount: CGFloat) -> ScannerQuadrilateral {
    func point(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
      CGPoint(x: a.x + (b.x - a.x) * amount, y: a.y + (b.y - a.y) * amount)
    }
    return ScannerQuadrilateral(
      topLeft: point(topLeft, other.topLeft),
      topRight: point(topRight, other.topRight),
      bottomRight: point(bottomRight, other.bottomRight),
      bottomLeft: point(bottomLeft, other.bottomLeft)
    )
  }
}

struct ScannerImageFingerprint: Equatable {
  let words: [UInt64]

  init(bits: UInt64) {
    words = [bits]
  }

  init(words: [UInt64]) {
    self.words = words
  }

  func distance(to other: ScannerImageFingerprint) -> Int {
    guard words.count == other.words.count else { return .max }
    return zip(words, other.words).reduce(0) { result, pair in
      result + (pair.0 ^ pair.1).nonzeroBitCount
    }
  }

  func isLikelySamePage(as other: ScannerImageFingerprint) -> Bool {
    guard words.count == other.words.count, !words.isEmpty else { return false }
    return distance(to: other) <= max(1, words.count / 2)
  }
}

struct ScannerProcessedCandidate {
  let jpeg: Data
  let sharpness: Double
  let coverage: Double
  let fingerprint: ScannerImageFingerprint
  // The corrected, uncompressed page is retained only until the three-shot
  // burst resolves. Keeping it out of the bridge avoids exposing extra copies
  // of a student's document while allowing one final, fused JPEG encode.
  let correctedImage: CGImage?

  init(
    jpeg: Data,
    sharpness: Double,
    coverage: Double,
    fingerprint: ScannerImageFingerprint,
    correctedImage: CGImage? = nil
  ) {
    self.jpeg = jpeg
    self.sharpness = sharpness
    self.coverage = coverage
    self.fingerprint = fingerprint
    self.correctedImage = correctedImage
  }
}

enum ScannerBurstResolutionMode: String, Equatable {
  case alignedMedianFusion = "aligned_median_fusion"
  case bestFrameFallback = "best_frame_fallback"
}

enum ScannerBurstFallbackReason: String, Equatable {
  case incompleteBurst = "incomplete_burst"
  case missingCorrectedImage = "missing_corrected_image"
  case frameTooSoft = "frame_too_soft"
  case incompatibleGeometry = "incompatible_geometry"
  case registrationRejected = "registration_rejected"
  case frameContentMismatch = "frame_content_mismatch"
  case renderOrEncodeFailure = "render_or_encode_failure"
}

enum ScannerBurstAlignmentModel: String, Equatable {
  case translation
  case homography
}

struct ScannerBurstResolution {
  let candidate: ScannerProcessedCandidate
  let mode: ScannerBurstResolutionMode
  let framesConsidered: Int
  let framesUsed: Int
  let fallbackReason: ScannerBurstFallbackReason?
  let alignmentModels: [ScannerBurstAlignmentModel]
}

enum ScannerCandidateSelector {
  static func best(_ candidates: [ScannerProcessedCandidate]) -> ScannerProcessedCandidate? {
    bestIndex(candidates).map { candidates[$0] }
  }

  static func bestIndex(_ candidates: [ScannerProcessedCandidate]) -> Int? {
    candidates.indices.max {
      let lhs = candidates[$0]
      let rhs = candidates[$1]
      if abs(lhs.sharpness - rhs.sharpness) > 0.0001 {
        return lhs.sharpness < rhs.sharpness
      }
      if abs(lhs.coverage - rhs.coverage) > 0.0001 {
        return lhs.coverage < rhs.coverage
      }
      return lhs.jpeg.count < rhs.jpeg.count
    }
  }
}

enum ScannerDuplicatePolicy {
  static func shouldReject(
    candidate: ScannerImageFingerprint,
    previous: ScannerImageFingerprint?,
    automatic: Bool
  ) -> Bool {
    guard automatic, let previous else { return false }
    return candidate.isLikelySamePage(as: previous)
  }
}
