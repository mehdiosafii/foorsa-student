import AVFoundation
import CoreImage
import ImageIO
import UIKit
import Vision

final class ScannerImageProcessor {
  private let context = CIContext(options: [
    .cacheIntermediates: false,
    .priorityRequestLow: false,
  ])

  func process(photoData: Data, profile: FoorsaScannerProfile) -> ScannerProcessedCandidate? {
    autoreleasepool {
      guard let source = CIImage(data: photoData, options: [.applyOrientationProperty: true]) else {
        return nil
      }
      let upright = source.transformed(by: CGAffineTransform(
        translationX: -source.extent.origin.x,
        y: -source.extent.origin.y
      ))
      guard let observation = try? ScannerRectangleDetector.detect(
        in: upright,
        profile: profile,
        purpose: .still
      ) else { return nil }
      let extent = upright.extent
      func vector(_ point: CGPoint) -> CIVector {
        CIVector(x: extent.minX + point.x * extent.width,
                 y: extent.minY + point.y * extent.height)
      }
      guard let corrected = CIFilter(
        name: "CIPerspectiveCorrection",
        parameters: [
          kCIInputImageKey: upright,
          "inputTopLeft": vector(observation.topLeft),
          "inputTopRight": vector(observation.topRight),
          "inputBottomRight": vector(observation.bottomRight),
          "inputBottomLeft": vector(observation.bottomLeft),
        ]
      )?.outputImage else { return nil }

      let bounded = resized(corrected, maximumEdge: 2600)
      guard let cgImage = context.createCGImage(bounded, from: bounded.extent) else { return nil }
      let image = UIImage(cgImage: cgImage, scale: 1, orientation: .up)
      // A page must fit inside the portal's bounded PDF request on its own.
      // Reduce JPEG quality only when necessary, keeping the original pixels.
      var encoded = image.jpegData(compressionQuality: 0.92)
      for quality in [0.86, 0.78, 0.68] where (encoded?.count ?? 0) > 2_650_000 {
        encoded = image.jpegData(compressionQuality: quality)
      }
      guard let jpeg = encoded, !jpeg.isEmpty, jpeg.count <= 2_650_000,
            let fingerprint = fingerprint(for: cgImage) else { return nil }
      let quad = ScannerQuadrilateral(
        topLeft: observation.topLeft,
        topRight: observation.topRight,
        bottomRight: observation.bottomRight,
        bottomLeft: observation.bottomLeft
      )
      return ScannerProcessedCandidate(
        jpeg: jpeg,
        sharpness: sharpness(of: cgImage),
        coverage: Double(quad.area),
        fingerprint: fingerprint
      )
    }
  }

  private func resized(_ image: CIImage, maximumEdge: CGFloat) -> CIImage {
    let edge = max(image.extent.width, image.extent.height)
    guard edge > maximumEdge else { return image }
    let scale = maximumEdge / edge
    let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    return scaled.transformed(by: CGAffineTransform(
      translationX: -scaled.extent.origin.x,
      y: -scaled.extent.origin.y
    ))
  }

  private func thumbnailBytes(for image: CGImage, side: Int) -> [UInt8]? {
    thumbnailBytes(for: image, width: side, height: side)
  }

  private func thumbnailBytes(for image: CGImage, width: Int, height: Int) -> [UInt8]? {
    var pixels = [UInt8](repeating: 0, count: width * height)
    guard let context = CGContext(
      data: &pixels,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: width,
      space: CGColorSpaceCreateDeviceGray(),
      bitmapInfo: CGImageAlphaInfo.none.rawValue
    ) else { return nil }
    context.interpolationQuality = .medium
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return pixels
  }

  private func sharpness(of image: CGImage) -> Double {
    guard let pixels = thumbnailBytes(for: image, side: 96) else { return 0 }
    var score = 0.0
    for y in 1..<95 {
      for x in 1..<95 {
        let index = y * 96 + x
        let center = Int(pixels[index]) * 4
        let laplacian = center - Int(pixels[index - 1]) - Int(pixels[index + 1])
          - Int(pixels[index - 96]) - Int(pixels[index + 96])
        score += Double(laplacian * laplacian)
      }
    }
    return log1p(score / Double(94 * 94))
  }

  private func fingerprint(for image: CGImage) -> ScannerImageFingerprint? {
    // Four times the detail of a traditional 9x8 dHash avoids treating two
    // text-heavy pages with the same margins as duplicates.
    let rows = 16
    let columns = 16
    guard let pixels = thumbnailBytes(for: image, width: columns + 1, height: rows) else { return nil }
    var words = [UInt64](repeating: 0, count: rows * columns / 64)
    for y in 0..<rows {
      for x in 0..<columns where pixels[y * (columns + 1) + x] > pixels[y * (columns + 1) + x + 1] {
        let bit = y * columns + x
        words[bit / 64] |= UInt64(1) << UInt64(bit % 64)
      }
    }
    return ScannerImageFingerprint(words: words)
  }
}
