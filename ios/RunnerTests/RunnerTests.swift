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
