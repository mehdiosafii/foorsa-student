/// The first three seconds, and one object the whole time. Frame one is the
/// native launch screen exactly: Foorsa's arrow alone, in pearl glass, on the
/// splash's navy (the launch image is rendered from the same painter). The
/// arrow catches the light, and its outline flows into an airliner pointing
/// the same way, its two trailing steps becoming the tailplanes. The engines
/// grow under the wings, light runs along the fuselage, the navigation lights
/// come on, and the plane climbs out the way the arrow pointed.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'airliner.dart';
import 'glass.dart';
import 'glass_arrow.dart';
import 'shape_morph.dart';
import 'stage_forms.dart';

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

/// How far the night has come in, at [t] seconds of the intro.
double takeoffNight(double t) => _smooth((t - 1.7) / 1.4);

/// The plane at rest: 168 pt, centred, pointing up and to the right.
const _planeSide = 168.0;

/// Where the plane is drawn: its 180 box placed at [at], turned to
/// [heading], [scale] times its resting size (also the loader's,
/// flight_loader.dart).
Matrix4 takeoffPlanePose(Offset at, double heading, double scale) =>
    _planePose(at, heading, scale);
Matrix4 _planePose(Offset at, double heading, double scale) =>
    Matrix4.identity()
      ..translateByDouble(at.dx, at.dy, 0, 1)
      ..rotateZ(heading + math.pi / 2)
      ..scaleByDouble(_planeSide / 180 * scale, _planeSide / 180 * scale, 1, 1)
      ..translateByDouble(-90, -90, 0, 1);

const _restHeading = -math.pi / 4;

/// The way the arrow points, and the plane at rest: up and to the right.
const takeoffRestHeading = _restHeading;

/// One of the F's pieces flowing into one of the plane's: [from] and [to]
/// are its outlines, point for point, the arrow centred and 100 pt tall and
/// the plane at rest on the same origin.
class TakeoffMorph {
  TakeoffMorph(this.from, this.to, this.fromPath, this.toPath);
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
final List<TakeoffMorph> takeoffMorphs = () {
  // The arrow as the launch screen draws it: centred, 100 pt tall.
  final pieces = arrowPieces(splashArrowHeight);
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
  TakeoffMorph morph(Path a, Path b, int count) {
    final from = outlineOf(a, count: count);
    return TakeoffMorph(from, alignTo(from, outlineOf(b, count: count)), a, b);
  }

  return [
    morph(pieces[0], body, 360),
    for (final (a, b) in pairs) morph(a, b, 140),
  ];
}();

class TakeoffIntro extends StatelessWidget {
  const TakeoffIntro({super.key, required this.time});

  /// Seconds into the intro, 0 to [takeoffSeconds].
  final Animation<double> time;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _TakeoffPainter(time),
        ),
      ),
    );
  }
}

/// The plane's pearl as the screen sees it at rest: the plane is turned 45°
/// to the right of its own box, and its light with it.
final Glass _inFlight = planeGlass.turned(45);

class _TakeoffPainter extends CustomPainter {
  _TakeoffPainter(this.time) : super(repaint: time);
  final Animation<double> time;

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    final centre = size.center(Offset.zero);
    canvas.save();
    canvas.translate(centre.dx, centre.dy);

    // The arrow wakes: a light comes up behind it and runs across it, and it
    // draws a breath.
    final wake = _smooth((t - 0.16) / 0.6);
    final morph = _inOut((t - morphStarts) / (morphEnds - morphStarts));
    final settle = _smooth((t - morphEnds) / 0.38);
    final lights = _smooth((t - lightsOn) / 0.12);

    // The plane's place: at rest, then a breath back before it goes, then
    // up and away the way the arrow points.
    final (at, heading, scale, flown) = _flight(t, size);

    if (morph <= 0) {
      final breath = 1 +
          0.03 * math.sin(math.pi * _smooth((t - 0.2) / (morphStarts - 0.2)));
      canvas.save();
      canvas.scale(breath);
      paintGlassArrow(canvas,
          height: splashArrowHeight, glow: 0.9 * wake, shine: (t - 0.3) / 0.5);
      canvas.restore();
    } else if (morph < 1) {
      paintArrowGlow(canvas, ui.lerpDouble(92, 90, morph)!,
          ui.lerpDouble(0.9, 0.31, morph)!);
      // The steps follow the arrow a beat behind, so it reads as one motion.
      final steps =
          _inOut((t - morphStarts - 0.12) / (morphEnds - morphStarts - 0.12));
      // Mid-change it glows and softens, as if made of light for a moment.
      final change = math.sin(math.pi * morph);
      final outline = Path();
      for (var i = 0; i < takeoffMorphs.length; i++) {
        outline.addPath(takeoffMorphs[i].at(i == 0 ? morph : steps), Offset.zero);
      }
      if (change > 0.02) {
        canvas.drawPath(
            outline,
            Paint()
              ..color = Color.fromRGBO(200, 225, 250, 0.42 * change)
              ..maskFilter = MaskFilter.blur(BlurStyle.normal, 12 * change));
      }
      // One piece of glass the whole way: its light turns with it.
      final glass = Glass.lerp(Glass.pearl, _inFlight, morph);
      final shape = GlassShape.path(outline);
      paintGlassBody(canvas, shape, glass);
      paintGlassRim(canvas, shape, glass);
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
  bool shouldRepaint(_TakeoffPainter old) => old.time != time;
}
