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
  func uniformOuterBand(_ rectangle: VNRectangleObservation) -> Bool {
    let points = [rectangle.topLeft, rectangle.topRight, rectangle.bottomRight, rectangle.bottomLeft]
      .map { CGPoint(x: $0.x * CGFloat(width), y: $0.y * CGFloat(height)) }
    return (0..<4).allSatisfy { edge in
      let a = points[edge], b = points[(edge + 1) % 4]
      let length = hypot(b.x - a.x, b.y - a.y)
      guard length > 1 else { return false }
      let normal = CGPoint(x: -(b.y - a.y) / length, y: (b.x - a.x) / length)
      var values: [SIMD3<Double>] = []
      for sample in 0..<19 {
        let t = CGFloat(sample + 1) / 20
        let point = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        for distance in [CGFloat(13), 17, 21] {
          guard let value = color(CGPoint(x: point.x + normal.x * distance,
                                          y: point.y + normal.y * distance)) else { return false }
          values.append(value)
        }
      }
      let median = SIMD3(values.map(\.x).sorted()[values.count / 2],
                         values.map(\.y).sorted()[values.count / 2],
                         values.map(\.z).sorted()[values.count / 2])
      let variation = values.map { value in
        let delta = value - median
        return sqrt((delta * delta).sum() / 3)
      }.sorted()[Int(Double(values.count - 1) * 0.85)]
      return variation <= 6
    }
  }
  // Localize the paper edge when segmentation ends at a faint or decorated margin.
  // A uniform far band only opens this bounded search. Each replacement must have
  // continuous narrow contrast and flat pixels immediately outside its own line.
  // Broad contrast can cross a contrasting printed margin, so it is not used as
  // the denominator of the narrow physical-edge contrast test.
  func localizedCompletion(_ rectangle: VNRectangleObservation) -> VNRectangleObservation? {
    struct Match {
      let line: Line
      let offset: CGFloat
      let tilt: CGFloat
      let score: Double
    }
    let source = [rectangle.topLeft, rectangle.topRight, rectangle.bottomRight, rectangle.bottomLeft]
    let points = source.map { CGPoint(x: $0.x * CGFloat(width), y: $0.y * CGFloat(height)) }
    let center = CGPoint(x: points.map(\.x).reduce(0,+)/4, y: points.map(\.y).reduce(0,+)/4)
    func localizedStep(a: CGPoint, b: CGPoint, n: CGPoint) -> Bool {
      var steps: [Double] = [], exteriorChanges: [Double] = []
      var vector = SIMD3<Double>(repeating: 0), magnitude = 0.0
      for sample in 0..<19 {
        let t = CGFloat(sample + 1) / 20
        let p = CGPoint(x:a.x+(b.x-a.x)*t, y:a.y+(b.y-a.y)*t)
        func sampleColor(_ d:CGFloat) -> SIMD3<Double>? {
          color(CGPoint(x:p.x+n.x*d,y:p.y+n.y*d))
        }
        guard let inside=sampleColor(-1.5), let outside=sampleColor(1.5),
              let far=sampleColor(5) else { return false }
        let delta=inside-outside, outerDelta=outside-far
        let norm=sqrt((delta*delta).sum()/3)
        steps.append(norm); exteriorChanges.append(sqrt((outerDelta*outerDelta).sum()/3))
        vector += delta; magnitude += norm
      }
      return steps.sorted()[2] >= 2 && exteriorChanges.sorted()[16] <= 3 &&
        sqrt((vector*vector).sum()/3) / max(1,magnitude) >= 0.9
    }
    var lines: [Line] = []
    var moved = 0
    for edge in 0..<4 {
      let a = points[edge], b = points[(edge + 1) % 4]
      let length = hypot(b.x - a.x, b.y - a.y)
      guard length > 30 else { return nil }
      var normal = CGPoint(x: -(b.y - a.y) / length, y: (b.x - a.x) / length)
      if (center.x - (a.x + b.x)/2) * normal.x + (center.y - (a.y + b.y)/2) * normal.y > 0 {
        normal = CGPoint(x: -normal.x, y: -normal.y)
      }
      let originalEvidence = evidence(a: a, b: b, n: normal)
      let original = Line(a:a,b:b,broad:originalEvidence.1,sharp:originalEvidence.2,coherence:originalEvidence.3)
      let originalExterior = outerVariation(a:a,b:b,n:normal)
      // Faint sheet boundaries can have small, varying RGB directions after
      // downsampling. Preserve an observed side only with both broad and narrow
      // contrast, coherent broad evidence, and a strictly flat exterior.
      let supportedFaintOriginal = originalEvidence.1 >= 2 && originalEvidence.1 <= 12 &&
        originalEvidence.2 >= 2 &&
        (originalEvidence.3 >= 0.8 ||
         (originalEvidence.3 >= 0.65 && originalEvidence.2 >= originalEvidence.1 * 0.65)) &&
        originalExterior <= 3
      if supportedFaintOriginal ||
        (originalExterior <= min(24,max(8,originalEvidence.1*0.5)) &&
         localizedStep(a:a,b:b,n:normal)) {
        lines.append(original)
        continue
      }
      var matches: [Match] = []
      for offset in stride(from: CGFloat(-3), through: 12, by: 1) {
        for tilt in stride(from: CGFloat(-4), through: 4, by: 2) {
          guard offset - abs(tilt) >= -3, offset + abs(tilt) <= 12 else { continue }
          let aa = CGPoint(x:a.x + normal.x * (offset-tilt), y:a.y + normal.y * (offset-tilt))
          let bb = CGPoint(x:b.x + normal.x * (offset+tilt), y:b.y + normal.y * (offset+tilt))
          let candidate = evidence(a:aa,b:bb,n:normal)
          guard candidate.1 >= 2,
                candidate.2 >= 2,
                candidate.3 >= 0.65,
                outerVariation(a:aa,b:bb,n:normal) <= min(24,max(8,candidate.1*0.5)),
                localizedStep(a:aa,b:bb,n:normal) else { continue }
          let raw = min(candidate.1, candidate.2 * 1.8) * candidate.3
          let score = raw / (1 + Double(abs(offset)) * 0.01 + Double(abs(tilt)) * 0.01)
          matches.append(Match(line:Line(a:aa,b:bb,broad:candidate.1,sharp:candidate.2,coherence:candidate.3),
                               offset:offset,tilt:tilt,score:score))
        }
      }
      // An unchanged side already passed explicit physical-edge evidence above.
      // Never retain an unsupported original side when completion fails.
      guard let best = matches.max(by: {$0.score < $1.score}), best.score >= 2.5 else { return nil }
      // Nearby samples describe the same physical edge. A similarly strong
      // distant line makes the completion ambiguous, so retain no boundary.
      if matches.contains(where: {
        (abs($0.offset-best.offset) > 4 || abs($0.tilt-best.tilt) > 6) && $0.score >= best.score * 0.87
      }) { return nil }
      lines.append(best.line)
      moved += 1
    }
    guard moved >= 1 else { return nil }
    func intersection(_ left:Line,_ right:Line) -> CGPoint? {
      let dx=left.b.x-left.a.x,dy=left.b.y-left.a.y,ex=right.b.x-right.a.x,ey=right.b.y-right.a.y
      let cross=dx*ey-dy*ex
      guard abs(cross)>1 else {return nil}
      let t=((right.a.x-left.a.x)*ey-(right.a.y-left.a.y)*ex)/cross
      return CGPoint(x:(left.a.x+t*dx)/CGFloat(width),y:(left.a.y+t*dy)/CGFloat(height))
    }
    var corners:[CGPoint]=[]
    for edge in 0..<4 {
      guard let corner=intersection(lines[(edge+3)%4],lines[edge]) else {return nil}
      corners.append(corner)
    }
    guard corners.allSatisfy({$0.x.isFinite && $0.y.isFinite && $0.x >= 0 && $0.x <= 1 && $0.y >= 0 && $0.y <= 1}) else{return nil}
    for edge in 0..<4 {
      let a=corners[edge],b=corners[(edge+1)%4],c=corners[(edge+2)%4]
      guard (b.x-a.x)*(c.y-b.y)-(b.y-a.y)*(c.x-b.x) < 0 else{return nil}
    }
    return VNRectangleObservation(requestRevision:VNDetectRectanglesRequestRevision1,
      topLeft:corners[0],bottomLeft:corners[3],bottomRight:corners[2],topRight:corners[1])
  }

  // A physical dark rim separates two surfaces beyond the rim itself. A
  // printed line on one sheet loses its contrast in these farther bands.
  func sustainedSurfaceStep(_ rectangle: VNRectangleObservation) -> Bool {
    let points=[rectangle.topLeft,rectangle.topRight,rectangle.bottomRight,rectangle.bottomLeft]
      .map { CGPoint(x:$0.x*CGFloat(width), y:$0.y*CGFloat(height)) }
    return (0..<4).allSatisfy { edge in
      let a=points[edge],b=points[(edge+1)%4],length=hypot(b.x-a.x,b.y-a.y)
      guard length > 30 else { return false }
      let n=CGPoint(x:-(b.y-a.y)/length,y:(b.x-a.x)/length)
      var contrasts:[Double]=[]
      var vector=SIMD3<Double>(repeating:0), magnitude=0.0
      for i in 0..<17 {
        let t=CGFloat(i+3)/22,p=CGPoint(x:a.x+(b.x-a.x)*t,y:a.y+(b.y-a.y)*t)
        for distance in [CGFloat(12),18] {
          guard let inside=color(CGPoint(x:p.x-n.x*distance,y:p.y-n.y*distance)),
            let outside=color(CGPoint(x:p.x+n.x*distance,y:p.y+n.y*distance)) else {return false}
          let delta=inside-outside,norm=sqrt((delta*delta).sum()/3)
          contrasts.append(norm); vector += delta; magnitude += norm
        }
      }
      return contrasts.sorted()[contrasts.count/3] >= 12 &&
        sqrt((vector*vector).sum()/3)/max(1,magnitude) >= 0.9
    }
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
  func outerVariation(a: CGPoint, b: CGPoint, n: CGPoint) -> Double {
    var values:[SIMD3<Double>]=[]
    for j in 0..<19 {
      let t=CGFloat(j+1)/20,c=CGPoint(x:a.x+(b.x-a.x)*t,y:a.y+(b.y-a.y)*t)
      for d in [CGFloat(3),7,11] {
        guard let v=color(CGPoint(x:c.x+n.x*d,y:c.y+n.y*d)) else{return 999}
        values.append(v)
      }
    }
    let m=SIMD3(values.map{$0.x}.sorted()[values.count/2],values.map{$0.y}.sorted()[values.count/2],values.map{$0.z}.sorted()[values.count/2])
    return values.map{let d=$0-m;return sqrt((d*d).sum()/3)}.sorted()[Int(Double(values.count-1)*0.85)]
  }
  // A booklet binding is a narrow dark valley, unlike an outer paper/background
  // step. Require both flanks and continuity along almost the full edge.
  func crease(a: CGPoint, b: CGPoint, n: CGPoint) -> Double {
    var values: [Double] = []
    for i in 0..<31 {
      let t=CGFloat(i+1)/32, p=CGPoint(x:a.x+(b.x-a.x)*t,y:a.y+(b.y-a.y)*t)
      func luma(_ d:CGFloat)->Double? {
        guard let c=color(CGPoint(x:p.x+n.x*d,y:p.y+n.y*d)) else{return nil}
        return (c.x+c.y+c.z)/3
      }
      guard let c=luma(0),let a=luma(-3),let b=luma(3),let aa=luma(-5),let bb=luma(5) else{return 0}
      values.append(min(a-c,b-c,aa-c,bb-c))
    }
    return values.sorted()[6]
  }
  func refine(_ rectangle: VNRectangleObservation, diffuseEdge: Int? = nil, bindingEdge: Int? = nil) -> VNRectangleObservation? {
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
      if let binding = bindingEdge {
        return lines.enumerated().allSatisfy { i,line in
          if i == binding {return crease(a:line.a,b:line.b,n:normals[i]) >= 8}
          return line.broad >= 12 && line.sharp >= line.broad * 0.32 && line.coherence >= 0.9
        }
      }
      if let weak = diffuseEdge {
        return lines.enumerated().allSatisfy { i, line in
          if i == weak { return line.broad >= 2 && line.sharp >= 1 && line.coherence >= 0.35 }
          return line.broad >= 8 && line.sharp >= line.broad * 0.32 && line.coherence >= 0.9
        }
      }
      return lines.allSatisfy({$0.broad >= 8}) &&
        lines.filter({$0.broad >= 12}).count >= 3 &&
        lines.map(\.broad).reduce(0,+)/4 >= 16 &&
        lines.filter({$0.sharp >= $0.broad * 0.32}).count >= 3
    }
    // Strong perimeter evidence means there is no reason to perturb accurate Vision corners.
    if bindingEdge == nil && supported(originals) &&
      (diffuseEdge == nil || safeExterior(rectangle)) { return rectangle }
    func fit(_ edge:Int, expanding:Bool) -> Line {
      let a=points[edge],b=points[(edge+1)%4],n=normals[edge]
      let length=hypot(b.x-a.x,b.y-a.y)
      var bestScore = -1.0, bestOffset:CGFloat = 0, bestTilt:CGFloat = 0
      var best=originals[edge]
      func test(_ offset:CGFloat,_ tilt:CGFloat) {
        let aa=CGPoint(x:a.x+n.x*(offset-tilt),y:a.y+n.y*(offset-tilt))
        let bb=CGPoint(x:b.x+n.x*(offset+tilt),y:b.y+n.y*(offset+tilt))
        let e=evidence(a:aa,b:bb,n:n)
        if ((bindingEdge != nil && bindingEdge != edge) || diffuseEdge != nil) &&
          outerVariation(a:aa,b:bb,n:n) > min(24,max(8,e.1*0.5)) {return}
        let rawScore = bindingEdge == edge ? crease(a:aa,b:bb,n:n) : e.0
        let score=rawScore / (1 + Double(abs(offset))*0.006 + Double(abs(tilt))*0.005)
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
      guard diffuseEdge == nil && bindingEdge == nil else { return nil }
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

  struct CurvedEvidence {
    let steps: [Double]
    let valleys: [Double]
    let lengths: [Double]
  }
  func curvedEvidence(_ r: VNRectangleObservation) -> CurvedEvidence {
    let points=[r.topLeft,r.topRight,r.bottomRight,r.bottomLeft].map {CGPoint(x:$0.x*CGFloat(width),y:$0.y*CGFloat(height))}
    var steps:[Double]=[],valleys:[Double]=[],lengths:[Double]=[]
    for edge in 0..<4 {
      let a=points[edge],b=points[(edge+1)%4],length=hypot(b.x-a.x,b.y-a.y)
      lengths.append(Double(length))
      guard length > 1 else {steps.append(0);valleys.append(0);continue}
      let n=CGPoint(x:-(b.y-a.y)/length,y:(b.x-a.x)/length)
      var stepCount=0,valleyCount=0
      for sample in 0..<31 {
        let t=CGFloat(sample+2)/34,p=CGPoint(x:a.x+(b.x-a.x)*t,y:a.y+(b.y-a.y)*t)
        var step=false,valley=false
        for offset in stride(from:CGFloat(-4),through:4,by:0.5) {
          func c(_ d:CGFloat)->SIMD3<Double>? {color(CGPoint(x:p.x+n.x*(d+offset),y:p.y+n.y*(d+offset)))}
          guard let inner=c(-5),let outer=c(5),let ni=c(-1.5),let no=c(1.5),let center=c(0),let flankA=c(-3),let flankB=c(3) else {continue}
          let broad=inner-outer,near=ni-no
          let broadNorm=sqrt((broad*broad).sum()/3),nearNorm=sqrt((near*near).sum()/3)
          if broadNorm >= 12 && nearNorm >= max(8,broadNorm*0.25) && (broad*near).sum() > 0 {step=true}
          func luma(_ x:SIMD3<Double>)->Double {(x.x+x.y+x.z)/3}
          if min(luma(inner),luma(outer),luma(flankA),luma(flankB))-luma(center) >= 8 {valley=true}
        }
        if step {stepCount += 1};if valley {valleyCount += 1}
      }
      steps.append(Double(stepCount)/31);valleys.append(Double(valleyCount)/31)
    }
    return CurvedEvidence(steps:steps,valleys:valleys,lengths:lengths)
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

  // Map a CCW quarter-turn detection back to the original Vision coordinates.
  // The cyclic shift preserves semantic corner names for non-square images.
  static func mapFromQuarterTurn(_ rectangle: VNRectangleObservation, turns: Int) -> VNRectangleObservation {
    let count=((turns % 4)+4)%4
    let points=[rectangle.topLeft,rectangle.topRight,rectangle.bottomRight,rectangle.bottomLeft].map { point in
      var p=point
      for _ in 0..<count {p=CGPoint(x:p.y,y:1-p.x)}
      return p
    }
    let start=(4-count)%4
    return VNRectangleObservation(requestRevision:VNDetectRectanglesRequestRevision1,
      topLeft:points[start],bottomLeft:points[(start+3)%4],bottomRight:points[(start+2)%4],topRight:points[(start+1)%4])
  }
  static func detect(
    in image: CIImage,
    profile: FoorsaScannerProfile,
    purpose: ScannerDetectionPurpose
  ) throws -> VNRectangleObservation? {
    let e=image.extent
    guard !e.isInfinite,!e.isNull,e.minX.isFinite,e.minY.isFinite,
      e.width.isFinite,e.height.isFinite,e.width >= 32,e.height >= 32 else {return nil}
    let clarity=ContentClarity.score(image)
    // Do not run any Vision orientation after an independent severe-blur failure.
    guard clarity.support < 24 || clarity.q50 >= 0.35 else {return nil}
    var remainingContentRequests=4
    func acceptedBoundary(_ candidate: VNRectangleObservation?) -> VNRectangleObservation? {
      guard let candidate else {return nil}
      if profile.layout == .passport, let pixels=BoundaryPixels(image:image) {
        if pixels.enclosingClippedSheet(around:candidate).veto {return nil}
        if pixels.hasPrintedFrame(candidate) && !hasPassportContent(in:image,rectangle:candidate,remainingRequests:&remainingContentRequests) {return nil}
      }
      return candidate
    }
    var recovery: VNRectangleObservation?
    var raw: VNRectangleObservation?
    var rawContentClear=false
    var contentCleared:[VNRectangleObservation]=[]
    var accepted: [VNRectangleObservation] = []
    var documents: [(VNRectangleObservation, Float)] = []
    var rotated=image.transformed(by:CGAffineTransform(translationX:-e.minX,y:-e.minY))
    for turns in 0..<(profile.layout == .passport ? 4 : 1) {
      if turns > 0 {rotated=rotated.transformed(by:CGAffineTransform(a:0,b:1,c:-1,d:0,tx:rotated.extent.height,ty:0))}
      recovery=nil; raw=nil; rawContentClear=false
      let primary=try detectSingleOrientation(in:rotated,profile:profile,purpose:purpose,measuredClarity:turns == 0 ? clarity : nil,recovery:&recovery,rawDocument:&raw,rawContentClear:&rawContentClear)
      if let raw {
        let mapped=mapFromQuarterTurn(raw,turns:turns)
        documents.append((mapped,raw.confidence))
        if rawContentClear {contentCleared.append(mapped)}
      }
      for candidate in [primary,recovery].compactMap({$0}) {
        let mapped=mapFromQuarterTurn(candidate,turns:turns)
        if select([mapped],imageSize:e.size,profile:profile,purpose:.still) != nil {accepted.append(mapped)}
      }
    }
    if profile.layout != .passport {
      guard let candidate = accepted.first else { return nil }
      // A strong printed panel can satisfy an early contrast/consensus path.
      // Apply the enclosing physical-sheet veto after every page selection,
      // including those that never needed margin completion.
      if let pixels = BoundaryPixels(image:image),
        pixels.enclosingClippedSheet(around:candidate).veto { return nil }
      return candidate
    }
    guard let pixels=BoundaryPixels(image:image) else {return accepted.first}
    func points(_ r:VNRectangleObservation)->[CGPoint] {[r.topLeft,r.topRight,r.bottomRight,r.bottomLeft]}
    func area(_ r:VNRectangleObservation)->CGFloat {
      let p=points(r)
      return abs((0..<4).map {p[$0].x*p[($0+1)%4].y-p[($0+1)%4].x*p[$0].y}.reduce(0,+))/2
    }
    func agrees(_ a:VNRectangleObservation,_ b:VNRectangleObservation)->Bool {
      let diagonal=hypot(b.boundingBox.width*e.width,b.boundingBox.height*e.height)
      return zip(points(a),points(b)).filter {hypot(($0.x-$1.x)*e.width,($0.y-$1.y)*e.height)<=diagonal*0.03}.count>=3
    }
    let evidence=documents.map {pixels.curvedEvidence($0.0)}
    func outerSupported(_ ev:BoundaryPixels.CurvedEvidence, rectangle: VNRectangleObservation, allowTexturedStep: Bool = false)->Bool {
      let edges=allowTexturedStep ? pixels.outline(rectangle) : []
      let longest=ev.lengths.max() ?? 0
      return (0..<4).contains {binding in
        let outside=(0..<4).filter {$0 != binding}
        return ev.lengths[binding]>=longest*0.9 && ev.valleys[binding]>=0.5 && outside.allSatisfy {ev.steps[$0]>=0.8} &&
          outside.map {ev.steps[$0]}.reduce(0,+)>=2.8 &&
          outside.allSatisfy { edge in
            if edge == (binding+2)%4 || ev.valleys[edge]<0.5 {return true}
            // Dark texture beside a genuine physical edge can also form local
            // valleys. A continuous, directionally coherent color step across
            // the edge distinguishes that boundary from a narrow printed line.
            return allowTexturedStep && ev.steps[edge]>=0.95 && edges[edge].1>=12 &&
              edges[edge].2>=8 && edges[edge].3>=0.9
          }
      }
    }
    func confirmedDocuments(allowTexturedStep: Bool)->[VNRectangleObservation] {
      var result:[VNRectangleObservation]=[]
      for i in documents.indices where documents[i].1>=0.85 && outerSupported(evidence[i],rectangle:documents[i].0,allowTexturedStep:allowTexturedStep) {
        let sibling=documents.indices.contains {j in
          j != i && documents[j].1>=0.95 && agrees(documents[i].0,documents[j].0) &&
            outerSupported(evidence[j],rectangle:documents[j].0,allowTexturedStep:allowTexturedStep) && (evidence[j].valleys.max() ?? 0)>=0.9
        }
        if sibling {result.append(documents[i].0)}
      }
      return result
    }
    let confirmed=confirmedDocuments(allowTexturedStep:false)
    let textureConfirmed=confirmedDocuments(allowTexturedStep:true)
    // Extra texture evidence can recover an observed complete outer boundary.
    // Its incomplete hypotheses veto those additional candidates, not a page
    // already validated by the stricter original boundary evidence.
    let textureCandidates=textureConfirmed.filter {candidate in
      !confirmed.contains {$0 === candidate} && contentCleared.contains {$0 === candidate} &&
        select([candidate],imageSize:e.size,profile:profile,purpose:.still) != nil
    }
    // Preserve observed corners. Three-corner agreement associates competing
    // proposals with the same page without synthesizing a missing corner.
    var candidates=accepted+confirmed.filter { candidate in
      contentCleared.contains { $0 === candidate } && select([candidate],imageSize:e.size,profile:profile,purpose:.still) != nil
    }
    candidates += textureCandidates
    candidates.sort {area($0)>area($1)}
    for candidate in candidates {
      // An independently observed matching page touching the frame makes the
      // complete inner hypothesis unsafe. A corner may move outside one edge
      // while shrinking net area, so polygon area cannot establish safety.
      let clippingEvidence=textureCandidates.contains {$0 === candidate} ? textureConfirmed : confirmed
      let clipped=clippingEvidence.contains {other in
        agrees(candidate,other) &&
          select([other],imageSize:e.size,profile:profile,purpose:.still)==nil
      }
      if clipped {continue}
      if let result=acceptedBoundary(candidate) {return result}
    }
    return nil
  }


  // Only ambiguous closed dark frames need this bounded local content check.
  // It is not field extraction or authenticity verification; no text is retained.
  private static func hasPassportContent(in image: CIImage,rectangle: VNRectangleObservation,remainingRequests: inout Int) -> Bool {
    let e=image.extent
    func point(_ p:CGPoint)->CIVector {CIVector(x:e.minX+p.x*e.width,y:e.minY+p.y*e.height)}
    var page=image.applyingFilter("CIPerspectiveCorrection",parameters:[
      "inputTopLeft":point(rectangle.topLeft),"inputTopRight":point(rectangle.topRight),
      "inputBottomRight":point(rectangle.bottomRight),"inputBottomLeft":point(rectangle.bottomLeft)])
    page=page.transformed(by:CGAffineTransform(translationX:-page.extent.minX,y:-page.extent.minY))
    let scale=min(1,960/max(page.extent.width,page.extent.height))
    page=page.transformed(by:CGAffineTransform(scaleX:scale,y:scale),highQualityDownsample:true)
    if page.extent.height>page.extent.width {
      page=page.transformed(by:CGAffineTransform(a:0,b:1,c:-1,d:0,tx:page.extent.height,ty:0))
    }
    for orientation in [CGImagePropertyOrientation.up,.down] {
      guard remainingRequests>0 else {return false}
      remainingRequests -= 1
      let request=VNRecognizeTextRequest()
      request.recognitionLevel = .fast
      request.usesLanguageCorrection=false
      request.recognitionLanguages=["en-US"]
      request.minimumTextHeight=0.008
      guard (try? VNImageRequestHandler(ciImage:page,orientation:orientation).perform([request])) != nil else {continue}
      let lines=(request.results ?? []).compactMap { observation -> ([UInt8],CGRect)? in
        guard let text=observation.topCandidates(1).first?.string else {return nil}
        let bytes=Array(text.uppercased().utf8.filter {($0>=65 && $0<=90)||($0>=48 && $0<=57)||$0==60})
        return (bytes,observation.boundingBox)
      }
      for (first,firstBox) in lines where (44...45).contains(first.count) && first[0]==80 && first[1]==60 && first.contains(60) {
        guard firstBox.minY>0.02,firstBox.maxY<0.4,firstBox.width>0.72,firstBox.minX>=0.01,firstBox.maxX<=0.99 else {continue}
        for (recognized,secondBox) in lines where (44...45).contains(recognized.count) && secondBox.midY<firstBox.midY {
          guard secondBox.minY>0.01,secondBox.width>0.72,secondBox.maxX<=0.99,secondBox.minX>=0.01,
            abs(firstBox.minX-secondBox.minX)<0.08,abs(firstBox.maxX-secondBox.maxX)<0.08,
            firstBox.minY-secondBox.maxY < max(firstBox.height,secondBox.height)*3 else {continue}
          // Fast recognition can duplicate one glyph. Permit only deletion of
          // one extra glyph, and require the resulting row's independent checks.
          let variants: [[UInt8]]=recognized.count==44 ? [recognized] : recognized.indices.map { drop in recognized.enumerated().filter {$0.offset != drop}.map(\.element) }
          for second in variants {
          func check(_ range:Range<Int>,_ digit:Int)->Bool {
            guard second[digit]>=48 && second[digit]<=57 else {return false}
            var sum=0
            for (index,offset) in range.enumerated() {
              let char=second[offset]
              let value=char==60 ? 0 : char>=65 ? Int(char-65)+10 : Int(char-48)
              sum += value*[7,3,1][index%3]
            }
            return sum%10==Int(second[digit]-48)
          }
          if [check(0..<9,9),check(13..<19,19),check(21..<27,27)].filter({$0}).count >= (recognized.count==44 ? 2 : 3) {return true}
          }
        }
      }
    }
    return false
  }

  private static func detectSingleOrientation(
    in image: CIImage,
    profile: FoorsaScannerProfile,
    purpose: ScannerDetectionPurpose,
    measuredClarity: ClarityScores? = nil,
    recovery: inout VNRectangleObservation?,
    rawDocument: inout VNRectangleObservation?,
    rawContentClear: inout Bool
  ) throws -> VNRectangleObservation? {
    let extent=image.extent
    guard !extent.isInfinite, !extent.isNull,
      extent.minX.isFinite, extent.minY.isFinite,
      extent.width.isFinite, extent.height.isFinite,
      extent.width >= 32, extent.height >= 32 else {return nil}
    let clarity = measuredClarity ?? ContentClarity.score(image)
    guard clarity.support < 24 || clarity.q50 >= 0.35 else { return nil }
    let request = makeRequest(for: purpose)
    let segmentation = VNDetectDocumentSegmentationRequest()
    try VNImageRequestHandler(ciImage: image, orientation: .up).perform([request, segmentation])
    rawDocument=segmentation.results?.first
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
    rawContentClear=true
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
    // Agreement proposes the details page; a locally tracked binding and three
    // continuous physical edges confirm it without requiring a plain backdrop.
    if profile.layout == .passport && document.confidence >= 0.95 {
      let independentRectangle=proposals.contains(where:{agreeingCorners($0,tolerance:0.03)>=3})
      let noCompleteRectangle=proposals.allSatisfy {select([$0],imageSize:image.extent.size,profile:profile,purpose:.still)==nil}
      let evidence=pixels.curvedEvidence(document)
      let longest=evidence.lengths.max() ?? 0
      for binding in 0..<4 where evidence.lengths[binding] >= longest*0.9 {
        let bindingAgrees=proposals.contains { proposal in
          let a=[proposal.topLeft,proposal.topRight,proposal.bottomRight,proposal.bottomLeft]
          let b=[document.topLeft,document.topRight,document.bottomRight,document.bottomLeft]
          let diagonal=hypot(document.boundingBox.width*image.extent.width,document.boundingBox.height*image.extent.height)
          let agrees=(0..<4).map {i in hypot((a[i].x-b[i].x)*image.extent.width,(a[i].y-b[i].y)*image.extent.height) <= diagonal*0.03}
          return agrees.filter {$0}.count >= 3 && agrees[binding] && agrees[(binding+1)%4]
        }
        let consensus=document.confidence>=0.98 && independentRectangle && bindingAgrees
        // The rectangle model can return only the portrait inside a curved page.
        // With no complete competing rectangle, require near-continuous evidence
        // on the binding and every outside edge before using segmentation alone.
        let strongContour=noCompleteRectangle && evidence.valleys[binding]>=0.95 &&
          (0..<4).filter({$0 != binding}).allSatisfy({evidence.steps[$0]>=0.95})
        if (consensus || strongContour) && evidence.valleys[binding] >= 0.8 &&
          (0..<4).filter({$0 != binding}).allSatisfy({evidence.steps[$0] >= 0.8 && evidence.valleys[$0] < 0.5}) {
          recovery=document
          break
        }
      }
    }
    // Independent exterior support preserves complete low-contrast pages when
    // rectangle detection favors a divider or joins nearby clutter.
    if document.confidence >= 0.98 && pixels.isolatedOutline(document) {
      // A plain exterior can surround a corner borrowed from nearby clutter.
      // Multiple strong but unlocalized sides must defer to rectangle consensus;
      // genuinely faint sides retain the existing low-contrast behavior.
      let localizedSides = pixels.outline(document).filter { $0.1 < 12 || $0.2 >= $0.1 * 0.2 }.count
      if profile.layout == .passport || profile.layout == .card || localizedSides >= 3 { return document }
    }
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
    // When both models agree on the complete outer perimeter, allow one faint
    // boundary only if its exterior is uniform and the other three sides have
    // coherent localized edges. Local refinement cannot search outward for a
    // replacement edge; this path never substitutes an inner rectangle.
    if document.confidence >= 0.98,
      let outer = select(proposals, imageSize: image.extent.size, profile: profile, purpose: .still),
      agreeingCorners(outer) == 4 {
      let edges = pixels.outline(outer), strips = pixels.exterior(outer)
      let faint = edges.indices.filter { edges[$0].1 < 8 }
      if faint.count == 1, let weak = faint.first,
        edges[weak].1 >= 2, edges[weak].2 >= edges[weak].1 * 0.2,
        strips[weak][0] <= 6,
        let refined = pixels.refine(outer, diffuseEdge: weak),
        pixels.safeExterior(refined),
        agreeingCorners(refined) == 4,
        select([refined], imageSize: image.extent.size, profile: profile, purpose: .still) != nil {
        return refined
      }
    }
    // Single data pages in a booklet may border the facing page at their binding.
    // Only a narrow, continuous crease may replace one long physical outer side;
    // all three remaining sides must localize with coherent background contrast.
    if profile.layout == .passport && document.confidence >= 0.9 {
      let points=[document.topLeft,document.topRight,document.bottomRight,document.bottomLeft]
      let lengths=(0..<4).map { i in hypot((points[i].x-points[(i+1)%4].x)*image.extent.width,(points[i].y-points[(i+1)%4].y)*image.extent.height) }
      let shape=max(lengths[0]+lengths[2],lengths[1]+lengths[3])/min(lengths[0]+lengths[2],lengths[1]+lengths[3])
      if shape >= 1.3 && shape <= 1.6 {
        for edge in 0..<4 where lengths[edge] >= (lengths.max() ?? 0)*0.9 {
          guard let refined=pixels.refine(document,bindingEdge:edge),
            select([refined],imageSize:image.extent.size,profile:profile,purpose:.still) != nil else {continue}
          let edges=pixels.outline(refined),strips=pixels.exterior(refined)
          guard (0..<4).filter({$0 != edge}).allSatisfy({ i in
            edges[i].1 >= 12 && edges[i].2 >= edges[i].1*0.32 && edges[i].3 >= 0.9 &&
            strips[i][0] <= min(24,max(8,edges[i].1*0.5))
          }) else {continue}
          return refined
        }
      }
    }
    guard document.confidence >= 0.9 else { return nil }
    if proposals.contains(where: { agreeingCorners($0) == 4 }), let refined = pixels.refine(document),
      select([refined], imageSize: image.extent.size, profile: profile, purpose: .still) != nil {
      if let result = fused(refined) { return result }
    }
    // A high-confidence proposal can end on a decorative inset instead of the
    // paper edge. Complete it only from localized physical edge evidence.
    if profile.layout != .passport && profile.layout != .card && document.confidence >= 0.98 &&
      (proposals.contains(where: { agreeingCorners($0) == 4 }) ||
       (proposals.isEmpty && pixels.lowContrastOutline(document))) &&
      pixels.uniformOuterBand(document) && !pixels.hasPrintedFrame(document, requireMatchingSurfaces: true) &&
      !pixels.enclosingClippedSheet(around:document).veto,
      let completed = pixels.localizedCompletion(document),
      pixels.safeExterior(completed), !pixels.hasPrintedFrame(completed, requireMatchingSurfaces: true),
      !pixels.enclosingClippedSheet(around:completed).veto,
      select([completed], imageSize:image.extent.size, profile:profile, purpose:.still) != nil {
      return completed
    }
    // With no competing rectangle, validate the segmentation perimeter itself.
    if proposals.isEmpty {
      if let refined = pixels.refine(document),
        select([refined], imageSize: image.extent.size, profile: profile, purpose: .still) != nil && pixels.safeExterior(refined) { return refined }
      if pixels.lowContrastOutline(document) && pixels.safeExterior(document) { return document }
    }
    // Card segmentation may preserve the physical perimeter when rectangle
    // detection attaches one corner to printed content. Keep the observed
    // card only with strong local edges on all four sides and strict agreement
    // on the other three corners; never synthesize the missing corner.
    if profile.layout == .card && document.confidence >= 0.98 &&
      pixels.strongOutline(document) && pixels.safeExterior(document) &&
      (!pixels.hasPrintedFrame(document) || pixels.sustainedSurfaceStep(document)) &&
      !pixels.enclosingClippedSheet(around:document).veto &&
      proposals.contains(where: { agreeingCorners($0, tolerance: 0.03) >= 3 }) { return document }

    return nil
  }
}

private struct EnclosingSheetEvidence: Codable {
  struct Side: Codable {
    let edge: Int
    let offset: Double
    let broad: Double
    let sharp: Double
    let coherence: Double
    let beforeContinuation: Double
    let afterContinuation: Double
    let bandVariation: Double
    let bandSimilarity: Double
  }

  let veto: Bool
  let reason: String
  let pair: [Int]
  let sides: [Side]
}

extension BoundaryPixels {
  // Detect a printed inner panel only when two opposite, parallel outer edges
  // enclose it. Each outer edge must continue beyond both panel corners and the
  // intervening strip must look like one connected, nearly uniform paper band.
  // This intentionally avoids document color, OCR, and absolute coordinates.
  func enclosingClippedSheet(around rectangle: VNRectangleObservation) -> EnclosingSheetEvidence {
    let points = [rectangle.topLeft, rectangle.topRight, rectangle.bottomRight, rectangle.bottomLeft]
      .map { CGPoint(x: $0.x * CGFloat(width), y: $0.y * CGFloat(height)) }

    func distance(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
      let d = a - b
      return sqrt((d * d).sum() / 3)
    }
    func percentile(_ values: [Double], _ p: Double, fallback: Double = 999) -> Double {
      guard !values.isEmpty else { return fallback }
      let sorted = values.sorted()
      return sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * p))]
    }
    func lineSupport(a: CGPoint, b: CGPoint, n: CGPoint) -> Double {
      var values: [Double] = []
      for i in 0..<9 {
        let t = CGFloat(i + 1) / 10
        let p = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        guard let left = color(CGPoint(x: p.x - n.x * 3, y: p.y - n.y * 3)),
              let right = color(CGPoint(x: p.x + n.x * 3, y: p.y + n.y * 3)) else { continue }
        values.append(distance(left, right))
      }
      // A continuation is a line, so most samples—not one crossing—must agree.
      return percentile(values, 0.25, fallback: 0)
    }
    func candidate(edge: Int, offset: CGFloat) -> EnclosingSheetEvidence.Side? {
      let a = points[edge], b = points[(edge + 1) % 4]
      let length = hypot(b.x - a.x, b.y - a.y)
      guard length >= 30 else { return nil }
      let tangent = CGPoint(x: (b.x - a.x) / length, y: (b.y - a.y) / length)
      let normal = CGPoint(x: -tangent.y, y: tangent.x)
      let outerA = CGPoint(x: a.x + normal.x * offset, y: a.y + normal.y * offset)
      let outerB = CGPoint(x: b.x + normal.x * offset, y: b.y + normal.y * offset)
      let edgeEvidence = evidence(a: outerA, b: outerB, n: normal)
      guard edgeEvidence.1 >= 10, edgeEvidence.2 >= edgeEvidence.1 * 0.28,
            edgeEvidence.3 >= 0.78 else { return nil }

      let extensionLength = min(length * 0.22, CGFloat(34))
      let beforeA = CGPoint(x: outerA.x - tangent.x * extensionLength, y: outerA.y - tangent.y * extensionLength)
      let afterB = CGPoint(x: outerB.x + tangent.x * extensionLength, y: outerB.y + tangent.y * extensionLength)
      let before = lineSupport(a: beforeA, b: outerA, n: normal)
      let after = lineSupport(a: outerB, b: afterB, n: normal)
      guard before >= 8, after >= 8 else { return nil }

      var band: [SIMD3<Double>] = []
      var nearCandidate: [SIMD3<Double>] = []
      var nearOuter: [SIMD3<Double>] = []
      for along in 1...9 {
        let t = CGFloat(along) / 10
        let base = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        for fraction in [CGFloat(0.18), 0.38, 0.58, 0.78] {
          guard let value = color(CGPoint(x: base.x + normal.x * offset * fraction,
                                         y: base.y + normal.y * offset * fraction)) else { return nil }
          band.append(value)
          if fraction == 0.18 { nearCandidate.append(value) }
          if fraction == 0.78 { nearOuter.append(value) }
        }
      }
      let median = SIMD3(
        band.map(\.x).sorted()[band.count / 2],
        band.map(\.y).sorted()[band.count / 2],
        band.map(\.z).sorted()[band.count / 2]
      )
      let variation = percentile(band.map { distance($0, median) }, 0.85)
      let similarity = percentile(zip(nearCandidate, nearOuter).map(distance), 0.85)
      guard variation <= 11, similarity <= 10 else { return nil }
      return .init(edge: edge, offset: Double(offset), broad: edgeEvidence.1,
                   sharp: edgeEvidence.2, coherence: edgeEvidence.3,
                   beforeContinuation: before, afterContinuation: after,
                   bandVariation: variation, bandSimilarity: similarity)
    }

    var best: [Int: EnclosingSheetEvidence.Side] = [:]
    for edge in 0..<4 {
      let a = points[edge], b = points[(edge + 1) % 4]
      let length = hypot(b.x - a.x, b.y - a.y)
      let normal = CGPoint(x: -(b.y - a.y) / max(1, length), y: (b.x - a.x) / max(1, length))
      let center = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
      var distances: [CGFloat] = []
      if normal.x > 0.001 { distances.append((CGFloat(width - 2) - center.x) / normal.x) }
      if normal.x < -0.001 { distances.append((center.x - 2) / -normal.x) }
      if normal.y > 0.001 { distances.append((CGFloat(height - 2) - center.y) / normal.y) }
      if normal.y < -0.001 { distances.append((center.y - 2) / -normal.y) }
      distances = distances.filter { $0 > 0 }
      guard let bound = distances.min() else { continue }
      let opposite = points[(edge + 2) % 4]
      let span = abs((opposite.x - a.x) * normal.x + (opposite.y - a.y) * normal.y)
      let maximum = min(bound - 6, span * 0.48, CGFloat(max(width, height)) * 0.24)
      guard maximum >= 14 else { continue }
      var offset: CGFloat = 10
      while offset <= maximum {
        if let match = candidate(edge: edge, offset: offset),
           best[edge] == nil || match.broad > best[edge]!.broad {
          best[edge] = match
        }
        offset += 2
      }
    }

    for pair in [[0, 2], [1, 3]] {
      if let first = best[pair[0]], let second = best[pair[1]] {
        return .init(veto: true, reason: "paired_parallel_outer_edges_with_connected_paper_bands",
                     pair: pair, sides: [first, second])
      }
    }
    return .init(veto: false, reason: "no_paired_enclosing_sheet_evidence", pair: [],
                 sides: best.keys.sorted().compactMap { best[$0] })
  }
}

private extension BoundaryPixels {
  // A dark printed frame has light surface on both sides of at least three
  // perimeter strokes. A booklet has one binding; its physical outside edges
  // do not form a closed dark band surrounded by the same light sheet.
  func hasPrintedFrame(_ rectangle: VNRectangleObservation, requireMatchingSurfaces: Bool = false) -> Bool {
    let points=[rectangle.topLeft,rectangle.topRight,rectangle.bottomRight,rectangle.bottomLeft].map {CGPoint(x:$0.x*CGFloat(width),y:$0.y*CGFloat(height))}
    var framedSides=0
    for edge in 0..<4 {
      let a=points[edge],b=points[(edge+1)%4],length=hypot(b.x-a.x,b.y-a.y)
      guard length>1 else {continue}
      let n=CGPoint(x:-(b.y-a.y)/length,y:(b.x-a.x)/length)
      var supported=0
      for index in 0..<25 {
        let t=CGFloat(index+2)/28,p=CGPoint(x:a.x+(b.x-a.x)*t,y:a.y+(b.y-a.y)*t)
        var valley=false
        for offset in stride(from:CGFloat(-4),through:4,by:1) {
          func luma(_ d:CGFloat)->Double? {
            guard let c=color(CGPoint(x:p.x+n.x*(offset+d),y:p.y+n.y*(offset+d))) else {return nil}
            return (c.x+c.y+c.z)/3
          }
          guard let center=luma(0) else {continue}
          for radius in [CGFloat(3),5,8,11,14] {
            if let inside=luma(-radius),let outside=luma(radius),min(inside,outside)-center>=16 {
              if requireMatchingSurfaces {
                // A printed inset has the same paper surface on both flanks.
                // A dark margin at the physical edge can instead separate white
                // paper from a different-colored background; luma alone confuses them.
                guard let innerColor=color(CGPoint(x:p.x+n.x*(offset-radius),y:p.y+n.y*(offset-radius))),
                  let outerColor=color(CGPoint(x:p.x+n.x*(offset+radius),y:p.y+n.y*(offset+radius))) else {continue}
                let delta=innerColor-outerColor
                guard sqrt((delta*delta).sum()/3) <= 10 else {continue}
              }
              valley=true;break
            }
          }
          if valley {break}
        }
        if valley {supported += 1}
      }
      if supported >= 20 {framedSides += 1}
    }
    return framedSides >= 3
  }
}
