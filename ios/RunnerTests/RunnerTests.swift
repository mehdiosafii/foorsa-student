import Flutter
import UIKit
import Vision
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {
  func testPixelDetectorAndStillProcessorCaptureCompletePageAndRejectDefocus() throws {
    let bounds = CGRect(x: 0, y: 0, width: 1440, height: 1920)
    let background = CIImage(color: CIColor(red: 0.22, green: 0.26, blue: 0.31)).cropped(to: bounds)
    let paperBounds = CGRect(x: 200, y: 220, width: 1040, height: 1480)
    var image = CIImage(color: CIColor(red: 0.97, green: 0.95, blue: 0.86))
      .cropped(to: paperBounds).composited(over: background)
    for row in 0..<20 {
      let mark = CIImage(color: CIColor(red: 0.1, green: 0.15, blue: 0.2))
        .cropped(to: CGRect(x: 300, y: 350 + row * 60, width: row % 3 == 0 ? 700 : 800, height: 12))
      image = mark.composited(over: image)
    }
    let profile = FoorsaScannerProfile(arguments: ["profile": ["documentKey": "transcript"]])
    for purpose in [ScannerDetectionPurpose.live, .still] {
      let detected = try XCTUnwrap(ScannerRectangleDetector.detect(in: image, profile: profile, purpose: purpose))
      XCTAssertEqual(detected.boundingBox.minX, 200.0 / 1440, accuracy: 0.025)
      XCTAssertEqual(detected.boundingBox.minY, 220.0 / 1920, accuracy: 0.025)
      XCTAssertEqual(detected.boundingBox.maxX, 1240.0 / 1440, accuracy: 0.025)
      XCTAssertEqual(detected.boundingBox.maxY, 1700.0 / 1920, accuracy: 0.025)
      let blurred = image.clampedToExtent().applyingFilter("CIGaussianBlur",
        parameters: [kCIInputRadiusKey: 24]).cropped(to: bounds)
      XCTAssertNil(try ScannerRectangleDetector.detect(in: blurred, profile: profile, purpose: purpose))
    }
    let cg = try XCTUnwrap(CIContext().createCGImage(image, from: bounds))
    let jpeg = try XCTUnwrap(UIImage(cgImage: cg).jpegData(compressionQuality: 0.95))
    let processed = try XCTUnwrap(ScannerImageProcessor().process(photoData: jpeg, profile: profile))
    XCTAssertFalse(processed.jpeg.isEmpty)
    XCTAssertGreaterThan(processed.coverage, 0.5)
  }

  func testContentClarityRejectsSevereBlurAndEmptyFrames() {
    let bounds = CGRect(x: 0, y: 0, width: 1440, height: 1920)
    var page = CIImage(color: CIColor(red: 0.95, green: 0.95, blue: 0.95)).cropped(to: bounds)
    for row in 0..<20 {
      let line = CIImage(color: CIColor(red: 0.1, green: 0.1, blue: 0.1))
        .cropped(to: CGRect(x: 300, y: 400 + row * 50, width: 700, height: 12))
      page = line.composited(over: page)
    }
    let sharp = ContentClarity.score(page)
    let blurred = ContentClarity.score(page.clampedToExtent()
      .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 24])
      .cropped(to: bounds))
    XCTAssertGreaterThanOrEqual(sharp.support, 24)
    XCTAssertGreaterThan(sharp.q50, 0.7)
    XCTAssertLessThan(blurred.q50, 0.35)
    XCTAssertEqual(ContentClarity.score(CIImage(color: .white).cropped(to: bounds)).support, 0)
  }

  func testContentClarityNormalizesImageOriginAndRejectsInvalidInputs() {
    let bounds = CGRect(x: 0, y: 0, width: 1440, height: 1920)
    let paper = CIImage(color: .white).cropped(to: bounds)
    let mark = CIImage(color: .black).cropped(to: CGRect(x: 400, y: 500, width: 500, height: 600))
    let image = mark.composited(over: paper)
    let shifted = image.transformed(by: CGAffineTransform(translationX: 100, y: -200))
    XCTAssertEqual(ContentClarity.score(image).q50, ContentClarity.score(shifted).q50, accuracy: 0.001)
    XCTAssertEqual(ContentClarity.score(CIImage.empty()).support, 0)
    XCTAssertEqual(ContentClarity.score(CIImage(color: .white)).support, 0)
    XCTAssertEqual(ContentClarity.score(image,
      configuration: .init(longestSide: .infinity, maximumSelectedEdges: 4096)).support, 0)
  }

  func testClaritySmallInsetsAndInvalidDetectorExtentsAreSafe() throws {
    let bounds = CGRect(x: 0, y: 0, width: 32, height: 32)
    let page = CIImage(color: .white).cropped(to: bounds)
    let mark = CIImage(color: .black).cropped(to: CGRect(x: 8, y: 8, width: 16, height: 8))
    var configuration = ContentClarity.Configuration()
    configuration.longestSide = 64
    configuration.horizontalInset = 0.02
    configuration.verticalInset = 0.02
    XCTAssertGreaterThan(ContentClarity.score(mark.composited(over: page),
      configuration: configuration).support, 0)
    configuration.horizontalInset = .nan
    XCTAssertEqual(ContentClarity.score(page, configuration: configuration).support, 0)
    let profile = FoorsaScannerProfile(arguments: ["profile": ["documentKey": "transcript"]])
    for purpose in [ScannerDetectionPurpose.live, .still] {
      XCTAssertNil(try ScannerRectangleDetector.detect(in: CIImage.empty(), profile: profile, purpose: purpose))
      XCTAssertNil(try ScannerRectangleDetector.detect(in: CIImage(color: .white), profile: profile, purpose: purpose))
      XCTAssertNil(try ScannerRectangleDetector.detect(in: page.cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8)),
        profile: profile, purpose: purpose))
    }
  }

  func testCardCoverageAcceptsReadableSmallCardButNotDistantCard() {
    let card = FoorsaScannerProfile(arguments: ["profile": ["documentKey": "parent_id"]])
    let paper = FoorsaScannerProfile(arguments: ["profile": ["documentKey": "transcript"]])
    let framedCard = ScannerQuadrilateral(
      topLeft: CGPoint(x: 0.2, y: 0.625), topRight: CGPoint(x: 0.8, y: 0.625),
      bottomRight: CGPoint(x: 0.8, y: 0.375), bottomLeft: CGPoint(x: 0.2, y: 0.375)
    )
    var cardTracker = ScannerStabilityTracker(minimumArea: card.minimumCaptureArea)
    var paperTracker = ScannerStabilityTracker(minimumArea: paper.minimumCaptureArea)
    for tick in 0..<8 {
      _ = cardTracker.observe(framedCard, at: Double(tick) * 0.12)
      _ = paperTracker.observe(framedCard, at: Double(tick) * 0.12)
    }
    XCTAssertTrue(cardTracker.observe(framedCard, at: 0.96).ready)
    XCTAssertFalse(paperTracker.observe(framedCard, at: 0.96).ready)
    let distant = ScannerQuadrilateral(
      topLeft: CGPoint(x: 0.4, y: 0.6), topRight: CGPoint(x: 0.6, y: 0.6),
      bottomRight: CGPoint(x: 0.6, y: 0.4), bottomLeft: CGPoint(x: 0.4, y: 0.4)
    )
    XCTAssertFalse(cardTracker.observe(distant, at: 1.08).ready)
  }

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

  func testQuarterTurnMappingPreservesAsymmetricPageCorners() {
    // Explicit independently rotated coordinates catch swapped corner names,
    // mirrored axes, and half-turn mistakes on a skewed, non-square page.
    let original: [CGPoint] = [
      CGPoint(x: 0.13, y: 0.83), CGPoint(x: 0.87, y: 0.91),
      CGPoint(x: 0.79, y: 0.16), CGPoint(x: 0.08, y: 0.23),
    ]
    let orientations: [[CGPoint]] = [
      original,
      [CGPoint(x: 0.09, y: 0.87), CGPoint(x: 0.84, y: 0.79),
       CGPoint(x: 0.77, y: 0.08), CGPoint(x: 0.17, y: 0.13)],
      [CGPoint(x: 0.21, y: 0.84), CGPoint(x: 0.92, y: 0.77),
       CGPoint(x: 0.87, y: 0.17), CGPoint(x: 0.13, y: 0.09)],
      [CGPoint(x: 0.23, y: 0.92), CGPoint(x: 0.83, y: 0.87),
       CGPoint(x: 0.91, y: 0.13), CGPoint(x: 0.16, y: 0.21)],
    ]
    for (turns, corners) in orientations.enumerated() {
      let rotated = VNRectangleObservation(requestRevision: VNDetectRectanglesRequestRevision1,
        topLeft: corners[0], bottomLeft: corners[3],
        bottomRight: corners[2], topRight: corners[1])
      let mapped = ScannerRectangleDetector.mapFromQuarterTurn(rotated, turns: turns)
      let actual = [mapped.topLeft, mapped.topRight, mapped.bottomRight, mapped.bottomLeft]
      for (expected, point) in zip(original, actual) {
        XCTAssertEqual(point.x, expected.x, accuracy: 0.000001)
        XCTAssertEqual(point.y, expected.y, accuracy: 0.000001)
      }
    }
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

  func testCameraAwareGuideMeetsCaptureAreaAcrossPhonesAndCameraFormats() {
    // Available bounds mirror the real controls, including notch/home-indicator
    // insets, thumbnails, and the separate landscape control column.
    let phones: [(CGSize, CGFloat, CGFloat, CGFloat)] = [
      (CGSize(width: 320, height: 568), 20, 0, 0),
      (CGSize(width: 375, height: 667), 20, 0, 0),
      (CGSize(width: 390, height: 844), 47, 34, 47),
      (CGSize(width: 440, height: 956), 62, 34, 62),
    ]
    for (phone, top, bottom, landscapeSide) in phones {
      for landscape in [false, true] {
        let safe = landscape
          ? CGRect(x: landscapeSide, y: 0, width: phone.height - landscapeSide * 2,
              height: phone.width - (bottom > 0 ? 21 : 0))
          : CGRect(x: 0, y: top, width: phone.width, height: phone.height - top - bottom)
        let available = landscape
          ? CGRect(x: safe.minX + 12, y: safe.minY + 67,
              width: safe.width - 104, height: safe.height - 131)
          : CGRect(x: safe.minX + 12, y: safe.minY + 125,
              width: safe.width - 24, height: safe.height - 315)
        for cameraRatio: CGFloat in [4.0 / 3.0, 16.0 / 9.0] {
          let camera = landscape ? CGSize(width: 1920, height: 1920 / cameraRatio)
            : CGSize(width: 1920 / cameraRatio, height: 1920)
          for (key, ratio): (String, CGFloat) in [
            ("identity", 1.42), ("parent_id", 1.585), ("transcript", 0.71),
          ] {
            let profile = FoorsaScannerProfile(arguments: ["profile": ["documentKey": key]])
            let geometry = ScannerPreviewGeometry(imageSize: camera,
              availableRect: available, guideAspectRatio: ratio)
            let preview = geometry.previewRect
            let guide = geometry.guideRect
            XCTAssertGreaterThan(preview.width, 100)
            XCTAssertGreaterThan(preview.height, 100)
            XCTAssertTrue(available.insetBy(dx: -0.001, dy: -0.001).contains(preview))
            XCTAssertTrue(preview.contains(guide))
            XCTAssertEqual(preview.width / preview.height, camera.width / camera.height, accuracy: 0.001)
            // A page slightly smaller than the drawn guide must still auto-capture.
            let page = guide.insetBy(dx: guide.width * 0.05, dy: guide.height * 0.05)
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
              CGPoint(x: (x - preview.minX) / preview.width,
                y: 1 - (y - preview.minY) / preview.height)
            }
            let quad = ScannerQuadrilateral(topLeft: point(page.minX, page.minY),
              topRight: point(page.maxX, page.minY), bottomRight: point(page.maxX, page.maxY),
              bottomLeft: point(page.minX, page.maxY))
            XCTAssertTrue(quad.isComplete(minimumArea: profile.minimumCaptureArea))
            XCTAssertEqual(quad.estimatedAspectRatio(in: camera), ratio, accuracy: 0.001)
            let mapped = ScannerAspectFillMapper.layerPoint(fromVisionPoint: quad.topLeft,
              imageSize: camera, in: preview)
            XCTAssertEqual(mapped.x, page.minX, accuracy: 0.001)
            XCTAssertEqual(mapped.y, page.minY, accuracy: 0.001)
            var tracker = ScannerStabilityTracker(minimumArea: profile.minimumCaptureArea)
            for tick in 0...7 { _ = tracker.observe(quad, at: Double(tick) * 0.12) }
            XCTAssertTrue(tracker.observe(quad, at: 0.96).ready)
          }
        }
      }
    }
  }

  func testCameraAwareGuideRejectsInvalidViewport() {
    let geometry = ScannerPreviewGeometry(imageSize: CGSize(width: 1440, height: 1920),
      availableRect: .zero, guideAspectRatio: 1.42)
    XCTAssertEqual(geometry.previewRect, .zero)
    XCTAssertEqual(geometry.guideRect, .zero)
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

  func testSlowAnalysisCanFinishHoldWithoutAcceptingTooFewObservations() {
    var tracker = ScannerStabilityTracker()
    for time in [0.0, 0.30, 0.60] {
      XCTAssertFalse(tracker.observe(page, at: time, processingDuration: 0.29).ready)
    }
    XCTAssertTrue(tracker.observe(page, at: 0.90, processingDuration: 0.29).ready)

    tracker.reset()
    for time in [0.0, 0.55, 1.10] {
      XCTAssertFalse(tracker.observe(page, at: time, processingDuration: 0.54).ready)
    }
    XCTAssertTrue(tracker.observe(page, at: 1.65, processingDuration: 0.54).ready)
    XCTAssertFalse(tracker.observe(page, at: 2.35, processingDuration: 0.54).ready)
  }

  func testSlowAnalysisResetsForMissingStaleOrNonMonotonicObservations() {
    var tracker = ScannerStabilityTracker()
    for time in [0.0, 0.30, 0.60, 0.90] {
      _ = tracker.observe(page, at: time, processingDuration: 0.29)
    }
    XCTAssertEqual(tracker.observe(nil, at: 1.20, processingDuration: 0.29).progress, 0)
    XCTAssertFalse(tracker.observe(page, at: 1.50, processingDuration: 0.29).ready)
    XCTAssertEqual(tracker.observe(page, at: 1.80, processingDuration: 0.70).progress, 0)
    XCTAssertNil(tracker.anchor)
    _ = tracker.observe(page, at: 2.10, processingDuration: 0.29)
    XCTAssertEqual(tracker.observe(page, at: 2.0, processingDuration: 0.29).progress, 0)
    XCTAssertEqual(tracker.observe(page, at: .nan, processingDuration: 0.29).progress, 0)
    XCTAssertNil(tracker.anchor)
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

  func testSinglePageFlowCompletesWithBestCandidateExactlyOnce() {
    let soft = ScannerProcessedCandidate(
      jpeg: Data([1]), sharpness: 8, coverage: 0.95,
      fingerprint: ScannerImageFingerprint(bits: 0)
    )
    let sharp = ScannerProcessedCandidate(
      jpeg: Data([2]), sharpness: 9, coverage: 0.7,
      fingerprint: ScannerImageFingerprint(bits: 1)
    )
    var flow = ScannerSinglePageCompletionFlow()

    XCTAssertEqual(flow.resolve([soft, sharp]), .complete(Data([2])))
    XCTAssertTrue(flow.isFinished)
    XCTAssertEqual(flow.resolve([soft]), .ignored)
    XCTAssertFalse(flow.terminate())
  }

  func testSinglePageFlowRetriesRejectedBurstThenCompletesFreshBurst() {
    var flow = ScannerSinglePageCompletionFlow()
    let retry = flow.resolve([])
    guard case let .retry(message) = retry else {
      return XCTFail("A burst with no retained candidate must remain on camera")
    }
    XCTAssertTrue(message.contains("try again"))
    XCTAssertFalse(flow.isFinished)

    let retained = ScannerProcessedCandidate(
      jpeg: Data([7]), sharpness: 9, coverage: 0.8,
      fingerprint: ScannerImageFingerprint(bits: 7)
    )
    XCTAssertEqual(flow.resolve([retained]), .complete(Data([7])))
    XCTAssertTrue(flow.isFinished)
  }

  func testSinglePageFlowCancellationSuppressesLateBurstCompletion() {
    var flow = ScannerSinglePageCompletionFlow()
    XCTAssertTrue(flow.terminate())
    let late = ScannerProcessedCandidate(
      jpeg: Data([9]), sharpness: 10, coverage: 0.9,
      fingerprint: ScannerImageFingerprint(bits: 9)
    )
    XCTAssertEqual(flow.resolve([late]), .ignored)
    XCTAssertFalse(flow.terminate())
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

extension RunnerTests {
  func testBurstFusionRegistersThreeFramesAndRejectsOneFrameNoise() throws {
    let pristine = try makeFusionFixture(offset: .zero, noisePhase: nil)
    let frames = try [
      makeFusionFixture(offset: .zero, noisePhase: 0),
      makeFusionFixture(offset: CGPoint(x: 2, y: -1), noisePhase: 1),
      makeFusionFixture(offset: CGPoint(x: -2, y: 1), noisePhase: 2, glare: true),
    ]
    let candidates = frames.enumerated().map { index, image in
      ScannerProcessedCandidate(
        jpeg: Data([UInt8(10 + index)]),
        sharpness: 10 - Double(index) * 0.05,
        coverage: 0.8,
        fingerprint: ScannerImageFingerprint(bits: 0),
        correctedImage: image
      )
    }

    let resolution = try XCTUnwrap(ScannerImageProcessor().resolveBurst(candidates))
    XCTAssertEqual(resolution.mode, .alignedMedianFusion)
    XCTAssertEqual(resolution.framesConsidered, 3)
    XCTAssertEqual(resolution.framesUsed, 3)
    XCTAssertLessThanOrEqual(resolution.candidate.jpeg.count, 2_650_000)
    let fused = try XCTUnwrap(resolution.candidate.correctedImage)
    XCTAssertEqual(fused.width, frames[0].width)
    XCTAssertEqual(fused.height, frames[0].height)
    XCTAssertLessThan(
      try meanAbsoluteDifference(fused, pristine),
      try meanAbsoluteDifference(frames[0], pristine) * 0.7
    )
    // The third frame contains a bright glare block here. The two clean
    // captures must outvote it rather than adding translucent false content.
    let glarePixel = try rgbPixel(fused, at: CGPoint(x: 180, y: 240))
    XCTAssertLessThan(glarePixel.0, 245)
    XCTAssertLessThan(glarePixel.1, 245)
    XCTAssertLessThan(glarePixel.2, 245)
  }

  func testBurstFusionFallsBackExactlyWhenContentDoesNotAgree() throws {
    let reference = try makeFusionFixture(offset: .zero, noisePhase: 0)
    let similar = try makeFusionFixture(offset: CGPoint(x: 1, y: 0), noisePhase: 1)
    let different = try makeFusionFixture(offset: .zero, noisePhase: nil, foreignContent: true)
    let candidates = [reference, similar, different].enumerated().map { index, image in
      ScannerProcessedCandidate(
        jpeg: Data([UInt8(40 + index)]),
        sharpness: 10 - Double(index) * 0.05,
        coverage: 0.8,
        fingerprint: ScannerImageFingerprint(bits: UInt64(index)),
        correctedImage: image
      )
    }

    let resolution = try XCTUnwrap(ScannerImageProcessor().resolveBurst(candidates))
    XCTAssertEqual(resolution.mode, .bestFrameFallback)
    XCTAssertEqual(resolution.framesUsed, 1)
    XCTAssertEqual(resolution.candidate.jpeg, Data([40]))
    XCTAssertTrue(resolution.candidate.correctedImage === reference)
  }

  func testBurstFusionFallsBackForMissingOrSoftFrames() throws {
    let image = try makeFusionFixture(offset: .zero, noisePhase: 0)
    let sharp = ScannerProcessedCandidate(
      jpeg: Data([70]), sharpness: 10, coverage: 0.8,
      fingerprint: ScannerImageFingerprint(bits: 0), correctedImage: image
    )
    let soft = ScannerProcessedCandidate(
      jpeg: Data([71]), sharpness: 8, coverage: 0.8,
      fingerprint: ScannerImageFingerprint(bits: 0), correctedImage: image
    )
    let processor = ScannerImageProcessor()

    let missing = try XCTUnwrap(processor.resolveBurst([sharp, sharp]))
    XCTAssertEqual(missing.mode, .bestFrameFallback)
    XCTAssertEqual(missing.framesConsidered, 2)
    let softResult = try XCTUnwrap(processor.resolveBurst([sharp, sharp, soft]))
    XCTAssertEqual(softResult.mode, .bestFrameFallback)
    XCTAssertEqual(softResult.candidate.jpeg, sharp.jpeg)
  }

  func testBurstFusionFallsBackForResidualRotationThatCouldDoubleText() throws {
    let frames = try [
      makeFusionFixture(offset: .zero, noisePhase: 0),
      makeFusionFixture(offset: .zero, noisePhase: 1, rotationDegrees: 0.55),
      makeFusionFixture(offset: .zero, noisePhase: 2, rotationDegrees: -0.45),
    ]
    let candidates = frames.enumerated().map { index, image in
      ScannerProcessedCandidate(
        jpeg: Data([UInt8(90 + index)]),
        sharpness: 10 - Double(index) * 0.05,
        coverage: 0.8,
        fingerprint: ScannerImageFingerprint(bits: UInt64(index)),
        correctedImage: image
      )
    }

    let resolution = try XCTUnwrap(ScannerImageProcessor().resolveBurst(candidates))
    XCTAssertEqual(resolution.mode, .bestFrameFallback)
    XCTAssertEqual(resolution.fallbackReason, .registrationRejected)
    XCTAssertEqual(resolution.candidate.jpeg, Data([90]))
  }

  func testBurstFusionRejectsLocalizedThreePixelGlyphShiftAtCaptureResolution() throws {
    let frames = try [
      makeHighResolutionTextFixture(localShift: 0),
      makeHighResolutionTextFixture(localShift: 3),
      makeHighResolutionTextFixture(localShift: 3),
    ]
    let candidates = frames.enumerated().map { index, image in
      ScannerProcessedCandidate(
        jpeg: Data([UInt8(100 + index)]),
        sharpness: 10 - Double(index) * 0.01,
        coverage: 0.8,
        fingerprint: ScannerImageFingerprint(bits: UInt64(index)),
        correctedImage: image
      )
    }

    let resolution = try XCTUnwrap(ScannerImageProcessor().resolveBurst(candidates))
    XCTAssertEqual(resolution.mode, .bestFrameFallback)
    XCTAssertEqual(resolution.fallbackReason, .registrationRejected)
    XCTAssertEqual(resolution.candidate.jpeg, Data([100]))
  }
}

private extension RunnerTests {
  func makeHighResolutionTextFixture(localShift: Int) throws -> CGImage {
    let width = 1200
    let height = 1600
    let bytesPerRow = width * 4
    var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
    let context = try XCTUnwrap(CGContext(
      data: &pixels,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: bytesPerRow,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.setFillColor(CGColor(red: 0.94, green: 0.92, blue: 0.86, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(CGColor(red: 0.08, green: 0.10, blue: 0.13, alpha: 1))
    for line in 0..<70 {
      let y = 1450 - line * 19
      let shift = (30...33).contains(line) ? localShift : 0
      for glyph in 0..<34 {
        let x = 100 + glyph * 27 + shift
        context.fill(CGRect(x: x, y: y, width: glyph.isMultiple(of: 5) ? 5 : 3, height: 11))
        if !glyph.isMultiple(of: 3) {
          context.fill(CGRect(x: x, y: y, width: 18, height: 2))
        }
      }
    }
    return try XCTUnwrap(context.makeImage())
  }

  func makeFusionFixture(
    offset: CGPoint,
    noisePhase: Int?,
    glare: Bool = false,
    foreignContent: Bool = false,
    rotationDegrees: CGFloat = 0
  ) throws -> CGImage {
    let width = 360
    let height = 480
    let bytesPerRow = width * 4
    var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
    let context = try XCTUnwrap(CGContext(
      data: &pixels,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: bytesPerRow,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.setFillColor(CGColor(red: 0.91, green: 0.89, blue: 0.83, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.saveGState()
    context.translateBy(x: offset.x, y: offset.y)
    context.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
    context.rotate(by: rotationDegrees * .pi / 180)
    context.translateBy(x: -CGFloat(width) / 2, y: -CGFloat(height) / 2)
    if foreignContent {
      context.setFillColor(CGColor(red: 0.12, green: 0.30, blue: 0.52, alpha: 1))
      for column in 0..<8 {
        context.fill(CGRect(x: 28 + column * 40, y: 35, width: 18, height: 410))
      }
    } else {
      context.setFillColor(CGColor(red: 0.10, green: 0.12, blue: 0.16, alpha: 1))
      context.fill(CGRect(x: 34, y: 420, width: 210, height: 18))
      for row in 0..<15 {
        context.fill(CGRect(
          x: 38,
          y: 380 - row * 22,
          width: row.isMultiple(of: 4) ? 275 : 235,
          height: row.isMultiple(of: 3) ? 7 : 4
        ))
      }
      context.setFillColor(CGColor(red: 0.25, green: 0.42, blue: 0.65, alpha: 1))
      context.fillEllipse(in: CGRect(x: 265, y: 395, width: 54, height: 54))
    }
    context.restoreGState()
    if let phase = noisePhase {
      context.setFillColor(CGColor(red: 0.28, green: 0.23, blue: 0.19, alpha: 1))
      for index in 0..<900 {
        let x = (index * 67 + phase * 19) % (width - 24) + 12
        let y = (index * 43 + phase * 31) % (height - 24) + 12
        context.fill(CGRect(x: x, y: y, width: 1, height: 1))
      }
    }
    if glare {
      context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
      context.fill(CGRect(x: 158, y: 218, width: 44, height: 44))
    }
    return try XCTUnwrap(context.makeImage())
  }

  func rgbaBytes(_ image: CGImage) throws -> [UInt8] {
    let bytesPerRow = image.width * 4
    var pixels = [UInt8](repeating: 0, count: image.height * bytesPerRow)
    let context = try XCTUnwrap(CGContext(
      data: &pixels,
      width: image.width,
      height: image.height,
      bitsPerComponent: 8,
      bytesPerRow: bytesPerRow,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return pixels
  }

  func meanAbsoluteDifference(_ lhs: CGImage, _ rhs: CGImage) throws -> Double {
    XCTAssertEqual(lhs.width, rhs.width)
    XCTAssertEqual(lhs.height, rhs.height)
    let a = try rgbaBytes(lhs)
    let b = try rgbaBytes(rhs)
    var total = 0.0
    for index in stride(from: 0, to: min(a.count, b.count), by: 4) {
      total += abs(Double(a[index]) - Double(b[index]))
      total += abs(Double(a[index + 1]) - Double(b[index + 1]))
      total += abs(Double(a[index + 2]) - Double(b[index + 2]))
    }
    return total / Double(lhs.width * lhs.height * 3)
  }

  func rgbPixel(_ image: CGImage, at point: CGPoint) throws -> (UInt8, UInt8, UInt8) {
    let pixels = try rgbaBytes(image)
    let x = min(max(Int(point.x), 0), image.width - 1)
    let y = min(max(Int(point.y), 0), image.height - 1)
    let index = (y * image.width + x) * 4
    return (pixels[index], pixels[index + 1], pixels[index + 2])
  }
}

// Synthetic paper and printed panels exercise capture safety without customer assets.
extension RunnerTests {
  func testPaperDetectorRejectsAlignedAndRotatedFilledPanelsOnClippedSheets() throws {
    struct Fixture {
      let name: String
      let key: String
      let size: CGSize
      let outer: [CGPoint]
      let inner: [CGPoint]
    }
    func points(_ values: [[CGFloat]]) -> [CGPoint] {
      values.map { CGPoint(x: $0[0], y: $0[1]) }
    }
    func rotated(center: CGPoint, width: CGFloat, height: CGFloat, degrees: CGFloat) -> [CGPoint] {
      let radians = degrees * .pi / 180
      return points([[-width / 2, -height / 2], [width / 2, -height / 2],
                     [width / 2, height / 2], [-width / 2, height / 2]]).map { p in
        CGPoint(x: center.x + p.x * cos(radians) - p.y * sin(radians),
                y: center.y + p.x * sin(radians) + p.y * cos(radians))
      }
    }
    let fixtures = [
      Fixture(name: "portrait_aligned_clipped_top", key: "cv", size: CGSize(width: 1600, height: 2200),
        outer: points([[180,-100],[1420,-60],[1360,1900],[220,1850]]),
        inner: points([[390,180],[1210,200],[1170,1640],[420,1610]])),
      Fixture(name: "adaptive_aligned_clipped_left", key: "highest_degree", size: CGSize(width: 2200, height: 1600),
        outer: points([[-140,190],[1900,130],[1840,1420],[-100,1480]]),
        inner: points([[250,380],[1650,340],[1610,1210],[280,1250]])),
      Fixture(name: "portrait_rotated10_clipped_right", key: "cv", size: CGSize(width: 1600, height: 2200),
        outer: points([[250,120],[1690,170],[1620,2050],[280,2000]]),
        inner: rotated(center: CGPoint(x: 900, y: 1080), width: 760, height: 1260, degrees: 10)),
      Fixture(name: "adaptive_rotated11_clipped_bottom", key: "highest_degree", size: CGSize(width: 2200, height: 1600),
        outer: points([[150,260],[2050,200],[1990,1740],[190,1800]]),
        inner: rotated(center: CGPoint(x: 1100, y: 900), width: 1320, height: 760, degrees: -11)),
    ]
    for fixture in fixtures {
      let width = Int(fixture.size.width), height = Int(fixture.size.height)
      let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      context.setFillColor(CGColor(red: 0.47, green: 0.45, blue: 0.42, alpha: 1))
      context.fill(CGRect(origin: .zero, size: fixture.size))
      // Fixture coordinates are top-origin; Core Graphics drawing is bottom-origin.
      func draw(_ corners: [CGPoint], fill: CGColor, stroke: CGColor, lineWidth: CGFloat) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: corners[0].x, y: fixture.size.height - corners[0].y))
        for p in corners.dropFirst() {
          path.addLine(to: CGPoint(x: p.x, y: fixture.size.height - p.y))
        }
        path.closeSubpath()
        context.addPath(path)
        context.setFillColor(fill)
        context.setStrokeColor(stroke)
        context.setLineWidth(lineWidth)
        context.drawPath(using: .fillStroke)
      }
      draw(fixture.outer, fill: CGColor(red: 0.965, green: 0.955, blue: 0.92, alpha: 1),
        stroke: CGColor(red: 0.40, green: 0.38, blue: 0.34, alpha: 1), lineWidth: 8)
      draw(fixture.inner, fill: CGColor(red: 0.035, green: 0.23, blue: 0.31, alpha: 1),
        stroke: CGColor(red: 0.015, green: 0.08, blue: 0.11, alpha: 1), lineWidth: 16)
      context.setStrokeColor(CGColor(red: 0.91, green: 0.83, blue: 0.48, alpha: 1))
      context.setLineWidth(10)
      let minX = try XCTUnwrap(fixture.inner.map(\.x).min()) + 80
      let maxX = try XCTUnwrap(fixture.inner.map(\.x).max()) - 80
      var y = try XCTUnwrap(fixture.inner.map(\.y).min()) + 130
      let maxY = try XCTUnwrap(fixture.inner.map(\.y).max()) - 100
      while y < maxY {
        context.move(to: CGPoint(x: minX, y: fixture.size.height - y))
        context.addLine(to: CGPoint(x: maxX, y: fixture.size.height - y))
        context.strokePath()
        y += 95
      }
      let cgImage = try XCTUnwrap(context.makeImage())
      let jpeg = try XCTUnwrap(UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.95))
      let jpegImage = try XCTUnwrap(CIImage(data: jpeg))
      for key in [fixture.key, "parent_id"] {
        let profile = FoorsaScannerProfile(arguments: ["profile": ["documentKey": key]])
        for (encoding, image) in [("uncompressed", CIImage(cgImage: cgImage)), ("UIKitJPEG", jpegImage)] {
          // Ensure the negative is not passing merely because its content is blank or blurred.
          let clarity = ContentClarity.score(image)
          XCTAssertGreaterThanOrEqual(clarity.support, 24, "\(fixture.name) \(key) \(encoding)")
          XCTAssertGreaterThanOrEqual(clarity.q50, 0.35, "\(fixture.name) \(key) \(encoding)")
          for purpose in [ScannerDetectionPurpose.live, .still] {
            XCTAssertNil(try ScannerRectangleDetector.detect(in: image, profile: profile, purpose: purpose),
              "\(fixture.name) \(key) \(encoding) \(purpose): printed panel must not substitute for clipped paper")
          }
        }
      }
    }
  }
}
