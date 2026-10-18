import CoreGraphics
import CoreImage
import Foundation

@main struct ScannerLightingProcessingTests {
  static let space = CGColorSpace(name: CGColorSpace.sRGB)!
  static var passed = 0
  static func expect(_ test: Bool, _ label: String) {
    guard test else { print("FAIL: \(label)"); exit(1) }
    passed += 1
    print("PASS: \(label)")
  }
  static func image(_ body: (Int, Int) -> [UInt8]) -> CGImage {
    let width = 600, height = 400
    var bytes = [UInt8](); bytes.reserveCapacity(width * height * 4)
    for y in 0..<height { for x in 0..<width { bytes += body(x,y) + [255] } }
    return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
      bytesPerRow: width*4, space: space,
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
      provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
  }
  static func printed(_ x: Int, _ y: Int) -> [UInt8] {
    if x > 35 && x < 165 && y > 65 && y < 250 { return [135,135,135] }
    if x > 380 && x < 455 && y > 30 && y < 100 { return [255,255,255] }
    if x > 230 && x < 570 && y > 70 && y < 340 && y % 25 < 3 { return [35,45,50] }
    return [225,221,215]
  }
  static func pixels(_ image: CGImage) -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: image.width*image.height*4)
    bytes.withUnsafeMutableBytes { data in
      let context = CGContext(data: data.baseAddress, width: image.width, height: image.height,
        bitsPerComponent: 8, bytesPerRow: image.width*4, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
      context.draw(image, in: CGRect(x:0,y:0,width:image.width,height:image.height))
    }
    return bytes
  }
  static func difference(_ a: CGImage, _ b: CGImage) -> Double {
    let x = pixels(a), y = pixels(b)
    return zip(x,y).reduce(0.0) { $0 + abs(Double($1.0)-Double($1.1)) } / Double(x.count)
  }
  static func main() throws {
    let lighting = ScannerDocumentLighting(), context = CIContext()
    let clean = image(printed)
    let bounds = CGRect(x:0,y:0,width:600,height:400)
    func combine(_ base: CGImage, _ images: [CGImage]) -> (image: CGImage, glareFraction: Double,
      unresolvedObstructionFraction: Double, shadowLifted: Bool, framesUsed: Int) {
      lighting.combineLighting(base: base, aligned: images.map(CIImage.init(cgImage:)),
        reference: CIImage(cgImage:base), safeInterior:bounds, context:context, isCancelled:{false})!
    }
    let unchanged = combine(clean, [clean,clean,clean])
    expect(difference(unchanged.image, clean) < 0.01, "same gray portrait and white print preserved")
    expect(!unchanged.shadowLifted && unchanged.glareFraction == 0, "static print is not lighting recovery")
    let dark = image { x,y in printed(x,y).map { UInt8((Double($0) * (x < 300 ? 0.65 : 1)).rounded()) } }
    let alternate = image { x,y in printed(x,y).map { UInt8((Double($0) * (x > 350 ? 0.65 : 1)).rounded()) } }
    let persistent = combine(dark,[dark,dark,dark])
    expect(difference(persistent.image,dark) < 0.01 && !persistent.shadowLifted, "persistent shadow is not invented away")
    let recovered = combine(dark,[dark,dark,dark,alternate])
    expect(recovered.shadowLifted, "complementary real brightness used")
    expect(difference(recovered.image,clean) < difference(dark,clean)*0.70, "observed moving-shadow recovery improves known truth")
    expect(recovered.framesUsed == 4, "used-frame report includes contributing fourth view only")
    let glare = image { x,y in (x > 270 && x < 320 && y > 180 && y < 220) ? [255,255,255] : printed(x,y) }
    let deglared = combine(glare,[glare,glare,glare,clean])
    expect(deglared.glareFraction > 0, "clear donor replaces reflected region")
    expect(difference(deglared.image,clean) < difference(glare,clean)*0.6, "source-only glare replacement recovers printed detail")
    func coloredReflection(_ x0: Int, _ x1: Int, _ color: [UInt8],
      y0: Int = 135, y1: Int = 285, strength: Double = 0.80) -> CGImage {
      image { x,y in
        let source = printed(x,y)
        guard x >= x0, x < x1, y >= y0, y < y1 else { return source }
        // A colored reflection reduces the contrast of real print rather than
        // adding a synthetic replacement character.
        return zip(source,color).map {
          UInt8((Double($0.0)*(1-strength) + Double($0.1)*strength).rounded())
        }
      }
    }
    let cyan = coloredReflection(215,390,[45,205,235])
    let blue = coloredReflection(285,455,[60,115,245])
    let colored = combine(cyan,[cyan,blue,clean])
    expect(colored.glareFraction > 0, "moving colored reflection uses a real clear source patch")
    expect(difference(colored.image,clean) < difference(cyan,clean)*0.72,
      "moving cyan and blue reflections recover underlying print contrast")
    expect(colored.unresolvedObstructionFraction < 0.0015,
      "recovered colored reflection is not reported as unresolved")
    let staticColor = image { x,y in
      let source = printed(x,y)
      return (x >= 215 && x < 390 && y >= 135 && y < 285)
        ? zip(source,[45,205,235]).map { UInt8((Double($0.0)*0.20 + Double($0.1)*0.80).rounded()) }
        : source
    }
    let staticColored = combine(staticColor,[staticColor,staticColor,staticColor])
    expect(difference(staticColored.image,staticColor) < 0.01,
      "static colored print or security pattern is preserved")
    expect(staticColored.glareFraction == 0 && staticColored.unresolvedObstructionFraction == 0,
      "static color alone is not classified as reflection")
    let movingColorWithoutLostDetail = image { x,y in
      let source = printed(x,y)
      guard x >= 215, x < 390, y >= 135, y < 285 else { return source }
      // Add a strong color shift with near-zero luminance change, retaining
      // the exact printed strokes underneath.
      return [Int(source[0])+25, Int(source[1])-5, Int(source[2])-25]
        .map { UInt8(max(0,min(255,$0))) }
    }
    let harmlessShift = combine(clean,[clean,movingColorWithoutLostDetail,clean])
    expect(difference(harmlessShift.image,clean) < 0.01,
      "moving holographic color without detail loss is not scrubbed")
    func whiteBorderSample(_ side: Int) -> CGImage {
      image { x,y in
        (x >= 250 && x < 250 + side && y >= 150 && y < 150 + side)
          ? [255,255,255] : printed(x,y)
      }
    }
    let resampledBorder = whiteBorderSample(16)
    let smallerBorder = whiteBorderSample(14)
    let borderResult = combine(resampledBorder,[resampledBorder,smallerBorder,smallerBorder])
    expect(borderResult.unresolvedObstructionFraction < 0.0015,
      "small white-border resampling does not become a full-tile retry")
    expect(difference(borderResult.image,resampledBorder) < 0.01,
      "white-border resampling does not alter authentic pixels")
    func whiteBorderWithEdgeResampling(_ edge: Int) -> CGImage {
      image { x,y in
        // A broad, static white security panel. The one-pixel edge variation
        // models interpolation across a registered document boundary without
        // introducing any real moving reflection.
        let inPanel = x >= 212 && x < 388 && y >= 116 && y < 292
        guard inPanel else { return printed(x,y) }
        if x == 212 + edge || y == 116 + edge || x == 387 - edge || y == 291 - edge {
          return [254,254,254]
        }
        return [255,255,255]
      }
    }
    let broadWhite = whiteBorderWithEdgeResampling(0)
    let broadWhiteShifted = whiteBorderWithEdgeResampling(1)
    let broadWhiteResult = combine(broadWhite,[broadWhite,broadWhiteShifted,broadWhiteShifted])
    expect(broadWhiteResult.unresolvedObstructionFraction < 0.0015,
      "static white border with edge resampling does not request another angle")
    expect(difference(broadWhiteResult.image,broadWhite) < 0.01,
      "static white border resampling preserves the source")
    var cancellationChecks = 0
    let cancelled = lighting.combineLighting(base:dark, aligned:[dark,alternate,clean].map(CIImage.init(cgImage:)),
      reference:CIImage(cgImage:dark), safeInterior:bounds, context:context, isCancelled:{ cancellationChecks += 1; return cancellationChecks >= 3 })
    expect(cancelled == nil, "lighting processing cooperatively cancels")
    let processor = ScannerImageProcessor()
    let profile = FoorsaScannerProfile(arguments: ["profile": ["documentKey": "identity"]])
    func candidate(_ image: CGImage, _ index: Int) -> ScannerProcessedCandidate {
      ScannerProcessedCandidate(jpeg: Data([UInt8(index + 1)]), sharpness: 10 - Double(index)*0.03,
        coverage: 0.8, fingerprint: ScannerImageFingerprint(bits: 0), correctedImage: image)
    }
    let broadObstruction = processor.resolveBurst([cyan,blue,clean].enumerated().map {
      candidate($0.element,$0.offset)
    }, profile:profile)!
    expect(broadObstruction.mode == .bestFrameFallback
      && broadObstruction.fallbackReason == .registrationRejected,
      "broad hidden content still fails registration instead of being synthesized")
    let pipelineCyan = coloredReflection(270,330,[45,205,235],y0:180,y1:240,strength:0.45)
    let pipelineBlue = coloredReflection(290,350,[60,115,245],y0:180,y1:240,strength:0.45)
    let coloredBurst = processor.resolveBurst([pipelineCyan,pipelineBlue,clean].enumerated().map {
      candidate($0.element,$0.offset)
    }, profile:profile)!
    expect(coloredBurst.mode == .alignedLightingFusion,
      "full pipeline registers three colored-reflection viewpoints")
    expect(difference(coloredBurst.candidate.correctedImage!,clean) < difference(pipelineCyan,clean)*0.98,
      "full pipeline retains colored-reflection detail recovery")
    expect(coloredBurst.lighting?.needsDifferentAngle == false,
      "full pipeline clears retry only after safe real-source recovery")
    if let privateDirectory = ProcessInfo.processInfo.environment["FOORSA_PRIVATE_LIGHTING_CASE_DIR"] {
      let privateCandidates = ["0021.png","0022.png","0023.png"].compactMap { name -> ScannerProcessedCandidate? in
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: privateDirectory)
          .appendingPathComponent(name)) else { return nil }
        return processor.process(photoData:data,profile:profile)
      }
      expect(privateCandidates.count == 3, "private parent-ID replay prepares all three views")
      let privateResolution = processor.resolveBurst(privateCandidates,profile:profile)!
      expect(privateResolution.mode != .bestFrameFallback
        && privateResolution.lighting?.needsDifferentAngle == false,
        "private white-border perspective replay avoids false lighting retry")
    }
    let oldBurst = processor.resolveBurst([dark,dark,dark].enumerated().map { candidate($0.element,$0.offset) }, profile: profile)!
    expect(oldBurst.lighting?.needsDifferentAngle == false,
      "persistent gray or shadow is not rejected without moving-obstruction evidence")
    let newView = processor.resolveBurst([dark,dark,dark,clean].enumerated().map { candidate($0.element,$0.offset) }, profile: profile)!
    expect(difference(newView.candidate.correctedImage!,clean) < difference(dark,clean)*0.7,
      "complete pipeline retains a cleaner extra view even if fusion is unsafe")
    let staticPrint = processor.resolveBurst(Array(repeating: clean,count:5).enumerated().map {
      candidate($0.element,$0.offset)
    }, profile:profile)!
    expect(staticPrint.lighting?.needsDifferentAngle == false, "ordinary printed white does not create endless angle requests")
    expect(difference(staticPrint.candidate.correctedImage!,clean) < 0.1,
      "five-view pipeline preserves static gray and white print")
    let paperProfile = FoorsaScannerProfile(arguments: ["profile": ["documentKey": "transcript"]])
    let paperDark = image { x,y in
      printed(x,y).map { UInt8((Double($0) * (x < 300 ? 0.78 : 1)).rounded()) }
    }
    let paperAlternate = image { x,y in
      printed(x,y).map { UInt8((Double($0) * (x > 350 ? 0.78 : 1)).rounded()) }
    }
    let paperLighting = processor.resolveBurst([paperDark,paperDark,paperAlternate].enumerated().map {
      candidate($0.element,$0.offset)
    }, profile:paperProfile)!
    expect(paperLighting.mode == .alignedLightingFusion && paperLighting.lighting?.shadowCorrectionApplied == true,
      "registered lighting recovery also applies to paper documents")
    let missing = ScannerProcessedCandidate(jpeg:Data([1]),sharpness:11,coverage:0.8,
      fingerprint:ScannerImageFingerprint(bits:0))
    let missingResolution = processor.resolveBurst([missing,candidate(clean,1),candidate(clean,2),candidate(clean,3)],profile:profile)
    expect(missingResolution?.fallbackReason == .missingCorrectedImage,
      "missing corrected reference cannot crash extra-view selection")
    func finePrint(_ shift: Int) -> CGImage {
      image { x,y in
        let dx = (170..<220).contains(y) ? shift : 0
        let column = (x - dx + 600) % 23, row = y % 17
        let ink = x > 35 && x < 565 && y > 40 && y < 360
          && ((column < 3 && row < 11) || (column < 14 && row < 2))
        return ink ? [30,35,40] : [225,221,215]
      }
    }
    let shifted = [finePrint(0),finePrint(3),finePrint(3)].enumerated().map {
      candidate($0.element,$0.offset)
    }
    let unsafe = processor.resolveBurst(shifted,profile:profile)!
    expect(unsafe.mode == .bestFrameFallback && unsafe.candidate.jpeg == shifted[0].jpeg,
      "lighting agreement cannot bypass localized misaligned fine print")
    func resizedCandidate(_ width: Int, _ height: Int, _ index: Int) -> ScannerProcessedCandidate {
      let raster = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
      raster.draw(clean, in: CGRect(x: 0, y: 0, width: width, height: height))
      return ScannerProcessedCandidate(jpeg: Data([UInt8(index)]), sharpness: 10.2,
        coverage: 0.8, fingerprint: ScannerImageFingerprint(bits: 0), correctedImage: raster.makeImage())
    }
    let adaptivePool = [candidate(clean, 0), candidate(clean, 1), candidate(clean, 2),
      resizedCandidate(150, 150, 4), resizedCandidate(150, 75, 5), resizedCandidate(100, 200, 6)]
    let adaptive = processor.resolveAdaptiveCapture(adaptivePool, profile: profile)
    expect(adaptive?.mode != nil && adaptive?.mode != .bestFrameFallback && adaptive?.framesUsed == 3,
      "adaptive search reaches an earlier valid triplet after incompatible newer views")
    expect(adaptive?.lighting?.needsDifferentAngle == false,
      "adaptive completion requires usable lighting in the selected set")
    let supplemental = processor.resolveAdaptiveCapture(
      [paperDark, paperDark, paperDark, paperDark, paperDark, paperAlternate].enumerated().map {
        candidate($0.element, $0.offset)
      }, profile: paperProfile)
    expect(supplemental?.mode == .alignedLightingFusion && supplemental?.framesConsidered == 6
      && supplemental?.lighting?.shadowCorrectionApplied == true,
      "adaptive fusion can use a sixth observation to recover lighting beyond the initial three")
    expect(processor.resolveAdaptiveCapture(shifted, profile: profile)?.mode == .bestFrameFallback,
      "adaptive selection keeps the localized fine-print rejection")
    var adaptiveCancelChecks = 0
    let adaptiveCancelled = processor.resolveAdaptiveCapture(adaptivePool, profile: profile) {
      adaptiveCancelChecks += 1
      return adaptiveCancelChecks >= 8
    }
    expect(adaptiveCancelled == nil && adaptiveCancelChecks >= 8,
      "adaptive search cancels while trying incompatible subsets")
    print("\(passed) lighting regression checks passed")
  }
}
