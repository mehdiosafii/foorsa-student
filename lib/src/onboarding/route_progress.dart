/// How far along the setup is: one hairline, the part already flown lit, and
/// the journey's airliner, small, at its tip.
library;

import 'package:flutter/widgets.dart';

import 'airliner.dart';
import 'boarding_style.dart';

class RouteProgress extends StatelessWidget {
  const RouteProgress({super.key, required this.progress, this.width = 132});

  /// 0 at the start, 1 at the end; the parent springs it.
  final Animation<double> progress;
  final double width;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: progress,
      builder: (context, _) => Semantics(
        label: 'Setting up',
        value: '${(progress.value.clamp(0.0, 1.0) * 100).round()}%',
        child: CustomPaint(
          size: Size(width, 16),
          painter: _LinePainter(progress.value.clamp(0.0, 1.0)),
        ),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.p);
  final double p;

  static const _plane = AirlinerSilhouettePainter(Boarding.heading);
  static const _side = 15.0;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    // The plane needs room at both ends, so the line runs inside them.
    const inset = _side / 2;
    final from = Offset(inset, y);
    final to = Offset(size.width - inset, y);
    final tip = Offset.lerp(from, to, p)!;
    final line = Paint()
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(tip + const Offset(_side * 0.6, 0), to,
        line..color = Boarding.hairline);
    if (tip.dx - _side * 0.6 > from.dx) {
      canvas.drawLine(from, tip - const Offset(_side * 0.6, 0),
          line..color = Boarding.heading.withValues(alpha: 0.72));
    }
    canvas.save();
    canvas.translate(tip.dx, tip.dy);
    // Nose to the right, along the line.
    canvas.rotate(1.5707963267948966);
    canvas.translate(-_side / 2, -_side / 2);
    _plane.paint(canvas, const Size(_side, _side));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LinePainter old) => old.p != p;
}
