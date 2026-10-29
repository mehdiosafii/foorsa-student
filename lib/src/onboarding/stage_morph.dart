/// The transition between two steps: the object on the stage folds into the
/// arrow, the arrow catches the light, and it unfolds into the next object.
/// Drawn as outlines (stage_forms.dart) in the objects' own glass, the
/// arrow's pearl at the middle, so the old object and the new one are the
/// same thing changing.
///
/// When the runway's arrow flies in ([ghost]), the object folds into an
/// arrow made of light, only its edge and a breath of its face, and the
/// flying arrow docks into it: from then on the arrow is solid pearl.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'glass.dart';
import 'glass_arrow.dart';
import 'shape_morph.dart';
import 'stage_forms.dart';

/// The arrow's height on the stage.
const stageArrowHeight = 84.0;

/// When the old object has become the arrow, and when the arrow starts to
/// become the new one, as parts of the transition.
const arrowAt = 0.46;
const arrowLeaves = 0.56;

/// The arrow made of light the object folds into, for the flying arrow to
/// dock in: the pearl's edge, a faint face.
final Glass _ghost = Glass.lerp(
    Glass.pearl,
    const Glass(
      fill: [Color(0x40FFFFFF), Color(0x1AEBF1F7), Color(0x0DBCCAD9)],
      fillAngle: 145,
      rim: [Color(0xFFFFFFFF), Color(0x99FFFFFF), Color(0x40FFFFFF)],
      rimWidth: 1.4,
      wall: Color(0x00FFFFFF),
      highlight: GlassShadow(Color(0x66FFFFFF), dx: 1.2, dy: 1.8, blur: 2),
      glow: GlassShadow(Color(0x00FFFFFF)),
      shadows: [GlassShadow.none, GlassShadow.none, GlassShadow.none],
    ),
    1);

double _inOut(double x) {
  final t = x.clamp(0.0, 1.0);
  return t < 0.5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3) / 2;
}

double _smooth(double x) {
  final t = x.clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

class _Plan {
  _Plan(StageForm from, StageForm to) {
    final pieces = arrowPieces(stageArrowHeight);
    steps = Path();
    for (final step in pieces.sublist(1)) {
      steps.addPath(step, Offset.zero);
    }
    stepCentres = [for (final s in pieces.sublist(1)) s.getBounds().center];
    stepPieces = pieces.sublist(1);
    final arrow = outlineOf(pieces.first, count: 320);
    fromOutline = outlineOf(from.path, count: 320);
    arrowIn = alignTo(fromOutline, arrow);
    arrowOut = arrow;
    toOutline = alignTo(arrow, outlineOf(to.path, count: 320));
  }

  late final List<Offset> fromOutline;
  late final List<Offset> arrowIn;
  late final List<Offset> arrowOut;
  late final List<Offset> toOutline;
  late final Path steps;
  late final List<Path> stepPieces;
  late final List<Offset> stepCentres;
}

final Map<String, _Plan> _plans = {};

/// The outline [main] and the arrow's steps grown to [steps] (0 to 1), as one
/// piece of glass: one light across all of it, as the arrow is drawn.
GlassShape _pieces(List<Offset> main, _Plan plan, double steps) {
  final path = Path()..addPolygon(main, true);
  final grown = Path();
  if (steps > 0.01) {
    for (var i = 0; i < plan.stepPieces.length; i++) {
      final c = plan.stepCentres[i];
      // A step grows out of, and shrinks back into, the arrow's middle.
      final at = Offset.lerp(Offset.zero, c, 0.4 + 0.6 * steps)!;
      final matrix = Matrix4.identity()
        ..translateByDouble(at.dx, at.dy, 0, 1)
        ..scaleByDouble(steps, steps, 1, 1)
        ..translateByDouble(-c.dx, -c.dy, 0, 1);
      grown.addPath(plan.stepPieces[i].transform(matrix.storage), Offset.zero);
    }
    path.addPath(grown, Offset.zero);
  }
  return GlassShape.withGrow(path, (d) {
    final out = Path()..addPolygon(offsetOutline(main, d), true);
    if (steps > 0.01) out.addPath(grown, Offset.zero);
    return out;
  });
}

class StageMorphPainter extends CustomPainter {
  StageMorphPainter(
      {required this.from,
      required this.to,
      required this.progress,
      this.toArrow = false,
      this.ghost = false})
      : super(repaint: progress);

  final StageForm from;
  final StageForm to;

  /// Only the first half: [from] becomes the arrow over the whole progress
  /// and stays it, for the arrow the sign-in is handed.
  final bool toArrow;

  /// A flying arrow docks in the middle: [from] folds into an arrow of light
  /// rather than a solid one.
  final bool ghost;

  /// 0 to 1 over the whole transition.
  final Animation<double> progress;

  _Plan get _plan =>
      _plans.putIfAbsent('${from.shape}|${to.shape}', () => _Plan(from, to));

  @override
  void paint(Canvas canvas, Size size) {
    final m = progress.value;
    if (m >= 1) return;
    final plan = _plan;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);

    // The arrow's moment: it swells a little and the light crosses it.
    final beat = toArrow
        ? 0.0
        : ((m - arrowAt + 0.02) / (arrowLeaves - arrowAt + 0.08))
            .clamp(0.0, 1.0);
    final pulse = 1 + 0.05 * math.sin(math.pi * beat);
    canvas.scale(pulse);

    late final List<Offset> main;
    late final Glass glass;
    late final double steps;
    late final double change;
    late final double scale;
    late final double glow;
    final arrowGlass = Glass.pearl;
    if (toArrow || m < arrowAt) {
      // A breath before it moves, while the old object fades over it.
      final a = toArrow ? _inOut(m) : _inOut((m - 0.05) / (arrowAt - 0.05));
      main = a >= 1 ? plan.arrowIn : lerpOutlinePoints(plan.fromOutline, plan.arrowIn, a);
      glass = Glass.lerp(from.glass, ghost ? _ghost : arrowGlass,
          _smooth(a * 1.25));
      steps = _smooth((a - 0.55) / 0.45);
      change = math.sin(math.pi * a);
      scale = ui.lerpDouble(1, stageArrowHeight / 100, a)!;
      glow = (ghost ? 0.45 : 0.8) * _smooth((a - 0.45) / 0.55);
    } else if (m < arrowLeaves) {
      main = plan.arrowOut;
      glass = arrowGlass;
      steps = 1;
      change = 0;
      scale = stageArrowHeight / 100;
      glow = 0.8;
    } else {
      final b = _inOut((m - arrowLeaves) / (1 - arrowLeaves - 0.06));
      main = b >= 1 ? plan.toOutline : lerpOutlinePoints(plan.arrowOut, plan.toOutline, b);
      glass = Glass.lerp(arrowGlass, to.glass, _smooth(b * 1.2 - 0.1));
      steps = 1 - _smooth(b / 0.4);
      change = math.sin(math.pi * b);
      scale = ui.lerpDouble(stageArrowHeight / 100, 1, b)!;
      glow = 0.8 * (1 - _smooth(b / 0.5));
    }
    // The outline gives way to the new object once it is there.
    final fade = toArrow ? 1.0 : 1 - _smooth((m - 0.93) / 0.07);

    canvas.saveLayer(Rect.fromCircle(center: Offset.zero, radius: 600),
        Paint()..color = Color.fromRGBO(255, 255, 255, fade));
    paintArrowGlow(canvas, 92 * stageArrowHeight / 100, glow);
    final shape = _pieces(main, plan, steps);
    // Mid-change it glows and softens, as if made of light for a moment.
    final light = glass.fill[0].computeLuminance();
    if (change > 0.02 && light > 0.3) {
      canvas.drawPath(
          shape.path,
          Paint()
            ..color = Color.fromRGBO(200, 225, 250, 0.32 * change * light)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, 12 * change));
    }
    paintGlassBody(canvas, shape, glass, scale: scale);
    // Light runs across the arrow, the way it points.
    if (beat > 0 && beat < 1) {
      final along = ui.lerpDouble(-70, 70, Curves.easeInOut.transform(beat))!;
      canvas.save();
      canvas.clipPath(shape.path);
      canvas.drawRect(
        const Rect.fromLTWH(-80, -80, 160, 160),
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = ui.Gradient.linear(
            Offset(along - 22, -along - 22) * 0.7,
            Offset(along + 22, -along + 22) * 0.7,
            const [Color(0x00FFFFFF), Color(0x80FFFFFF), Color(0x00FFFFFF)],
            const [0, 0.5, 1],
          ),
      );
      canvas.restore();
    }
    paintGlassRim(canvas, shape, glass, scale: scale);
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(StageMorphPainter old) =>
      old.from != from ||
      old.to != to ||
      old.progress != progress ||
      old.toArrow != toArrow ||
      old.ghost != ghost;
}

/// The arrow alone on the stage, [height] tall, [offset] from the stage's
/// middle: on its way to the sign-in's own arrow.
class ArrowPainter extends CustomPainter {
  ArrowPainter({required this.offset, required this.height, this.glow = 1});
  final Offset offset;
  final double height;
  final double glow;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2 + offset.dx, size.height / 2 + offset.dy);
    paintGlassArrow(canvas, height: height, glow: 0.8 * glow);
    canvas.restore();
  }

  @override
  bool shouldRepaint(ArrowPainter old) =>
      old.offset != offset || old.height != height || old.glow != glow;
}
