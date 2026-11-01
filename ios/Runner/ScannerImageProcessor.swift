import CoreImage
import ImageIO
import UniformTypeIdentifiers
import Vision

final class ScannerImageProcessor {
  private static let maximumEncodedBytes = 2_650_000
  private static let fusionFrameCount = 3
  // Keep the in-progress view gate and the final burst gate on the same
  // relative scale. A frame may be softer than the best frame by this amount
  // because the final lighting/fusion pass can still use it safely.
  static let relativeSharpnessDrop = log(1.8)
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

  enum ViewQualityAssessment: Equatable {
    case accepted
    case retakeCurrentView
    case restartForEarlierSoftView
    case invalidImage
  }

  enum PhotoProcessingFailure: String, Error {
    case invalidPhoto
    case photoTooSoft
    case documentBoundaryNotFound
    case perspectiveCorrectionFailed
    case renderFailed
    case encodingFailed
    case fingerprintFailed
  }

  /// Checks a newly processed view against the views already accepted for the
  /// current burst. This intentionally has no absolute sharpness floor: the
  /// final burst resolver uses the same relative log-sharpness policy, and a
  /// document's scale/print density can vary between devices.
  static func assessViewQuality(
    accepted: [ScannerProcessedCandidate],
    candidate: ScannerProcessedCandidate?
  ) -> ViewQualityAssessment {
    guard let candidate,
          candidate.sharpness.isFinite,
          accepted.allSatisfy({ $0.sharpness.isFinite }) else {
      return .invalidImage
    }
    guard let previousBest = accepted.map(\.sharpness).max() else {
      return .accepted
    }
    let minimum = previousBest - relativeSharpnessDrop
    if candidate.sharpness < minimum {
      return .retakeCurrentView
    }
    let newBest = max(previousBest, candidate.sharpness)
    if accepted.contains(where: { $0.sharpness < newBest - relativeSharpnessDrop }) {
      return .restartForEarlierSoftView
    }
    return .accepted
  }

  /// Drops a clearly weaker early view before adaptive capture tries a burst.
  /// The final resolver remains the authority on geometry and lighting; this
  /// only prevents one soft frame from poisoning every later three-view set.
  static func retainingUsefulViews(
    _ candidates: [ScannerProcessedCandidate],
    maximumCount: Int = 6
  ) -> [ScannerProcessedCandidate] {
    guard maximumCount > 0 else { return [] }
    let limit = min(maximumCount, ScannerAdaptiveCaptureGuide.maximumCandidates)
    let finite = candidates.enumerated().filter { $0.element.sharpness.isFinite }
    guard !finite.isEmpty else { return [] }
    let best = finite.map(\.element.sharpness).max()!
    // It is better to ask for another clear view than to retain a known soft
    // frame merely to reach the minimum number needed by the median.
    let useful = finite.filter { $0.element.sharpness >= best - relativeSharpnessDrop }
    var selected = Array(useful.sorted {
      if abs($0.element.sharpness - $1.element.sharpness) > 0.0001 {
        return $0.element.sharpness > $1.element.sharpness
      }
      return $0.offset > $1.offset
    }.prefix(limit))
    // Preserve the latest useful view when trimming a larger pool.
    if let latest = useful.max(by: { $0.offset < $1.offset }),
       !selected.contains(where: { $0.offset == latest.offset }) {
      selected[selected.count - 1] = latest
    }
    return selected.sorted { $0.offset < $1.offset }.map(\.element)
  }

  /// Tries bounded combinations of useful views, preferring combinations
  /// containing the newest useful view. Existing registration, sharpness, and
  /// lighting gates remain unchanged because every attempt delegates to
  /// resolveBurst.
  func resolveAdaptiveCapture(
    _ candidates: [ScannerProcessedCandidate],
    profile: FoorsaScannerProfile? = nil,
    isCancelled: () -> Bool = { false }
  ) -> ScannerBurstResolution? {
    let pool = Self.retainingUsefulViews(candidates)
    guard pool.count >= Self.fusionFrameCount else { return nil }
    var combinations: [(indices: [Int], score: Double, newest: Bool)] = []
    func appendCombinations(_ count: Int, from start: Int, prefix: [Int]) {
      if prefix.count == count {
        let score = prefix.reduce(0) { $0 + pool[$1].sharpness } / Double(count)
        combinations.append((prefix, score, prefix.last == pool.count - 1))
        return
      }
      let remaining = count - prefix.count
      guard start <= pool.count - remaining else { return }
      for index in start...(pool.count - remaining) {
        appendCombinations(count, from: index + 1, prefix: prefix + [index])
      }
    }
    for count in Self.fusionFrameCount...pool.count {
      appendCombinations(count, from: 0, prefix: [])
    }
    combinations.sort {
      if $0.indices.count != $1.indices.count { return $0.indices.count > $1.indices.count }
      if $0.newest != $1.newest { return $0.newest }
      if abs($0.score - $1.score) > 0.0001 { return $0.score > $1.score }
      return $0.indices.lexicographicallyPrecedes($1.indices)
    }
    var bestFallback: (resolution: ScannerBurstResolution, rank: Int, score: Double)?
    // Six retained views produce at most 42 subsets of three or more. Larger
    // compatible sets can supply a fourth or later donor when three views do
    // not cover every observed obstruction. Deadlines still cancel the search.
    for combination in combinations {
      guard !isCancelled() else { return nil }
      let subset = combination.indices.map { pool[$0] }
      guard let resolution = resolveBurst(subset, profile: profile, isCancelled: isCancelled) else {
        guard !isCancelled() else { return nil }
        continue
      }
      let isSafeFusion = resolution.mode != .bestFrameFallback
        && !(resolution.lighting?.needsDifferentAngle ?? false)
      if isSafeFusion { return resolution }
      let rank: Int
      switch resolution.fallbackReason {
      case nil where resolution.lighting?.needsDifferentAngle == true: rank = 4
      case .registrationRejected, .frameContentMismatch: rank = 3
      case .frameTooSoft: rank = 2
      case .missingCorrectedImage, .incompatibleGeometry: rank = 1
      default: rank = 0
      }
      if bestFallback == nil || rank > bestFallback!.rank
        || (rank == bestFallback!.rank && combination.score > bestFallback!.score) {
        bestFallback = (resolution, rank, combination.score)
      }
    }
    guard !isCancelled() else { return nil }
    return bestFallback?.resolution
  }

  func process(photoData: Data, profile: FoorsaScannerProfile) -> ScannerProcessedCandidate? {
    try? processCapture(photoData: photoData, profile: profile).get()
  }

  // Keep capture failures distinct from lighting/fusion failures. A missing
  // boundary does not establish that the user's light is the problem.
  //
  // custom-live-v11 uses one policy for every capture mode: severe blur is
  // rejected before and after cropping; the crop is the strict boundary, else
  // the document model on this photo anchored to the live outline, else the
  // live outline the student saw when the shutter fired. Only a photo taken
  // by hand without any outline may keep the whole frame.
  func processCapture(photoData: Data, profile: FoorsaScannerProfile,
                      liveQuadrilateral: ScannerQuadrilateral? = nil,
                      liveImageSize: CGSize? = nil,
                      allowFullFrame: Bool = false)
    -> Result<ScannerProcessedCandidate, PhotoProcessingFailure> {
    autoreleasepool {
      guard let source = CIImage(data: photoData, options: [.applyOrientationProperty: true]) else {
        return .failure(.invalidPhoto)
      }
      let upright = source.transformed(by: CGAffineTransform(
        translationX: -source.extent.origin.x,
        y: -source.extent.origin.y
      ))
      let sourceClarity = ContentClarity.score(upright)
      guard sourceClarity.support < 24 || sourceClarity.q50 >= 0.35 else { return .failure(.photoTooSoft) }
      // One Vision pass serves both the strict cascade and the model fallback.
      let vision = ScannerVisionFrameCache()
      let observation = try? ScannerRectangleDetector.detect(
        in: upright, profile: profile, purpose: .still, cache: vision
      )
      let extent = upright.extent
      let detected = observation.map { ScannerQuadrilateral(
        topLeft: $0.topLeft, topRight: $0.topRight,
        bottomRight: $0.bottomRight, bottomLeft: $0.bottomLeft
      ) }
      // Live geometry belongs to the actual shutter event. The .photo session
      // shares its centered sensor field with the still; account for any aspect
      // crop before projecting its normalized corners into source pixels.
      let projected = liveQuadrilateral.flatMap { quad in
        liveImageSize.flatMap { ScannerLivePhotoCrop.map(quad, liveSize: $0,
          photoSize: extent.size, minimumArea: profile.minimumCaptureArea) }
      }
      // The strict cascade rejects most hand-held pages (it needs a plain
      // background at every edge). The document model on the photo itself is
      // more precise than the projected live outline, and must agree with it.
      let model = detected == nil
        ? ScannerRectangleDetector.stillDocumentModel(in: upright, profile: profile, near: projected,
          allowUnanchored: allowFullFrame, cache: vision) : nil
      // Only a photo taken by hand without any outline keeps the whole frame.
      let wholeFrame = allowFullFrame ? ScannerQuadrilateral.fullFrame : nil
      // A passport photographed open keeps both pages: the photo page the cascade found and the
      // page facing it, which carries the passport number (ScannerPassportBooklet).
      let booklet = profile.layout == .passport ? detected.flatMap {
        ScannerRectangleDetector.openPassportBooklet(in: upright, around: $0, profile: profile, cache: vision)
      } : nil
      guard let quad = booklet ?? detected ?? model ?? projected ?? wholeFrame else {
        return .failure(.documentBoundaryNotFound)
      }
      func vector(_ point: CGPoint) -> CIVector {
        CIVector(x: extent.minX + point.x * extent.width,
                 y: extent.minY + point.y * extent.height)
      }
      let perspective = CIFilter(
        name: "CIPerspectiveCorrection",
        parameters: [
          kCIInputImageKey: upright,
          "inputTopLeft": vector(quad.topLeft),
          "inputTopRight": vector(quad.topRight),
          "inputBottomRight": vector(quad.bottomRight),
          "inputBottomLeft": vector(quad.bottomLeft),
        ]
      )?.outputImage
      // A source-pixel bounding crop is a last resort for a render/filter
      // failure. It contains every captured corner and never paints the guide.
      let fallbackBounds = CGRect(
        x: quad.points.map(\.x).min()! * extent.width,
        y: quad.points.map(\.y).min()! * extent.height,
        width: (quad.points.map(\.x).max()! - quad.points.map(\.x).min()!) * extent.width,
        height: (quad.points.map(\.y).max()! - quad.points.map(\.y).min()!) * extent.height
      ).insetBy(dx: -extent.width * 0.015, dy: -extent.height * 0.015).intersection(extent)
      let sourceCrop: CIImage? = upright.cropped(to: fallbackBounds)
      guard let corrected = perspective ?? sourceCrop else { return .failure(.perspectiveCorrectionFailed) }
      let bounded = resized(corrected, maximumEdge: 2600)
      let rendered = context.createCGImage(bounded, from: bounded.extent)
      let fallbackRendered = rendered == nil ? sourceCrop.flatMap { crop -> CGImage? in
        let boundedCrop = resized(crop, maximumEdge: 2600)
        return context.createCGImage(boundedCrop, from: boundedCrop.extent)
      } : nil
      guard let cgImage = rendered ?? fallbackRendered else { return .failure(.renderFailed) }
      let image = CIImage(cgImage: cgImage)
      var clarity = ContentClarity.score(image)
      if clarity.support < 24 {
        var configuration = ContentClarity.Configuration()
        configuration.horizontalInset = 0.08
        configuration.verticalInset = 0.08
        clarity = ContentClarity.score(image, configuration: configuration)
      }
      guard clarity.support >= 24, clarity.q50 >= 0.35 else { return .failure(.photoTooSoft) }
      guard let jpeg = encode(cgImage) else { return .failure(.encodingFailed) }
      guard let fingerprint = fingerprint(for: cgImage) else { return .failure(.fingerprintFailed) }
      return .success(ScannerProcessedCandidate(
        jpeg: jpeg,
        sharpness: sharpness(of: cgImage),
        coverage: Double(quad.area),
        fingerprint: fingerprint,
        correctedImage: cgImage
      ))
    }
  }

  func resolveBurst(
    _ candidates: [ScannerProcessedCandidate],
    profile: FoorsaScannerProfile? = nil,
    isCancelled: () -> Bool = { false }
  ) -> ScannerBurstResolution? {
    autoreleasepool {
      guard !isCancelled() else { return nil }
      guard let sharpestIndex = ScannerCandidateSelector.bestIndex(candidates) else { return nil }
      var referenceIndex = sharpestIndex
      // An extra viewpoint can itself be the cleanest complete capture. Prefer
      // that real image for fallback too, rather than discarding it when a
      // curved page cannot be registered safely to the initial burst.
      if candidates.count >= Self.fusionFrameCount,
         let sharpestImage = candidates[sharpestIndex].correctedImage {
        let lighting = ScannerDocumentLighting()
        var bestScore = lighting.obstructionScore(sharpestImage)
        for index in candidates.indices where index != sharpestIndex {
          guard !isCancelled() else { return nil }
          guard candidates[index].sharpness >= candidates[sharpestIndex].sharpness - 0.20,
                let image = candidates[index].correctedImage else { continue }
          let score = lighting.obstructionScore(image)
          if score + 0.01 < bestScore {
            referenceIndex = index
            bestScore = score
          }
        }
      }
      let best = candidates[referenceIndex]
      func fallback(_ reason: ScannerBurstFallbackReason) -> ScannerBurstResolution? {
        let resolution = ScannerBurstResolution(
          candidate: best,
          mode: .bestFrameFallback,
          framesConsidered: candidates.count,
          framesUsed: 1,
          fallbackReason: reason,
          alignmentModels: []
        )
        return self.finishLighting(resolution, profile: profile, isCancelled: isCancelled)
      }
      guard (Self.fusionFrameCount...ScannerAdaptiveCaptureGuide.maximumCandidates).contains(candidates.count) else {
        return fallback(.incompleteBurst)
      }
      guard let referenceCG = best.correctedImage else { return fallback(.missingCorrectedImage) }
      guard let kernel = Self.temporalMedianKernel else { return fallback(.renderOrEncodeFailure) }

      // Perspective correction has already put each page in document space.
      // Normalize the small crop-size variation, then register residual hand
      // motion. A substantially softer frame can only reduce document detail.
      let minimumSharpness = candidates[sharpestIndex].sharpness - Self.relativeSharpnessDrop
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
          allowLightingDifference: profile != nil,
          isCancelled: isCancelled
        ) else {
          guard !isCancelled() else { return nil }
          return fallback(.registrationRejected)
        }
        maximumTranslation = max(maximumTranslation, registered.maximumDisplacement)
        aligned.append(registered.image)
        alignmentModels.append(registered.model)
      }
      guard aligned.count >= Self.fusionFrameCount,
            let median = kernel.apply(extent: referenceExtent, arguments: Array(aligned.prefix(3))) else {
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

      let resolution = ScannerBurstResolution(
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
      guard let profile else { return resolution }
      return finishLighting(resolution, profile: profile, aligned: aligned,
        reference: reference, safeInterior: interior, isCancelled: isCancelled)
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

  // Lighting is separate from geometric fusion. A shadow is a slowly varying
  // exposure change; a reflection may conceal real content and needs another
  // capture. Neither operation draws letters, faces, or security patterns.
  private func finishLighting(
    _ resolution: ScannerBurstResolution,
    profile: FoorsaScannerProfile?,
    aligned: [CIImage] = [],
    reference: CIImage? = nil,
    safeInterior: CGRect? = nil,
    isCancelled: () -> Bool
  ) -> ScannerBurstResolution? {
    guard profile != nil, let original = resolution.candidate.correctedImage else { return resolution }
    guard !isCancelled() else { return nil }
    let lighting = ScannerDocumentLighting()
    var source = original
    var replaced = 0.0
    var lifted = false
    var used = resolution.framesUsed
    // Replace a reflection only with a complete RGB sample from a geometrically
    // verified source. Keep the ordinary temporal median everywhere else.
    var unresolved = 0.0
    if aligned.count >= 3, let reference, let safeInterior {
      if let composite = lighting.combineLighting(
          base: original, aligned: aligned, reference: reference,
          safeInterior: safeInterior, context: context, isCancelled: isCancelled
         ) {
        source = composite.image
        replaced = composite.glareFraction
        lifted = composite.shadowLifted
        unresolved = composite.unresolvedObstructionFraction
        if replaced > 0 || lifted { used = composite.framesUsed }
      } else {
        guard !isCancelled() else { return nil }
        // A failed comparison must not certify a view as unobstructed.
        unresolved = 0.0015
      }
    }
    guard !isCancelled() else { return nil }
    // A clipped white print can look like glare in one image. After a verified
    // three-view sequence, request a retry only for obstruction that actually
    // moved between those registered views and could not be safely recovered.
    // Single-frame glare remains diagnostic on a fallback, which the capture
    // controller handles separately from final image acceptance.
    let diagnosticGlare = lighting.glareFraction(source)
    if aligned.isEmpty { unresolved = diagnosticGlare }
    let summary = ScannerLightingSummary(
      shadowCorrectionApplied: lifted,
      glarePixelsReplacedFraction: replaced,
      unresolvedGlareFraction: unresolved,
      needsDifferentAngle: unresolved >= 0.0015
    )
    guard !isCancelled() else { return nil }
    if !lifted && replaced == 0 {
      var unchanged = resolution
      unchanged.lighting = summary
      return unchanged
    }
    guard let jpeg = encode(source), let fingerprint = fingerprint(for: source) else {
      var unchanged = resolution
      let originalGlare = lighting.glareFraction(original)
      unchanged.lighting = ScannerLightingSummary(
        shadowCorrectionApplied: false, glarePixelsReplacedFraction: 0,
        unresolvedGlareFraction: originalGlare,
        needsDifferentAngle: aligned.isEmpty && originalGlare >= 0.0015
      )
      return unchanged
    }
    return ScannerBurstResolution(
      candidate: ScannerProcessedCandidate(
        jpeg: jpeg, sharpness: sharpness(of: source),
        coverage: resolution.candidate.coverage, fingerprint: fingerprint,
        correctedImage: source
      ),
      mode: replaced > 0 || lifted ? .alignedLightingFusion : resolution.mode,
      framesConsidered: resolution.framesConsidered, framesUsed: used,
      fallbackReason: resolution.fallbackReason,
      alignmentModels: resolution.alignmentModels,
      lighting: summary
    )
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
    allowLightingDifference: Bool = false,
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
        if framesAgree(reference, translated, extent: extent)
          || (allowLightingDifference && lightingEdgesAgree(reference, translated, extent: extent)) {
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
    guard framesAgree(reference, transformed, extent: extent)
      || (allowLightingDifference && lightingEdgesAgree(reference, transformed, extent: extent)) else { return nil }
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

  // Spatial lighting changes are the point of another viewpoint. Compare
  // locally normalized stroke gradients instead of relaxing the original raw
  // luminance gate. A misplaced line of fine text still rejects the whole donor.
  private func lightingEdgesAgree(_ reference: CIImage, _ floating: CIImage, extent: CGRect) -> Bool {
    guard let a = agreementThumbnail(reference, extent: extent),
          let b = agreementThumbnail(floating, extent: extent),
          let colorA = agreementColorThumbnail(reference, extent: extent),
          let colorB = agreementColorThumbnail(floating, extent: extent),
          a.width == b.width, a.height == b.height,
          colorA.width == a.width, colorA.height == a.height,
          colorB.width == a.width, colorB.height == a.height else { return false }
    let width = a.width, height = a.height
    guard width >= 64, height >= 64 else { return false }
    func localMeans(_ pixels: [UInt8]) -> [Double] {
      let stride = width + 1
      var integral = [Double](repeating: 0, count: stride * (height + 1))
      for y in 0..<height {
        var row = 0.0
        for x in 0..<width {
          row += Double(pixels[y * width + x])
          integral[(y + 1) * stride + x + 1] = integral[y * stride + x + 1] + row
        }
      }
      var values = [Double](repeating: 0, count: width * height)
      for y in 0..<height {
        for x in 0..<width {
          let x0 = max(0, x - 8), x1 = min(width, x + 9)
          let y0 = max(0, y - 8), y1 = min(height, y + 9)
          let sum = integral[y1 * stride + x1] - integral[y0 * stride + x1]
            - integral[y1 * stride + x0] + integral[y0 * stride + x0]
          values[y * width + x] = sum / Double((x1 - x0) * (y1 - y0))
        }
      }
      return values
    }
    let meansA = localMeans(a.pixels), meansB = localMeans(b.pixels)
    func chromaDistance(_ index: Int) -> Double {
      let i = index * 4
      let sumA = Double(colorA.pixels[i]) + Double(colorA.pixels[i + 1])
        + Double(colorA.pixels[i + 2]) + 48
      let sumB = Double(colorB.pixels[i]) + Double(colorB.pixels[i + 1])
        + Double(colorB.pixels[i + 2]) + 48
      var distance = 0.0
      for channel in 0..<3 {
        distance += abs((Double(colorA.pixels[i + channel]) + 16) / sumA
          - (Double(colorB.pixels[i + channel]) + 16) / sumB)
      }
      return distance
    }
    let margin = max(5, min(width, height) * 8 / 100)
    let tile = max(48, min(width, height) / 7)
    var informative = 0
    for y0 in stride(from: margin, to: height - margin, by: tile) {
      for x0 in stride(from: margin, to: width - margin, by: tile) {
        var dot = 0.0, energyA = 0.0, energyB = 0.0
        var valid = 0, total = 0
        for y in y0..<min(y0 + tile, height - margin) {
          for x in x0..<min(x0 + tile, width - margin) {
            let index = y * width + x
            total += 1
            let valueA = Double(a.pixels[index]), valueB = Double(b.pixels[index])
            // A small clipped patch cannot establish correspondence; require
            // the remaining majority of each tile to agree independently.
            if (valueA > 240 && valueA - meansA[index] > 18)
              || (valueB > 240 && valueB - meansB[index] > 18)
              || chromaDistance(index) >= 0.105 { continue }
            valid += 1
            let ax = Double(Int(a.pixels[index + 1]) - Int(a.pixels[index - 1])) / (meansA[index] + 20)
            let ay = Double(Int(a.pixels[index + width]) - Int(a.pixels[index - width])) / (meansA[index] + 20)
            let bx = Double(Int(b.pixels[index + 1]) - Int(b.pixels[index - 1])) / (meansB[index] + 20)
            let by = Double(Int(b.pixels[index + width]) - Int(b.pixels[index - width])) / (meansB[index] + 20)
            dot += ax * bx + ay * by
            energyA += ax * ax + ay * ay
            energyB += bx * bx + by * by
          }
        }
        guard valid >= max(1, total * 80 / 100) else { return false }
        if max(energyA, energyB) / Double(valid) < 0.0008 { continue }
        guard min(energyA, energyB) / Double(valid) >= 0.0004 else { return false }
        guard dot / sqrt(energyA * energyB) >= 0.90 else { return false }
        informative += 1
      }
    }
    return informative >= 6
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

  private func agreementColorThumbnail(
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
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let made = pixels.withUnsafeMutableBytes { buffer -> Bool in
      guard let drawing = CGContext(
        data: buffer.baseAddress, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          | CGBitmapInfo.byteOrder32Big.rawValue
      ) else { return false }
      drawing.interpolationQuality = .medium
      drawing.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    return made ? (pixels, width, height) : nil
  }

  private func resized(_ image: CIImage, maximumEdge: CGFloat) -> CIImage {
    let edge = max(image.extent.width, image.extent.height)
    guard edge > maximumEdge else { return image }
    let scale = maximumEdge / edge
    let origin = image.extent.origin
    let target = CGRect(x: 0, y: 0, width: (image.extent.width * scale).rounded(.down),
                        height: (image.extent.height * scale).rounded(.down))
    // Lanczos, not the default affine resample: iOS's default is a low-quality
    // filter that aliases one-pixel strokes, guilloche and passport MRZ edges
    // (macOS defaults to high quality, so the CI tests never saw it). The
    // input is clamped so the filter never pulls transparent pixels into the
    // page's border, and the result is cut back to whole pixels.
    return image
      .transformed(by: CGAffineTransform(translationX: -origin.x, y: -origin.y))
      .clampedToExtent()
      .applyingFilter("CILanczosScaleTransform", parameters: [
        kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1.0,
      ])
      .cropped(to: target)
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

// Coarse illumination measurements compare real views. They never brighten a
// single image: a printed gray area and a persistent shadow are indistinguishable
// without complementary captured evidence.
final class ScannerDocumentLighting {
  private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
  private let side = 384
  private let columns = 24

  private struct Raster {
    var pixels: [UInt8]
    let width: Int
    let height: Int
  }

  private struct Field {
    let values: [Double]
    let width: Int
    let height: Int
    let target: Double
    let reliable: Bool

    func value(x: Double, y: Double) -> Double {
      let u = max(0, min(Double(width - 1), x * Double(width) - 0.5))
      let v = max(0, min(Double(height - 1), y * Double(height) - 0.5))
      let x0 = Int(u), y0 = Int(v)
      let x1 = min(width - 1, x0 + 1), y1 = min(height - 1, y0 + 1)
      let a = u - Double(x0), b = v - Double(y0)
      return (values[y0 * width + x0] * (1 - a) + values[y0 * width + x1] * a) * (1 - b)
        + (values[y1 * width + x0] * (1 - a) + values[y1 * width + x1] * a) * b
    }
  }

  func hasUnevenLighting(_ image: CGImage) -> Bool {
    guard let small = raster(image, maximumEdge: side) else { return false }
    let field = illumination(small)
    guard field.reliable else { return false }
    return field.values.filter { field.target / max(0.25, $0) > 1.25 }.count > field.values.count / 12
  }

  func obstructionScore(_ image: CGImage) -> Double {
    guard let small = raster(image, maximumEdge: side) else { return 1 }
    let field = illumination(small)
    let glare = Double(glareMask(small).filter { $0 }.count) / Double(small.width * small.height)
    let shading = field.reliable ? field.values.reduce(0) {
      $0 + max(0, min(1, field.target / max(0.25, $1) - 1.15))
    } / Double(field.values.count) : 0
    return glare * 8 + shading * 0.25
  }

  func glareFraction(_ image: CGImage) -> Double {
    guard let small = raster(image, maximumEdge: side) else { return 0 }
    let mask = glareMask(small)
    return Double(mask.filter { $0 }.count) / Double(mask.count)
  }

  func combineLighting(
    base: CGImage, aligned: [CIImage], reference: CIImage,
    safeInterior: CGRect, context: CIContext, isCancelled: () -> Bool
  ) -> (image: CGImage, glareFraction: Double, unresolvedObstructionFraction: Double,
    shadowLifted: Bool, framesUsed: Int)? {
    guard var output = raster(base), let thumbnail = raster(base, maximumEdge: side) else { return nil }
    let baseMask = glareMask(thumbnail)
    let baseField = illumination(thumbnail)
    let extent = CGRect(x: 0, y: 0, width: base.width, height: base.height)
    let tileSide = 16
    let tilesX = (thumbnail.width + tileSide - 1) / tileSide
    let tilesY = (thumbnail.height + tileSide - 1) / tileSide
    let tileCount = tilesX * tilesY
    var scores = [Double](repeating: 0, count: tilesX * tilesY)
    var donors = [Int](repeating: -1, count: tileCount)
    var shadowTiles = [Bool](repeating: false, count: tileCount)
    var coloredTiles = [Bool](repeating: false, count: tileCount)
    var replacedPixels = [Bool](repeating: false, count: output.width * output.height)
    var unresolvedPixels = 0
    var usedFrames = Set(0..<min(3, aligned.count))
    var shadowLifted = false

    // Keep only bounded thumbnails while comparing views. Full-resolution
    // donors are rendered one at a time after a winning source is known.
    var smallViews: [Raster] = []
    var masks: [[Bool]] = []
    var fields: [Field] = []
    for image in aligned {
      guard !isCancelled(), let cg = context.createCGImage(image, from: extent),
            let small = raster(cg, maximumEdge: side),
            small.width == thumbnail.width, small.height == thumbnail.height else { return nil }
      smallViews.append(small)
      masks.append(glareMask(small))
      fields.append(illumination(small))
    }
    guard smallViews.count >= 3 else { return nil }

    var details = [[Double]](repeating: [Double](repeating: 0, count: tileCount),
      count: smallViews.count)
    var baseDetails = [Double](repeating: 0, count: tileCount)
    var colorMoves = [Bool](repeating: false, count: tileCount)
    var detailDrops = [Bool](repeating: false, count: tileCount)
    var glareMoves = [Bool](repeating: false, count: tileCount)
    var baseGlareCounts = [Int](repeating: 0, count: tileCount)
    var minimumGlareCounts = [Int](repeating: 0, count: tileCount)
    for ty in 0..<tilesY {
      for tx in 0..<tilesX {
        let tile = ty * tilesX + tx
        let x0 = tx * tileSide, x1 = min(thumbnail.width, x0 + tileSide)
        let y0 = ty * tileSide, y1 = min(thumbnail.height, y0 + tileSide)
        baseDetails[tile] = detailScore(thumbnail, x0: x0, x1: x1, y0: y0, y1: y1)
        for y in y0..<y1 {
          for x in x0..<x1 where baseMask[y * thumbnail.width + x] {
            baseGlareCounts[tile] += 1
          }
        }
        var glareCounts: [Int] = []
        for frame in smallViews.indices {
          details[frame][tile] = detailScore(smallViews[frame], x0: x0, x1: x1,
            y0: y0, y1: y1)
          var glareCount = 0
          for y in y0..<y1 {
            for x in x0..<x1 where masks[frame][y * thumbnail.width + x] {
              glareCount += 1
            }
          }
          glareCounts.append(glareCount)
        }
        let area = max(1, (x1 - x0) * (y1 - y0))
        var changed = 0
        for y in y0..<y1 {
          for x in x0..<x1 {
            let index = y * thumbnail.width + x
            var maximum = 0.0
            for first in 0..<(smallViews.count - 1) {
              for second in (first + 1)..<smallViews.count {
                maximum = max(maximum, chromaDistance(smallViews[first], smallViews[second], at: index))
              }
            }
            if maximum >= 0.105 { changed += 1 }
          }
        }
        colorMoves[tile] = changed >= max(8, area / 10)
        let tileDetails = details.map { $0[tile] }
        let lowest = tileDetails.min() ?? 0
        let highest = tileDetails.max() ?? 0
        // Color movement alone can be a real hologram. Only treat it as an
        // obstruction when at least one real angle also recovers materially
        // stronger registered luminance edges (typically hidden text).
        detailDrops[tile] = highest >= 2.2
          && highest >= lowest * 1.18 + 0.35
        if let lowGlare = glareCounts.min(), let highGlare = glareCounts.max() {
          minimumGlareCounts[tile] = lowGlare
          glareMoves[tile] = highGlare >= 3 && highGlare - lowGlare >= max(3, area / 40)
        }
      }
    }

    // Brightness and reflection differences must exist in the real aligned
    // inputs. A portrait, printed gray panel, or colored security pattern that
    // is stable in every view stays unchanged. Each selected tile comes from
    // one complete RGB source; channels are never synthesized independently.
    for frameIndex in smallViews.indices {
      let small = smallViews[frameIndex]
      let donorMask = masks[frameIndex]
      let donorField = fields[frameIndex]
      for ty in 0..<tilesY {
        for tx in 0..<tilesX {
          let x0 = tx * tileSide, x1 = min(thumbnail.width, x0 + tileSide)
          let y0 = ty * tileSide, y1 = min(thumbnail.height, y0 + tileSide)
          var baseGlare = 0, donorGlare = 0
          var consistentLift = 0, count = 0
          for y in y0..<y1 {
            for x in x0..<x1 {
              let index = y * thumbnail.width + x
              if baseMask[index] { baseGlare += 1 }
              if donorMask[index] { donorGlare += 1 }
              let i = index * 4
              let a = Double(max(thumbnail.pixels[i], thumbnail.pixels[i+1], thumbnail.pixels[i+2]))
              let b = Double(max(small.pixels[i], small.pixels[i+1], small.pixels[i+2]))
              // A common brightness lift in all three channels is consistent
              // with shadow moving; colored holographic changes do not qualify.
              let ratios = (0..<3).map { (Double(small.pixels[i+$0]) + 1) / (Double(thumbnail.pixels[i+$0]) + 1) }
              if b - a > 12, b < 245, (ratios.max()! - ratios.min()!) < 0.12 { consistentLift += 1 }
              count += 1
            }
          }
          let px = Double(x0 + x1) / (2 * Double(thumbnail.width))
          let py = Double(y0 + y1) / (2 * Double(thumbnail.height))
          let lightGain = donorField.value(x: px, y: py) - baseField.value(x: px, y: py)
          let clearsGlare = baseGlare >= 3 && donorGlare * 3 < baseGlare
          let clearsShadow = baseField.reliable && donorField.reliable
            && lightGain > 0.055 && consistentLift > count * 55 / 100
            && donorGlare <= baseGlare
          let tile = ty * tilesX + tx
          let bestDetail = details.map { $0[tile] }.max() ?? 0
          let donorDetail = details[frameIndex][tile]
          let clearsColoredReflection = colorMoves[tile] && detailDrops[tile]
            && donorDetail >= bestDetail * 0.96
            && donorDetail >= baseDetails[tile] * 1.12 + 0.25
          let score = clearsGlare ? 3 + Double(baseGlare - donorGlare) / Double(max(1, count))
            : clearsColoredReflection ? 2 + (donorDetail - baseDetails[tile]) / max(1, bestDetail)
            : clearsShadow ? lightGain : 0
          if score > scores[tile] {
            scores[tile] = score
            donors[tile] = frameIndex
            shadowTiles[tile] = clearsShadow
            coloredTiles[tile] = clearsColoredReflection
          }
        }
      }
    }

    // Report only evidence that survived the safe source-selection gate.
    // Static clipped white print has no temporal glare movement, and a moving
    // hologram with unchanged text detail has no detail drop.
    for tile in 0..<tileCount where donors[tile] < 0 {
      let bestDetail = details.map { $0[tile] }.max() ?? 0
      let coloredUnresolved = colorMoves[tile] && detailDrops[tile]
        && bestDetail >= baseDetails[tile] * 1.12 + 0.25
      let neutralUnresolved = glareMoves[tile] && baseGlareCounts[tile] >= 3
        && baseGlareCounts[tile] - minimumGlareCounts[tile] >= 3
      guard coloredUnresolved || neutralUnresolved else { continue }
      // The temporal median may already contain the clearest observation.
      if baseDetails[tile] >= bestDetail * 0.96 { continue }
      let tx = tile % tilesX, ty = tile / tilesX
      let x0 = tx * tileSide, x1 = min(thumbnail.width, x0 + tileSide)
      let y0 = ty * tileSide, y1 = min(thumbnail.height, y0 + tileSide)
      if coloredUnresolved {
        // Color movement is tile evidence because its safety gate requires a
        // matching recovery of local detail across the patch.
        unresolvedPixels += (x1 - x0) * (y1 - y0)
      } else {
        // A few clipped samples can move along an otherwise clean white edge
        // after perspective resampling. A pixel that is bright in every
        // registered view is shared white print, not temporal obstruction;
        // only count the temporal excess that is clear in at least two views.
        // This keeps a static border from becoming a retry when interpolation
        // moves a handful of mask samples at its edge.
        for y in y0..<y1 {
          for x in x0..<x1 {
            let index = y * thumbnail.width + x
            guard baseMask[index] else { continue }
            let clearViews = masks.reduce(into: 0) { count, mask in
              if !mask[index] { count += 1 }
            }
            guard clearViews >= 2 else { continue }
            unresolvedPixels += 1
          }
        }
      }
    }

    for (frameIndex, image) in aligned.enumerated() {
      var choices = [Bool](repeating: false, count: tileCount)
      for tile in 0..<tileCount where donors[tile] == frameIndex { choices[tile] = true }
      guard choices.contains(true) else { continue }
      guard !isCancelled() else { return nil }
      guard let cg = context.createCGImage(image, from: extent), let donor = raster(cg) else { return nil }
      // Feather only the boundary of a selected region, using one shared RGB
      // weight. This avoids rectangular exposure seams across continuous print.
      var weights = [Double](repeating: 0, count: thumbnail.width * thumbnail.height)
      for y in 0..<thumbnail.height {
        for x in 0..<thumbnail.width {
          var hits = 0, count = 0
          for yy in max(0, y-3)...min(thumbnail.height-1, y+3) {
            for xx in max(0, x-3)...min(thumbnail.width-1, x+3) {
              if choices[(yy/tileSide)*tilesX+xx/tileSide] { hits += 1 }
              count += 1
            }
          }
          weights[y*thumbnail.width+x] = Double(hits)/Double(count)
        }
      }
      var contributed = false
      for y in 0..<output.height {
        if y.isMultiple(of: 64), isCancelled() { return nil }
        for x in 0..<output.width {
          let sx = min(thumbnail.width - 1, x * thumbnail.width / output.width)
          let sy = min(thumbnail.height - 1, y * thumbnail.height / output.height)
          let weight = weights[sy * thumbnail.width + sx]
          guard weight > 0, safeInterior.contains(CGPoint(x: x, y: y)) else { continue }
          let i = (y * output.width + x) * 4
          for channel in 0..<3 {
            let blended = Double(output.pixels[i+channel])*(1-weight) + Double(donor.pixels[i+channel])*weight
            output.pixels[i+channel] = UInt8(max(0, min(255, blended.rounded())))
          }
          contributed = true
          let tile = (sy / tileSide) * tilesX + sx / tileSide
          if coloredTiles[tile]
            || (baseMask[sy * thumbnail.width + sx] && !masks[frameIndex][sy * thumbnail.width + sx]) {
            replacedPixels[y * output.width + x] = true
          }
        }
      }
      if contributed {
        usedFrames.insert(frameIndex)
        for tile in 0..<tileCount where donors[tile] == frameIndex && shadowTiles[tile] {
          shadowLifted = true
        }
      }
    }
    guard !isCancelled(), let result = makeImage(output) else { return nil }
    return (
      result,
      Double(replacedPixels.filter { $0 }.count) / Double(output.width * output.height),
      Double(unresolvedPixels) / Double(thumbnail.width * thumbnail.height),
      shadowLifted,
      usedFrames.count
    )
  }

  private func detailScore(
    _ raster: Raster, x0: Int, x1: Int, y0: Int, y1: Int
  ) -> Double {
    guard x1 - x0 >= 3, y1 - y0 >= 3 else { return 0 }
    var energy = 0.0
    var count = 0.0
    for y in max(1, y0)..<min(raster.height - 1, y1) {
      for x in max(1, x0)..<min(raster.width - 1, x1) {
        let horizontal = abs(luminance(raster, at: y * raster.width + x + 1)
          - luminance(raster, at: y * raster.width + x - 1))
        let vertical = abs(luminance(raster, at: (y + 1) * raster.width + x)
          - luminance(raster, at: (y - 1) * raster.width + x))
        // Clip isolated sensor spikes; repeated document strokes still add up.
        energy += min(64, horizontal + vertical)
        count += 1
      }
    }
    return count > 0 ? energy / count : 0
  }

  private func luminance(_ raster: Raster, at index: Int) -> Double {
    let i = index * 4
    return 0.2126 * Double(raster.pixels[i])
      + 0.7152 * Double(raster.pixels[i + 1])
      + 0.0722 * Double(raster.pixels[i + 2])
  }

  private func chromaDistance(_ first: Raster, _ second: Raster, at index: Int) -> Double {
    let i = index * 4
    let firstSum = Double(first.pixels[i]) + Double(first.pixels[i + 1])
      + Double(first.pixels[i + 2]) + 48
    let secondSum = Double(second.pixels[i]) + Double(second.pixels[i + 1])
      + Double(second.pixels[i + 2]) + 48
    var distance = 0.0
    for channel in 0..<3 {
      distance += abs((Double(first.pixels[i + channel]) + 16) / firstSum
        - (Double(second.pixels[i + channel]) + 16) / secondSum)
    }
    return distance
  }

  private func illumination(_ raster: Raster) -> Field {
    let rows = max(8, Int((Double(columns) * Double(raster.height) / Double(raster.width)).rounded()))
    var samples = [Double?](repeating: nil, count: columns * rows)
    for row in 0..<rows {
      for column in 0..<columns {
        let x0 = column * raster.width / columns, x1 = (column + 1) * raster.width / columns
        let y0 = row * raster.height / rows, y1 = (row + 1) * raster.height / rows
        var pale: [Double] = []
        for y in y0..<y1 {
          for x in x0..<x1 {
            let index = (y * raster.width + x) * 4
            let high = Double(max(raster.pixels[index], raster.pixels[index + 1], raster.pixels[index + 2])) / 255
            let low = Double(min(raster.pixels[index], raster.pixels[index + 1], raster.pixels[index + 2])) / 255
            if high > 0.36, high < 0.96, low / high > 0.72 { pale.append(high) }
          }
        }
        if pale.count >= max(8, (x1 - x0) * (y1 - y0) / 4) {
          pale.sort()
          samples[row * columns + column] = pale[min(pale.count - 1, pale.count * 85 / 100)]
        }
      }
    }
    let valid = samples.compactMap { $0 }.sorted()
    let target = min(0.94, valid.isEmpty ? 0.9 : valid[min(valid.count - 1, valid.count * 90 / 100)])
    let reliable = valid.count >= samples.count / 2 && target >= 0.60
    var smooth = [Double](repeating: target, count: samples.count)
    for row in 0..<rows {
      for column in 0..<columns {
        var sum = 0.0, weight = 0.0
        // Missing areas (portrait, stamps, dark print) inherit only a broad
        // field measured from surrounding pale paper, never their own color.
        for sampleRow in max(0, row - 6)...min(rows - 1, row + 6) {
          for sampleColumn in max(0, column - 6)...min(columns - 1, column + 6) {
            guard let sample = samples[sampleRow * columns + sampleColumn] else { continue }
            let distance = Double((row - sampleRow) * (row - sampleRow) + (column - sampleColumn) * (column - sampleColumn))
            let w = exp(-distance / 5.0)
            sum += sample * w
            weight += w
          }
        }
        if weight > 0.01 { smooth[row * columns + column] = sum / weight }
      }
    }
    return Field(values: smooth, width: columns, height: rows, target: target, reliable: reliable)
  }

  private func glareMask(_ raster: Raster) -> [Bool] {
    let field = illumination(raster)
    var mask = [Bool](repeating: false, count: raster.width * raster.height)
    guard field.reliable else { return mask }
    let margin = max(2, min(raster.width, raster.height) / 100)
    for y in margin..<(raster.height - margin) {
      for x in margin..<(raster.width - margin) {
        let index = (y * raster.width + x) * 4
        let high = Double(max(raster.pixels[index], raster.pixels[index + 1], raster.pixels[index + 2])) / 255
        let low = Double(min(raster.pixels[index], raster.pixels[index + 1], raster.pixels[index + 2])) / 255
        let background = field.value(x: (Double(x) + 0.5) / Double(raster.width),
          y: (Double(y) + 0.5) / Double(raster.height))
        mask[y * raster.width + x] = low > 0.87 && high - low < 0.12 && high - background > 0.095
      }
    }
    // Ignore isolated bright sensor pixels. White printed paper does not
    // qualify without a darker local substrate, and holographic color alone
    // is never classified as glare.
    var connected = mask
    for y in 1..<(raster.height - 1) {
      for x in 1..<(raster.width - 1) where mask[y * raster.width + x] {
        var neighbors = 0
        for dy in -1...1 {
          for dx in -1...1 where mask[(y + dy) * raster.width + x + dx] { neighbors += 1 }
        }
        connected[y * raster.width + x] = neighbors >= 3
      }
    }
    return connected
  }

  private func raster(_ image: CGImage, maximumEdge: Int? = nil) -> Raster? {
    let scale = maximumEdge.map { min(1, Double($0) / Double(max(image.width, image.height))) } ?? 1
    let width = max(1, Int((Double(image.width) * scale).rounded()))
    let height = max(1, Int((Double(image.height) * scale).rounded()))
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let made = bytes.withUnsafeMutableBytes { buffer -> Bool in
      guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
      context.interpolationQuality = .high
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    return made ? Raster(pixels: bytes, width: width, height: height) : nil
  }

  private func makeImage(_ raster: Raster) -> CGImage? {
    guard let provider = CGDataProvider(data: Data(raster.pixels) as CFData) else { return nil }
    return CGImage(width: raster.width, height: raster.height, bitsPerComponent: 8,
      bitsPerPixel: 32, bytesPerRow: raster.width * 4, space: colorSpace,
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
      provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
  }
}
