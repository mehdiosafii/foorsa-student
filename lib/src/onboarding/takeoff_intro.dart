/// The first three seconds: the native launch screen, exactly (the white
/// roundel on the splash's navy, 256 pt and centred, as LaunchScreen.storyboard
/// draws it), then the roundel lets go of its F, the F becomes the journey's
/// airliner the way it does on My journey, and the plane takes off into the
/// night the onboarding lives in.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'airliner.dart';
import 'splash_logo.dart';

/// The intro's length, in seconds.
const takeoffSeconds = 3.0;

double _smooth(double x) {
  final t = x.clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

double _inOut(double x) {
  final t = x.clamp(0.0, 1.0);
  return t < 0.5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3) / 2;
}

double _accelerate(double x) {
  final t = x.clamp(0.0, 1.0);
  return t * t * t;
}

/// How far the night has come in, at [t] seconds of the intro.
double takeoffNight(double t) => _smooth((t - 1.6) / 1.3);

class TakeoffIntro extends StatelessWidget {
  const TakeoffIntro({super.key, required this.time, this.splash});

  /// Seconds into the intro, 0 to [takeoffSeconds].
  final Animation<double> time;

  /// The roundel decoded before the first frame (splash_logo.dart).
  final ui.Image? splash;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: time,
        builder: (context, _) {
          final t = time.value;
          final roundel = 1 - _smooth((t - 0.3) / 0.45);
          return Stack(fit: StackFit.expand, children: [
            if (roundel > 0.001)
              Center(
                child: Opacity(
                  opacity: roundel,
                  child: Transform.scale(
                    scale: 1 + 0.06 * (1 - roundel),
                    child: splash == null
                        ? Image.asset(splashLogoAsset,
                            width: splashLogoSide,
                            height: splashLogoSide,
                            filterQuality: FilterQuality.medium)
                        : RawImage(
                            image: splash,
                            width: splashLogoSide,
                            height: splashLogoSide,
                            filterQuality: FilterQuality.medium),
                  ),
                ),
              ),
            CustomPaint(painter: _TakeoffPainter(t)),
          ]);
        },
      ),
    );
  }
}

class _TakeoffPainter extends CustomPainter {
  _TakeoffPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);

    // The roundel's rim lets go as a ring of light.
    final ring = ((t - 0.3) / 0.9).clamp(0.0, 1.0);
    if (ring > 0 && ring < 1) {
      final eased = 1 - math.pow(1 - ring, 3).toDouble();
      canvas.drawCircle(
          centre,
          92 + 78 * eased,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6 * (1 - ring) + 0.4
            ..color = Color.fromRGBO(235, 244, 255, 0.55 * (1 - ring)));
    }

    final mark = _smooth((t - 0.25) / 0.4);
    if (mark <= 0.001) return;
    final assembly = _inOut((t - 0.75) / 1.2);
    final takeoff = _accelerate((t - 2.15) / 0.85);
    // 128 pt puts the vector F where the splash's F is; the plane then grows.
    var box = 128 + 44 * _inOut((t - 0.75) / 1.25);
    box *= 1 - 0.55 * takeoff;
    final hover =
        assembly >= 1 && takeoff == 0 ? math.sin((t - 1.95) * 5) * 1.5 : 0.0;
    final y = centre.dy + hover - takeoff * (size.height / 2 + box + 60);

    // Contrails from the engines once it climbs.
    if (takeoff > 0) {
      for (final engineX in const [57.0, 123.0]) {
        final x = centre.dx + (engineX - 90) / 180 * box;
        final from = Offset(x, y + box * 0.2);
        final to = Offset(
            x,
            math.min(
                size.height + 40, from.dy + 40 + takeoff * size.height * 0.9));
        canvas.drawLine(
            from,
            to,
            Paint()
              ..strokeWidth = 2.2 * (1 - takeoff * 0.5)
              ..strokeCap = StrokeCap.round
              ..shader = ui.Gradient.linear(from, to, [
                Color.fromRGBO(236, 244, 255, 0.55 * (1 - takeoff * 0.6)),
                const Color.fromRGBO(236, 244, 255, 0),
              ]));
      }
    }

    canvas.saveLayer(Offset.zero & size,
        Paint()..color = Color.fromRGBO(255, 255, 255, mark));
    canvas.translate(centre.dx - box / 2, y - box / 2);
    AirlinerPainter(assembly: assembly, glow: 1).paint(canvas, Size(box, box));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TakeoffPainter old) => old.t != t;
}
