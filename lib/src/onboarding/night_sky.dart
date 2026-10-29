/// The ground behind every onboarding screen: a still night that starts as the
/// native splash's navy and deepens, with a few faint stars high up that drift
/// a little as the student moves through the steps. Nothing else: the object
/// on each screen is lit by its own light (Spotlight).
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'boarding_style.dart';

class NightSky extends StatefulWidget {
  const NightSky(
      {super.key,
      required this.night,
      required this.drift,
      this.still = false});

  /// 0: the splash's flat navy; 1: the night.
  final Animation<double> night;

  /// How far the stars have drifted, in steps.
  final Animation<double> drift;

  /// Reduce Motion: the stars hold still.
  final bool still;

  @override
  State<NightSky> createState() => _NightSkyState();
}

class _NightSkyState extends State<NightSky>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<double> _clock = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    _ticker =
        createTicker((elapsed) => _clock.value = elapsed.inMicroseconds / 1e6);
    if (!widget.still) _ticker.start();
  }

  @override
  void didUpdateWidget(NightSky old) {
    super.didUpdateWidget(old);
    if (widget.still && _ticker.isActive) _ticker.stop();
    if (!widget.still && !_ticker.isActive) _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: [
      RepaintBoundary(
          child: CustomPaint(painter: _GroundPainter(widget.night))),
      RepaintBoundary(
        child: CustomPaint(
          painter: _StarsPainter(
            night: widget.night,
            drift: widget.drift,
            clock: _clock,
            still: widget.still,
            // The sign-in's sky (NightStage.tsx) is laid out in the web view,
            // which starts under the status bar: the stars are placed in that
            // frame so both nights have them in the same places.
            top: statusBarHeight(context),
          ),
        ),
      ),
    ]);
  }
}

class _GroundPainter extends CustomPainter {
  _GroundPainter(this.night) : super(repaint: night);
  final Animation<double> night;

  @override
  void paint(Canvas canvas, Size size) {
    final n = night.value.clamp(0.0, 1.0);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, size.height),
          [
            Color.lerp(Boarding.splashNavy, Boarding.nightTop, n)!,
            Color.lerp(Boarding.splashNavy, Boarding.night, n)!,
            Color.lerp(Boarding.splashNavy, Boarding.nightFoot, n)!,
          ],
          const [0, 0.5, 1],
        ),
    );
  }

  @override
  bool shouldRepaint(_GroundPainter old) => old.night != night;
}

class _Star {
  const _Star(this.x, this.y, this.radius, this.alpha, this.speed, this.phase,
      this.depth);
  final double x, y, radius, alpha, speed, phase, depth;
}

final List<_Star> _stars = () {
  // Seeded, so every student sees the same sky and the tests can rely on it.
  final random = math.Random(2026);
  return List<_Star>.generate(26, (_) {
    final y = math.pow(random.nextDouble(), 1.6).toDouble() * 0.46;
    return _Star(
      random.nextDouble(),
      y,
      0.4 + random.nextDouble() * 0.55,
      0.16 + random.nextDouble() * 0.34,
      0.25 + random.nextDouble() * 0.5,
      random.nextDouble() * math.pi * 2,
      0.3 + random.nextDouble() * 0.7,
    );
  });
}();

class _StarsPainter extends CustomPainter {
  _StarsPainter(
      {required this.night,
      required this.drift,
      required this.clock,
      required this.still,
      required this.top})
      : super(repaint: Listenable.merge([night, drift, clock]));

  final Animation<double> night;
  final Animation<double> drift;
  final ValueNotifier<double> clock;
  final bool still;

  /// Where the web view starts: the height of the status bar.
  final double top;

  @override
  void paint(Canvas canvas, Size size) {
    final n = night.value.clamp(0.0, 1.0);
    if (n <= 0.001) return;
    final t = clock.value;
    final paint = Paint();
    for (final star in _stars) {
      // Nearer stars drift further: depth.
      final shift = drift.value * 14 * star.depth;
      var x = (star.x * size.width - shift) % size.width;
      if (x < 0) x += size.width;
      final y = top + star.y * (size.height - top);
      final fade = 1 - (star.y / 0.46);
      final twinkle =
          still ? 1.0 : 0.7 + 0.3 * math.sin(t * star.speed + star.phase);
      final a = (star.alpha * twinkle * fade * n).clamp(0.0, 1.0);
      if (a < 0.02) continue;
      paint.color = Color.fromRGBO(226, 236, 248, a);
      canvas.drawCircle(Offset(x, y), star.radius, paint);
    }
  }

  @override
  bool shouldRepaint(_StarsPainter old) => old.still != still || old.top != top;
}

/// The one light on the stage: a soft pool behind the object, breathing very
/// slowly so the screen is never quite frozen.
class Spotlight extends StatelessWidget {
  const Spotlight({super.key, required this.radius, this.clock});
  final double radius;
  final ValueListenable<double>? clock;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: CustomPaint(
          size: Size.square(radius * 2),
          painter: _SpotlightPainter(clock),
        ),
      );
}

class _SpotlightPainter extends CustomPainter {
  _SpotlightPainter(this.clock) : super(repaint: clock);
  final ValueListenable<double>? clock;

  @override
  void paint(Canvas canvas, Size size) {
    final t = clock?.value ?? 0;
    final breath = 0.92 + 0.08 * math.sin(t * 2 * math.pi / 7);
    final centre = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.drawCircle(
      centre,
      r,
      Paint()
        ..shader = ui.Gradient.radial(centre, r, [
          Boarding.spotlight.withValues(alpha: 0.62 * breath),
          Boarding.spotlight.withValues(alpha: 0.24 * breath),
          Boarding.spotlight.withValues(alpha: 0),
        ], const [
          0,
          0.45,
          1
        ]),
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) => old.clock != clock;
}

/// The height of the status bar, from the window itself: a SafeArea above a
/// widget hides it from MediaQuery. The same inset the shell's SafeArea puts
/// the web view under.
double statusBarHeight(BuildContext context) {
  final view = View.of(context);
  return view.padding.top / view.devicePixelRatio;
}

/// Paints its child only below the status bar. The sign-in's light is cut
/// where its web view starts, and the band above is the shell's flat colour,
/// so the onboarding's light ends at the same line.
class UnderStatusBar extends SingleChildRenderObjectWidget {
  const UnderStatusBar({super.key, required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderUnderStatusBar(statusBarHeight(context));

  @override
  void updateRenderObject(
          BuildContext context, RenderUnderStatusBar renderObject) =>
      renderObject.top = statusBarHeight(context);
}

/// [UnderStatusBar]'s render object.
class RenderUnderStatusBar extends RenderProxyBox {
  RenderUnderStatusBar(this._top);

  double _top;
  set top(double value) {
    if (value == _top) return;
    _top = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    // Where the status bar ends, in this box's own points.
    final edge = globalToLocal(Offset(0, _top)).dy;
    if (edge <= 0) {
      layer = null;
      super.paint(context, offset);
      return;
    }
    layer = context.pushClipRect(
        needsCompositing,
        offset,
        Rect.fromLTRB(0, edge, size.width, math.max(edge, size.height)),
        super.paint,
        oldLayer: layer as ClipRectLayer?);
  }
}
