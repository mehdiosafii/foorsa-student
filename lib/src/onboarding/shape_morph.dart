/// One outline flowing into another: both are walked at even steps along
/// their length, turned the same way round and lined up point for point, so
/// the in-between shapes stay whole instead of folding. Used where the F
/// becomes the plane, and where each step's object becomes the arrow and the
/// arrow the next object.
library;

import 'dart:math' as math;
import 'dart:ui';

/// A closed outline as [count] points, clockwise on screen.
List<Offset> outlineOf(Path path, {int count = 320, int contour = -1}) {
  final metrics = path.computeMetrics().toList();
  if (metrics.isEmpty) return List.filled(count, Offset.zero);
  // The longest contour unless one is named: the outline, not a hole.
  final metric = contour >= 0
      ? metrics[contour]
      : metrics.reduce((a, b) => a.length >= b.length ? a : b);
  final points = <Offset>[
    for (var i = 0; i < count; i++)
      metric.getTangentForOffset(metric.length * i / count)!.position,
  ];
  return _clockwise(points);
}

List<Offset> _clockwise(List<Offset> points) {
  var area = 0.0;
  for (var i = 0; i < points.length; i++) {
    final a = points[i], b = points[(i + 1) % points.length];
    area += a.dx * b.dy - b.dx * a.dy;
  }
  // Screen y runs down: a positive sum is clockwise as seen.
  return area >= 0 ? points : points.reversed.toList();
}

/// [to] started at the point that best matches [from]'s first, so every
/// point travels as short a way as it can.
List<Offset> alignTo(List<Offset> from, List<Offset> to) {
  assert(from.length == to.length);
  final n = from.length;
  var best = 0;
  var bestCost = double.infinity;
  // Every eighth start is tried, then the neighbours of the best.
  double cost(int k) {
    var sum = 0.0;
    for (var i = 0; i < n; i += 2) {
      final d = from[i] - to[(i + k) % n];
      sum += d.dx * d.dx + d.dy * d.dy;
    }
    return sum;
  }

  for (var k = 0; k < n; k += 8) {
    final c = cost(k);
    if (c < bestCost) {
      bestCost = c;
      best = k;
    }
  }
  for (var k = best - 8; k <= best + 8; k++) {
    final c = cost(k % n);
    if (c < bestCost) {
      bestCost = c;
      best = k % n;
    }
  }
  return [for (var i = 0; i < n; i++) to[(i + best) % n]];
}

/// The outline between [a] (at 0) and [b] (at 1), already aligned.
Path lerpOutline(List<Offset> a, List<Offset> b, double t) {
  final path = Path();
  for (var i = 0; i < a.length; i++) {
    final p = Offset.lerp(a[i], b[i], t)!;
    if (i == 0) {
      path.moveTo(p.dx, p.dy);
    } else {
      path.lineTo(p.dx, p.dy);
    }
  }
  return path..close();
}

/// The points between [a] (at 0) and [b] (at 1), already aligned.
List<Offset> lerpOutlinePoints(List<Offset> a, List<Offset> b, double t) =>
    [for (var i = 0; i < a.length; i++) Offset.lerp(a[i], b[i], t)!];

/// A rounded rectangle's outline (a circle when the radius is half the
/// side), as a morph end.
Path roundedOutline(Rect rect, double radius) => Path()
  ..addRRect(RRect.fromRectAndRadius(
      rect, Radius.circular(math.min(radius, rect.shortestSide / 2))));
