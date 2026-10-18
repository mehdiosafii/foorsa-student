import CoreGraphics
import CoreImage
import Foundation

// macOS (Vision) check for custom-live-v11 live detection on synthetic scenes:
// a page held over a busy background, sometimes with a hand across one edge,
// versus the same clutter with no page at all. Synthetic scenes are not
// camera frames; physical-device acceptance remains separate. The test prints
// every case and fails on any page-free scene judged ready, or when the new
// path finds fewer pages than the strict cascade it replaces for live use.
@main
struct ScannerLiveDetectionTests {
  struct Generator {
    var state: UInt64
    mutating func next() -> Double {
      state = state &* 6364136223846793005 &+ 1442695040888963407
      return Double(state >> 11) / Double(1 << 53)
    }
    mutating func range(_ low: Double, _ high: Double) -> Double { low + (high - low) * next() }
  }

  static let space = CGColorSpace(name: CGColorSpace.sRGB)!

  static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
    CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
  }

  /// Corners in normalized bottom-left coordinates: TL, TR, BR, BL.
  static func scene(width: Int, height: Int, page: [CGPoint]?, seed: UInt64, hand: Bool) -> CGImage {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    var random = Generator(state: seed)
    let w = CGFloat(width), h = CGFloat(height)
    // A dark, warm room: sofa, clothes, legs. Nothing in the clutter is paper-white.
    context.setFillColor(CGColor(colorSpace: space, components: [0.22, 0.24, 0.20, 1])!)
    context.fill(CGRect(x: 0, y: 0, width: w, height: h))
    for _ in 0..<16 {
      let color = [random.range(0.15, 0.62), random.range(0.12, 0.55), random.range(0.10, 0.48), 1]
      context.setFillColor(CGColor(colorSpace: space, components: color.map { CGFloat($0) })!)
      let rect = CGRect(x: random.range(-0.2, 0.9) * w, y: random.range(-0.2, 0.9) * h,
        width: random.range(0.1, 0.6) * w, height: random.range(0.1, 0.6) * h)
      if random.next() < 0.5 { context.fillEllipse(in: rect) } else { context.fill(rect) }
    }
    // Fabric texture.
    for _ in 0..<900 {
      let v = random.range(0.1, 0.5)
      context.setFillColor(CGColor(colorSpace: space, components: [v, v * 0.95, v * 0.85, 0.35])!)
      context.fill(CGRect(x: random.next() * w, y: random.next() * h, width: 3, height: 3))
    }
    if let page {
      let p = page.map { CGPoint(x: $0.x * w, y: $0.y * h) }
      context.setFillColor(CGColor(colorSpace: space, components: [0.95, 0.94, 0.92, 1])!)
      context.beginPath()
      context.move(to: p[0]); p.dropFirst().forEach { context.addLine(to: $0) }
      context.closePath(); context.fillPath()
      // Printed lines that follow the page's perspective.
      context.setStrokeColor(CGColor(colorSpace: space, components: [0.12, 0.12, 0.14, 1])!)
      context.setLineWidth(max(2, w * 0.004))
      for row in 0..<24 {
        let t = 0.1 + 0.8 * CGFloat(row) / 24
        let left = lerp(p[0], p[3], t), right = lerp(p[1], p[2], t)
        var u: CGFloat = 0.08
        while u < 0.9 {
          let length = CGFloat(random.range(0.04, 0.14))
          context.move(to: lerp(left, right, u))
          context.addLine(to: lerp(left, right, min(0.92, u + length)))
          u += length + 0.03
        }
      }
      context.strokePath()
      if hand {
        // A thumb and palm over the middle of the left edge.
        let mid = lerp(p[0], p[3], 0.5)
        context.setFillColor(CGColor(colorSpace: space, components: [0.78, 0.58, 0.46, 1])!)
        context.fillEllipse(in: CGRect(x: mid.x - w * 0.12, y: mid.y - h * 0.08, width: w * 0.2, height: h * 0.16))
      }
    }
    return context.makeImage()!
  }

  static func error(_ quad: ScannerQuadrilateral?, _ truth: [CGPoint], size: CGSize) -> Double {
    guard let quad else { return .infinity }
    let diagonal = hypot(size.width, size.height)
    return zip(quad.points, truth).map {
      Double(hypot(($0.x - $1.x) * size.width, ($0.y - $1.y) * size.height) / diagonal)
    }.max() ?? .infinity
  }

  static func main() {
    let profile = FoorsaScannerProfile(arguments: ["profile": ["documentKey": "highest_degree", "outputMode": "imagegen"]])
    let size = CGSize(width: 1080, height: 1440)
    var random = Generator(state: 20261018)
    var newFound = 0, strictFound = 0, positives = 0, falseReady = 0
    for index in 0..<24 {
      let landscape = index % 2 == 1
      let cx = random.range(0.42, 0.58), cy = random.range(0.42, 0.58)
      let halfW = landscape ? random.range(0.36, 0.44) : random.range(0.30, 0.36)
      let halfH = landscape ? halfW * 0.71 * Double(size.width / size.height) : halfW * 1.41 * Double(size.width / size.height)
      let angle = random.range(-0.18, 0.18), skew = random.range(-0.05, 0.05)
      func corner(_ sx: Double, _ sy: Double) -> CGPoint {
        let x = sx * halfW * (1 + (sy > 0 ? skew : -skew)), y = sy * halfH
        let ax = x * Double(size.width), ay = y * Double(size.height)
        let rx = ax * cos(angle) - ay * sin(angle), ry = ax * sin(angle) + ay * cos(angle)
        return CGPoint(x: cx + rx / Double(size.width), y: cy + ry / Double(size.height))
      }
      let truth = [corner(-1, 1), corner(1, 1), corner(1, -1), corner(-1, -1)]
      let image = CIImage(cgImage: scene(width: Int(size.width), height: Int(size.height), page: truth,
        seed: UInt64(1000 + index), hand: index % 3 == 0))
      let live = ScannerRectangleDetector.detectLive(in: image, profile: profile)
      let strict = (try? ScannerRectangleDetector.detect(in: image, profile: profile, purpose: .live))
        .map(ScannerQuadrilateral.init)
      let liveError = error(live.quadrilateral, truth, size: size)
      let strictError = error(strict, truth, size: size)
      let liveOK = live.framing == .ready && liveError <= 0.04
      let strictOK = strictError <= 0.04
      positives += 1
      if liveOK { newFound += 1 }
      if strictOK { strictFound += 1 }
      print(String(format: "page %02d %@%@ live=%@ err=%.3f strict err=%.3f", index,
        landscape ? "landscape" : "portrait", index % 3 == 0 ? "+hand" : "",
        live.framing.rawValue, liveError, strictError))
    }
    for index in 0..<12 {
      let image = CIImage(cgImage: scene(width: Int(size.width), height: Int(size.height), page: nil,
        seed: UInt64(5000 + index), hand: false))
      let live = ScannerRectangleDetector.detectLive(in: image, profile: profile)
      if live.framing == .ready { falseReady += 1 }
      print("clutter \(index) live=\(live.framing.rawValue)")
    }
    print("SUMMARY new=\(newFound)/\(positives) strict=\(strictFound)/\(positives) falseReady=\(falseReady)/12")
    precondition(falseReady == 0, "a scene without a page must never be ready to capture")
    precondition(newFound >= strictFound, "live detection must find at least the pages the strict cascade found")
    print("PASS: synthetic hand-held pages and page-free clutter")
  }
}
