/// The portal's glass, for the onboarding: index.css's `.glass-2` and
/// portal.css's `.portal-tile-pane`, as the portal's dark theme tunes them,
/// and the pearl the arrow is made of. Clear, not frosted: what reads as
/// glass is the edge (a rim that is hot where it faces the light at the
/// upper left and cold where it faces away), the slab's inner wall, the
/// light caught in its bevel, and a shadow in three layers. Nothing here
/// blurs what is behind it: on the night there is nothing a blur would show,
/// and on a phone the portal blurs no control either.
library;

import 'dart:collection';
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
  GlassShape._(this.path, this.bounds, this._grow, {this.isRRect = false});

  factory GlassShape.rrect(RRect shape) => GlassShape._(Path()..addRRect(shape),
      shape.outerRect, (d) => Path()..addRRect(_inflate(shape, d)),
      isRRect: true);

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

  /// A rounded rectangle: its shadows are drawn without a blur pass on every
  /// renderer, so they are never baked ([GlassBake]).
  final bool isRRect;

  Path grown(double d) => d == 0 ? path : _grow(d);
}

/// Android's low-cost glass, for the first-launch onboarding: the glass's
/// blurs, rastered once and drawn as pictures from then on.
///
/// A blur on a rounded rectangle is drawn in one pass by Impeller, Flutter's
/// renderer. A blur on any other shape (the arrow, the plane, and the light
/// inside every piece of glass, which is a frame with a hole in it) is drawn
/// through an offscreen picture and two blur passes, every frame: up to eight
/// of them a frame in the onboarding's scenes, on phones whose GPUs and
/// raster threads are far weaker than an iPhone's. Those blurred fields are
/// soft by nature, so each is drawn once at the size it is shown (at a
/// coarser grid when its blur is wide enough to hide it), and from then on
/// the picture is drawn under the same clips, by the same steps, between the
/// same vector face, wall and rim: what changes is a resampling of fields
/// with no edges. Only glass whose shape and light stay the same is baked;
/// glass that changes as it moves (the touch, an object turning into the
/// arrow) is drawn as before. iOS draws it all as before.
abstract final class GlassBake {
  /// On while the onboarding runs on Android (onboarding_gate.dart).
  static bool get enabled => _enabled;
  static bool _enabled = false;
  static set enabled(bool value) {
    if (value == _enabled) return;
    _enabled = value;
    if (!value) clear();
  }

  static final LinkedHashMap<Object, ui.Image> _images =
      LinkedHashMap<Object, ui.Image>();

  /// Enough for every baked piece of glass of the onboarding at a few sizes
  /// (the arrow grows as it flies); the oldest go first.
  static const _limit = 48;

  /// Lets every picture go.
  static void clear() {
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
  }

  @visibleForTesting
  static int get count => _images.length;

  /// The pixels the pictures held take, together.
  @visibleForTesting
  static int get pixels =>
      _images.values.fold(0, (sum, image) => sum + image.width * image.height);

  /// How many pictures have been made: a picture is made once for a piece of
  /// glass at a size, then drawn again, frame after frame.
  @visibleForTesting
  static int made = 0;

  /// Whether a blur of [sigma] points is wide enough on the screen to be
  /// drawn from a picture: one under a pixel and a half reads as an edge,
  /// and the picture's resampling would soften it (the light along a small
  /// arrow's bevel). Those are drawn as before.
  static bool softEnough(double sigma, double device) => sigma * device >= 1.5;

  /// How many device pixels a point of [canvas] covers: the transform in
  /// its picture, times the screen's.
  static double deviceScale(Canvas canvas) {
    final m = canvas.getTransform();
    final local = math.max(math.sqrt(m[0] * m[0] + m[1] * m[1]),
        math.sqrt(m[4] * m[4] + m[5] * m[5]));
    final screen =
        ui.PlatformDispatcher.instance.implicitView?.devicePixelRatio ?? 1;
    return local * screen;
  }

  /// Draws [region] of what [paint] draws (in [canvas]'s own points) from a
  /// picture made the first time. [sigma] is the narrowest blur in it, in the
  /// same points, which sets how coarse its grid may be.
  static void draw(Canvas canvas, Object key,
      {required Rect region,
      required double sigma,
      required double device,
      required void Function(Canvas canvas) paint}) {
    if (region.isEmpty || device <= 0) return;
    // A quarter octave at a time, never coarser than the screen: an arrow
    // that breathes or flies (40 to 84 pt) reuses a handful of pictures, and
    // each is drawn at most a fifth smaller than it was made.
    final bucket = math.pow(2, (math.log(device) / math.ln2 * 4).ceil() / 4)
        as double;
    // Only a wide blur is drawn on a coarser grid, and never below eight
    // pixels of it: a narrow one, drawn coarse and stretched back, comes
    // out a little narrower or wider than it should (Skia approximates a
    // blur with boxes a whole number of pixels wide).
    final coarse = (sigma * bucket / 8).clamp(1.0, 4.0);
    final pixels = bucket / coarse;
    final width = (region.width * pixels).ceil();
    final height = (region.height * pixels).ceil();
    if (width <= 0 || height <= 0 || width > 4096 || height > 4096) {
      paint(canvas);
      return;
    }
    final full = (key, bucket);
    var image = _images.remove(full);
    if (image == null) {
      final recorder = ui.PictureRecorder();
      final c = Canvas(recorder);
      c.scale(pixels);
      c.translate(-region.left, -region.top);
      paint(c);
      final picture = recorder.endRecording();
      image = picture.toImageSync(width, height);
      picture.dispose();
      made++;
      if (_images.length >= _limit) {
        _images.remove(_images.keys.first)?.dispose();
      }
    }
    _images[full] = image;
    canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        Rect.fromLTWH(region.left, region.top, width / pixels, height / pixels),
        _paint);
  }

  static final Paint _paint = Paint()..filterQuality = FilterQuality.low;
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
///
/// [bake] names a shape that stays the same from frame to frame, for
/// [GlassBake]: with it, and the glass at rest (full opacity, unscaled,
/// unpressed), its blurs are drawn from pictures while baking is on.
void paintGlassBody(Canvas canvas, GlassShape shape, Glass glass,
    {double opacity = 1, double scale = 1, double lift = 1, Object? bake}) {
  if (opacity <= 0) return;
  final bounds = shape.bounds;
  if (bounds.isEmpty) return;
  final baked = bake != null &&
      GlassBake.enabled &&
      opacity == 1 &&
      scale == 1 &&
      lift == 1;
  final device = baked ? GlassBake.deviceScale(canvas) : 0.0;

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
    void shadows(Canvas canvas) {
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
    }

    double sigmaOf(GlassShadow s) =>
        s.blur * scale * (0.7 + 0.3 * lift) / 2;
    final sigma =
        baked ? cast.map(sigmaOf).reduce(math.min) : double.infinity;
    if (baked && !shape.isRRect && GlassBake.softEnough(sigma, device)) {
      // Everything the blurs reach, as far as the clip lets them.
      var region = Rect.zero;
      for (final s in cast) {
        final reach = shape
            .grown(s.spread * scale)
            .shift(Offset(s.dx, s.dy * lift) * scale)
            .getBounds()
            .inflate(sigmaOf(s) * 3 + 1);
        region = region.isEmpty ? reach : region.expandToInclude(reach);
      }
      GlassBake.draw(canvas, (bake, glass, 'shadows'),
          region: region.intersect(bounds.inflate(160 * scale)),
          sigma: sigma,
          device: device,
          paint: shadows);
    } else {
      shadows(canvas);
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
  void inset(GlassShadow s, String part) {
    if (s.color.a <= 0.001) return;
    final hole =
        shape.grown(-s.spread * scale).shift(Offset(s.dx, s.dy) * scale);
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(bounds.inflate((40 + s.blur) * scale))
      ..addPath(hole, Offset.zero);
    final paint = Paint()
      ..color = _fade(s.color, opacity)
      ..maskFilter = _blur(s.blur * scale);
    if (baked &&
        paint.maskFilter != null &&
        GlassBake.softEnough(s.blur * scale / 2, device)) {
      // Baked unclipped, a field with no edge in it: the shape's own clip
      // above still cuts it, in vector, every frame.
      GlassBake.draw(canvas, (bake, glass, part),
          region: bounds.inflate(1),
          sigma: s.blur * scale / 2,
          device: device,
          paint: (c) => c.drawPath(path, paint));
    } else {
      canvas.drawPath(path, paint);
    }
  }

  inset(GlassShadow(glass.wall, spread: 1), 'wall');
  inset(glass.highlight, 'highlight');
  inset(glass.glow, 'glow');
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
      paintGlassBody(canvas, shape, glass,
          opacity: opacity, lift: lift, bake: (size, r, circle));
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
