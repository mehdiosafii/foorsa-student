/// Location: a quiet night map seen through a lens that fades into the stage,
/// the phone's blue dot in the middle with its heading, and the one thing it
/// gives a student in a new city: the next prayer.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'boarding_style.dart';
import 'stage_forms.dart';

class LocationScene extends StatefulWidget {
  const LocationScene({super.key, required this.still, required this.feel});
  final bool still;
  final Feel feel;

  @override
  State<LocationScene> createState() => _LocationSceneState();
}

class _LocationSceneState extends State<LocationScene>
    with SingleTickerProviderStateMixin, SceneClock<LocationScene> {
  @override
  void initState() {
    super.initState();
    startClock(still: widget.still);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Your location on a map, with the next prayer time',
      excludeSemantics: true,
      child: Center(
        child: SizedBox(
          width: lensBox,
          height: lensBox,
          child: Stack(alignment: Alignment.center, children: [
            Positioned.fill(
              child:
                  CustomPaint(painter: _MapPainter(clock, still: widget.still)),
            ),
            // The label floats above the dot once the map is there.
            ValueListenableBuilder<double>(
              valueListenable: clock,
              builder: (context, t, child) {
                final v = widget.still ? 1.0 : easeOut(t, 0.5, 1.2);
                return Transform.translate(
                  offset: Offset(0, -50 + 8 * (1 - v)),
                  child: Opacity(opacity: v, child: child),
                );
              },
              child: const _PrayerLabel(),
            ),
          ]),
        ),
      ),
    );
  }
}

class _PrayerLabel extends StatelessWidget {
  const _PrayerLabel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
      decoration: BoxDecoration(
        color: const Color(0xFF1B2836),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Boarding.slateEdge, width: 0.5),
        boxShadow: const [
          BoxShadow(
              color: Color(0x66000000),
              blurRadius: 18,
              offset: Offset(0, 8),
              spreadRadius: -6),
        ],
      ),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(
              text: 'Asr  ',
              style: TextStyle(
                  color: Boarding.muted.withValues(alpha: 0.95),
                  fontWeight: FontWeight.w500)),
          const TextSpan(
              text: '15:42',
              style: TextStyle(
                  color: Boarding.heading,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()])),
        ]),
        style:
            const TextStyle(fontSize: 13.5, height: 1.2, letterSpacing: -0.1),
      ),
    );
  }
}

class _MapPainter extends CustomPainter {
  _MapPainter(this.clock, {required this.still}) : super(repaint: clock);
  final ValueNotifier<double> clock;
  final bool still;

  @override
  void paint(Canvas canvas, Size size) {
    final t = still ? 0.0 : clock.value;
    final centre = size.center(Offset.zero);
    final r = size.width / 2;
    final appear = still ? 1.0 : easeOut(t, 0, 0.9);

    // The map, through a lens that fades out at its edge.
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    // It drifts very slowly, as a map does in a walking hand.
    canvas.rotate(0.03 * math.sin(t * 0.35));
    canvas.translate(4 * math.sin(t * 0.21), 3 * math.cos(t * 0.17));
    canvas.scale(0.94 + 0.06 * appear);
    canvas.translate(-145, -145);
    _streets(canvas);
    canvas.restore();
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = ui.Gradient.radial(centre, r, [
          Color.fromRGBO(0, 0, 0, appear),
          Color.fromRGBO(0, 0, 0, 0.88 * appear),
          const Color(0x00000000),
        ], const [
          0,
          0.55,
          1
        ]),
    );
    canvas.restore();

    // Where the phone is pointing.
    final heading =
        -math.pi / 2 + 0.75 + (still ? 0 : 0.12 * math.sin(t * 0.8));
    const reach = 64.0, spread = 0.5;
    final cone = Path()
      ..moveTo(centre.dx, centre.dy)
      ..arcTo(Rect.fromCircle(center: centre, radius: reach), heading - spread,
          spread * 2, false)
      ..close();
    canvas.drawPath(
      cone,
      Paint()
        ..shader = ui.Gradient.radial(centre, reach, [
          Boarding.here.withValues(alpha: 0.5 * appear),
          Boarding.here.withValues(alpha: 0.16 * appear),
          Boarding.here.withValues(alpha: 0),
        ], const [
          0.15,
          0.55,
          1
        ])
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    // The dot, its halo breathing.
    final pulse = still ? 0.5 : (t % 2.4) / 2.4;
    canvas.drawCircle(
        centre,
        12 + 26 * Curves.easeOut.transform(pulse),
        Paint()
          ..color =
              Boarding.here.withValues(alpha: 0.22 * (1 - pulse) * appear));
    canvas.drawCircle(
        centre,
        11,
        Paint()
          ..color = Color.fromRGBO(0, 0, 0, 0.35 * appear)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    canvas.drawCircle(
        centre, 10.5, Paint()..color = Color.fromRGBO(255, 255, 255, appear));
    canvas.drawCircle(
        centre, 7.5, Paint()..color = Boarding.here.withValues(alpha: appear));
  }

  /// A part of a city at night, in a 290 pt square: a river, avenues, a
  /// grid of side streets and a park.
  void _streets(Canvas canvas) {
    canvas.drawRect(const Rect.fromLTWH(-40, -40, 370, 370),
        Paint()..color = const Color(0xFF101A25));
    // Side streets, a slightly turned grid.
    final side = Paint()
      ..color = const Color(0xFF172433)
      ..strokeWidth = 1.2;
    canvas.save();
    canvas.translate(145, 145);
    canvas.rotate(0.21);
    for (var k = -9; k <= 9; k++) {
      final o = k * 22.0;
      canvas.drawLine(Offset(o, -220), Offset(o, 220), side);
      canvas.drawLine(Offset(-220, o), Offset(220, o), side);
    }
    canvas.restore();
    // The river.
    final river = Path()
      ..moveTo(-40, 214)
      ..cubicTo(60, 186, 120, 242, 190, 210)
      ..cubicTo(240, 188, 280, 150, 340, 160);
    canvas.drawPath(
        river,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 30
          ..color = const Color(0xFF162C43));
    // Avenues.
    final avenue = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.2
      ..color = const Color(0xFF2D3E52);
    canvas.drawPath(
        Path()
          ..moveTo(-20, 98)
          ..quadraticBezierTo(150, 72, 320, 92),
        avenue);
    canvas.drawPath(
        Path()
          ..moveTo(96, -20)
          ..quadraticBezierTo(124, 150, 110, 320),
        avenue);
    canvas.drawPath(
        Path()
          ..moveTo(232, -20)
          ..quadraticBezierTo(196, 160, 214, 320),
        avenue..strokeWidth = 2.4);
    // A bridge over the river.
    canvas.drawLine(const Offset(152, 196), const Offset(160, 246),
        avenue..strokeWidth = 2.6);
  }

  @override
  bool shouldRepaint(_MapPainter old) => old.still != still;
}
