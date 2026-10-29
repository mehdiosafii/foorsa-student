/// How far along the setup is, drawn as the boarding pass draws a route
/// (CMN, the airway, the destination): Casablanca to China, a gate for each
/// step and the journey's airliner flying between them.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'airliner.dart';
import 'boarding_style.dart';

class RouteProgress extends StatelessWidget {
  const RouteProgress({super.key, required this.progress, required this.gates});

  /// 0 at Casablanca, 1 in China; the parent springs it.
  final Animation<double> progress;

  /// The gates along the way (the permission steps shown).
  final int gates;

  @override
  Widget build(BuildContext context) {
    Widget end(String code, String city, CrossAxisAlignment align) => FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            crossAxisAlignment: align,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(code,
                  style: Boarding.monoStyle(13,
                      color: Boarding.ink,
                      weight: FontWeight.w700,
                      spacing: 1.2)),
              const SizedBox(height: 1),
              Text(city,
                  style: const TextStyle(
                      fontSize: 10.5,
                      color: Boarding.faint,
                      letterSpacing: 0.2)),
            ],
          ),
        );
    return Semantics(
      label: 'Setting up',
      value: '${(progress.value * 100).round()}%',
      child: SizedBox(
        height: 40,
        child: Row(children: [
          end('CMN', 'Casablanca', CrossAxisAlignment.start),
          const SizedBox(width: 12),
          Expanded(
            child: CustomPaint(
              painter: _RoutePainter(progress, gates),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(width: 12),
          end('CHN', 'China', CrossAxisAlignment.end),
        ]),
      ),
    );
  }
}

class _RoutePainter extends CustomPainter {
  _RoutePainter(this.progress, this.gates) : super(repaint: progress);
  final Animation<double> progress;
  final int gates;

  static const _plane = AirlinerSilhouettePainter(Boarding.heading);

  Offset _at(Size size, double t) {
    // A shallow great-circle bow.
    final a = Offset(4, size.height * 0.5);
    final b = Offset(size.width - 4, size.height * 0.5);
    final c = Offset(size.width / 2, size.height * 0.5 - 13);
    final u = 1 - t;
    return a * (u * u) + c * (2 * u * t) + b * (t * t);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final p = progress.value.clamp(0.0, 1.0);
    // The remaining airway: fine dashes.
    final dash = Paint()
      ..color = const Color(0x3DE0E5EC)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    const samples = 64;
    for (var i = 0; i < samples; i += 2) {
      final t0 = i / samples, t1 = (i + 1) / samples;
      if (t1 <= p) continue;
      canvas.drawLine(_at(size, math.max(t0, p)), _at(size, t1), dash);
    }
    // The flown part: solid accent.
    if (p > 0) {
      final flown = Path()..moveTo(_at(size, 0).dx, _at(size, 0).dy);
      for (var i = 1; i <= 48; i++) {
        final q = _at(size, p * i / 48);
        flown.lineTo(q.dx, q.dy);
      }
      canvas.drawPath(
          flown,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round
            ..shader = ui.Gradient.linear(
                _at(size, 0),
                _at(size, math.max(p, 0.01)),
                [Boarding.accent.withValues(alpha: 0.35), Boarding.accent]));
    }
    // The ends and the gates.
    for (var g = 0; g <= gates + 1; g++) {
      final t = g / (gates + 1);
      final at = _at(size, t);
      final reached = p >= t - 0.001;
      final endpoint = g == 0 || g == gates + 1;
      canvas.drawCircle(at, endpoint ? 3.2 : 2.6,
          Paint()..color = reached ? Boarding.accent : const Color(0xFF3A4A5C));
      if (!reached) {
        canvas.drawCircle(
            at,
            endpoint ? 3.2 : 2.6,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1
              ..color = const Color(0x52E0E5EC));
      }
    }
    // The plane, nose along the airway.
    final here = _at(size, p);
    final ahead = _at(size, math.min(1, p + 0.01));
    final behind = _at(size, math.max(0, p - 0.01));
    final heading = math.atan2(ahead.dy - behind.dy, ahead.dx - behind.dx);
    canvas.drawCircle(
        here,
        11,
        Paint()
          ..color = Boarding.accent.withValues(alpha: 0.18)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    canvas.save();
    canvas.translate(here.dx, here.dy);
    canvas.rotate(heading + math.pi / 2);
    const side = 22.0;
    canvas.translate(-side / 2, -side / 2);
    _plane.paint(canvas, const Size(side, side));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RoutePainter old) =>
      old.gates != gates || old.progress != progress;
}
