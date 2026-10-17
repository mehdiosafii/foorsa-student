import Foundation
import CoreGraphics
import CoreImage

// Calibrated at a fixed preview scale and the scanner capture guide. A zero-support
// result means insufficient content, not verified blur. This is not an OCR score.
struct ClarityScores: Codable {
  let q50: Double
  let q75: Double
  let q90: Double
  let broadThreshold: Double
  let support: Int
  let milliseconds: Double
}
// Measures edge spread in central image content, independently of rectangle detection.
// At a fixed preview scale, broad derivative finds coherent edges; the maximum
// short derivative near each edge measures how concentrated its transition is.
// Ratios approach 1 for a step and 0.25 for a transition wider than 8 pixels.
// The central region avoids relying on the possibly mislocalized paper boundary.
enum ContentClarity {
  private static let context = CIContext(options: [.useSoftwareRenderer: false, .cacheIntermediates: false])
  struct Configuration {
    var longestSide: CGFloat = 768
    var maximumSelectedEdges: Int = 4096
    var horizontalInset: Double = 0.2
    var verticalInset: Double = 0.25
  }
  static func score(_ image: CIImage, configuration: Configuration = Configuration()) -> ClarityScores {
    let start = CFAbsoluteTimeGetCurrent()
    let invalid = ClarityScores(q50: 0, q75: 0, q90: 0, broadThreshold: 0, support: 0, milliseconds: 0)
    guard !image.extent.isInfinite, !image.extent.isNull,
      image.extent.minX.isFinite, image.extent.minY.isFinite,
      image.extent.width.isFinite, image.extent.height.isFinite,
      image.extent.width > 0, image.extent.height > 0,
      configuration.longestSide.isFinite, (64...2048).contains(configuration.longestSide),
      configuration.maximumSelectedEdges > 0,
      configuration.horizontalInset.isFinite, configuration.verticalInset.isFinite,
      (0.02...0.45).contains(configuration.horizontalInset),
      (0.02...0.45).contains(configuration.verticalInset) else { return invalid }
    let scale = configuration.longestSide / max(image.extent.width, image.extent.height)
    let normalized = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
    let scaled = normalized.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    guard !scaled.extent.isInfinite, !scaled.extent.isNull,
      scaled.extent.width.isFinite, scaled.extent.height.isFinite,
      scaled.extent.width <= configuration.longestSide + 2,
      scaled.extent.height <= configuration.longestSide + 2 else { return invalid }
    let w = Int(scaled.extent.width), h = Int(scaled.extent.height)
    guard w >= 32, h >= 32 else { return invalid }
    var rgba = [UInt8](repeating: 0, count: w*h*4)
    context.render(scaled, toBitmap: &rgba, rowBytes: w*4,
      bounds: CGRect(x:0,y:0,width:w,height:h), format: .RGBA8,
      colorSpace: CGColorSpaceCreateDeviceRGB())
    var luma = [Float](repeating:0, count:w*h)
    for i in luma.indices { luma[i] = (Float(rgba[i*4])*0.2126 + Float(rgba[i*4+1])*0.7152 + Float(rgba[i*4+2])*0.0722) }
    var candidates: [(Float,Float)] = []
    let minY=max(4,Int(Double(h)*configuration.verticalInset))
    let maxY=min(h-4,Int(Double(h)*(1-configuration.verticalInset)))
    let minX=max(4,Int(Double(w)*configuration.horizontalInset))
    let maxX=min(w-4,Int(Double(w)*(1-configuration.horizontalInset)))
    for y in minY..<maxY {
      for x in minX..<maxX {
        let i = y*w+x
        let dx = abs(luma[i+4]-luma[i-4]), dy = abs(luma[i+4*w]-luma[i-4*w])
        let horizontal = dx >= dy, broad = max(dx,dy)
        if broad < 8 { continue }
        let step = horizontal ? 1 : w
        var fine: Float = 0
        for shift in -3...3 {
          fine = max(fine, abs(luma[i+(shift+1)*step]-luma[i+(shift-1)*step]))
        }
        candidates.append((broad, min(2, fine/broad)))
      }
    }
    candidates.sort { $0.0 > $1.0 }
    let count = min(candidates.count, max(1, configuration.maximumSelectedEdges), max(24, Int(Double(w*h)*0.3*0.02)))
    let ratios = candidates.prefix(count).map { Double($0.1) }.sorted()
    func q(_ p: Double)->Double { ratios.isEmpty ? 0 : ratios[min(ratios.count-1,Int(Double(ratios.count-1)*p))] }
    return ClarityScores(q50:q(0.5),q75:q(0.75),q90:q(0.9),
      broadThreshold: count == 0 ? 0 : Double(candidates[count-1].0),support:count,
      milliseconds:(CFAbsoluteTimeGetCurrent()-start)*1000)
  }
}
