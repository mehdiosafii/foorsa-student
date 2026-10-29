/// Camera: what the app's scanner does with a paper (guided_scan_page.dart,
/// and the portal's main scan). A passport page lies tilted on a desk; the
/// corner brackets look for it, lock on its edges, a beam reads it, and the
/// page comes up flat and white, text checked. The passport is a specimen
/// with made-up details.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'boarding_style.dart';
import 'lucide.dart';

const _pageSize = Size(300, 212);

class ScanScene extends StatefulWidget {
  const ScanScene({super.key, required this.still, required this.feel});
  final bool still;
  final Feel feel;

  @override
  State<ScanScene> createState() => _ScanSceneState();
}

class _ScanSceneState extends State<ScanScene>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final ValueNotifier<double> _t = ValueNotifier<double>(0);
  bool _felt = false;

  static const loop = 6.6;

  @override
  void initState() {
    super.initState();
    if (widget.still) {
      _t.value = 4.6;
    } else {
      _ticker.start();
    }
  }

  void _tick(Duration elapsed) {
    final t = elapsed.inMicroseconds / 1e6;
    _t.value = t % loop;
    // The lock is felt once, the first time.
    if (!_felt && t >= 1.52) {
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

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          'A passport page being scanned: edges found, straightened, text checked',
      excludeSemantics: true,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Boarding.glassEdge),
              ),
              child: Stack(fit: StackFit.expand, children: [
                RepaintBoundary(
                    child: CustomPaint(
                        painter: _ScanPainter(
                            _t, DefaultTextStyle.of(context).style))),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 16,
                  child: Center(child: _ScanStatus(t: _t)),
                ),
                Positioned(
                  left: 14,
                  top: 14,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(9, 6, 11, 6),
                    decoration: BoxDecoration(
                      color: const Color(0x8C0B1521),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: const Color(0x24FFFFFF)),
                    ),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Lucide(LucideIcons.scanLine,
                          size: 14, color: Boarding.accent),
                      SizedBox(width: 6),
                      Text('Passport',
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: Boarding.ink)),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// The line under the viewfinder, as the scanner's guidance reads.
class _ScanStatus extends StatelessWidget {
  const _ScanStatus({required this.t});
  final ValueNotifier<double> t;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: t,
      builder: (context, t, _) {
        final (label, done) = switch (t) {
          < 1.5 => ('Looking for the page…', false),
          < 2.0 => ('Edges found', false),
          < 3.0 => ('Reading…', false),
          < 3.8 => ('Straightening…', false),
          < 6.0 => ('Text checked', true),
          _ => ('Looking for the page…', false),
        };
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: Container(
            key: ValueKey(label),
            padding: const EdgeInsets.fromLTRB(12, 8, 14, 8),
            decoration: BoxDecoration(
              color: done ? const Color(0xE6103326) : const Color(0xCC0B1521),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                  color:
                      done ? const Color(0x666EE7B7) : const Color(0x29FFFFFF)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (done) ...[
                const Lucide(LucideIcons.circleCheck,
                    size: 15, color: Boarding.done, strokeWidth: 2.4),
                const SizedBox(width: 7),
              ],
              Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: done ? Boarding.done : Boarding.ink)),
            ]),
          ),
        );
      },
    );
  }
}

double _ease(double x) => 1 - math.pow(1 - x.clamp(0.0, 1.0), 3).toDouble();
double _smooth(double x) {
  final t = x.clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// A spring's landing (damping ~0.7): overshoots a touch and settles.
double _springy(double x) {
  final t = x.clamp(0.0, 1.0);
  return 1 - math.exp(-6.5 * t) * math.cos(9 * t);
}

class _ScanPainter extends CustomPainter {
  _ScanPainter(this.t, this.base) : super(repaint: t);
  final ValueNotifier<double> t;

  /// The ambient text style: the page's print in the app's own font.
  final TextStyle base;

  static ui.Picture? _page;
  static String? _pageFont;

  ui.Picture _pagePicture() {
    if (_page == null || _pageFont != base.fontFamily) {
      final recorder = ui.PictureRecorder();
      _paintPassportPage(Canvas(recorder), base);
      _page = recorder.endRecording();
      _pageFont = base.fontFamily;
    }
    return _page!;
  }

  Matrix4 _pose(Size size, double flat) {
    final fit = math.min(size.width * 0.84 / _pageSize.width,
        size.height * 0.62 / _pageSize.height);
    // The perspective about the page's centre, not the canvas's corner.
    final perspective = Matrix4.identity()..setEntry(3, 2, 0.0018 * (1 - flat));
    final m = Matrix4.translationValues(
        size.width / 2, size.height * (0.47 - 0.03 * flat), 0)
      ..multiply(perspective)
      ..rotateX(0.66 * (1 - flat))
      ..rotateZ(-0.16 * (1 - flat))
      ..scaleByDouble(
          fit * (0.92 + 0.08 * flat), fit * (0.92 + 0.08 * flat), 1, 1)
      ..translateByDouble(-_pageSize.width / 2, -_pageSize.height / 2, 0, 1);
    return m;
  }

  List<Offset> _corners(Matrix4 m) => [
        MatrixUtils.transformPoint(m, Offset.zero),
        MatrixUtils.transformPoint(m, Offset(_pageSize.width, 0)),
        MatrixUtils.transformPoint(
            m, Offset(_pageSize.width, _pageSize.height)),
        MatrixUtils.transformPoint(m, Offset(0, _pageSize.height)),
      ];

  @override
  void paint(Canvas canvas, Size size) {
    final time = t.value;
    // The desk under the phone: dark, lit from above.
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFF0D1621));
    canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = ui.Gradient.radial(
              Offset(size.width * 0.5, size.height * 0.42), size.width * 0.75, [
            const Color(0xFF2A3D52),
            const Color(0xFF15212E),
            const Color(0xFF0D1621)
          ], [
            0,
            0.5,
            1
          ]));
    // Wood grain, barely there.
    final grain = Paint()
      ..color = const Color(0x08FFFFFF)
      ..strokeWidth = 1;
    for (var i = 0; i < 26; i++) {
      final y = size.height * (i / 26);
      final path = Path()..moveTo(0, y);
      for (var x = 0.0; x <= size.width; x += 12) {
        path.lineTo(x, y + math.sin(x / 47 + i * 1.7) * 3);
      }
      canvas.drawPath(path, grain..style = PaintingStyle.stroke);
    }

    final flat =
        _smooth((time - 2.95) / 0.85) * (1 - _smooth((time - 5.95) / 0.6));
    final reset = _smooth((time - 5.95) / 0.6);
    final m = _pose(size, flat);
    final corners = _corners(m);

    // The page's shadow, soft when tilted and crisp once flat.
    final shadowPath = Path()
      ..addPolygon(
          corners.map((c) => c + Offset(0, 10 - 6 * flat)).toList(), true);
    canvas.drawPath(
        shadowPath,
        Paint()
          ..color = Color.fromRGBO(0, 0, 0, 0.45 - 0.1 * flat)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 16 - 9 * flat));

    canvas.save();
    canvas.transform(m.storage);
    canvas.drawPicture(_pagePicture());
    // The flatbed white of a cleaned scan.
    if (flat > 0) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Offset.zero & _pageSize, const Radius.circular(7)),
          Paint()..color = Color.fromRGBO(255, 255, 255, 0.22 * flat));
    }
    canvas.restore();

    // The brackets: wandering while they look, then on the corners.
    final lock = _springy((time - 1.5) / 0.55) * (1 - reset);
    final looking = 1 - lock;
    final centre = Offset(size.width / 2, size.height * 0.47);
    final search = <Offset>[];
    for (var i = 0; i < 4; i++) {
      final base = [
        Offset(-size.width * 0.36, -size.height * 0.27),
        Offset(size.width * 0.36, -size.height * 0.27),
        Offset(size.width * 0.36, size.height * 0.27),
        Offset(-size.width * 0.36, size.height * 0.27),
      ][i];
      final wobble = Offset(math.sin(time * 2.3 + i * 1.9) * 9,
          math.cos(time * 1.9 + i * 2.6) * 7);
      search.add(centre + base * (0.96 + 0.04 * math.sin(time * 3)) + wobble);
    }
    final at = [
      for (var i = 0; i < 4; i++) Offset.lerp(search[i], corners[i], lock)!
    ];

    final checked = _smooth((time - 3.7) / 0.3) * (1 - reset);
    final bracketColor = Color.lerp(
        Color.lerp(const Color(0xF2FFFFFF), Boarding.accent,
            _smooth((time - 1.5) / 0.3)),
        Boarding.done,
        checked)!;

    if (lock > 0.6) {
      final quad = Path()..addPolygon(at, true);
      final show = ((lock - 0.6) / 0.4).clamp(0.0, 1.0);
      canvas.drawPath(
          quad, Paint()..color = bracketColor.withValues(alpha: 0.09 * show));
      canvas.drawPath(
          quad,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..color = bracketColor.withValues(alpha: 0.75 * show));
    }

    // The beam reading the page.
    final beam = (time - 2.0) / 0.95;
    if (beam > 0 && beam < 1) {
      final b = _ease(beam);
      final left = Offset.lerp(at[0], at[3], b)!;
      final right = Offset.lerp(at[1], at[2], b)!;
      final normal = Offset(0, 1) * 16;
      final band = Path()
        ..addPolygon([
          left - normal,
          right - normal,
          right + normal * 0.3,
          left + normal * 0.3
        ], true);
      canvas.drawPath(
          band,
          Paint()
            ..shader = ui.Gradient.linear(left - normal, left + normal * 0.3,
                [const Color(0x00A9C8E6), const Color(0x55A9C8E6)]));
      canvas.drawLine(
          left,
          right,
          Paint()
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round
            ..color = const Color(0xE6E9F4FF));
    }

    final arm = 20.0 * (0.85 + 0.15 * looking);
    final pen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = bracketColor;
    for (var i = 0; i < 4; i++) {
      final here = at[i];
      final toNext = at[(i + 1) % 4] - here;
      final toPrev = at[(i + 3) % 4] - here;
      final a = here + toNext / toNext.distance * arm;
      final c = here + toPrev / toPrev.distance * arm;
      canvas.drawPath(
          Path()
            ..moveTo(a.dx, a.dy)
            ..lineTo(here.dx, here.dy)
            ..lineTo(c.dx, c.dy),
          pen);
    }
  }

  @override
  bool shouldRepaint(_ScanPainter old) => old.t != t || old.base != base;
}

TextStyle _print = const TextStyle();

TextPainter _text(String text, double size,
    {Color color = const Color(0xFF2D332F),
    FontWeight weight = FontWeight.w500,
    double spacing = 0,
    bool mono = false,
    TextDirection direction = TextDirection.ltr}) {
  return TextPainter(
    text: TextSpan(
      text: text,
      style: _print.copyWith(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: spacing,
        fontFamily: mono ? Boarding.mono : _print.fontFamily,
        fontFamilyFallback:
            mono ? Boarding.monoFallback : _print.fontFamilyFallback,
        height: 1.1,
        decoration: TextDecoration.none,
      ),
    ),
    textDirection: direction,
  )..layout();
}

/// A Moroccan passport's data page, made up and marked as a specimen.
void _paintPassportPage(Canvas canvas, TextStyle base) {
  _print = TextStyle(
      fontFamily: base.fontFamily, fontFamilyFallback: base.fontFamilyFallback);
  final page = Offset.zero & _pageSize;
  final shape = RRect.fromRectAndRadius(page, const Radius.circular(7));
  canvas.drawRRect(
      shape,
      Paint()
        ..shader = ui.Gradient.linear(page.topLeft, page.bottomRight, [
          const Color(0xFFF1EFE6),
          const Color(0xFFE9E8DE),
          const Color(0xFFF2F0E8)
        ], [
          0,
          0.55,
          1
        ]));
  canvas.save();
  canvas.clipRRect(shape);
  // Guilloche: fine waves in two inks.
  final wave = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.45;
  for (var i = 0; i < 34; i++) {
    wave.color = (i.isEven ? const Color(0xFF3F8E8A) : const Color(0xFFB9789A))
        .withValues(alpha: 0.14);
    final path = Path();
    for (var x = 0.0; x <= _pageSize.width; x += 3) {
      final y = 14 +
          i * 5.6 +
          math.sin(x / 19 + i * 0.55) * 3.4 +
          math.sin(x / 7.3 + i) * 0.8;
      x == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(path, wave);
  }
  // A rosette behind the details.
  final rose = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.5
    ..color = const Color(0xFF3F8E8A).withValues(alpha: 0.16);
  final roseCentre = const Offset(236, 92);
  for (var ring = 0; ring < 5; ring++) {
    final path = Path();
    for (var a = 0.0; a <= math.pi * 2 + 0.01; a += 0.04) {
      final r = 24 + ring * 5 + 5 * math.cos(7 * a + ring * 0.6);
      final p = roseCentre + Offset(math.cos(a), math.sin(a)) * r;
      a == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path..close(), rose);
  }

  const teal = Color(0xFF2E6C6E);
  _text('ROYAUME DU MAROC', 7.4,
          color: teal, weight: FontWeight.w700, spacing: 0.9)
      .paint(canvas, const Offset(14, 11));
  _text('KINGDOM OF MOROCCO', 5.8,
          color: teal, weight: FontWeight.w600, spacing: 0.8)
      .paint(canvas, const Offset(14, 21));
  final arabic = _text('المملكة المغربية', 9,
      color: teal, weight: FontWeight.w700, direction: TextDirection.rtl);
  arabic.paint(canvas, Offset(_pageSize.width - 14 - arabic.width, 10));
  _text('PASSEPORT · PASSPORT', 5.4,
          color: const Color(0xFF6D7470), spacing: 0.6)
      .paint(canvas, const Offset(14, 31));

  // The photo.
  final photo = RRect.fromRectAndRadius(
      const Rect.fromLTWH(14, 42, 64, 84), const Radius.circular(3));
  canvas.drawRRect(
      photo,
      Paint()
        ..shader = ui.Gradient.linear(
            photo.outerRect.topLeft,
            photo.outerRect.bottomRight,
            [const Color(0xFFDCD9D0), const Color(0xFFC2C6BF)]));
  canvas.save();
  canvas.clipRRect(photo);
  final person = Paint()..color = const Color(0xFF9EA39C);
  canvas.drawCircle(const Offset(46, 74), 13.5, person);
  canvas.drawOval(const Rect.fromLTWH(22, 92, 48, 46), person);
  canvas.restore();

  void field(String label, String value, Offset at, {double size = 8.6}) {
    _text(label, 4.9, color: const Color(0xFF6D7470), spacing: 0.2)
        .paint(canvas, at);
    _text(value, size, mono: true, weight: FontWeight.w600, spacing: 0.4)
        .paint(canvas, at + const Offset(0, 6.5));
  }

  field('Type', 'P', const Offset(90, 44));
  field('Code', 'MAR', const Offset(118, 44));
  field('No. du passeport / Passport No.', 'AB1234567', const Offset(160, 44));
  field('Nom / Surname', 'STUDENT', const Offset(90, 64));
  field('Prénoms / Given names', 'FOORSA', const Offset(90, 83));
  field('Nationalité / Nationality', 'MAROCAINE', const Offset(90, 102));
  field(
      'Date de naissance / Date of birth', '01 JAN 2006', const Offset(90, 121),
      size: 8);
  field('Sexe / Sex', 'F', const Offset(196, 121), size: 8);
  field("Date d'expiration / Date of expiry", '01 JAN 2034',
      const Offset(90, 140),
      size: 8);

  // SPECIMEN across the details, as sample documents carry it.
  canvas.save();
  canvas.translate(178, 118);
  canvas.rotate(-0.3);
  final specimen = _text('SPECIMEN', 21,
      color: const Color(0xFFC0392B).withValues(alpha: 0.28),
      weight: FontWeight.w800,
      spacing: 3);
  specimen.paint(canvas, Offset(-specimen.width / 2, -specimen.height / 2));
  canvas.restore();

  // The machine-readable zone.
  canvas.drawRect(const Rect.fromLTWH(0, 164, 300, 48),
      Paint()..color = const Color(0x66FFFFFF));
  _text('P<MARSTUDENT<<FOORSA<<<<<<<<<<<<<<<<<<<<<<<<', 7.9,
          mono: true, weight: FontWeight.w600, spacing: 0.6)
      .paint(canvas, const Offset(12, 172));
  _text('AB12345674MAR0601014F3401011<<<<<<<<<<<<<<06', 7.9,
          mono: true, weight: FontWeight.w600, spacing: 0.6)
      .paint(canvas, const Offset(12, 188));
  canvas.restore();
}
