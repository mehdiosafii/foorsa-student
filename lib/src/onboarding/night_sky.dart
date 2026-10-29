/// The ground behind every onboarding screen: a still night that starts as the
/// native splash's navy and deepens, with a few faint stars high up that drift
/// a little as the student moves through the steps. Nothing else: the object
/// on each screen is lit by its own light (Spotlight).
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
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
      required this.still})
      : super(repaint: Listenable.merge([night, drift, clock]));

  final Animation<double> night;
  final Animation<double> drift;
  final ValueNotifier<double> clock;
  final bool still;

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
      final y = star.y * size.height;
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
  bool shouldRepaint(_StarsPainter old) => old.still != still;
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
