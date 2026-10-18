import Foundation
import CoreImage
import ImageIO

@main
struct ScannerImagegenProcessingTests {
  static func main() throws {
    let processor = ScannerImageProcessor()
    let ordinary = FoorsaScannerProfile(arguments: ["profile": ["documentKey": "drive_files"]])
    let imagegen = FoorsaScannerProfile(arguments: ["profile": ["documentKey": "drive_files", "outputMode": "imagegen"]])
    let bounds = CGRect(x: 0, y: 0, width: 900, height: 1200)
    var page = CIImage(color: CIColor(red: 0.92, green: 0.92, blue: 0.92)).cropped(to: bounds)
    for row in 0..<24 {
      // Sharp text-like marks with no visible outer page boundary.
      for column in 0..<12 {
        let glyph = CIImage(color: CIColor(red: 0.12, green: 0.12, blue: 0.12))
          .cropped(to: CGRect(x: 160 + column * 45, y: 190 + row * 32,
            width: 8 + column % 4, height: 16))
        page = glyph.composited(over: page)
      }
    }
    let context = CIContext()
    func jpeg(_ image: CIImage) -> Data {
      context.jpegRepresentation(of: image, colorSpace: CGColorSpaceCreateDeviceRGB(),
        options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.95])!
    }
    let source = jpeg(page)
    let quad = ScannerQuadrilateral(topLeft: CGPoint(x: 0.1, y: 0.9),
      topRight: CGPoint(x: 0.9, y: 0.9), bottomRight: CGPoint(x: 0.9, y: 0.1),
      bottomLeft: CGPoint(x: 0.1, y: 0.1))
    // The same source fails strict boundary detection; only the explicit mode
    // may use the stable shutter-time live outline to produce an OCR preview.
    guard case .failure(.documentBoundaryNotFound) = processor.processCapture(
      photoData: source, profile: ordinary, liveQuadrilateral: quad, liveImageSize: bounds.size)
      else { fatalError("ordinary mode must preserve strict boundary policy") }
    let result = try processor.processCapture(photoData: source, profile: imagegen,
      liveQuadrilateral: quad, liveImageSize: bounds.size).get()
    precondition(!result.jpeg.isEmpty && result.correctedImage != nil)
    precondition(result.correctedImage!.width < 900 && result.correctedImage!.height < 1200)
    guard case .failure(.documentBoundaryNotFound) = processor.processCapture(
      photoData: source, profile: imagegen) else { fatalError("missing live geometry must not fabricate a crop") }
    let blank = jpeg(CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: bounds))
    guard case .failure(.photoTooSoft) = processor.processCapture(photoData: blank,
      profile: imagegen, liveQuadrilateral: quad, liveImageSize: bounds.size)
      else { fatalError("empty content must not be a usable fallback view") }
    let blur = jpeg(page.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 10]).cropped(to: bounds))
    guard case .failure(.photoTooSoft) = processor.processCapture(photoData: blur,
      profile: imagegen, liveQuadrilateral: quad, liveImageSize: bounds.size)
      else { fatalError("severe blur must not bypass the clarity gate") }
    var pool = ScannerOriginalPhotoPool()
    precondition(pool.append(source) && pool.photos[0] == source)
    precondition(pool.photos[0] != result.jpeg)
    print("PASS: real source crop fallback, default strict boundary gating, missing-geometry rejection, empty/blur rejection, original versus preview separation")
  }
}
