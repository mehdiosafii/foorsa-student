import CoreGraphics
import CoreImage
import ImageIO
import Vision

enum ScannerDetectionPurpose {
  case live
  case still
}

enum ScannerRectangleDetector {
  static func makeRequest(for purpose: ScannerDetectionPurpose) -> VNDetectRectanglesRequest {
    let request = VNDetectRectanglesRequest()
    switch purpose {
    case .live:
      request.maximumObservations = 3
      request.minimumConfidence = 0.6
      request.minimumAspectRatio = 0.25
      request.maximumAspectRatio = 1
      request.minimumSize = 0.18
      request.quadratureTolerance = 30
    case .still:
      request.maximumObservations = 4
      request.minimumConfidence = 0.55
      request.minimumAspectRatio = 0.3
      request.maximumAspectRatio = 1
      request.minimumSize = 0.18
      request.quadratureTolerance = 28
    }
    return request
  }

  static func select(
    _ observations: [VNRectangleObservation],
    imageSize: CGSize,
    profile: FoorsaScannerProfile,
    purpose: ScannerDetectionPurpose
  ) -> VNRectangleObservation? {
    guard let largest = observations.max(by: {
      $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height
    }) else { return nil }
    if purpose == .still {
      let quad = ScannerQuadrilateral(
        topLeft: largest.topLeft, topRight: largest.topRight,
        bottomRight: largest.bottomRight, bottomLeft: largest.bottomLeft
      )
      // A still photo is detected again after the live preview. Apply the same
      // type rule before cropping; never substitute a smaller inner rectangle
      // merely because its shape happens to match the requested document.
      guard quad.isComplete(minimumArea: 0.12),
            profile.accepts(aspectRatio: quad.estimatedAspectRatio(in: imageSize)) else { return nil }
    }
    return largest
  }

  static func detect(
    in image: CIImage,
    profile: FoorsaScannerProfile,
    purpose: ScannerDetectionPurpose
  ) throws -> VNRectangleObservation? {
    let request = makeRequest(for: purpose)
    try VNImageRequestHandler(ciImage: image, orientation: .up).perform([request])
    return select(request.results ?? [], imageSize: image.extent.size, profile: profile, purpose: purpose)
  }
}
