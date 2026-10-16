/// Deterministic, offline live-scanner analysis on a tiny greyscale preview.
///
/// No OCR, raw camera uploads, or heavy ML calls happen here. The automatic
/// shutter requires four document-border signals, visible image detail and a
/// steady frame; if it cannot prove readiness, the manual shutter remains.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

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
  String get label => switch (this) {
        ScanHint.position => 'Align all four edges',
        ScanHint.moveCloser => 'Move a little closer',
        ScanHint.moveBack => 'Move back to include every corner',
        ScanHint.brighten => 'Find brighter, even light',
        ScanHint.reduceGlare => 'Tilt slightly to remove glare',
        ScanHint.focus => 'Move closer and let the camera focus',
        ScanHint.holdSteady => 'Hold still',
        ScanHint.ready => 'Document aligned',
      };
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
  });

  final ScanHint hint;
  final Rect? bounds;
  final double edgeSupport;
  final double motion;
  final double brightness;
  final double sharpness;
  final int contrast;

  bool get autoReady => hint == ScanHint.ready && bounds != null;
}

class _Line {
  const _Line(this.position, this.support, this.strength);
  final int position;
  final double support;
  final double strength;
}

class ScanFrameAnalyzer {
  const ScanFrameAnalyzer();

  _Line? _vertical(
    ScanLumaGrid g,
    int target,
    int band,
    int top,
    int bottom,
  ) {
    _Line? best;
    double bestScore = -1;
    final minX = math.max(2, target - band);
    final maxX = math.min(g.width - 3, target + band);
    for (var x = minX; x <= maxX; x++) {
      var hits = 0;
      var energy = 0.0;
      var total = 0;
      for (var y = top; y <= bottom; y += 2) {
        final contrast = (g.value(x + 2, y) - g.value(x - 2, y)).abs();
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

  _Line? _horizontal(
    ScanLumaGrid g,
    int target,
    int band,
    int left,
    int right,
  ) {
    _Line? best;
    double bestScore = -1;
    final minY = math.max(2, target - band);
    final maxY = math.min(g.height - 3, target + band);
    for (var y = minY; y <= maxY; y++) {
      var hits = 0;
      var energy = 0.0;
      var total = 0;
      for (var x = left; x <= right; x += 2) {
        final contrast = (g.value(x, y + 2) - g.value(x, y - 2)).abs();
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

  double _motion(ScanLumaGrid a, ScanLumaGrid? b) {
    if (b == null || !b.valid || b.width != a.width || b.height != a.height) {
      return double.infinity; // one frame alone cannot prove stability
    }
    var diff = 0.0;
    var samples = 0;
    for (var y = 4; y < a.height - 4; y += 4) {
      for (var x = 4; x < a.width - 4; x += 4) {
        diff += (a.value(x, y) - b.value(x, y)).abs();
        samples++;
      }
    }
    return samples == 0 ? double.infinity : diff / samples;
  }

  ScanFrameAnalysis analyse(
    ScanLumaGrid current,
    GuidedDocumentKind kind, {
    ScanLumaGrid? previous,
  }) {
    if (!current.valid) {
      return const ScanFrameAnalysis(
        hint: ScanHint.position, bounds: null, edgeSupport: 0,
        motion: double.infinity, brightness: 0, sharpness: 0, contrast: 0,
      );
    }
    final guide = kind.guide;
    final w = current.width;
    final h = current.height;
    final l = (guide.left * w).round();
    final r = (guide.right * w).round();
    final t = (guide.top * h).round();
    final b = (guide.bottom * h).round();
    final middleTop = (t + (b - t) * 0.15).round();
    final middleBottom = (b - (b - t) * 0.15).round();
    final middleLeft = (l + (r - l) * 0.14).round();
    final middleRight = (r - (r - l) * 0.14).round();
    final horizontalBand = math.max(4, (w * 0.1).round());
    final verticalBand = math.max(5, (h * 0.075).round());
    final left = _vertical(
      current, l, horizontalBand, middleTop, middleBottom,
    );
    final right = _vertical(
      current, r, horizontalBand, middleTop, middleBottom,
    );
    final top = _horizontal(
      current, t, verticalBand, middleLeft, middleRight,
    );
    final bottom = _horizontal(
      current, b, verticalBand, middleLeft, middleRight,
    );
    final motion = _motion(current, previous);
    if (left == null || right == null || top == null || bottom == null) {
      return ScanFrameAnalysis(
        hint: ScanHint.position, bounds: null, edgeSupport: 0,
        motion: motion, brightness: 0, sharpness: 0, contrast: 0,
      );
    }

    final x0 = left.position;
    final x1 = right.position;
    final y0 = top.position;
    final y1 = bottom.position;
    if (x1 - x0 < (r - l) * 0.74 || y1 - y0 < (b - t) * 0.72) {
      return ScanFrameAnalysis(
        hint: ScanHint.moveCloser, bounds: null, edgeSupport: 0,
        motion: motion, brightness: 0, sharpness: 0, contrast: 0,
      );
    }
    if (x0 < w * 0.035 || x1 > w * 0.965
        || y0 < h * 0.035 || y1 > h * 0.965) {
      return ScanFrameAnalysis(
        hint: ScanHint.moveBack, bounds: null, edgeSupport: 0,
        motion: motion, brightness: 0, sharpness: 0, contrast: 0,
      );
    }

    final bounds = Rect.fromLTRB(
      x0 / w, y0 / h, x1 / w, y1 / h,
    );
    final support = math.min(
      math.min(left.support, right.support),
      math.min(top.support, bottom.support),
    );
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
    if (_goodFrames >= 4
        && now.difference(_stableSince!).inMilliseconds >= 650) {
      _triggered = true;
      return true;
    }
    return false;
  }
}
