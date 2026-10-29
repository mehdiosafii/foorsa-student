/// Foorsa's arrow as a piece of pearl glass, lit from the upper left. It is
/// the app's first picture (the native splash is rendered from this painter,
/// scripts/onboarding_splash/render_splash_test.dart), the arrow parked on
/// the runway, the one that flies between the objects, and the one that
/// lands on the sign-in.
library;

import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'glass.dart';
import 'stage_forms.dart';

/// How tall the native splash draws it, centred on the screen.
const splashArrowHeight = 100.0;

/// The arrow at the reference height, its three pieces as one path.
final Path arrowPath100 = () {
  final path = Path();
  for (final piece in arrowPieces(100)) {
    path.addPath(piece, Offset.zero);
  }
  return path;
}();

final GlassShape _shape = GlassShape.path(arrowPath100);

/// The arrow, [height] tall and centred on the origin, pointing up and to the
/// right (turn the canvas for any other heading). [glow] lights the night
/// around it; [shine] runs a band of light across it, 0 to 1 from tail to
/// tip; [lift] lowers its shadow (0.6 while it is pressed).
void paintGlassArrow(Canvas canvas,
    {double height = 100,
    double opacity = 1,
    double glow = 0,
    double shine = -1,
    double lift = 1}) {
  if (opacity <= 0 || height <= 0) return;
  canvas.save();
  canvas.scale(height / 100);
  paintArrowGlow(canvas, 92, glow * opacity);
  paintGlassBody(canvas, _shape, Glass.pearl, opacity: opacity, lift: lift);
  if (shine > 0 && shine < 1) _shine(canvas, shine, opacity);
  paintGlassRim(canvas, _shape, Glass.pearl, opacity: opacity);
  canvas.restore();
}

/// The night lit around the arrow, [radius] out from the origin.
void paintArrowGlow(Canvas canvas, double radius, double strength) {
  if (strength <= 0.005) return;
  canvas.drawCircle(
      Offset.zero,
      radius,
      Paint()
        ..shader = ui.Gradient.radial(Offset.zero, radius, [
          Color.fromRGBO(172, 206, 240, 0.34 * strength),
          Color.fromRGBO(172, 206, 240, 0.1 * strength),
          const Color.fromRGBO(172, 206, 240, 0),
        ], const [
          0,
          0.45,
          1
        ]));
}

/// A band of light crossing the arrow the way it points.
void _shine(Canvas canvas, double s, double opacity) {
  // Along the arrow's axis, from its lower left to its upper right.
  final along = ui.lerpDouble(-86, 86, Curves.easeInOut.transform(s))!;
  const axis = Offset(0.7071, -0.7071);
  final centre = axis * along;
  canvas.save();
  canvas.clipPath(arrowPath100);
  canvas.drawRect(
    const Rect.fromLTWH(-70, -70, 140, 140),
    Paint()
      ..blendMode = BlendMode.plus
      ..shader = ui.Gradient.linear(
        centre - axis * 18,
        centre + axis * 18,
        [
          const Color(0x00FFFFFF),
          Color.fromRGBO(255, 255, 255, 0.55 * opacity),
          const Color(0x00FFFFFF),
        ],
        const [0, 0.5, 1],
      ),
  );
  canvas.restore();
}

/// The arrow alone in a box, for a widget tree: [height] tall, centred.
class GlassArrow extends StatelessWidget {
  const GlassArrow({super.key, this.height = 100, this.glow = 0});
  final double height;
  final double glow;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.square(height * 1.6),
        painter: _GlassArrowPainter(height, glow),
      );
}

class _GlassArrowPainter extends CustomPainter {
  _GlassArrowPainter(this.height, this.glow);
  final double height;
  final double glow;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    paintGlassArrow(canvas, height: height, glow: glow);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlassArrowPainter old) =>
      old.height != height || old.glow != glow;
}
