/// The ground behind every onboarding screen: the portal's dark backdrop
/// (PortalBackdrop.tsx, its folds and edge light verbatim, sliced to the
/// screen as `xMidYMid slice` does) over a night that starts as the native
/// splash's navy, with a quiet field of stars that drifts as the student
/// moves through the steps, and the warm glow of a city on the horizon.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'boarding_style.dart';
import 'svg_path.dart';

class NightSky extends StatefulWidget {
  const NightSky(
      {super.key,
      required this.night,
      required this.drift,
      this.still = false});

  /// 0: the splash's flat navy; 1: the night with its folds and stars.
  final Animation<double> night;

  /// How far the stars have drifted, in steps.
  final Animation<double> drift;

  /// Reduce Motion: no twinkle and no shooting star.
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

// The portal's dark folds, in its 864 x 1536 box.
const _upper = 'M370-80C536 43 557 167 725 228C790 252 834 253 914 273V-80Z';
const _sweep =
    'M-70 98C218 200 462 235 740 578C969 862 808 1012 576 1105C279 1224 121 1260-50 1449Z';
const _sweepEdge =
    'M-70 98C218 200 462 235 740 578C969 862 808 1012 576 1105C279 1224 121 1260-50 1449';
const _fold =
    'M928 660C836 929 691 1053 618 1256C583 1353 550 1480 517 1616H928Z';
const _foldEdge =
    'M928 660C836 929 691 1053 618 1256C583 1353 550 1480 517 1616';

/// An SVG linearGradient in objectBoundingBox units over [box].
ui.Shader _bboxGradient(Rect box, Offset from, Offset to, List<Color> colors,
        List<double> stops) =>
    ui.Gradient.linear(
      Offset(box.left + box.width * from.dx, box.top + box.height * from.dy),
      Offset(box.left + box.width * to.dx, box.top + box.height * to.dy),
      colors,
      stops,
    );

class _GroundPainter extends CustomPainter {
  _GroundPainter(this.night) : super(repaint: night);
  final Animation<double> night;

  @override
  void paint(Canvas canvas, Size size) {
    final n = night.value.clamp(0.0, 1.0);
    final screen = Offset.zero & size;
    // The night's ground: a little bluer at the top than the portal's, so the
    // splash's navy deepens into it instead of being replaced.
    canvas.drawRect(
      screen,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(size.width * 0.35, size.height),
          [
            Color.lerp(Boarding.splashNavy, const Color(0xFF13263D), n)!,
            Color.lerp(Boarding.splashNavy, const Color(0xFF0B1521), n)!,
            Color.lerp(Boarding.splashNavy, Boarding.night, n)!,
          ],
          const [0, 0.55, 1],
        ),
    );
    if (n <= 0.001) return;

    // xMidYMid slice: cover the screen, centred.
    final scale = math.max(size.width / 864, size.height / 1536);
    final dx = (size.width - 864 * scale) / 2;
    final dy = (size.height - 1536 * scale) / 2;
    canvas.save();
    canvas.translate(dx, dy);
    canvas.scale(scale);
    canvas.saveLayer(const Rect.fromLTWH(-100, -100, 1100, 1800),
        Paint()..color = Color.fromRGBO(255, 255, 255, 0.62 * n));

    final upper = svgPath(_upper);
    canvas.drawPath(
        upper,
        Paint()
          ..shader = _bboxGradient(upper.getBounds(), const Offset(0, 1),
              const Offset(0.7, 0), const [
            Color(0xFF344350),
            Color(0xFF17222E),
            Color(0xFF0A111A),
            Color(0xFF060C13)
          ], const [
            0,
            0.16,
            0.45,
            1
          ]));
    final sweep = svgPath(_sweep);
    canvas.drawPath(
        sweep,
        Paint()
          ..shader = _bboxGradient(sweep.getBounds(), const Offset(0.1, 0.15),
              const Offset(0.95, 0.95), const [
            Color(0xFF101821),
            Color(0xFF090F15),
            Color(0xFF111E2A),
            Color(0xFF384D5D),
            Color(0xFF91A6B4)
          ], const [
            0,
            0.42,
            0.76,
            0.94,
            1
          ]));
    final edgeColors = [
      const Color(0xFFD3DFE7).withValues(alpha: 0.75),
      const Color(0xFF7B98B0).withValues(alpha: 0.12),
      const Color(0xFFAEC5D6).withValues(alpha: 0.45),
      const Color(0xFFF5E5D2).withValues(alpha: 0.75),
    ];
    const edgeStops = [0.0, 0.32, 0.75, 1.0];
    final sweepEdge = svgPath(_sweepEdge);
    canvas.drawPath(
        sweepEdge,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..shader = _bboxGradient(sweepEdge.getBounds(), Offset.zero,
              const Offset(1, 1), edgeColors, edgeStops));
    final fold = svgPath(_fold);
    canvas.drawPath(
        fold,
        Paint()
          ..shader = _bboxGradient(
              fold.getBounds(), Offset.zero, const Offset(1, 0.8), const [
            Color(0xFF536C80),
            Color(0xFF1B2A38),
            Color(0xFF060C12),
            Color(0xFF0C141D)
          ], const [
            0,
            0.15,
            0.48,
            1
          ]));
    final foldEdge = svgPath(_foldEdge);
    canvas.drawPath(
        foldEdge,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..shader = _bboxGradient(foldEdge.getBounds(), Offset.zero,
              const Offset(1, 1), edgeColors, edgeStops));
    canvas.restore();
    canvas.restore();

    // The portal's soft light from the top left.
    canvas.drawRect(
        screen,
        Paint()
          ..shader = ui.Gradient.radial(
              Offset.zero, math.max(size.width, size.height), [
            const Color(0xFFBFCEDA).withValues(alpha: 0.09 * n),
            const Color(0x00BFCEDA)
          ]));

    // A city on the horizon: warm, then cool, very faint.
    final horizon = Offset(size.width * 0.5, size.height * 1.06);
    canvas.drawRect(
        screen,
        Paint()
          ..shader = ui.Gradient.radial(horizon, size.width * 0.95, [
            const Color(0xFFF5E5D2).withValues(alpha: 0.075 * n),
            const Color(0xFF6A8FB8).withValues(alpha: 0.035 * n),
            const Color(0x006A8FB8),
          ], const [
            0,
            0.45,
            1
          ]));
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
  return List<_Star>.generate(84, (_) {
    final y = math.pow(random.nextDouble(), 1.35).toDouble() * 0.7;
    return _Star(
      random.nextDouble(),
      y,
      0.35 + random.nextDouble() * 0.95,
      0.25 + random.nextDouble() * 0.6,
      0.5 + random.nextDouble() * 1.4,
      random.nextDouble() * math.pi * 2,
      0.25 + random.nextDouble() * 0.75,
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
      final shift = drift.value * 26 * star.depth;
      var x = (star.x * size.width - shift) % size.width;
      if (x < 0) x += size.width;
      final y = star.y * size.height;
      final fade = 1 - (star.y / 0.7);
      final twinkle =
          still ? 1.0 : 0.62 + 0.38 * math.sin(t * star.speed + star.phase);
      final a = (star.alpha * twinkle * fade * n).clamp(0.0, 1.0);
      if (a < 0.02) continue;
      paint.color = Color.fromRGBO(226, 236, 248, a);
      canvas.drawCircle(Offset(x, y), star.radius, paint);
      if (star.radius > 1.05) {
        paint.color = Color.fromRGBO(190, 214, 240, a * 0.18);
        canvas.drawCircle(Offset(x, y), star.radius * 3.2, paint);
      }
    }

    if (still) return;
    // Now and then a shooting star, high up, gone in under a second.
    const period = 11.0;
    final cycle = (t + 4) % period;
    if (cycle < 0.85) {
      final p = cycle / 0.85;
      final seed = ((t + 4) / period).floor();
      final r = math.Random(seed);
      final start = Offset(size.width * (0.15 + r.nextDouble() * 0.5),
          size.height * (0.06 + r.nextDouble() * 0.16));
      const angle = 0.42;
      final length = size.width * 0.34;
      final head =
          start + Offset(math.cos(angle), math.sin(angle)) * (length * p);
      final tail = head -
          Offset(math.cos(angle), math.sin(angle)) *
              (length * 0.38 * math.sin(p * math.pi));
      final alpha = math.sin(p * math.pi) * 0.7 * n;
      canvas.drawLine(
          tail,
          head,
          Paint()
            ..strokeWidth = 1.2
            ..strokeCap = StrokeCap.round
            ..shader = ui.Gradient.linear(tail, head, [
              const Color(0x00E8F2FF),
              Color.fromRGBO(232, 242, 255, alpha),
            ]));
    }
  }

  @override
  bool shouldRepaint(_StarsPainter old) => old.still != still;
}
