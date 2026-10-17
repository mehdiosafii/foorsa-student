import CoreGraphics
import CoreImage
import ImageIO
import Vision


// Bitmap rows are top-origin; boundary geometry uses Vision bottom-origin.
private struct BoundaryPixels {
  private static let context = CIContext(options: [.useSoftwareRenderer: false, .cacheIntermediates: false])
  let width: Int
  let height: Int
  let rgba: [UInt8]
  init?(image: CIImage) {
    let e = image.extent
    guard !e.isInfinite, !e.isNull, e.minX.isFinite, e.minY.isFinite,
      e.width.isFinite, e.height.isFinite, e.width > 0, e.height > 0 else { return nil }
    let scale = min(1, 384 / max(e.width, e.height))
    let scaledWidth = (e.width * scale).rounded(), scaledHeight = (e.height * scale).rounded()
    guard scaledWidth >= 16, scaledHeight >= 16 else { return nil }
    width = Int(scaledWidth)
    height = Int(scaledHeight)
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    // Core Image defaults to high-quality downsampling on macOS but not iOS.
    // Match boundary evidence across devices and avoid aliasing thin printed strokes.
    let normalized = image.transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY))
      .transformed(by: CGAffineTransform(scaleX: CGFloat(width) / e.width, y: CGFloat(height) / e.height), highQualityDownsample: true)
    Self.context.render(normalized, toBitmap: &bytes, rowBytes: width * 4,
      bounds: CGRect(x: 0, y: 0, width: width, height: height), format: .RGBA8,
      colorSpace: CGColorSpaceCreateDeviceRGB())
    rgba = bytes
  }
  func color(_ p: CGPoint) -> SIMD3<Double>? {
    guard p.x.isFinite, p.y.isFinite, p.x >= 1, p.x < CGFloat(width - 1),
      p.y >= 1, p.y < CGFloat(height - 1) else { return nil }
    let x = Int(p.x.rounded()), y = Int((CGFloat(height) - p.y).rounded())
    guard x >= 1, x < width - 1, y >= 1, y < height - 1 else { return nil }
    let i = (y * width + x) * 4
    return SIMD3(Double(rgba[i]), Double(rgba[i+1]), Double(rgba[i+2]))
  }
  struct Line {
    let a: CGPoint
    let b: CGPoint
    let broad: Double
    let sharp: Double
    let coherence: Double
  }
  func evidence(a: CGPoint, b: CGPoint, n: CGPoint) -> (Double, Double, Double, Double) {
    var broad: [Double] = [], near: [Double] = []
    var vector = SIMD3<Double>(repeating: 0)
    var magnitude = 0.0
    for i in 0..<17 {
      let t = CGFloat(i + 3) / 22
      let p = CGPoint(x: a.x + (b.x-a.x)*t, y: a.y + (b.y-a.y)*t)
      func sample(_ d: CGFloat) -> SIMD3<Double>? { color(CGPoint(x: p.x+n.x*d, y:p.y+n.y*d)) }
      guard let i8=sample(-7), let o8=sample(7), let i2=sample(-1.5), let o2=sample(1.5) else { continue }
      let v = i8-o8, u = i2-o2
      let norm = sqrt((v*v).sum()/3), sharp = sqrt((u*u).sum()/3)
      vector += v; magnitude += norm
      broad.append(norm); near.append(sharp)
    }
    guard broad.count >= 14 else { return (0,0,0,0) }
    broad.sort(); near.sort()
    let b = broad[broad.count/3], s = near[near.count/3]
    let consistency = min(1, sqrt((vector*vector).sum()/3) / max(1,magnitude))
    // A broad color step rejects printed strokes; a narrow step localizes the border.
    let score = min(b, s * 1.8) * consistency
    return (score,b,s,consistency)
  }
  func outline(_ rectangle: VNRectangleObservation) -> [(Double, Double, Double, Double)] {
    let p = [rectangle.topLeft,rectangle.topRight,rectangle.bottomRight,rectangle.bottomLeft].map { CGPoint(x:$0.x*CGFloat(width), y:$0.y*CGFloat(height)) }
    return (0..<4).map { i in
      let a=p[i],b=p[(i+1)%4],length=hypot(b.x-a.x,b.y-a.y)
      guard length > 1 else { return (0,0,0,0) }
      return evidence(a:a,b:b,n:CGPoint(x:-(b.y-a.y)/length,y:(b.x-a.x)/length))
    }
  }
  func exterior(_ rectangle: VNRectangleObservation) -> [[Double]] {
    let p=[rectangle.topLeft,rectangle.topRight,rectangle.bottomRight,rectangle.bottomLeft].map {CGPoint(x:$0.x*CGFloat(width),y:$0.y*CGFloat(height))}
    return (0..<4).map { i in
      let a=p[i],b=p[(i+1)%4],length=hypot(b.x-a.x,b.y-a.y)
      guard length.isFinite, length > 1 else {return [999,999]}
      let n=CGPoint(x:-(b.y-a.y)/length,y:(b.x-a.x)/length)
      var outer:[SIMD3<Double>]=[], inner:[SIMD3<Double>]=[]
      for j in 0..<19 {
        let t=CGFloat(j+1)/20, c=CGPoint(x:a.x+(b.x-a.x)*t,y:a.y+(b.y-a.y)*t)
        for d in [CGFloat(3),7,11] {
          if let o=color(CGPoint(x:c.x+n.x*d,y:c.y+n.y*d)) {outer.append(o)}
          if let v=color(CGPoint(x:c.x-n.x*d,y:c.y-n.y*d)) {inner.append(v)}
        }
      }
      func variation(_ v:[SIMD3<Double>])->Double {
        guard !v.isEmpty else{return 999}
        let m=SIMD3(v.map{$0.x}.sorted()[v.count/2],v.map{$0.y}.sorted()[v.count/2],v.map{$0.z}.sorted()[v.count/2])
        return v.map{let d=$0-m; return sqrt((d*d).sum()/3)}.sorted()[Int(Double(v.count-1)*0.85)]
      }
      return [variation(outer),variation(inner)]
    }
  }
  func isolatedOutline(_ rectangle: VNRectangleObservation) -> Bool {
    outline(rectangle).allSatisfy { $0.1 >= 2 } && exterior(rectangle).allSatisfy { $0[0] <= 6 }
  }
  func safeExterior(_ rectangle: VNRectangleObservation) -> Bool {
    let edges=outline(rectangle), strips=exterior(rectangle)
    return zip(edges,strips).allSatisfy { edge,strip in
      strip[0] <= min(24,max(8,edge.1 * 0.5))
    }
  }
  func lowContrastOutline(_ rectangle: VNRectangleObservation) -> Bool {
    let edges = outline(rectangle)
    return edges.allSatisfy {$0.1 >= 2 && $0.1 <= 12} && edges.map {$0.3}.reduce(0,+)/4 >= 0.5
  }
  func strongOutline(_ rectangle: VNRectangleObservation) -> Bool {
    let edges = outline(rectangle)
    let median = edges.map {$0.1}.sorted()[2]
    // A printed divider can close an otherwise correct outer outline. Require
    // every side to have a localized, coherent step of comparable strength.
    return edges.allSatisfy { $0.1 >= max(12, median / 3) && $0.2 >= $0.1 * 0.2 && $0.3 >= 0.65 }
  }
  func supportedOutline(_ rectangle: VNRectangleObservation) -> Bool {
    let edges = outline(rectangle)
    return edges.allSatisfy {$0.1 >= 8} && edges.filter {$0.2 >= $0.1 * 0.32}.count >= 3
  }
  func refine(_ rectangle: VNRectangleObservation) -> VNRectangleObservation? {
    let source = [rectangle.topLeft, rectangle.topRight, rectangle.bottomRight, rectangle.bottomLeft]
    let points = source.map { CGPoint(x:$0.x*CGFloat(width), y:$0.y*CGFloat(height)) }
    let center = CGPoint(x:points.map(\.x).reduce(0,+)/4,y:points.map(\.y).reduce(0,+)/4)
    var shortest: CGFloat = .greatestFiniteMagnitude
    for i in 0..<4 {
      let p = points[i], q = points[(i+1)%4]
      shortest = min(shortest, hypot(p.x-q.x,p.y-q.y))
    }
    guard shortest > 25 else { return nil }
    var originals: [Line] = []
    var normals: [CGPoint] = []
    for edge in 0..<4 {
      let a=points[edge],b=points[(edge+1)%4]
      let length=hypot(b.x-a.x,b.y-a.y)
      var n=CGPoint(x:-(b.y-a.y)/length,y:(b.x-a.x)/length)
      if (center.x-(a.x+b.x)/2)*n.x+(center.y-(a.y+b.y)/2)*n.y > 0 { n=CGPoint(x:-n.x,y:-n.y) }
      normals.append(n)
      let e=evidence(a:a,b:b,n:n)
      originals.append(Line(a:a,b:b,broad:e.1,sharp:e.2,coherence:e.3))
    }
    func supported(_ lines:[Line]) -> Bool {
      lines.allSatisfy({$0.broad >= 8}) &&
        lines.filter({$0.broad >= 12}).count >= 3 &&
        lines.map(\.broad).reduce(0,+)/4 >= 16 &&
        lines.filter({$0.sharp >= $0.broad * 0.32}).count >= 3
    }
    // Strong perimeter evidence means there is no reason to perturb accurate Vision corners.
    if supported(originals) { return rectangle }
    func fit(_ edge:Int, expanding:Bool) -> Line {
      let a=points[edge],b=points[(edge+1)%4],n=normals[edge]
      let length=hypot(b.x-a.x,b.y-a.y)
      var bestScore = -1.0, bestOffset:CGFloat = 0, bestTilt:CGFloat = 0
      var best=originals[edge]
      func test(_ offset:CGFloat,_ tilt:CGFloat) {
        let aa=CGPoint(x:a.x+n.x*(offset-tilt),y:a.y+n.y*(offset-tilt))
        let bb=CGPoint(x:b.x+n.x*(offset+tilt),y:b.y+n.y*(offset+tilt))
        let e=evidence(a:aa,b:bb,n:n)
        let score=e.0 / (1 + Double(abs(offset))*0.006 + Double(abs(tilt))*0.005)
        if score > bestScore {
          bestScore=score;bestOffset=offset;bestTilt=tilt
          best=Line(a:aa,b:bb,broad:e.1,sharp:e.2,coherence:e.3)
        }
      }
      if expanding {
        let range=min(70,shortest*0.32), tiltRange=min(18,length*0.1)
        for offset in stride(from:CGFloat(0),through:range,by:2) {
          for tilt in stride(from:-tiltRange,through:tiltRange,by:3) {test(offset,tilt)}
        }
        let o=bestOffset,t=bestTilt
        for offset in stride(from:o-2,through:o+2,by:0.5) {
          for tilt in stride(from:t-3,through:t+3,by:1) {test(offset,tilt)}
        }
      } else {
        for offset in stride(from:CGFloat(-3),through:3,by:0.5) {
          for tilt in stride(from:CGFloat(-2),through:2,by:1) {test(offset,tilt)}
        }
      }
      return best
    }
    var lines=(0..<4).map { fit($0,expanding:false) }
    if !supported(lines) {
      // An isolated missing side commonly means clipping. Expanding only that
      // side invents a border across document content; require multi-side evidence.
      let weak=lines.filter {$0.broad < 8 || $0.sharp < $0.broad * 0.48}.count
      guard weak >= 2 else { return nil }
      lines=(0..<4).map {fit($0,expanding:true)}
      guard supported(lines) else { return nil }
      let expanded=(0..<4).filter {
        let old=originals[$0],new=lines[$0],n=normals[$0]
        return ((new.a.x+new.b.x-old.a.x-old.b.x)*n.x +
          (new.a.y+new.b.y-old.a.y-old.b.y)*n.y)/2 > 6
      }.count
      guard expanded >= 2 else {return nil}
    }
    func intersection(_ l:Line,_ r:Line) -> CGPoint? {
      let dx=l.b.x-l.a.x,dy=l.b.y-l.a.y,ex=r.b.x-r.a.x,ey=r.b.y-r.a.y
      let cross=dx*ey-dy*ex
      guard abs(cross)>1 else { return nil }
      let t=((r.a.x-l.a.x)*ey-(r.a.y-l.a.y)*ex)/cross
      return CGPoint(x:(l.a.x+t*dx)/CGFloat(width),y:(l.a.y+t*dy)/CGFloat(height))
    }
    var corners:[CGPoint]=[]
    for i in 0..<4 { guard let p=intersection(lines[(i+3)%4],lines[i]) else{return nil}; corners.append(p) }
    // Preserve the seed's cyclic order; reject extreme or non-convex intersections.
    guard corners.allSatisfy({$0.x.isFinite && $0.y.isFinite && $0.x >= 0 && $0.x <= 1 && $0.y >= 0 && $0.y <= 1}) else{return nil}
    for i in 0..<4 {
      let a=corners[i],b=corners[(i+1)%4],c=corners[(i+2)%4]
      guard (b.x-a.x)*(c.y-b.y)-(b.y-a.y)*(c.x-b.x) < 0 else { return nil }
    }
    return VNRectangleObservation(requestRevision: VNDetectRectanglesRequestRevision1,
      topLeft:corners[0],bottomLeft:corners[3],bottomRight:corners[2],topRight:corners[1])
  }
}

enum ScannerDetectionPurpose {
  case live
  case still
}

enum ScannerRectangleDetector {
  static func makeRequest(for purpose: ScannerDetectionPurpose) -> VNDetectRectanglesRequest {
    let request = VNDetectRectanglesRequest()
    // Live guidance and the saved crop must consider the same candidates.
    request.maximumObservations = 4
    request.minimumConfidence = 0.55
    request.minimumAspectRatio = 0.3
    request.maximumAspectRatio = 1
    request.minimumSize = 0.18
    request.quadratureTolerance = 28
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
    let extent=image.extent
    guard !extent.isInfinite, !extent.isNull,
      extent.minX.isFinite, extent.minY.isFinite,
      extent.width.isFinite, extent.height.isFinite,
      extent.width >= 32, extent.height >= 32 else {return nil}
    let clarity = ContentClarity.score(image)
    guard clarity.support < 24 || clarity.q50 >= 0.35 else { return nil }
    let request = makeRequest(for: purpose)
    let segmentation = VNDetectDocumentSegmentationRequest()
    try VNImageRequestHandler(ciImage: image, orientation: .up).perform([request, segmentation])
    guard let document = segmentation.results?.first, document.confidence >= 0.6,
      select([document], imageSize: image.extent.size, profile: profile, purpose: .still) != nil else { return nil }
    if clarity.support < 24 {
      // Sparse pages may place all their writing outside the central guide.
      // Recheck the page interior, excluding its border and the background.
      func point(_ p:CGPoint)->CIVector { CIVector(x:p.x*image.extent.width+image.extent.minX,y:p.y*image.extent.height+image.extent.minY) }
      let corrected=image.applyingFilter("CIPerspectiveCorrection",parameters:[
        "inputTopLeft":point(document.topLeft),"inputTopRight":point(document.topRight),
        "inputBottomRight":point(document.bottomRight),"inputBottomLeft":point(document.bottomLeft)])
      var configuration=ContentClarity.Configuration()
      configuration.horizontalInset=0.08; configuration.verticalInset=0.08
      let pageClarity=ContentClarity.score(corrected,configuration:configuration)
      guard pageClarity.support >= 24, pageClarity.q50 >= 0.35 else {return nil}
    }
    let proposals = request.results ?? []
    func agreeingCorners(_ candidate: VNRectangleObservation, tolerance: CGFloat = 0.06) -> Int {
      let a = [candidate.topLeft,candidate.topRight,candidate.bottomRight,candidate.bottomLeft]
      let b = [document.topLeft,document.topRight,document.bottomRight,document.bottomLeft]
      let w = image.extent.width, h = image.extent.height
      let diagonal = hypot(document.boundingBox.width*w,document.boundingBox.height*h)
      return zip(a,b).filter { hypot(($0.x-$1.x)*w,($0.y-$1.y)*h) <= diagonal * tolerance }.count
    }
    let pixels = BoundaryPixels(image: image)
    func fused(_ rectangle: VNRectangleObservation) -> VNRectangleObservation? {
      func midpoint(_ a: CGPoint,_ b: CGPoint) -> CGPoint { CGPoint(x:(a.x+b.x)/2,y:(a.y+b.y)/2) }
      let result = VNRectangleObservation(requestRevision: VNDetectRectanglesRequestRevision1,
        topLeft:midpoint(rectangle.topLeft,document.topLeft),
        bottomLeft:midpoint(rectangle.bottomLeft,document.bottomLeft),
        bottomRight:midpoint(rectangle.bottomRight,document.bottomRight),
        topRight:midpoint(rectangle.topRight,document.topRight))
      guard let pixels, pixels.safeExterior(result) else {return nil}
      // Consensus must not move a localized paper edge out into the background.
      // Agreement between Vision models is insufficient when fusion loses the
      // perimeter evidence present on the original rectangle.
      if pixels.supportedOutline(rectangle) && !pixels.supportedOutline(result) {return nil}
      return select([result], imageSize:image.extent.size, profile:profile, purpose:.still)
    }
    guard let pixels else { return nil }
    // Independent exterior support preserves complete low-contrast pages when
    // rectangle detection favors a divider or joins nearby clutter.
    if document.confidence >= 0.98 && pixels.isolatedOutline(document) { return document }
    // Independent rectangle agreement can confirm a lower-confidence, faint
    // page perimeter when its exterior remains uniform on every side.
    if document.confidence >= 0.9 && pixels.lowContrastOutline(document) &&
      pixels.isolatedOutline(document) && proposals.contains(where: {agreeingCorners($0) == 4}) {return document}
    if let candidate = select(proposals, imageSize: image.extent.size, profile: profile, purpose: .still),
      let refined = pixels.refine(candidate),
      select([refined], imageSize: image.extent.size, profile: profile, purpose: .still) != nil {
      let agreement = agreeingCorners(refined)
      let strong = pixels.strongOutline(refined)
      // Segmentation sometimes joins nearby clutter to one or two corners.
      // Pixel evidence on every rectangle side can preserve the complete page.
      if strong && pixels.safeExterior(refined) && agreement >= 2 && (agreement < 4 || (!pixels.supportedOutline(document) && pixels.refine(document) == nil) || document.confidence < 0.9) {
        return refined
      }
      if agreement == 4 && document.confidence >= 0.9 {
        if let consensus=fused(refined) {return consensus}
        // Averaging must not move a supported paper edge into printed content.
        if (strong || (pixels.supportedOutline(refined) && pixels.isolatedOutline(refined))) &&
          pixels.safeExterior(refined) {return refined}
      }
    }
    guard document.confidence >= 0.9 else { return nil }
    if proposals.contains(where: { agreeingCorners($0) == 4 }), let refined = pixels.refine(document),
      select([refined], imageSize: image.extent.size, profile: profile, purpose: .still) != nil { return fused(refined) }
    // With no competing rectangle, validate the segmentation perimeter itself.
    if proposals.isEmpty {
      if let refined = pixels.refine(document),
        select([refined], imageSize: image.extent.size, profile: profile, purpose: .still) != nil && pixels.safeExterior(refined) { return refined }
      if pixels.lowContrastOutline(document) && pixels.safeExterior(document) { return document }
    }
    return nil
  }
}
