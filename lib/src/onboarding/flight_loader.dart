/// The app's loading sign. Since 31 Oct 2026 it tells what Foorsa does, in
/// the logo's own pieces (the arrow and its two steps), each form flowing
/// into the next: the logo catches the light; it becomes stairs that climb
/// up the way the arrow points; an arrow straight up, its steps left behind
/// as a trail; the airliner, nose up, its lights on; the graduate's cap,
/// tossed, its tassel swinging; and the logo again.
///
/// Before, it was the arrow becoming the plane and leaving (as the take-off
/// intro does); the portal's loader (foorsa-reward src/portal/FlightLoader.tsx)
/// still plays that one until it is brought over.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../app_language.dart';
import 'airliner.dart';
import 'glass.dart';
import 'glass_arrow.dart';
import 'shape_morph.dart';
import 'stage_forms.dart';
import 'takeoff_intro.dart';

/// One loop, in seconds: the logo, the stairs, the arrow, the plane, the
/// cap, and the logo again (see [_scenes]).
const flightLoaderSeconds = 6.8;

/// Under Reduce Motion the same forms follow each other where they stand,
/// with nothing climbing, bobbing or swinging, at a calmer pace.
const flightLoaderCalmSeconds = 8.8;

/// How long one form takes to become the next.
const _morphSeconds = 0.5;

/// The arrow in navy on a light ground, lit from the upper left like the
/// pearl.
const navyGlass = Glass(
  fill: [Color(0xFF2E4E76), Color(0xFF183250), Color(0xFF0E2136)],
  fillAngle: 145,
  rim: [Color(0x73FFFFFF), Color(0x1FFFFFFF), Color(0x00FFFFFF)],
  rimWidth: 1.2,
  wall: Color(0x00FFFFFF),
  highlight: GlassShadow(Color(0x47FFFFFF), dx: 1.2, dy: 1.8, blur: 2),
  glow: GlassShadow(Color(0x00000000)),
  shadows: [
    GlassShadow(Color(0x24020817), dy: 3, blur: 6),
    GlassShadow.none,
    GlassShadow(Color(0x1A020817), dy: 14, blur: 28),
  ],
);

double _smooth(double x) {
  final t = x.clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

double _inOut(double x) {
  final t = x.clamp(0.0, 1.0);
  return t < 0.5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3) / 2;
}

/// The loader: the arrow [size] tall, in a square 2.6 times that so the
/// plane has room to leave. [dark] is the theme's ground: pearl on the night,
/// navy on white.
class FlightLoader extends StatefulWidget {
  const FlightLoader({super.key, this.size = 64, this.dark = true});
  final double size;
  final bool dark;

  /// The square the loader takes, for a given arrow height.
  static double boxFor(double size) => size * 2.6;

  @override
  State<FlightLoader> createState() => _FlightLoaderState();
}

class _FlightLoaderState extends State<FlightLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4400),
  );
  bool? _calm;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final calm = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (calm == _calm) return;
    _calm = calm;
    _clock.duration = Duration(
        milliseconds:
            ((calm ? flightLoaderCalmSeconds : flightLoaderSeconds) * 1000)
                .round());
    _clock.repeat();
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: const Words('Loading', 'Chargement', 'جارٍ التحميل')
          .of(AppLanguageScope.of(context)),
      child: SizedBox.square(
        dimension: FlightLoader.boxFor(widget.size),
        child: RepaintBoundary(
          child: CustomPaint(
            painter: FlightLoaderPainter(
              _clock,
              size: widget.size,
              dark: widget.dark,
              calm: _calm ?? false,
            ),
          ),
        ),
      ),
    );
  }
}

/// The forms of the loop, each three pieces like the logo (the arrow and its
/// two steps), so each flows into the next piece for piece.
enum _Form { logo, stairs, rise, plane, cap }

/// Each form and how long it holds before it becomes the next; the last
/// flows back into the first.
const _scenes = [
  (_Form.logo, 0.7),
  (_Form.stairs, 1.1),
  (_Form.rise, 0.7),
  (_Form.plane, 0.9),
  (_Form.cap, 0.9),
];

/// One cell of the logo's grid: the mark is four cells tall.
const _cell = splashArrowHeight / 4;

/// The stairs: the logo's diagonal of cells, two thick, running on past the
/// round window they are seen through, moved [phase] cells up the way the
/// arrow points (1 is the same picture as 0, one step on).
Path _stairs(double phase) {
  final band = Path();
  final shift = Offset(_cell, -_cell) * phase;
  // Column c holds the cells whose row and column add to 1 and 2.
  double left(int c) => -_cell + _cell * c;
  double top(int c) => -_cell - _cell * c;
  Offset at(double x, double y) => Offset(x, y) + shift;
  const first = -5, last = 6;
  final start = at(left(first), top(first));
  band.moveTo(start.dx, start.dy);
  for (var c = first; c <= last; c++) {
    for (final p in [at(left(c), top(c)), at(left(c) + _cell, top(c))]) {
      band.lineTo(p.dx, p.dy);
    }
  }
  for (var c = last; c >= first; c--) {
    for (final p in [
      at(left(c) + _cell, top(c) + 2 * _cell),
      at(left(c), top(c) + 2 * _cell),
    ]) {
      band.lineTo(p.dx, p.dy);
    }
  }
  band.close();
  return Path.combine(PathOperation.intersect, band,
      Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: 48)));
}

/// A speck where a step is taken into the stairs.
Path _speck(Offset at) =>
    Path()..addRect(Rect.fromCenter(center: at, width: 1, height: 1));

Path _polygon(List<Offset> points) => Path()..addPolygon(points, true);

Path _bar(double l, double t, double r, double b, double radius) =>
    Path()..addRRect(RRect.fromLTRBR(l, t, r, b, Radius.circular(radius)));

/// The plane pointing straight up, a little smaller than at take-off.
const _planeHeading = -math.pi / 2;
const _planeScale = 0.72;

/// Where the cap's tassel hangs from.
const _tasselPivot = Offset(41.7, -16);

/// Each form's pieces, centred on the origin at the arrow's 100 pt height:
/// the main shape, then the piece that takes the near step's place, then
/// the far step's.
List<Path> _piecesOf(_Form form) {
  switch (form) {
    case _Form.logo:
      return arrowPieces(splashArrowHeight);
    case _Form.stairs:
      // The two steps go into the stairs they already sit on.
      return [
        _stairs(0),
        _speck(const Offset(-12.5, 12.5)),
        _speck(const Offset(-30, 30))
      ];
    case _Form.rise:
      // An arrow straight up, the two steps left behind as its trail.
      return [
        _polygon(const [
          Offset(0, -50),
          Offset(38, -12),
          Offset(13, -12),
          Offset(13, 42),
          Offset(-13, 42),
          Offset(-13, -12),
          Offset(-38, -12),
        ]),
        _bar(-33, 8, -25, 40, 4),
        _bar(25, 8, 33, 40, 4),
      ];
    case _Form.plane:
      final pose =
          takeoffPlanePose(Offset.zero, _planeHeading, _planeScale).storage;
      return [
        PlaneShape.body.transform(pose),
        PlaneShape.tailLeft.transform(pose),
        PlaneShape.tailRight.transform(pose),
      ];
    case _Form.cap:
      // The graduate's cap: the board and the crown as one, then the
      // tassel's cord and its tuft.
      final board = _polygon(const [
        Offset(0, -36),
        Offset(54, -16),
        Offset(0, 4),
        Offset(-54, -16),
      ]);
      final crown = Path()
        ..moveTo(-30, -12)
        ..lineTo(30, -12)
        ..lineTo(30, 14)
        ..quadraticBezierTo(0, 28, -30, 14)
        ..close();
      return [
        Path.combine(PathOperation.union, board, crown),
        _bar(40, -16, 43.4, 12, 1.7),
        _bar(36.5, 10, 46.9, 26, 3),
      ];
  }
}

/// One form flowing into the next: each piece's outline, point for point.
class _Change {
  _Change(List<Path> from, List<Path> to)
      : pieces = [
          for (var i = 0; i < 3; i++)
            () {
              final a = outlineOf(from[i], count: i == 0 ? 360 : 140);
              return (
                a,
                alignTo(a, outlineOf(to[i], count: i == 0 ? 360 : 140))
              );
            }(),
        ];
  final List<(List<Offset>, List<Offset>)> pieces;

  Path at(double main, double steps) {
    final path = Path();
    for (var i = 0; i < 3; i++) {
      final (a, b) = pieces[i];
      path.addPath(lerpOutline(a, b, i == 0 ? main : steps), Offset.zero);
    }
    return path;
  }
}

final List<_Change> _changes = () {
  final shapes = [for (final s in _scenes) _piecesOf(s.$1)];
  return [
    for (var i = 0; i < shapes.length; i++)
      _Change(shapes[i], shapes[(i + 1) % shapes.length]),
  ];
}();

/// Paints the loop at the clock's place (0 to 1 of a loop). Public for the
/// widget test and the frame renders.
class FlightLoaderPainter extends CustomPainter {
  FlightLoaderPainter(this.clock,
      {required this.size, required this.dark, this.calm = false})
      : super(repaint: clock);
  final Animation<double> clock;
  final double size;
  final bool dark;

  /// Reduce Motion: the forms change where they stand, nothing else moves.
  final bool calm;

  Glass get _arrowGlass => dark ? Glass.pearl : navyGlass;

  /// The plane's material in its own box, which points up like the screen.
  Glass get _planeGlass => dark ? planeGlass : navyGlass;

  Glass _glassOf(_Form form) => form == _Form.plane ? _planeGlass : _arrowGlass;

  @override
  void paint(Canvas canvas, Size box) {
    canvas.save();
    canvas.translate(box.width / 2, box.height / 2);
    canvas.scale(size / splashArrowHeight);
    if (dark) paintArrowGlow(canvas, 92, 0.6);
    // The same story at either pace: the clock is a share of the loop.
    var t = clock.value * flightLoaderSeconds;
    for (var i = 0; i < _scenes.length; i++) {
      final (form, hold) = _scenes[i];
      if (t < hold) {
        _paintHold(canvas, form, t, hold);
        break;
      }
      t -= hold;
      if (t < _morphSeconds || i == _scenes.length - 1) {
        final next = _scenes[(i + 1) % _scenes.length].$1;
        _paintChange(
            canvas, i, form, next, (t / _morphSeconds).clamp(0.0, 1.0));
        break;
      }
      t -= _morphSeconds;
    }
    canvas.restore();
  }

  /// [i]'s form [m] of the way into the next; the small pieces follow a
  /// beat behind, so it reads as one motion.
  void _paintChange(Canvas canvas, int i, _Form from, _Form to, double m) {
    final main = _inOut(m);
    final steps = _inOut((m - 0.15) / 0.85);
    final outline = _changes[i].at(main, steps);
    if (dark) {
      final change = math.sin(math.pi * main);
      if (change > 0.02) {
        canvas.drawPath(
            outline,
            Paint()
              ..color = Color.fromRGBO(200, 225, 250, 0.3 * change)
              ..maskFilter = MaskFilter.blur(BlurStyle.normal, 10 * change));
      }
    }
    _paintGlass(
        canvas, outline, Glass.lerp(_glassOf(from), _glassOf(to), main));
  }

  void _paintGlass(Canvas canvas, Path path, Glass glass) {
    final shape = GlassShape.path(path);
    paintGlassBody(canvas, shape, glass);
    paintGlassRim(canvas, shape, glass);
  }

  /// A form at rest, [t] of its [hold] seconds in: each one does what it
  /// stands for, and is back where it started when the hold ends.
  void _paintHold(Canvas canvas, _Form form, double t, double hold) {
    final f = (t / hold).clamp(0.0, 1.0);
    final move = calm ? 0.0 : 1.0;
    switch (form) {
      case _Form.logo:
        paintGlassArrow(canvas,
            height: splashArrowHeight,
            shine: calm ? -1 : f,
            // White light on navy reads as a smudge at full strength.
            shineStrength: dark ? 1 : 0.35,
            glass: _arrowGlass);
      case _Form.stairs:
        // Two steps up, one after the other, each with a moment's rest.
        final p = f * 2;
        final step = _inOut((p - p.floorToDouble()) * 1.25);
        _paintGlass(canvas, _stairs(step * move), _arrowGlass);
      case _Form.rise:
        // Up and back, the trail a little behind.
        final lift = -8 * math.sin(math.pi * f) * move;
        final pieces = _risePieces;
        final path = Path()
          ..addPath(pieces[0], Offset(0, lift))
          ..addPath(pieces[1], Offset(0, lift * 0.4))
          ..addPath(pieces[2], Offset(0, lift * 0.4));
        _paintGlass(canvas, path, _arrowGlass);
      case _Form.plane:
        // Its engines and lights come on, it climbs a little, and they go
        // out again just before it changes.
        final on = 1 - _smooth((t - hold + 0.22) / 0.22);
        canvas.save();
        canvas.transform(takeoffPlanePose(
                Offset(0, -6 * math.sin(math.pi * f) * move),
                _planeHeading,
                _planeScale)
            .storage);
        paintPearlPlane(canvas,
            detail: _smooth(t / 0.3) * on,
            lights: _smooth((t - 0.2) / 0.1) * on,
            clock: t,
            glass: _planeGlass,
            onLight: !dark);
        canvas.restore();
      case _Form.cap:
        // A small toss, and the tassel swings.
        final pieces = _capPieces;
        final swing = 0.45 * math.sin(3 * math.pi * f) * (1 - f) * move;
        final tassel = Matrix4.identity()
          ..translateByDouble(_tasselPivot.dx, _tasselPivot.dy, 0, 1)
          ..rotateZ(swing)
          ..translateByDouble(-_tasselPivot.dx, -_tasselPivot.dy, 0, 1);
        final toss = -7 * math.sin(math.pi * f) * move;
        final path = Path()
          ..addPath(pieces[0], Offset.zero)
          ..addPath(pieces[1].transform(tassel.storage), Offset.zero)
          ..addPath(pieces[2].transform(tassel.storage), Offset.zero);
        canvas.save();
        canvas.translate(0, toss);
        canvas.rotate(-0.08 * math.sin(2 * math.pi * f) * move);
        _paintGlass(canvas, path, _arrowGlass);
        canvas.restore();
    }
  }

  @override
  bool shouldRepaint(FlightLoaderPainter old) =>
      old.clock != clock ||
      old.size != size ||
      old.dark != dark ||
      old.calm != calm;
}

final List<Path> _risePieces = _piecesOf(_Form.rise);
final List<Path> _capPieces = _piecesOf(_Form.cap);
