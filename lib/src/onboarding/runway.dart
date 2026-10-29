/// The one control, in the portal's lit glass: a runway with Foorsa's arrow
/// parked at its gate. Pressing it is how the student moves on. The arrow
/// taxis down the runway and lifts off (the page then flies it up into the
/// picture, which folds into it and unfolds as the next one), and the next
/// arrow taxis in to the gate with the next word. Its word says what it does
/// ("Continue", never "Allow"): App Review reads the button by its label.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'boarding_style.dart';
import 'glass.dart';
import 'glass_arrow.dart';
import 'lucide.dart';

const runwayHeight = 60.0;
const _radius = runwayHeight / 2;

/// The arrow's height while it waits at the gate.
const gateArrowHeight = 21.0;

/// Its height as it leaves the runway.
const liftArrowHeight = 24.0;

/// What the arrow on the runway is doing.
enum RunwayPhase {
  /// At the gate, waiting for the student.
  parked,

  /// Rolling down the runway and lifting off ([RunwayState.depart]).
  departing,

  /// Gone: the page is flying it.
  away,

  /// The next arrow rolling in to the gate ([RunwayState.arrive]).
  arriving,
}

/// Where the arrow is, in its runway's coordinates.
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
      height: pose.height,
      opacity: pose.opacity,
      glow: pose.glow,
      lift: lift);
  canvas.restore();
}

/// The gate, where the arrow waits, on a runway [size] wide.
Offset runwayGate(Size size) => Offset(34, size.height / 2);

/// Where the arrow is once it has lifted off: just above the runway's far
/// end, pointing up and to the right.
Offset runwayLiftOff(Size size) => Offset(size.width - 30, -20);

double _clamp01(double x) => x.clamp(0.0, 1.0);
double _smooth(double x) {
  final t = _clamp01(x);
  return t * t * (3 - 2 * t);
}

/// The ground run and the lift-off: a straight roll that bends up into the
/// air at the far end.
(Offset, Offset) _departPath(Size size, double s) {
  final p0 = runwayGate(size);
  final p1 = Offset(size.width * 0.62, size.height / 2);
  final p2 = Offset(size.width - 58, size.height / 2);
  final p3 = runwayLiftOff(size);
  final u = 1 - s;
  final point = p0 * (u * u * u) +
      p1 * (3 * u * u * s) +
      p2 * (3 * u * s * s) +
      p3 * (s * s * s);
  final tangent = (p1 - p0) * (3 * u * u) +
      (p2 - p1) * (6 * u * s) +
      (p3 - p2) * (3 * s * s);
  return (point, tangent);
}

/// How far down the runway the arrow is at [depart] (0 to 1 of the run):
/// slow off the gate, faster and faster.
double departProgress(double depart) {
  final t = _clamp01(depart);
  return t * t * (0.6 + 0.4 * t);
}

/// The arrow on a runway of [size], for its [phase].
ArrowPose? runwayArrow(
  Size size,
  RunwayPhase phase, {
  double depart = 0,
  double arrive = 1,
  double press = 0,
  double clock = 0,
  bool still = false,
}) {
  final gate = runwayGate(size);
  switch (phase) {
    case RunwayPhase.away:
      return null;
    case RunwayPhase.parked:
      // It breathes, and every few seconds it edges forward, keen to go.
      final idle = still ? 0.0 : clock;
      final cycle = idle % 4.6;
      final nudge = still
          ? 0.0
          : math.sin(math.pi * _clamp01((cycle - 3.6) / 0.7)) *
              (1 - _clamp01((cycle - 3.6) / 0.7) * 0.4);
      final breath = still ? 0.5 : 0.5 + 0.5 * math.sin(idle * 2 * math.pi / 3.2);
      return ArrowPose(
        gate + Offset(3.2 * nudge - 2.6 * press, 0),
        0,
        gateArrowHeight * (1 - 0.05 * press),
        glow: 0.34 + 0.16 * breath + 0.4 * press,
      );
    case RunwayPhase.departing:
      final s = departProgress(depart);
      final (point, tangent) = _departPath(size, s);
      // It pitches up with the runway's bend, and leaves pointing the way it
      // will fly.
      final pitch = _smooth((s - 0.62) / 0.38);
      final along = math.atan2(tangent.dy, tangent.dx);
      final heading = ui.lerpDouble(along, -math.pi / 4, pitch * pitch)!;
      return ArrowPose(
        point,
        heading,
        ui.lerpDouble(gateArrowHeight, liftArrowHeight, pitch)!,
        glow: 0.5 + 0.4 * s,
      );
    case RunwayPhase.arriving:
      final a = Curves.easeOutCubic.transform(_clamp01(arrive));
      return ArrowPose(
        Offset(ui.lerpDouble(10, gate.dx, a)!, gate.dy),
        0,
        gateArrowHeight,
        opacity: _smooth(arrive / 0.35),
        glow: 0.34 + 0.3 * (1 - a),
      );
  }
}

/// How present the runway's word is: it leaves ahead of the departing arrow
/// and comes in behind the arriving one. Its offset, and its opacity.
(double, double) runwayWord(RunwayPhase phase,
    {double depart = 0, double arrive = 1}) {
  switch (phase) {
    case RunwayPhase.parked:
      return (0, 1);
    case RunwayPhase.departing:
      final s = departProgress(depart);
      final gone = _smooth((s - 0.06) / 0.34);
      return (16 * gone, 1 - gone);
    case RunwayPhase.away:
      return (16, 0);
    case RunwayPhase.arriving:
      final a = _smooth((arrive - 0.12) / 0.7);
      return (-14 * (1 - a), a);
  }
}

/// The runway, and the student's way forward.
class Runway extends StatelessWidget {
  const Runway({
    super.key,
    required this.label,
    required this.phase,
    required this.depart,
    required this.arrive,
    required this.press,
    required this.clock,
    required this.onPressed,
    this.onDown,
    this.onUp,
    this.done = false,
    this.still = false,
  });

  final String label;
  final RunwayPhase phase;
  final Animation<double> depart;
  final Animation<double> arrive;
  final Animation<double> press;
  final ValueListenable<double> clock;

  /// Null while the plan is loading or the arrow is away.
  final VoidCallback? onPressed;
  final VoidCallback? onDown;
  final VoidCallback? onUp;

  /// The student just turned this on: a check stands where the word was.
  final bool done;
  final bool still;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && phase == RunwayPhase.parked;
    final motion = Listenable.merge([depart, arrive, press, clock]);
    return Semantics(
      button: true,
      enabled: enabled,
      label: done ? '$label, turned on' : label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => onDown?.call() : null,
        onTapUp: enabled ? (_) => onUp?.call() : null,
        onTapCancel: enabled ? () => onUp?.call() : null,
        onTap: enabled ? onPressed : null,
        child: AnimatedBuilder(
          animation: press,
          builder: (context, child) => Transform.scale(
              scale: 1 - 0.025 * press.value.clamp(0.0, 1.0), child: child),
          // The glass paints once (again only under a finger); the arrow and
          // its light, which move every frame, paint on their own layers.
          child: SizedBox(
            height: runwayHeight,
            width: double.infinity,
            child: Stack(fit: StackFit.expand, children: [
              RepaintBoundary(
                  child: CustomPaint(painter: _RunwayBodyPainter(press))),
              RepaintBoundary(
                child: CustomPaint(
                  painter: _RunwayLightPainter(
                      phase: phase,
                      depart: depart,
                      arrive: arrive,
                      press: press,
                      clock: clock,
                      still: still,
                      repaint: motion),
                ),
              ),
              AnimatedBuilder(
                animation: Listenable.merge([depart, arrive]),
                builder: (context, _) {
                  final (shift, presence) = runwayWord(phase,
                      depart: depart.value, arrive: arrive.value);
                  return Stack(alignment: Alignment.center, children: [
                    Transform.translate(
                      offset: Offset(shift, 0),
                      child: Opacity(
                        opacity: presence.clamp(0.0, 1.0),
                        child: AnimatedSwitcher(
                          duration: Duration(milliseconds: still ? 0 : 220),
                          child: Text(
                            label,
                            key: ValueKey(label),
                            maxLines: 1,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.3,
                              color: Boarding.heading,
                            ),
                          ),
                        ),
                      ),
                    ),
                    _Check(shown: done, still: still),
                  ]);
                },
              ),
              RepaintBoundary(
                child: CustomPaint(
                  painter: _RunwayArrowPainter(
                      phase: phase,
                      depart: depart,
                      arrive: arrive,
                      press: press,
                      clock: clock,
                      still: still,
                      repaint: motion),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// A yes, shown on the empty runway while the arrow waits above it.
class _Check extends StatelessWidget {
  const _Check({required this.shown, required this.still});
  final bool shown;
  final bool still;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: shown ? 1 : 0),
      duration: Duration(milliseconds: still ? 0 : (shown ? 420 : 200)),
      curve: shown ? Curves.easeOutBack : Curves.easeIn,
      builder: (context, v, child) => Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform.scale(scale: 0.7 + 0.3 * v, child: child),
      ),
      child: const Lucide(LucideIcons.check,
          size: 24, color: Boarding.heading, strokeWidth: 2.6),
    );
  }
}

abstract class _RunwayPainterBase extends CustomPainter {
  _RunwayPainterBase({
    required this.phase,
    required this.depart,
    required this.arrive,
    required this.press,
    required this.clock,
    required this.still,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final RunwayPhase phase;
  final Animation<double> depart;
  final Animation<double> arrive;
  final Animation<double> press;
  final ValueListenable<double> clock;
  final bool still;

  ArrowPose? arrow(Size size) => runwayArrow(size, phase,
      depart: depart.value,
      arrive: arrive.value,
      press: press.value.clamp(0.0, 1.0),
      clock: clock.value,
      still: still);

  GlassShape shape(Size size) => _runwayShape(size);

  @override
  bool shouldRepaint(_RunwayPainterBase old) =>
      old.phase != phase || old.still != still;
}

GlassShape _runwayShape(Size size) => GlassShape.rrect(
    RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(_radius)));

/// The runway's glass, its shadow falling less while it is pressed.
class _RunwayBodyPainter extends CustomPainter {
  _RunwayBodyPainter(this.press) : super(repaint: press);
  final Animation<double> press;

  @override
  void paint(Canvas canvas, Size size) {
    paintGlassBody(canvas, _runwayShape(size), Glass.tile,
        lift: 1 - 0.4 * press.value.clamp(0.0, 1.0));
  }

  @override
  bool shouldRepaint(_RunwayBodyPainter old) => old.press != press;
}

/// The light the arrow throws on the glass, and the runway's lights.
class _RunwayLightPainter extends _RunwayPainterBase {
  _RunwayLightPainter({
    required super.phase,
    required super.depart,
    required super.arrive,
    required super.press,
    required super.clock,
    required super.still,
    required super.repaint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final glass = shape(size);
    final pose = arrow(size);
    if (pose == null) return;
    canvas.save();
    canvas.clipPath(glass.path);
    // The runway's lights: a streak left behind on the glass as it rolls.
    if (phase == RunwayPhase.departing) {
      final s = departProgress(depart.value);
      final tail = pose.at - Offset(30 + 120 * s, 0);
      final strength = _smooth(s / 0.25) * (1 - _smooth((s - 0.8) / 0.2));
      if (strength > 0.01) {
        canvas.drawRRect(
          RRect.fromLTRBR(tail.dx, size.height / 2 - 1.2, pose.at.dx - 6,
              size.height / 2 + 1.2, const Radius.circular(2)),
          Paint()
            ..shader = ui.Gradient.linear(tail, pose.at, [
              const Color(0x00DDEBFA),
              Color.fromRGBO(221, 235, 250, 0.7 * strength),
            ])
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2),
        );
      }
    }
    // The arrow's own light, pooled on the glass under it.
    final pool = 46.0 * (0.8 + 0.4 * pose.glow);
    canvas.drawCircle(
        pose.at,
        pool,
        Paint()
          ..shader = ui.Gradient.radial(pose.at, pool, [
            Color.fromRGBO(190, 216, 244, 0.16 * pose.opacity * pose.glow),
            const Color.fromRGBO(190, 216, 244, 0),
          ]));
    canvas.restore();
  }
}

class _RunwayArrowPainter extends _RunwayPainterBase {
  _RunwayArrowPainter({
    required super.phase,
    required super.depart,
    required super.arrive,
    required super.press,
    required super.clock,
    required super.still,
    required super.repaint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final glass = shape(size);
    final pose = arrow(size);
    // The glass catches the arrow's light where it passes nearest the rim.
    if (pose != null) {
      paintGlassRim(canvas, glass, Glass.tile);
      paintGlassCatch(canvas, glass, pose.at, 44,
          strength: pose.opacity * (0.35 + 0.5 * pose.glow));
      // Once it has lifted off, the page flies it.
      if (!(phase == RunwayPhase.departing && depart.value >= 1)) {
        paintArrowAt(canvas, pose,
            lift: 1 - 0.4 * press.value.clamp(0.0, 1.0));
      }
    } else {
      paintGlassRim(canvas, glass, Glass.tile);
    }
  }
}
