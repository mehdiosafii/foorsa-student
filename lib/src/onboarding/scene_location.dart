/// Location: a night map of a Chinese city (Hangzhou, around West Lake) with
/// the phone finding itself, then what the portal does with it: the next
/// prayer, the weather, a supermarket nearby. Drawn, not fetched: the map is
/// an illustration.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'boarding_style.dart';
import 'lucide.dart';

class LocationScene extends StatefulWidget {
  const LocationScene({super.key, required this.still, required this.feel});
  final bool still;
  final Feel feel;

  @override
  State<LocationScene> createState() => _LocationSceneState();
}

class _LocationSceneState extends State<LocationScene>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final ValueNotifier<double> _t = ValueNotifier<double>(0);
  bool _felt = false;

  @override
  void initState() {
    super.initState();
    if (widget.still) {
      _t.value = 6;
    } else {
      _ticker.start();
    }
  }

  void _tick(Duration elapsed) {
    _t.value = elapsed.inMicroseconds / 1e6;
    if (!_felt && _t.value > 1.25) {
      _felt = true;
      widget.feel('detent');
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _t.dispose();
    super.dispose();
  }

  double _pop(double t, double at) {
    final x = ((t - at) / 0.5).clamp(0.0, 1.0);
    return 1 - math.exp(-6 * x) * math.cos(8 * x) * (1 - x);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          'A map of Hangzhou with your position, the next prayer, the weather and a supermarket nearby',
      excludeSemantics: true,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Boarding.glassEdge),
              ),
              child: ValueListenableBuilder<double>(
                valueListenable: _t,
                builder: (context, t, _) =>
                    LayoutBuilder(builder: (context, constraints) {
                  final size = constraints.biggest;
                  final me = Offset(size.width * 0.44, size.height * 0.5);
                  final shop =
                      me + Offset(size.width * 0.2, -size.height * 0.2);
                  final pin = _pop(t, 1.45);
                  final prayer = _pop(t, 1.85);
                  final weather = _pop(t, 2.2);
                  return Stack(clipBehavior: Clip.none, children: [
                    Positioned.fill(
                        child: CustomPaint(
                            painter: _MapPainter(
                                t: t,
                                me: me,
                                still: widget.still,
                                base: DefaultTextStyle.of(context).style))),
                    // The supermarket, and its label.
                    Positioned(
                      left: shop.dx - 17,
                      top: shop.dy - 40,
                      child: Opacity(
                        opacity: pin.clamp(0.0, 1.0),
                        child: Transform.scale(
                          scale: 0.6 + 0.4 * pin,
                          alignment: Alignment.bottomCenter,
                          child: const _Pin(),
                        ),
                      ),
                    ),
                    Positioned(
                      left: shop.dx + 22,
                      top: shop.dy - 40,
                      child: Opacity(
                        opacity: pin.clamp(0.0, 1.0),
                        child: Transform.translate(
                          offset: Offset(-8 * (1 - pin), 0),
                          child: const _Label(
                              title: 'Supermarket', detail: '4 min walk'),
                        ),
                      ),
                    ),
                    // The next prayer.
                    Positioned(
                      left: 14,
                      bottom: 14,
                      child: Opacity(
                        opacity: prayer.clamp(0.0, 1.0),
                        child: Transform.translate(
                          offset: Offset(0, 16 * (1 - prayer)),
                          child: const _PrayerCard(),
                        ),
                      ),
                    ),
                    // The weather.
                    Positioned(
                      right: 14,
                      top: 14,
                      child: Opacity(
                        opacity: weather.clamp(0.0, 1.0),
                        child: Transform.translate(
                          offset: Offset(0, -10 * (1 - weather)),
                          child: const _Weather(),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 14,
                      top: 14,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(10, 6, 11, 6),
                        decoration: BoxDecoration(
                          color: const Color(0x990B1521),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: const Color(0x24FFFFFF)),
                        ),
                        child: const Text('HANGZHOU · 杭州',
                            style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                                color: Boarding.ink)),
                      ),
                    ),
                  ]);
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MapPainter extends CustomPainter {
  _MapPainter(
      {required this.t,
      required this.me,
      required this.still,
      required this.base});
  final double t;
  final Offset me;
  final bool still;
  final TextStyle base;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFF0F1A27));
    // The map drifts a little under the phone, as a map does while it settles.
    final drift = still
        ? Offset.zero
        : Offset(math.sin(t * 0.21) * 10, math.cos(t * 0.17) * 6);
    canvas.save();
    canvas.translate(drift.dx, drift.dy);
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-0.21);
    canvas.translate(-size.width / 2, -size.height / 2);

    final w = size.width, h = size.height;
    // West Lake.
    final lake = Path()
      ..moveTo(-w * 0.2, h * 0.72)
      ..cubicTo(w * 0.02, h * 0.62, w * 0.06, h * 0.98, -w * 0.05, h * 1.25)
      ..lineTo(-w * 0.4, h * 1.25)
      ..close();
    final lakeBig = Path()
      ..moveTo(-w * 0.3, h * 0.55)
      ..cubicTo(w * 0.1, h * 0.5, w * 0.26, h * 0.72, w * 0.18, h * 0.98)
      ..cubicTo(w * 0.12, h * 1.18, -w * 0.2, h * 1.3, -w * 0.4, h * 1.2)
      ..close();
    canvas.drawPath(lakeBig, Paint()..color = const Color(0xFF123049));
    canvas.drawPath(lake, Paint()..color = const Color(0xFF15385A));
    canvas.drawPath(
        lakeBig,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = const Color(0x334F86B6));
    // A park.
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.62, h * 0.62, w * 0.3, h * 0.22),
            const Radius.circular(14)),
        Paint()..color = const Color(0xFF11251F));

    // Blocks on a grid, streets between them.
    final block = Paint()..color = const Color(0xFF142233);
    for (var gx = -2; gx < 9; gx++) {
      for (var gy = -2; gy < 10; gy++) {
        final rect = Rect.fromLTWH(gx * 58.0 + 12, gy * 46.0 + 8, 46, 34);
        if (lakeBig.contains(rect.center)) continue;
        canvas.drawRRect(
            RRect.fromRectAndRadius(rect, const Radius.circular(5)), block);
      }
    }
    final street = Paint()
      ..color = const Color(0xFF1C2D41)
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    for (var gx = -2; gx < 10; gx++) {
      canvas.drawLine(
          Offset(gx * 58.0 + 4, -40), Offset(gx * 58.0 + 4, h + 60), street);
    }
    for (var gy = -2; gy < 12; gy++) {
      canvas.drawLine(
          Offset(-40, gy * 46.0 + 2), Offset(w + 80, gy * 46.0 + 2), street);
    }
    // An avenue across, with its centre line.
    final avenue = Path()
      ..moveTo(-40, h * 0.3)
      ..cubicTo(w * 0.3, h * 0.24, w * 0.6, h * 0.42, w + 60, h * 0.36);
    canvas.drawPath(
        avenue,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 11
          ..color = const Color(0xFF26394F));
    canvas.drawPath(
        avenue,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0x26E0E5EC));
    canvas.restore();

    // A wash of light where the phone is.
    canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = ui.Gradient.radial(me, size.width * 0.7,
              [const Color(0x223B6FA0), const Color(0x00000000)]));

    // Finding itself: a wide circle closing in, then the dot.
    final fix = still ? 1.0 : ((t - 0.2) / 1.05).clamp(0.0, 1.0);
    final eased = 1 - math.pow(1 - fix, 3).toDouble();
    final accuracy = 90 - 70 * eased;
    canvas.drawCircle(
        me,
        accuracy,
        Paint()
          ..color = Color.fromRGBO(78, 163, 255, 0.10 + 0.04 * (1 - eased)));
    canvas.drawCircle(
        me,
        accuracy,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Color.fromRGBO(78, 163, 255, 0.35 * (1 - eased) + 0.12));
    if (fix >= 1 && !still) {
      final pulse = ((t - 1.25) % 2.2) / 2.2;
      canvas.drawCircle(me, 10 + 26 * pulse,
          Paint()..color = Color.fromRGBO(78, 163, 255, 0.3 * (1 - pulse)));
    }
    // Which way the phone faces.
    final heading = -math.pi / 2 + 0.5 + (still ? 0 : math.sin(t * 0.8) * 0.12);
    final cone = Path()
      ..moveTo(me.dx, me.dy)
      ..arcTo(
          Rect.fromCircle(center: me, radius: 34), heading - 0.42, 0.84, false)
      ..close();
    canvas.drawPath(
        cone,
        Paint()
          ..shader = ui.Gradient.radial(
              me, 34, [const Color(0x664EA3FF), const Color(0x004EA3FF)])
          ..color = Color.fromRGBO(255, 255, 255, eased));
    canvas.drawCircle(me, 9.5, Paint()..color = const Color(0xFFFFFFFF));
    canvas.drawCircle(me, 7, Paint()..color = const Color(0xFF4EA3FF));
    canvas.drawCircle(
        me,
        9.5,
        Paint()
          ..color = const Color(0x40000000)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5);

    // The lake's name, upright.
    final label = TextPainter(
      text: TextSpan(
          text: 'West Lake · 西湖',
          style: base.copyWith(
              fontSize: 11,
              color: const Color(0x997FA6CC),
              letterSpacing: 0.4,
              decoration: TextDecoration.none)),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, Offset(size.width * 0.06, size.height * 0.74));
  }

  @override
  bool shouldRepaint(_MapPainter old) =>
      old.t != t || old.me != me || old.still != still;
}

class _Pin extends StatelessWidget {
  const _Pin();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 34,
      height: 42,
      child: Stack(alignment: Alignment.topCenter, children: [
        Positioned(
          bottom: 0,
          child: Container(
              width: 8,
              height: 3,
              decoration: BoxDecoration(
                  color: const Color(0x66000000),
                  borderRadius: BorderRadius.circular(4))),
        ),
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Boarding.pearlTop, Boarding.pearlBottom],
            ),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x80000000),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                  spreadRadius: -3)
            ],
          ),
          child: const Lucide(LucideIcons.shoppingBasket,
              size: 18, color: Boarding.pearlInk, strokeWidth: 2.1),
        ),
        Positioned(
          top: 32,
          child: CustomPaint(size: const Size(10, 6), painter: _TailPainter()),
        ),
      ]),
    );
  }
}

class _TailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
        Path()
          ..moveTo(0, 0)
          ..lineTo(size.width, 0)
          ..lineTo(size.width / 2, size.height)
          ..close(),
        Paint()..color = Boarding.pearlBottom);
  }

  @override
  bool shouldRepaint(_TailPainter old) => false;
}

class _Label extends StatelessWidget {
  const _Label({required this.title, required this.detail});
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 11, 7),
      decoration: BoxDecoration(
        color: const Color(0xD9111C29),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x26FFFFFF)),
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Boarding.heading)),
            Text(detail,
                style: const TextStyle(fontSize: 11, color: Boarding.muted)),
          ]),
    );
  }
}

class _PrayerCard extends StatelessWidget {
  const _PrayerCard();

  @override
  Widget build(BuildContext context) {
    return NightGlass(
      deep: true,
      radius: 18,
      padding: const EdgeInsets.fromLTRB(12, 10, 14, 11),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: Boarding.accentSoft,
              borderRadius: BorderRadius.circular(10)),
          child:
              const Lucide(LucideIcons.moon, size: 17, color: Boarding.accent),
        ),
        const SizedBox(width: 10),
        Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('NEXT PRAYER',
                  style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: Boarding.faint)),
              const SizedBox(height: 2),
              Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    const Text('Asr',
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Boarding.heading)),
                    const SizedBox(width: 8),
                    Text('15:42',
                        style: Boarding.monoStyle(15, color: Boarding.ink)),
                  ]),
            ]),
      ]),
    );
  }
}

class _Weather extends StatelessWidget {
  const _Weather();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
      decoration: BoxDecoration(
        color: const Color(0x990B1521),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x24FFFFFF)),
      ),
      child: const Row(mainAxisSize: MainAxisSize.min, children: [
        Lucide(LucideIcons.sun,
            size: 15, color: Boarding.accent, strokeWidth: 2.2),
        SizedBox(width: 6),
        Text('21°',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Boarding.heading)),
        SizedBox(width: 5),
        Text('Clear', style: TextStyle(fontSize: 12, color: Boarding.muted)),
      ]),
    );
  }
}
