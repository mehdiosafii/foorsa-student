/// Ads and privacy: one shield, quietly lit. What the screen asks is said in
/// its words, not drawn: there is nothing to show about an ad that worked.
/// The shield is the control.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'boarding_style.dart';
import 'glass.dart';
import 'lucide.dart';
import 'scene_hint.dart';
import 'stage_forms.dart';

class TrackingScene extends StatefulWidget {
  const TrackingScene({
    super.key,
    required this.still,
    required this.feel,
    required this.armed,
    required this.label,
    required this.hint,
    required this.onAct,
    required this.outcome,
  });
  final bool still;
  final Feel feel;
  final bool armed;
  final String label;
  final String hint;
  final SceneAct onAct;
  final ValueListenable<bool?> outcome;

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
    return LayoutBuilder(builder: (context, box) {
      final middle = box.maxHeight / 2;
      return Stack(clipBehavior: Clip.none, children: [
        Positioned(
          left: box.maxWidth / 2 - 110,
          top: middle - 110,
          width: 220,
          height: 220,
          child:
              CustomPaint(painter: _RingsPainter(clock, still: widget.still)),
        ),
        Positioned(
          left: box.maxWidth / 2 - shieldSide / 2,
          top: middle - shieldSide / 2,
          width: shieldSide,
          height: shieldSide,
          child: ObjectControl(
            label: widget.label,
            armed: widget.armed,
            feel: widget.feel,
            scale: 0.94,
            onTap: () => widget.onAct(),
            child: const GlassPane(
              glass: Glass.tile,
              circle: true,
              child: Center(
                child: Lucide(LucideIcons.shieldCheck,
                    size: 40, color: Boarding.heading, strokeWidth: 1.7),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: middle + 110 + 6,
          child: ValueListenableBuilder<bool?>(
            valueListenable: widget.outcome,
            builder: (context, answer, _) => GestureHint(widget.hint,
                still: widget.still, shown: widget.armed && answer == null),
          ),
        ),
      ]);
    });
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
