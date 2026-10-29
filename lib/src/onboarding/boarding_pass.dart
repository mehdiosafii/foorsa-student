/// The last screen: a boarding pass on the portal's paper (FlightPass,
/// flightPass.css), the perforation with its two punched notches, and a stub
/// that tears off under the finger, which is how the student boards. "Board"
/// tears it for them.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import 'airliner.dart';
import 'boarding_style.dart';
import 'brand_marks.dart';
import 'stage_forms.dart';

const _passWidth = passWidth;
/// The perforation's band, its middle at [passTearY].
const _tearHeight = 20.0;
const _passHeight = passHeight;
const _tearY = passTearY;

class BoardingPassScene extends StatefulWidget {
  const BoardingPassScene({
    super.key,
    required this.still,
    required this.feel,
    required this.onTorn,
    this.onTear,
  });

  final bool still;
  final Feel feel;

  /// The paper gives: its sound.
  final VoidCallback? onTear;

  /// The stub is off: board.
  final VoidCallback onTorn;

  @override
  State<BoardingPassScene> createState() => BoardingPassSceneState();
}

class BoardingPassSceneState extends State<BoardingPassScene>
    with TickerProviderStateMixin {
  // How far the stub is pulled, in px.
  late final AnimationController _pull =
      AnimationController.unbounded(vsync: this);
  // The stub falling once it is off.
  late final AnimationController _fall = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900));
  bool _torn = false;
  int _lastNotch = 0;

  static const _tearAt = 110.0;

  @override
  void initState() {
    super.initState();
    _pull.addListener(_pullFeel);
  }

  void _pullFeel() {
    final notch = (_pull.value / _tearAt * 8).floor();
    if (notch > _lastNotch && !_torn) {
      widget.feel('grain', (_pull.value / _tearAt).clamp(0.0, 1.0));
    }
    _lastNotch = math.max(0, notch);
  }

  @override
  void dispose() {
    _pull.dispose();
    _fall.dispose();
    super.dispose();
  }

  /// The arrow is cutting along the perforation, [p] of the way: the stub
  /// comes away behind it.
  void peel(double p) {
    if (_torn) return;
    _pull.value = p.clamp(0.0, 1.0) * _tearAt;
  }

  /// The stub falls away, cut by the arrow rather than torn by hand.
  void tearQuietly() {
    if (_torn) return;
    setState(() => _torn = true);
    if (!widget.still) _fall.forward();
  }

  void _complete() {
    if (_torn) return;
    setState(() => _torn = true);
    widget.feel('release');
    widget.onTear?.call();
    if (widget.still) {
      widget.onTorn();
      return;
    }
    _fall.forward();
    Timer(const Duration(milliseconds: 260), widget.onTorn);
  }

  void _drag(DragUpdateDetails details) {
    if (_torn) return;
    _pull.value = math.max(
        0,
        _pull.value +
            details.delta.dy * (_pull.value > _tearAt * 0.7 ? 0.8 : 1));
    if (_pull.value >= _tearAt) _complete();
  }

  void _release(DragEndDetails details) {
    if (_torn) return;
    final velocity = details.velocity.pixelsPerSecond.dy;
    if (_pull.value > _tearAt * 0.55 || velocity > 750) {
      _complete();
    } else {
      widget.feel('detent');
      _pull.animateWith(SpringSimulation(
          foorsaSpring(damping: 0.62, response: 0.32),
          _pull.value,
          0,
          velocity));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Your boarding pass. Tear off the stub, or tap Board.',
      child: LayoutBuilder(builder: (context, constraints) {
        // The pass is drawn at its own size, fitted to the stage and
        // centred, where the transition leaves it.
        final scale = passScale(constraints.biggest);
        return Center(
          child: SizedBox(
            width: _passWidth * scale,
            height: _passHeight * scale,
            child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: _passWidth,
                height: _passHeight,
                child: AnimatedBuilder(
                  animation: Listenable.merge([_pull, _fall]),
                  builder: (context, _) => _pass(),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _pass() {
    final pull = _pull.value.clamp(0.0, _tearAt + 30);
    final fall = _fall.value;
    final tearAngle = (pull / _tearAt) * 0.1 + fall * 0.5;
    final stubDrop = pull * 0.32 + fall * fall * 420;
    return Stack(clipBehavior: Clip.none, children: [
      // The upper piece's shadow lies under everything, the stub too.
      const Positioned(
        left: 0,
        top: 0,
        width: _passWidth,
        height: _tearY,
        child: CustomPaint(painter: _PieceShadowPainter(true)),
      ),
      // The stub, its own piece below the perforation.
      Positioned(
        left: 0,
        top: _tearY,
        width: _passWidth,
        height: _passHeight - _tearY,
        child: Opacity(
          opacity: (1 - fall * 1.3).clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(fall * 40, stubDrop),
            child: Transform.rotate(
              angle: tearAngle,
              alignment: Alignment.topRight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragUpdate: _drag,
                onVerticalDragEnd: _release,
                child: _Piece(top: false, child: _stub()),
              ),
            ),
          ),
        ),
      ),
      Positioned(
        left: 0,
        top: 0,
        width: _passWidth,
        height: _tearY,
        child: _Piece(top: true, shadow: false, child: _upper()),
      ),
    ]);
  }

  Widget _upper() {
    return Container(
      color: Boarding.paper,
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const FoorsaWordmark(height: 18, color: Boarding.passInk),
          const Spacer(),
          Text('BOARDING PASS',
              style: Boarding.caption(
                  color: Boarding.passLabel, size: 8.5, spacing: 1.8)),
        ]),
        const SizedBox(height: 30),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _end('CMN', 'Casablanca', CrossAxisAlignment.start),
          const Expanded(child: _Airway()),
          _end('CHN', 'China', CrossAxisAlignment.end),
        ]),
        const SizedBox(height: 22),
        Container(height: 1, color: Boarding.passRule),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: _field('PASSENGER', 'FOORSA STUDENT')),
          _field('GATE', 'SIGN IN', end: true),
        ]),
      ]),
    );
  }

  Widget _stub() {
    final hint = widget.still ? 0.0 : (1 - _pull.value / 36).clamp(0.0, 1.0);
    return Container(
      color: Boarding.paper,
      child: Column(children: [
        // The lower half of the perforation band, with its dashes.
        SizedBox(
          height: _tearHeight / 2,
          child: CustomPaint(
              size: const Size(_passWidth, _tearHeight / 2),
              painter: _PerforationPainter()),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 6, 24, 16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // The barcode takes what the stub has left.
              const Expanded(
                child: SizedBox(
                    width: double.infinity,
                    child: CustomPaint(painter: _BarcodePainter())),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: Text('FS2026 · CMN · CHN · 0001',
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: Boarding.monoStyle(9.5,
                          color: Boarding.passLabel, spacing: 1)),
                ),
                if (hint > 0)
                  Opacity(
                    opacity: hint,
                    child: Text('PULL TO BOARD',
                        style: Boarding.caption(
                            color: Boarding.passInk, size: 8.5, spacing: 1.6)),
                  ),
              ]),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _end(String code, String city, CrossAxisAlignment align) =>
      Column(crossAxisAlignment: align, children: [
        Text(code,
            style: const TextStyle(
              fontSize: 42,
              height: 1.05,
              letterSpacing: -1.6,
              fontWeight: FontWeight.w600,
              color: Boarding.passInk,
              fontFeatures: [FontFeature.tabularFigures()],
            )),
        const SizedBox(height: 4),
        Text(city,
            style: const TextStyle(
                fontSize: 11.5, height: 1.3, color: Boarding.passLabel)),
      ]);

  Widget _field(String label, String value, {bool end = false}) => Column(
        crossAxisAlignment:
            end ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(label,
              style: Boarding.caption(
                  color: Boarding.passLabel, size: 8, spacing: 1.4)),
          const SizedBox(height: 5),
          Text(value,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                  color: Boarding.passInk)),
        ],
      );
}

/// A piece of the pass: the paper's rounded corners and its two notches.
class _Piece extends StatelessWidget {
  const _Piece({required this.top, required this.child, this.shadow = true});
  final bool top;
  final bool shadow;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: shadow ? _PieceShadowPainter(top) : null,
      child: ClipPath(clipper: _PieceClipper(top), child: child),
    );
  }
}

Path _piecePath(Size size, bool top) {
  const r = 20.0, notch = 10.0;
  final rect = Offset.zero & size;
  final shape = Path()
    ..addRRect(top
        ? RRect.fromRectAndCorners(rect,
            topLeft: const Radius.circular(r),
            topRight: const Radius.circular(r))
        : RRect.fromRectAndCorners(rect,
            bottomLeft: const Radius.circular(r),
            bottomRight: const Radius.circular(r)));
  final y = top ? size.height : 0.0;
  final holes = Path()
    ..addOval(Rect.fromCircle(center: Offset(0, y), radius: notch))
    ..addOval(Rect.fromCircle(center: Offset(size.width, y), radius: notch));
  return Path.combine(PathOperation.difference, shape, holes);
}

class _PieceClipper extends CustomClipper<Path> {
  _PieceClipper(this.top);
  final bool top;

  @override
  Path getClip(Size size) => _piecePath(size, top);

  @override
  bool shouldReclip(_PieceClipper old) => old.top != top;
}

class _PieceShadowPainter extends CustomPainter {
  const _PieceShadowPainter(this.top);
  final bool top;

  @override
  void paint(Canvas canvas, Size size) {
    final path = _piecePath(size, top);
    canvas.drawPath(
        path.shift(const Offset(0, 18)),
        Paint()
          ..color = const Color(0x6B000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24));
  }

  @override
  bool shouldRepaint(_PieceShadowPainter old) => old.top != top;
}

class _PerforationPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFCFCBC0)
      ..strokeWidth = 1;
    for (var x = 18.0; x < size.width - 18; x += 7) {
      canvas.drawLine(Offset(x, 0.5), Offset(x + 3.5, 0.5), paint);
    }
  }

  @override
  bool shouldRepaint(_PerforationPainter old) => false;
}

/// The route between the codes: the plane, on its way.
class _Airway extends StatelessWidget {
  const _Airway();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 15),
      child: Center(
        child: Transform.rotate(
          angle: math.pi / 2,
          child: const SizedBox.square(
            dimension: 18,
            child: CustomPaint(
                painter: AirlinerSilhouettePainter(Boarding.passInk)),
          ),
        ),
      ),
    );
  }
}

/// A barcode, the same for everyone: it carries nothing.
class _BarcodePainter extends CustomPainter {
  const _BarcodePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(2026);
    final paint = Paint()..color = Boarding.passInk;
    var x = 0.0;
    while (x < size.width) {
      final bar = 1.0 + random.nextInt(3);
      final gap = 1.0 + random.nextInt(3);
      canvas.drawRect(
          Rect.fromLTWH(x, 0, math.min(bar, size.width - x), size.height),
          paint);
      x += bar + gap;
    }
  }

  @override
  bool shouldRepaint(_BarcodePainter old) => false;
}
