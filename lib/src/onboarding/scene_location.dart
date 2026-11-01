/// Location: a quiet night map seen through a glass lens, and on the lens's
/// edge the map's locate button, which is Foorsa's arrow: the same shape as
/// the phone's own location arrow. Tapping it is how the student turns
/// location on. Then the phone's blue dot drops onto the map with its
/// heading, and the one thing it gives a student in a new city: the next
/// prayer. The arrow then leaves the button for the middle of the map, and
/// the story goes on from there.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../app_language.dart';
import 'arrow_flight.dart';
import 'boarding_style.dart';
import 'gesture_demo.dart';
import 'glass.dart';
import 'scene_hint.dart';
import 'stage_forms.dart';

/// The locate button: a disc of the portal's lit glass on the lens's edge.
const locateSide = 46.0;

/// The arrow in it.
const locateArrowHeight = 19.0;

/// Where the locate button sits, from the lens's middle: on its edge, low on
/// the right, where a thumb is.
Offset locateOffset(double lensRadius) =>
    Offset(math.cos(math.pi / 4), math.sin(math.pi / 4)) * lensRadius;

/// The location's gesture: a tap on the locate button, not the map. Still,
/// a chevron points at the button from outside the lens.
GestureDemo locationDemo(Size stage) {
  final button = stage.center(Offset.zero) + locateOffset(lensRadius(stage));
  const out = Offset(0.7071, 0.7071);
  return GestureDemo.tap(
      thumbOn(button, locateSide / 2),
      RRect.fromRectAndRadius(
          Rect.fromCircle(center: button, radius: locateSide / 2),
          const Radius.circular(locateSide / 2)),
      cueAt: button + out * (locateSide / 2 + 17),
      cueAngle: -3 * math.pi / 4);
}

class LocationScene extends StatefulWidget {
  const LocationScene({
    super.key,
    required this.still,
    required this.feel,
    required this.armed,
    required this.label,
    required this.hint,
    required this.onAct,
    required this.outcome,
    required this.away,
    this.spoken,
  });
  final bool still;
  final Feel feel;
  final bool armed;
  final String label;
  final String hint;
  final String? spoken;

  /// Tapped: the arrow, where it is on the screen, for the flight on.
  final SceneAct onAct;

  /// null until the student answers; then whether location is on.
  final ValueListenable<bool?> outcome;

  /// The arrow has left the button (the page flies it on).
  final ValueListenable<bool> away;

  @override
  State<LocationScene> createState() => _LocationSceneState();
}

class _LocationSceneState extends State<LocationScene>
    with TickerProviderStateMixin, SceneClock<LocationScene> {
  final GlobalKey _button = GlobalKey();

  /// How hard the guide's touch presses the button: the arrow answers.
  final ValueNotifier<double> _nudge = ValueNotifier<double>(0);

  /// When the button was tapped, the map was tapped (the button answers,
  /// to show it is the one), and the dot was found.
  double _pressedAt = -1;
  double _pokedAt = -1;
  double _foundAt = -1;

  /// The prayer chip floating in once the dot is found, in seconds. Its own
  /// clock, not the scene's: built from the scene's every frame, the chip's
  /// builder laid the whole scene out again every frame, found or not.
  late final AnimationController _chipIn = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 950));

  @override
  void initState() {
    super.initState();
    widget.outcome.addListener(_answered);
    startClock(still: widget.still);
    if (widget.outcome.value == true) {
      _foundAt = 0;
      _showChip();
    }
  }

  void _showChip() {
    if (widget.still) {
      _chipIn.value = 1;
    } else {
      _chipIn.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(LocationScene old) {
    super.didUpdateWidget(old);
    if (old.outcome != widget.outcome) {
      old.outcome.removeListener(_answered);
      widget.outcome.addListener(_answered);
    }
  }

  @override
  void dispose() {
    widget.outcome.removeListener(_answered);
    _nudge.dispose();
    _chipIn.dispose();
    super.dispose();
  }

  void _answered() {
    if (widget.outcome.value != true || !mounted) return;
    setState(() => _foundAt = clock.value);
    _showChip();
  }

  void _locate() {
    if (!widget.armed || _pressedAt >= 0) return;
    final box = _button.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    setState(() => _pressedAt = clock.value);
    final at = box.localToGlobal(box.size.center(Offset.zero));
    widget.onAct(
        arrow: ArrowPose(at, restHeading, locateArrowHeight, glow: 0.9));
  }

  void _poke() {
    if (!widget.armed || _pressedAt >= 0) return;
    widget.feel('detent');
    setState(() => _pokedAt = clock.value);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final stage = box.biggest;
      final r = lensRadius(stage);
      final middle = stage.center(Offset.zero);
      final button = middle + locateOffset(r);
      return SceneGuide(
        instruction: widget.hint,
        demo: locationDemo(stage),
        instructionTop: middle.dy + r + 26,
        clearOf: math.max(middle.dy + r, button.dy + locateSide / 2),
        active: widget.armed && _pressedAt < 0,
        still: widget.still,
        response: _nudge,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(
            child: ExcludeSemantics(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _poke,
                // Its own layer: the map drifts every frame.
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _MapPainter(clock,
                        still: widget.still, radius: r, found: _foundAt),
                  ),
                ),
              ),
            ),
          ),
          // The prayer floats in above the dot once the phone knows where it
          // is.
          Positioned(
            left: 0,
            right: 0,
            top: middle.dy - 64,
            child: Center(
              child: _foundAt < 0
                  ? const SizedBox.shrink()
                  : AnimatedBuilder(
                      animation: _chipIn,
                      builder: (context, child) {
                        final v = widget.still
                            ? 1.0
                            : easeOut(_chipIn.value * 0.95, 0.3, 0.95);
                        if (v <= 0) return const SizedBox.shrink();
                        return Transform.translate(
                          offset: Offset(0, 8 * (1 - v)),
                          child: Opacity(opacity: v, child: child),
                        );
                      },
                      child: const _PrayerLabel(),
                    ),
            ),
          ),
          Positioned(
            left: button.dx - 32,
            top: button.dy - 32,
            width: 64,
            height: 64,
            child: Semantics(
              button: true,
              enabled: widget.armed,
              label: widget.label,
              hint: widget.spoken,
              excludeSemantics: true,
              onTap: widget.armed ? _locate : null,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: widget.armed ? (_) => widget.feel('press') : null,
                onTap: _locate,
                child: Center(
                  child: SizedBox.square(
                    key: _button,
                    dimension: locateSide,
                    child: GlassPane(
                      glass: Glass.tile,
                      circle: true,
                      child: ValueListenableBuilder<bool>(
                        valueListenable: widget.away,
                        builder: (context, away, _) => away
                            ? const SizedBox.expand()
                            // Its own layer, apart from the button's glass.
                            : RepaintBoundary(
                                child: CustomPaint(
                                  painter: _LocateArrowPainter(clock,
                                      still: widget.still,
                                      nudge: _nudge,
                                      pressedAt: _pressedAt,
                                      pokedAt: _pokedAt),
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ]),
      );
    });
  }
}

/// The arrow in the locate button: it hops along its own way as the guide's
/// touch presses it, answers when the map is tapped, and lights once
/// pressed.
class _LocateArrowPainter extends CustomPainter {
  _LocateArrowPainter(this.clock,
      {required this.still,
      required this.nudge,
      required this.pressedAt,
      required this.pokedAt})
      : super(repaint: Listenable.merge([clock, nudge]));
  final ValueNotifier<double> clock;
  final bool still;
  final ValueListenable<double> nudge;
  final double pressedAt;
  final double pokedAt;

  @override
  void paint(Canvas canvas, Size size) {
    final t = clock.value;
    final hop = still || pressedAt >= 0 ? 0.0 : nudge.value;
    final poke = pokedAt < 0 || still
        ? 0.0
        : math.sin(math.pi * ((t - pokedAt) / 0.5).clamp(0.0, 1.0));
    final lift = math.max(hop, poke);
    final lit =
        pressedAt < 0 ? 0.0 : (still ? 1.0 : ease(t - pressedAt, 0, 0.25));
    // Pressed, it lights the phone's blue, as the phone's own button does.
    if (lit > 0) {
      final middle = size.center(Offset.zero);
      canvas.drawCircle(
          middle,
          size.width / 2,
          Paint()
            ..shader = ui.Gradient.radial(middle, size.width / 2, [
              Boarding.here.withValues(alpha: 0.42 * lit),
              Boarding.here.withValues(alpha: 0.16 * lit),
            ]));
    }
    const way = Offset(0.7071, -0.7071);
    paintArrowAt(
        canvas,
        ArrowPose(size.center(Offset.zero) + way * (2.6 * lift), restHeading,
            locateArrowHeight,
            glow: 0.25 + 0.4 * lift + 0.65 * lit));
  }

  @override
  bool shouldRepaint(_LocateArrowPainter old) =>
      old.still != still ||
      old.pressedAt != pressedAt ||
      old.pokedAt != pokedAt;
}

/// The afternoon prayer, as the portal names it.
const _asr = Words('Asr', 'Asr', 'العصر');

class _PrayerLabel extends StatelessWidget {
  const _PrayerLabel();

  @override
  Widget build(BuildContext context) {
    final language = AppLanguageScope.of(context);
    return GlassPane(
      glass: Glass.pane,
      radius: 999,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
        child: Text.rich(
          TextSpan(children: [
            TextSpan(
                text: '${_asr.of(language)}  ',
                style: TextStyle(
                    color: Boarding.muted.withValues(alpha: 0.95),
                    fontWeight: FontWeight.w500)),
            const TextSpan(
                text: '15:42',
                style: TextStyle(
                    color: Boarding.heading,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()])),
          ]),
          style: scriptStyle(
              const TextStyle(fontSize: 13.5, height: 1.2, letterSpacing: -0.1),
              language),
        ),
      ),
    );
  }
}

/// The lens's frame: [lensGlass] without its face, so the map shows.
final Glass _lensFrame = Glass(
  fill: const [Color(0x00000000), Color(0x00000000), Color(0x00000000)],
  rim: lensGlass.rim,
  wall: lensGlass.wall,
  highlight: lensGlass.highlight,
  glow: lensGlass.glow,
  shadows: lensGlass.shadows,
);

class _MapPainter extends CustomPainter {
  _MapPainter(this.clock,
      {required this.still, required this.radius, required this.found})
      : super(repaint: clock);
  final ValueNotifier<double> clock;
  final bool still;

  /// The lens's radius (stage_forms.dart's lensRadius).
  final double radius;

  /// When the phone found where it is; below 0 while it does not know.
  final double found;

  @override
  void paint(Canvas canvas, Size size) {
    final t = still ? 0.0 : clock.value;
    final centre = size.center(Offset.zero);
    final appear = still ? 1.0 : easeOut(t, 0, 0.9);

    // The map, through the lens.
    final r = radius;
    final circle = Rect.fromCircle(center: centre, radius: r);
    canvas.save();
    canvas.clipPath(Path()..addOval(circle));
    // Faded in as one piece, then drawn straight on: once it is there, an
    // offscreen layer every frame changes nothing but the cost.
    if (appear < 1) {
      canvas.saveLayer(
          circle, Paint()..color = Color.fromRGBO(0, 0, 0, appear));
    } else {
      canvas.save();
    }
    canvas.translate(centre.dx, centre.dy);
    // It drifts very slowly, as a map does in a walking hand.
    canvas.rotate(0.03 * math.sin(t * 0.35));
    canvas.translate(4 * math.sin(t * 0.21), 3 * math.cos(t * 0.17));
    canvas.scale(0.94 + 0.06 * appear);
    canvas.translate(-145, -145);
    _streets(canvas);
    canvas.restore();
    // Darker towards the glass's edge, as a lens is.
    canvas.drawRect(
      circle,
      Paint()
        ..shader = ui.Gradient.radial(centre, r, [
          const Color(0x00060B12),
          Color.fromRGBO(6, 11, 18, 0.55 * appear),
        ], const [
          0.62,
          1
        ]),
    );
    canvas.restore();
    final lens =
        GlassShape.rrect(RRect.fromRectAndRadius(circle, Radius.circular(r)));
    paintGlassBody(canvas, lens, _lensFrame,
        opacity: appear, bake: ('lens', r));

    if (found >= 0) _here(canvas, centre, t, still ? 99 : clock.value - found);
    paintGlassRim(canvas, lens, _lensFrame, opacity: appear);
  }

  /// The phone's blue dot, [since] seconds after it was found: it drops onto
  /// the map with a ring going out from it, then breathes, its heading lit.
  void _here(Canvas canvas, Offset centre, double t, double since) {
    final drop = Curves.easeOutBack.transform(ease(since, 0, 0.42));
    final appear = ease(since, 0, 0.22);
    if (appear <= 0) return;
    // Found: one ring goes out over the map.
    if (since < 1.1) {
      final k = (since / 1.1).clamp(0.0, 1.0);
      canvas.drawCircle(
          centre,
          12 + 70 * Curves.easeOut.transform(k),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..color = Boarding.here.withValues(alpha: 0.55 * (1 - k)));
    }
    final cone = ease(since, 0.35, 0.9);
    // Where the phone is pointing.
    final heading =
        -math.pi / 2 + 0.75 + (still ? 0 : 0.12 * math.sin(t * 0.8));
    const reach = 64.0, spread = 0.5;
    final beam = Path()
      ..moveTo(centre.dx, centre.dy)
      ..arcTo(Rect.fromCircle(center: centre, radius: reach), heading - spread,
          spread * 2, false)
      ..close();
    canvas.drawPath(
      beam,
      Paint()
        ..shader = ui.Gradient.radial(centre, reach, [
          Boarding.here.withValues(alpha: 0.5 * cone),
          Boarding.here.withValues(alpha: 0.16 * cone),
          Boarding.here.withValues(alpha: 0),
        ], const [
          0.15,
          0.55,
          1
        ])
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    // The dot, its halo breathing.
    final pulse = still ? 0.5 : (t % 2.4) / 2.4;
    canvas.drawCircle(
        centre,
        12 + 26 * Curves.easeOut.transform(pulse),
        Paint()
          ..color = Boarding.here.withValues(alpha: 0.22 * (1 - pulse) * cone));
    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    // It comes down onto the map: larger and lighter first.
    final s = 1.9 - 0.9 * drop;
    canvas.scale(s);
    canvas.drawCircle(
        Offset.zero,
        11,
        Paint()
          ..color = Color.fromRGBO(0, 0, 0, 0.35 * appear)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    canvas.drawCircle(Offset.zero, 10.5,
        Paint()..color = Color.fromRGBO(255, 255, 255, appear));
    canvas.drawCircle(Offset.zero, 7.5,
        Paint()..color = Boarding.here.withValues(alpha: appear));
    canvas.restore();
  }

  /// A part of a city at night, in a 290 pt square: a river, avenues, a
  /// grid of side streets and a park.
  void _streets(Canvas canvas) {
    canvas.drawRect(const Rect.fromLTWH(-40, -40, 370, 370),
        Paint()..color = const Color(0xFF101A25));
    // Side streets, a slightly turned grid.
    final side = Paint()
      ..color = const Color(0xFF172433)
      ..strokeWidth = 1.2;
    canvas.save();
    canvas.translate(145, 145);
    canvas.rotate(0.21);
    for (var k = -9; k <= 9; k++) {
      final o = k * 22.0;
      canvas.drawLine(Offset(o, -220), Offset(o, 220), side);
      canvas.drawLine(Offset(-220, o), Offset(220, o), side);
    }
    canvas.restore();
    // The river.
    final river = Path()
      ..moveTo(-40, 214)
      ..cubicTo(60, 186, 120, 242, 190, 210)
      ..cubicTo(240, 188, 280, 150, 340, 160);
    canvas.drawPath(
        river,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 30
          ..color = const Color(0xFF162C43));
    // Avenues.
    final avenue = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.2
      ..color = const Color(0xFF2D3E52);
    canvas.drawPath(
        Path()
          ..moveTo(-20, 98)
          ..quadraticBezierTo(150, 72, 320, 92),
        avenue);
    canvas.drawPath(
        Path()
          ..moveTo(96, -20)
          ..quadraticBezierTo(124, 150, 110, 320),
        avenue);
    canvas.drawPath(
        Path()
          ..moveTo(232, -20)
          ..quadraticBezierTo(196, 160, 214, 320),
        avenue..strokeWidth = 2.4);
    // A bridge over the river.
    canvas.drawLine(const Offset(152, 196), const Offset(160, 246),
        avenue..strokeWidth = 2.6);
  }

  @override
  bool shouldRepaint(_MapPainter old) =>
      old.still != still || old.radius != radius || old.found != found;
}
