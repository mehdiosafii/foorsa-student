/// The portal's glass, for the onboarding: index.css's `.glass-2` and
/// portal.css's `.portal-tile-pane`, as the portal's dark theme tunes them,
/// and the pearl the arrow is made of. Clear, not frosted: what reads as
/// glass is the edge (a rim that is hot where it faces the light at the
/// upper left and cold where it faces away), the slab's inner wall, the
/// light caught in its bevel, and a shadow in three layers. Nothing here
/// blurs what is behind it: on the night there is nothing a blur would show,
/// and on a phone the portal blurs no control either.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// One CSS box-shadow, in points: its offset, blur radius and spread.
@immutable
class GlassShadow {
  const GlassShadow(this.color,
      {this.dx = 0, this.dy = 0, this.blur = 0, this.spread = 0});
  final Color color;
  final double dx, dy, blur, spread;

  static const none = GlassShadow(Color(0x00000000));

  static GlassShadow lerp(GlassShadow a, GlassShadow b, double t) =>
      GlassShadow(Color.lerp(a.color, b.color, t)!,
          dx: ui.lerpDouble(a.dx, b.dx, t)!,
          dy: ui.lerpDouble(a.dy, b.dy, t)!,
          blur: ui.lerpDouble(a.blur, b.blur, t)!,
          spread: ui.lerpDouble(a.spread, b.spread, t)!);
}

@immutable
class Glass {
  const Glass({
    required this.fill,
    this.fillAngle = 140,
    required this.rim,
    this.rimWidth = 1,
    this.rimAngle = 145,
    required this.wall,
    required this.highlight,
    required this.glow,
    required this.shadows,
  });

  /// The front face: three stops, at 0, 48 % and 100 % of a CSS gradient
  /// at [fillAngle] degrees.
  final List<Color> fill;
  final double fillAngle;

  /// The cut edge: hot, mid, cold, drawn hot-mid-cold-mid-hot at 145°, so
  /// the upper left and the lower right catch the light.
  final List<Color> rim;
  final double rimWidth;

  /// Where the light falls on the rim, as a CSS gradient angle.
  final double rimAngle;

  /// The slab's thickness: a hairline just inside the edge.
  final Color wall;

  /// Light inside the glass: the edge facing the light, and what the bevel
  /// catches on the far side (CSS inset shadows).
  final GlassShadow highlight;
  final GlassShadow glow;

  /// Outside it: contact, occlusion and ambient shadows.
  final List<GlassShadow> shadows;

  /// `.glass-2` on the portal's dark theme: smoked, for panes the student
  /// reads (a notification, a label).
  static const pane = Glass(
    fill: [Color(0x8C121B24), Color(0x8C121B24), Color(0x8C121B24)],
    rim: [Color(0xF2FFFFFF), Color(0x8AD8E8F8), Color(0x3DA4BCCF)],
    wall: Color(0x21E4EFFA),
    highlight: GlassShadow(Color(0x40FFFFFF), dy: 1),
    glow: GlassShadow(Color(0x7ACDE7FF), dy: -12, blur: 24, spread: -16.8),
    shadows: [
      GlassShadow(Color(0x33000000), dy: 1, blur: 2),
      GlassShadow(Color(0x40000000), dy: 8, blur: 16, spread: -8),
      GlassShadow(Color(0x59000000), dy: 26, blur: 56, spread: -14),
    ],
  );

  /// `.portal-tile-pane` on the portal's dark theme: glass lit from inside,
  /// for what the student presses (the portal's home tiles).
  static const tile = Glass(
    fill: [Color(0x40D0DAE2), Color(0x451C252E), Color(0x2E617484)],
    rim: [Color(0xF2FFFFFF), Color(0x99D2E0F1), Color(0x40B1C5D8)],
    wall: Color(0x2EF0F8FF),
    highlight: GlassShadow(Color(0x5CFFFFFF), dx: 1, dy: 2, blur: 3),
    glow: GlassShadow(Color(0x99DAF0FF), dx: -2, dy: -3, blur: 7),
    shadows: [
      GlassShadow.none,
      GlassShadow.none,
      GlassShadow(Color(0x59000000), dy: 9, blur: 22, spread: -7),
    ],
  );

  /// The arrow: a solid piece of pearl glass, lit from the upper left, at a
  /// reference height of 100 pt (paint it with `scale: height / 100`).
  static const pearl = Glass(
    fill: [Color(0xFFFFFFFF), Color(0xFFEBF1F7), Color(0xFFBCCAD9)],
    fillAngle: 145,
    rim: [Color(0xFFFFFFFF), Color(0x80FFFFFF), Color(0x26FFFFFF)],
    rimWidth: 1.4,
    wall: Color(0x00FFFFFF),
    highlight: GlassShadow(Color(0xF2FFFFFF), dx: 1.2, dy: 1.8, blur: 2),
    glow: GlassShadow(Color(0x4D3E5874), dx: -1.6, dy: -2.4, blur: 4.5),
    shadows: [
      GlassShadow(Color(0x47020817), dy: 3, blur: 6),
      GlassShadow.none,
      GlassShadow(Color(0x61020817), dy: 16, blur: 34),
    ],
  );

  /// A flat colour as a "glass" (no edge, no light), so a paper object can
  /// turn into glass and back by [lerp].
  static Glass solid(Color color) {
    final clear = color.withValues(alpha: 0);
    return Glass(
      fill: [color, color, color],
      rim: [clear, clear, clear],
      wall: clear,
      highlight: const GlassShadow(Color(0x00FFFFFF)),
      glow: const GlassShadow(Color(0x00FFFFFF)),
      shadows: const [GlassShadow.none, GlassShadow.none, GlassShadow.none],
    );
  }

  /// The same glass seen turned by [degrees] (its light turns with it).
  Glass turned(double degrees) => Glass(
        fill: fill,
        fillAngle: fillAngle + degrees,
        rim: rim,
        rimWidth: rimWidth,
        rimAngle: rimAngle + degrees,
        wall: wall,
        highlight: highlight,
        glow: glow,
        shadows: shadows,
      );

  static Glass lerp(Glass a, Glass b, double t) {
    if (t <= 0) return a;
    if (t >= 1) return b;
    return Glass(
      fill: [
        for (var i = 0; i < 3; i++) Color.lerp(a.fill[i], b.fill[i], t)!,
      ],
      fillAngle: ui.lerpDouble(a.fillAngle, b.fillAngle, t)!,
      rim: [for (var i = 0; i < 3; i++) Color.lerp(a.rim[i], b.rim[i], t)!],
      rimWidth: ui.lerpDouble(a.rimWidth, b.rimWidth, t)!,
      rimAngle: ui.lerpDouble(a.rimAngle, b.rimAngle, t)!,
      wall: Color.lerp(a.wall, b.wall, t)!,
      highlight: GlassShadow.lerp(a.highlight, b.highlight, t),
      glow: GlassShadow.lerp(a.glow, b.glow, t),
      shadows: [
        for (var i = 0; i < 3; i++)
          GlassShadow.lerp(a.shadows[i], b.shadows[i], t),
      ],
    );
  }
}

/// A shape glass can be drawn on, and the same shape grown or shrunk by a
/// distance (a CSS shadow's spread).
class GlassShape {
  GlassShape._(this.path, this.bounds, this._grow);

  factory GlassShape.rrect(RRect shape) => GlassShape._(Path()..addRRect(shape),
      shape.outerRect, (d) => Path()..addRRect(_inflate(shape, d)));

  /// Any path; a spread is ignored.
  factory GlassShape.path(Path path) =>
      GlassShape._(path, path.getBounds(), (_) => path);

  /// [path], and how it grows by a distance.
  factory GlassShape.withGrow(Path path, Path Function(double d) grow) =>
      GlassShape._(path, path.getBounds(), grow);

  /// A closed outline, clockwise (shape_morph.dart), grown along its normals.
  factory GlassShape.outline(List<Offset> points) {
    final path = _polygon(points);
    return GlassShape._(
        path, path.getBounds(), (d) => _polygon(offsetOutline(points, d)));
  }

  final Path path;
  final Rect bounds;
  final Path Function(double) _grow;

  Path grown(double d) => d == 0 ? path : _grow(d);
}

RRect _inflate(RRect r, double d) {
  Radius grow(Radius x) =>
      Radius.elliptical(math.max(0, x.x + d), math.max(0, x.y + d));
  final rect = r.outerRect.inflate(d);
  if (rect.width <= 0 || rect.height <= 0) {
    return RRect.fromRectAndRadius(
        Rect.fromCenter(center: r.center, width: 0, height: 0), Radius.zero);
  }
  return RRect.fromRectAndCorners(rect,
      topLeft: grow(r.tlRadius),
      topRight: grow(r.trRadius),
      bottomLeft: grow(r.blRadius),
      bottomRight: grow(r.brRadius));
}

Path _polygon(List<Offset> points) => Path()..addPolygon(points, true);

/// [points] (a closed clockwise outline) moved [d] outwards along their
/// normals; inwards when [d] is negative.
List<Offset> offsetOutline(List<Offset> points, double d) {
  final n = points.length;
  return [
    for (var i = 0; i < n; i++)
      () {
        final a = points[(i - 1 + n) % n], b = points[(i + 1) % n];
        final t = b - a;
        final len = t.distance;
        if (len == 0) return points[i];
        // Clockwise on screen (y down): the outward normal is (dy, -dx) of
        // the direction of travel.
        return points[i] + Offset(t.dy, -t.dx) / len * d;
      }(),
  ];
}

/// The line CSS draws a `linear-gradient(<degrees>deg, …)` along in [rect].
(Offset, Offset) cssGradientLine(Rect rect, double degrees) {
  final a = degrees * math.pi / 180;
  final dir = Offset(math.sin(a), -math.cos(a));
  final half =
      (rect.width * math.sin(a).abs() + rect.height * math.cos(a).abs()) / 2;
  return (rect.center - dir * half, rect.center + dir * half);
}

Color _fade(Color c, double opacity) =>
    opacity >= 1 ? c : c.withValues(alpha: c.a * opacity);

MaskFilter? _blur(double radius) => radius > 0.05
    // A CSS blur radius is two standard deviations.
    ? MaskFilter.blur(BlurStyle.normal, radius / 2)
    : null;

/// The glass under its content: shadows (outside it only, as CSS draws
/// them), the face, the inner wall and the light inside. [scale] multiplies
/// every distance; [lift] how far the shadows fall (0.6 while pressed).
void paintGlassBody(Canvas canvas, GlassShape shape, Glass glass,
    {double opacity = 1, double scale = 1, double lift = 1}) {
  if (opacity <= 0) return;
  final bounds = shape.bounds;
  if (bounds.isEmpty) return;

  final cast = [
    for (final s in glass.shadows)
      if (s.color.a > 0.001) s
  ];
  if (cast.isNotEmpty) {
    canvas.save();
    canvas.clipPath(Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(bounds.inflate(160 * scale))
      ..addPath(shape.path, Offset.zero));
    for (final s in cast) {
      final paint = Paint()
        ..color = _fade(s.color, opacity)
        ..maskFilter = _blur(s.blur * scale * (0.7 + 0.3 * lift));
      canvas.drawPath(
          shape
              .grown(s.spread * scale)
              .shift(Offset(s.dx, s.dy * lift) * scale),
          paint);
    }
    canvas.restore();
  }

  final (from, to) = cssGradientLine(bounds, glass.fillAngle);
  canvas.drawPath(
      shape.path,
      Paint()
        ..shader = ui.Gradient.linear(
            from,
            to,
            [for (final c in glass.fill) _fade(c, opacity)],
            const [0, .48, 1]));

  canvas.save();
  canvas.clipPath(shape.path);
  void inset(GlassShadow s) {
    if (s.color.a <= 0.001) return;
    final hole =
        shape.grown(-s.spread * scale).shift(Offset(s.dx, s.dy) * scale);
    canvas.drawPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(bounds.inflate((40 + s.blur) * scale))
          ..addPath(hole, Offset.zero),
        Paint()
          ..color = _fade(s.color, opacity)
          ..maskFilter = _blur(s.blur * scale));
  }

  inset(GlassShadow(glass.wall, spread: 1));
  inset(glass.highlight);
  inset(glass.glow);
  canvas.restore();
}

/// The glass's rim, over its content: a hairline inside the edge whose
/// brightness follows the light round the shape.
void paintGlassRim(Canvas canvas, GlassShape shape, Glass glass,
    {double opacity = 1, double scale = 1}) {
  if (opacity <= 0 || shape.bounds.isEmpty) return;
  if (glass.rim.every((c) => c.a <= 0.001)) return;
  final (from, to) = cssGradientLine(shape.bounds, glass.rimAngle);
  final hot = _fade(glass.rim[0], opacity),
      mid = _fade(glass.rim[1], opacity),
      cold = _fade(glass.rim[2], opacity);
  canvas.save();
  canvas.clipPath(shape.path);
  canvas.drawPath(
      shape.path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = glass.rimWidth * scale * 2
        ..shader = ui.Gradient.linear(
            from, to, [hot, mid, cold, mid, hot], const [0, .22, .48, .74, 1]));
  canvas.restore();
}

/// A light inside the glass near [at], as when something bright passes
/// behind the rim: the rim glows where it is closest.
void paintGlassCatch(Canvas canvas, GlassShape shape, Offset at, double radius,
    {double strength = 1, Color color = const Color(0xFFEAF4FF)}) {
  if (strength <= 0.01) return;
  canvas.save();
  canvas.clipPath(shape.path);
  canvas.drawPath(
      shape.path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.radial(at, radius, [
          color.withValues(alpha: 0.75 * strength.clamp(0.0, 1.0)),
          color.withValues(alpha: 0),
        ]));
  canvas.restore();
}

/// A widget on glass: [glass] under [child], its rim over it.
class GlassPane extends StatelessWidget {
  const GlassPane({
    super.key,
    this.glass = Glass.pane,
    this.radius = 26,
    this.circle = false,
    this.opacity = 1,
    this.lift = 1,
    this.child,
  });

  final Glass glass;
  final double radius;

  /// A disc, whatever its box.
  final bool circle;
  final double opacity;
  final double lift;
  final Widget? child;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter:
            _GlassPainter(glass, radius, circle, opacity, lift, rim: false),
        foregroundPainter:
            _GlassPainter(glass, radius, circle, opacity, lift, rim: true),
        child: child,
      );
}

class _GlassPainter extends CustomPainter {
  _GlassPainter(this.glass, this.radius, this.circle, this.opacity, this.lift,
      {required this.rim});
  final Glass glass;
  final double radius;
  final bool circle;
  final double opacity;
  final double lift;
  final bool rim;

  @override
  void paint(Canvas canvas, Size size) {
    final r = circle
        ? size.shortestSide / 2
        : math.min(radius, size.shortestSide / 2);
    final shape = GlassShape.rrect(circle
        ? RRect.fromRectAndRadius(
            Rect.fromCircle(
                center: size.center(Offset.zero),
                radius: size.shortestSide / 2),
            Radius.circular(r))
        : RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(r)));
    if (rim) {
      paintGlassRim(canvas, shape, glass, opacity: opacity);
    } else {
      paintGlassBody(canvas, shape, glass, opacity: opacity, lift: lift);
    }
  }

  @override
  bool shouldRepaint(_GlassPainter old) =>
      old.glass != glass ||
      old.radius != radius ||
      old.circle != circle ||
      old.opacity != opacity ||
      old.lift != lift ||
      old.rim != rim;
}
