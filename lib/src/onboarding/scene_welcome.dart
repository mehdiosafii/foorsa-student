/// The welcome: the departures board, and under it Foorsa's arrow, resting.
/// There is no Get started: the student throws the arrow up into the board
/// (or taps it), and the onboarding begins with its flight.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'arrow_flight.dart';
import 'boarding_style.dart';
import 'scene_departures.dart';
import 'scene_hint.dart';

/// The resting arrow's height.
const launchArrowHeight = 40.0;

/// Where the arrow rests under the board, from the stage's middle.
double launchArrowDrop(Size stage) =>
    (stage.height * 0.3).clamp(70.0, 150.0).toDouble();

/// The way the arrow points as it is drawn up by [drag]: from its own way, up
/// and to the right, round to the way it is pulled, so it leaves aimed.
double launchAim(Offset drag) {
  final lifted = (-drag.dy / 90).clamp(0.0, 1.0);
  if (lifted <= 0) return restHeading;
  var turn = math.atan2(drag.dy, drag.dx) - restHeading;
  while (turn > math.pi) {
    turn -= 2 * math.pi;
  }
  while (turn < -math.pi) {
    turn += 2 * math.pi;
  }
  return restHeading + turn * lifted;
}

class WelcomeScene extends StatelessWidget {
  const WelcomeScene({
    super.key,
    required this.still,
    required this.feel,
    required this.armed,
    required this.hint,
    required this.label,
    required this.onAct,
    this.onFlip,
  });

  final bool still;
  final Feel feel;

  /// The student may act (the takeoff is over, nothing is moving).
  final bool armed;
  final String hint;

  /// What a screen reader calls the arrow.
  final String label;

  /// The arrow is thrown: where it is on the screen and how fast it goes.
  final SceneAct onAct;
  final VoidCallback? onFlip;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final drop = launchArrowDrop(box.biggest);
      return Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(
            child: DeparturesScene(still: still, feel: feel, onFlip: onFlip)),
        // The lower part of the stage is the arrow's: a swipe up anywhere
        // there throws it.
        Positioned(
          left: 0,
          right: 0,
          top: box.maxHeight / 2 + drop - 70,
          height: 140,
          child: LaunchArrow(
            still: still,
            feel: feel,
            armed: armed,
            label: label,
            onAct: onAct,
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: box.maxHeight / 2 + drop + 34,
          child: GestureHint(hint, still: still, shown: armed),
        ),
      ]);
    });
  }
}

/// The arrow, resting, waiting to be thrown up.
class LaunchArrow extends StatefulWidget {
  const LaunchArrow({
    super.key,
    required this.still,
    required this.feel,
    required this.armed,
    required this.label,
    required this.onAct,
  });

  final bool still;
  final Feel feel;
  final bool armed;
  final String label;
  final SceneAct onAct;

  @override
  State<LaunchArrow> createState() => _LaunchArrowState();
}

class _LaunchArrowState extends State<LaunchArrow>
    with TickerProviderStateMixin {
  /// How far the finger has taken it from rest.
  final ValueNotifier<Offset> _drag = ValueNotifier<Offset>(Offset.zero);
  late final AnimationController _back =
      AnimationController.unbounded(vsync: this);
  late final Ticker _ticker;
  final ValueNotifier<double> _clock = ValueNotifier<double>(0);
  double _idleFrom = 0;
  bool _launched = false;
  int _ticks = 0;

  /// How far up it must go, or how fast, to fly.
  static const _throw = 64.0;
  static const _flick = 420.0;

  @override
  void initState() {
    super.initState();
    _ticker =
        createTicker((elapsed) => _clock.value = elapsed.inMicroseconds / 1e6);
    if (!widget.still) _ticker.start();
    _back.addListener(() {
      final from = _backFrom;
      if (from != null) _drag.value = from * _back.value;
    });
  }

  Offset? _backFrom;

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    _drag.dispose();
    _back.dispose();
    super.dispose();
  }

  void _start(DragStartDetails _) {
    if (!widget.armed || _launched) return;
    _back.stop();
    _backFrom = null;
    _ticks = 0;
    widget.feel('press');
  }

  void _move(DragUpdateDetails details) {
    if (!widget.armed || _launched) return;
    final d = _drag.value + details.delta;
    // Up freely, down and sideways only a little: it wants to go up.
    final down = d.dy > 0 ? 24 * (1 - math.exp(-d.dy / 24)) : d.dy;
    final side = 36 * _tanh(d.dx / 90);
    _drag.value = Offset(side, math.max(-260, down));
    final tick = (-_drag.value.dy / 18).floor();
    if (tick > _ticks) {
      _ticks = tick;
      widget.feel('grain', (-_drag.value.dy / _throw).clamp(0.0, 1.0));
    }
  }

  void _end(DragEndDetails details) {
    if (!widget.armed || _launched) return;
    final v = details.velocity.pixelsPerSecond;
    if (-_drag.value.dy > _throw || v.dy < -_flick) {
      _launch(v.dy < -200 ? v : const Offset(0, -900));
    } else {
      _settle(v);
    }
  }

  void _settle(Offset velocity) {
    if (widget.still) {
      _drag.value = Offset.zero;
      return;
    }
    _backFrom = _drag.value;
    _back.value = 1;
    _back.animateWith(
        SpringSimulation(foorsaSpring(damping: 0.62, response: 0.36), 1, 0, 0));
    widget.feel('detent');
  }

  void _tap() {
    if (!widget.armed || _launched) return;
    widget.feel('press');
    _launch(const Offset(0, -900));
  }

  void _launch(Offset velocity) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    setState(() => _launched = true);
    widget.feel('release');
    final at = box.localToGlobal(box.size.center(Offset.zero) + _drag.value);
    widget.onAct(
        arrow:
            ArrowPose(at, launchAim(_drag.value), launchArrowHeight, glow: 0.7),
        velocity: velocity);
  }

  @override
  void didUpdateWidget(LaunchArrow old) {
    super.didUpdateWidget(old);
    if (widget.armed && !old.armed) _idleFrom = _clock.value;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: widget.armed,
      label: widget.label,
      excludeSemantics: true,
      onTap: widget.armed ? _tap : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: _start,
        onVerticalDragUpdate: _move,
        onVerticalDragEnd: _end,
        onTap: _tap,
        child: CustomPaint(
          painter: _LaunchPainter(
            drag: _drag,
            clock: _clock,
            idleFrom: () => _idleFrom,
            launched: _launched,
            still: widget.still,
            armed: widget.armed,
          ),
        ),
      ),
    );
  }
}

class _LaunchPainter extends CustomPainter {
  _LaunchPainter({
    required this.drag,
    required this.clock,
    required this.idleFrom,
    required this.launched,
    required this.still,
    required this.armed,
  }) : super(repaint: Listenable.merge([drag, clock]));

  final ValueNotifier<Offset> drag;
  final ValueNotifier<double> clock;
  final double Function() idleFrom;
  final bool launched;
  final bool still;
  final bool armed;

  @override
  void paint(Canvas canvas, Size size) {
    if (launched) return;
    final t = clock.value;
    final rest = size.center(Offset.zero);
    // It floats, and now and then hops up, as if it could not wait.
    final bob = still ? 0.0 : 2.2 * math.sin(t * 2 * math.pi / 2.6);
    final hop = still || !armed ? 0.0 : idleNudge(t - idleFrom(), after: 1.8);
    final at = rest + drag.value + Offset(0, bob - 14 * hop);
    final lifted = (-drag.value.dy / 120).clamp(0.0, 1.0);

    // The light it throws on the stage under it.
    final pool = 70.0;
    canvas.drawOval(
        Rect.fromCenter(
            center: rest + const Offset(0, 30), width: pool * 2, height: 26),
        Paint()
          ..shader = ui.Gradient.radial(rest + const Offset(0, 30), pool, [
            Color.fromRGBO(172, 206, 240, 0.12 * (1 - lifted)),
            const Color.fromRGBO(172, 206, 240, 0),
          ]));
    // A faint trail under it as it hops or is drawn up.
    final rise = (14 * hop + math.max(0.0, -drag.value.dy)) / 60;
    if (rise > 0.02) {
      final from = at + const Offset(0, 22);
      canvas.drawLine(
          from,
          from + Offset(0, 26 * rise.clamp(0.0, 1.0)),
          Paint()
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round
            ..shader = ui.Gradient.linear(from, from + const Offset(0, 26), [
              Color.fromRGBO(222, 236, 252, 0.5 * rise.clamp(0.0, 1.0)),
              const Color(0x00DEECFC),
            ]));
    }
    paintArrowAt(
        canvas,
        ArrowPose(at, launchAim(drag.value), launchArrowHeight,
            glow: 0.5 + 0.3 * hop + 0.3 * lifted));
  }

  @override
  bool shouldRepaint(_LaunchPainter old) =>
      old.launched != launched || old.still != still || old.armed != armed;
}

double _tanh(double x) {
  final e = math.exp(2 * x.clamp(-20.0, 20.0));
  return (e - 1) / (e + 1);
}
