/// The arrow's flights into the picture: from where the student threw it
/// (the welcome) or tapped it (the map's arrow), it banks round in one swoop
/// and arrives in the middle of the stage the size and the way round the
/// stage's own arrow is (stage_morph.dart), docking into the arrow-shaped
/// light the picture has folded into. A light trail follows it.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'glass_arrow.dart';

/// Where the arrow is, in the coordinates of whoever paints it.
@immutable
class ArrowPose {
  const ArrowPose(this.at, this.heading, this.height,
      {this.opacity = 1, this.glow = 0});

  final Offset at;

  /// The way it points: 0 is right, -π/4 its own up and to the right.
  final double heading;
  final double height;
  final double opacity;
  final double glow;

  /// The canvas turn that points the arrow (drawn up and to the right) along
  /// [heading].
  double get turn => heading + math.pi / 4;

  ArrowPose shift(Offset by) =>
      ArrowPose(at + by, heading, height, opacity: opacity, glow: glow);
}

/// Draws the glass arrow at [pose].
void paintArrowAt(Canvas canvas, ArrowPose pose, {double lift = 1}) {
  if (pose.opacity <= 0) return;
  canvas.save();
  canvas.translate(pose.at.dx, pose.at.dy);
  canvas.rotate(pose.turn);
  paintGlassArrow(canvas,
      height: pose.height, opacity: pose.opacity, glow: pose.glow, lift: lift);
  canvas.restore();
}

/// The way the stage's arrow points.
const restHeading = -math.pi / 4;

/// The stage's arrow's height (stage_morph.dart), which a flight arrives at.
const stageArrowHeightForFlight = 84.0;

/// A speed curve that leaves at [v0] (in journeys per journey-time) and
/// arrives at rest: 0 for a start from rest, 2 to carry on from a run.
double launchCurve(double t, double v0) {
  final x = t.clamp(0.0, 1.0);
  return v0 * x + (3 - 2 * v0) * x * x + (v0 - 2) * x * x * x;
}

/// One swoop, in the coordinates of whoever paints it.
class Swoop {
  /// [launch] is the way it climbs away and [approach] the way it comes in
  /// (unit vectors; the headings it leaves and arrives with by default). The
  /// arrow turns from [fromHeading] onto its path as it goes, and onto
  /// [toHeading] as it arrives.
  Swoop({
    required this.from,
    required this.fromHeading,
    required this.fromHeight,
    required this.to,
    required this.toHeight,
    this.toHeading = restHeading,
    this.speed = 0,
    this.follow = true,
    Offset? launch,
    Offset? approach,
    double launchReach = 0.25,
    double approachReach = 0.32,
  }) {
    final reach = (to - from).distance;
    final out = launch ?? Offset(math.cos(fromHeading), math.sin(fromHeading));
    final into = approach ?? Offset(math.cos(toHeading), math.sin(toHeading));
    _p1 = from + out / out.distance * (reach * launchReach);
    _p2 = to - into / into.distance * (reach * approachReach);
  }

  /// Up and round into the stage from below: one arc, and the arrow rights
  /// itself as it docks.
  factory Swoop.intoStage({
    required Offset from,
    required double fromHeading,
    required double fromHeight,
    required Offset to,
    double speed = 0,
  }) =>
      Swoop(
        from: from,
        fromHeading: fromHeading,
        fromHeight: fromHeight,
        to: to,
        toHeight: stageArrowHeightForFlight,
        speed: speed,
        launch: const Offset(0, -1),
        approach: const Offset(0, -1),
      );

  final Offset from;
  final double fromHeading;
  final double fromHeight;
  final Offset to;
  final double toHeight;
  final double toHeading;

  /// How fast it is already going as the swoop starts (see [launchCurve]).
  final double speed;

  /// It points the way it flies, and banks as it turns. Otherwise it glides,
  /// turning only from [fromHeading] to [toHeading], level: for a short hop
  /// whose way would turn it round.
  final bool follow;

  late final Offset _p1, _p2;

  (Offset, Offset) _bezier(double s) {
    final u = 1 - s;
    final point = from * (u * u * u) +
        _p1 * (3 * u * u * s) +
        _p2 * (3 * u * s * s) +
        to * (s * s * s);
    final tangent = (_p1 - from) * (3 * u * u) +
        (_p2 - _p1) * (6 * u * s) +
        (to - _p2) * (3 * s * s);
    return (point, tangent);
  }

  double _headingAt(double s) {
    final (_, tangent) = _bezier(s);
    if (tangent.distance < 1e-6) return s < 0.5 ? fromHeading : toHeading;
    return math.atan2(tangent.dy, tangent.dx);
  }

  /// Where it is at [t] (0 to 1 of the swoop's time), and how hard it is
  /// banking (-1 to 1).
  (ArrowPose, double) at(double t,
      {double glowFrom = 0.6, double glowTo = 0.8}) {
    final s = launchCurve(t, speed);
    final (point, _) = _bezier(s);
    final height = ui.lerpDouble(fromHeight, toHeight, _smooth(s))!;
    final glow = ui.lerpDouble(glowFrom, glowTo, s)!;
    if (!follow) {
      final heading = _blendAngle(fromHeading, toHeading, _smooth(s));
      return (ArrowPose(point, heading, height, glow: glow), 0.0);
    }
    var heading = _headingAt(s);
    // Its heading eases in from the one it left with and out to the one it
    // arrives with, so the ends never snap.
    heading = _blendAngle(fromHeading, heading, _smooth(s / 0.16));
    heading = _blendAngle(heading, toHeading, _smooth((s - 0.72) / 0.28));
    // Turning, it banks: the faster the heading changes, the more.
    final ahead = _headingAt(math.min(1, s + 0.02));
    final behind = _headingAt(math.max(0, s - 0.02));
    final turn = _angleBetween(behind, ahead) / 0.04;
    final bank = (turn / 6).clamp(-1.0, 1.0) * math.sin(math.pi * s);
    return (ArrowPose(point, heading, height, glow: glow), bank);
  }

  /// Points behind it, newest first, for its light trail.
  List<Offset> trail(double t, {int count = 14, double length = 0.16}) {
    final s = launchCurve(t, speed);
    return [
      for (var i = 0; i < count; i++)
        _bezier(math.max(0, s - length * i / (count - 1))).$1,
    ];
  }
}

double _smooth(double x) {
  final t = x.clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

double _angleBetween(double a, double b) {
  var d = b - a;
  while (d > math.pi) {
    d -= 2 * math.pi;
  }
  while (d < -math.pi) {
    d += 2 * math.pi;
  }
  return d;
}

double _blendAngle(double a, double b, double t) => a + _angleBetween(a, b) * t;

/// Paints the flying arrow, banked, with its trail.
void paintFlight(Canvas canvas, ArrowPose pose,
    {double bank = 0,
    List<Offset> trail = const [],
    double trailStrength = 1}) {
  if (trail.length > 1 && trailStrength > 0) {
    // The trail leaves from the arrow's tail, not its middle.
    final back = Offset(math.cos(pose.heading), math.sin(pose.heading)) *
        (pose.height * 0.42);
    final points = [pose.at - back, ...trail.skip(1)];
    for (var i = 1; i < points.length; i++) {
      final age = i / (points.length - 1);
      final a = 0.5 * (1 - age) * trailStrength * pose.opacity;
      if (a < 0.01) continue;
      canvas.drawLine(
          points[i - 1],
          points[i],
          Paint()
            ..strokeCap = StrokeCap.round
            ..strokeWidth = math.max(0.6, pose.height * 0.09 * (1 - age))
            ..color = Color.fromRGBO(222, 236, 252, a));
    }
  }
  canvas.save();
  canvas.translate(pose.at.dx, pose.at.dy);
  // Banked, it shows less of itself across the way it flies.
  canvas.rotate(pose.heading);
  canvas.scale(1, 1 - 0.38 * bank.abs());
  canvas.rotate(math.pi / 4);
  final arrow = ArrowPose(Offset.zero, restHeading, pose.height,
      opacity: pose.opacity, glow: pose.glow);
  paintArrowAt(canvas, arrow);
  canvas.restore();
}
