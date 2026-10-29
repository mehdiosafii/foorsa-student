/// Ads and privacy: one shield, quietly lit. What the screen asks is said in
/// its words, not drawn: there is nothing to show about an ad that worked.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'boarding_style.dart';
import 'lucide.dart';

class TrackingScene extends StatefulWidget {
  const TrackingScene({super.key, required this.still});
  final bool still;

  @override
  State<TrackingScene> createState() => _TrackingSceneState();
}

class _TrackingSceneState extends State<TrackingScene>
    with SingleTickerProviderStateMixin, SceneClock<TrackingScene> {
  @override
  void initState() {
    super.initState();
    startClock(still: widget.still);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'A shield',
      excludeSemantics: true,
      child: Center(
        child: SizedBox.square(
          dimension: 220,
          child: CustomPaint(
            painter: _RingsPainter(clock, still: widget.still),
            child: Center(
              child: Container(
                width: 96,
                height: 96,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    center: Alignment(-0.3, -0.5),
                    radius: 1.1,
                    colors: [Color(0xFF263749), Color(0xFF17232F)],
                  ),
                ),
                foregroundDecoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border:
                      Border.all(color: const Color(0x24FFFFFF), width: 0.8),
                ),
                alignment: Alignment.center,
                child: const Lucide(LucideIcons.shieldCheck,
                    size: 40, color: Boarding.heading, strokeWidth: 1.7),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  _RingsPainter(this.clock, {required this.still}) : super(repaint: clock);
  final ValueNotifier<double> clock;
  final bool still;

  @override
  void paint(Canvas canvas, Size size) {
    final t = still ? 0.0 : clock.value;
    final centre = size.center(Offset.zero);
    for (var k = 0; k < 2; k++) {
      final breathe = 0.5 + 0.5 * math.sin(t * 1.1 - k * 0.9);
      canvas.drawCircle(
          centre,
          70.0 + k * 30,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8
            ..color = Boarding.accent
                .withValues(alpha: (0.16 - k * 0.06) * (0.6 + 0.4 * breathe)));
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) => old.still != still;
}
