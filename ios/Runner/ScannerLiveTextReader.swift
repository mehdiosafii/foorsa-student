import CoreImage
import Foundation
import ImageIO
import Vision

/// How carefully one live read looks at the page.
enum ScannerTextReadLevel: Equatable {
  /// While the student frames the page.
  case fast
  /// Once the page is ready: the confirm that decides the capture.
  case accurate
}

/// What became of one live read.
enum ScannerTextReadOutcome {
  case read(ScannerTextFrame)
  /// The outline could not be cropped (too small, degenerate): nothing to judge.
  case skipped
  /// Vision itself failed.
  case failed
}

/// Reads the text on the live page a few times a second, on its own queue,
/// so the preview and the outline never wait for it. Each read crops the
/// page with a margin from one preview frame, holds the camera's buffer only
/// while that crop is drawn, and hands back what Vision read as a pure
/// ScannerTextFrame. Nothing leaves the phone and nothing read is logged.
final class ScannerLiveTextReader {
  static let fastInterval: TimeInterval = 0.25
  static let accurateInterval: TimeInterval = 0.35
  /// A slow phone reads less often instead of falling behind.
  static let durationBackoff = 1.5

  /// The preview frame, released as soon as its crop is drawn, so the camera
  /// can reuse its buffer while Vision reads.
  private final class PendingFrame {
    var image: CIImage?
    init(_ image: CIImage) { self.image = image }
  }

  private let queue = DispatchQueue(label: "ma.foorsa.scanner.text", qos: .utility)
  private let context = CIContext(options: [.useSoftwareRenderer: false, .cacheIntermediates: false])
  private let lock = NSLock()
  private var busy = false
  private var lastStart: TimeInterval?
  private var lastDuration: TimeInterval = 0

  /// Starts a read unless one is running or the last began too recently.
  /// Called on the camera's analysis queue; `completion` runs on the text queue.
  @discardableResult
  func submit(image: CIImage, quadrilateral: ScannerQuadrilateral, level: ScannerTextReadLevel,
              settings: ScannerTextReadSettings, turns: ScannerTextTurnPolicy, at time: TimeInterval,
              completion: @escaping (ScannerTextReadOutcome) -> Void) -> Bool {
    lock.lock()
    let interval = max(level == .accurate ? Self.accurateInterval : Self.fastInterval,
      lastDuration * Self.durationBackoff)
    if busy || lastStart.map({ time >= $0 && time - $0 < interval }) == true {
      lock.unlock()
      return false
    }
    busy = true
    lastStart = time
    lock.unlock()
    let pending = PendingFrame(image)
    queue.async { [weak self] in
      guard let self else { return }
      let started = ProcessInfo.processInfo.systemUptime
      let outcome = autoreleasepool {
        self.read(pending, quadrilateral: quadrilateral, level: level, settings: settings, turns: turns)
      }
      let duration = ProcessInfo.processInfo.systemUptime - started
      self.lock.lock()
      self.busy = false
      self.lastDuration = duration
      self.lock.unlock()
      completion(outcome)
    }
    return true
  }

  /// The next page is read at once.
  func reset() {
    lock.lock()
    lastStart = nil
    lock.unlock()
  }

  private func read(_ pending: PendingFrame, quadrilateral: ScannerQuadrilateral, level: ScannerTextReadLevel,
                    settings: ScannerTextReadSettings, turns: ScannerTextTurnPolicy) -> ScannerTextReadOutcome {
    // The frame is held only inside this closure: once its crop is drawn,
    // nothing here keeps the camera's buffer while Vision reads.
    let rendered: (image: CGImage, quarterTurns: Int, page: [CGPoint])? = {
      guard let image = pending.image else { return nil }
      return self.render(image, quadrilateral: quadrilateral, level: level, turns: turns)
    }()
    pending.image = nil
    guard let crop = rendered else { return .skipped }
    let recognize = VNRecognizeTextRequest()
    recognize.recognitionLevel = level == .accurate ? .accurate : .fast
    recognize.usesLanguageCorrection = false
    recognize.recognitionLanguages = settings.languages
    recognize.minimumTextHeight = settings.minimumTextHeight
    // The outline's own detection keeps priority over a framing read.
    recognize.preferBackgroundProcessing = level == .fast
    let regions = VNDetectTextRectanglesRequest()
    regions.reportCharacterBoxes = false
    let requests: [VNRequest] = settings.detectsRegions ? [recognize, regions] : [recognize]
    do {
      try VNImageRequestHandler(cgImage: crop.image, orientation: .up, options: [:]).perform(requests)
    } catch {
      return .failed
    }
    let lines = (recognize.results ?? []).prefix(ScannerTextFrame.maximumLines).map { observation in
      ScannerTextObservation(candidates: observation.topCandidates(3).map { $0.string },
        box: observation.boundingBox, quarterTurns: crop.quarterTurns)
    }
    let found: [ScannerTextObservation] = settings.detectsRegions
      ? (regions.results ?? []).prefix(ScannerTextFrame.maximumRegions).map { observation in
          ScannerTextObservation(candidates: [], box: observation.boundingBox, quarterTurns: crop.quarterTurns)
        }
      : []
    return .read(ScannerTextFrame(lines: Array(lines), regions: found, quarterTurns: crop.quarterTurns,
      page: crop.page, readingSize: CGSize(width: crop.image.width, height: crop.image.height)))
  }

  /// The page and a margin around it, perspective-corrected, turned for
  /// reading and drawn into memory the camera does not own.
  private func render(_ image: CIImage, quadrilateral: ScannerQuadrilateral, level: ScannerTextReadLevel,
                      turns: ScannerTextTurnPolicy) -> (image: CGImage, quarterTurns: Int, page: [CGPoint])? {
    let extent = image.extent
    guard !extent.isInfinite, !extent.isNull, extent.width >= 32, extent.height >= 32 else { return nil }
    let crop = quadrilateral.expanded(by: ScannerTextGeometry.cropExpansion)
    guard let page = ScannerTextGeometry.pageInCrop(page: quadrilateral, crop: crop) else { return nil }
    func vector(_ point: CGPoint) -> CIVector {
      CIVector(x: extent.minX + point.x * extent.width, y: extent.minY + point.y * extent.height)
    }
    guard let corrected = CIFilter(name: "CIPerspectiveCorrection", parameters: [
      kCIInputImageKey: image,
      "inputTopLeft": vector(crop.topLeft), "inputTopRight": vector(crop.topRight),
      "inputBottomRight": vector(crop.bottomRight), "inputBottomLeft": vector(crop.bottomLeft),
    ])?.outputImage else { return nil }
    let correctedExtent = corrected.extent
    guard !correctedExtent.isInfinite, !correctedExtent.isNull,
          correctedExtent.width >= 48, correctedExtent.height >= 48 else { return nil }
    var output = corrected.transformed(by: CGAffineTransform(translationX: -correctedExtent.minX,
      y: -correctedExtent.minY))
    // Machine lines need every preview pixel; a framing read can do with fewer.
    let limit: CGFloat = level == .accurate ? 1600 : 1200
    let scale = min(1, limit / max(correctedExtent.width, correctedExtent.height))
    if scale < 1 {
      output = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale), highQualityDownsample: true)
    }
    let width = output.extent.width, height = output.extent.height
    let quarterTurns = turns.quarterTurns(width: width, height: height)
    output = output.transformed(by: Self.turn(quarterTurns, width: width, height: height))
    let turned = output.extent
    output = output.transformed(by: CGAffineTransform(translationX: -turned.minX, y: -turned.minY))
    let bounds = CGRect(x: 0, y: 0, width: floor(turned.width), height: floor(turned.height))
    guard bounds.width >= 32, bounds.height >= 32,
          let rendered = context.createCGImage(output, from: bounds) else { return nil }
    return (rendered, quarterTurns, page)
  }

  /// Turns an image whose origin is zero counterclockwise by quarter turns,
  /// keeping its origin at zero; ScannerQuarterTurn maps points the same way.
  static func turn(_ quarterTurns: Int, width: CGFloat, height: CGFloat) -> CGAffineTransform {
    switch ScannerQuarterTurn.normalized(quarterTurns) {
    case 1: return CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: height, ty: 0)
    case 2: return CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: width, ty: height)
    case 3: return CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: width)
    default: return .identity
    }
  }
}
