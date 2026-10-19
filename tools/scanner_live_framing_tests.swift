import CoreGraphics
import Foundation

// Pure live-framing tests for custom-live-v11. No camera, Vision or UIKit.
// xcrun swiftc ios/Runner/ScannerGeometry.swift tools/scanner_live_framing_tests.swift -o /tmp/scanner-live-framing-tests
@main
struct ScannerLiveFramingTests {
  static func quad(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> ScannerQuadrilateral {
    ScannerQuadrilateral(topLeft: CGPoint(x: x0, y: y1), topRight: CGPoint(x: x1, y: y1),
      bottomRight: CGPoint(x: x1, y: y0), bottomLeft: CGPoint(x: x0, y: y0))
  }

  static func profile(_ key: String) -> FoorsaScannerProfile {
    FoorsaScannerProfile(arguments: ["profile": ["documentKey": key, "outputMode": "imagegen"]])
  }

  static func page(width: Int, height: Int, paper: UInt8 = 236,
                   fill: (Int, Int, inout (UInt8, UInt8, UInt8)) -> Void = { _, _, _ in }) -> [UInt8] {
    var rgba = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height {
      for x in 0..<width {
        var pixel = (paper, paper, paper)
        // Sparse dark text strokes on every row band.
        if (y % 9 == 0 || y % 9 == 1) && x % 7 != 0 && x > width / 12 && x < width * 11 / 12 { pixel = (40, 40, 44) }
        fill(x, y, &pixel)
        let i = (y * width + x) * 4
        rgba[i] = pixel.0; rgba[i + 1] = pixel.1; rgba[i + 2] = pixel.2
      }
    }
    return rgba
  }

  static func main() {
    let portraitImage = CGSize(width: 3024, height: 4032)
    let diploma = profile("highest_degree")
    let passport = profile("identity")
    let card = profile("parent_id")

    // Plausibility rejects degenerate shapes and keeps perspective pages.
    precondition(quad(0.2, 0.2, 0.8, 0.8).isPlausiblePage(in: portraitImage))
    let perspective = ScannerQuadrilateral(topLeft: CGPoint(x: 0.25, y: 0.82), topRight: CGPoint(x: 0.75, y: 0.80),
      bottomRight: CGPoint(x: 0.85, y: 0.18), bottomLeft: CGPoint(x: 0.12, y: 0.20))
    precondition(perspective.isPlausiblePage(in: portraitImage))
    let bowTie = ScannerQuadrilateral(topLeft: CGPoint(x: 0.2, y: 0.8), topRight: CGPoint(x: 0.8, y: 0.2),
      bottomRight: CGPoint(x: 0.8, y: 0.8), bottomLeft: CGPoint(x: 0.2, y: 0.2))
    precondition(!bowTie.isPlausiblePage(in: portraitImage))
    let spike = ScannerQuadrilateral(topLeft: CGPoint(x: 0.2, y: 0.8), topRight: CGPoint(x: 0.8, y: 0.8),
      bottomRight: CGPoint(x: 0.95, y: 0.75), bottomLeft: CGPoint(x: 0.2, y: 0.2))
    precondition(!spike.isPlausiblePage(in: portraitImage))
    precondition(!quad(0.2, 0.49, 0.8, 0.51).isPlausiblePage(in: portraitImage))
    precondition(!quad(0.2, 0.2, 0.8, 0.8).isPlausiblePage(in: .zero))

    // The recording's case: a landscape diploma held across a portrait view,
    // with a cluttered background. It is a ready page, not a rotate request.
    let heldLandscape = ScannerQuadrilateral(topLeft: CGPoint(x: 0.07, y: 0.70), topRight: CGPoint(x: 0.91, y: 0.68),
      bottomRight: CGPoint(x: 0.92, y: 0.17), bottomLeft: CGPoint(x: 0.06, y: 0.16))
    precondition(ScannerLiveFramingPolicy.classify(heldLandscape, imageSize: portraitImage,
      profile: diploma, isClear: true) == .ready)
    precondition(heldLandscape.isComplete(minimumArea: diploma.minimumCaptureArea))
    precondition(ScannerLiveFramingPolicy.classify(nil, imageSize: portraitImage, profile: diploma, isClear: true) == .searching)
    precondition(ScannerLiveFramingPolicy.classify(bowTie, imageSize: portraitImage, profile: diploma, isClear: true) == .searching)
    precondition(ScannerLiveFramingPolicy.classify(quad(0.005, 0.1, 0.9, 0.9), imageSize: portraitImage,
      profile: diploma, isClear: true) == .clipped)
    precondition(ScannerLiveFramingPolicy.classify(quad(0.4, 0.4, 0.65, 0.65), imageSize: portraitImage,
      profile: diploma, isClear: true) == .tooSmall)
    precondition(ScannerLiveFramingPolicy.classify(heldLandscape, imageSize: portraitImage,
      profile: diploma, isClear: false) == .blurry)
    // A square in pixels is not a passport page or a card.
    let square = quad(0.1, 0.2, 0.9, 0.8)
    precondition(abs(square.estimatedAspectRatio(in: portraitImage) - 1) < 0.01)
    precondition(ScannerLiveFramingPolicy.classify(square, imageSize: portraitImage, profile: passport, isClear: true) == .wrongShape)
    precondition(ScannerLiveFramingPolicy.classify(square, imageSize: portraitImage, profile: card, isClear: true) == .wrongShape)
    precondition(ScannerLiveFramingPolicy.classify(square, imageSize: portraitImage, profile: diploma, isClear: true) == .ready)
    // Ready always satisfies the hold tracker's completeness rule.
    for case let candidate? in [heldLandscape, perspective, square] where
      ScannerLiveFramingPolicy.classify(candidate, imageSize: portraitImage, profile: diploma, isClear: true) == .ready {
      precondition(candidate.isComplete(minimumArea: diploma.minimumCaptureArea))
    }

    // A clipped page that contains an inner panel is still a clipped page.
    let clippedPage = quad(0.0, 0.05, 1.0, 0.95)
    precondition(clippedPage.encloses(quad(0.1, 0.15, 0.9, 0.85)))
    precondition(!quad(0.3, 0.3, 0.6, 0.6).encloses(quad(0.1, 0.15, 0.9, 0.85)))
    // The still margin grows the outline about its centre and stays in the image.
    let grown = quad(0.2, 0.2, 0.8, 0.8).expanded(by: 0.1)
    precondition(abs(grown.topLeft.x - 0.17) < 1e-9 && abs(grown.topLeft.y - 0.83) < 1e-9)
    let edge = quad(0.0, 0.0, 1.0, 1.0).expanded(by: 0.2)
    precondition(edge == ScannerQuadrilateral.fullFrame)
    precondition(ScannerQuadrilateral.fullFrame.isPlausiblePage(in: portraitImage))
    precondition(abs(ScannerQuadrilateral.fullFrame.area - 1) < 1e-9)

    // Every state has short, distinct guidance; light hints only follow a ready page.
    let framings: [ScannerLiveFraming] = [.searching, .ready, .tooSmall, .clipped, .wrongShape, .blurry]
    for layout in [FoorsaScannerProfile.Layout.passport, .card, .portrait, .adaptive] {
      for framing in framings {
        for lighting in [ScannerLiveLighting.good, .shadow, .glare, .dim] {
          let copy = ScannerLiveGuidance.copy(framing: framing, lighting: lighting, layout: layout)
          precondition(!copy.title.isEmpty && copy.title.count <= 26, copy.title)
          precondition(!copy.detail.isEmpty && copy.detail.count <= 64, copy.detail)
          precondition(!copy.compact.isEmpty && copy.compact.count <= 22, copy.compact)
          precondition(!copy.detail.contains("%"))
          if framing != .ready {
            precondition(copy == ScannerLiveGuidance.copy(framing: framing, lighting: .good, layout: layout))
          }
        }
      }
    }
    precondition(ScannerLiveGuidance.copy(framing: .tooSmall, lighting: .good, layout: .adaptive).title == "Move closer")
    precondition(ScannerLiveGuidance.copy(framing: .ready, lighting: .shadow, layout: .adaptive).title == "Shadow on the page")
    precondition(ScannerLiveGuidance.copy(framing: .ready, lighting: .good, layout: .adaptive).title == "Hold still")

    // The outline averages jitter, follows a real move at once, and survives
    // two missed frames before disappearing.
    var smoother = ScannerOutlineSmoother()
    let first = smoother.update(quad(0.2, 0.2, 0.8, 0.8))!
    precondition(first == quad(0.2, 0.2, 0.8, 0.8))
    let jittered = smoother.update(quad(0.21, 0.2, 0.81, 0.8))!
    precondition(jittered.topLeft.x > 0.2 && jittered.topLeft.x < 0.21)
    let moved = smoother.update(quad(0.4, 0.3, 0.95, 0.9))!
    precondition(moved == quad(0.4, 0.3, 0.95, 0.9))
    precondition(smoother.update(nil) != nil)
    precondition(smoother.update(nil) != nil)
    precondition(smoother.update(nil) == nil)
    smoother.reset()
    precondition(smoother.current == nil)

    // Lighting: plain pages are good; a large neutral shadow, a blown-out
    // reflection and a small dark header or colored panel behave as expected.
    let w = 120, h = 168
    precondition(ScannerPageLightingProbe.assess(rgba: page(width: w, height: h), width: w, height: h) == .good)
    let shadowed = page(width: w, height: h) { _, y, pixel in
      if y > h / 2 { pixel = (UInt8(Double(pixel.0) * 0.45), UInt8(Double(pixel.1) * 0.45), UInt8(Double(pixel.2) * 0.45)) }
    }
    precondition(ScannerPageLightingProbe.assess(rgba: shadowed, width: w, height: h) == .shadow)
    let glare = page(width: w, height: h) { x, y, pixel in
      if x > 80 && x < 105 && y > 20 && y < 45 { pixel = (255, 255, 255) }
    }
    precondition(ScannerPageLightingProbe.assess(rgba: glare, width: w, height: h) == .glare)
    let header = page(width: w, height: h) { _, y, pixel in if y < 14 { pixel = (20, 20, 22) } }
    precondition(ScannerPageLightingProbe.assess(rgba: header, width: w, height: h) == .good)
    let navyPanel = page(width: w, height: h) { x, _, pixel in if x < 40 { pixel = (24, 40, 110) } }
    precondition(ScannerPageLightingProbe.assess(rgba: navyPanel, width: w, height: h) == .good)
    let overexposed = page(width: w, height: h, paper: 255)
    precondition(ScannerPageLightingProbe.assess(rgba: overexposed, width: w, height: h) == .good)
    precondition(ScannerPageLightingProbe.assess(rgba: [1, 2, 3], width: 1, height: 1) == .good)

    // One missed preview frame keeps the hold; a second resets it. Defaults
    // keep the original single-miss reset.
    let stable = quad(0.2, 0.2, 0.8, 0.8)
    var tolerant = ScannerStabilityTracker(requiredDuration: 0.6, minimumArea: 0.16, requiredObservations: 4, toleratedMisses: 1)
    _ = tolerant.observe(stable, at: 0.0)
    _ = tolerant.observe(stable, at: 0.1)
    let held = tolerant.observe(stable, at: 0.2)
    precondition(held.progress > 0)
    let missed = tolerant.observe(nil, at: 0.3)
    precondition(missed.progress == held.progress && !missed.ready)
    _ = tolerant.observe(stable, at: 0.4)
    let ready = tolerant.observe(stable, at: 0.6)
    precondition(ready.ready, "a tolerated miss must not restart the hold")
    _ = tolerant.observe(nil, at: 0.7)
    precondition(tolerant.observe(nil, at: 0.8).progress == 0)
    var strict = ScannerStabilityTracker()
    _ = strict.observe(stable, at: 0.0)
    _ = strict.observe(stable, at: 0.1)
    precondition(strict.observe(nil, at: 0.2).progress == 0)
    precondition(strict.anchor == nil)
    var quick = ScannerStabilityTracker(requiredDuration: 0.2, minimumArea: 0.16, requiredObservations: 2)
    _ = quick.observe(stable, at: 0.0)
    precondition(!quick.observe(stable, at: 0.1).ready)
    precondition(quick.observe(stable, at: 0.25).ready)

    // Imagegen capture: two photos in one hold, waits for results, replaces a
    // soft view, stops at the attempt and time bounds.
    var policy = ScannerImagegenCapturePolicy(startedAt: 10)
    precondition(policy.decision(at: 10) == .shootNext)
    policy.photoRequested()
    precondition(policy.decision(at: 10.4) == .shootNext, "the second photo is taken without waiting for the first result")
    policy.photoRequested()
    precondition(policy.decision(at: 10.8) == .waitForResults)
    policy.photoResolved(usefulViews: 1)
    precondition(policy.decision(at: 11) == .waitForResults)
    policy.photoResolved(usefulViews: 2)
    precondition(policy.decision(at: 11.2) == .complete)
    var failing = ScannerImagegenCapturePolicy(startedAt: 0)
    for attempt in 1...ScannerImagegenCapturePolicy.maximumAttempts {
      precondition(failing.decision(at: Double(attempt)) == .shootNext)
      failing.photoRequested()
      failing.photoResolved(usefulViews: 0)
    }
    precondition(failing.decision(at: 9) == .giveUp)
    var slow = ScannerImagegenCapturePolicy(startedAt: 0)
    slow.photoRequested()
    precondition(slow.decision(at: ScannerImagegenCapturePolicy.totalDuration + 1) == .waitForResults)
    slow.photoResolved(usefulViews: 1)
    precondition(slow.decision(at: ScannerImagegenCapturePolicy.totalDuration + 1) == .giveUp)
    var replaced = ScannerImagegenCapturePolicy(startedAt: 0)
    replaced.photoRequested(); replaced.photoRequested()
    replaced.photoResolved(usefulViews: 1)
    replaced.photoResolved(usefulViews: 1)
    precondition(replaced.decision(at: 2) == .shootNext, "a dropped soft view asks for one more photo")

    // Outline refinement, on the corners Vision reported for synthetic
    // hand-held scenes (macOS run of scanner_live_detection_tests): the
    // document model threw corners to the frame edge or onto a hand while a
    // rectangle proposal traced the page.
    let scene = CGSize(width: 1080, height: 1440)
    func q(_ c: [(CGFloat, CGFloat)]) -> ScannerQuadrilateral {
      ScannerQuadrilateral(topLeft: CGPoint(x: c[0].0, y: c[0].1), topRight: CGPoint(x: c[1].0, y: c[1].1),
        bottomRight: CGPoint(x: c[2].0, y: c[2].1), bottomLeft: CGPoint(x: c[3].0, y: c[3].1))
    }
    func refined(_ model: ScannerQuadrilateral, _ proposals: [ScannerQuadrilateral]) -> ScannerQuadrilateral? {
      ScannerOutlineRefinement.refine(model: model, proposals: proposals, imageSize: scene)
    }
    // One corner thrown to the frame's corner: three agree.
    let page05 = q([(0.287, 0.747), (0.923, 0.688), (0.861, 0.359), (0.241, 0.417)])
    precondition(refined(q([(0.285, 0.754), (0.931, 0.691), (0.868, 0.355), (0.007, 0.004)]), [page05]) == page05)
    // One corner dragged onto a hand over the edge: three agree, and the
    // proposal wins over a model outline that was itself "ready".
    let page06 = q([(0.231, 0.845), (0.900, 0.841), (0.865, 0.158), (0.253, 0.162)])
    let model06 = q([(0.229, 0.852), (0.903, 0.848), (0.875, 0.152), (0.083, 0.141)])
    precondition(ScannerLiveFramingPolicy.classify(model06, imageSize: scene, profile: diploma, isClear: true) == .ready)
    precondition(refined(model06, [page06]) == page06)
    // Two corners ran to the frame's edge: two agree, and the stray two are at the edge.
    let page13 = q([(0.073, 0.764), (0.815, 0.765), (0.790, 0.388), (0.096, 0.387)])
    let model13 = q([(0.069, 0.770), (1.000, 0.996), (1.000, 0.234), (0.090, 0.383)])
    let clipped13 = q([(0.012, 0.896), (0.834, 0.772), (0.808, 0.373), (0.085, 0.373)])
    precondition(refined(model13, [clipped13, page13]) == page13, "the agreeing proposal, not a clipped neighbour")
    let page15 = q([(0.191, 0.661), (0.881, 0.722), (0.923, 0.366), (0.262, 0.307)])
    let cushion15 = q([(0.018, 0.624), (0.419, 0.624), (0.418, 0.047), (0.016, 0.047)])
    precondition(refined(q([(0.222, 0.996), (0.889, 0.730), (0.938, 0.359), (0.007, 0.043)]), [page15, cushion15]) == page15)
    // Two diagonal corners agree but one stray corner is inside the frame:
    // not enough to replace the model (page 11 stays for the next frame).
    precondition(refined(q([(0.104, 0.996), (0.715, 0.750), (0.917, 0.188), (0.153, 0.352)]),
      [q([(0.079, 0.674), (0.703, 0.744), (0.756, 0.421), (0.155, 0.353)])]) == nil)
    // Corner labels do not matter: the same page listed from another corner.
    let relabelled = q([(0.923, 0.688), (0.861, 0.359), (0.241, 0.417), (0.287, 0.747)])
    precondition(ScannerOutlineRefinement.agreement(of: relabelled,
      with: q([(0.285, 0.754), (0.931, 0.691), (0.868, 0.355), (0.007, 0.004)]), imageSize: scene).agreeing == 3)
    // A printed border four percent inside the page never stands in for it.
    let sheet = q([(0.15, 0.80), (0.85, 0.80), (0.85, 0.30), (0.15, 0.30)])
    let border = sheet.expanded(by: -0.08)
    precondition(ScannerOutlineRefinement.agreement(of: border, with: sheet, imageSize: scene).agreeing == 0)
    precondition(refined(sheet, [border]) == nil)
    // One page of an open booklet shares two corners with the whole spread,
    // whose other corners are inside the frame: the spread keeps its outline.
    let spread = q([(0.10, 0.70), (0.90, 0.70), (0.90, 0.35), (0.10, 0.35)])
    let rightPage = q([(0.50, 0.70), (0.90, 0.70), (0.90, 0.35), (0.50, 0.35)])
    precondition(ScannerOutlineRefinement.agreement(of: rightPage, with: spread, imageSize: scene).agreeing == 2)
    precondition(refined(spread, [rightPage]) == nil)
    // Page-free clutter whose model outline hugs the frame matches nothing.
    precondition(refined(q([(0.007, 0.656), (0.924, 0.684), (0.993, 0.004), (0.083, 0.004)]),
      [q([(0.148, 0.852), (0.414, 0.889), (0.432, 0.665), (0.125, 0.665)])]) == nil)
    // A model that is already right is sharpened by the proposal tracing it.
    let model00 = q([(0.229, 0.719), (0.792, 0.754), (0.868, 0.137), (0.285, 0.102)])
    let page00 = q([(0.214, 0.719), (0.793, 0.754), (0.867, 0.136), (0.275, 0.101)])
    precondition(refined(model00, [q([(0.132, 0.477), (0.304, 0.488), (0.317, 0.362), (0.147, 0.316)]), page00]) == page00)

    print("PASS: live framing states, plausibility, guidance copy, outline smoothing, lighting probe, miss-tolerant hold, imagegen one-hold capture policy, outline refinement")
  }
}
