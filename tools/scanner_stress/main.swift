import CoreGraphics
import CoreImage
import Darwin
import Foundation
import ImageIO
import Vision

private let frameSize = CGSize(width: 1440, height: 1920)
private let repository: URL = {
  var candidate = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).standardizedFileURL
  while true {
    if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("ios/Runner/ScannerGeometry.swift").path) {
      return candidate
    }
    let nested = candidate.appendingPathComponent("scanner-mobile")
    if FileManager.default.fileExists(atPath: nested.appendingPathComponent("ios/Runner/ScannerGeometry.swift").path) {
      return nested
    }
    let parent = candidate.deletingLastPathComponent()
    if parent.path == candidate.path { fatalError("run from scanner-mobile or a parent directory") }
    candidate = parent
  }
}()
private func insideRepository(_ url: URL) -> Bool {
  let path = url.standardizedFileURL.resolvingSymlinksInPath().path
  return path == repository.path || path.hasPrefix(repository.path + "/")
}

struct Sample: Decodable {
  let id: String
  let category: String
  let layout: String
  let documentKey: String?
  let path: String
  let split: String?
  let capture: String?
  let rawQuad: [[Double]]?
  let framingSafe: Bool?
  let qualityConcern: String?
}
struct Manifest: Decodable {
  let samples: [Sample]
  let requiredCategories: [String]?
}
struct Options {
  var manifest: URL?
  var output: URL?
  var limit = Int.max
  var variants = 40
  var split: String?
  var diagnostics = 0
  var smoke = false
  var requirePass = false
  var seed: UInt64 = 0
}
struct Variant {
  let name: String
  let family: String
  let scale: CGFloat
  let rotation: CGFloat
  let tilt: CGFloat
  let background: Int
  let blur: CGFloat
  let contrast: CGFloat
  let glare: CGFloat
  let shadow: CGFloat
  let clutter: Bool
  let inner: Bool
  let offset: CGPoint
  let expected: Bool
  let qualityConcern: String?
}
struct Outcome: Encodable {
  let id: String
  let category: String
  let layout: String
  let split: String
  let variant: String
  let family: String
  let imageSize: [Int]
  let qualityConcern: String?
  let expected: Bool
  let detected: Bool
  let eligible: Bool
  let accurate: Bool
  let unsafeAuto: Bool
  let cornerError: Double?
  let polygonIoU: Double?
  let milliseconds: Double
  let stillMilliseconds: Double
  let stillCornerError: Double?
  let stillPolygonIoU: Double?
  let stillDetected: Bool
  let stillAccurate: Bool
  let unsafeStill: Bool
  let unsafeQuality: Bool
}
struct Sequence: Encodable {
  let id: String
  let category: String
  let name: String
  let ready: Bool
  let unsafeReady: Bool
}
struct Report: Encodable {
  let schema: Int
  let frameSize: [Int]
  let selectedSamples: Int
  let requestedVariantsPerSample: Int
  let perturbationSeed: UInt64
  let outcomes: [Outcome]
  let sequences: [Sequence]
  let peakRSSBytes: UInt64
}
struct CategoryGate: Encodable {
  let category: String
  let gate: String
}
struct GateReport: Encodable {
  let pass: Bool
  let missingCategories: [String]
  let categories: [CategoryGate]
}
struct Rendered {
  let image: CIImage
  let truth: ScannerQuadrilateral?
  let imageSize: CGSize
}

private func fail(_ message: String) -> Never {
  fputs("scanner-stress: \(message)\n", stderr)
  exit(2)
}
private func parseOptions() -> Options {
  var options = Options()
  var index = 1
  let args = CommandLine.arguments
  while index < args.count {
    let flag = args[index]
    if flag == "--smoke" { options.smoke = true; index += 1; continue }
    if flag == "--require-pass" { options.requirePass = true; index += 1; continue }
    guard index + 1 < args.count else { fail("missing value for \(flag)") }
    let value = args[index + 1]
    switch flag {
    case "--manifest": options.manifest = URL(fileURLWithPath: value)
    case "--output": options.output = URL(fileURLWithPath: value)
    case "--limit": options.limit = Int(value) ?? -1
    case "--variants": options.variants = Int(value) ?? -1
    case "--split": options.split = value
    case "--seed":
      guard let seed = UInt64(value) else { fail("--seed must be an unsigned integer") }
      options.seed = seed
    case "--diagnostics": options.diagnostics = Int(value) ?? -1
    default: fail("unknown argument \(flag)")
    }
    index += 2
  }
  guard options.limit > 0, (1...40).contains(options.variants), options.diagnostics >= 0 else {
    fail("--limit must be positive; --variants must be 1...40; --diagnostics must be nonnegative")
  }
  guard let output = options.output, output.path.hasPrefix("/") else { fail("--output must be an absolute private directory") }
  guard !insideRepository(output) else { fail("--output must be outside the repository") }
  if !options.smoke && options.manifest == nil { fail("--manifest is required unless --smoke is set") }
  return options
}
private func load(_ sample: Sample, raw: Bool) -> CIImage {
  guard sample.path.hasPrefix("/") else { fail("sample \(sample.id) path must be absolute") }
  let url = URL(fileURLWithPath: sample.path).standardizedFileURL.resolvingSymlinksInPath()
  guard !insideRepository(url) else { fail("sample \(sample.id) source must be outside repository") }
  guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fail("cannot read source for \(sample.id)") }
  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
  let orientation = CGImagePropertyOrientation(rawValue: UInt32(properties?[kCGImagePropertyOrientation] as? Int ?? 1)) ?? .up
  var image = CIImage(cgImage: cg).oriented(orientation)
  image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
  let scale = raw ? 1 : min(1, 1500 / max(image.extent.width, image.extent.height))
  return image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
}
private func syntheticSource() -> CIImage {
  let w = 850, h = 1200
  let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  context.setFillColor(CGColor(red: 0.97, green: 0.95, blue: 0.86, alpha: 1))
  context.fill(CGRect(x: 0, y: 0, width: w, height: h))
  context.setFillColor(CGColor(red: 0.18, green: 0.24, blue: 0.31, alpha: 1))
  for row in 0..<17 { context.fill(CGRect(x: 85, y: 110 + row * 50, width: row % 3 == 0 ? 580 : 680, height: 9)) }
  context.setFillColor(CGColor(red: 0.3, green: 0.46, blue: 0.66, alpha: 1))
  context.fill(CGRect(x: 85, y: 1010, width: 660, height: 90))
  return CIImage(cgImage: context.makeImage()!)
}
private func variants() -> [Variant] {
  var result: [Variant] = []
  let backgrounds = [0, 1, 2, 3]
  for i in 0..<32 {
    let family: String
    if i < 8 { family = "normal" }
    else if i < 16 { family = "perspective_rotation" }
    else if i < 24 { family = "lighting_texture" }
    else { family = "blur_clutter" }
    result.append(Variant(name: String(format: "p%02d", i), family: family,
      scale: [0.76, 0.88, 1.0, 1.08][i % 4],
      rotation: i < 8 ? [0, 3, -3, 8][(i / 2) % 4] : [0, 90, 180, 270][i % 4],
      tilt: i < 8 ? 0.015 : [0.035, 0.07, 0.1, 0.13][i % 4], background: backgrounds[i % 4],
      blur: i >= 24 ? [0, 1.5, 3, 5][i % 4] : 0,
      contrast: i >= 16 && i < 24 ? [0.52, 0.7, 0.9, 1.1][i % 4] : 1,
      glare: i >= 16 && i < 24 ? [0, 0.2, 0.32, 0.42][i % 4] : 0,
      shadow: i >= 16 && i < 24 ? [0.2, 0.4, 0.55, 0.65][i % 4] : 0,
      clutter: i >= 24, inner: i >= 28,
      offset: CGPoint(x: CGFloat((i % 3) - 1) * 52, y: CGFloat(((i / 3) % 3) - 1) * 58), expected: true,
      qualityConcern: i >= 24 && i % 4 >= 2 ? "moderate_blur" : nil))
  }
  let negativeNames = ["clip_left", "clip_right", "clip_top", "partial_corner", "tiny", "heavy_glare", "heavy_blur", "no_document"]
  for (i, name) in negativeNames.enumerated() {
    let safetyNegative = i < 5 || i == 7
    result.append(Variant(name: name, family: safetyNegative ? "framing_negative" : "quality_challenge", scale: i == 4 ? 0.34 : 0.94,
      rotation: i == 3 ? 12 : 0, tilt: i == 3 ? 0.18 : 0.04, background: i % 4,
      blur: i == 6 ? 18 : 0, contrast: 1, glare: i == 5 ? 0.98 : 0,
      shadow: 0, clutter: i == 7, inner: false,
      offset: CGPoint(x: i == 0 ? -600 : i == 1 ? 600 : 0, y: i == 2 ? 850 : 0), expected: !safetyNegative,
      qualityConcern: i == 5 ? "severe_glare" : i == 6 ? "severe_blur" : nil))
  }
  return result
}
// A fixed seed reproduces an additional geometry sweep without changing source
// labels or the accuracy/coverage gate. Zero preserves the original benchmark.
private func perturbed(_ variants: [Variant], seed: UInt64) -> [Variant] {
  guard seed != 0 else { return variants }
  var state = seed
  func random(_ radius: CGFloat) -> CGFloat {
    state = state &* 6364136223846793005 &+ 1442695040888963407
    return (CGFloat(state >> 11) / CGFloat(UInt64.max >> 11) * 2 - 1) * radius
  }
  return variants.map { v in
    Variant(name: v.name, family: v.family,
      scale: v.scale * (1 + random(0.02)), rotation: v.rotation + random(2),
      tilt: max(0, v.tilt + random(0.005)), background: v.background,
      blur: v.blur, contrast: v.contrast, glare: v.glare, shadow: v.shadow,
      clutter: v.clutter, inner: v.inner,
      offset: CGPoint(x: v.offset.x + random(15), y: v.offset.y + random(15)),
      expected: v.expected, qualityConcern: v.qualityConcern)
  }
}
private func background(_ variant: Variant) -> CIImage {
  let w = Int(frameSize.width), h = Int(frameSize.height)
  let colors: [(CGFloat, CGFloat, CGFloat)] = [(0.22,0.26,0.31), (0.83,0.82,0.79), (0.47,0.38,0.31), (0.11,0.15,0.2)]
  let c = colors[variant.background]
  let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  ctx.setFillColor(CGColor(red: c.0, green: c.1, blue: c.2, alpha: 1))
  ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
  if variant.background == 2 || variant.clutter {
    for i in 0..<23 {
      let x = CGFloat((i * 367 + 47) % w), y = CGFloat((i * 571 + 113) % h)
      let shade = CGFloat((i * 23) % 19) / 100
      ctx.setFillColor(CGColor(red: min(1,c.0 + shade), green: min(1,c.1 + shade), blue: min(1,c.2 + shade), alpha: 0.5))
      ctx.fill(CGRect(x: x, y: y, width: CGFloat((i % 5 + 2) * 16), height: 3))
    }
  }
  if variant.clutter {
    ctx.setStrokeColor(CGColor(red: variant.background == 1 ? 0.24 : 0.88, green: 0.28, blue: 0.25, alpha: 0.9))
    ctx.setLineWidth(11)
    ctx.stroke(CGRect(x: 55, y: 1340, width: 510, height: 360))
    ctx.setLineWidth(5)
    ctx.stroke(CGRect(x: 990, y: 140, width: 310, height: 510))
  }
  return CIImage(cgImage: ctx.makeImage()!)
}
private func canonical(_ points: [CGPoint]) -> ScannerQuadrilateral {
  let top = points.sorted { $0.y > $1.y }.prefix(2).sorted { $0.x < $1.x }
  let bottom = points.sorted { $0.y < $1.y }.prefix(2).sorted { $0.x < $1.x }
  return ScannerQuadrilateral(topLeft: top[0], topRight: top[1], bottomRight: bottom[1], bottomLeft: bottom[0])
}
private func render(_ source: CIImage, _ variant: Variant) -> Rendered {
  let base = background(variant)
  if variant.name == "no_document" { return Rendered(image: base, truth: nil, imageSize: frameSize) }
  let sw = source.extent.width, sh = source.extent.height
  let angle = variant.rotation * .pi / 180
  let rotatedWidth = abs(sw * cos(angle)) + abs(sh * sin(angle))
  let rotatedHeight = abs(sw * sin(angle)) + abs(sh * cos(angle))
  let baseFit = min(frameSize.width * 0.78 / rotatedWidth, frameSize.height * 0.77 / rotatedHeight)
  let distortion = min(sw, sh) * variant.tilt * 2
  let safeWidth = frameSize.width * 0.97 - 2 * abs(variant.offset.x)
  let safeHeight = frameSize.height * 0.97 - 2 * abs(variant.offset.y)
  let fit = variant.expected ? min(baseFit,
    safeWidth / (variant.scale * (rotatedWidth + distortion)),
    safeHeight / (variant.scale * (rotatedHeight + distortion))) : baseFit
  let halfW = sw * fit * variant.scale / 2, halfH = sh * fit * variant.scale / 2
  let x = frameSize.width / 2 + variant.offset.x, y = frameSize.height / 2 + variant.offset.y
  let original: [CGPoint] = [CGPoint(x: -halfW, y: halfH), CGPoint(x: halfW, y: halfH),
                             CGPoint(x: halfW, y: -halfH), CGPoint(x: -halfW, y: -halfH)]
  var corners = original.map { p in CGPoint(x: x + p.x * cos(angle) - p.y * sin(angle),
                                            y: y + p.x * sin(angle) + p.y * cos(angle)) }
  let skew = min(halfW, halfH) * variant.tilt
  corners[0].x += skew; corners[0].y -= skew * 0.5
  corners[1].x -= skew * 0.6; corners[1].y += skew * 0.5
  corners[2].x += skew * 0.7; corners[2].y += skew
  corners[3].x -= skew; corners[3].y -= skew * 0.8
  if variant.name == "partial_corner" { corners[0].x -= 670; corners[0].y += 400 }
  if variant.expected && corners.contains(where: {
    $0.x < frameSize.width * 0.015 || $0.x > frameSize.width * 0.985 ||
    $0.y < frameSize.height * 0.015 || $0.y > frameSize.height * 0.985
  }) { fail("generated framing-safe variant extends beyond the image: \(variant.name)") }
  let filter = CIFilter(name: "CIPerspectiveTransform")!
  filter.setValue(source, forKey: kCIInputImageKey)
  filter.setValue(CIVector(cgPoint: corners[0]), forKey: "inputTopLeft")
  filter.setValue(CIVector(cgPoint: corners[1]), forKey: "inputTopRight")
  filter.setValue(CIVector(cgPoint: corners[2]), forKey: "inputBottomRight")
  filter.setValue(CIVector(cgPoint: corners[3]), forKey: "inputBottomLeft")
  var paper = filter.outputImage!
  if variant.contrast != 1 {
    paper = paper.applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: variant.contrast,
      kCIInputSaturationKey: 0.65])
  }
  var image = paper.composited(over: base).cropped(to: CGRect(origin: .zero, size: frameSize))
  if variant.shadow > 0 {
    let shadow = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: variant.shadow))
      .cropped(to: CGRect(x: x - halfW * 1.25, y: y - halfH * 0.15, width: halfW * 2.5, height: halfH * 0.35))
      .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 55])
    image = shadow.composited(over: image).cropped(to: CGRect(origin: .zero, size: frameSize))
  }
  if variant.glare > 0 {
    let glare = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: variant.glare))
      .cropped(to: CGRect(x: x - halfW * 0.75, y: y + halfH * 0.05, width: halfW * 1.5, height: halfH * 0.7))
      .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 70])
    image = glare.composited(over: image).cropped(to: CGRect(origin: .zero, size: frameSize))
  }
  if variant.inner {
    let box = CGRect(x: x - halfW * 0.64, y: y - halfH * 0.62, width: halfW * 1.28, height: halfH * 1.24)
    let ctx = CGContext(data: nil, width: Int(frameSize.width), height: Int(frameSize.height), bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.clear(CGRect(origin: .zero, size: frameSize))
    ctx.setStrokeColor(CGColor(red: 0.12, green: 0.16, blue: 0.21, alpha: 0.8))
    ctx.setLineWidth(8); ctx.stroke(box)
    image = CIImage(cgImage: ctx.makeImage()!).composited(over: image).cropped(to: CGRect(origin: .zero, size: frameSize))
  }
  if variant.blur > 0 {
    image = image.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: variant.blur])
      .cropped(to: CGRect(origin: .zero, size: frameSize))
  }
  let normalized = corners.map { CGPoint(x: $0.x / frameSize.width, y: $0.y / frameSize.height) }
  return Rendered(image: image, truth: canonical(normalized), imageSize: frameSize)
}
private func rawFrame(_ source: CIImage, _ sample: Sample) -> Rendered {
  let truth = sample.rawQuad.map { quad -> ScannerQuadrilateral in
    let points = quad.map { CGPoint(x: $0[0], y: 1 - $0[1]) }
    return ScannerQuadrilateral(topLeft: points[0], topRight: points[1],
                                bottomRight: points[2], bottomLeft: points[3])
  }
  return Rendered(image: source, truth: truth, imageSize: source.extent.size)
}
private func quadrilateral(_ observation: VNRectangleObservation) -> ScannerQuadrilateral {
  ScannerQuadrilateral(topLeft: observation.topLeft, topRight: observation.topRight,
                       bottomRight: observation.bottomRight, bottomLeft: observation.bottomLeft)
}
private func cornerError(_ a: ScannerQuadrilateral, _ b: ScannerQuadrilateral, imageSize: CGSize) -> Double {
  let diagonal = hypot((b.topLeft.x - b.bottomRight.x) * imageSize.width,
                       (b.topLeft.y - b.bottomRight.y) * imageSize.height)
  guard diagonal > 0 else { return .infinity }
  return zip(a.points, b.points).map { hypot(($0.x - $1.x) * imageSize.width,
                                             ($0.y - $1.y) * imageSize.height) / diagonal }.max() ?? .infinity
}
private func polygonArea(_ p: [CGPoint]) -> Double {
  guard p.count > 2 else { return 0 }
  return abs(zip(p, Array(p.dropFirst()) + [p[0]]).reduce(0.0) {
    $0 + Double($1.0.x * $1.1.y - $1.1.x * $1.0.y)
  }) / 2
}
private func polygonIoU(_ a: ScannerQuadrilateral, _ b: ScannerQuadrilateral) -> Double {
  // Sutherland-Hodgman clipping in normalized coordinates; both quadrilaterals are convex.
  var polygon = a.points
  let clip = b.points
  let signed = zip(clip, Array(clip.dropFirst()) + [clip[0]]).reduce(0.0) {
    $0 + Double($1.0.x * $1.1.y - $1.1.x * $1.0.y)
  }
  for edge in 0..<4 {
    let p = clip[edge], q = clip[(edge + 1) % 4]
    func cross(_ r: CGPoint) -> CGFloat { (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x) }
    func inside(_ r: CGPoint) -> Bool { signed >= 0 ? cross(r) >= 0 : cross(r) <= 0 }
    var next: [CGPoint] = []
    for i in polygon.indices {
      let start = polygon[i], end = polygon[(i + 1) % polygon.count]
      let c1 = cross(start), c2 = cross(end)
      if inside(start) != inside(end) {
        let t = c1 / (c1 - c2)
        next.append(CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t))
      }
      if inside(end) { next.append(end) }
    }
    polygon = next
    if polygon.isEmpty { break }
  }
  let intersection = polygonArea(polygon)
  let union = polygonArea(a.points) + polygonArea(b.points) - intersection
  return union > 0 ? intersection / union : 0
}
private func memoryRSS() -> UInt64 {
  var usage = rusage()
  getrusage(RUSAGE_SELF, &usage)
  return UInt64(max(0, usage.ru_maxrss))
}
private func safeName(_ value: String) -> String {
  String(String(value.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character(String($0)) : "_" }).prefix(80))
}
private func writeDiagnostic(_ image: CIImage, truth: ScannerQuadrilateral?, live: ScannerQuadrilateral?,
                             still: ScannerQuadrilateral?, to url: URL) {
  let context = CIContext(options: [.useSoftwareRenderer: false])
  guard let cg = context.createCGImage(image, from: image.extent),
        let overlay = CGContext(data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: 0,
          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
        let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
  overlay.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
  let width = CGFloat(cg.width), height = CGFloat(cg.height)
  func outline(_ quad: ScannerQuadrilateral?, color: CGColor, dash: [CGFloat], lineWidth: CGFloat) {
    guard let quad else { return }
    overlay.setStrokeColor(color)
    overlay.setLineWidth(lineWidth)
    overlay.setLineDash(phase: 0, lengths: dash)
    overlay.beginPath()
    overlay.move(to: CGPoint(x: quad.topLeft.x * width, y: quad.topLeft.y * height))
    for point in quad.points.dropFirst() { overlay.addLine(to: CGPoint(x: point.x * width, y: point.y * height)) }
    overlay.closePath()
    overlay.strokePath()
  }
  // Wider truth remains visible underneath near-matching prediction lines.
  outline(truth, color: CGColor(red: 0.15, green: 1, blue: 0.2, alpha: 1), dash: [], lineWidth: 10)
  outline(live, color: CGColor(red: 0, green: 0.9, blue: 1, alpha: 1), dash: [16, 10], lineWidth: 5)
  outline(still, color: CGColor(red: 1, green: 0.1, blue: 0.7, alpha: 1), dash: [4, 12], lineWidth: 5)
  guard let annotated = overlay.makeImage() else { return }
  CGImageDestinationAddImage(destination, annotated, nil)
  _ = CGImageDestinationFinalize(destination)
}
private func csv(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
private func percentile(_ values: [Double], _ p: Double) -> Double {
  guard !values.isEmpty else { return 0 }
  let sorted = values.sorted()
  return sorted[min(sorted.count - 1, Int(ceil(Double(sorted.count) * p)) - 1)]
}
private func categoryGates(_ outcomes: [Outcome], _ sequences: [Sequence], samples: [Sample]) -> [CategoryGate] {
  Set(samples.map(\.category)).sorted().map { category in
    let rows = outcomes.filter { $0.category == category }
    let normal = rows.filter { $0.family == "normal" }
    let unsafe = rows.filter { $0.unsafeAuto || $0.unsafeStill || $0.unsafeQuality }.count
    let unsafeReady = sequences.filter { $0.category == category && $0.unsafeReady }.count
    let normalHits = normal.filter(\.accurate).count
    let stillNormalHits = normal.filter(\.stillAccurate).count
    let normalNames = Set(normal.map { "held_\($0.variant)" })
    let normalReady = sequences.filter { $0.category == category && normalNames.contains($0.name) && $0.ready }.count
    let generated = rows.contains { $0.family != "raw_capture" }
    let generatedSamples = samples.filter { $0.category == category && $0.capture != "raw" }
    let complete = generated ? generatedSamples.allSatisfy { sample in
      let sourceRows = rows.filter { $0.id == sample.id }
      return sourceRows.filter { $0.family == "normal" }.count == 8 &&
        sourceRows.filter { $0.family == "framing_negative" }.count == 6
    } : rows.contains { $0.expected && $0.accurate && $0.stillAccurate }
    let failed = unsafe > 0 || unsafeReady > 0 || (generated && (normalHits != normal.count || stillNormalHits != normal.count || normalReady != normal.count))
    return CategoryGate(category: category, gate: failed ? "FAIL" : (complete ? "PASS" : "PARTIAL"))
  }
}
private func markdown(_ outcomes: [Outcome], _ sequences: [Sequence], samples: [Sample], peakRSS: UInt64,
                      gates: [CategoryGate], missingCategories: [String]) -> String {
  let overallP50 = String(format: "%.1f", percentile(outcomes.map(\.milliseconds), 0.5))
  let overallP95 = String(format: "%.1f", percentile(outcomes.map(\.milliseconds), 0.95))
  let stillP95 = String(format: "%.1f", percentile(outcomes.map(\.stillMilliseconds), 0.95))
  let overallRSS = String(format: "%.1f", Double(peakRSS) / 1_048_576)
  var lines = ["# Scanner framing report", "", "Generated camera frames use a 1440 × 1920 canvas; raw captures retain their EXIF-oriented dimensions. Production `ScannerRectangleDetector.detect` is called for every live and still frame. Framing accuracy requires maximum corner error ≤3% of the annotated document diagonal, polygon IoU ≥0.85, complete corners, and profile acceptance. Any eligible wrong boundary is an unsafe auto capture, including on difficult positives.", "", "Generated cases reproject real document content. Raw cases evaluate the original photo using independently annotated corners. The detector rejects severe defocus using an edge-spread check; accepting a severe-blur challenge fails this gate even with accurate corners. Other quality labels describe challenges, not verified legibility. Framing PASS does not certify OCR, readability, authenticity, physical camera speed, or TestFlight acceptance. Categories absent from the manifest are untested.", "", "Samples: \(samples.count). Frames: \(outcomes.count). Peak process RSS: \(overallRSS) MiB. Live detection p50/p95: \(overallP50) / \(overallP95) ms; still p95: \(stillP95) ms.", "", "| Category | Inputs | Normal live accurate | Normal still accurate | All framing-safe live accurate | Normal hold ready | Unsafe live (all frames) | Unsafe still (all frames) | Unsafe hold ready | Unsafe quality | Quality-labeled frames | Live p95 ms | Gate |", "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|"]
  for category in Set(samples.map(\.category)).sorted() {
    let rows = outcomes.filter { $0.category == category }
    let normal = rows.filter { $0.family == "normal" }
    let positives = rows.filter(\.expected)
    let unsafe = rows.filter(\.unsafeAuto).count
    let unsafeStill = rows.filter(\.unsafeStill).count
    let unsafeReady = sequences.filter { $0.category == category && $0.unsafeReady }.count
    let unsafeQuality = rows.filter(\.unsafeQuality).count
    let quality = rows.filter { $0.qualityConcern != nil }.count
    let normalHits = normal.filter(\.accurate).count
    let stillNormalHits = normal.filter(\.stillAccurate).count
    let allHits = positives.filter(\.accurate).count
    let normalNames = Set(normal.map { "held_\($0.variant)" })
    let normalReady = sequences.filter { $0.category == category && normalNames.contains($0.name) && $0.ready }.count
    let gate = gates.first { $0.category == category }?.gate ?? "PARTIAL"
    let categoryP95 = String(format: "%.1f", percentile(rows.map(\.milliseconds), 0.95))
    let cleanCategory = category.replacingOccurrences(of: "|", with: "/")
    lines.append("| \(cleanCategory) | \(samples.filter { $0.category == category }.count) | \(normalHits)/\(normal.count) | \(stillNormalHits)/\(normal.count) | \(allHits)/\(positives.count) | \(normalReady)/\(normal.count) | \(unsafe)/\(rows.count) | \(unsafeStill)/\(rows.count) | \(unsafeReady) | \(unsafeQuality) | \(quality) | \(categoryP95) | \(gate) |")
  }
  if !missingCategories.isEmpty {
    lines += ["", "Required categories missing from this run: \(missingCategories.joined(separator: ", "))."]
  }
  let failures = outcomes.filter { ($0.expected && (!$0.accurate || !$0.stillAccurate)) || $0.unsafeAuto || $0.unsafeStill || $0.unsafeQuality }
  let variants = Dictionary(grouping: failures, by: \.variant)
    .map { "\($0.key) \($0.value.count)" }.sorted().joined(separator: ", ")
  lines += ["", "Framing misses or unsafe selections: \(failures.count). Accepted severe-blur frames: \(outcomes.filter(\.unsafeQuality).count). A no-detection difficult positive requests retake and appears in accuracy counts; only an eligible wrong crop is unsafe. Failure variants: \(variants.isEmpty ? "none" : variants). The detailed JSON and CSV contain anonymous source IDs, labels, variant names, and metrics only.", ""]
  return lines.joined(separator: "\n")
}

let options = parseOptions()
let output = options.output!.standardizedFileURL
do { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
catch { fail("cannot create output directory") }
guard !insideRepository(output) else { fail("--output must be outside the repository") }
let manifest: Manifest
if options.smoke {
  manifest = Manifest(samples: [Sample(id: "synthetic", category: "synthetic_smoke", layout: "portrait",
                                       documentKey: nil, path: "", split: "smoke", capture: nil,
                                       rawQuad: nil, framingSafe: nil, qualityConcern: nil)], requiredCategories: nil)
} else {
  guard !insideRepository(options.manifest!) else {
    fail("manifest must be outside the repository")
  }
  guard let data = try? Data(contentsOf: options.manifest!),
        let decoded = try? JSONDecoder().decode(Manifest.self, from: data) else { fail("invalid manifest JSON") }
  manifest = decoded
}
let samples = Array(manifest.samples.filter { options.split == nil || $0.split == options.split }.prefix(options.limit))
guard !samples.isEmpty else { fail("no samples selected") }
guard Set(samples.map(\.id)).count == samples.count else { fail("sample IDs must be unique") }
guard samples.allSatisfy({ FoorsaScannerProfile.Layout(rawValue: $0.layout) != nil }) else { fail("manifest has an unsupported layout") }
guard samples.allSatisfy({ sample in
  if sample.capture == nil || sample.capture == "source" { return sample.rawQuad == nil && sample.framingSafe == nil }
  guard sample.capture == "raw", sample.framingSafe != nil else { return false }
  if sample.framingSafe == true && sample.rawQuad == nil { return false }
  guard let quad = sample.rawQuad else { return true }
  return quad.count == 4 && quad.allSatisfy { point in
    point.count == 2 && point.allSatisfy { $0.isFinite && $0 >= -0.5 && $0 <= 1.5 }
  } && polygonArea(quad.map { CGPoint(x: $0[0], y: $0[1]) }) >= 0.01
}) else { fail("invalid capture or raw quadrilateral annotation") }
let allVariants = Array(perturbed(variants(), seed: options.seed).prefix(options.variants))
var outcomes: [Outcome] = []
var sequences: [Sequence] = []
var diagnosticCount = 0
for sample in samples {
  let raw = sample.capture == "raw"
  let source = options.smoke ? syntheticSource() : load(sample, raw: raw)
  let profile = FoorsaScannerProfile(arguments: ["profile": ["layout": sample.layout,
    "documentKey": sample.documentKey ?? sample.category]])
  var recent: [String: ScannerQuadrilateral?] = [:]
  let sampleVariants = raw ? [Variant(name: "raw_capture", family: "raw_capture", scale: 1,
    rotation: 0, tilt: 0, background: 0, blur: 0, contrast: 1, glare: 0, shadow: 0,
    clutter: false, inner: false, offset: .zero, expected: sample.framingSafe!,
    qualityConcern: sample.qualityConcern)] : allVariants
  for variant in sampleVariants {
    autoreleasepool {
    let frame = raw ? rawFrame(source, sample) : render(source, variant)
    let started = CFAbsoluteTimeGetCurrent()
    let live: VNRectangleObservation?
    let still: VNRectangleObservation?
    do {
      live = try ScannerRectangleDetector.detect(in: frame.image, profile: profile, purpose: .live)
      let liveElapsed = (CFAbsoluteTimeGetCurrent() - started) * 1000
      let stillStarted = CFAbsoluteTimeGetCurrent()
      still = try ScannerRectangleDetector.detect(in: frame.image, profile: profile, purpose: .still)
      let stillElapsed = (CFAbsoluteTimeGetCurrent() - stillStarted) * 1000
      let quad = live.map(quadrilateral)
      let stillQuad = still.map(quadrilateral)
      let eligible = quad.map { $0.isComplete(minimumArea: profile.minimumCaptureArea) && profile.accepts(aspectRatio: $0.estimatedAspectRatio(in: frame.imageSize)) } ?? false
      let error = quad.flatMap { q in frame.truth.map { cornerError(q, $0, imageSize: frame.imageSize) } }
      let iou = quad.flatMap { q in frame.truth.map { polygonIoU(q, $0) } }
      let accurate = variant.expected && eligible && (error ?? .infinity) <= 0.03 && (iou ?? 0) >= 0.85
      let stillError = stillQuad.flatMap { q in frame.truth.map { cornerError(q, $0, imageSize: frame.imageSize) } }
      let stillIoU = stillQuad.flatMap { q in frame.truth.map { polygonIoU(q, $0) } }
      let stillEligible = stillQuad.map { $0.isComplete(minimumArea: 0.12) && profile.accepts(aspectRatio: $0.estimatedAspectRatio(in: frame.imageSize)) } ?? false
      let stillAccurate = variant.expected && stillEligible && (stillError ?? .infinity) <= 0.03 && (stillIoU ?? 0) >= 0.85
      let unsafeAuto = eligible && (!variant.expected || !accurate)
      let unsafeStill = stillEligible && (!variant.expected || !stillAccurate)
      // Severe defocus must request a retake even when its outline is correct.
      // Other quality labels remain descriptive until independently calibrated.
      let unsafeQuality = variant.qualityConcern == "severe_blur" && (eligible || stillEligible)
      outcomes.append(Outcome(id: sample.id, category: sample.category, layout: sample.layout,
        split: sample.split ?? "unspecified", variant: variant.name, family: variant.family,
        imageSize: [Int(frame.imageSize.width), Int(frame.imageSize.height)], qualityConcern: variant.qualityConcern,
        expected: variant.expected, detected: live != nil, eligible: eligible, accurate: accurate,
        unsafeAuto: unsafeAuto, cornerError: error, polygonIoU: iou, milliseconds: liveElapsed,
        stillMilliseconds: stillElapsed, stillCornerError: stillError, stillPolygonIoU: stillIoU, stillDetected: still != nil, stillAccurate: stillAccurate, unsafeStill: unsafeStill, unsafeQuality: unsafeQuality))
      recent[variant.name] = eligible ? quad : nil
      if diagnosticCount < options.diagnostics && ((variant.expected && (!accurate || !stillAccurate)) || unsafeAuto || unsafeStill || unsafeQuality) {
        let dir = output.appendingPathComponent("diagnostics", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard !insideRepository(dir) else { fail("diagnostics directory must be outside the repository") }
        let destination = dir.appendingPathComponent("\(safeName(sample.id))_\(variant.name).png")
        guard !insideRepository(destination) else { fail("diagnostic file must be outside the repository") }
        writeDiagnostic(frame.image, truth: frame.truth, live: quad, still: stillQuad, to: destination)
        diagnosticCount += 1
      }
    } catch { fail("Vision detection failed for \(sample.id)/\(variant.name)") }
    }
  }
  // Every candidate is held steady to expose auto capture of a bad boundary or negative frame.
  // The tracker consumes actual production-selected observations, after profile acceptance.
  let held = recent["p00"] ?? nil
  for variant in sampleVariants {
    var heldTracker = ScannerStabilityTracker(minimumArea: profile.minimumCaptureArea)
    var heldReady = false
    for tick in 0..<9 {
      heldReady = heldTracker.observe(recent[variant.name] ?? nil, at: Double(tick) * 0.12).ready || heldReady
    }
    let row = outcomes.last { $0.id == sample.id && $0.variant == variant.name }
    sequences.append(Sequence(id: sample.id, category: sample.category,
      name: "held_\(variant.name)", ready: heldReady, unsafeReady: heldReady && (row?.accurate != true || row?.unsafeQuality == true)))
  }
  // Dropout and alternating movement must revoke or delay readiness.
  var tracker = ScannerStabilityTracker(minimumArea: profile.minimumCaptureArea)
  for tick in 0..<9 { _ = tracker.observe(held, at: Double(tick) * 0.12) }
  let dropped = tracker.observe(nil, at: 1.10)
  sequences.append(Sequence(id: sample.id, category: sample.category, name: "dropout", ready: dropped.ready, unsafeReady: dropped.ready))
  tracker.reset()
  var motionReady = false
  let alternate = recent["p03"] ?? nil
  for tick in 0..<9 { motionReady = tracker.observe(tick % 2 == 0 ? held : alternate, at: Double(tick) * 0.12).ready || motionReady }
  sequences.append(Sequence(id: sample.id, category: sample.category, name: "alternating_motion", ready: motionReady, unsafeReady: motionReady))
  let sampleRows = outcomes.suffix(sampleVariants.count)
  let normalRows = sampleRows.filter { $0.family == "normal" }
  let unsafeRows = sampleRows.filter { $0.unsafeAuto || $0.unsafeStill || $0.unsafeQuality }
  print("\(sample.id): \(sampleVariants.count) frames complete; normal \(normalRows.filter { $0.accurate && $0.stillAccurate }.count)/\(normalRows.count); unsafe \(unsafeRows.count)")
  fflush(stdout)
}
let report = Report(schema: 3, frameSize: [Int(frameSize.width), Int(frameSize.height)], selectedSamples: samples.count,
                    requestedVariantsPerSample: options.variants, perturbationSeed: options.seed, outcomes: outcomes, sequences: sequences, peakRSSBytes: memoryRSS())
let gates = categoryGates(outcomes, sequences, samples: samples)
let selectedCategories = Set(samples.map(\.category))
let missingCategories = (manifest.requiredCategories ?? []).filter { !selectedCategories.contains($0) }.sorted()
let gateReport = GateReport(pass: missingCategories.isEmpty && gates.allSatisfy { $0.gate == "PASS" },
                            missingCategories: missingCategories, categories: gates)
let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
do {
  try encoder.encode(report).write(to: output.appendingPathComponent("metrics.json"), options: .atomic)
  var csvLines = ["id,category,layout,split,variant,family,image_width,image_height,quality_concern,framing_safe,detected,eligible,accurate,unsafe_auto,corner_error,polygon_iou,live_milliseconds,still_milliseconds,still_corner_error,still_polygon_iou,still_detected,still_accurate,unsafe_still,unsafe_quality"]
  for row in outcomes {
    csvLines.append([csv(row.id), csv(row.category), csv(row.layout), csv(row.split), csv(row.variant), csv(row.family),
      String(row.imageSize[0]), String(row.imageSize[1]), csv(row.qualityConcern ?? ""),
      String(row.expected), String(row.detected), String(row.eligible), String(row.accurate), String(row.unsafeAuto),
      row.cornerError.map { String($0) } ?? "", row.polygonIoU.map { String($0) } ?? "", String(row.milliseconds), String(row.stillMilliseconds),
      row.stillCornerError.map { String($0) } ?? "", row.stillPolygonIoU.map { String($0) } ?? "",
      String(row.stillDetected), String(row.stillAccurate), String(row.unsafeStill), String(row.unsafeQuality)].joined(separator: ","))
  }
  try (csvLines.joined(separator: "\n") + "\n").write(to: output.appendingPathComponent("metrics.csv"), atomically: true, encoding: .utf8)
  try encoder.encode(gateReport).write(to: output.appendingPathComponent("gate.json"), options: .atomic)
  try markdown(outcomes, sequences, samples: samples, peakRSS: report.peakRSSBytes,
               gates: gates, missingCategories: missingCategories)
    .write(to: output.appendingPathComponent("report.md"), atomically: true, encoding: .utf8)
} catch { fail("could not write report") }
print("Report: \(output.appendingPathComponent("report.md").path)")
if options.requirePass && !gateReport.pass { exit(1) }
