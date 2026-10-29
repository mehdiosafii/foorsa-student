/// The first three seconds, and one object the whole time. Frame one is the
/// native launch screen exactly (the white roundel on the splash's navy,
/// 256 pt and centred, as LaunchScreen.storyboard draws it). Then the
/// roundel's white opens like an iris and lets go as a ring of light, and the
/// F, left standing on the night, turns from navy to pearl. The F is an arrow
/// pointing up and to the right: its outline flows into an airliner pointing
/// the same way, its two trailing steps becoming the tailplanes. The engines
/// grow under the wings, light runs along the fuselage, the navigation lights
/// come on, and the plane climbs out the way the arrow pointed.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'airliner.dart';
import 'brand_vectors.dart';
import 'shape_morph.dart';
import 'splash_logo.dart';
import 'svg_path.dart';

/// The intro's length, in seconds.
const takeoffSeconds = 3.4;

/// The beats: the F starts to become the plane, is the plane, lights up,
/// leaves.
const morphStarts = 0.85;
const morphEnds = 1.6;
const lightsOn = 1.95;
const climbStarts = 2.42;

double _smooth(double x) {
  final t = x.clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

double _inOut(double x) {
  final t = x.clamp(0.0, 1.0);
  return t < 0.5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3) / 2;
}

double _out(double x) {
  final t = x.clamp(0.0, 1.0);
  return 1 - math.pow(1 - t, 3).toDouble();
}

/// How far the night has come in, at [t] seconds of the intro.
double takeoffNight(double t) => _smooth((t - 1.7) / 1.4);

/// The roundel's disc, in points, at 256 pt.
const _discRadius = 92.0;

/// The F's colour on the white roundel, and on the night.
const _navyInk = Color(0xFF14325A);
const _pearl = Color(0xFFF4F7FB);

/// The F mark, placed exactly over the roundel's raster F: its 721 x 712
/// box at 0.1404 pt a unit, its top left at (-52.25, -52.25) from the centre.
final Matrix4 _markPlacement = Matrix4.identity()
  ..translateByDouble(-52.25, -52.25, 0, 1)
  ..scaleByDouble(0.140425, 0.140425, 1, 1)
  ..translateByDouble(-18, -22, 0, 1);

/// The plane at rest: 168 pt, centred, pointing up and to the right.
const _planeSide = 168.0;
Matrix4 _planePose(Offset at, double heading, double scale) =>
    Matrix4.identity()
      ..translateByDouble(at.dx, at.dy, 0, 1)
      ..rotateZ(heading + math.pi / 2)
      ..scaleByDouble(_planeSide / 180 * scale, _planeSide / 180 * scale, 1, 1)
      ..translateByDouble(-90, -90, 0, 1);

const _restHeading = -math.pi / 4;

class _Morph {
  _Morph(this.from, this.to, this.fromPath, this.toPath);
  final List<Offset> from;
  final List<Offset> to;
  final Path fromPath;
  final Path toPath;

  Path at(double t) => t <= 0
      ? fromPath
      : t >= 1
          ? toPath
          : lerpOutline(from, to, t);
}

/// The F's three pieces flowing into the plane's three: the arrow into the
/// fuselage and wings, each step into the tailplane nearest it.
final List<_Morph> _morphs = () {
  final mark = svgPath(foorsaMarkPath);
  final pieces = [
    for (final m in mark.computeMetrics())
      m.extractPath(0, m.length).transform(_markPlacement.storage),
  ]..sort((a, b) => b
      .computeMetrics()
      .first
      .length
      .compareTo(a.computeMetrics().first.length));
  final pose = _planePose(Offset.zero, _restHeading, 1).storage;
  final body = PlaneShape.body.transform(pose);
  final tails = [
    PlaneShape.tailLeft.transform(pose),
    PlaneShape.tailRight.transform(pose),
  ];
  final steps = pieces.sublist(1);
  // Whichever pairing moves the steps the least.
  double d(Path a, Path b) =>
      (a.getBounds().center - b.getBounds().center).distance;
  final straight = d(steps[0], tails[0]) + d(steps[1], tails[1]);
  final crossed = d(steps[0], tails[1]) + d(steps[1], tails[0]);
  final pairs = straight <= crossed
      ? [(steps[0], tails[0]), (steps[1], tails[1])]
      : [(steps[0], tails[1]), (steps[1], tails[0])];
  _Morph morph(Path a, Path b, int count) {
    final from = outlineOf(a, count: count);
    return _Morph(from, alignTo(from, outlineOf(b, count: count)), a, b);
  }

  return [
    morph(pieces[0], body, 360),
    for (final (a, b) in pairs) morph(a, b, 140),
  ];
}();

class TakeoffIntro extends StatefulWidget {
  const TakeoffIntro({super.key, required this.time, this.splash});

  /// Seconds into the intro, 0 to [takeoffSeconds].
  final Animation<double> time;

  /// The roundel decoded before the first frame (splash_logo.dart).
  final ui.Image? splash;

  @override
  State<TakeoffIntro> createState() => _TakeoffIntroState();
}

class _TakeoffIntroState extends State<TakeoffIntro> {
  ui.Image? _roundel;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void initState() {
    super.initState();
    _roundel = widget.splash;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_roundel != null || _stream != null) return;
    // Decoded here only when main.dart could not do it first.
    _stream = const AssetImage(splashLogoAsset)
        .resolve(createLocalImageConfiguration(context));
    _listener = ImageStreamListener((info, _) {
      if (mounted) setState(() => _roundel = info.image);
    });
    _stream!.addListener(_listener!);
  }

  @override
  void dispose() {
    if (_listener != null) _stream?.removeListener(_listener!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _TakeoffPainter(widget.time, _roundel),
        ),
      ),
    );
  }
}

class _TakeoffPainter extends CustomPainter {
  _TakeoffPainter(this.time, this.roundel) : super(repaint: time);
  final Animation<double> time;
  final ui.Image? roundel;

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    final centre = size.center(Offset.zero);
    canvas.save();
    canvas.translate(centre.dx, centre.dy);

    // The roundel's white opens from the middle like an iris.
    final iris = _inOut((t - 0.3) / 0.5);
    final hole = iris * (_discRadius + 2);
    if (iris < 1) _roundelWithHole(canvas, hole);

    // What is left of its rim lets go as a ring of light.
    final ring = ((t - 0.72) / 0.85).clamp(0.0, 1.0);
    if (ring > 0 && ring < 1) {
      final r = _discRadius + 120 * _out(ring);
      canvas.drawCircle(
          Offset.zero,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6 * (1 - ring) + 0.3
            ..color = Color.fromRGBO(236, 244, 252, 0.6 * (1 - ring)));
    }

    final morph = _inOut((t - morphStarts) / (morphEnds - morphStarts));
    final settle = _smooth((t - morphEnds) / 0.38);
    final lights = _smooth((t - lightsOn) / 0.12);

    // The plane's place: at rest, then a breath back before it goes, then
    // up and away the way the arrow points.
    final (at, heading, scale, flown) = _flight(t, size);

    if (morph <= 0) {
      // The F turns pearl exactly where the iris has opened, and stays the
      // roundel's own navy F everywhere else.
      if (iris > 0) {
        _glow(canvas, 0.5 * _smooth(iris / 0.6), 70);
        canvas.save();
        canvas.clipPath(Path()
          ..addOval(Rect.fromCircle(center: Offset.zero, radius: hole)));
        for (final m in _morphs) {
          canvas.drawPath(m.fromPath, Paint()..color = _pearl);
        }
        canvas.restore();
      }
    } else if (morph < 1) {
      _glow(canvas, 0.5 - 0.15 * morph, 70 + 20 * morph);
      // The plane's own light, so nothing changes when the outline becomes
      // the plane; flat pearl at first, as the F was.
      final pose = _planePose(Offset.zero, _restHeading, 1);
      final paint = Paint()
        ..shader = ui.Gradient.linear(
          MatrixUtils.transformPoint(pose, Offset.zero),
          MatrixUtils.transformPoint(pose, const Offset(180, 180)),
          [
            Color.lerp(_pearl, const Color(0xFFFFFFFF), morph)!,
            Color.lerp(_pearl, const Color(0xFFE8EFF6), morph)!,
            Color.lerp(_pearl, const Color(0xFFBACADA), morph)!,
          ],
          const [0, 0.5, 1],
        );
      // The steps follow the arrow a beat behind, so it reads as one motion.
      final steps =
          _inOut((t - morphStarts - 0.12) / (morphEnds - morphStarts - 0.12));
      // Mid-change it glows and softens, as if made of light for a moment.
      final change = math.sin(math.pi * morph);
      final outlines = [
        for (var i = 0; i < _morphs.length; i++)
          _morphs[i].at(i == 0 ? morph : steps),
      ];
      if (change > 0.02) {
        final bloom = Paint()
          ..color = Color.fromRGBO(200, 225, 250, 0.42 * change)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 12 * change);
        for (final o in outlines) {
          canvas.drawPath(o, bloom);
        }
        paint.maskFilter = MaskFilter.blur(BlurStyle.normal, 1.1 * change);
      }
      for (final o in outlines) {
        canvas.drawPath(o, paint);
      }
    } else {
      // The trails first, under the plane.
      if (flown > 0) _contrails(canvas, t, size);
      canvas.save();
      canvas.transform(_planePose(at, heading, scale).storage);
      _glowLocal(canvas, 0.35 * (1 - flown));
      paintPearlPlane(canvas,
          detail: settle, lights: lights, clock: t - lightsOn);
      _sweep(canvas, t);
      canvas.restore();
    }
    canvas.restore();
  }

  void _roundelWithHole(Canvas canvas, double hole) {
    final disc =
        Rect.fromCircle(center: Offset.zero, radius: splashLogoSide / 2);
    canvas.save();
    if (hole > 0) {
      canvas.clipPath(Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(disc.inflate(4))
        ..addOval(Rect.fromCircle(center: Offset.zero, radius: hole)));
    }
    final image = roundel;
    if (image != null) {
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        disc,
        Paint()..filterQuality = FilterQuality.medium,
      );
    } else {
      // Until the asset arrives: the disc, its rim and the F, drawn.
      canvas.drawCircle(
          Offset.zero, _discRadius, Paint()..color = const Color(0xFFFAFBFD));
      canvas.drawCircle(
          Offset.zero,
          _discRadius * 0.94,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2
            ..color = _navyInk);
    }
    canvas.restore();
  }

  /// A soft pool of light behind the mark as it turns pearl.
  void _glow(Canvas canvas, double strength, double radius) {
    if (strength <= 0) return;
    canvas.drawCircle(
        Offset.zero,
        radius,
        Paint()
          ..shader = ui.Gradient.radial(Offset.zero, radius, [
            Color.fromRGBO(170, 205, 240, 0.32 * strength),
            const Color.fromRGBO(170, 205, 240, 0),
          ]));
  }

  void _glowLocal(Canvas canvas, double strength) {
    if (strength <= 0) return;
    canvas.drawCircle(
        const Offset(90, 90),
        96,
        Paint()
          ..shader = ui.Gradient.radial(const Offset(90, 90), 96, [
            Color.fromRGBO(170, 205, 240, 0.3 * strength),
            const Color.fromRGBO(170, 205, 240, 0),
          ]));
  }

  /// Light running along the fuselage, tail to nose, as the plane settles.
  void _sweep(Canvas canvas, double t) {
    final s = ((t - 1.66) / 0.46).clamp(0.0, 1.0);
    if (s <= 0 || s >= 1) return;
    final y = ui.lerpDouble(190, -10, Curves.easeInOut.transform(s))!;
    canvas.save();
    canvas.clipPath(PlaneShape.body);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 180, 180),
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.linear(Offset(0, y + 26), Offset(0, y - 26), [
          const Color(0x00FFFFFF),
          const Color(0x52FFFFFF),
          const Color(0x00FFFFFF),
        ], const [
          0,
          0.5,
          1
        ]),
    );
    canvas.restore();
  }

  /// Where the plane is at [t]: its place, heading, scale (smaller as it
  /// climbs away), and how far along its way out it is, 0 to 1.
  (Offset, double, double, double) _flight(double t, Size size) {
    final back = _smooth((t - climbStarts + 0.2) / 0.18) *
        (1 - _smooth((t - climbStarts) / 0.2));
    final rest = Offset(math.cos(_restHeading), math.sin(_restHeading));
    if (t < climbStarts) {
      return (rest * (-5 * back), _restHeading, 1.0, 0.0);
    }
    final u =
        ((t - climbStarts) / (takeoffSeconds - climbStarts)).clamp(0.0, 1.0);
    // Faster and faster, as a plane leaving does.
    final s = u * u * (0.35 + 0.65 * u);
    final (point, tangent) = _path(s, size);
    final heading = math.atan2(tangent.dy, tangent.dx);
    return (point, heading, 1 - 0.5 * s, s);
  }

  /// The way out: up and to the right, bending a little steeper towards the
  /// screen's top corner.
  (Offset, Offset) _path(double s, Size size) {
    const p0 = Offset.zero;
    final p1 = Offset(math.cos(_restHeading), math.sin(_restHeading)) * 180;
    final p2 = Offset(size.width / 2 + 190, -size.height / 2 - 190);
    final u = 1 - s;
    final point = p0 * (u * u) + p1 * (2 * u * s) + p2 * (s * s);
    final tangent = (p1 - p0) * (2 * u) + (p2 - p1) * (2 * s);
    return (point, tangent);
  }

  void _contrails(Canvas canvas, double t, Size size) {
    final u =
        ((t - climbStarts) / (takeoffSeconds - climbStarts)).clamp(0.0, 1.0);
    final s = u * u * (0.35 + 0.65 * u);
    const samples = 28;
    for (final exhaust in PlaneShape.exhausts) {
      final points = <Offset>[];
      for (var i = 0; i <= samples; i++) {
        final si = s * i / samples;
        final (point, tangent) = _path(si, size);
        final pose =
            _planePose(point, math.atan2(tangent.dy, tangent.dx), 1 - 0.5 * si);
        points.add(MatrixUtils.transformPoint(pose, exhaust));
      }
      for (var i = 1; i < points.length; i++) {
        final age = 1 - i / samples;
        final a = (0.5 * (1 - age) * (1 - age * 0.4)).clamp(0.0, 1.0);
        canvas.drawLine(
            points[i - 1],
            points[i],
            Paint()
              ..strokeWidth = 1.2 + 1.6 * age
              ..strokeCap = StrokeCap.round
              ..color = Color.fromRGBO(236, 244, 255, a * (1 - 0.6 * u)));
      }
    }
  }

  @override
  bool shouldRepaint(_TakeoffPainter old) =>
      old.time != time || old.roundel != roundel;
}
