/// The camera: a passport page held up at an angle, the scanner's four
/// corners finding it, and the page straightening out flat, the way the app's
/// scanner straightens a paper. The page is a drawing, not a real passport:
/// a photo, a few lines and a machine-readable zone made up for a student
/// called Foorsa.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'boarding_style.dart';
import 'stage_forms.dart';

/// One pass of the scene, in seconds; it then starts again.
const _cycle = 6.0;

class ScanScene extends StatefulWidget {
  const ScanScene({super.key, required this.still, required this.feel});
  final bool still;
  final Feel feel;

  @override
  State<ScanScene> createState() => _ScanSceneState();
}

class _ScanSceneState extends State<ScanScene>
    with SingleTickerProviderStateMixin, SceneClock<ScanScene> {
  @override
  void initState() {
    super.initState();
    startClock(still: widget.still);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'A passport page being scanned and straightened',
      excludeSemantics: true,
      child: LayoutBuilder(builder: (context, constraints) {
        final width = pageWidth(constraints.maxWidth);
        return Center(
          child: CustomPaint(
            size: Size(width + 80, width * 0.71 + 110),
            painter: _ScanPainter(clock, still: widget.still, page: width),
          ),
        );
      }),
    );
  }
}

class _ScanPainter extends CustomPainter {
  _ScanPainter(this.clock, {required this.still, required this.page})
      : super(repaint: clock);
  final ValueNotifier<double> clock;
  final bool still;

  /// The page's width; a passport page is 125 by 88 mm.
  final double page;

  static final _mrz = [
    'P<MARSTUDENT<<FOORSA'.padRight(44, '<'),
    '${'FS20260011MAR0601012<3601017'.padRight(42, '<')}02',
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final clockNow = clock.value;
    final t = still ? 4.2 : clockNow % _cycle;
    final first = !still && clockNow < _cycle;
    final w = page, h = page * 0.704;
    final centre = size.center(Offset.zero);

    // The pass: the page lies flat where it arrived, is picked up and tipped
    // (the corners lose it), is found again, laid flat and read. It ends
    // flat and found, where the next pass starts.
    final tip = ease(t, 0.6, 1.4) * (1 - ease(t, 2.5, 3.4));
    final lost = ease(t, 0.5, 1.1);
    final found = ease(t, 1.5, 2.2);
    final sheen = ((t - 3.3) / 0.9).clamp(0.0, 1.0);
    final corners0 = first ? ease(t, 0.15, 0.55) : 1.0;

    // The page in space: tipped back and turned, then flat and square.
    final tilt = 0.5 * tip;
    final turn = -0.13 * tip;
    final scale = 1 - 0.1 * tip;
    final rise = 8 * tip;
    final m = Matrix4.identity()
      ..translateByDouble(centre.dx, centre.dy + rise, 0, 1)
      ..multiply(Matrix4.identity()..setEntry(3, 2, 0.0017))
      ..rotateX(tilt)
      ..rotateZ(turn)
      ..scaleByDouble(scale, scale, 1, 1)
      ..translateByDouble(-w / 2, -h / 2, 0, 1);

    Offset project(double x, double y) =>
        MatrixUtils.transformPoint(m, Offset(x, y));

    final quad = [project(0, 0), project(w, 0), project(w, h), project(0, h)];

    // Its shadow on the stage.
    final bottom = (quad[2].dy + quad[3].dy) / 2;
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(centre.dx, bottom + 22), width: w * 0.86, height: 16),
      Paint()
        ..color = const Color.fromRGBO(0, 0, 0, 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );

    canvas.save();
    canvas.transform(m.storage);
    _page(canvas, w, h, sheen);
    canvas.restore();

    // The scanner's corners: just outside the page while it has it, wide
    // while it looks for it.
    final looking =
        Rect.fromCenter(center: centre, width: w + 54, height: h + 74);
    final wide = [
      looking.topLeft,
      looking.topRight,
      looking.bottomRight,
      looking.bottomLeft
    ];
    final searching = lost * (1 - found);
    final breathe = still ? 0.0 : math.sin(t * 3.2) * 3 * searching;
    const outset = 9.0;
    final signs = const [
      Offset(-1, -1),
      Offset(1, -1),
      Offset(1, 1),
      Offset(-1, 1),
    ];
    final corners = [
      for (var i = 0; i < 4; i++)
        Offset.lerp(quad[i] + signs[i] * outset, wide[i] + signs[i] * breathe,
            searching)!,
    ];
    final ink = Color.fromRGBO(244, 247, 251, 0.95 * corners0);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = ink;
    for (var i = 0; i < 4; i++) {
      final here = corners[i];
      final along = corners[(i + 1) % 4];
      final back = corners[(i + 3) % 4];
      final arm = 20.0;
      final a = here + _unit(along - here) * arm;
      final b = here + _unit(back - here) * arm;
      canvas.drawPath(
          Path()
            ..moveTo(a.dx, a.dy)
            ..lineTo(here.dx, here.dy)
            ..lineTo(b.dx, b.dy),
          stroke);
    }
  }

  static Offset _unit(Offset o) => o / math.max(o.distance, 0.001);

  void _page(Canvas canvas, double w, double h, double sheen) {
    final card = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, h), Radius.circular(w * 0.035));
    canvas.drawRRect(
      card,
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, Offset(w, h), const [
          Color(0xFFF7F5EF),
          Color(0xFFEDE9DF),
        ]),
    );
    canvas.save();
    canvas.clipRRect(card);
    final u = w / 250;

    // The title band.
    final faint = Paint()..color = const Color(0xFFDCD6CA);
    final mid = Paint()..color = const Color(0xFFC3BCAE);
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(16 * u, 14 * u, 78 * u, 5 * u),
            Radius.circular(3 * u)),
        mid);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(w - 54 * u, 14 * u, 38 * u, 5 * u),
            Radius.circular(3 * u)),
        faint);

    // The photo.
    final photo = Rect.fromLTWH(16 * u, 30 * u, 56 * u, 72 * u);
    canvas.drawRRect(RRect.fromRectAndRadius(photo, Radius.circular(4 * u)),
        Paint()..color = const Color(0xFFD3DAE2));
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(photo, Radius.circular(4 * u)));
    final person = Paint()..color = const Color(0xFFB3BECA);
    canvas.drawCircle(photo.center + Offset(0, -10 * u), 13 * u, person);
    canvas.drawOval(
        Rect.fromCenter(
            center: Offset(photo.center.dx, photo.bottom + 6 * u),
            width: 50 * u,
            height: 46 * u),
        person);
    canvas.restore();

    // The fields: a label and its value, four times.
    const values = [92.0, 64.0, 78.0, 54.0];
    for (var i = 0; i < 4; i++) {
      final y = (32 + i * 18) * u;
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(84 * u, y, 26 * u, 3 * u), Radius.circular(2 * u)),
          faint);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(84 * u, y + 6 * u, values[i] * u, 5 * u),
              Radius.circular(3 * u)),
          mid);
    }

    // The machine-readable zone.
    final style = Boarding.monoStyle(7.05 * u,
        color: const Color(0xFF8C877D), weight: FontWeight.w500, spacing: 0);
    for (var i = 0; i < _mrz.length; i++) {
      final painter = TextPainter(
        text: TextSpan(text: _mrz[i], style: style),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: w - 24 * u);
      painter.paint(canvas, Offset(14 * u, h - (30 - i * 11) * u));
    }

    // Light runs across it once it lies flat.
    if (sheen > 0 && sheen < 1) {
      final x =
          ui.lerpDouble(-w * 0.5, w * 1.5, Curves.easeInOut.transform(sheen))!;
      canvas.drawRect(
        Rect.fromLTWH(0, 0, w, h),
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = ui.Gradient.linear(
              Offset(x - w * 0.3, 0), Offset(x + w * 0.1, h), const [
            Color(0x00FFFFFF),
            Color(0x40FFFFFF),
            Color(0x00FFFFFF),
          ], const [
            0,
            0.5,
            1
          ]),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ScanPainter old) =>
      old.still != still || old.page != page || old.clock != clock;
}
