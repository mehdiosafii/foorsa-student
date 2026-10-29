/// The journey's airliner, the one the portal flies along My journey
/// (JourneyFlightCraft.tsx in foorsa-reward), drawn natively from the same
/// paths in its 180 x 180 box.
///
/// [AirlinerPainter.assembly] is that component's `progress`: at 0 it is the
/// Foorsa F mark, and as it runs to 1 the body, the wings, the tail and the
/// engines fly out of the mark into place, with the same curves and the same
/// offsets as the web, so the opening of the onboarding is the portal's own
/// brand moment. [AirlinerSilhouette] is the plane as one flat shape, for the
/// small plane on the progress line.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'brand_vectors.dart';
import 'svg_path.dart';

double _clamp(double v) => v.clamp(0.0, 1.0);

/// smoothstep between [from] and [to], as `phase()` in the web component.
double _phase(double v, double from, double to) {
  final t = _clamp((v - from) / (to - from));
  return t * t * (3 - 2 * t);
}

double _mix(double from, double to, double amount) =>
    from + (to - from) * amount;

const _navy = [
  Color(0xFF7CC4DE),
  Color(0xFF2C7CA4),
  Color(0xFF0B456E),
  Color(0xFF061E36)
];
const _navyStops = [0.0, 0.2, 0.54, 1.0];
const _deep = [Color(0xFF4F91B2), Color(0xFF123F61), Color(0xFF05192B)];
const _deepStops = [0.0, 0.42, 1.0];
const _silver = [
  Color(0xFF526D80),
  Color(0xFFC6D6DF),
  Color(0xFFF8FCFD),
  Color(0xFFA8BDCA),
  Color(0xFFEEF5F7),
  Color(0xFF425B6E),
];
const _silverStops = [0.0, 0.17, 0.43, 0.58, 0.78, 1.0];
const _glass = [Color(0xFFD7F8FF), Color(0xFF62C5DF), Color(0xFF092B47)];
const _glassStops = [0.0, 0.35, 1.0];

/// The dark variant of the F mark's fill (`journey-flight-craft--dark`).
const _markColors = [
  Color(0xFFF0FBFF),
  Color(0xFF82CBE2),
  Color(0xFF2580AA),
  Color(0xFF0B426C)
];
const _markStops = [0.0, 0.33, 0.68, 1.0];

enum _Fill { navy, deep, silver, glass }

Shader _shader(_Fill fill, Rect box) {
  switch (fill) {
    case _Fill.navy:
      return LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _navy,
              stops: _navyStops)
          .createShader(box);
    case _Fill.deep:
      return LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: _deep,
              stops: _deepStops)
          .createShader(box);
    case _Fill.silver:
      return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: _silver,
              stops: _silverStops)
          .createShader(box);
    case _Fill.glass:
      return LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: _glass,
              stops: _glassStops)
          .createShader(box);
  }
}

// The component's paths, verbatim.
const _plateF = 'M71 26h58l-5 19H92v22h27l-5 18H92v60H72V26Z';
const _plateDiamonds =
    'm57 76 12 12-12 12-12-12 12-12Zm-14 31 12 12-12 12-12-12 12-12Z';
const _wingL = 'M84 69 27 91 13 107l7 8 64-20Z';
const _wingLEdge = 'M84 69 27 91 17 101l64-20Z';
const _wingLFlap = 'm29 96-16 11 7 8 28-9Z';
const _wingLLines = 'm48 84 1 22M65 78l2 22M25 106l55-18';
const _wingR = 'm96 69 57 22 14 16-7 8-64-20Z';
const _wingREdge = 'm96 69 57 22 10 10-64-20Z';
const _wingRFlap = 'm151 96 16 11-7 8-28-9Z';
const _wingRLines = 'm132 84-1 22M115 78l-2 22M155 106l-55-18';
const _tailL = 'm86 132-30 17-10 12 39-9Z';
const _tailLEdge = 'm86 132-30 17-5 6 34-12Z';
const _tailLLine = 'm59 149 24-6';
const _tailR = 'm94 132 30 17 10 12-39-9Z';
const _tailREdge = 'm94 132 30 17 5 6-34-12Z';
const _tailRLine = 'm121 149-24-6';
const _engineL = 'M50 88c0-5 3-8 7-8s7 3 7 8l-2 28c0 5-2 8-5 8s-5-3-5-8Z';
const _engineLLines = 'M52 105h10M52 114h10';
const _engineR = 'M116 88c0-5 3-8 7-8s7 3 7 8l-2 28c0 5-2 8-5 8s-5-3-5-8Z';
const _engineRLines = 'M118 105h10M118 114h10';
const _bodyOuter =
    'M90 9c-9 12-14 32-14 58l5 76 9 26 9-26 5-76c0-26-5-46-14-58Z';
const _bodyInner = 'M90 14c-5 13-7 35-6 65l3 64 3 15 3-15 3-64c1-30-1-52-6-65Z';
const _canopy = 'm90 28-8 14 1 11 7-5 7 5 1-11Z';
const _canopyLines = 'M90 29v19M83 42l7 6 7-6';
const _bodyLines = 'M78 65h24M79 81h22M81 119h18M83 141h14';
const _rivets = 'M82 72h2M96 72h2M83 93h2M95 93h2M84 109h2M94 109h2';
const _highlights = 'M82 57c1-20 4-33 8-41M21 106l59-19M100 87l59 19';

/// The airliner in its 180 x 180 box, scaled to [size]. The nose points up.
class AirlinerPainter extends CustomPainter {
  AirlinerPainter({this.assembly = 1, this.glow = 1, this.shadow = true});

  /// 0: the F mark; 1: the assembled plane (the web component's progress).
  final double assembly;

  /// The dark theme's cyan halo, 0 to 1.
  final double glow;

  /// The contact shadow under the plane.
  final bool shadow;

  @override
  void paint(Canvas canvas, Size size) {
    final v = _clamp(assembly);
    final body = _phase(v, 0.03, 0.62);
    final wings = _phase(v, 0.1, 0.76);
    final tail = _phase(v, 0.24, 0.82);
    final finish = _phase(v, 0.58, 1);
    final markOpacity = 1 - _phase(v, 0.14, 0.52);
    final machineOpacity = _phase(v, 0.015, 0.2);
    final plateOpacity = _mix(0.18, 0, _phase(v, 0.34, 0.76));
    final engineOpacity = _phase(v, 0.36, 0.72);
    final engineScale = _mix(0.44, 1, _phase(v, 0.31, 0.8));
    final machineScale = _mix(0.89, 1, body);

    canvas.save();
    canvas.scale(size.width / 180, size.height / 180);

    if (markOpacity > 0.001) _paintMark(canvas, markOpacity);

    if (machineOpacity > 0.001) {
      canvas.saveLayer(const Rect.fromLTWH(-40, -40, 260, 260),
          Paint()..color = Color.fromRGBO(255, 255, 255, machineOpacity));
      canvas.translate(90, 90);
      canvas.scale(machineScale);
      canvas.translate(-90, -90);

      void part(Offset origin, double dx, double dy, double degrees, double sx,
          double sy, void Function() draw) {
        canvas.save();
        canvas.translate(origin.dx + dx, origin.dy + dy);
        canvas.rotate(degrees * math.pi / 180);
        canvas.scale(sx, sy);
        canvas.translate(-origin.dx, -origin.dy);
        draw();
        canvas.restore();
      }

      final lineOpacity = 0.16 + finish * 0.66;
      final edgeOpacity = 0.38 + wings * 0.62;
      final flapOpacity = 0.5 + wings * 0.5;

      // Shadow and halo first, under everything, from the assembled outline.
      if (shadow || glow > 0) {
        final silhouette = Path()
          ..addPath(svgPath(_bodyOuter), Offset.zero)
          ..addPath(svgPath(_wingL), Offset.zero)
          ..addPath(svgPath(_wingR), Offset.zero)
          ..addPath(svgPath(_tailL), Offset.zero)
          ..addPath(svgPath(_tailR), Offset.zero);
        final settled = _phase(v, 0.55, 1);
        if (shadow && settled > 0) {
          canvas.drawPath(
              silhouette.shift(const Offset(0, 4)),
              Paint()
                ..color = Color.fromRGBO(3, 21, 34, 0.36 * settled)
                ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5));
        }
        if (glow > 0 && settled > 0) {
          canvas.drawPath(
              silhouette,
              Paint()
                ..color = Color.fromRGBO(69, 210, 255, 0.16 * glow * settled)
                ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
        }
      }

      if (plateOpacity > 0.001) {
        _fill(canvas, _plateF, _Fill.navy, opacity: plateOpacity);
        _fill(canvas, _plateDiamonds, _Fill.navy, opacity: plateOpacity);
      }

      final w = wings;
      part(const Offset(83, 82), _mix(41, 0, w), _mix(-26, 0, w),
          _mix(72, 0, w), _mix(0.24, 1, w), _mix(0.66, 1, w), () {
        _fill(canvas, _wingL, _Fill.navy);
        _fill(canvas, _wingLEdge, _Fill.silver, opacity: edgeOpacity);
        _fill(canvas, _wingLFlap, _Fill.deep, opacity: flapOpacity);
        _lines(canvas, _wingLLines, lineOpacity);
      });
      part(const Offset(97, 82), _mix(-17, 0, w), _mix(-26, 0, w),
          _mix(-72, 0, w), _mix(0.24, 1, w), _mix(0.66, 1, w), () {
        _fill(canvas, _wingR, _Fill.navy);
        _fill(canvas, _wingREdge, _Fill.silver, opacity: edgeOpacity);
        _fill(canvas, _wingRFlap, _Fill.deep, opacity: flapOpacity);
        _lines(canvas, _wingRLines, lineOpacity);
      });

      final t = tail;
      final tailScale = _mix(0.42, 1, t);
      part(const Offset(86, 143), _mix(37, 0, t), _mix(-32, 0, t),
          _mix(48, 0, t), tailScale, tailScale, () {
        _fill(canvas, _tailL, _Fill.deep);
        _fill(canvas, _tailLEdge, _Fill.silver);
        _lines(canvas, _tailLLine, lineOpacity);
      });
      part(const Offset(94, 143), _mix(9, 0, t), _mix(-32, 0, t),
          _mix(-48, 0, t), tailScale, tailScale, () {
        _fill(canvas, _tailR, _Fill.deep);
        _fill(canvas, _tailREdge, _Fill.silver);
        _lines(canvas, _tailRLine, lineOpacity);
      });

      if (engineOpacity > 0.001) {
        for (final engine in [
          (const Offset(57, 96), _engineL, _engineLLines, const Offset(57, 88)),
          (
            const Offset(123, 96),
            _engineR,
            _engineRLines,
            const Offset(123, 88)
          ),
        ]) {
          part(engine.$1, 0, 0, 0, engineScale, engineScale, () {
            _fill(canvas, engine.$2, _Fill.silver,
                opacity: engineOpacity,
                stroke: const Color(0xFF18384C),
                strokeWidth: 0.8);
            canvas.drawOval(
                Rect.fromCenter(center: engine.$4, width: 11.4, height: 6),
                Paint()
                  ..color =
                      const Color(0xFF071722).withValues(alpha: engineOpacity));
            canvas.drawOval(
                Rect.fromCenter(center: engine.$4, width: 5.4, height: 2.4),
                Paint()
                  ..color = const Color(0xFF90E6F3)
                      .withValues(alpha: 0.8 * engineOpacity));
            _lines(canvas, engine.$3, lineOpacity * engineOpacity);
          });
        }
      }

      part(const Offset(90, 90), _mix(17, 0, body), _mix(5, 0, body),
          _mix(-7, 0, body), _mix(0.66, 1, body), _mix(0.56, 1, body), () {
        _fill(canvas, _bodyOuter, _Fill.silver,
            stroke: const Color(0xFF21465D), strokeWidth: 1.2);
        _fill(canvas, _bodyInner, _Fill.navy);
        _fill(canvas, _canopy, _Fill.glass,
            stroke: const Color(0xFFBCEBF3), strokeWidth: 0.8);
        _lines(canvas, _canopyLines, 0.22 + finish * 0.58,
            color: const Color(0xFFDCFBFF));
        _lines(canvas, _bodyLines, lineOpacity);
        _lines(canvas, _rivets, lineOpacity, width: 1.25);
      });

      if (finish > 0.001) {
        canvas.drawPath(
            svgPath(_highlights),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.round
              ..strokeWidth = 1.05
              ..color = Color.fromRGBO(234, 250, 255, 0.72 * finish));
        final dot = Paint()
          ..color = const Color(0xFFC9F7FF).withValues(alpha: finish);
        canvas.drawCircle(const Offset(76, 87), 1.3, dot);
        canvas.drawCircle(const Offset(104, 87), 1.3, dot);
      }
      canvas.restore();
    }
    canvas.restore();
  }

  void _paintMark(Canvas canvas, double opacity) {
    // The official mark, 82% of the box and centred, filled with the dark
    // theme's gradient (the web masks its white PNG with it).
    const side = 180 * 0.82;
    const inset = (180 - side) / 2;
    canvas.save();
    canvas.translate(inset, inset);
    canvas.scale(side / 757);
    final mark = svgPath(foorsaMarkPath);
    final bounds = mark.getBounds();
    // A layer fades the gradient: a shader is not dimmed by the paint's alpha
    // on every backend.
    canvas.saveLayer(bounds.inflate(120),
        Paint()..color = Color.fromRGBO(255, 255, 255, opacity));
    canvas.drawPath(
        mark.shift(const Offset(0, 18)),
        Paint()
          ..color = const Color.fromRGBO(10, 37, 57, 0.2)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 40));
    canvas.drawPath(
        mark,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment(-0.82, -1),
            end: Alignment(0.82, 1),
            colors: _markColors,
            stops: _markStops,
          ).createShader(bounds));
    canvas.restore();
    canvas.restore();
  }

  void _fill(Canvas canvas, String data, _Fill fill,
      {double opacity = 1, Color? stroke, double strokeWidth = 1}) {
    final path = svgPath(data);
    final paint = Paint()..shader = _shader(fill, path.getBounds());
    if (opacity < 1) {
      canvas.saveLayer(path.getBounds().inflate(strokeWidth + 1),
          Paint()..color = Color.fromRGBO(255, 255, 255, opacity));
    }
    canvas.drawPath(path, paint);
    if (stroke != null) {
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = strokeWidth
            ..strokeJoin = StrokeJoin.round
            ..color = stroke);
    }
    if (opacity < 1) canvas.restore();
  }

  void _lines(Canvas canvas, String data, double opacity,
      {Color color = const Color(0xFFD5E4EA), double width = 0.8}) {
    if (opacity <= 0.001) return;
    canvas.drawPath(
        svgPath(data),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = width
          ..color = color.withValues(alpha: opacity.clamp(0.0, 1.0)));
  }

  @override
  bool shouldRepaint(AirlinerPainter old) =>
      old.assembly != assembly || old.glow != glow || old.shadow != shadow;
}

/// The airliner as one flat shape in [color], nose up, in its 180 box.
class AirlinerSilhouettePainter extends CustomPainter {
  const AirlinerSilhouettePainter(this.color);
  final Color color;

  static final Path _shape = () {
    final path = Path()..fillType = PathFillType.nonZero;
    for (final d in [
      _bodyOuter,
      _wingL,
      _wingR,
      _tailL,
      _tailR,
      _engineL,
      _engineR
    ]) {
      path.addPath(svgPath(d), Offset.zero);
    }
    return path;
  }();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 180, size.height / 180);
    canvas.drawPath(_shape, Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(AirlinerSilhouettePainter old) => old.color != color;
}
