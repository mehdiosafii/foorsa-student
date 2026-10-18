import CoreGraphics
import Foundation

// Run with:
// xcrun swiftc ios/Runner/ScannerGeometry.swift tools/scanner_lighting_capture_tests.swift -o /tmp/scanner-lighting-capture-tests
// /tmp/scanner-lighting-capture-tests
@main
struct ScannerLightingCaptureTests {
  static func main() {
    let size = CGSize(width: 1200, height: 1600)
    let flat = quad(0.22, 0.78, 0.8, 0.2)
    let left = ScannerQuadrilateral(topLeft: CGPoint(x: 0.25, y: 0.76),
      topRight: CGPoint(x: 0.79, y: 0.85), bottomRight: CGPoint(x: 0.79, y: 0.15),
      bottomLeft: CGPoint(x: 0.25, y: 0.24))
    let right = ScannerQuadrilateral(topLeft: CGPoint(x: 0.19, y: 0.85),
      topRight: CGPoint(x: 0.73, y: 0.76), bottomRight: CGPoint(x: 0.73, y: 0.24),
      bottomLeft: CGPoint(x: 0.19, y: 0.15))

    precondition(ScannerLightingAngleGuide.maximumExtraCaptures == 4)
    precondition(ScannerLightingAngleGuide.maximumCandidates == 3)
    precondition(ScannerLightingAngleGuide.requiredExtraCaptures == 2)
    precondition(ScannerLightingAngleGuide.waitDuration == 18)

    var settle = ScannerCaptureSettlePolicy()
    settle.begin(at: 10)
    precondition(settle.observe(at: 10.1, isAdjustingFocus: true,
                                isAdjustingExposure: false, lensPosition: 0.5) == .waiting(0),
                 "A moving lens cannot trigger a still")
    precondition(settle.observe(at: 10.2, isAdjustingFocus: false,
                                isAdjustingExposure: false, lensPosition: 0.5) == .waiting(0),
                 "The settle hold must run before capture")
    let settleProgress = settle.observe(at: 10.5, isAdjustingFocus: false,
                                        isAdjustingExposure: false, lensPosition: 0.5)
    precondition(settleProgress == .ready, "A stable focus and exposure should permit capture")
    precondition(settle.observe(at: 10.5, isAdjustingFocus: false,
                                isAdjustingExposure: true, lensPosition: 0.5) == .waiting(0),
                 "Exposure movement must revoke the stable hold")
    var movingLens = ScannerCaptureSettlePolicy()
    movingLens.begin(at: 20)
    _ = movingLens.observe(at: 20.1, isAdjustingFocus: false,
                           isAdjustingExposure: false, lensPosition: 0.2)
    precondition(movingLens.observe(at: 20.2, isAdjustingFocus: false,
                                    isAdjustingExposure: false, lensPosition: 0.25) == .waiting(0),
                 "A moving lens must restart the hold")
    precondition(movingLens.observe(at: 22, isAdjustingFocus: false,
                                    isAdjustingExposure: false, lensPosition: 0.25) == .expired,
                 "Settling has a bounded timeout")
    movingLens.cancel()
    precondition(movingLens.observe(at: 22.1, isAdjustingFocus: false,
                                    isAdjustingExposure: false, lensPosition: 0.25) == .inactive,
                 "A cancelled settle callback must be ignored")
    var stalePage = ScannerCaptureSettlePolicy()
    stalePage.begin(at: 30)
    _ = stalePage.observe(at: 30.1, isAdjustingFocus: false,
                         isAdjustingExposure: false, lensPosition: 0.5)
    precondition(stalePage.observe(at: 30.4, isAdjustingFocus: false,
                                  isAdjustingExposure: false, lensPosition: 0.5,
                                  documentIsStable: false) == .waiting(0),
                 "A lost, moved or stale page must revoke the settled capture")
    precondition(stalePage.observe(at: 30.5, isAdjustingFocus: false,
                                  isAdjustingExposure: false, lensPosition: 0.5) == .waiting(0),
                 "A fresh page must establish a new settling hold")
    var driftingLens = ScannerCaptureSettlePolicy()
    driftingLens.begin(at: 40)
    for index in 0...6 {
      precondition(driftingLens.observe(at: 40 + Double(index) * 0.05,
        isAdjustingFocus: false, isAdjustingExposure: false,
        lensPosition: 0.3 + Float(index) * 0.015) != .ready,
        "Small lens movements must not accumulate into a false stable hold")
    }

    func different(_ view: ScannerQuadrilateral, from anchor: ScannerQuadrilateral = flat) -> Bool {
      ScannerLightingAngleGuide.isDifferentAngle(view, from: anchor, imageSize: size)
    }
    precondition(!different(flat), "Identical view must not qualify")
    precondition(!different(transform(flat) { CGPoint(x: $0.x + 0.08, y: $0.y - 0.05) }),
                 "Translation is not a new angle")
    precondition(!different(transform(flat) {
      CGPoint(x: 0.5 + ($0.x - 0.5) * 0.9, y: 0.5 + ($0.y - 0.5) * 0.9)
    }), "Uniform zoom is not a new angle")
    let rotation: CGFloat = 0.12
    let rotated = transform(flat) {
      let x = ($0.x - 0.5) * size.width, y = ($0.y - 0.5) * size.height
      return CGPoint(x: 0.5 + (x * cos(rotation) - y * sin(rotation)) / size.width,
                     y: 0.5 + (x * sin(rotation) + y * cos(rotation)) / size.height)
    }
    precondition(!different(rotated), "In-plane rotation must not qualify")
    precondition(!different(quad(0.221, 0.779, 0.801, 0.199)),
                 "Detector jitter must not qualify")
    precondition(different(left) && different(right), "Perspective views should qualify")
    precondition(different(right, from: left),
                 "The third view must differ from the first guided view too")

    var guide = ScannerLightingAngleGuide(anchor: flat, imageSize: size, minimumArea: 0.16)
    precondition(guide.acceptedViews == [flat] && guide.mostRecentCapturedView == flat,
                 "The initial accepted photo is the anchor")
    precondition(!guide.hasRequiredViews && guide.acceptedExtraCaptures == 0)
    precondition(guide.beginWaiting(at: 10, candidateCount: 1))
    precondition(!guide.beginWaiting(at: 10, candidateCount: 1),
                 "Cannot restart the deadline while waiting")
    precondition(guide.observe(left, at: 9.9) == .move,
                 "Stale observations must reset the hold")
    for index in 0...3 {
      precondition(guide.observe(flat, at: 10 + Double(index) * 0.12) == .move)
    }
    let clipped = transform(left) { CGPoint(x: $0.x + 0.25, y: $0.y) }
    precondition(guide.observe(clipped, at: 10.6) == .move,
                 "An incomplete page cannot start angle stability")
    precondition(guide.observe(left, at: 11) == .hold(0))
    _ = guide.observe(left, at: 11.2)
    precondition(guide.observe(nil, at: 11.4) == .move,
                 "A lost page must revoke stability")
    precondition(capture(&guide, view: left, startingAt: 11.6) == .capture)
    precondition(guide.extraCaptures == 1 && guide.acceptedExtraCaptures == 0)
    precondition(guide.pendingCaptureView == left && guide.acceptedViews == [flat],
                 "Emitting capture records an attempt, not an accepted view")
    precondition(guide.mostRecentCapturedView == flat,
                 "Retry anchors come only from accepted views")
    precondition(!guide.beginWaiting(at: 13, candidateCount: 1),
                 "A pending still must be resolved before another attempt")
    precondition(!guide.resolveCapture(accepted: false),
                 "Rejected processing must not add a view")
    precondition(guide.pendingCaptureView == nil && guide.acceptedExtraCaptures == 0)
    precondition(!guide.resolveCapture(accepted: true),
                 "A delayed resolution without a pending still must be ignored")

    precondition(guide.beginWaiting(at: 13, candidateCount: 1),
                 "A failed guided view can be retried")
    precondition(capture(&guide, view: left, startingAt: 13.1) == .capture)
    precondition(guide.resolveCapture(accepted: true))
    precondition(guide.extraCaptures == 2 && guide.acceptedExtraCaptures == 1)
    precondition(guide.acceptedViews == [flat, left] && guide.mostRecentCapturedView == left)
    precondition(!guide.hasRequiredViews, "One guided acceptance is insufficient")

    precondition(guide.beginWaiting(at: 15, candidateCount: 2))
    precondition(guide.observe(left, at: 15) == .move,
                 "An accepted guided view cannot be reused")
    precondition(guide.observe(flat, at: 15.2) == .move,
                 "The initial view cannot be reused")
    precondition(guide.observe(right, at: 15.4) == .hold(0),
                 "A distinct third view still requires a stable hold")
    precondition(capture(&guide, view: right, startingAt: 15.6) == .capture)
    precondition(!guide.hasRequiredViews, "A pending third photo is not accepted yet")
    precondition(guide.resolveCapture(accepted: true))
    precondition(guide.acceptedExtraCaptures == 2 && guide.acceptedViews == [flat, left, right])
    precondition(guide.hasRequiredViews, "Three accepted distinct views are required")
    precondition(!guide.beginWaiting(at: 17, candidateCount: 2),
                 "A completed guide cannot capture more views")

    var capped = ScannerLightingAngleGuide(anchor: flat, imageSize: size, minimumArea: 0.16)
    precondition(!capped.beginWaiting(at: 0, candidateCount: 3),
                 "Three accepted candidates is a hard limit")
    for attempt in 0..<ScannerLightingAngleGuide.maximumExtraCaptures {
      let start = 1 + Double(attempt) * 2
      precondition(capped.beginWaiting(at: start, candidateCount: 1))
      precondition(capture(&capped, view: left, startingAt: start + 0.1) == .capture)
      precondition(!capped.resolveCapture(accepted: false))
    }
    precondition(capped.extraCaptures == 4 && capped.acceptedExtraCaptures == 0)
    precondition(!capped.beginWaiting(at: 10, candidateCount: 1),
                 "Four attempts prevent an infinite retry loop")

    var timeout = ScannerLightingAngleGuide(anchor: flat, imageSize: size, minimumArea: 0.16)
    precondition(timeout.beginWaiting(at: 1, candidateCount: 1))
    precondition(timeout.observe(left, at: 19) == .expired,
                 "The live instruction wait has a bounded deadline")
    precondition(timeout.observe(left, at: 19.2) == .inactive)

    var cancelled = ScannerLightingAngleGuide(anchor: flat, imageSize: size, minimumArea: 0.16)
    precondition(cancelled.beginWaiting(at: 1, candidateCount: 1))
    precondition(capture(&cancelled, view: left, startingAt: 1.1) == .capture)
    precondition(cancelled.pendingCaptureView != nil)
    cancelled.cancel()
    precondition(cancelled.pendingCaptureView == nil)
    precondition(!cancelled.resolveCapture(accepted: true),
                 "A delayed result after cancellation must not accept a view")
    precondition(cancelled.observe(left, at: 2.1) == .inactive)

    var slow = ScannerLightingAngleGuide(anchor: flat, imageSize: size, minimumArea: 0.16)
    precondition(slow.beginWaiting(at: 1, candidateCount: 1))
    for index in 0...5 {
      precondition(slow.observe(left, at: 1 + Double(index) * 0.2,
                                processingDuration: 0.8) != .capture,
                   "Over-age detections cannot capture")
    }
    var gap = ScannerLightingAngleGuide(anchor: flat, imageSize: size, minimumArea: 0.16)
    precondition(gap.beginWaiting(at: 1, candidateCount: 1))
    _ = gap.observe(left, at: 1)
    _ = gap.observe(left, at: 1.2)
    precondition(gap.observe(left, at: 2) == .hold(0),
                 "An interrupted observation stream must restart the hold")

    print("PASS: capture settling focus/exposure/lens guards, bounded timeout/cancellation, mandatory three-view acceptance, failed-view retry, four-attempt bound, all-view angle diversity, stable holds, stale/nil/delayed guards, timeout, cancellation, slow frames, and translation/zoom/rotation/jitter rejection")
  }

  static func capture(_ guide: inout ScannerLightingAngleGuide,
                      view: ScannerQuadrilateral,
                      startingAt start: TimeInterval) -> ScannerLightingAngleObservation {
    var observation: ScannerLightingAngleObservation = .inactive
    for index in 0...4 {
      observation = guide.observe(view, at: start + Double(index) * 0.2)
      if observation == .capture || observation == .expired { return observation }
    }
    return observation
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
