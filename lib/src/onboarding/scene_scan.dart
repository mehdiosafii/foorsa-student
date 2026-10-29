/// The camera: the scanner's frame, and a passport page the student puts in
/// it. The page arrives in the frame (it is what the last object became),
/// lifts out of it into the student's hand, tipped and turned, and waits.
/// Dragged back, it straightens as it nears the frame and the scanner's
/// corners close on it; let go close enough, it settles in and is taken, the
/// way the app's scanner takes a paper. A tap puts it in by itself. The page
/// is a drawing, not a real passport: a photo, a few lines and a
/// machine-readable zone made up for a student called Foorsa.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'boarding_style.dart';
import 'scene_hint.dart';
import 'stage_forms.dart';

/// Where the page waits in the hand, as parts of its own size, from the
/// frame's middle.
const _restX = 0.13, _restY = 0.27;

/// How near it must be let go for the scanner to take it (1 is home).
const _takes = 0.6;

class ScanScene extends StatefulWidget {
  const ScanScene({
    super.key,
    required this.still,
    required this.feel,
    required this.armed,
    required this.label,
    required this.hint,
    required this.onAct,
    required this.outcome,
  });

  final bool still;
  final Feel feel;
  final bool armed;
  final String label;
  final String hint;
  final SceneAct onAct;

  /// null until the student answers; then whether the camera is on.
  final ValueListenable<bool?> outcome;

  @override
  State<ScanScene> createState() => _ScanSceneState();
}

class _ScanSceneState extends State<ScanScene> with TickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<double> _clock = ValueNotifier<double>(0);

  /// Moves the student makes, for a phone whose clock stands still.
  final ValueNotifier<int> _moved = ValueNotifier<int>(0);

  /// Where the student has the page, from the frame's middle, while they
  /// hold it.
  Offset? _held;

  /// The page going home or back to the hand on its own: from, to, and the
  /// spring's way between them (0 to 1).
  late final AnimationController _settle =
      AnimationController.unbounded(vsync: this);
  Offset? _settleFrom, _settleTo;

  bool _captured = false;
  double _capturedAt = -1;
  double _readFrom = -1;
  double _idleFrom = 0;
  bool _found = false;
  double _pageWidth = 250;

  @override
  void initState() {
    super.initState();
    _ticker =
        createTicker((elapsed) => _clock.value = elapsed.inMicroseconds / 1e6);
    if (!widget.still) _ticker.start();
    _settle.addListener(_settled);
    widget.outcome.addListener(_answered);
  }

  @override
  void didUpdateWidget(ScanScene old) {
    super.didUpdateWidget(old);
    if (old.outcome != widget.outcome) {
      old.outcome.removeListener(_answered);
      widget.outcome.addListener(_answered);
    }
    if (widget.armed && !old.armed) _idleFrom = _clock.value;
  }

  @override
  void dispose() {
    widget.outcome.removeListener(_answered);
    _ticker.dispose();
    _settle.dispose();
    _clock.dispose();
    _moved.dispose();
    super.dispose();
  }

  void _bump() => _moved.value++;

  void _settled() {
    _bump();
    // Taken as it arrives, not once the spring has spent its last pixel.
    if (_captured && _capturedAt < 0 && _settle.value > 0.94) _take();
  }

  void _answered() {
    if (widget.outcome.value != true || !mounted) return;
    // The camera is on: light reads across the page once.
    setState(() => _readFrom = _clock.value);
  }

  Offset get _rest {
    final w = _pageWidth, h = w * 0.704;
    return Offset(w * _restX, h * _restY);
  }

  /// Where the page is now, from the frame's middle.
  Offset get _offset {
    if (_captured && !_settle.isAnimating) return Offset.zero;
    final held = _held;
    if (held != null) return held;
    final from = _settleFrom, to = _settleTo;
    if (from != null && to != null) {
      return Offset.lerp(from, to, _settle.value)!;
    }
    if (widget.still) return _rest;
    // It arrives in the frame, then lifts out into the hand.
    final t = _clock.value;
    final lift = ease(t, 0.3, 1.05);
    // Until it is touched, it drifts a little towards the frame now and
    // then, to show where it goes.
    final nudge = widget.armed ? idleNudge(t - _idleFrom, after: 1.6) : 0.0;
    return _rest * (lift * (1 - 0.22 * nudge));
  }

  /// 1 in the frame, 0 in the hand.
  double _near(Offset offset) =>
      1 - (offset.distance / _rest.distance).clamp(0.0, 1.0);

  void _grab(DragStartDetails _) {
    if (!widget.armed || _captured) return;
    _settle.stop();
    _held = _offset;
    _settleFrom = _settleTo = null;
    _found = _near(_held!) > 0.8;
    widget.feel('press');
  }

  void _move(DragUpdateDetails details) {
    final held = _held;
    if (held == null || _captured) return;
    final w = _pageWidth, h = w * 0.704;
    final next = held + details.delta;
    _held = Offset(next.dx.clamp(-w * 0.8, w * 0.8).toDouble(),
        next.dy.clamp(-h * 0.9, h * 0.9).toDouble());
    final near = _near(_held!);
    // The corners find it as it comes in, and let go of it as it leaves.
    if (!_found && near > 0.8) {
      _found = true;
      widget.feel('detent');
    } else if (_found && near < 0.6) {
      _found = false;
    }
    _bump();
  }

  void _drop(DragEndDetails details) {
    final held = _held;
    if (held == null || _captured) return;
    // Where it would come to rest, carried by the throw.
    final v = details.velocity.pixelsPerSecond;
    final landing = held + v * 0.12;
    if (_near(held) > _takes || _near(landing) > _takes + 0.15) {
      _home(velocity: v);
    } else {
      _back(velocity: v);
      widget.feel('detent');
    }
  }

  void _tap() {
    if (!widget.armed || _captured) return;
    widget.feel('press');
    _home();
  }

  /// Back to the hand, where it waits again.
  void _back({Offset velocity = Offset.zero}) {
    final from = _offset;
    final target = _rest;
    _held = null;
    _found = false;
    if (widget.still) {
      _settleFrom = _settleTo = null;
      _bump();
      return;
    }
    _settleFrom = from;
    _settleTo = target;
    final span = (target - from).distance;
    _settle.value = 0;
    _settle
        .animateWith(SpringSimulation(
            foorsaSpring(damping: 0.78, response: 0.4),
            0,
            1,
            span < 1
                ? 0
                : (velocity.dx * (target - from).dx +
                        velocity.dy * (target - from).dy) /
                    (span * span)))
        .whenComplete(() {
      if (!mounted || _held != null || _captured) return;
      _settleFrom = _settleTo = null;
      _idleFrom = _clock.value;
    });
  }

  /// Into the frame, and taken.
  void _home({Offset velocity = Offset.zero}) {
    if (_captured) return;
    final from = _offset;
    _held = null;
    _found = true;
    setState(() => _captured = true);
    if (widget.still) {
      _take();
      return;
    }
    _settleFrom = from;
    _settleTo = Offset.zero;
    final span = from.distance;
    _settle.value = 0;
    _settle
        .animateWith(SpringSimulation(
            foorsaSpring(damping: 0.86, response: 0.32),
            0,
            1,
            span < 1
                ? 0
                : -(velocity.dx * from.dx + velocity.dy * from.dy) /
                    (span * span)))
        .whenCompleteOrCancel(_take);
  }

  /// The scanner takes the page: its corners close, a breath of light, and
  /// the phone asks for the camera.
  void _take() {
    if (!mounted || _capturedAt >= 0) return;
    setState(() => _capturedAt = _clock.value);
    widget.feel('detent');
    widget.onAct();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      _pageWidth = pageWidth(box.maxWidth);
      final w = _pageWidth, h = w * 0.704;
      final frame = Size(w + 54, h + 74);
      return Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(
          child: Semantics(
            button: true,
            enabled: widget.armed && !_captured,
            label: widget.label,
            excludeSemantics: true,
            onTap: widget.armed && !_captured ? _tap : null,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _tap,
              onPanStart: _grab,
              onPanUpdate: _move,
              onPanEnd: _drop,
              onPanCancel: () {
                if (_held != null && !_captured) _back();
              },
              child: CustomPaint(
                painter: _ScanPainter(
                  Listenable.merge([_clock, _moved]),
                  _clock,
                  still: widget.still,
                  page: w,
                  offset: () => _offset,
                  near: _near,
                  capturedAt: _capturedAt,
                  readFrom: _readFrom,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: box.maxHeight / 2 + frame.height / 2 + 18,
          child: GestureHint(widget.hint,
              still: widget.still, shown: widget.armed && !_captured),
        ),
      ]);
    });
  }
}

class _ScanPainter extends CustomPainter {
  _ScanPainter(
    Listenable repaint,
    this.clock, {
    required this.still,
    required this.page,
    required this.offset,
    required this.near,
    required this.capturedAt,
    required this.readFrom,
  }) : super(repaint: repaint);

  final ValueNotifier<double> clock;
  final bool still;

  /// The page's width; a passport page is 125 by 88 mm.
  final double page;
  final Offset Function() offset;
  final double Function(Offset) near;
  final double capturedAt;
  final double readFrom;

  static final _mrz = [
    'P<MARSTUDENT<<FOORSA'.padRight(44, '<'),
    '${'FS20260011MAR0601012<3601017'.padRight(42, '<')}02',
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final t = clock.value;
    final w = page, h = page * 0.704;
    final centre = size.center(Offset.zero);
    final at = offset();
    final p = near(at);
    final away = 1 - p;
    final taken = capturedAt >= 0;
    final since = taken ? t - capturedAt : -1.0;

    // In the hand it is tipped back and turned, and a little smaller; it
    // straightens as it comes home.
    final tilt = 0.42 * away;
    final turn = -0.17 * away;
    final scale = 1 - 0.1 * away;
    final m = Matrix4.identity()
      ..translateByDouble(centre.dx + at.dx, centre.dy + at.dy, 0, 1)
      ..multiply(Matrix4.identity()..setEntry(3, 2, 0.0017))
      ..rotateX(tilt)
      ..rotateZ(turn)
      ..scaleByDouble(scale, scale, 1, 1)
      ..translateByDouble(-w / 2, -h / 2, 0, 1);

    Offset project(double x, double y) =>
        MatrixUtils.transformPoint(m, Offset(x, y));
    final quad = [project(0, 0), project(w, 0), project(w, h), project(0, h)];

    // Its shadow: lifted in the hand, close under it in the frame.
    final bottom = (quad[2].dy + quad[3].dy) / 2;
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(centre.dx + at.dx, bottom + 12 + 18 * away),
          width: w * (0.86 - 0.12 * away),
          height: 14 + 6 * away),
      Paint()
        ..color = Color.fromRGBO(0, 0, 0, 0.5 - 0.2 * away)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 12 + 8 * away),
    );

    // The read: light runs across the page once the camera is on.
    final read = readFrom >= 0 ? ((t - readFrom) / 0.9).clamp(0.0, 1.0) : 0.0;
    canvas.save();
    canvas.transform(m.storage);
    _page(canvas, w, h, read);
    // The scanner's flash as it takes the page: the paper lit up for a
    // moment, its print paling under the light.
    if (taken && !still && since < 0.36) {
      final flash = 0.42 * (1 - Curves.easeOut.transform(since / 0.36));
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(0, 0, w, h), Radius.circular(w * 0.035)),
          Paint()..color = Color.fromRGBO(255, 255, 255, flash));
    }
    canvas.restore();

    // The scanner's corners: on the frame while they look for the page,
    // closing on it as it comes home, and tight round it once taken.
    final frame =
        Rect.fromCenter(center: centre, width: w + 54, height: h + 74);
    final wide = [
      frame.topLeft,
      frame.topRight,
      frame.bottomRight,
      frame.bottomLeft
    ];
    final appear = still ? 1.0 : ease(t, 0.12, 0.5);
    final hold = ease(p, 0.45, 0.95);
    final breathe = still ? 0.0 : math.sin(t * 3.2) * 2.5 * (1 - hold);
    // Once taken, they pinch in and settle.
    final pinch = taken && !still
        ? math.sin(math.pi * (since / 0.32).clamp(0.0, 1.0)) * 5
        : 0.0;
    final outset = 9.0 - pinch;
    const signs = [Offset(-1, -1), Offset(1, -1), Offset(1, 1), Offset(-1, 1)];
    final corners = [
      for (var i = 0; i < 4; i++)
        Offset.lerp(
            wide[i] + signs[i] * breathe, quad[i] + signs[i] * outset, hold)!,
    ];
    final lit = taken ? 1.0 : 0.62 + 0.38 * hold;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Color.fromRGBO(244, 247, 251, 0.95 * appear * lit);
    for (var i = 0; i < 4; i++) {
      final here = corners[i];
      final along = corners[(i + 1) % 4];
      final back = corners[(i + 3) % 4];
      const arm = 20.0;
      final a = here + _unit(along - here) * arm;
      final b = here + _unit(back - here) * arm;
      canvas.drawPath(
          Path()
            ..moveTo(a.dx, a.dy)
            ..lineTo(here.dx, here.dy)
            ..lineTo(b.dx, b.dy),
          stroke);
    }
  }

  static Offset _unit(Offset o) => o / math.max(o.distance, 0.001);

  void _page(Canvas canvas, double w, double h, double read) {
    final card = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, h), Radius.circular(w * 0.035));
    canvas.drawRRect(
      card,
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, Offset(w, h), const [
          Color(0xFFF7F5EF),
          Color(0xFFEDE9DF),
        ]),
    );
    canvas.save();
    canvas.clipRRect(card);
    final u = w / 250;

    // The title band.
    final faint = Paint()..color = const Color(0xFFDCD6CA);
    final mid = Paint()..color = const Color(0xFFC3BCAE);
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(16 * u, 14 * u, 78 * u, 5 * u),
            Radius.circular(3 * u)),
        mid);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(w - 54 * u, 14 * u, 38 * u, 5 * u),
            Radius.circular(3 * u)),
        faint);

    // The photo.
    final photo = Rect.fromLTWH(16 * u, 30 * u, 56 * u, 72 * u);
    canvas.drawRRect(RRect.fromRectAndRadius(photo, Radius.circular(4 * u)),
        Paint()..color = const Color(0xFFD3DAE2));
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(photo, Radius.circular(4 * u)));
    final person = Paint()..color = const Color(0xFFB3BECA);
    canvas.drawCircle(photo.center + Offset(0, -10 * u), 13 * u, person);
    canvas.drawOval(
        Rect.fromCenter(
            center: Offset(photo.center.dx, photo.bottom + 6 * u),
            width: 50 * u,
            height: 46 * u),
        person);
    canvas.restore();

    // The fields: a label and its value, four times.
    const values = [92.0, 64.0, 78.0, 54.0];
    for (var i = 0; i < 4; i++) {
      final y = (32 + i * 18) * u;
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(84 * u, y, 26 * u, 3 * u), Radius.circular(2 * u)),
          faint);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(84 * u, y + 6 * u, values[i] * u, 5 * u),
              Radius.circular(3 * u)),
          mid);
    }

    // The machine-readable zone.
    final style = Boarding.monoStyle(7.05 * u,
        color: const Color(0xFF8C877D), weight: FontWeight.w500, spacing: 0);
    for (var i = 0; i < _mrz.length; i++) {
      final painter = TextPainter(
        text: TextSpan(text: _mrz[i], style: style),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: w - 24 * u);
      painter.paint(canvas, Offset(14 * u, h - (30 - i * 11) * u));
      painter.dispose();
    }

    // Read: light runs across it once.
    if (read > 0 && read < 1) {
      final x =
          ui.lerpDouble(-w * 0.5, w * 1.5, Curves.easeInOut.transform(read))!;
      canvas.drawRect(
        Rect.fromLTWH(0, 0, w, h),
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = ui.Gradient.linear(
              Offset(x - w * 0.3, 0), Offset(x + w * 0.1, h), const [
            Color(0x00FFFFFF),
            Color(0x40FFFFFF),
            Color(0x00FFFFFF),
          ], const [
            0,
            0.5,
            1
          ]),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ScanPainter old) => true;
}
