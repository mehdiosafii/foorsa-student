/// The journey's airliner, the one the portal flies along My journey
/// (JourneyFlightCraft.tsx in foorsa-reward), from the same paths in its
/// 180 x 180 box, nose up.
///
/// Here it is drawn as one material, pearl, the colour the F turns as the
/// launch screen's roundel opens: so the F can flow into it outline for
/// outline, and the plane stays the same object it was born as. Its lights
/// are a real airliner's: red on the left wingtip, green on the right, white
/// strobes flashing twice, a red beacon pulsing on the fuselage.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'glass.dart';
import 'svg_path.dart';

// The component's paths, verbatim.
const _wingL = 'M84 69 27 91 13 107l7 8 64-20Z';
const _wingLLines = 'm48 84 1 22M65 78l2 22';
const _wingR = 'm96 69 57 22 14 16-7 8-64-20Z';
const _wingRLines = 'm132 84-1 22M115 78l-2 22';
const _tailL = 'm86 132-30 17-10 12 39-9Z';
const _tailR = 'm94 132 30 17 10 12-39-9Z';
const _engineL = 'M50 88c0-5 3-8 7-8s7 3 7 8l-2 28c0 5-2 8-5 8s-5-3-5-8Z';
const _engineR = 'M116 88c0-5 3-8 7-8s7 3 7 8l-2 28c0 5-2 8-5 8s-5-3-5-8Z';
const _bodyOuter =
    'M90 9c-9 12-14 32-14 58l5 76 9 26 9-26 5-76c0-26-5-46-14-58Z';
const _canopy = 'm90 28-8 14 1 11 7-5 7 5 1-11Z';
const _spine = 'M90 22c3 20 4 60 2 118';

/// The plane's parts, in its 180 box.
class PlaneShape {
  PlaneShape._();

  /// The fuselage and both wings, as one outline.
  static final Path body = Path.combine(
      PathOperation.union,
      Path.combine(PathOperation.union, svgPath(_bodyOuter), svgPath(_wingL)),
      svgPath(_wingR));
  static final Path tailLeft = svgPath(_tailL);
  static final Path tailRight = svgPath(_tailR);
  static final Path engineLeft = svgPath(_engineL);
  static final Path engineRight = svgPath(_engineR);
  static final Path canopy = svgPath(_canopy);

  /// The rear of each engine, where a contrail starts.
  static const exhausts = [Offset(57, 124), Offset(123, 124)];

  static const _leftTip = Offset(15, 109);
  static const _rightTip = Offset(165, 109);
  static const _tailLight = Offset(90, 168);
  static const _beacon = Offset(90, 98);
}

/// The arrow's pearl glass as the plane wears it in the sky: no shadow cast
/// on the night, and a lighter bevel for its thin wings.
const planeGlass = Glass(
  fill: [Color(0xFFFFFFFF), Color(0xFFE8EFF6), Color(0xFFBACADA)],
  fillAngle: 145,
  rim: [Color(0xFFFFFFFF), Color(0x80FFFFFF), Color(0x26FFFFFF)],
  rimWidth: 1.2,
  wall: Color(0x00FFFFFF),
  highlight: GlassShadow(Color(0xD9FFFFFF), dx: 1.2, dy: 1.8, blur: 2.4),
  glow: GlassShadow(Color(0x403E5874), dx: -1.6, dy: -2.4, blur: 6),
  shadows: [GlassShadow.none, GlassShadow.none, GlassShadow.none],
);

/// The plane as one outline. Added as three subpaths, each piece's rim was
/// traced in full, so where a tailplane overlaps the fuselage its rim ran
/// across the body as a bright fleck (the loader's frames, 31 Oct 2026).
final GlassShape _hull = GlassShape.path(Path.combine(
  PathOperation.union,
  Path.combine(PathOperation.union, PlaneShape.tailLeft, PlaneShape.tailRight),
  PlaneShape.body,
));

/// The pearl material: lit from the top left of the plane.
Paint pearlPaint(Rect box, {double opacity = 1}) => Paint()
  ..shader = ui.Gradient.linear(
    box.topLeft,
    box.bottomRight,
    [
      Color.fromRGBO(255, 255, 255, opacity),
      Color.fromRGBO(232, 239, 246, opacity),
      Color.fromRGBO(186, 202, 218, opacity),
    ],
    const [0, 0.5, 1],
  );

/// Paints the plane in its 180 box. [detail] brings in the engines, the
/// cockpit and the panel lines; [lights] the navigation lights, which blink
/// on [clock] (seconds).
void paintPearlPlane(Canvas canvas,
    {double detail = 1,
    double lights = 0,
    double clock = 0,
    double opacity = 1,
    Glass glass = planeGlass,
    bool onLight = false}) {
  if (opacity <= 0.001) return;
  // Faded as one piece (the loader's plane leaving), not part by part.
  if (opacity < 1) {
    canvas.saveLayer(const Rect.fromLTWH(-20, -20, 220, 220),
        Paint()..color = Color.fromRGBO(0, 0, 0, opacity));
    paintPearlPlane(canvas,
        detail: detail, lights: lights, clock: clock, glass: glass, onLight: onLight);
    canvas.restore();
    return;
  }
  // The engines hang under the wings, so they come first.
  if (detail > 0.001) {
    final grow = 0.5 + 0.5 * detail;
    for (final (engine, centre) in [
      (PlaneShape.engineLeft, const Offset(57, 100)),
      (PlaneShape.engineRight, const Offset(123, 100)),
    ]) {
      canvas.save();
      canvas.translate(centre.dx, centre.dy);
      canvas.scale(grow);
      canvas.translate(-centre.dx, -centre.dy);
      canvas.drawPath(
          engine,
          Paint()
            ..shader = ui.Gradient.linear(
                const Offset(50, 80), const Offset(64, 124), onLight
                    ? [
                        Color.fromRGBO(58, 88, 124, detail),
                        Color.fromRGBO(16, 36, 60, detail),
                      ]
                    : [
                        Color.fromRGBO(236, 242, 248, detail),
                        Color.fromRGBO(160, 178, 196, detail),
                      ]));
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset(centre.dx, 85), width: 10, height: 4.4),
          Paint()..color = Color.fromRGBO(16, 30, 46, 0.85 * detail));
      canvas.restore();
    }
  }

  paintGlassBody(canvas, _hull, glass, bake: _hull);
  paintGlassRim(canvas, _hull, glass);

  if (detail > 0.001) {
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 0.7
      ..color = onLight
          ? Color.fromRGBO(255, 255, 255, 0.2 * detail)
          : Color.fromRGBO(120, 140, 162, 0.32 * detail);
    canvas.drawPath(svgPath(_wingLLines), line);
    canvas.drawPath(svgPath(_wingRLines), line);
    // Light along the spine.
    canvas.drawPath(
        svgPath(_spine),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 1.4
          ..color = Color.fromRGBO(255, 255, 255, (onLight ? 0.32 : 0.75) * detail));
    // The cockpit windows: a cool tint at the nose, not a hole in it.
    canvas.save();
    canvas.translate(90, 41);
    canvas.scale(0.62);
    canvas.translate(-90, -41);
    canvas.drawPath(
        PlaneShape.canopy,
        Paint()
          ..shader =
              ui.Gradient.linear(const Offset(90, 28), const Offset(90, 52), [
            Color.fromRGBO(150, 178, 204, detail),
            Color.fromRGBO(88, 114, 140, detail),
          ]));
    canvas.restore();
  }

  if (lights > 0.001) _lights(canvas, lights, clock);
}

void _lights(Canvas canvas, double on, double clock) {
  void light(Offset at, Color color, double strength, {double halo = 7}) {
    if (strength <= 0.01) return;
    canvas.drawCircle(
        at,
        halo,
        Paint()
          ..color = color.withValues(alpha: 0.38 * strength)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, halo * 0.6));
    canvas.drawCircle(
        at,
        1.7,
        Paint()
          ..color = Color.lerp(color, const Color(0xFFFFFFFF), 0.35)!
              .withValues(alpha: strength));
  }

  // Steady position lights.
  light(PlaneShape._leftTip, const Color(0xFFFF453A), on);
  light(PlaneShape._rightTip, const Color(0xFF30D158), on);
  light(PlaneShape._tailLight, const Color(0xFFFFFFFF), 0.7 * on, halo: 5);

  // Strobes: two short white flashes, then a pause.
  final phase = clock % 1.3;
  double flash(double at) {
    final d = (phase - at).abs();
    return d < 0.05 ? 1 - d / 0.05 : 0;
  }

  final strobe = math.max(flash(0.0), flash(0.14)) * on;
  if (strobe > 0) {
    for (final tip in [PlaneShape._leftTip, PlaneShape._rightTip]) {
      light(tip, const Color(0xFFFFFFFF), strobe, halo: 16);
    }
  }
  // The beacon: a slow red pulse.
  final beat = (clock + 0.5) % 1.1;
  final beacon = beat < 0.35 ? math.sin(beat / 0.35 * math.pi) : 0.0;
  light(PlaneShape._beacon, const Color(0xFFFF3B30), 0.8 * beacon * on,
      halo: 4.5);
}

/// The airliner as one flat shape in [color], nose up, in its 180 box.
class AirlinerSilhouettePainter extends CustomPainter {
  const AirlinerSilhouettePainter(this.color);
  final Color color;

  static final Path _shape = () {
    final path = Path()..fillType = PathFillType.nonZero;
    for (final part in [
      PlaneShape.body,
      PlaneShape.tailLeft,
      PlaneShape.tailRight,
      PlaneShape.engineLeft,
      PlaneShape.engineRight,
    ]) {
      path.addPath(part, Offset.zero);
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
