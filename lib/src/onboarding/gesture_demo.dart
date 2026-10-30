/// What each scene shows the student to do: a touch, made of the portal's
/// glass, doing the scene's own gesture on its object, where the object
/// really is. A tap is the touch coming down, pressing, and a ring going out
/// from the object's edge; a swipe, a drag or a pull is the touch travelling
/// the gesture's way, a trail of light fading behind it. It starts with the
/// object and comes back calmly every few seconds until the student acts
/// (scene_hint.dart's SceneGuide runs it). With Reduce Motion it is a still
/// chevron pointing the way the gesture goes.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'boarding_style.dart';
import 'glass.dart';

/// The gestures the scenes ask for.
enum DemoGesture { tap, swipe, drag, pull }

/// One scene's gesture, in the scene's own points: where the finger goes
/// down (on the object), where it lifts, and, for a tap, the outline its ring
/// grows from.
@immutable
class GestureDemo {
  const GestureDemo._(this.gesture, this.from, this.to, this.target, this.cueAt,
      this.cueAngle, this.cueInk,
      [this.cueShaft = 0]);

  /// A tap on [target], the finger coming down at [at], inside it. With
  /// Reduce Motion a chevron at [cueAt] points at the target: from above it,
  /// pointing down, unless the scene says otherwise.
  factory GestureDemo.tap(Offset at, RRect target,
          {Offset? cueAt, double cueAngle = math.pi / 2, Color? cueInk}) =>
      GestureDemo._(DemoGesture.tap, at, at, target,
          cueAt ?? Offset(target.center.dx, target.top - 18), cueAngle, cueInk);

  /// A swipe, a drag or a pull, from [from] on the object to [to]. With
  /// Reduce Motion a chevron at [cueAt] (halfway, unless the scene says
  /// otherwise) points the same way.
  factory GestureDemo.move(DemoGesture gesture, Offset from, Offset to,
      {Offset? cueAt, Color? cueInk, double cueShaft = 0}) {
    assert(gesture != DemoGesture.tap, 'a tap does not travel');
    return GestureDemo._(
        gesture,
        from,
        to,
        null,
        cueAt ?? Offset.lerp(from, to, 0.5)!,
        (to - from).direction,
        cueInk,
        cueShaft);
  }

  final DemoGesture gesture;

  /// Where the finger goes down, and where it lifts (the same for a tap).
  final Offset from, to;

  /// The tap's object, whose edge its ring grows from.
  final RRect? target;

  /// Reduce Motion: where the still chevron sits, the way it points (0 is
  /// right, π/2 down) and, on paper, its ink.
  final Offset cueAt;
  final double cueAngle;
  final Color? cueInk;

  /// A shaft behind the chevron, this long, makes it an arrow: for a short
  /// way across something, where two chevrons would read as a corner.
  final double cueShaft;

  bool get taps => gesture == DemoGesture.tap;

  /// Seconds the finger travels: a swipe is a flick, a drag carries
  /// something.
  double get travelTime => switch (gesture) {
        DemoGesture.tap => 0,
        DemoGesture.swipe => 0.5,
        DemoGesture.pull => 0.62,
        DemoGesture.drag => 0.9,
      };

  /// One demonstration and the rest after it, in seconds.
  double get period => switch (gesture) {
        DemoGesture.tap => 2.8,
        DemoGesture.swipe => 3.2,
        DemoGesture.pull => 3.4,
        DemoGesture.drag => 3.6,
      };

  @override
  bool operator ==(Object other) =>
      other is GestureDemo &&
      other.gesture == gesture &&
      other.from == from &&
      other.to == to &&
      other.target == target &&
      other.cueAt == cueAt &&
      other.cueAngle == cueAngle &&
      other.cueInk == cueInk &&
      other.cueShaft == cueShaft;

  @override
  int get hashCode =>
      Object.hash(gesture, from, to, target, cueAt, cueAngle, cueInk, cueShaft);
}

/// Where the touch is, one moment into a demonstration.
@immutable
class DemoPose {
  const DemoPose({
    required this.at,
    required this.presence,
    required this.press,
    required this.scale,
    required this.along,
    required this.tail,
    required this.ring,
    required this.response,
  });

  /// No touch on the screen.
  static const none = DemoPose(
      at: Offset.zero,
      presence: 0,
      press: 0,
      scale: 1,
      along: 0,
      tail: 0,
      ring: -1,
      response: 0);

  final Offset at;

  /// 0 to 1: how much of the touch is there.
  final double presence;

  /// 0 to 1: how hard it presses.
  final double press;

  /// Its size: a little larger as it comes down and as it lifts, as a
  /// fingertip nearing the glass.
  final double scale;

  /// How far along its way it is, 0 to 1, and how far the end of its trail.
  final double along, tail;

  /// A tap's ring, 0 to 1 of its going out; below 0 while there is none.
  final double ring;

  /// 0 to 1: how much the object answers the touch (it dips under a tap,
  /// follows a moving touch a little and settles when it lets go).
  final double response;
}

double _ease(double x, double from, double to) {
  final t = ((x - from) / (to - from)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

double _easeOut(double x, double from, double to) {
  final t = ((x - from) / (to - from)).clamp(0.0, 1.0);
  return 1 - math.pow(1 - t, 3).toDouble();
}

/// The touch has come down onto the object, and has pressed it.
const demoDown = 0.28;
const demoPressed = 0.4;

/// When a tap's ring starts going out, and how long it takes.
const demoRingFrom = 0.34;
const demoRingFor = 0.8;

/// When the touch has gone, in seconds into a demonstration of [demo]: after
/// that, the object rests until the next one.
double demoEnds(GestureDemo demo) => demo.taps
    ? math.max(_phases(demo).leaveEnd, demoRingFrom + demoRingFor)
    : _phases(demo).leaveEnd;

class _Phases {
  const _Phases(this.releaseFrom, this.releaseEnd, this.leaveFrom,
      this.leaveEnd, this.settleFrom);
  final double releaseFrom, releaseEnd, leaveFrom, leaveEnd, settleFrom;
}

_Phases _phases(GestureDemo demo) {
  final moveEnd = demoPressed + demo.travelTime;
  switch (demo.gesture) {
    case DemoGesture.tap:
      return const _Phases(0.52, 0.68, 0.7, 1.0, 0.52);
    case DemoGesture.swipe:
      // A flick: it lets go while still moving, and fades as it goes.
      final leaveFrom = demoPressed + demo.travelTime * 0.6;
      return _Phases(moveEnd - 0.08, moveEnd + 0.06, leaveFrom, moveEnd + 0.08,
          moveEnd - 0.04);
    case DemoGesture.drag:
    case DemoGesture.pull:
      // It carries the object there, holds a beat, lets go and lifts.
      final releaseFrom = moveEnd + 0.1;
      return _Phases(releaseFrom, releaseFrom + 0.16, releaseFrom + 0.04,
          releaseFrom + 0.34, releaseFrom);
  }
}

/// The touch [t] seconds into one demonstration of [demo] (0 at its start;
/// nothing after [demoEnds]).
DemoPose demoAt(GestureDemo demo, double t) {
  if (t < 0 || t >= demoEnds(demo)) return DemoPose.none;
  final p = _phases(demo);
  final arrive = _easeOut(t, 0, demoDown);
  final leave = _ease(t, p.leaveFrom, p.leaveEnd);
  final presence = arrive * (1 - leave);
  final press = _ease(t, demoDown, demoPressed) *
      (1 - _ease(t, p.releaseFrom, p.releaseEnd));
  final travel = demo.travelTime;
  final along = demo.taps
      ? 0.0
      : Curves.easeInOutCubic
          .transform(((t - demoPressed) / travel).clamp(0.0, 1.0));
  final tail = demo.taps
      ? 0.0
      : Curves.easeInOutCubic
          .transform(((t - demoPressed - 0.16) / travel).clamp(0.0, 1.0));
  final ring = demo.taps && t >= demoRingFrom && t < demoRingFrom + demoRingFor
      ? (t - demoRingFrom) / demoRingFor
      : -1.0;
  final response = demo.taps
      ? press
      : along * (1 - _ease(t, p.settleFrom, p.settleFrom + 0.42));
  return DemoPose(
    at: Offset.lerp(demo.from, demo.to, along)!,
    presence: presence,
    press: press,
    scale: 1 + 0.16 * (1 - arrive) + 0.12 * leave,
    along: along,
    tail: tail,
    ring: ring,
    response: response,
  );
}

/// The touch's size, at rest: about a fingertip.
const touchRadius = 18.0;

/// The touch: a bead of the portal's glass tinted with its accent, the
/// colour that means "you can press this", clear enough to see the object
/// through and edged enough to read on the night and on the paper of the
/// passport and the pass alike.
const touchGlass = Glass(
  fill: [Color(0xA6F4F8FC), Color(0x80CFE0F2), Color(0x738FB4DA)],
  rim: [Color(0xFFFFFFFF), Color(0xB3D8E8F8), Color(0xA65A7C9E)],
  rimWidth: 1.2,
  wall: Color(0x40FFFFFF),
  highlight: GlassShadow(Color(0x99FFFFFF), dx: 1, dy: 1.5, blur: 2),
  glow: GlassShadow(Color(0x733E5874), dx: -1, dy: -1.5, blur: 4),
  shadows: [
    GlassShadow(Color(0x47020817), dy: 1, blur: 2),
    GlassShadow(Color(0x38020817), dy: 4, blur: 8, spread: -2),
    GlassShadow(Color(0x4D020817), dy: 10, blur: 20, spread: -6),
  ],
);

/// The trail a moving touch leaves, deep enough to show on paper, and a
/// tap's ring.
const _trail = Color(0xFF8FB4DA);
const _ring = Color(0xFFC4DCF2);

/// Where a thumb comes down on a round object of [radius] round [centre]: a
/// little low and to the right of its middle, so what is printed on it
/// stays in sight.
Offset thumbOn(Offset centre, double radius) =>
    centre + Offset(radius * 0.2, radius * 0.24);

/// Paints [pose] of [demo]. [gate] fades the whole touch (it goes the moment
/// the student touches the screen); [emphasis] (0 to 1) makes it larger and
/// brighter once the student has waited a while.
void paintDemo(Canvas canvas, GestureDemo demo, DemoPose pose,
    {double gate = 1, double emphasis = 0}) {
  if (gate <= 0.001) return;
  final e = emphasis.clamp(0.0, 1.0);

  // A tap's ring, going out from the object's edge.
  final target = demo.target;
  if (target != null && pose.ring >= 0 && pose.ring < 1) {
    final k = pose.ring;
    final reach = (20 + 14 * e) * Curves.easeOutCubic.transform(k);
    final alpha = (0.62 + 0.3 * e) * math.pow(1 - k, 1.5) * gate;
    canvas.drawRRect(
        target.inflate(2 + reach),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6 + 0.9 * e
          ..color = _ring.withValues(alpha: alpha.clamp(0.0, 1.0)));
  }

  final presence = pose.presence * gate;
  if (presence <= 0.004) return;
  final radius =
      touchRadius * (1 + 0.22 * e) * pose.scale * (1 - 0.12 * pose.press);

  // The trail behind a moving touch: one soft tail, from the touch's edge
  // back to where it was, thinning and fading as it goes.
  if (!demo.taps && pose.along > pose.tail + 0.002) {
    final end = Offset.lerp(demo.from, demo.to, pose.tail)!;
    final way = pose.at - end;
    final length = way.distance;
    if (length > radius * 0.6) {
      final u = way / length;
      final n = Offset(-u.dy, u.dx) * (radius * 0.86);
      final tail = Path()
        ..moveTo(pose.at.dx + n.dx, pose.at.dy + n.dy)
        ..lineTo(end.dx, end.dy)
        ..lineTo(pose.at.dx - n.dx, pose.at.dy - n.dy)
        ..close();
      canvas.save();
      // Only outside the touch: it is clear glass, and the tail would show
      // through it.
      canvas.clipPath(Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(tail.getBounds().inflate(radius * 2))
        ..addOval(Rect.fromCircle(center: pose.at, radius: radius * 0.97)));
      // A breath of the night under it, which only paper shows, then its
      // light.
      for (final (colour, alpha, blur) in [
        (Boarding.night, 0.2, 3.0),
        (_trail, 0.55 + 0.2 * e, 1.5),
      ]) {
        canvas.drawPath(
            tail,
            Paint()
              ..shader = ui.Gradient.linear(pose.at, end, [
                colour.withValues(alpha: alpha * presence),
                colour.withValues(alpha: 0),
              ])
              ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur));
      }
      canvas.restore();
    }
  }

  // Its light on what it touches.
  canvas.drawCircle(
      pose.at,
      radius * 2.4,
      Paint()
        ..shader = ui.Gradient.radial(pose.at, radius * 2.4, [
          Boarding.accent.withValues(
              alpha: (0.22 + 0.26 * pose.press + 0.12 * e) * presence),
          Boarding.accent.withValues(alpha: 0),
        ]));

  final shape = GlassShape.rrect(RRect.fromRectAndRadius(
      Rect.fromCircle(center: pose.at, radius: radius),
      Radius.circular(radius)));
  // Pressed, it sits down on the object: its shadow tightens.
  final lift = 1 - 0.55 * pose.press;
  paintGlassBody(canvas, shape, touchGlass, opacity: presence, lift: lift);
  paintGlassRim(canvas, shape, touchGlass, opacity: presence);
  // Its edge against the light paper (on the night it is the night).
  canvas.drawCircle(
      pose.at,
      radius + 0.7,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = Boarding.night.withValues(alpha: 0.42 * presence));
}

/// Reduce Motion: two chevrons at [demo]'s cue, pointing the way its gesture
/// goes (at the object, for a tap), drawn in the accent, or in the ink of
/// the paper they lie on.
void paintStillCue(Canvas canvas, GestureDemo demo,
    {double gate = 1, double emphasis = 0}) {
  if (gate <= 0.001) return;
  final e = emphasis.clamp(0.0, 1.0);
  final ink = demo.cueInk ?? Color.lerp(Boarding.accent, Boarding.heading, e)!;
  canvas.save();
  canvas.translate(demo.cueAt.dx, demo.cueAt.dy);
  canvas.rotate(demo.cueAngle);
  final size = 1 + 0.15 * e;
  canvas.scale(size);
  void stroke(Path path, double alpha) {
    if (demo.cueInk == null) {
      // A breath of the night under it, so it stays crisp over anything.
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5.6
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = Boarding.night.withValues(alpha: 0.5 * alpha));
    }
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = ink.withValues(alpha: ink.a * alpha));
  }

  final shaft = demo.cueShaft;
  if (shaft > 0) {
    // An arrow: its shaft, and one sharp head at the front.
    final tip = shaft / 2;
    stroke(
        Path()
          ..moveTo(-shaft / 2, 0)
          ..lineTo(tip, 0)
          ..moveTo(tip - 7.5, -5.5)
          ..lineTo(tip, 0)
          ..lineTo(tip - 7.5, 5.5),
        gate);
  } else {
    for (var i = 0; i < 2; i++) {
      // Sharp, so it reads as a way at any angle and never as a corner;
      // the one nearest where it points is the brighter.
      final x = i == 0 ? 5.0 : -4.0;
      stroke(
          Path()
            ..moveTo(x - 8, -5.5)
            ..lineTo(x + 1.5, 0)
            ..lineTo(x - 8, 5.5),
          (i == 0 ? 1.0 : 0.5) * gate);
    }
  }
  canvas.restore();
}
