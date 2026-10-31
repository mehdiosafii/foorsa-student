/// The app's loading sign since 31 Oct 2026 (the owner: "change the loading
/// screen from the dots to the arrow that turns in airplan you did in the
/// loading"): the take-off intro, small and in a loop. Foorsa's arrow catches
/// the light, flows into the airliner pointing the same way, its lights come
/// on, it climbs away the way the arrow pointed, and a new arrow comes up
/// where it was.
///
/// The portal plays the same loop from the same outlines (foorsa-reward
/// src/portal/FlightLoader.tsx, its numbers from
/// scripts/loader_outline/dump_outline_test.dart), so when the app's loader
/// hands over to the web's nothing changes on the screen.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'airliner.dart';
import 'glass.dart';
import 'glass_arrow.dart';
import 'takeoff_intro.dart';

/// One loop, in seconds.
const flightLoaderSeconds = 3.2;

/// The beats of a loop: the shine across the arrow, the arrow becoming the
/// plane, the plane settling and lighting up, the climb away, and the next
/// arrow coming up while the plane leaves.
const _shineStarts = 0.1, _shineEnds = 0.6;
const _morphStarts = 0.7, _morphEnds = 1.35;
const _lightsOn = 1.5;
const _climbStarts = 1.95, _climbEnds = 2.85;
const _returnStarts = 2.55;

/// Under Reduce Motion the arrow becomes the plane and back where it stands,
/// with nothing crossing the screen, at half the pace.
const flightLoaderCalmSeconds = 4.4;

/// The arrow in navy on a light ground, lit from the upper left like the
/// pearl.
const navyGlass = Glass(
  fill: [Color(0xFF2E4E76), Color(0xFF183250), Color(0xFF0E2136)],
  fillAngle: 145,
  rim: [Color(0x73FFFFFF), Color(0x1FFFFFFF), Color(0x00FFFFFF)],
  rimWidth: 1.2,
  wall: Color(0x00FFFFFF),
  highlight: GlassShadow(Color(0x47FFFFFF), dx: 1.2, dy: 1.8, blur: 2),
  glow: GlassShadow(Color(0x00000000)),
  shadows: [
    GlassShadow(Color(0x24020817), dy: 3, blur: 6),
    GlassShadow.none,
    GlassShadow(Color(0x1A020817), dy: 14, blur: 28),
  ],
);

double _smooth(double x) {
  final t = x.clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

double _inOut(double x) {
  final t = x.clamp(0.0, 1.0);
  return t < 0.5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3) / 2;
}

/// The loader: the arrow [size] tall, in a square 2.6 times that so the
/// plane has room to leave. [dark] is the theme's ground: pearl on the night,
/// navy on white.
class FlightLoader extends StatefulWidget {
  const FlightLoader({super.key, this.size = 64, this.dark = true});
  final double size;
  final bool dark;

  /// The square the loader takes, for a given arrow height.
  static double boxFor(double size) => size * 2.6;

  @override
  State<FlightLoader> createState() => _FlightLoaderState();
}

class _FlightLoaderState extends State<FlightLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4400),
  );
  bool? _calm;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final calm = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (calm == _calm) return;
    _calm = calm;
    _clock.duration = Duration(
        milliseconds:
            ((calm ? flightLoaderCalmSeconds : flightLoaderSeconds) * 1000)
                .round());
    _clock.repeat();
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading',
      child: SizedBox.square(
        dimension: FlightLoader.boxFor(widget.size),
        child: RepaintBoundary(
          child: CustomPaint(
            painter: FlightLoaderPainter(
              _clock,
              size: widget.size,
              dark: widget.dark,
              calm: _calm ?? false,
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints the loop at the clock's place (0 to 1 of a loop). Public for the
/// golden test and the frame renders.
class FlightLoaderPainter extends CustomPainter {
  FlightLoaderPainter(this.clock,
      {required this.size, required this.dark, this.calm = false})
      : super(repaint: clock);
  final Animation<double> clock;
  final double size;
  final bool dark;
  final bool calm;

  Glass get _arrowGlass => dark ? Glass.pearl : navyGlass;

  /// The plane's material in its own box, which is turned 45° to the screen.
  Glass get _planeGlass => dark ? planeGlass : navyGlass;

  /// The same light as the screen sees it, for the outline mid-change, which
  /// is drawn on the screen's own axes.
  Glass get _planeGlassOnScreen => _planeGlass.turned(45);

  @override
  void paint(Canvas canvas, Size box) {
    canvas.save();
    canvas.translate(box.width / 2, box.height / 2);
    canvas.scale(size / splashArrowHeight);
    if (calm) {
      _paintCalm(canvas, clock.value * flightLoaderCalmSeconds);
    } else {
      _paintLoop(canvas, clock.value * flightLoaderSeconds);
    }
    canvas.restore();
  }

  void _paintLoop(Canvas canvas, double t) {
    final morph = _inOut((t - _morphStarts) / (_morphEnds - _morphStarts));
    final glow = dark ? 0.75 : 0.0;
    if (t < _morphStarts) {
      paintGlassArrow(canvas,
          height: splashArrowHeight,
          glow: glow,
          shine: (t - _shineStarts) / (_shineEnds - _shineStarts),
          // White light on navy reads as a smudge at full strength.
          shineStrength: dark ? 1 : 0.35,
          glass: _arrowGlass);
      return;
    }
    if (t < _morphEnds) {
      _paintMorph(canvas, t, morph);
      return;
    }
    // The plane: settling, lighting up, then away the way it points.
    final settle = _smooth((t - _morphEnds) / 0.4);
    final lights = _smooth((t - _lightsOn) / 0.12);
    final away = ((t - _climbStarts) / (_climbEnds - _climbStarts)).clamp(0.0, 1.0);
    // Faster and faster, as a plane leaving does.
    final s = away * away * (0.35 + 0.65 * away);
    final dir = Offset(math.cos(takeoffRestHeading), math.sin(takeoffRestHeading));
    // A short climb that bends a little steeper, inside the loader's square.
    final at = dir * (120 * s) + const Offset(0, -26) * (s * s);
    final heading = takeoffRestHeading - 0.18 * s;
    final scale = 1 - 0.45 * s;
    final fade = 1 - _smooth((away - 0.45) / 0.55);
    if (fade > 0) {
      canvas.save();
      canvas.transform(takeoffPlanePose(at, heading, scale).storage);
      paintPearlPlane(canvas,
          detail: settle,
          lights: lights,
          clock: t - _lightsOn,
          opacity: fade,
          glass: _planeGlass,
          onLight: !dark);
      canvas.restore();
    }
    // The next arrow, coming up where the plane left.
    final back = _smooth((t - _returnStarts) / (flightLoaderSeconds - _returnStarts));
    if (back > 0) {
      canvas.save();
      canvas.scale(ui.lerpDouble(0.88, 1, back)!);
      paintGlassArrow(canvas,
          height: splashArrowHeight,
          opacity: back,
          glow: glow * back,
          glass: _arrowGlass);
      canvas.restore();
    }
  }

  /// The outline between the arrow and the plane, [morph] of the way; the
  /// steps follow a beat behind, so it reads as one motion.
  void _paintMorph(Canvas canvas, double t, double morph) {
    final steps = _inOut(
        (t - _morphStarts - 0.1) / (_morphEnds - _morphStarts - 0.1));
    _paintOutline(canvas, morph, steps);
  }

  void _paintOutline(Canvas canvas, double morph, double steps) {
    final outline = Path();
    for (var i = 0; i < takeoffMorphs.length; i++) {
      outline.addPath(
          takeoffMorphs[i].at(i == 0 ? morph : steps), Offset.zero);
    }
    if (dark) {
      paintArrowGlow(canvas, 92, ui.lerpDouble(0.75, 0.3, morph)!);
      final change = math.sin(math.pi * morph);
      if (change > 0.02) {
        canvas.drawPath(
            outline,
            Paint()
              ..color = Color.fromRGBO(200, 225, 250, 0.38 * change)
              ..maskFilter = MaskFilter.blur(BlurStyle.normal, 12 * change));
      }
    }
    final glass = Glass.lerp(_arrowGlass, _planeGlassOnScreen, morph);
    final shape = GlassShape.path(outline);
    paintGlassBody(canvas, shape, glass);
    paintGlassRim(canvas, shape, glass);
  }

  /// Reduce Motion: the arrow becomes the plane and back where it stands.
  void _paintCalm(Canvas canvas, double t) {
    const rest = 1.2, change = 0.8, hold = 1.0;
    final glow = dark ? 0.75 : 0.0;
    if (t < rest) {
      paintGlassArrow(canvas,
          height: splashArrowHeight, glow: glow, glass: _arrowGlass);
    } else if (t < rest + change) {
      final m = _inOut((t - rest) / change);
      _paintOutline(canvas, m, m);
    } else if (t < rest + change + hold) {
      canvas.save();
      canvas.transform(
          takeoffPlanePose(Offset.zero, takeoffRestHeading, 1).storage);
      paintPearlPlane(canvas,
          detail: _smooth((t - rest - change) / 0.4),
          lights: 1,
          clock: t,
          glass: _planeGlass,
          onLight: !dark);
      canvas.restore();
    } else {
      final m = 1 - _inOut((t - rest - change - hold) / change);
      _paintOutline(canvas, m, m);
    }
  }

  @override
  bool shouldRepaint(FlightLoaderPainter old) =>
      old.clock != clock || old.size != size || old.dark != dark || old.calm != calm;
}
