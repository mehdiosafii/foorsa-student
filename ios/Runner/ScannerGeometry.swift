#if canImport(CoreGraphics)
import CoreGraphics
#endif
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
  private var misses = 0
  private var lastProgress: CGFloat = 0
  let requiredDuration: TimeInterval
  let minimumArea: CGFloat
  let requiredObservations: Int
  // A hand-held page is occasionally missed for one preview frame. Without a
  // tolerance that single miss restarts the hold and delays capture.
  let toleratedMisses: Int

  init(requiredDuration: TimeInterval = 0.72, minimumArea: CGFloat = 0.16,
       requiredObservations: Int = 4, toleratedMisses: Int = 0) {
    self.requiredDuration = requiredDuration
    self.minimumArea = minimumArea
    self.requiredObservations = max(2, requiredObservations)
    self.toleratedMisses = max(0, toleratedMisses)
  }

  mutating func observe(
    _ quadrilateral: ScannerQuadrilateral?,
    at time: TimeInterval,
    processingDuration: TimeInterval = 0
  ) -> ScannerStabilityState {
    guard time.isFinite, processingDuration.isFinite,
          processingDuration >= 0, processingDuration <= Self.maximumObservationAge else {
      reset()
      return ScannerStabilityState(progress: 0, ready: false)
    }
    guard let quadrilateral, quadrilateral.isComplete(minimumArea: minimumArea) else {
      // Keep the hold through a single missing frame, without advancing it.
      if misses < toleratedMisses, anchor != nil, let lastSeen,
         time > lastSeen, time - lastSeen < Self.maximumObservationAge {
        misses += 1
        return ScannerStabilityState(progress: lastProgress, ready: false)
      }
      reset()
      return ScannerStabilityState(progress: 0, ready: false)
    }
    let missedFrames = misses
    misses = 0
    // Account for time spent analyzing the previous frame, while retaining a
    // hard ceiling so a camera interruption cannot count as a continuous hold.
    // A tolerated miss leaves one extra analysis interval between sightings.
    let allowedGap = min(Self.maximumObservationAge,
      max(0.28, lastProcessingDuration * 1.5 + 0.12) * Double(1 + missedFrames))
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
      lastProgress = 0
      return ScannerStabilityState(progress: 0, ready: false)
    }
    // Slowly follow hand drift while preserving a stable reference window.
    self.anchor = anchor.blended(with: quadrilateral, amount: 0.18)
    consecutiveObservations += 1
    let progress = min(1, CGFloat(consecutiveObservations - 1) / CGFloat(requiredObservations - 1),
      max(0, CGFloat((time - stableSince) / requiredDuration)))
    lastProgress = progress
    return ScannerStabilityState(progress: progress, ready: progress >= 1)
  }

  mutating func reset() {
    anchor = nil
    stableSince = nil
    lastSeen = nil
    lastProcessingDuration = 0
    consecutiveObservations = 0
    misses = 0
    lastProgress = 0
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

// MARK: - Live framing (custom-live-v11)
//
// The live preview answers one question per frame: is there a page, and what
// should the student change? These types are pure so the decisions can be
// tested without a camera. Stability over time stays in the tracker.

/// What one preview frame shows, before any hold time is counted.
enum ScannerLiveFraming: String, Equatable {
  case searching
  case ready
  case tooSmall
  case clipped
  case wrongShape
  case blurry
}

/// Coarse light on the corrected page. Only a hint: it never blocks capture
/// for long, because a slightly shadowed page is better than no page.
enum ScannerLiveLighting: String, Equatable {
  case good
  case shadow
  case glare
  case dim
}

extension ScannerQuadrilateral {
  /// A convex outline whose corners make plausible paper angles in image
  /// pixels. Perspective is allowed; bow ties, slivers and spikes are not.
  func isPlausiblePage(in imageSize: CGSize) -> Bool {
    guard imageSize.width > 0, imageSize.height > 0, imageSize.width.isFinite,
          imageSize.height.isFinite else { return false }
    let p = points.map { CGPoint(x: $0.x * imageSize.width, y: $0.y * imageSize.height) }
    guard p.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return false }
    var orientation: CGFloat = 0
    var sides: [CGFloat] = []
    for index in 0..<4 {
      let a = p[index], b = p[(index + 1) % 4], c = p[(index + 2) % 4]
      let cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
      guard abs(cross) > 1e-6 else { return false }
      let sign: CGFloat = cross > 0 ? 1 : -1
      if orientation == 0 { orientation = sign } else if sign != orientation { return false }
      let u = CGPoint(x: a.x - b.x, y: a.y - b.y)
      let v = CGPoint(x: c.x - b.x, y: c.y - b.y)
      let lu = hypot(u.x, u.y), lv = hypot(v.x, v.y)
      guard lu > 1, lv > 1 else { return false }
      let cosine = Double((u.x * v.x + u.y * v.y) / (lu * lv))
      let angle = acos(max(-1, min(1, cosine))) * 180 / Double.pi
      guard angle >= 40, angle <= 140 else { return false }
      sides.append(hypot(b.x - a.x, b.y - a.y))
    }
    guard let shortest = sides.min(), let longest = sides.max(), longest > 0 else { return false }
    return shortest / longest >= 0.15
  }
}

enum ScannerLiveFramingPolicy {
  static let edgeMargin: CGFloat = 0.015

  /// `ready` implies `isComplete(minimumArea: profile.minimumCaptureArea)`
  /// and the profile's shape rule, so the hold tracker sees the same page.
  static func classify(_ quadrilateral: ScannerQuadrilateral?, imageSize: CGSize,
                       profile: FoorsaScannerProfile, isClear: Bool) -> ScannerLiveFraming {
    guard let quadrilateral, quadrilateral.isPlausiblePage(in: imageSize) else { return .searching }
    let inside = quadrilateral.points.allSatisfy {
      $0.x >= edgeMargin && $0.x <= 1 - edgeMargin && $0.y >= edgeMargin && $0.y <= 1 - edgeMargin
    }
    guard inside else { return .clipped }
    guard quadrilateral.area >= profile.minimumCaptureArea else { return .tooSmall }
    guard profile.accepts(aspectRatio: quadrilateral.estimatedAspectRatio(in: imageSize)) else {
      return .wrongShape
    }
    guard isClear else { return .blurry }
    return .ready
  }
}

struct ScannerGuidanceCopy: Equatable {
  let title: String
  let detail: String
  /// Shown instead of `detail` at accessibility text sizes.
  let compact: String
}

/// One short instruction per state: framing first, then light, then the hold.
enum ScannerLiveGuidance {
  static func copy(framing: ScannerLiveFraming, lighting: ScannerLiveLighting,
                   layout: FoorsaScannerProfile.Layout) -> ScannerGuidanceCopy {
    switch framing {
    case .searching:
      switch layout {
      case .passport:
        return .init(title: "Show the photo page",
          detail: "Open the passport and fit the whole photo page in view.", compact: "Photo page in view.")
      case .card:
        return .init(title: "Show the card", detail: "Fit the whole card in view, all four corners.",
          compact: "Whole card in view.")
      case .portrait, .adaptive:
        return .init(title: "Show the whole page", detail: "Fit all four corners in view. Any orientation works.",
          compact: "Whole page in view.")
      }
    case .clipped:
      return .init(title: "Move back a little", detail: "Keep all four corners inside the view.",
        compact: "Show all corners.")
    case .tooSmall:
      return .init(title: "Move closer", detail: "Let the document fill more of the view.",
        compact: "Move closer.")
    case .wrongShape:
      return layout == .passport
        ? .init(title: "Show only the photo page", detail: "Keep the passport open on the page with your photo.",
          compact: "Photo page only.")
        : .init(title: "Fit the whole page", detail: "Show the complete document with all four corners.",
          compact: "Show all corners.")
    case .blurry:
      return .init(title: "Hold still", detail: "Keep the phone steady so the text is sharp.", compact: "Hold still.")
    case .ready:
      switch lighting {
      case .shadow:
        return .init(title: "Shadow on the page", detail: "Move the phone or the light so the page is evenly lit.",
          compact: "Avoid the shadow.")
      case .glare:
        return .init(title: "Glare on the page", detail: "Tilt the phone slightly to move the reflection.",
          compact: "Tilt slightly.")
      case .dim:
        return .init(title: "More light needed", detail: "Turn on a light or use the torch.", compact: "More light.")
      case .good:
        return .init(title: "Hold still", detail: "Capturing automatically.", compact: "Capturing.")
      }
    }
  }
}

/// Keeps the drawn outline calm: small detector jitter is averaged, a real
/// move jumps at once, and one missed frame does not make the outline blink.
struct ScannerOutlineSmoother {
  private(set) var current: ScannerQuadrilateral?
  private var misses = 0
  let holdFrames: Int
  let blendAmount: CGFloat
  let jumpDistance: CGFloat

  init(holdFrames: Int = 2, blendAmount: CGFloat = 0.6, jumpDistance: CGFloat = 0.06) {
    self.holdFrames = max(0, holdFrames)
    self.blendAmount = min(1, max(0.05, blendAmount))
    self.jumpDistance = max(0.001, jumpDistance)
  }

  mutating func update(_ quadrilateral: ScannerQuadrilateral?) -> ScannerQuadrilateral? {
    guard let quadrilateral else {
      misses += 1
      if misses > holdFrames { current = nil }
      return current
    }
    misses = 0
    if let current, current.maximumCornerDistance(to: quadrilateral) < jumpDistance {
      self.current = current.blended(with: quadrilateral, amount: blendAmount)
    } else {
      current = quadrilateral
    }
    return current
  }

  mutating func reset() {
    current = nil
    misses = 0
  }
}

/// Reads a small, perspective-corrected rendering of the page only (RGBA8,
/// row-major). Paper is the brightest material on most pages, so each cell's
/// bright percentile estimates the light falling on the paper there.
enum ScannerPageLightingProbe {
  struct Cell {
    let paper: Double
    let saturated: Double
    let neutral: Bool
  }

  static func cells(rgba: [UInt8], width: Int, height: Int) -> [Cell] {
    guard width >= 24, height >= 24, rgba.count == width * height * 4 else { return [] }
    let columns = width >= height ? 8 : 6
    let rows = width >= height ? 6 : 8
    var result: [Cell] = []
    result.reserveCapacity(columns * rows)
    for row in 0..<rows {
      for column in 0..<columns {
        let x0 = column * width / columns, x1 = (column + 1) * width / columns
        let y0 = row * height / rows, y1 = (row + 1) * height / rows
        var lumas: [Double] = []
        lumas.reserveCapacity((x1 - x0) * (y1 - y0))
        var saturated = 0
        var chroma = 0.0
        for y in y0..<y1 {
          for x in x0..<x1 {
            let i = (y * width + x) * 4
            let r = Double(rgba[i]), g = Double(rgba[i + 1]), b = Double(rgba[i + 2])
            let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
            lumas.append(luma)
            if luma >= 250 { saturated += 1 }
            chroma += max(abs(r - g), abs(g - b), abs(r - b))
          }
        }
        guard !lumas.isEmpty else { continue }
        lumas.sort()
        let paper = lumas[min(lumas.count - 1, Int(Double(lumas.count - 1) * 0.9))]
        result.append(Cell(paper: paper, saturated: Double(saturated) / Double(lumas.count),
          neutral: chroma / Double(lumas.count) <= 28))
      }
    }
    return result
  }

  static func assess(rgba: [UInt8], width: Int, height: Int) -> ScannerLiveLighting {
    let grid = cells(rgba: rgba, width: width, height: height)
    guard grid.count >= 24 else { return .good }
    func percentile(_ values: [Double], _ p: Double) -> Double {
      let sorted = values.sorted()
      return sorted[min(sorted.count - 1, max(0, Int(Double(sorted.count - 1) * p)))]
    }
    // Glare: a few cells blown out while the typical cell is not.
    let blown = grid.filter { $0.saturated >= 0.35 }.count
    let typicalSaturation = percentile(grid.map(\.saturated), 0.5)
    if blown >= 1, blown * 3 <= grid.count, typicalSaturation < 0.05 { return .glare }
    // Shadow: a sizeable, neutral region where the paper itself is much darker
    // than the brightest paper. Small dark artwork (a photo, a header) is too
    // small to count, and colored panels are not neutral.
    let bright = percentile(grid.map(\.paper), 0.9)
    guard bright >= 60 else { return .good }
    let shaded = grid.filter { $0.neutral && $0.paper < bright * 0.62 }.count
    let share = Double(shaded) / Double(grid.count)
    if share >= 0.15 && share <= 0.85 { return .shadow }
    return .good
  }
}

/// Imagegen capture keeps taking clear photos in one hold until enough are
/// useful, instead of asking for a fresh hold before every photo. A photo in
/// flight counts toward the goal so the camera never over-shoots.
/// A page is taken as a short burst: the next photo is shot while the last
/// one is checked. The system shutter would sound on every one of them, so
/// only a page's first photo sounds; the rest are silenced where iOS allows
/// it (iOS 18+, and not in regions that require the sound).
enum ScannerShutterSound {
  /// `photoNumber` counts the photos of the current page, starting at 1.
  static func plays(photoNumber: Int) -> Bool { photoNumber <= 1 }
}

struct ScannerImagegenCapturePolicy {
  static let requiredUsefulViews = ScannerOriginalPhotoPool.minimumUsefulViews
  static let maximumAttempts = ScannerOriginalPhotoPool.maximumCount
  static let totalDuration: TimeInterval = 30

  enum Decision: Equatable {
    case shootNext
    case waitForResults
    case complete
    case giveUp
  }

  let startedAt: TimeInterval
  private(set) var attempts = 0
  private(set) var usefulViews = 0
  private(set) var inFlight = 0

  init(startedAt: TimeInterval) {
    self.startedAt = startedAt.isFinite ? startedAt : 0
  }

  mutating func photoRequested() {
    attempts += 1
    inFlight += 1
  }

  /// `usefulViews` is the processor's retained count, which can drop when a
  /// much sharper later view replaces an earlier soft one.
  mutating func photoResolved(usefulViews: Int) {
    inFlight = max(0, inFlight - 1)
    self.usefulViews = max(0, usefulViews)
  }

  func decision(at time: TimeInterval) -> Decision {
    if usefulViews >= Self.requiredUsefulViews { return .complete }
    if usefulViews + inFlight >= Self.requiredUsefulViews { return .waitForResults }
    let expired = !time.isFinite || time < startedAt || time - startedAt >= Self.totalDuration
    if expired || attempts >= Self.maximumAttempts { return inFlight > 0 ? .waitForResults : .giveUp }
    return .shootNext
  }
}

extension ScannerQuadrilateral {
  /// Loose containment: every corner of `other` lies inside this outline's
  /// bounding box, widened by `margin`.
  func encloses(_ other: ScannerQuadrilateral, margin: CGFloat = 0.01) -> Bool {
    let xs = points.map(\.x), ys = points.map(\.y)
    guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return false }
    return other.points.allSatisfy {
      $0.x >= minX - margin && $0.x <= maxX + margin && $0.y >= minY - margin && $0.y <= maxY + margin
    }
  }

  /// Scales the outline about its centroid, clamped to the image. A small
  /// outward margin keeps printed detail at an approximate model edge.
  func expanded(by fraction: CGFloat) -> ScannerQuadrilateral {
    let center = centroid
    func point(_ p: CGPoint) -> CGPoint {
      CGPoint(x: min(1, max(0, center.x + (p.x - center.x) * (1 + fraction))),
              y: min(1, max(0, center.y + (p.y - center.y) * (1 + fraction))))
    }
    return ScannerQuadrilateral(topLeft: point(topLeft), topRight: point(topRight),
      bottomRight: point(bottomRight), bottomLeft: point(bottomLeft))
  }

  static let fullFrame = ScannerQuadrilateral(topLeft: CGPoint(x: 0, y: 1), topRight: CGPoint(x: 1, y: 1),
    bottomRight: CGPoint(x: 1, y: 0), bottomLeft: CGPoint(x: 0, y: 0))
}

/// A precise rectangle proposal checked against Vision's document model.
/// The model tells a page from clutter, but over a busy background it often
/// throws one or two corners off to the frame's edge or onto a hand; the
/// rectangle detector traces exact edges but cannot tell paper from a cushion.
/// A proposal that shares the model's corners takes the best of both.
enum ScannerOutlineRefinement {
  /// Corners agree within this share of the proposal's own diagonal, which is
  /// tighter than the inset of a printed border inside the page.
  static let cornerTolerance: CGFloat = 0.025
  /// A model corner this close to the frame's edge has run off the page.
  static let edgeMargin: CGFloat = 0.02

  struct Agreement: Equatable {
    let agreeing: Int
    /// Model corners, by index, that matched none of the proposal's corners.
    let strayModelCorners: [Int]
    /// Summed pixel distance of the agreeing corners, for ranking.
    let distance: CGFloat
  }

  /// Corners matched under the best cyclic alignment, so the result does not
  /// depend on which corner each detector called top-left.
  static func agreement(of proposal: ScannerQuadrilateral, with model: ScannerQuadrilateral,
                        imageSize: CGSize) -> Agreement {
    func pixel(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * imageSize.width, y: p.y * imageSize.height) }
    let a = proposal.points.map(pixel), b = model.points.map(pixel)
    let diagonal = max(hypot(a[0].x - a[2].x, a[0].y - a[2].y), hypot(a[1].x - a[3].x, a[1].y - a[3].y))
    let limit = diagonal * cornerTolerance
    var best = Agreement(agreeing: 0, strayModelCorners: [0, 1, 2, 3], distance: .infinity)
    for shift in 0..<4 {
      var agreeing = 0, distance: CGFloat = 0, stray: [Int] = []
      for index in 0..<4 {
        let corner = (index + shift) % 4
        let gap = hypot(a[index].x - b[corner].x, a[index].y - b[corner].y)
        if gap <= limit { agreeing += 1; distance += gap } else { stray.append(corner) }
      }
      if agreeing > best.agreeing || (agreeing == best.agreeing && agreeing > 0 && distance < best.distance) {
        best = Agreement(agreeing: agreeing, strayModelCorners: stray.sorted(), distance: distance)
      }
    }
    return best
  }

  /// Three shared corners place the page. Two are enough only when the
  /// model's other two ran off to the frame's edge: a page inside the frame
  /// whose model corners stay inside it (an open booklet, a two-page spread)
  /// keeps its own outline rather than shrinking to one half.
  static func accepts(_ agreement: Agreement, model: ScannerQuadrilateral) -> Bool {
    if agreement.agreeing >= 3 { return true }
    guard agreement.agreeing == 2 else { return false }
    return agreement.strayModelCorners.allSatisfy { index in
      let p = model.points[index]
      return p.x <= edgeMargin || p.x >= 1 - edgeMargin || p.y <= edgeMargin || p.y >= 1 - edgeMargin
    }
  }

  /// The proposal that sharpens `model`, if one agrees closely enough.
  static func refine(model: ScannerQuadrilateral, proposals: [ScannerQuadrilateral],
                     imageSize: CGSize) -> ScannerQuadrilateral? {
    var best: (proposal: ScannerQuadrilateral, agreement: Agreement)?
    for proposal in proposals where proposal.isPlausiblePage(in: imageSize) {
      let candidate = agreement(of: proposal, with: model, imageSize: imageSize)
      guard accepts(candidate, model: model) else { continue }
      if let current = best?.agreement {
        let more = candidate.agreeing > current.agreeing
        let closer = candidate.agreeing == current.agreeing && candidate.distance < current.distance
        guard more || closer else { continue }
      }
      best = (proposal, candidate)
    }
    return best?.proposal
  }
}
