import CoreImage
import ImageIO
import UniformTypeIdentifiers
import Vision

final class ScannerImageProcessor {
  private static let maximumEncodedBytes = 2_650_000
  private static let fusionFrameCount = 3
  private static let registrationMaximumEdge: CGFloat = 720
  private static let agreementMaximumEdge: CGFloat = 900

  // A temporal median keeps a detail only when at least two aligned captures
  // contain it. This is pixel denoising, with no OCR or text reconstruction;
  // accepted frames can still cause small, ordinary per-channel color changes.
  private static let temporalMedianKernel = CIColorKernel(source: """
    kernel vec4 temporalMedian(__sample a, __sample b, __sample c) {
      vec4 low = min(a, min(b, c));
      vec4 high = max(a, max(b, c));
      vec4 middle = a + b + c - low - high;
      return vec4(middle.rgb, a.a);
    }
    """)

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
      guard let jpeg = encode(cgImage),
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
        fingerprint: fingerprint,
        correctedImage: cgImage
      )
    }
  }

  func resolveBurst(
    _ candidates: [ScannerProcessedCandidate],
    isCancelled: () -> Bool = { false }
  ) -> ScannerBurstResolution? {
    autoreleasepool {
      guard !isCancelled() else { return nil }
      guard let referenceIndex = ScannerCandidateSelector.bestIndex(candidates) else { return nil }
      let best = candidates[referenceIndex]
      let fallback: (ScannerBurstFallbackReason) -> ScannerBurstResolution = { reason in
        ScannerBurstResolution(
          candidate: best,
          mode: .bestFrameFallback,
          framesConsidered: candidates.count,
          framesUsed: 1,
          fallbackReason: reason,
          alignmentModels: []
        )
      }
      guard candidates.count == Self.fusionFrameCount else { return fallback(.incompleteBurst) }
      guard let referenceCG = best.correctedImage else { return fallback(.missingCorrectedImage) }
      guard let kernel = Self.temporalMedianKernel else { return fallback(.renderOrEncodeFailure) }

      // Perspective correction has already put each page in document space.
      // Normalize the small crop-size variation, then register residual hand
      // motion. A substantially softer frame can only reduce document detail.
      let minimumSharpness = best.sharpness - log(1.8)
      guard candidates.allSatisfy({ $0.correctedImage != nil }) else {
        return fallback(.missingCorrectedImage)
      }
      guard candidates.allSatisfy({ $0.sharpness >= minimumSharpness }) else {
        return fallback(.frameTooSoft)
      }
      let referenceExtent = CGRect(
        x: 0,
        y: 0,
        width: referenceCG.width,
        height: referenceCG.height
      )
      guard referenceExtent.width >= 64, referenceExtent.height >= 64 else {
        return fallback(.incompatibleGeometry)
      }
      let reference = CIImage(cgImage: referenceCG).cropped(to: referenceExtent)
      var aligned = [reference]
      var alignmentModels: [ScannerBurstAlignmentModel] = []
      var maximumTranslation = CGFloat.zero

      for (index, candidate) in candidates.enumerated() where index != referenceIndex {
        guard !isCancelled() else { return nil }
        guard let candidateCG = candidate.correctedImage,
              dimensionsAreCompatible(candidateCG, referenceCG) else {
          return fallback(.incompatibleGeometry)
        }
        let normalized = normalizedImage(candidateCG, to: referenceExtent)
        guard let registered = registeredImage(
          normalized,
          to: reference,
          extent: referenceExtent,
          isCancelled: isCancelled
        ) else {
          guard !isCancelled() else { return nil }
          return fallback(.registrationRejected)
        }
        maximumTranslation = max(maximumTranslation, registered.maximumDisplacement)
        aligned.append(registered.image)
        alignmentModels.append(registered.model)
      }
      guard aligned.count == Self.fusionFrameCount,
            let median = kernel.apply(extent: referenceExtent, arguments: aligned) else {
        return fallback(.renderOrEncodeFailure)
      }
      guard !isCancelled() else { return nil }

      // Registration creates undefined pixels at the outside edge. Preserve
      // those pixels verbatim from the sharpest capture instead of letting a
      // shifted transparent edge enter the median.
      let safetyInset = ceil(max(2, maximumTranslation + 2))
      let interior = referenceExtent.insetBy(dx: safetyInset, dy: safetyInset)
      guard interior.width > 0, interior.height > 0 else { return fallback(.incompatibleGeometry) }
      let mask = CIImage(color: .white).cropped(to: interior)
      guard let fused = CIFilter(
        name: "CIBlendWithMask",
        parameters: [
          kCIInputImageKey: median,
          kCIInputBackgroundImageKey: reference,
          kCIInputMaskImageKey: mask,
        ]
      )?.outputImage?.cropped(to: referenceExtent),
      let fusedCG = context.createCGImage(fused, from: referenceExtent) else {
        return fallback(.renderOrEncodeFailure)
      }
      guard !isCancelled() else { return nil }
      guard let jpeg = encode(fusedCG),
            let fingerprint = fingerprint(for: fusedCG) else {
        return fallback(.renderOrEncodeFailure)
      }

      return ScannerBurstResolution(
        candidate: ScannerProcessedCandidate(
          jpeg: jpeg,
          sharpness: sharpness(of: fusedCG),
          coverage: best.coverage,
          fingerprint: fingerprint,
          correctedImage: fusedCG
        ),
        mode: .alignedMedianFusion,
        framesConsidered: candidates.count,
        framesUsed: Self.fusionFrameCount,
        fallbackReason: nil,
        alignmentModels: alignmentModels
      )
    }
  }

  private func encode(_ image: CGImage) -> Data? {
    // A page must fit inside the portal's bounded PDF request on its own.
    // Reduce JPEG quality only when necessary, keeping the original pixels.
    var encoded: Data?
    for quality in [0.92, 0.86, 0.78, 0.68] {
      let data = NSMutableData()
      guard let destination = CGImageDestinationCreateWithData(
        data,
        UTType.jpeg.identifier as CFString,
        1,
        nil
      ) else { return nil }
      CGImageDestinationAddImage(destination, image, [
        kCGImageDestinationLossyCompressionQuality: quality,
      ] as CFDictionary)
      guard CGImageDestinationFinalize(destination) else { return nil }
      encoded = data as Data
      if data.length <= Self.maximumEncodedBytes { break }
    }
    guard let encoded, !encoded.isEmpty, encoded.count <= Self.maximumEncodedBytes else { return nil }
    return encoded
  }

  private func dimensionsAreCompatible(_ image: CGImage, _ reference: CGImage) -> Bool {
    let imageRatio = CGFloat(image.width) / CGFloat(image.height)
    let referenceRatio = CGFloat(reference.width) / CGFloat(reference.height)
    return imageRatio.isFinite && referenceRatio.isFinite
      && abs(imageRatio / referenceRatio - 1) <= 0.025
  }

  private func normalizedImage(_ image: CGImage, to extent: CGRect) -> CIImage {
    let source = CIImage(cgImage: image)
    let normalized = source.transformed(by: CGAffineTransform(
      scaleX: extent.width / source.extent.width,
      y: extent.height / source.extent.height
    ))
    return normalized.transformed(by: CGAffineTransform(
      translationX: -normalized.extent.origin.x,
      y: -normalized.extent.origin.y
    )).cropped(to: extent)
  }

  private func registeredImage(
    _ floating: CIImage,
    to reference: CIImage,
    extent: CGRect,
    isCancelled: () -> Bool
  ) -> (image: CIImage, maximumDisplacement: CGFloat, model: ScannerBurstAlignmentModel)? {
    guard !isCancelled() else { return nil }
    let scale = min(1, Self.registrationMaximumEdge / max(extent.width, extent.height))
    let registrationExtent = CGRect(
      x: 0,
      y: 0,
      width: extent.width * scale,
      height: extent.height * scale
    )
    let smallFloating = floating.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
      .cropped(to: registrationExtent)
    let smallReference = reference.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
      .cropped(to: registrationExtent)

    // Vision treats the targeted image as the floating image and the image
    // supplied to the request handler as the fixed reference image.
    let translationRequest = VNTranslationalImageRegistrationRequest(
      targetedCIImage: smallFloating,
      options: [:]
    )
    let handler = VNImageRequestHandler(ciImage: smallReference, options: [:])
    guard (try? handler.perform([translationRequest])) != nil else { return nil }
    guard !isCancelled() else { return nil }

    // Prefer the least expressive model that passes the high-resolution
    // agreement gate. This prevents a homography from fitting sensor noise and
    // slightly warping otherwise translation-only text.
    if let transform = translationRequest.results?.first?.alignmentTransform,
       transform.a.isFinite, transform.b.isFinite,
       transform.c.isFinite, transform.d.isFinite,
       transform.tx.isFinite, transform.ty.isFinite,
       abs(transform.a - 1) < 0.001, abs(transform.d - 1) < 0.001,
       abs(transform.b) < 0.001, abs(transform.c) < 0.001 {
      let fullTransform = CGAffineTransform(
        translationX: transform.tx / scale,
        y: transform.ty / scale
      )
      if abs(fullTransform.tx) <= extent.width * 0.03,
         abs(fullTransform.ty) <= extent.height * 0.03 {
        let translated = floating.transformed(by: fullTransform).cropped(to: extent)
        if framesAgree(reference, translated, extent: extent) {
          return (
            translated,
            max(abs(fullTransform.tx), abs(fullTransform.ty)),
            .translation
          )
        }
      }
    }

    let homographyRequest = VNHomographicImageRegistrationRequest(
      targetedCIImage: smallFloating,
      options: [:]
    )
    let homographyHandler = VNImageRequestHandler(ciImage: smallReference, options: [:])
    guard (try? homographyHandler.perform([homographyRequest])) != nil,
          let observation = homographyRequest.results?.first else { return nil }
    guard !isCancelled() else { return nil }
    let matrix = observation.warpTransform
    let sourceCorners = [
      CGPoint(x: extent.minX, y: extent.maxY),
      CGPoint(x: extent.maxX, y: extent.maxY),
      CGPoint(x: extent.maxX, y: extent.minY),
      CGPoint(x: extent.minX, y: extent.minY),
    ]
    guard let destinationCorners = transformedCorners(
      sourceCorners,
      matrix: matrix,
      registrationScale: scale
    ), homographyIsSafe(from: sourceCorners, to: destinationCorners, extent: extent) else {
      return nil
    }
    let transformed = floating.applyingFilter("CIPerspectiveTransform", parameters: [
      "inputTopLeft": CIVector(cgPoint: destinationCorners[0]),
      "inputTopRight": CIVector(cgPoint: destinationCorners[1]),
      "inputBottomRight": CIVector(cgPoint: destinationCorners[2]),
      "inputBottomLeft": CIVector(cgPoint: destinationCorners[3]),
    ]).cropped(to: extent)
    let maximumDisplacement = zip(sourceCorners, destinationCorners).reduce(CGFloat.zero) {
      max($0, abs($1.0.x - $1.1.x), abs($1.0.y - $1.1.y))
    }
    guard framesAgree(reference, transformed, extent: extent) else { return nil }
    return (transformed, maximumDisplacement, .homography)
  }

  private func transformedCorners(
    _ corners: [CGPoint],
    matrix: simd_float3x3,
    registrationScale: CGFloat
  ) -> [CGPoint]? {
    let transformed = corners.map { point -> CGPoint in
      let source = SIMD3<Float>(
        Float(point.x * registrationScale),
        Float(point.y * registrationScale),
        1
      )
      let destination = matrix * source
      let denominator = CGFloat(destination.z)
      guard denominator.isFinite, abs(denominator) > 0.0001 else {
        return CGPoint(x: CGFloat.nan, y: CGFloat.nan)
      }
      return CGPoint(
        x: CGFloat(destination.x) / denominator / registrationScale,
        y: CGFloat(destination.y) / denominator / registrationScale
      )
    }
    return transformed.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) ? transformed : nil
  }

  private func homographyIsSafe(
    from source: [CGPoint],
    to destination: [CGPoint],
    extent: CGRect
  ) -> Bool {
    guard source.count == 4, destination.count == 4 else { return false }
    let displacements = zip(source, destination).map {
      CGPoint(x: $1.x - $0.x, y: $1.y - $0.y)
    }
    let mean = displacements.reduce(CGPoint.zero) {
      CGPoint(x: $0.x + $1.x / 4, y: $0.y + $1.y / 4)
    }
    guard abs(mean.x) <= extent.width * 0.03,
          abs(mean.y) <= extent.height * 0.03 else { return false }
    let residualLimit = max(extent.width, extent.height) * 0.018
    guard displacements.allSatisfy({ hypot($0.x - mean.x, $0.y - mean.y) <= residualLimit }) else {
      return false
    }
    let sourceArea = extent.width * extent.height
    let destinationArea = abs(zip(destination, destination.dropFirst() + destination.prefix(1)).reduce(0) {
      $0 + $1.0.x * $1.1.y - $1.1.x * $1.0.y
    }) / 2
    guard destinationArea / sourceArea >= 0.94, destinationArea / sourceArea <= 1.06 else {
      return false
    }
    let top = CGPoint(
      x: destination[1].x - destination[0].x,
      y: destination[1].y - destination[0].y
    )
    return abs(atan2(top.y, top.x)) <= 1.5 * .pi / 180
  }

  private func framesAgree(_ reference: CIImage, _ floating: CIImage, extent: CGRect) -> Bool {
    guard let referencePixels = agreementThumbnail(reference, extent: extent),
          let floatingPixels = agreementThumbnail(floating, extent: extent),
          referencePixels.width == floatingPixels.width,
          referencePixels.height == floatingPixels.height else { return false }
    let width = referencePixels.width
    let height = referencePixels.height
    let border = max(4, Int(CGFloat(min(width, height)) * 0.05))
    var referenceMean = 0.0
    var floatingMean = 0.0
    var count = 0.0
    for y in border..<(height - border) {
      for x in border..<(width - border) {
        let index = y * width + x
        referenceMean += Double(referencePixels.pixels[index])
        floatingMean += Double(floatingPixels.pixels[index])
        count += 1
      }
    }
    guard count > 0 else { return false }
    referenceMean /= count
    floatingMean /= count

    var covariance = 0.0
    var referenceVariance = 0.0
    var floatingVariance = 0.0
    var residual = 0.0
    var severeResiduals = 0
    let exposureDelta = floatingMean - referenceMean
    for y in border..<(height - border) {
      for x in border..<(width - border) {
        let index = y * width + x
        let referenceValue = Double(referencePixels.pixels[index])
        let floatingValue = Double(floatingPixels.pixels[index])
        let centeredReference = referenceValue - referenceMean
        let centeredFloating = floatingValue - floatingMean
        covariance += centeredReference * centeredFloating
        referenceVariance += centeredReference * centeredReference
        floatingVariance += centeredFloating * centeredFloating
        let difference = abs((floatingValue - exposureDelta) - referenceValue)
        residual += difference
        if difference > 36 { severeResiduals += 1 }
      }
    }
    guard referenceVariance > 1, floatingVariance > 1 else { return false }
    let correlation = covariance / sqrt(referenceVariance * floatingVariance)
    let meanResidual = residual / count
    let severeFraction = Double(severeResiduals) / count
    guard correlation >= 0.91, meanResidual <= 15, severeFraction <= 0.14 else {
      return false
    }
    return localizedTilesAgree(
      referencePixels.pixels,
      floatingPixels.pixels,
      width: width,
      height: height,
      exposureDelta: exposureDelta
    )
  }

  private func localizedTilesAgree(
    _ reference: [UInt8],
    _ floating: [UInt8],
    width: Int,
    height: Int,
    exposureDelta: Double
  ) -> Bool {
    let tileSide = max(48, min(width, height) / 7)
    let margin = max(4, Int(CGFloat(min(width, height)) * 0.08))
    for originY in stride(from: margin, to: height - margin, by: tileSide) {
      for originX in stride(from: margin, to: width - margin, by: tileSide) {
        let maximumX = min(originX + tileSide, width - margin)
        let maximumY = min(originY + tileSide, height - margin)
        var referenceMean = 0.0
        var floatingMean = 0.0
        var count = 0.0
        for y in originY..<maximumY {
          for x in originX..<maximumX {
            let index = y * width + x
            referenceMean += Double(reference[index])
            floatingMean += Double(floating[index])
            count += 1
          }
        }
        guard count > 0 else { continue }
        referenceMean /= count
        floatingMean /= count
        var covariance = 0.0
        var referenceVariance = 0.0
        var floatingVariance = 0.0
        var residual = 0.0
        var severe = 0
        for y in originY..<maximumY {
          for x in originX..<maximumX {
            let index = y * width + x
            let referenceValue = Double(reference[index])
            let floatingValue = Double(floating[index])
            let centeredReference = referenceValue - referenceMean
            let centeredFloating = floatingValue - floatingMean
            covariance += centeredReference * centeredFloating
            referenceVariance += centeredReference * centeredReference
            floatingVariance += centeredFloating * centeredFloating
            let difference = abs((floatingValue - exposureDelta) - referenceValue)
            residual += difference
            if difference > 36 { severe += 1 }
          }
        }
        // Uniform paper and margins carry no fine detail to protect.
        guard referenceVariance / count >= 40, floatingVariance / count >= 40 else { continue }
        let correlation = covariance / sqrt(referenceVariance * floatingVariance)
        let meanResidual = residual / count
        let severeFraction = Double(severe) / count
        guard correlation >= 0.70, meanResidual <= 22, severeFraction <= 0.25 else {
          return false
        }
      }
    }
    return true
  }

  private func agreementThumbnail(
    _ image: CIImage,
    extent: CGRect
  ) -> (pixels: [UInt8], width: Int, height: Int)? {
    let scale = min(1, Self.agreementMaximumEdge / max(extent.width, extent.height))
    let width = max(1, Int((extent.width * scale).rounded()))
    let height = max(1, Int((extent.height * scale).rounded()))
    let scaled = image.transformed(by: CGAffineTransform(
      scaleX: CGFloat(width) / extent.width,
      y: CGFloat(height) / extent.height
    ))
    let scaledExtent = CGRect(x: 0, y: 0, width: width, height: height)
    guard let cgImage = context.createCGImage(scaled, from: scaledExtent) else { return nil }
    guard let pixels = thumbnailBytes(for: cgImage, width: width, height: height) else { return nil }
    return (pixels, width, height)
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
