import Flutter
import UIKit
import Vision
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {
  func testStillCaptureDoesNotReplaceWrongShapeWithInnerRectangle() {
    let outer = VNRectangleObservation(boundingBox: CGRect(x: 0.05, y: 0.35, width: 0.90, height: 0.30))
    let inner = VNRectangleObservation(boundingBox: CGRect(x: 0.25, y: 0.35, width: 0.48, height: 0.30))
    let passport = FoorsaScannerProfile(arguments: ["profile": ["documentKey": "identity"]])
    let receipt = FoorsaScannerProfile(arguments: ["profile": ["documentKey": "receipts"]])
    let size = CGSize(width: 1200, height: 1200)
    XCTAssertNil(ScannerRectangleDetector.select([inner, outer], imageSize: size, profile: passport, purpose: .still))
    XCTAssertEqual(ScannerRectangleDetector.select([inner, outer], imageSize: size, profile: receipt, purpose: .still)?.boundingBox, outer.boundingBox)
    let clipped = VNRectangleObservation(boundingBox: CGRect(x: 0.05, y: 0.2, width: 0.90, height: 0.81))
    XCTAssertNil(ScannerRectangleDetector.select([inner, clipped], imageSize: size, profile: passport, purpose: .still))
  }

  private let page = ScannerQuadrilateral(
    topLeft: CGPoint(x: 0.1, y: 0.9),
    topRight: CGPoint(x: 0.9, y: 0.9),
    bottomRight: CGPoint(x: 0.9, y: 0.1),
    bottomLeft: CGPoint(x: 0.1, y: 0.1)
  )

  func testQuadrilateralMeasuresActualCorners() {
    XCTAssertEqual(page.area, 0.64, accuracy: 0.001)
    XCTAssertEqual(
      page.estimatedAspectRatio(in: CGSize(width: 1200, height: 1200)),
      1,
      accuracy: 0.001
    )
    XCTAssertTrue(page.isComplete())
    let clipped = ScannerQuadrilateral(
      topLeft: CGPoint(x: -0.02, y: 0.9),
      topRight: CGPoint(x: 0.9, y: 0.9),
      bottomRight: CGPoint(x: 0.9, y: 0.1),
      bottomLeft: CGPoint(x: -0.02, y: 0.1)
    )
    XCTAssertFalse(clipped.isComplete())
  }

  func testAspectRatioUsesOrientedImagePixelsForProfileValidation() {
    let normalizedSquare = ScannerQuadrilateral(
      topLeft: CGPoint(x: 0.2, y: 0.8),
      topRight: CGPoint(x: 0.8, y: 0.8),
      bottomRight: CGPoint(x: 0.8, y: 0.2),
      bottomLeft: CGPoint(x: 0.2, y: 0.2)
    )
    let portraitPixels = normalizedSquare.estimatedAspectRatio(
      in: CGSize(width: 1080, height: 1920)
    )
    let landscapePixels = normalizedSquare.estimatedAspectRatio(
      in: CGSize(width: 1920, height: 1080)
    )
    XCTAssertEqual(portraitPixels, 0.5625, accuracy: 0.001)
    XCTAssertEqual(landscapePixels, 16.0 / 9.0, accuracy: 0.001)

    let portrait = FoorsaScannerProfile(arguments: ["profile": ["layout": "portrait"]])
    let card = FoorsaScannerProfile(arguments: ["profile": ["layout": "card"]])
    XCTAssertTrue(portrait.accepts(aspectRatio: portraitPixels))
    XCTAssertTrue(card.accepts(aspectRatio: portraitPixels))
    XCTAssertTrue(card.accepts(aspectRatio: landscapePixels))
    XCTAssertFalse(card.accepts(aspectRatio: 1.0))
  }

  func testAspectFillMappingMatchesPortraitAndLandscapePreviewCropping() {
    let portraitBounds = CGRect(x: 0, y: 0, width: 390, height: 844)
    let portraitRect = ScannerAspectFillMapper.videoRect(
      imageSize: CGSize(width: 1080, height: 1920),
      in: portraitBounds
    )
    XCTAssertEqual(portraitRect.minY, 0, accuracy: 0.001)
    XCTAssertLessThan(portraitRect.minX, 0)
    XCTAssertEqual(
      ScannerAspectFillMapper.layerPoint(
        fromVisionPoint: CGPoint(x: 0.5, y: 0.5),
        imageSize: CGSize(width: 1080, height: 1920),
        in: portraitBounds
      ),
      CGPoint(x: portraitBounds.midX, y: portraitBounds.midY)
    )

    let landscapeBounds = CGRect(x: 0, y: 0, width: 844, height: 390)
    let landscapeRect = ScannerAspectFillMapper.videoRect(
      imageSize: CGSize(width: 1920, height: 1080),
      in: landscapeBounds
    )
    XCTAssertEqual(landscapeRect.minX, 0, accuracy: 0.001)
    XCTAssertLessThan(landscapeRect.minY, 0)
    let topLeft = ScannerAspectFillMapper.layerPoint(
      fromVisionPoint: CGPoint(x: 0, y: 1),
      imageSize: CGSize(width: 1920, height: 1080),
      in: landscapeBounds
    )
    XCTAssertEqual(topLeft.x, landscapeRect.minX, accuracy: 0.001)
    XCTAssertEqual(topLeft.y, landscapeRect.minY, accuracy: 0.001)
  }

  func testPassportAcceptsDataPageAndOpenSpread() {
    let passport = FoorsaScannerProfile(arguments: ["profile": [
      "documentKey": "identity", "layout": "adaptive"
    ]])
    XCTAssertEqual(passport.layout, .passport)
    XCTAssertTrue(passport.accepts(aspectRatio: 125.0 / 88.0))
    XCTAssertTrue(passport.accepts(aspectRatio: 125.0 / 176.0))
    XCTAssertTrue(passport.accepts(aspectRatio: 1275.0 / 1600.0))
    XCTAssertTrue(passport.accepts(aspectRatio: 88.0 / 125.0))
    XCTAssertTrue(passport.accepts(aspectRatio: 176.0 / 125.0))
    XCTAssertFalse(passport.accepts(aspectRatio: 0.35))
    XCTAssertFalse(passport.accepts(aspectRatio: 2.5))
  }

  func testKnownDocumentKeysControlShapeAndUnknownKeysStayGeneric() {
    let card = FoorsaScannerProfile(arguments: ["profile": [
      "documentKey": " PARENT_ID ", "layout": "passport"
    ]])
    XCTAssertEqual(card.documentKey, "parent_id")
    XCTAssertEqual(card.layout, .card)
    XCTAssertTrue(card.accepts(aspectRatio: 1 / 1.585))
    XCTAssertFalse(card.accepts(aspectRatio: 0.35))

    let letter = FoorsaScannerProfile(arguments: ["profile": [
      "documentKey": "recommendation_letter", "layout": "card"
    ]])
    XCTAssertEqual(letter.layout, .portrait)
    XCTAssertTrue(letter.accepts(aspectRatio: 1.41))
    XCTAssertTrue(letter.accepts(aspectRatio: 1 / 1.41))

    let receipt = FoorsaScannerProfile(arguments: ["profile": [
      "documentKey": "receipts", "layout": "passport"
    ]])
    XCTAssertTrue(receipt.accepts(aspectRatio: 3.0))
    XCTAssertTrue(receipt.accepts(aspectRatio: 1 / 3.0))
    XCTAssertFalse(receipt.accepts(aspectRatio: 3.5))
    XCTAssertFalse(card.accepts(aspectRatio: 3.0))

    let unknown = FoorsaScannerProfile(arguments: ["profile": [
      "documentKey": "invented_passport", "layout": "passport"
    ]])
    XCTAssertEqual(unknown.documentKey, "drive_files")
    XCTAssertEqual(unknown.layout, .adaptive)
    XCTAssertFalse(unknown.accepts(aspectRatio: 3.0))
    for invalid in [CGFloat.zero, -.infinity, .infinity, .nan] {
      XCTAssertFalse(receipt.accepts(aspectRatio: invalid))
    }
  }

  func testStabilityRequiresContinuousHoldAndResetsForMovement() {
    var tracker = ScannerStabilityTracker(requiredDuration: 0.7)
    XCTAssertFalse(tracker.observe(page, at: 0).ready)
    for time in [0.12, 0.24, 0.36, 0.48, 0.60] {
      XCTAssertFalse(tracker.observe(page, at: time).ready)
    }
    XCTAssertTrue(tracker.observe(page, at: 0.72).ready)
    XCTAssertFalse(tracker.observe(page, at: 1.10).ready) // Dropped frames reset the hold.

    let moved = ScannerQuadrilateral(
      topLeft: CGPoint(x: 0.2, y: 0.9),
      topRight: CGPoint(x: 0.98, y: 0.9),
      bottomRight: CGPoint(x: 0.98, y: 0.1),
      bottomLeft: CGPoint(x: 0.2, y: 0.1)
    )
    XCTAssertEqual(tracker.observe(moved, at: 0.8).progress, 0)
  }

  func testCandidateSelectionPrefersSharperCompleteFrame() {
    let soft = ScannerProcessedCandidate(
      jpeg: Data([1]), sharpness: 8.8, coverage: 0.92,
      fingerprint: ScannerImageFingerprint(bits: 0)
    )
    let sharp = ScannerProcessedCandidate(
      jpeg: Data([2]), sharpness: 9, coverage: 0.4,
      fingerprint: ScannerImageFingerprint(bits: 1)
    )
    XCTAssertEqual(ScannerCandidateSelector.best([soft, sharp])?.jpeg, Data([2]))
    XCTAssertEqual(soft.fingerprint.distance(to: sharp.fingerprint), 1)
  }

  func testDuplicateGuardNeverBlocksManualCapture() {
    let prior = ScannerImageFingerprint(words: [0, 0, 0, 0])
    let same = ScannerImageFingerprint(words: [0, 0, 0, 0])
    let differentTranscriptPage = ScannerImageFingerprint(words: [0, 0, 0, 0b111])

    XCTAssertTrue(ScannerDuplicatePolicy.shouldReject(
      candidate: same, previous: prior, automatic: true
    ))
    XCTAssertFalse(ScannerDuplicatePolicy.shouldReject(
      candidate: same, previous: prior, automatic: false
    ))
    XCTAssertFalse(ScannerDuplicatePolicy.shouldReject(
      candidate: differentTranscriptPage, previous: prior, automatic: true
    ))
  }
}
