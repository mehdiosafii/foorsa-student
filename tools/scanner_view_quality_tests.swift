import Foundation
import CoreImage

@main
struct ScannerViewQualityTests {
  static var passed = 0

  static func expect(_ condition: Bool, _ name: String) {
    guard condition else {
      print("FAIL: \(name)")
      exit(1)
    }
    passed += 1
    print("PASS: \(name)")
  }

  static func candidate(_ sharpness: Double, _ id: UInt8 = 1) -> ScannerProcessedCandidate {
    // correctedImage is deliberately nil: this policy only decides whether a
    // processed view's measured quality belongs in the burst.
    ScannerProcessedCandidate(
      jpeg: Data([id]),
      sharpness: sharpness,
      coverage: 0.9,
      fingerprint: ScannerImageFingerprint(bits: UInt64(id))
    )
  }

  static func main() {
    let policy = ScannerImageProcessor.self
    let result = ScannerImageProcessor.ViewQualityAssessment.self

    expect(policy.assessViewQuality(accepted: [], candidate: candidate(9.077)) == .accepted,
      "first finite view is accepted")
    expect(policy.assessViewQuality(accepted: [candidate(9.326)], candidate: candidate(8.646))
      == .retakeCurrentView,
      "retry view below the shared log(1.8) margin is retaken")
    let boundary = 9.264 - policy.relativeSharpnessDrop
    expect(policy.assessViewQuality(accepted: [candidate(9.264)], candidate: candidate(boundary))
      == .accepted,
      "exact relative sharpness boundary is accepted")
    expect(policy.assessViewQuality(accepted: [candidate(8.646), candidate(9.212)],
      candidate: candidate(9.114)) == .accepted,
      "three close-focus retry values remain accepted when all fit the margin")
    expect(policy.assessViewQuality(accepted: [candidate(8.0)], candidate: candidate(9.212))
      == .restartForEarlierSoftView,
      "a much sharper later view asks to restart an earlier soft view")
    expect(policy.assessViewQuality(accepted: [candidate(9.0)], candidate: nil) == .invalidImage,
      "missing candidate is invalid")
    expect(policy.assessViewQuality(accepted: [candidate(9.0)], candidate: candidate(.nan))
      == .invalidImage,
      "non-finite candidate sharpness is invalid")
    expect(policy.assessViewQuality(accepted: [candidate(.infinity)], candidate: candidate(9.0))
      == .invalidImage,
      "non-finite accepted sharpness is invalid")
    expect(policy.assessViewQuality(accepted: [candidate(8.6), candidate(9.0), candidate(8.8)],
      candidate: candidate(8.7)) == .accepted,
      "candidate count does not impose an absolute quality floor")
    let retained = policy.retainingUsefulViews([
      candidate(8.0, 1), candidate(9.212, 2), candidate(9.114, 3), candidate(9.264, 4)
    ])
    expect(retained.count == 3 && retained.map(\.jpeg) == [Data([2]), Data([3]), Data([4])],
      "adaptive pool drops one clearly soft early view")
    expect(policy.retainingUsefulViews([candidate(8.0, 1), candidate(9.212, 2)]).map(\.jpeg) == [Data([2])],
      "a known soft first view is dropped before reaching three photos")
    expect(policy.retainingUsefulViews([candidate(9, 1), candidate(9, 2), candidate(9, 3)], maximumCount: 1).count == 1,
      "retention respects a smaller explicit memory limit")
    let uniformlySoft = policy.retainingUsefulViews([
      candidate(8.0, 1), candidate(8.1, 2), candidate(8.05, 3), candidate(8.02, 4)
    ])
    expect(uniformlySoft.count == 4,
      "uniformly soft pool is not rejected by an invented absolute floor")
    expect(ScannerImageProcessor().resolveAdaptiveCapture(retained, isCancelled: { true }) == nil,
      "adaptive resolver observes cancellation before trying a subset")

    let processor = ScannerImageProcessor()
    let profile = FoorsaScannerProfile(arguments: ["profile": ["documentKey": "identity"]])
    if case .failure(.invalidPhoto) = processor.processCapture(photoData: Data([1, 2, 3]), profile: profile) {
      expect(true, "invalid photo is distinguished from a lighting failure")
    } else { expect(false, "invalid photo is distinguished from a lighting failure") }
    let blank = CIImage(color: CIColor(red: 1, green: 1, blue: 1))
      .cropped(to: CGRect(x: 0, y: 0, width: 600, height: 400))
    let blankData = CIContext().jpegRepresentation(of: blank,
      colorSpace: CGColorSpaceCreateDeviceRGB(), options: [:])!
    if case .failure(.documentBoundaryNotFound) = processor.processCapture(photoData: blankData, profile: profile) {
      expect(true, "blank capture reports missing boundary and produces no scan")
    } else { expect(false, "blank capture reports missing boundary and produces no scan") }

    print("\(passed) scanner view-quality tests passed")
    _ = result // Keep the enum's intended public-in-module surface explicit.
  }
}
