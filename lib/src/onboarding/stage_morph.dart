/// The transition between two steps: the object on the stage melts into the
/// arrow, the arrow catches the light, and it unfolds into the next object.
/// Drawn as outlines (stage_forms.dart) in the objects' own colours, pearl at
/// the arrow, so the old object and the new one are the same thing changing.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'shape_morph.dart';
import 'stage_forms.dart';

const _pearl = Color(0xFFF4F7FB);

/// The arrow's height on the stage.
const _arrowHeight = 84.0;

/// When the old object has become the arrow, and when the arrow starts to
/// become the new one, as parts of the transition.
const arrowAt = 0.46;
const arrowLeaves = 0.56;

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
    final pieces = arrowPieces(_arrowHeight);
    steps = pieces.sublist(1);
    final arrow = outlineOf(pieces.first, count: 320);
    fromOutline = outlineOf(from.path, count: 320);
    arrowIn = alignTo(fromOutline, arrow);
    arrowOut = arrow;
    toOutline = alignTo(arrow, outlineOf(to.path, count: 320));
    arrowPath = pieces.first;
  }

  late final List<Offset> fromOutline;
  late final List<Offset> arrowIn;
  late final List<Offset> arrowOut;
  late final List<Offset> toOutline;
  late final List<Path> steps;
  late final Path arrowPath;
}

final Map<String, _Plan> _plans = {};

class StageMorphPainter extends CustomPainter {
  StageMorphPainter(
      {required this.from,
      required this.to,
      required this.progress,
      this.toArrow = false})
      : super(repaint: progress);

  final StageForm from;
  final StageForm to;

  /// Only the first half: [from] becomes the arrow over the whole progress
  /// and stays it, for the arrow the sign-in is handed.
  final bool toArrow;

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
        : ((m - arrowAt + 0.06) / (arrowLeaves - arrowAt + 0.12))
            .clamp(0.0, 1.0);
    final pulse = 1 + 0.06 * math.sin(math.pi * beat);
    canvas.scale(pulse);

    late final Path main;
    late final Color color;
    late final double steps;
    late final double change;
    if (toArrow || m < arrowLeaves) {
      // A breath before it moves, while the old object fades over it.
      final a = toArrow ? _inOut(m) : _inOut((m - 0.05) / (arrowAt - 0.05));
      main = a >= 1
          ? plan.arrowPath
          : lerpOutline(plan.fromOutline, plan.arrowIn, a);
      color = Color.lerp(from.color, _pearl, _smooth(a * 1.25))!;
      steps = _smooth((a - 0.55) / 0.45);
      change = math.sin(math.pi * a);
    } else {
      final b = _inOut((m - arrowLeaves) / (1 - arrowLeaves - 0.06));
      main = b >= 1 ? to.path : lerpOutline(plan.arrowOut, plan.toOutline, b);
      color = Color.lerp(_pearl, to.color, _smooth(b * 1.2 - 0.1))!;
      steps = 1 - _smooth(b / 0.4);
      change = math.sin(math.pi * b);
    }
    // The outline gives way to the new object once it is there.
    final fade = toArrow ? 1.0 : 1 - _smooth((m - 0.93) / 0.07);
    final light = color.computeLuminance();

    canvas.saveLayer(Rect.fromCircle(center: Offset.zero, radius: 600),
        Paint()..color = Color.fromRGBO(255, 255, 255, fade));
    final pieces = <Path>[main];
    if (steps > 0.01) {
      for (final step in plan.steps) {
        final c = step.getBounds().center;
        // A step grows out of, and shrinks back into, the arrow's middle.
        final at = Offset.lerp(Offset.zero, c, 0.4 + 0.6 * steps)!;
        final matrix = Matrix4.identity()
          ..translateByDouble(at.dx, at.dy, 0, 1)
          ..scaleByDouble(steps, steps, 1, 1)
          ..translateByDouble(-c.dx, -c.dy, 0, 1);
        pieces.add(step.transform(matrix.storage));
      }
    }
    if (change > 0.02 && light > 0.3) {
      final bloom = Paint()
        ..color = Color.fromRGBO(200, 225, 250, 0.38 * change * light)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 12 * change);
      for (final p in pieces) {
        canvas.drawPath(p, bloom);
      }
    }
    final fill = Paint()..color = color;
    if (change > 0.02) {
      fill.maskFilter = MaskFilter.blur(BlurStyle.normal, 0.9 * change);
    }
    for (final p in pieces) {
      canvas.drawPath(p, fill);
    }

    // Light runs across the arrow, the way it points.
    if (beat > 0 && beat < 1) {
      final along = ui.lerpDouble(-70, 70, Curves.easeInOut.transform(beat))!;
      canvas.save();
      final clip = Path();
      for (final p in pieces) {
        clip.addPath(p, Offset.zero);
      }
      canvas.clipPath(clip);
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
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(StageMorphPainter old) =>
      old.from != from ||
      old.to != to ||
      old.progress != progress ||
      old.toArrow != toArrow;
}

/// The arrow alone, [height] tall, [offset] from the stage's middle: on its
/// way to the sign-in's own arrow.
class ArrowPainter extends CustomPainter {
  ArrowPainter({required this.offset, required this.height, this.glow = 1});
  final Offset offset;
  final double height;
  final double glow;

  static final List<Path> _pieces = arrowPieces(_arrowHeight);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2 + offset.dx, size.height / 2 + offset.dy);
    final scale = height / _arrowHeight;
    if (glow > 0) {
      final r = 70 * scale;
      canvas.drawCircle(
          Offset.zero,
          r,
          Paint()
            ..shader = ui.Gradient.radial(Offset.zero, r, [
              Color.fromRGBO(170, 205, 240, 0.22 * glow),
              const Color.fromRGBO(170, 205, 240, 0),
            ]));
    }
    canvas.scale(scale);
    final fill = Paint()..color = _pearl;
    for (final piece in _pieces) {
      canvas.drawPath(piece, fill);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(ArrowPainter old) =>
      old.offset != offset || old.height != height || old.glow != glow;
}
