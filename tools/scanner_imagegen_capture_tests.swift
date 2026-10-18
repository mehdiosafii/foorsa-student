import CoreGraphics
import Foundation

@main
struct ScannerImagegenCaptureTests {
  static func main() {
    precondition(!FoorsaScannerProfile(arguments: nil).usesImagegen)
    precondition(!FoorsaScannerProfile(arguments: ["profile": ["outputMode": "other"]]).usesImagegen)
    precondition(FoorsaScannerProfile(arguments: ["profile": ["outputMode": "imagegen"]]).usesImagegen)
    let size = CGSize(width: 1200, height: 1600)
    let flat = ScannerQuadrilateral(topLeft: CGPoint(x: 0.22, y: 0.80),
      topRight: CGPoint(x: 0.78, y: 0.80), bottomRight: CGPoint(x: 0.78, y: 0.20),
      bottomLeft: CGPoint(x: 0.22, y: 0.20))
    let left = ScannerQuadrilateral(topLeft: CGPoint(x: 0.25, y: 0.76),
      topRight: CGPoint(x: 0.79, y: 0.85), bottomRight: CGPoint(x: 0.79, y: 0.15),
      bottomLeft: CGPoint(x: 0.25, y: 0.24))
    let right = ScannerQuadrilateral(topLeft: CGPoint(x: 0.19, y: 0.85),
      topRight: CGPoint(x: 0.73, y: 0.76), bottomRight: CGPoint(x: 0.73, y: 0.24),
      bottomLeft: CGPoint(x: 0.19, y: 0.15))
    var guide = ScannerAdaptiveCaptureGuide(anchor: flat, imageSize: size,
      minimumArea: 0.16, at: 0, requiresNovelViews: true)
    precondition(guide.beginWaiting(at: 1))
    precondition(guide.observe(flat, at: 1.1) == .move)
    precondition(capture(&guide, view: left, start: 1.2) == .capture)
    precondition(!guide.resolveCapture(accepted: false))
    precondition(guide.beginWaiting(at: 3))
    // Holding the same rejected geometry never repeatedly spends captures.
    precondition(capture(&guide, view: left, start: 3.1) == .move)
    precondition(guide.attemptsTaken == 2)
    precondition(capture(&guide, view: right, start: 4.5) == .capture)
    precondition(guide.resolveCapture(accepted: true))
    precondition(guide.beginWaiting(at: 6))
    precondition(capture(&guide, view: flat, start: 6.1) == .move)
    precondition(capture(&guide, view: left, start: 7.5) == .move)
    guide.cancel()
    precondition(!guide.resolveCapture(accepted: true))
    precondition(guide.observe(right, at: 9) == .inactive)
    var timeout = ScannerAdaptiveCaptureGuide(anchor: flat, imageSize: size,
      minimumArea: 0.16, at: 0, requiresNovelViews: true)
    precondition(timeout.beginWaiting(at: 1))
    precondition(timeout.observe(left, at: 19) == .expired)
    precondition(!timeout.beginWaiting(at: 60))

    // Real-iPhone regression: the page stayed clear and stable for 18 seconds,
    // but perspective novelty timed out and discarded the first usable photo.
    // ImageGen must request its next source photo after a fresh stable hold,
    // including when the user does not tilt. It still waits for a per-still
    // quality decision before accepting that source photo.
    var source = ScannerAdaptiveCaptureGuide(anchor: flat, imageSize: size,
      minimumArea: 0.16, at: 0, requiresPerspectiveChange: false)
    precondition(source.beginWaiting(at: 1))
    precondition(source.observe(flat, at: 1.1) == .hold(0))
    precondition(source.observe(flat, at: 1.3) != .capture)
    precondition(source.observe(flat, at: 1.5) != .capture)
    precondition(source.observe(flat, at: 1.7) != .capture)
    precondition(source.observe(flat, at: 1.9) == .capture)
    precondition(source.acceptedAdditionalViews == 0)
    precondition(!source.resolveCapture(accepted: false))
    precondition(source.beginWaiting(at: 2))
    precondition(capture(&source, view: flat, start: 2.1) == .capture)
    precondition(source.resolveCapture(accepted: true))
    precondition(source.acceptedViews == [flat, flat])
    precondition(source.acceptedAdditionalViews == 1)
    source.cancel()
    precondition(source.observe(flat, at: 4) == .inactive)

    // Same-angle permission is not permission for timed, stale, missing,
    // clipped, or moving-page capture. Each failure resets the fresh hold.
    var unsafe = ScannerAdaptiveCaptureGuide(anchor: flat, imageSize: size,
      minimumArea: 0.16, at: 0, requiresPerspectiveChange: false)
    precondition(unsafe.beginWaiting(at: 1))
    precondition(unsafe.observe(nil, at: 1.1) == .move)
    precondition(unsafe.observe(flat, at: 1.3, processingDuration: 0.7) == .hold(0))
    precondition(unsafe.observe(flat, at: 1.5) == .hold(0))
    precondition(unsafe.observe(left, at: 1.7) == .hold(0))
    precondition(unsafe.observe(right, at: 1.9) == .hold(0))
    let clipped = ScannerQuadrilateral(topLeft: CGPoint(x: 0.22, y: 1.02),
      topRight: CGPoint(x: 0.78, y: 1.02), bottomRight: flat.bottomRight,
      bottomLeft: flat.bottomLeft)
    precondition(unsafe.observe(clipped, at: 2.1) == .move)
    precondition(unsafe.observe(flat, at: 3) == .hold(0))
    precondition(unsafe.attemptsTaken == 1)
    precondition(unsafe.observe(flat, at: 19) == .expired)
    precondition(!unsafe.beginWaiting(at: 60))

    var boundedSource = ScannerAdaptiveCaptureGuide(anchor: flat, imageSize: size,
      minimumArea: 0.16, at: 0, requiresPerspectiveChange: false)
    for index in 0..<ScannerAdaptiveCaptureGuide.maximumAttempts - 1 {
      let start = 1 + Double(index) * 2
      precondition(boundedSource.beginWaiting(at: start))
      precondition(capture(&boundedSource, view: flat, start: start + 0.1) == .capture)
      precondition(!boundedSource.resolveCapture(accepted: false))
    }
    precondition(!boundedSource.beginWaiting(at: 16))
    precondition(boundedSource.attemptsTaken == ScannerAdaptiveCaptureGuide.maximumAttempts)

    var originals = ScannerOriginalPhotoPool()
    let original = Data([0xff, 0xd8, 1, 2, 3, 0xff, 0xd9])
    precondition(!originals.append(Data()))
    precondition(!originals.append(Data([1, 2, 3, 4])))
    precondition(originals.append(original))
    precondition(originals.photos.first == original)
    precondition(!originals.canComplete(usefulViews: 2))
    precondition(originals.append(original))
    precondition(!originals.canComplete(usefulViews: 1))
    precondition(originals.canComplete(usefulViews: 2))
    for _ in 0..<4 { precondition(originals.append(original)) }
    precondition(originals.isFull && !originals.append(original))
    originals.reset()
    precondition(originals.photos.isEmpty && originals.totalBytes == 0)
    var large = Data(repeating: 0, count: ScannerOriginalPhotoPool.maximumPhotoBytes)
    large[0] = 0xff; large[1] = 0xd8
    large[large.count - 2] = 0xff; large[large.count - 1] = 0xd9
    for _ in 0..<4 { precondition(originals.append(large)) }
    precondition(originals.totalBytes == ScannerOriginalPhotoPool.maximumTotalBytes)
    precondition(!originals.append(original))
    originals.reset()
    large.insert(0, at: 2)
    precondition(!originals.append(large))
    precondition(originals.append(original) && originals.photos == [original])

    let mapped = ScannerLivePhotoCrop.map(flat, liveSize: size, photoSize: size,
      minimumArea: 0.16)!
    precondition(mapped.topLeft.x < flat.topLeft.x && mapped.topLeft.y > flat.topLeft.y)
    let wideStill = ScannerLivePhotoCrop.map(flat, liveSize: size,
      photoSize: CGSize(width: 1600, height: 1600), minimumArea: 0.16)!
    precondition(wideStill.topLeft.x > flat.topLeft.x)
    precondition(ScannerLivePhotoCrop.map(flat, liveSize: .zero, photoSize: size,
      minimumArea: 0.16) == nil)
    print("PASS: imagegen stable-view latency regression, fresh hold and motion gates, rejected-view retake, bounded attempts, legacy distinct views, cancellation, deadlines, exact raw bytes, count/byte limits, retry reset, source crop mapping")
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
}
