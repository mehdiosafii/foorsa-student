/// Deterministic, offline live-scanner analysis on a tiny greyscale preview.
///
/// No OCR, raw camera uploads, or heavy ML calls happen here. The automatic
/// shutter requires the page's outline, visible image detail and a steady
/// frame; if it cannot prove readiness, the manual shutter remains.
///
/// The outline is found two ways. The guide's own four borders first: straight
/// edges near where the guide asks for them, which is exact for a page held
/// square to the phone. When they are not there, the page is taken as the
/// bright region the background surrounds (scan_page_segment.dart), which
/// finds a page turned, held at a slant, larger or smaller than the guide, or
/// off its centre: on Android, before 31 Oct 2026, a page turned by 8°, or
/// filling the screen, was never found, so the camera never took it alone.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../app_language.dart';
import 'scan_document_profile.dart';
import 'scan_page_segment.dart';

enum GuidedDocumentKind { passport, idCard, page }

extension GuidedDocumentKindInfo on GuidedDocumentKind {
  static GuidedDocumentKind fromPortal(String value) {
    switch (value.toLowerCase()) {
      case 'passport':
        return GuidedDocumentKind.passport;
      case 'id_card':
        return GuidedDocumentKind.idCard;
      default:
        return GuidedDocumentKind.page;
    }
  }

  String get label => switch (this) {
        GuidedDocumentKind.passport => 'passport',
        GuidedDocumentKind.idCard => 'ID card',
        GuidedDocumentKind.page => 'document',
      };

  String get instruction => switch (this) {
        GuidedDocumentKind.passport =>
          'Keep the photo, every corner and both bottom lines visible.',
        GuidedDocumentKind.idCard =>
          'Keep all four corners and printed details visible.',
        GuidedDocumentKind.page =>
          'Include the entire sheet, including stamps and signatures.',
      };

  /// A loose guide, never a hard crop. The real edges are found nearby.
  Rect get guide => switch (this) {
        GuidedDocumentKind.passport =>
          const Rect.fromLTWH(0.085, 0.355, 0.83, 0.29),
        GuidedDocumentKind.idCard =>
          const Rect.fromLTWH(0.09, 0.37, 0.82, 0.26),
        GuidedDocumentKind.page =>
          const Rect.fromLTWH(0.14, 0.19, 0.72, 0.62),
      };
}

class ScanLumaGrid {
  const ScanLumaGrid(this.width, this.height, this.pixels);

  final int width;
  final int height;
  final Uint8List pixels;

  bool get valid =>
      width >= 40 && height >= 40 && pixels.length == width * height;

  int value(int x, int y) => pixels[y * width + x];
}

enum ScanHint {
  position,
  moveCloser,
  moveBack,
  brighten,
  reduceGlare,
  focus,
  holdSteady,
  ready,
}

extension ScanHintLabel on ScanHint {
  String get label => labelIn(AppLanguage.en);

  /// What the camera says, in the student's language.
  String labelIn(AppLanguage language) => (switch (this) {
        ScanHint.position => const Words('Align all four edges',
            'Alignez les quatre bords', 'اضبط الحواف الأربعة'),
        ScanHint.moveCloser => const Words('Move a little closer',
            'Rapprochez-vous un peu', 'اقترب قليلًا'),
        ScanHint.moveBack => const Words('Move back to include every corner',
            'Reculez pour inclure chaque coin', 'ابتعد قليلًا لتظهر كل الزوايا'),
        ScanHint.brighten => const Words('Find brighter, even light',
            'Cherchez une lumière plus vive et égale',
            'ابحث عن إضاءة أقوى ومتساوية'),
        ScanHint.reduceGlare => const Words('Tilt slightly to remove glare',
            'Inclinez légèrement pour éviter le reflet',
            'أمِل الهاتف قليلًا لإزالة الانعكاس'),
        ScanHint.focus => const Words('Move closer and let the camera focus',
            'Rapprochez-vous et laissez l’appareil faire la mise au point',
            'اقترب واترك الكاميرا تضبط التركيز'),
        ScanHint.holdSteady =>
          const Words('Hold still', 'Ne bougez plus', 'ثبّت الهاتف'),
        ScanHint.ready => const Words(
            'Document aligned', 'Document aligné', 'الوثيقة في مكانها'),
      })
          .of(language);
}

class ScanFrameAnalysis {
  const ScanFrameAnalysis({
    required this.hint,
    required this.bounds,
    required this.edgeSupport,
    required this.motion,
    required this.brightness,
    required this.sharpness,
    required this.contrast,
    this.corners,
    this.shadow = false,
  });

  final ScanHint hint;

  /// The page's outline as an upright rectangle in the visible preview's
  /// normalized coordinates (the box round [corners] for a page held at a
  /// slant).
  final Rect? bounds;

  /// The page's four corners, top-left first and clockwise, in the same
  /// coordinates, when the page was found.
  final List<Offset>? corners;
  final double edgeSupport;
  final double motion;
  final double brightness;
  final double sharpness;
  final int contrast;

  /// A sizeable part of the page lies in shadow (a hand, the phone): only a
  /// hint for the student, never a reason to keep a page from being taken for
  /// long ([ScanFrameAnalyzer.shadowOn]).
  final bool shadow;

  bool get autoReady => hint == ScanHint.ready && bounds != null;
}

class _Line {
  const _Line(this.position, this.support, this.strength);
  final int position;
  final double support;
  final double strength;
}


class _ScanCandidate {
  const _ScanCandidate(this.l, this.r, this.t, this.b, this.support, this.score);
  final int l;
  final int r;
  final int t;
  final int b;
  final double support;
  final double score;
}

class ScanFrameAnalyzer {
  const ScanFrameAnalyzer();

  /// Paper this much darker than the brightest paper on the page lies in
  /// shadow, as on the iPhone (ScannerLiveLightingAssessment).
  static const shadowRatio = 0.62;

  /// Below this share of the brightest paper, a block is print (a photo, a
  /// navy band), not paper in shadow: the camera reads luminance alone, so
  /// what the iPhone tells by colour is told here by how dark it is.
  static const printRatio = 0.25;

  /// Whether a sizeable, connected part of the page's paper (between 15% and
  /// 85% of it) is in shadow: the page inside its outline ([corners], in grid
  /// cells, drawn in by 7% so its edge is left out) is cut into blocks, the
  /// bright end of each (its 90th percentile) is the paper there, and a block
  /// whose paper is far darker than the page's brightest paper is shaded.
  /// Scattered dark blocks (artwork, a photo) are not a shadow, and neither is
  /// the desk round a page held at a slant: only cells inside the outline count.
  static bool shadowOn(ScanLumaGrid g, List<Offset> corners) {
    if (corners.length != 4) return false;
    final centre = corners.fold(Offset.zero, (sum, c) => sum + c) / 4;
    final inner = [for (final c in corners) centre + (c - centre) * 0.86];
    var minX = g.width.toDouble(), minY = g.height.toDouble(), maxX = 0.0, maxY = 0.0;
    for (final c in inner) {
      minX = math.min(minX, c.dx);
      minY = math.min(minY, c.dy);
      maxX = math.max(maxX, c.dx);
      maxY = math.max(maxY, c.dy);
    }
    final x0 = math.max(0, minX.floor()), y0 = math.max(0, minY.floor());
    final x1 = math.min(g.width - 1, maxX.ceil()), y1 = math.min(g.height - 1, maxY.ceil());
    final width = x1 - x0 + 1, height = y1 - y0 + 1;
    if (width < 18 || height < 18) return false;
    // The outline's winding, so "inside" is one side of every edge.
    var area = 0.0;
    for (var i = 0; i < 4; i++) {
      final a = inner[i], b = inner[(i + 1) % 4];
      area += a.dx * b.dy - b.dx * a.dy;
    }
    final sign = area >= 0 ? 1.0 : -1.0;
    bool inside(double x, double y) {
      for (var i = 0; i < 4; i++) {
        final a = inner[i], b = inner[(i + 1) % 4];
        if (((b.dx - a.dx) * (y - a.dy) - (b.dy - a.dy) * (x - a.dx)) * sign < 0) return false;
      }
      return true;
    }
    final columns = width >= height ? 8 : 6, rows = width >= height ? 6 : 8;
    final levels = List<double>.filled(columns * rows, double.nan);
    final values = <int>[];
    for (var row = 0; row < rows; row++) {
      final top = y0 + row * height ~/ rows, bottom = y0 + (row + 1) * height ~/ rows;
      for (var column = 0; column < columns; column++) {
        final left = x0 + column * width ~/ columns, right = x0 + (column + 1) * width ~/ columns;
        values.clear();
        var cells = 0;
        for (var y = top; y < bottom; y++) {
          for (var x = left; x < right; x++) {
            cells++;
            if (inside(x + 0.5, y + 0.5)) values.add(g.value(x, y));
          }
        }
        // A block mostly outside the page is left out.
        if (cells == 0 || values.length < cells * 0.6) continue;
        values.sort();
        levels[row * columns + column] = values[((values.length - 1) * 0.9).floor()].toDouble();
      }
    }
    final known = [for (final level in levels) if (!level.isNaN) level]..sort();
    if (known.length < 12) return false;
    final bright = known[((known.length - 1) * 0.9).floor()];
    if (bright < 60) return false;
    final shaded = [
      for (final level in levels) !level.isNaN && level < bright * shadowRatio && level >= bright * printRatio,
    ];
    final total = shaded.where((s) => s).length;
    if (total < known.length * 0.15 || total > known.length * 0.85) return false;
    // The largest connected group of shaded blocks: a shadow is one region.
    final seen = List<bool>.filled(levels.length, false);
    var largest = 0;
    for (var start = 0; start < levels.length; start++) {
      if (!shaded[start] || seen[start]) continue;
      var size = 0;
      final stack = [start];
      seen[start] = true;
      while (stack.isNotEmpty) {
        final at = stack.removeLast();
        size++;
        final column = at % columns, row = at ~/ columns;
        for (final next in [
          if (column > 0) at - 1, if (column < columns - 1) at + 1,
          if (row > 0) at - columns, if (row < rows - 1) at + columns,
        ]) {
          if (shaded[next] && !seen[next]) {
            seen[next] = true;
            stack.add(next);
          }
        }
      }
      if (size > largest) largest = size;
    }
    return largest >= known.length * 0.15;
  }

  /// A page's left (`inward` 1) or right (`inward` -1) edge: a column
  /// along which the paper is brighter than what lies outside it. The
  /// polarity keeps out the edges of a block of print, which is darker than
  /// the margin round it: on a white desk, the old any-polarity search took
  /// a page's text block for the page and lost it again a frame later.
  _Line? _vertical(
    ScanLumaGrid g,
    int target,
    int band,
    int top,
    int bottom, {
    required int inward,
  }) {
    _Line? best;
    double bestScore = -1;
    final minX = math.max(2, target - band);
    final maxX = math.min(g.width - 3, target + band);
    for (var x = minX; x <= maxX; x++) {
      var hits = 0;
      var energy = 0.0;
      var total = 0;
      for (var y = top; y <= bottom; y += 2) {
        final contrast = math.max(0, (g.value(x + 2 * inward, y) - g.value(x - 2 * inward, y)));
        if (contrast >= 23) hits++;
        energy += contrast;
        total++;
      }
      if (total == 0) continue;
      final support = hits / total;
      final strength = energy / total;
      final score = strength * (0.3 + 0.7 * support);
      if (score > bestScore) {
        best = _Line(x, support, strength);
        bestScore = score;
      }
    }
    return best != null && best.support >= 0.53 && best.strength >= 20
        ? best
        : null;
  }

  /// A page's top (`inward` 1) or bottom (`inward` -1) edge, as [_vertical].
  _Line? _horizontal(
    ScanLumaGrid g,
    int target,
    int band,
    int left,
    int right, {
    required int inward,
  }) {
    _Line? best;
    double bestScore = -1;
    final minY = math.max(2, target - band);
    final maxY = math.min(g.height - 3, target + band);
    for (var y = minY; y <= maxY; y++) {
      var hits = 0;
      var energy = 0.0;
      var total = 0;
      for (var x = left; x <= right; x += 2) {
        final contrast = math.max(0, (g.value(x, y + 2 * inward) - g.value(x, y - 2 * inward)));
        if (contrast >= 23) hits++;
        energy += contrast;
        total++;
      }
      if (total == 0) continue;
      final support = hits / total;
      final strength = energy / total;
      final score = strength * (0.3 + 0.7 * support);
      if (score > bestScore) {
        best = _Line(y, support, strength);
        bestScore = score;
      }
    }
    return best != null && best.support >= 0.53 && best.strength >= 20
        ? best
        : null;
  }

  /// How much the view changed since the last frame: the mean difference of
  /// 2×2 blocks of the grid. A block rather than a cell, so a hand's tremor of
  /// a pixel or two over fine print is not read as the page moving.
  double _motion(ScanLumaGrid a, ScanLumaGrid? b) {
    if (b == null || !b.valid || b.width != a.width || b.height != a.height) {
      return double.infinity; // one frame alone cannot prove stability
    }
    var diff = 0.0;
    var samples = 0;
    for (var y = 4; y < a.height - 5; y += 4) {
      for (var x = 4; x < a.width - 5; x += 4) {
        final blockA = a.value(x, y) + a.value(x + 1, y) + a.value(x, y + 1) + a.value(x + 1, y + 1);
        final blockB = b.value(x, y) + b.value(x + 1, y) + b.value(x, y + 1) + b.value(x + 1, y + 1);
        diff += (blockA - blockB).abs() / 4;
        samples++;
      }
    }
    return samples == 0 ? double.infinity : diff / samples;
  }

  ScanFrameAnalysis analyse(
    ScanLumaGrid current,
    GuidedDocumentKind kind, {
    ScanLumaGrid? previous,
    GuidedDocumentProfile? profile,
    double viewportAspect = 0.5,
  }) {
    if (!current.valid) {
      return const ScanFrameAnalysis(
        hint: ScanHint.position, bounds: null, edgeSupport: 0,
        motion: double.infinity, brightness: 0, sharpness: 0, contrast: 0,
      );
    }
    final w = current.width;
    final h = current.height;
    final aspect = viewportAspect.isFinite && viewportAspect > 0.25 &&
      viewportAspect < 1.3 ? viewportAspect : 0.5;
    final guides = profile?.candidateGuides(aspect) ?? [kind.guide];
    final motion = _motion(current, previous);
    _ScanCandidate? best;
    var sawSmall = false;
    var sawClipped = false;

    // Follow detected borders within a generous band around the initial
    // document hint. Portrait and landscape are both attempted for variable
    // university formats. The actual detected bounds (not the hint) are what
    // the UI highlights and the shutter stability gate tracks.
    for (final guide in guides) {
      final l = (guide.left * w).round();
      final r = (guide.right * w).round();
      final t = (guide.top * h).round();
      final b = (guide.bottom * h).round();
      final midTop = (t + (b - t) * 0.15).round();
      final midBottom = (b - (b - t) * 0.15).round();
      // Sample almost the entire horizontal border. Interior printed
      // baselines often span the middle 70% of a document and otherwise
      // masquerade as its top/bottom edge.
      final midLeft = (l + (r - l) * 0.04).round();
      final midRight = (r - (r - l) * 0.04).round();
      final bandX = math.max(4, (w * (profile == null ? 0.1 : 0.16)).round());
      final bandY = math.max(5, (h * (profile == null ? 0.075 : 0.14)).round());
      final left = _vertical(current, l, bandX, midTop, midBottom, inward: 1);
      final right = _vertical(current, r, bandX, midTop, midBottom, inward: -1);
      final top = _horizontal(current, t, bandY, midLeft, midRight, inward: 1);
      final bottom = _horizontal(current, b, bandY, midLeft, midRight, inward: -1);
      if (left == null || right == null || top == null || bottom == null) continue;
      final x0 = left.position;
      final x1 = right.position;
      final y0 = top.position;
      final y1 = bottom.position;
      if (x1 <= x0 || y1 <= y0) continue;
      final width = x1 - x0;
      final height = y1 - y0;
      if (width < (r - l) * 0.68 || height < (b - t) * 0.68) {
        sawSmall = true;
        continue;
      }
      if (x0 < w * 0.035 || x1 > w * 0.965 ||
          y0 < h * 0.035 || y1 > h * 0.965) {
        sawClipped = true;
        continue;
      }
      // Source grid pixels are 120x160 while the actual phone viewport may
      // have any aspect. Convert detected pixel dimensions to normalized
      // viewport proportions BEFORE evaluating physical paper aspect.
      final ratio = (width / w) / (height / h) * aspect;
      if (profile != null && !profile.supportsRatio(ratio)) continue;
      final support = math.min(
        math.min(left.support, right.support),
        math.min(top.support, bottom.support),
      );
      // Prefer complete straight borders, not high-contrast printed text.
      // A shape closer to the expected paper ratio wins when multiple
      // rectangle candidates are found, without requiring an exact match.
      final expectedRatio = (guide.width / guide.height) * aspect;
      final aspectPenalty = (ratio - expectedRatio).abs() / expectedRatio;
      final score = support * 4
          + (left.strength + right.strength + top.strength + bottom.strength) / 280
          - aspectPenalty * (profile == null ? 0 : 0.8);
      final candidate = _ScanCandidate(x0, x1, y0, y1, support, score);
      if (best == null || candidate.score > best.score) best = candidate;
    }

    List<Offset>? corners;
    if (best == null) {
      // No straight border where the guide asks for it: the page as the
      // bright region the background surrounds, wherever it is held.
      final segment = ScanPageSegmenter.find(current,
          aspect: aspect, profile: profile, guides: guides);
      if (segment.page != null) {
        final page = segment.page!;
        final box = page.bounds;
        best = _ScanCandidate(
          (box.left * w).round(), (box.right * w).round(),
          (box.top * h).round(), (box.bottom * h).round(), page.fill, 0,
        );
        corners = page.corners;
      } else {
        final hint = sawClipped || segment.clipped ? ScanHint.moveBack
          : sawSmall || segment.small ? ScanHint.moveCloser
          : ScanHint.position;
        return ScanFrameAnalysis(
          hint: hint, bounds: null, edgeSupport: 0,
          motion: motion, brightness: 0, sharpness: 0, contrast: 0,
        );
      }
    }
    final x0 = best.l;
    final x1 = best.r;
    final y0 = best.t;
    final y1 = best.b;
    final support = best.support;
    final bounds = Rect.fromLTRB(x0 / w, y0 / h, x1 / w, y1 / h);
    corners ??= [bounds.topLeft, bounds.topRight, bounds.bottomRight, bounds.bottomLeft];
    final innerX0 = math.max(2, x0 + ((x1 - x0) * 0.07).round());
    final innerX1 = math.min(w - 3, x1 - ((x1 - x0) * 0.07).round());
    final innerY0 = math.max(2, y0 + ((y1 - y0) * 0.07).round());
    final innerY1 = math.min(h - 3, y1 - ((y1 - y0) * 0.07).round());
    final histogram = List<int>.filled(256, 0);
    var sum = 0.0;
    var lapSum = 0.0;
    var lapSquareSum = 0.0;
    var count = 0;
    var glareCenter = 0;
    var glareCenterCount = 0;
    var glareOuter = 0;
    var glareOuterCount = 0;

    for (var y = innerY0; y <= innerY1; y++) {
      for (var x = innerX0; x <= innerX1; x++) {
        final v = current.value(x, y);
        histogram[v]++;
        sum += v;
        count++;
        final lap = 4 * v - current.value(x - 1, y)
          - current.value(x + 1, y)
          - current.value(x, y - 1) - current.value(x, y + 1);
        lapSum += lap;
        lapSquareSum += lap * lap;
        final middle = x > x0 + (x1 - x0) * 0.3
          && x < x0 + (x1 - x0) * 0.7
          && y > y0 + (y1 - y0) * 0.3
          && y < y0 + (y1 - y0) * 0.7;
        if (middle) {
          glareCenterCount++;
          if (v >= 253) glareCenter++;
        } else {
          glareOuterCount++;
          if (v >= 253) glareOuter++;
        }
      }
    }
    if (count == 0) {
      return ScanFrameAnalysis(
        hint: ScanHint.position, bounds: bounds, edgeSupport: support,
        motion: motion, brightness: 0, sharpness: 0, contrast: 0,
        corners: corners,
      );
    }

    int quantile(double proportion) {
      final goal = math.max(1, (count * proportion).ceil());
      var running = 0;
      for (var v = 0; v < 256; v++) {
        running += histogram[v];
        if (running >= goal) return v;
      }
      return 255;
    }

    final brightness = sum / count;
    final contrast = quantile(0.95) - quantile(0.05);
    final sharpness = math.max(0.0,
      lapSquareSum / count - math.pow(lapSum / count, 2).toDouble(),
    );
    final centerWhite = glareCenterCount == 0 ? 0.0 : glareCenter / glareCenterCount;
    final outerWhite = glareOuterCount == 0 ? 0.0 : glareOuter / glareOuterCount;

    final hint = brightness < 75 || (brightness > 246 && contrast < 35)
        ? ScanHint.brighten
        : centerWhite > 0.48 && outerWhite < 0.12
          ? ScanHint.reduceGlare
          : contrast < 32 || sharpness < 24
            ? ScanHint.focus
            : motion > 10
              ? ScanHint.holdSteady
              : ScanHint.ready;
    return ScanFrameAnalysis(
      hint: hint, bounds: bounds, edgeSupport: support, motion: motion,
      brightness: brightness, sharpness: sharpness, contrast: contrast,
      corners: corners,
      shadow: hint != ScanHint.brighten &&
          shadowOn(current, [for (final c in corners) Offset(c.dx * w, c.dy * h)]),
    );
  }
}

/// Conservative auto-shutter gate. It never captures on one lucky frame, on
/// motion, or after a status transition. The manual shutter always works.
class ScanAutoCaptureGate {
  DateTime? _stableSince;
  Rect? _previousBounds;
  int _goodFrames = 0;
  bool _triggered = false;

  double get progress {
    if (_triggered) return 1;
    return (_goodFrames / 4).clamp(0.0, 1.0);
  }

  void reset() {
    _stableSince = null;
    _previousBounds = null;
    _goodFrames = 0;
    _triggered = false;
  }

  bool consume(ScanFrameAnalysis frame, DateTime now) {
    if (_triggered) return false;
    final ready = observe(frame, now);
    if (ready) _triggered = true;
    return ready;
  }

  /// The same hold as [consume], without its one-shot latch: true for as
  /// long as the page stays steady, so the live reading can decide the
  /// moment of capture (scan_text_reading.dart).
  bool observe(ScanFrameAnalysis frame, DateTime now) {
    final bounds = frame.bounds;
    if (!frame.autoReady || bounds == null) {
      _stableSince = null;
      _previousBounds = null;
      _goodFrames = 0;
      return false;
    }
    final prior = _previousBounds;
    if (prior != null && (
      (prior.center.dx - bounds.center.dx).abs() > 0.025
        || (prior.center.dy - bounds.center.dy).abs() > 0.025
        || (prior.width - bounds.width).abs() > 0.035
        || (prior.height - bounds.height).abs() > 0.035
    )) {
      _stableSince = now;
      _goodFrames = 1;
    } else {
      _stableSince ??= now;
      _goodFrames++;
    }
    _previousBounds = bounds;
    return _goodFrames >= 4
        && now.difference(_stableSince!).inMilliseconds >= 650;
  }
}
