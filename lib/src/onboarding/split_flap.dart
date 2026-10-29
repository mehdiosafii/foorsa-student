/// A line of an airport's split-flap board: each character is a flap that
/// falls through the alphabet to its letter, the top half folding down over
/// the hinge, then the bottom half landing, in perspective. One painter draws
/// the whole line, from glyphs laid out once.
library;

import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

const flapCharacters = " ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'-:·";

class SplitFlapLine extends StatefulWidget {
  const SplitFlapLine({
    super.key,
    required this.text,
    required this.length,
    required this.cellWidth,
    required this.cellHeight,
    this.gap = 3,
    this.color = const Color(0xFFF2F5F9),
    this.fontSize,
    this.still = false,
    this.onSettled,
    this.seed = 0,
  });

  final String text;
  final int length;
  final double cellWidth;
  final double cellHeight;
  final double gap;
  final Color color;
  final double? fontSize;

  /// Reduce Motion: the letters change without flipping.
  final bool still;

  /// Every flap has landed on its letter.
  final VoidCallback? onSettled;
  final int seed;

  @override
  State<SplitFlapLine> createState() => _SplitFlapLineState();
}

class _Flap {
  _Flap(this.index);
  int index;
  List<int> path = const [];
  double start = 0;
  double step = 0.068;
}

class _SplitFlapLineState extends State<SplitFlapLine>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final ValueNotifier<double> _now = ValueNotifier<double>(0);
  late List<_Flap> _flaps;
  late final math.Random _random = math.Random(widget.seed + 7);
  double _elapsed = 0;
  bool _flipping = false;

  static int _indexOf(String c) {
    final i = flapCharacters.indexOf(c.toUpperCase());
    return i < 0 ? 0 : i;
  }

  String _padded(String text) =>
      text.toUpperCase().padRight(widget.length).substring(0, widget.length);

  @override
  void initState() {
    super.initState();
    // The board starts blank and flips to its first word.
    _flaps = List<_Flap>.generate(widget.length, (_) => _Flap(0));
    _flipTo(widget.text);
  }

  @override
  void didUpdateWidget(SplitFlapLine old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) _flipTo(widget.text);
  }

  void _flipTo(String text) {
    final target = _padded(text);
    if (widget.still) {
      for (var i = 0; i < _flaps.length; i++) {
        _flaps[i]
          ..index = _indexOf(target[i])
          ..path = const [];
      }
      _now.value = _elapsed;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => widget.onSettled?.call());
      return;
    }
    final base = _elapsed;
    for (var i = 0; i < _flaps.length; i++) {
      final flap = _flaps[i];
      // Settle whatever was mid-flip on the letter it was heading for.
      if (flap.path.isNotEmpty) flap.index = flap.path.last;
      final to = _indexOf(target[i]);
      final count = flapCharacters.length;
      final distance = (to - flap.index) % count;
      if (distance == 0) {
        flap.path = const [];
        continue;
      }
      // A real board runs the whole drum; this one shows the last few letters
      // before each, so a word lands in about half a second.
      final shown = math.min(distance, 5 + _random.nextInt(6));
      final from = (to - shown) % count;
      flap.path = [for (var k = 0; k <= shown; k++) (from + k) % count];
      flap.index = flap.path.first;
      flap.start = base + i * 0.036 + _random.nextDouble() * 0.05;
      flap.step = 0.058 + _random.nextDouble() * 0.018;
    }
    _flipping = true;
    if (!_ticker.isActive) {
      _base = _elapsed;
      _ticker.start();
    }
  }

  /// The ticker counts from zero each time it starts; this keeps one clock.
  double _base = 0;

  void _tick(Duration elapsed) {
    _elapsed = _base + elapsed.inMicroseconds / 1e6;
    _now.value = _elapsed;
    if (!_flipping) return;
    var busy = false;
    for (final flap in _flaps) {
      if (flap.path.isEmpty) continue;
      final steps = flap.path.length - 1;
      if (_elapsed < flap.start + steps * flap.step) {
        busy = true;
      } else {
        flap.index = flap.path.last;
        flap.path = const [];
      }
    }
    if (!busy) {
      _flipping = false;
      _ticker.stop();
      widget.onSettled?.call();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _now.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width =
        widget.length * widget.cellWidth + (widget.length - 1) * widget.gap;
    final style = DefaultTextStyle.of(context).style.copyWith(
      fontSize: widget.fontSize ?? widget.cellHeight * 0.62,
      fontWeight: FontWeight.w700,
      color: widget.color,
      height: 1,
      letterSpacing: 0,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Semantics(
      label: widget.text,
      excludeSemantics: true,
      child: SizedBox(
        width: width,
        height: widget.cellHeight,
        child: CustomPaint(
          painter: _FlapPainter(
            flaps: _flaps,
            now: _now,
            cellWidth: widget.cellWidth,
            cellHeight: widget.cellHeight,
            gap: widget.gap,
            glyphs: _Glyphs.of(style, Directionality.of(context)),
          ),
        ),
      ),
    );
  }
}

/// The board's letters, laid out once per style.
class _Glyphs {
  _Glyphs(this.painters);
  final List<TextPainter> painters;

  static final Map<TextStyle, _Glyphs> _cache = {};

  static _Glyphs of(TextStyle style, TextDirection direction) =>
      _cache.putIfAbsent(style, () {
        return _Glyphs([
          for (final c in flapCharacters.split(''))
            TextPainter(
                text: TextSpan(text: c, style: style), textDirection: direction)
              ..layout(),
        ]);
      });
}

class _FlapPainter extends CustomPainter {
  _FlapPainter({
    required this.flaps,
    required this.now,
    required this.cellWidth,
    required this.cellHeight,
    required this.gap,
    required this.glyphs,
  }) : super(repaint: now);

  final List<_Flap> flaps;
  final ValueNotifier<double> now;
  final double cellWidth;
  final double cellHeight;
  final double gap;
  final _Glyphs glyphs;

  static const _top = Color(0xFF1A2A3E);
  static const _bottom = Color(0xFF15233A);
  static const _hinge = Color(0xFF060B12);

  @override
  void paint(Canvas canvas, Size size) {
    final t = now.value;
    final radius = Radius.circular(cellHeight * 0.13);
    for (var i = 0; i < flaps.length; i++) {
      final flap = flaps[i];
      final cell =
          Rect.fromLTWH(i * (cellWidth + gap), 0, cellWidth, cellHeight);
      var current = flap.index;
      var next = flap.index;
      var f = 1.0;
      if (flap.path.isNotEmpty && t >= flap.start) {
        final k = ((t - flap.start) / flap.step).floor();
        if (k < flap.path.length - 1) {
          current = flap.path[k];
          next = flap.path[k + 1];
          f = ((t - flap.start) - k * flap.step) / flap.step;
        } else {
          current = next = flap.path.last;
        }
      }
      _cell(canvas, cell, radius, current, next, f.clamp(0.0, 1.0));
    }
  }

  void _half(Canvas canvas, Rect cell, Radius radius, int glyph,
      {required bool top, double shade = 0}) {
    final mid = cell.center.dy;
    final half = top
        ? Rect.fromLTRB(cell.left, cell.top, cell.right, mid - 0.5)
        : Rect.fromLTRB(cell.left, mid + 0.5, cell.right, cell.bottom);
    final shape = top
        ? RRect.fromRectAndCorners(half, topLeft: radius, topRight: radius)
        : RRect.fromRectAndCorners(half,
            bottomLeft: radius, bottomRight: radius);
    canvas.drawRRect(shape, Paint()..color = top ? _top : _bottom);
    canvas.save();
    canvas.clipRRect(shape);
    final painter = glyphs.painters[glyph];
    painter.paint(canvas,
        Offset(cell.center.dx - painter.width / 2, mid - painter.height / 2));
    if (top) {
      // A little light along the top edge of the flap.
      canvas.drawRect(Rect.fromLTWH(half.left, half.top, half.width, 1),
          Paint()..color = const Color(0x14FFFFFF));
    }
    if (shade > 0) {
      canvas.drawRRect(shape, Paint()..color = Color.fromRGBO(0, 0, 0, shade));
    }
    canvas.restore();
  }

  void _cell(Canvas canvas, Rect cell, Radius radius, int current, int next,
      double f) {
    final hingeY = cell.center.dy;
    if (current == next || f >= 1) {
      _half(canvas, cell, radius, next, top: true);
      _half(canvas, cell, radius, next, top: false);
    } else {
      // Behind: the next letter's top, the current letter's bottom.
      _half(canvas, cell, radius, next, top: true);
      _half(canvas, cell, radius, current,
          top: false, shade: f < 0.5 ? 0 : 0.28 * (1 - f) * 2);
      final hinged = Matrix4.identity()..setEntry(3, 2, 0.0035);
      canvas.save();
      canvas.translate(cell.center.dx, hingeY);
      if (f < 0.5) {
        // The current letter's top folds down towards the viewer.
        final angle = f * 2 * math.pi / 2;
        canvas.transform((hinged..rotateX(angle)).storage);
        canvas.translate(-cell.center.dx, -hingeY);
        _half(canvas, cell, radius, current, top: true, shade: 0.45 * f * 2);
      } else {
        // The next letter's bottom lands.
        final angle = -(1 - (f - 0.5) * 2) * math.pi / 2;
        canvas.transform((hinged..rotateX(angle)).storage);
        canvas.translate(-cell.center.dx, -hingeY);
        _half(canvas, cell, radius, next,
            top: false, shade: 0.3 * (1 - (f - 0.5) * 2));
      }
      canvas.restore();
    }
    // The hinge.
    canvas.drawRect(Rect.fromLTWH(cell.left, hingeY - 0.5, cell.width, 1),
        Paint()..color = _hinge);
    // Pins at the hinge's ends.
    final pin = Paint()..color = const Color(0xFF0A121C);
    canvas.drawRect(Rect.fromLTWH(cell.left, hingeY - 2, 1.6, 4), pin);
    canvas.drawRect(Rect.fromLTWH(cell.right - 1.6, hingeY - 2, 1.6, 4), pin);
  }

  @override
  bool shouldRepaint(_FlapPainter old) => true;
}
