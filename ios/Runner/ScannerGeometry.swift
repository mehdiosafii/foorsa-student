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
  let usesImagegen: Bool

  // A card contains far less text than a full paper page and can be legible at
  // a smaller camera footprint. Keep corner accuracy and edge margins equal.
  var minimumCaptureArea: CGFloat { layout == .card ? 0.12 : 0.16 }

  init(arguments: Any?) {
    let arguments = arguments as? [String: Any]
    let source = arguments?["profile"] as? [String: Any]
    usesImagegen = source?["outputMode"] as? String == "imagegen"
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
  case alignedLightingFusion = "aligned_lighting_fusion"
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

struct ScannerLightingSummary: Equatable {
  let shadowCorrectionApplied: Bool
  let glarePixelsReplacedFraction: Double
  let unresolvedGlareFraction: Double
  let needsDifferentAngle: Bool

  init(shadowCorrectionApplied: Bool = false, glarePixelsReplacedFraction: Double = 0,
       unresolvedGlareFraction: Double = 0, needsDifferentAngle: Bool = false) {
    self.shadowCorrectionApplied = shadowCorrectionApplied
    self.glarePixelsReplacedFraction = glarePixelsReplacedFraction
    self.unresolvedGlareFraction = unresolvedGlareFraction
    self.needsDifferentAngle = needsDifferentAngle
  }
}

struct ScannerBurstResolution {
  let candidate: ScannerProcessedCandidate
  let mode: ScannerBurstResolutionMode
  let framesConsidered: Int
  let framesUsed: Int
  let fallbackReason: ScannerBurstFallbackReason?
  let alignmentModels: [ScannerBurstAlignmentModel]
  var lighting: ScannerLightingSummary? = nil
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


// Pure capture policy: changing position alone cannot prove that reflected light
// moved. Require measurable perspective/foreshortening, then a fresh stable hold.
enum ScannerLightingAngleObservation: Equatable {
  case inactive
  case move
  case hold(CGFloat)
  case capture
  case expired
}

struct ScannerLightingAngleGuide {
  // A guided still is only an attempt until its processing result is resolved.
  // Two accepted guided views plus the initial anchor form the required set.
  static let maximumExtraCaptures = 4
  static let maximumCandidates = 3
  static let requiredExtraCaptures = 2
  static let waitDuration: TimeInterval = 18
  private(set) var extraCaptures = 0
  private(set) var acceptedExtraCaptures = 0
  private(set) var isWaiting = false
  private(set) var acceptedViews: [ScannerQuadrilateral]
  private(set) var pendingCaptureView: ScannerQuadrilateral?
  var mostRecentCapturedView: ScannerQuadrilateral? { acceptedViews.last }
  var hasRequiredViews: Bool {
    acceptedExtraCaptures >= Self.requiredExtraCaptures &&
      acceptedViews.count >= Self.maximumCandidates
  }
  private let imageSize: CGSize
  private var startedAt: TimeInterval = 0
  private var tracker: ScannerStabilityTracker

  init(anchor: ScannerQuadrilateral, imageSize: CGSize, minimumArea: CGFloat) {
    acceptedViews = [anchor]
    self.imageSize = imageSize
    tracker = ScannerStabilityTracker(minimumArea: minimumArea)
  }

  mutating func beginWaiting(at time: TimeInterval, candidateCount: Int) -> Bool {
    guard time.isFinite, !isWaiting, pendingCaptureView == nil, !hasRequiredViews,
          extraCaptures < Self.maximumExtraCaptures,
          acceptedExtraCaptures < Self.requiredExtraCaptures,
          acceptedViews.count < Self.maximumCandidates,
          candidateCount < Self.maximumCandidates else { return false }
    startedAt = time
    tracker.reset()
    isWaiting = true
    return true
  }

  mutating func observe(_ view: ScannerQuadrilateral?, at time: TimeInterval,
                       processingDuration: TimeInterval = 0) -> ScannerLightingAngleObservation {
    guard isWaiting else { return .inactive }
    guard time.isFinite, time >= startedAt else {
      tracker.reset()
      return .move
    }
    if time - startedAt >= Self.waitDuration {
      cancel()
      return .expired
    }
    guard let view, view.isComplete(minimumArea: tracker.minimumArea), acceptedViews.allSatisfy({
      Self.isDifferentAngle(view, from: $0, imageSize: imageSize)
    }) else {
      tracker.reset()
      return .move
    }
    let state = tracker.observe(view, at: time, processingDuration: processingDuration)
    guard state.ready else { return .hold(state.progress) }
    pendingCaptureView = view
    extraCaptures += 1
    isWaiting = false
    tracker.reset()
    return .capture
  }

  // Returns true only when an accepted pending still was added to the distinct
  // view set. Rejected, cancelled, duplicate and stale resolutions add nothing.
  @discardableResult
  mutating func resolveCapture(accepted: Bool) -> Bool {
    guard let pendingCaptureView else { return false }
    self.pendingCaptureView = nil
    guard accepted, acceptedExtraCaptures < Self.requiredExtraCaptures,
          acceptedViews.count < Self.maximumCandidates,
          acceptedViews.allSatisfy({
            Self.isDifferentAngle(pendingCaptureView, from: $0, imageSize: imageSize)
          }) else { return false }
    acceptedViews.append(pendingCaptureView)
    acceptedExtraCaptures += 1
    return true
  }

  mutating func cancel() {
    isWaiting = false
    pendingCaptureView = nil
    tracker.reset()
  }

  static func isDifferentAngle(_ view: ScannerQuadrilateral,
                               from anchor: ScannerQuadrilateral,
                               imageSize: CGSize) -> Bool {
    guard imageSize.width > 0, imageSize.height > 0,
          view.area > 0, anchor.area > 0 else { return false }
    func signature(_ quad: ScannerQuadrilateral) -> [CGFloat] {
      let p = quad.points.map { CGPoint(x: $0.x * imageSize.width, y: $0.y * imageSize.height) }
      let top = max(1, p[0].distance(to: p[1]))
      let right = max(1, p[1].distance(to: p[2]))
      let bottom = max(1, p[2].distance(to: p[3]))
      let left = max(1, p[3].distance(to: p[0]))
      return [log(top / bottom), log(left / right), log((top + bottom) / (left + right))]
    }
    let perspectiveChange = zip(signature(view), signature(anchor)).map { abs($0 - $1) }.max() ?? 0
    let movement = view.centroid.distance(to: anchor.centroid)
    // A strong perspective change also qualifies when the page stays centered.
    // Small detector jitter, translation, uniform zoom and in-plane rotation do not.
    return perspectiveChange >= 0.09 || (perspectiveChange >= 0.055 && movement >= 0.025)
  }
}

// Adaptive capture policy for documents whose useful reflection-free views are
// not known in advance. The controller asks the processor whether each still
// adds useful evidence; this policy bounds the capture session. Local fusion
// needs perspective changes; asynchronous ImageGen needs clear source photos
// and must not make a stable, readable page wait for a particular phone tilt.
struct ScannerAdaptiveCaptureGuide {
  static let maximumAttempts = 8
  static let maximumCandidates = 6
  static let minimumFramesForEvaluation = 3
  static let totalCaptureDuration: TimeInterval = 60
  static let waitDuration: TimeInterval = 18

  private(set) var attemptsTaken: Int = 1
  private(set) var acceptedAdditionalViews: Int = 0
  private(set) var isWaiting = false
  private(set) var pendingCaptureView: ScannerQuadrilateral?
  private(set) var acceptedViews: [ScannerQuadrilateral]
  var mostRecentCapturedView: ScannerQuadrilateral? { acceptedViews.last }
  var hasMinimumFramesForEvaluation: Bool {
    acceptedViews.count >= Self.minimumFramesForEvaluation
  }
  var remainingCaptureAttempts: Int {
    max(0, Self.maximumAttempts - attemptsTaken)
  }
  func hasExpired(at time: TimeInterval) -> Bool {
    guard time.isFinite, startedAt.isFinite else { return true }
    return time < startedAt || time - startedAt >= Self.totalCaptureDuration
  }
  func remainingBudget(at time: TimeInterval) -> TimeInterval {
    guard time.isFinite, startedAt.isFinite, time >= startedAt else { return 0 }
    return max(0, Self.totalCaptureDuration - (time - startedAt))
  }

  private let imageSize: CGSize
  private let requiresNovelViews: Bool
  private let requiresPerspectiveChange: Bool
  private var rejectedViews: [ScannerQuadrilateral] = []
  private let minimumArea: CGFloat
  private let startedAt: TimeInterval
  private var waitingStartedAt: TimeInterval?
  private var tracker: ScannerStabilityTracker

  init(anchor: ScannerQuadrilateral, imageSize: CGSize, minimumArea: CGFloat,
       at time: TimeInterval, requiresNovelViews: Bool = false,
       requiresPerspectiveChange: Bool = true) {
    acceptedViews = [anchor]
    self.requiresNovelViews = requiresNovelViews
    self.requiresPerspectiveChange = requiresPerspectiveChange
    self.imageSize = imageSize
    self.minimumArea = minimumArea
    startedAt = time.isFinite ? time : 0
    tracker = ScannerStabilityTracker(minimumArea: minimumArea)
  }

  mutating func beginWaiting(at time: TimeInterval) -> Bool {
    guard time.isFinite, !hasExpired(at: time), !isWaiting,
          pendingCaptureView == nil, attemptsTaken < Self.maximumAttempts else { return false }
    waitingStartedAt = time
    tracker.reset()
    isWaiting = true
    return true
  }

  mutating func observe(_ view: ScannerQuadrilateral?, at time: TimeInterval,
                        processingDuration: TimeInterval = 0) -> ScannerLightingAngleObservation {
    guard isWaiting else { return .inactive }
    guard time.isFinite, processingDuration.isFinite, processingDuration >= 0,
          let waitingStartedAt, time >= waitingStartedAt else {
      tracker.reset()
      return .move
    }
    if hasExpired(at: time) || time - waitingStartedAt >= Self.waitDuration ||
        time + processingDuration >= startedAt + Self.totalCaptureDuration {
      cancel()
      return .expired
    }
    guard let view, view.isComplete(minimumArea: minimumArea),
          let previous = mostRecentCapturedView,
          !requiresPerspectiveChange || Self.isDifferentAngle(view, from: previous, imageSize: imageSize),
          !requiresNovelViews || acceptedViews.allSatisfy({
            Self.isDifferentAngle(view, from: $0, imageSize: imageSize)
          }),
          !requiresNovelViews || rejectedViews.allSatisfy({
            Self.isDifferentAngle(view, from: $0, imageSize: imageSize)
          }) else {
      tracker.reset()
      return .move
    }
    let state = tracker.observe(view, at: time, processingDuration: processingDuration)
    guard state.ready else { return .hold(state.progress) }
    pendingCaptureView = view
    attemptsTaken += 1
    isWaiting = false
    tracker.reset()
    return .capture
  }

  @discardableResult
  mutating func resolveCapture(accepted: Bool) -> Bool {
    guard let pendingCaptureView else { return false }
    self.pendingCaptureView = nil
    guard accepted else {
      if requiresNovelViews { rejectedViews.append(pendingCaptureView) }
      return false
    }
    acceptedViews.append(pendingCaptureView)
    if acceptedViews.count > Self.maximumCandidates { acceptedViews.removeFirst() }
    acceptedAdditionalViews += 1
    return true
  }

  mutating func cancel() {
    isWaiting = false
    pendingCaptureView = nil
    waitingStartedAt = nil
    tracker.reset()
  }

  private static func isDifferentAngle(_ view: ScannerQuadrilateral,
                                       from anchor: ScannerQuadrilateral,
                                       imageSize: CGSize) -> Bool {
    ScannerLightingAngleGuide.isDifferentAngle(view, from: anchor, imageSize: imageSize)
  }
}

// A camera can report a good page boundary while its lens is still moving.
// Keep this policy pure so the timing and cancellation behavior is testable
// without a camera or an AVCaptureSession.
enum ScannerCaptureSettleObservation: Equatable {
  case waiting(CGFloat)
  case ready
  case expired
  case inactive
}

struct ScannerCaptureSettlePolicy {
  static let stableDuration: TimeInterval = 0.25
  static let maximumWait: TimeInterval = 2.0
  static let lensDeltaTolerance: Float = 0.02

  private(set) var startedAt: TimeInterval?
  private var stableSince: TimeInterval?
  private var lastLensPosition: Float?

  mutating func begin(at time: TimeInterval) {
    startedAt = time.isFinite ? time : nil
    stableSince = nil
    lastLensPosition = nil
  }

  mutating func observe(at time: TimeInterval,
                        isAdjustingFocus: Bool,
                        isAdjustingExposure: Bool,
                        lensPosition: Float,
                        documentIsStable: Bool = true) -> ScannerCaptureSettleObservation {
    guard let startedAt, time.isFinite, time >= startedAt else { return .inactive }
    let elapsed = time - startedAt
    if elapsed >= Self.maximumWait {
      return .expired
    }
    guard documentIsStable, !isAdjustingFocus, !isAdjustingExposure,
          lensPosition.isFinite, lensPosition >= 0, lensPosition <= 1 else {
      stableSince = nil
      lastLensPosition = nil
      return .waiting(0)
    }
    if let lastLensPosition,
       abs(lensPosition - lastLensPosition) > Self.lensDeltaTolerance {
      stableSince = nil
      self.lastLensPosition = nil
    }
    // Compare against the start of the hold, not only the previous sample:
    // slow lens drift is still movement.
    if lastLensPosition == nil { lastLensPosition = lensPosition }
    if stableSince == nil { stableSince = time }
    let stableElapsed = max(0, time - (stableSince ?? time))
    guard stableElapsed >= Self.stableDuration else {
      return .waiting(CGFloat(min(1, stableElapsed / Self.stableDuration)))
    }
    return .ready
  }

  mutating func cancel() {
    startedAt = nil
    stableSince = nil
    lastLensPosition = nil
  }
}

// Raw camera bytes are retained only for the explicit asynchronous CRM mode.
// This pool never encodes, resizes, or substitutes photo data.
struct ScannerOriginalPhotoPool {
  static let maximumCount = 6
  static let maximumPhotoBytes = 8 * 1024 * 1024
  static let maximumTotalBytes = 32 * 1024 * 1024
  static let minimumUsefulViews = 2
  private(set) var photos: [Data] = []
  private(set) var totalBytes = 0

  var isFull: Bool { photos.count >= Self.maximumCount || totalBytes >= Self.maximumTotalBytes }
  mutating func append(_ photo: Data) -> Bool {
    guard photos.count < Self.maximumCount, photo.count >= 4,
          photo.count <= Self.maximumPhotoBytes,
          totalBytes <= Self.maximumTotalBytes - photo.count,
          photo.prefix(2) == Data([0xff, 0xd8]),
          photo.suffix(2) == Data([0xff, 0xd9]) else { return false }
    photos.append(photo)
    totalBytes += photo.count
    return true
  }

  func canComplete(usefulViews: Int) -> Bool {
    usefulViews >= Self.minimumUsefulViews && photos.count >= Self.minimumUsefulViews
  }

  mutating func reset() { photos.removeAll(); totalBytes = 0 }
}

// Maps the centered live sensor crop into the full, oriented still image.
enum ScannerLivePhotoCrop {
  static func map(_ quad: ScannerQuadrilateral, liveSize: CGSize,
                  photoSize: CGSize, minimumArea: CGFloat) -> ScannerQuadrilateral? {
    guard quad.isComplete(minimumArea: minimumArea),
          [liveSize.width, liveSize.height, photoSize.width, photoSize.height]
            .allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
    let liveAspect = liveSize.width / liveSize.height
    let photoAspect = photoSize.width / photoSize.height
    let xScale = min(1, liveAspect / photoAspect)
    let yScale = min(1, photoAspect / liveAspect)
    func point(_ p: CGPoint) -> CGPoint {
      // Slight padding protects printed detail at the detected edge.
      CGPoint(x: min(1, max(0, 0.5 + (p.x - 0.5) * xScale * 1.02)),
              y: min(1, max(0, 0.5 + (p.y - 0.5) * yScale * 1.02)))
    }
    return ScannerQuadrilateral(topLeft: point(quad.topLeft), topRight: point(quad.topRight),
      bottomRight: point(quad.bottomRight), bottomLeft: point(quad.bottomLeft))
  }
}
