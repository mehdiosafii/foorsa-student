/// How far along the setup is: one hairline, the part already flown lit, the
/// journey's airliner, small, at its tip, and under it which step this is of
/// how many, as a departures board would print it.
library;

import 'package:flutter/widgets.dart';

import '../app_language.dart';
import 'airliner.dart';
import 'boarding_style.dart';

class RouteProgress extends StatelessWidget {
  const RouteProgress(
      {super.key,
      required this.progress,
      this.width = 132,
      this.step,
      this.steps});

  /// 0 at the start, 1 at the end; the parent springs it.
  final Animation<double> progress;
  final double width;

  /// Which step this is, of how many: printed under the line and said to a
  /// screen reader. Without them, the line alone.
  final int? step, steps;

  /// "Step 2 of 5", or null without a count.
  String? get where => whereIn(AppLanguage.en);

  /// The same in [language].
  String? whereIn(AppLanguage language) {
    final of = steps, at = step;
    if (of == null || at == null || of < 1) return null;
    return _where
        .of(language)
        .replaceFirst('{at}', '${at.clamp(1, of)}')
        .replaceFirst('{of}', '$of');
  }

  static const _where =
      Words('Step {at} of {of}', 'Étape {at} sur {of}', 'الخطوة {at} من {of}');
  static const _settingUp = Words('Setting up', 'Configuration', 'الإعداد');

  @override
  Widget build(BuildContext context) {
    final language = AppLanguageScope.of(context);
    final where = whereIn(language);
    return AnimatedBuilder(
      animation: progress,
      builder: (context, _) => Semantics(
        label: _settingUp.of(language),
        value: where ?? '${(progress.value.clamp(0.0, 1.0) * 100).round()}%',
        excludeSemantics: true,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CustomPaint(
            size: Size(width, 16),
            painter: _LinePainter(progress.value.clamp(0.0, 1.0)),
          ),
          if (where != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                where.toUpperCase(),
                maxLines: 1,
                // The bar it sits in is a fixed height.
                textScaler:
                    MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3),
                style: scriptStyle(
                    Boarding.caption(
                        color: Boarding.muted, size: 9.5, spacing: 1.8),
                    language),
              ),
            ),
        ]),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.p);
  final double p;

  static const _plane = AirlinerSilhouettePainter(Boarding.heading);
  static const _side = 15.0;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    // The plane needs room at both ends, so the line runs inside them.
    const inset = _side / 2;
    final from = Offset(inset, y);
    final to = Offset(size.width - inset, y);
    final tip = Offset.lerp(from, to, p)!;
    final line = Paint()
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(tip + const Offset(_side * 0.6, 0), to,
        line..color = Boarding.hairline);
    if (tip.dx - _side * 0.6 > from.dx) {
      canvas.drawLine(from, tip - const Offset(_side * 0.6, 0),
          line..color = Boarding.heading.withValues(alpha: 0.72));
    }
    canvas.save();
    canvas.translate(tip.dx, tip.dy);
    // Nose to the right, along the line.
    canvas.rotate(1.5707963267948966);
    canvas.translate(-_side / 2, -_side / 2);
    _plane.paint(canvas, const Size(_side, _side));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LinePainter old) => old.p != p;
}
