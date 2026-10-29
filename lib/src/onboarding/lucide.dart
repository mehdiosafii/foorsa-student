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

  static const bell = LucideGlyph(<String>[
    'M10.268 21a2 2 0 0 0 3.464 0',
    'M3.262 15.326A1 1 0 0 0 4 17h16a1 1 0 0 0 .74-1.673C19.41 13.956 18 12.499 18 8A6 6 0 0 0 6 8c0 4.499-1.411 5.956-2.738 7.326',
  ]);
  static const camera = LucideGlyph(<String>[
    'M13.997 4a2 2 0 0 1 1.76 1.05l.486.9A2 2 0 0 0 18.003 7H20a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V9a2 2 0 0 1 2-2h1.997a2 2 0 0 0 1.759-1.048l.489-.904A2 2 0 0 1 10.004 4z',
    'M9 13a3 3 0 1 0 6 0a3 3 0 1 0 -6 0',
  ]);
  static const mic = LucideGlyph(<String>[
    'M12 19v3',
    'M19 10v2a7 7 0 0 1-14 0v-2',
    'M12 2h0a3 3 0 0 1 3 3v7a3 3 0 0 1 -3 3h0a3 3 0 0 1 -3 -3v-7a3 3 0 0 1 3 -3Z',
  ]);
  static const mapPin = LucideGlyph(<String>[
    'M20 10c0 4.993-5.539 10.193-7.399 11.799a1 1 0 0 1-1.202 0C9.539 20.193 4 14.993 4 10a8 8 0 0 1 16 0',
    'M9 10a3 3 0 1 0 6 0a3 3 0 1 0 -6 0',
  ]);
  static const check = LucideGlyph(<String>[
    'M20 6 9 17l-5-5',
  ]);
  static const chevronRight = LucideGlyph(<String>[
    'm9 18 6-6-6-6',
  ]);
  static const plane = LucideGlyph(<String>[
    'M17.8 19.2 16 11l3.5-3.5C21 6 21.5 4 21 3c-1-.5-3 0-4.5 1.5L13 8 4.8 6.2c-.5-.1-.9.1-1.1.5l-.3.5c-.2.5-.1 1 .3 1.3L9 12l-2 3H4l-1 1 3 2 2 3 1-1v-3l3-2 3.5 5.3c.3.4.8.5 1.3.3l.5-.2c.4-.3.6-.7.5-1.2z',
  ]);
  static const shoppingBasket = LucideGlyph(<String>[
    'm15 11-1 9',
    'm19 11-4-7',
    'M2 11h20',
    'm3.5 11 1.6 7.4a2 2 0 0 0 2 1.6h9.8a2 2 0 0 0 2-1.6l1.7-7.4',
    'M4.5 15.5h15',
    'm5 11 4-7',
    'm9 11 1 9',
  ]);
  static const sun = LucideGlyph(<String>[
    'M8 12a4 4 0 1 0 8 0a4 4 0 1 0 -8 0',
    'M12 2v2',
    'M12 20v2',
    'm4.93 4.93 1.41 1.41',
    'm17.66 17.66 1.41 1.41',
    'M2 12h2',
    'M20 12h2',
    'm6.34 17.66-1.41 1.41',
    'm19.07 4.93-1.41 1.41',
  ]);
  static const phone = LucideGlyph(<String>[
    'M13.832 16.568a1 1 0 0 0 1.213-.303l.355-.465A2 2 0 0 1 17 15h3a2 2 0 0 1 2 2v3a2 2 0 0 1-2 2A18 18 0 0 1 2 4a2 2 0 0 1 2-2h3a2 2 0 0 1 2 2v3a2 2 0 0 1-.8 1.6l-.468.351a1 1 0 0 0-.292 1.233 14 14 0 0 0 6.392 6.384',
  ]);
  static const play = LucideGlyph(<String>[
    'M5 5a2 2 0 0 1 3.008-1.728l11.997 6.998a2 2 0 0 1 .003 3.458l-12 7A2 2 0 0 1 5 19z',
  ]);
  static const shieldCheck = LucideGlyph(<String>[
    'M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z',
    'm9 12 2 2 4-4',
  ]);
  static const scanLine = LucideGlyph(<String>[
    'M3 7V5a2 2 0 0 1 2-2h2',
    'M17 3h2a2 2 0 0 1 2 2v2',
    'M21 17v2a2 2 0 0 1-2 2h-2',
    'M7 21H5a2 2 0 0 1-2-2v-2',
    'M7 12h10',
  ]);
  static const megaphone = LucideGlyph(<String>[
    'M11 6a13 13 0 0 0 8.4-2.8A1 1 0 0 1 21 4v12a1 1 0 0 1-1.6.8A13 13 0 0 0 11 14H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2z',
    'M6 14a12 12 0 0 0 2.4 7.2 2 2 0 0 0 3.2-2.4A8 8 0 0 1 10 14',
    'M8 6v8',
  ]);
  static const graduationCap = LucideGlyph(<String>[
    'M21.42 10.922a1 1 0 0 0-.019-1.838L12.83 5.18a2 2 0 0 0-1.66 0L2.6 9.08a1 1 0 0 0 0 1.832l8.57 3.908a2 2 0 0 0 1.66 0z',
    'M22 10v6',
    'M6 12.5V16a6 3 0 0 0 12 0v-3.5',
  ]);
  static const lock = LucideGlyph(<String>[
    'M5 11h14a2 2 0 0 1 2 2v7a2 2 0 0 1 -2 2h-14a2 2 0 0 1 -2 -2v-7a2 2 0 0 1 2 -2Z',
    'M7 11V7a5 5 0 0 1 10 0v4',
  ]);
  static const moon = LucideGlyph(<String>[
    'M20.985 12.486a9 9 0 1 1-9.473-9.472c.405-.022.617.46.402.803a6 6 0 0 0 8.268 8.268c.344-.215.825-.004.803.401',
  ]);
  static const checkCheck = LucideGlyph(<String>[
    'M18 6 7 17l-5-5',
    'm22 10-7.5 7.5L13 16',
  ]);
  static const circleCheck = LucideGlyph(<String>[
    'M2 12a10 10 0 1 0 20 0a10 10 0 1 0 -20 0',
    'm9 12 2 2 4-4',
  ]);
  static const sparkles = LucideGlyph(<String>[
    'M11.017 2.814a1 1 0 0 1 1.966 0l1.051 5.558a2 2 0 0 0 1.594 1.594l5.558 1.051a1 1 0 0 1 0 1.966l-5.558 1.051a2 2 0 0 0-1.594 1.594l-1.051 5.558a1 1 0 0 1-1.966 0l-1.051-5.558a2 2 0 0 0-1.594-1.594l-5.558-1.051a1 1 0 0 1 0-1.966l5.558-1.051a2 2 0 0 0 1.594-1.594z',
    'M20 2v4',
    'M22 4h-4',
    'M2 20a2 2 0 1 0 4 0a2 2 0 1 0 -4 0',
  ]);
  static const settings = LucideGlyph(<String>[
    'M9.671 4.136a2.34 2.34 0 0 1 4.659 0 2.34 2.34 0 0 0 3.319 1.915 2.34 2.34 0 0 1 2.33 4.033 2.34 2.34 0 0 0 0 3.831 2.34 2.34 0 0 1-2.33 4.033 2.34 2.34 0 0 0-3.319 1.915 2.34 2.34 0 0 1-4.659 0 2.34 2.34 0 0 0-3.32-1.915 2.34 2.34 0 0 1-2.33-4.033 2.34 2.34 0 0 0 0-3.831A2.34 2.34 0 0 1 6.35 6.051a2.34 2.34 0 0 0 3.319-1.915',
    'M9 12a3 3 0 1 0 6 0a3 3 0 1 0 -6 0',
  ]);
  static const eyeOff = LucideGlyph(<String>[
    'M10.733 5.076a10.744 10.744 0 0 1 11.205 6.575 1 1 0 0 1 0 .696 10.747 10.747 0 0 1-1.444 2.49',
    'M14.084 14.158a3 3 0 0 1-4.242-4.242',
    'M17.479 17.499a10.75 10.75 0 0 1-15.417-5.151 1 1 0 0 1 0-.696 10.75 10.75 0 0 1 4.446-5.143',
    'm2 2 20 20',
  ]);
  static const handHeart = LucideGlyph(<String>[
    'M11 14h2a2 2 0 0 0 0-4h-3c-.6 0-1.1.2-1.4.6L3 16',
    'm14.45 13.39 5.05-4.694C20.196 8 21 6.85 21 5.75a2.75 2.75 0 0 0-4.797-1.837.276.276 0 0 1-.406 0A2.75 2.75 0 0 0 11 5.75c0 1.2.802 2.248 1.5 2.946L16 11.95',
    'm2 15 6 6',
    'm7 20 1.6-1.4c.3-.4.8-.6 1.4-.6h4c1.1 0 2.1-.4 2.8-1.2l4.6-4.4a1 1 0 0 0-2.75-2.91',
  ]);
  static const square = LucideGlyph(<String>[
    'M5 3h14a2 2 0 0 1 2 2v14a2 2 0 0 1 -2 2h-14a2 2 0 0 1 -2 -2v-14a2 2 0 0 1 2 -2Z',
  ]);
}
