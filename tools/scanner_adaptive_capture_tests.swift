import CoreGraphics
import Foundation

// Run with:
// xcrun swiftc ios/Runner/ScannerGeometry.swift tools/scanner_adaptive_capture_tests.swift -o /tmp/scanner-adaptive-capture-tests
// /tmp/scanner-adaptive-capture-tests
@main
struct ScannerAdaptiveCaptureTests {
  static func main() {
    let size = CGSize(width: 1200, height: 1600)
    let flat = quad(0.22, 0.78, 0.80, 0.20)
    let left = ScannerQuadrilateral(topLeft: CGPoint(x: 0.25, y: 0.76),
      topRight: CGPoint(x: 0.79, y: 0.85), bottomRight: CGPoint(x: 0.79, y: 0.15),
      bottomLeft: CGPoint(x: 0.25, y: 0.24))
    let right = ScannerQuadrilateral(topLeft: CGPoint(x: 0.19, y: 0.85),
      topRight: CGPoint(x: 0.73, y: 0.76), bottomRight: CGPoint(x: 0.73, y: 0.24),
      bottomLeft: CGPoint(x: 0.19, y: 0.15))

    // The scanner is silent wherever the rules allow it: before iOS 18 the
    // region decides (iOS 18 decides by itself), and not in Japan or Korea.
    precondition(ScannerShutterSound.silenceAllowed(region: "MA"))
    precondition(ScannerShutterSound.silenceAllowed(region: "CN"))
    precondition(ScannerShutterSound.silenceAllowed(region: "TN"))
    precondition(ScannerShutterSound.silenceAllowed(region: nil))
    precondition(ScannerShutterSound.silenceAllowed(region: ""))
    precondition(!ScannerShutterSound.silenceAllowed(region: "JP"))
    precondition(!ScannerShutterSound.silenceAllowed(region: "kr"))

    precondition(ScannerAdaptiveCaptureGuide.maximumAttempts == 8)
    precondition(ScannerAdaptiveCaptureGuide.maximumCandidates == 6)
    precondition(ScannerAdaptiveCaptureGuide.minimumFramesForEvaluation == 3)
    precondition(ScannerAdaptiveCaptureGuide.waitDuration == 18)

    var guide = ScannerAdaptiveCaptureGuide(anchor: flat, imageSize: size,
      minimumArea: 0.16, at: 0)
    precondition(guide.attemptsTaken == 1 && guide.acceptedAdditionalViews == 0)
    precondition(!guide.hasMinimumFramesForEvaluation)
    precondition(guide.remainingCaptureAttempts == 7)
    precondition(guide.beginWaiting(at: 1))
    precondition(!guide.beginWaiting(at: 1.1))

    // Lost, stale and same-angle observations never spend an attempt.
    precondition(guide.observe(nil, at: 1.2) == .move)
    precondition(guide.observe(flat, at: 1.4) == .move)
    precondition(guide.observe(left, at: 1.6) == .hold(0))
    precondition(guide.observe(left, at: 1.8) != .capture)
    precondition(guide.observe(left, at: 2.0) != .capture)
    precondition(guide.observe(left, at: 2.2) != .capture)
    precondition(guide.observe(left, at: 2.4) == .capture)
    precondition(guide.attemptsTaken == 2)
    precondition(guide.pendingCaptureView == left)
    precondition(guide.resolveCapture(accepted: false) == false)
    precondition(guide.attemptsTaken == 2 && guide.acceptedAdditionalViews == 0)

    // A later angle is accepted, and a return to a prior angle is allowed
    // because diversity is measured against only the most recent accepted view.
    precondition(guide.beginWaiting(at: 3))
    precondition(capture(&guide, view: right, start: 3.1) == .capture)
    precondition(guide.resolveCapture(accepted: true))
    precondition(guide.acceptedAdditionalViews == 1)
    precondition(guide.beginWaiting(at: 5))
    precondition(capture(&guide, view: left, start: 5.1) == .capture)
    precondition(guide.resolveCapture(accepted: true))
    precondition(guide.acceptedViews == [flat, right, left])
    precondition(guide.hasMinimumFramesForEvaluation)

    // The processor can keep the session open for more useful views; there
    // is no fixed left/right/straight requirement.
    let fourth = transform(flat) { CGPoint(x: $0.x + 0.03, y: $0.y) }
    precondition(guide.beginWaiting(at: 7))
    precondition(capture(&guide, view: fourth, start: 7.1) == .capture)
    precondition(guide.resolveCapture(accepted: true))
    precondition(guide.acceptedAdditionalViews == 3)
    precondition(guide.acceptedViews.count == 4)

    // Processing that would finish beyond the 60-second budget expires while
    // the guide is waiting, and does not emit a capture.
    var processingTimeout = ScannerAdaptiveCaptureGuide(anchor: flat, imageSize: size,
      minimumArea: 0.16, at: 100)
    precondition(processingTimeout.beginWaiting(at: 101))
    precondition(processingTimeout.observe(left, at: 101.2,
      processingDuration: 59) == .expired)
    precondition(processingTimeout.hasExpired(at: 160))
    precondition(!processingTimeout.beginWaiting(at: 160))

    // A wait deadline is bounded even if the page never reaches a new angle.
    var waitTimeout = ScannerAdaptiveCaptureGuide(anchor: flat, imageSize: size,
      minimumArea: 0.16, at: 200)
    precondition(waitTimeout.beginWaiting(at: 201))
    precondition(waitTimeout.observe(left, at: 219) == .expired)
    precondition(waitTimeout.observe(left, at: 219.1) == .inactive)

    // Failed processing never advances the accepted anchor; cancellation also
    // makes delayed results harmless.
    var cancelled = ScannerAdaptiveCaptureGuide(anchor: flat, imageSize: size,
      minimumArea: 0.16, at: 240)
    precondition(cancelled.beginWaiting(at: 241))
    precondition(capture(&cancelled, view: right, start: 241.1) == .capture)
    cancelled.cancel()
    precondition(!cancelled.resolveCapture(accepted: true))
    precondition(cancelled.mostRecentCapturedView == flat)

    // Rejected captures still consume the bounded attempt budget, preventing
    // an infinite retry loop when the processor never finds useful evidence.
    var capped = ScannerAdaptiveCaptureGuide(anchor: flat, imageSize: size,
      minimumArea: 0.16, at: 300)
    for index in 0..<ScannerAdaptiveCaptureGuide.maximumAttempts - 1 {
      let start = 301 + Double(index) * 2
      precondition(capped.beginWaiting(at: start))
      precondition(capture(&capped, view: left, start: start + 0.1) == .capture)
      precondition(!capped.resolveCapture(accepted: false))
    }
    precondition(capped.attemptsTaken == ScannerAdaptiveCaptureGuide.maximumAttempts)
    precondition(!capped.beginWaiting(at: 320))

    // Useful views can replace earlier candidates all the way to the photo
    // budget; retained geometry is bounded independently from attempts.
    var replacing = ScannerAdaptiveCaptureGuide(anchor: flat, imageSize: size,
      minimumArea: 0.16, at: 400)
    for index in 0..<ScannerAdaptiveCaptureGuide.maximumAttempts - 1 {
      let start = 401 + Double(index) * 2
      precondition(replacing.beginWaiting(at: start))
      precondition(capture(&replacing, view: index.isMultiple(of: 2) ? left : right,
        start: start + 0.1) == .capture)
      precondition(replacing.resolveCapture(accepted: true))
    }
    precondition(replacing.attemptsTaken == 8 && replacing.acceptedAdditionalViews == 7)
    precondition(replacing.acceptedViews.count == 6)
    precondition(!replacing.beginWaiting(at: 420))
    precondition(replacing.hasExpired(at: 399) && replacing.remainingBudget(at: 399) == 0)

    print("PASS: adaptive capture accepts processor-selected views, allows later-angle returns, ignores stale/missing observations, bounds wait and total processing time, preserves failed/cancelled anchors, and caps retries")
  }

  static func capture(_ guide: inout ScannerAdaptiveCaptureGuide,
                      view: ScannerQuadrilateral, start: TimeInterval) -> ScannerLightingAngleObservation {
    var result: ScannerLightingAngleObservation = .inactive
    for index in 0...5 {
      result = guide.observe(view, at: start + Double(index) * 0.2)
      if result == .capture || result == .expired { return result }
    }
    return result
  }

  static func quad(_ left: CGFloat, _ right: CGFloat, _ top: CGFloat,
                   _ bottom: CGFloat) -> ScannerQuadrilateral {
    ScannerQuadrilateral(topLeft: CGPoint(x: left, y: top),
      topRight: CGPoint(x: right, y: top), bottomRight: CGPoint(x: right, y: bottom),
      bottomLeft: CGPoint(x: left, y: bottom))
  }

  static func transform(_ quad: ScannerQuadrilateral,
                        _ apply: (CGPoint) -> CGPoint) -> ScannerQuadrilateral {
    ScannerQuadrilateral(topLeft: apply(quad.topLeft), topRight: apply(quad.topRight),
      bottomRight: apply(quad.bottomRight), bottomLeft: apply(quad.bottomLeft))
  }
}
