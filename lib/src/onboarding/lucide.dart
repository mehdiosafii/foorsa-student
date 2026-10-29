/// The portal's icons (lucide, as in src/portal), drawn natively: the same
/// 24 x 24 paths with lucide's 2-unit round stroke, so a bell here is the
/// bell the student sees on Home. Generated from lucide-react 0.556.0 (ISC).
library;

import 'package:flutter/widgets.dart';

import 'svg_path.dart';

/// One lucide icon: its path strings on the 24-unit grid.
class LucideGlyph {
  const LucideGlyph(this.paths);
  final List<String> paths;
}

/// A lucide icon at [size], stroked in [color].
class Lucide extends StatelessWidget {
  const Lucide(this.glyph,
      {super.key, this.size = 24, this.color, this.strokeWidth = 2});
  final LucideGlyph glyph;
  final double size;
  final Color? color;

  /// On lucide's 24-unit grid; the portal uses 1.5 to 2.
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final ink = color ??
        DefaultTextStyle.of(context).style.color ??
        const Color(0xFFFFFFFF);
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: LucidePainter(glyph, ink, strokeWidth)),
    );
  }
}

class LucidePainter extends CustomPainter {
  LucidePainter(this.glyph, this.color, [this.strokeWidth = 2]);
  final LucideGlyph glyph;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color
      ..isAntiAlias = true;
    for (final d in glyph.paths) {
      canvas.drawPath(svgPath(d), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(LucidePainter old) =>
      old.glyph != glyph ||
      old.color != color ||
      old.strokeWidth != strokeWidth;
}

class LucideIcons {
  LucideIcons._();

  static const mic = LucideGlyph(<String>[
    'M12 19v3',
    'M19 10v2a7 7 0 0 1-14 0v-2',
    'M12 2h0a3 3 0 0 1 3 3v7a3 3 0 0 1 -3 3h0a3 3 0 0 1 -3 -3v-7a3 3 0 0 1 3 -3Z',
  ]);
  static const check = LucideGlyph(<String>[
    'M20 6 9 17l-5-5',
  ]);
  static const shieldCheck = LucideGlyph(<String>[
    'M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z',
    'm9 12 2 2 4-4',
  ]);
}
