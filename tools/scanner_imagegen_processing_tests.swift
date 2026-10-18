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
    // custom-live-v11: strict detection finds no boundary on this source, so
    // both capture modes crop from the live outline the student saw when the
    // shutter fired.
    var result: ScannerProcessedCandidate?
    for profile in [ordinary, imagegen] {
      let crop = try processor.processCapture(photoData: source, profile: profile,
        liveQuadrilateral: quad, liveImageSize: bounds.size).get()
      precondition(!crop.jpeg.isEmpty && crop.correctedImage != nil)
      precondition(crop.correctedImage!.width < 900 && crop.correctedImage!.height < 1200)
      if profile.usesImagegen { result = crop }
    }
    // Automatic capture without live geometry never fabricates a crop.
    for profile in [ordinary, imagegen] {
      guard case .failure(.documentBoundaryNotFound) = processor.processCapture(
        photoData: source, profile: profile) else { fatalError("missing live geometry must not fabricate a crop") }
    }
    // A photo taken by hand keeps a real page or, failing that, the whole frame.
    let manual = try processor.processCapture(photoData: source, profile: imagegen, allowFullFrame: true).get()
    precondition(manual.correctedImage != nil && !manual.jpeg.isEmpty)
    let blank = jpeg(CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: bounds))
    let blur = jpeg(page.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 10]).cropped(to: bounds))
    for profile in [ordinary, imagegen] {
      guard case .failure(.photoTooSoft) = processor.processCapture(photoData: blank,
        profile: profile, liveQuadrilateral: quad, liveImageSize: bounds.size)
        else { fatalError("empty content must not be a usable view") }
      guard case .failure(.photoTooSoft) = processor.processCapture(photoData: blur,
        profile: profile, liveQuadrilateral: quad, liveImageSize: bounds.size)
        else { fatalError("severe blur must not bypass the clarity gate") }
      guard case .failure(.photoTooSoft) = processor.processCapture(photoData: blank,
        profile: profile, allowFullFrame: true)
        else { fatalError("a blank photo taken by hand is still rejected") }
    }
    var pool = ScannerOriginalPhotoPool()
    precondition(pool.append(source) && pool.photos[0] == source)
    precondition(pool.photos[0] != result!.jpeg)
    print("PASS: live-outline crop in both modes, missing-geometry rejection, manual whole-frame photo, empty/blur rejection in both modes, original versus preview separation")
  }
}
