/// The page as the bright region its background surrounds, on the guided
/// scanner's small luminance grid (Android's frame analysis, scan_guidance.dart).
///
/// The guide's border search needs four straight edges close to where the
/// guide asks for them, so it misses a page turned by more than a few
/// degrees, held at a slant, larger than the guide or off its centre. This
/// finds the page wherever it is: the grid is split into a bright and a dark
/// population (Otsu), the dark cells reachable from the frame's edge are the
/// background, and the largest region they surround is the page, printed
/// lines and photos included. Its four corners are its extreme points, and it
/// is a page only if it fills the quadrilateral they make, has two pairs of
/// matching sides, the paper's shape and a clear step to its background.
/// A white page on a white desk has no such step: the live reading's text is
/// what finds it then (scan_frame_loop.dart).
library;

import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'scan_document_profile.dart';
import 'scan_guidance.dart';

class ScanSegmentedPage {
  const ScanSegmentedPage({required this.bounds, required this.corners, required this.fill});

  /// Upright rectangle round the corners, normalized to the grid.
  final Rect bounds;

  /// Top-left, top-right, bottom-right, bottom-left, normalized to the grid.
  final List<Offset> corners;

  /// The share of the corners' quadrilateral the region fills.
  final double fill;
}

class ScanPageSegment {
  const ScanPageSegment({this.page, this.clipped = false, this.small = false});
  static const none = ScanPageSegment();

  final ScanSegmentedPage? page;

  /// A page-like region reaches the frame's edge: part of it is out of view.
  final bool clipped;

  /// A page-like region is there but far smaller than the guide.
  final bool small;
}

abstract final class ScanPageSegmenter {
  /// The two populations must differ by this much (grid levels).
  static const minimumSeparation = 24;

  /// The page must fill this share of its corners' quadrilateral.
  static const minimumFill = 0.84;

  /// Opposite sides at most this different (a page seen at a slant).
  static const minimumSideRatio = 0.72;

  /// Its share of the view, at least and at most.
  static const minimumArea = 0.08;
  static const maximumArea = 0.93;

  /// How much brighter than the background around it.
  static const minimumStep = 18.0;

  static ScanPageSegment find(ScanLumaGrid g, {
    required double aspect,
    GuidedDocumentProfile? profile,
    List<Rect> guides = const [],
  }) {
    if (!g.valid) return ScanPageSegment.none;
    final w = g.width, h = g.height, n = w * h;
    final pixels = g.pixels;

    // Otsu: the threshold that best splits the grid into two populations.
    final histogram = List<int>.filled(256, 0);
    var total = 0.0;
    for (final v in pixels) {
      histogram[v]++;
      total += v;
    }
    var bestThreshold = -1;
    var bestVariance = -1.0;
    var countBelow = 0, sumBelow = 0.0;
    for (var t = 0; t < 255; t++) {
      countBelow += histogram[t];
      sumBelow += t * histogram[t];
      final countAbove = n - countBelow;
      if (countBelow == 0 || countAbove == 0) continue;
      final meanBelow = sumBelow / countBelow;
      final meanAbove = (total - sumBelow) / countAbove;
      final variance = countBelow * countAbove * (meanAbove - meanBelow) * (meanAbove - meanBelow);
      if (variance > bestVariance) {
        bestVariance = variance;
        bestThreshold = t;
      }
    }
    if (bestThreshold < 0) return ScanPageSegment.none;
    var darkCount = 0, darkSum = 0.0;
    for (var t = 0; t <= bestThreshold; t++) {
      darkCount += histogram[t];
      darkSum += t * histogram[t];
    }
    final brightCount = n - darkCount;
    if (darkCount == 0 || brightCount == 0) return ScanPageSegment.none;
    final separation = (total - darkSum) / brightCount - darkSum / darkCount;
    if (separation < minimumSeparation) return ScanPageSegment.none;

    // The background: dark cells reachable from the frame's edge.
    final background = Uint8List(n);
    final queue = Queue<int>();
    void seed(int index) {
      if (background[index] == 0 && pixels[index] <= bestThreshold) {
        background[index] = 1;
        queue.add(index);
      }
    }
    for (var x = 0; x < w; x++) {
      seed(x);
      seed((h - 1) * w + x);
    }
    for (var y = 0; y < h; y++) {
      seed(y * w);
      seed(y * w + w - 1);
    }
    while (queue.isNotEmpty) {
      final index = queue.removeFirst();
      final x = index % w, y = index ~/ w;
      if (x > 0) seed(index - 1);
      if (x < w - 1) seed(index + 1);
      if (y > 0) seed(index - w);
      if (y < h - 1) seed(index + w);
    }

    // Regions the background surrounds; the largest is the page.
    final label = Int32List(n)..fillRange(0, n, -1);
    _Region? page;
    _Region? clippedRegion;
    for (var start = 0; start < n; start++) {
      if (background[start] == 1 || label[start] >= 0) continue;
      final region = _Region();
      label[start] = 0;
      queue.add(start);
      while (queue.isNotEmpty) {
        final index = queue.removeFirst();
        final x = index % w, y = index ~/ w;
        region.add(x, y, pixels[index], w, h, aspect);
        void visit(int next) {
          if (background[next] == 0 && label[next] < 0) {
            label[next] = 0;
            queue.add(next);
          }
        }
        if (x > 0) visit(index - 1);
        if (x < w - 1) visit(index + 1);
        if (y > 0) visit(index - w);
        if (y < h - 1) visit(index + w);
      }
      if (region.touchesEdge) {
        if (clippedRegion == null || region.area > clippedRegion.area) clippedRegion = region;
      } else if (page == null || region.area > page.area) {
        page = region;
      }
    }
    final viewArea = n.toDouble();
    // A bright region round most of the frame's edge is the background (a
    // white desk), not a page running out of view.
    final borderCells = 2 * (w + h) - 4;
    final clipped = clippedRegion != null && clippedRegion.area >= viewArea * 0.2 &&
        clippedRegion.edgeCells < borderCells * 0.5 &&
        (page == null || clippedRegion.area > page.area);
    if (page == null) return ScanPageSegment(clipped: clipped);
    final share = page.area / viewArea;
    if (share < minimumArea) {
      return ScanPageSegment(clipped: clipped, small: share >= minimumArea * 0.4);
    }
    if (share > maximumArea) return ScanPageSegment(clipped: true);

    // Its corners, as extreme points in a frame where both axes are measured
    // in the view's height, so a slant keeps its right angles.
    final quad = page.corners(w, h, aspect);
    final quadArea = _area(quad);
    if (quadArea <= 0) return ScanPageSegment(clipped: clipped);
    final cellArea = aspect / w / h;
    final fill = page.area * cellArea / quadArea;
    if (fill < minimumFill || fill > 1.12) return ScanPageSegment(clipped: clipped);
    double side(Offset a, Offset b) => (a - b).distance;
    final top = side(quad[0], quad[1]), right = side(quad[1], quad[2]);
    final bottom = side(quad[2], quad[3]), left = side(quad[3], quad[0]);
    if (math.min(top, bottom) < math.max(top, bottom) * minimumSideRatio ||
        math.min(left, right) < math.max(left, right) * minimumSideRatio) {
      return ScanPageSegment(clipped: clipped);
    }
    final ratio = ((top + bottom) / 2) / ((left + right) / 2);
    final shaped = profile?.supportsRatio(ratio) ?? (ratio > 0.4 && ratio < 2.5);
    if (!shaped) return ScanPageSegment(clipped: clipped);
    // Not much smaller than the smallest frame the guide offers.
    if (guides.isNotEmpty) {
      final smallest = guides.map((g) => g.width * g.height * aspect).reduce(math.min);
      if (quadArea < smallest * 0.42) return const ScanPageSegment(small: true);
    }
    // A clear step from the page to the background round it.
    final ring = _ringMean(g, page, background);
    if (ring == null || page.mean - ring < minimumStep) return ScanPageSegment(clipped: clipped);

    final normalized = [
      for (final corner in quad) Offset(corner.dx / aspect, corner.dy),
    ];
    final xs = normalized.map((p) => p.dx), ys = normalized.map((p) => p.dy);
    final bounds = Rect.fromLTRB(
      xs.reduce(math.min).clamp(0.0, 1.0), ys.reduce(math.min).clamp(0.0, 1.0),
      xs.reduce(math.max).clamp(0.0, 1.0), ys.reduce(math.max).clamp(0.0, 1.0),
    );
    // Corners too close to the frame's edge: the page may run out of view.
    if (bounds.left < 0.02 || bounds.top < 0.02 || bounds.right > 0.98 || bounds.bottom > 0.98) {
      return const ScanPageSegment(clipped: true);
    }
    return ScanPageSegment(page: ScanSegmentedPage(bounds: bounds, corners: normalized, fill: fill));
  }

  static double _area(List<Offset> quad) {
    var sum = 0.0;
    for (var i = 0; i < quad.length; i++) {
      final a = quad[i], b = quad[(i + 1) % quad.length];
      sum += a.dx * b.dy - b.dx * a.dy;
    }
    return sum.abs() / 2;
  }

  /// The mean of the background cells within a few cells of the page.
  static double? _ringMean(ScanLumaGrid g, _Region page, Uint8List background) {
    const reach = 3;
    var sum = 0.0, count = 0;
    final x0 = math.max(0, page.minX - reach), x1 = math.min(g.width - 1, page.maxX + reach);
    final y0 = math.max(0, page.minY - reach), y1 = math.min(g.height - 1, page.maxY + reach);
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        final inside = x > page.minX && x < page.maxX && y > page.minY && y < page.maxY;
        if (inside) continue;
        final index = y * g.width + x;
        if (background[index] == 1) {
          sum += g.pixels[index];
          count++;
        }
      }
    }
    return count < 8 ? null : sum / count;
  }
}

class _Region {
  int area = 0;
  double _sum = 0;
  int minX = 1 << 30, maxX = -1, minY = 1 << 30, maxY = -1;
  bool touchesEdge = false;

  /// Cells of the region on the frame's edge.
  int edgeCells = 0;
  // Extreme cells for the four corners (cell coordinates).
  int _tlX = 0, _tlY = 0, _trX = 0, _trY = 0, _brX = 0, _brY = 0, _blX = 0, _blY = 0;
  double _tl = double.infinity, _br = -double.infinity, _tr = -double.infinity, _bl = double.infinity;

  double get mean => area == 0 ? 0 : _sum / area;

  void add(int x, int y, int value, int w, int h, double aspect) {
    area++;
    _sum += value;
    if (x < minX) minX = x;
    if (x > maxX) maxX = x;
    if (y < minY) minY = y;
    if (y > maxY) maxY = y;
    if (x == 0 || y == 0 || x == w - 1 || y == h - 1) {
      touchesEdge = true;
      edgeCells++;
    }
    // Metric: both axes in units of the view's height.
    final mx = (x + 0.5) / w * aspect, my = (y + 0.5) / h;
    final sum = mx + my, difference = mx - my;
    if (sum < _tl) { _tl = sum; _tlX = x; _tlY = y; }
    if (sum > _br) { _br = sum; _brX = x; _brY = y; }
    if (difference > _tr) { _tr = difference; _trX = x; _trY = y; }
    if (difference < _bl) { _bl = difference; _blX = x; _blY = y; }
  }

  /// The corners at the outer edges of the extreme cells, in metric units.
  List<Offset> corners(int w, int h, double aspect) => [
        Offset(_tlX / w * aspect, _tlY / h),
        Offset((_trX + 1) / w * aspect, _trY / h),
        Offset((_brX + 1) / w * aspect, (_brY + 1) / h),
        Offset(_blX / w * aspect, (_blY + 1) / h),
      ];
}
