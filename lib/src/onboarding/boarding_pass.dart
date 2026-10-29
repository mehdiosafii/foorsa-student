/// The last screen: a boarding pass in the portal's own design (FlightPass,
/// flightPass.css: paper, ink, the dark header with the wordmark, the
/// perforation with its two punched notches). It prints out of a slot, says
/// what the student chose, and its stub tears off under the finger, which is
/// how the student boards. "Board" tears it for them.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import 'airliner.dart';
import 'boarding_style.dart';
import 'brand_marks.dart';
import 'lucide.dart';
import 'onboarding_flow.dart';

const _passWidth = 330.0;
const _headerHeight = 72.0;
const _bodyHeight = 230.0;
const _tearHeight = 20.0;
const _stubHeight = 90.0;
const _passHeight = _headerHeight + _bodyHeight + _tearHeight + _stubHeight;
const _tearY = _headerHeight + _bodyHeight + _tearHeight / 2;

class BoardingPassScene extends StatefulWidget {
  const BoardingPassScene({
    super.key,
    required this.still,
    required this.feel,
    required this.settings,
    required this.onTorn,
  });

  final bool still;
  final Feel feel;

  /// What is on, for the pass's settings row.
  final Map<BoardingAccess, bool> settings;

  /// The stub is off: board.
  final VoidCallback onTorn;

  @override
  State<BoardingPassScene> createState() => BoardingPassSceneState();
}

class BoardingPassSceneState extends State<BoardingPassScene>
    with TickerProviderStateMixin {
  // Printing: 0 inside the slot, 1 out.
  late final AnimationController _print = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1250));
  // How far the stub is pulled, in px.
  late final AnimationController _pull =
      AnimationController.unbounded(vsync: this);
  // The stub falling once it is off.
  late final AnimationController _fall = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900));
  bool _torn = false;
  int _lastNotch = 0;
  int _printTicks = 0;

  static const _tearAt = 118.0;

  @override
  void initState() {
    super.initState();
    if (widget.still) {
      _print.value = 1;
    } else {
      _print.addListener(_printFeel);
      _print.forward().whenComplete(() {
        if (mounted) widget.feel('land');
      });
    }
    _pull.addListener(_pullFeel);
  }

  void _printFeel() {
    // A printer feeds paper in steps: a grain under the finger as it does.
    final ticks = (_print.value * 9).floor();
    if (ticks > _printTicks && _print.value < 0.98) {
      _printTicks = ticks;
      widget.feel('grain', _print.value);
    }
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
    _print.dispose();
    _pull.dispose();
    _fall.dispose();
    super.dispose();
  }

  /// Tears the stub off by itself (the Board button). Completes when it is off.
  Future<void> tear() async {
    if (_torn) return;
    if (!widget.still) {
      await _pull.animateTo(_tearAt + 14,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeInCubic);
    }
    _complete();
  }

  void _complete() {
    if (_torn) return;
    setState(() => _torn = true);
    widget.feel('release');
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
        // The pass is drawn at its own size and fitted to the screen.
        final scale = math.min(
            1.0,
            math.min(constraints.maxWidth / (_passWidth + 8),
                constraints.maxHeight / (_passHeight + 30)));
        return Center(
          child: SizedBox(
            width: _passWidth * scale,
            height: (_passHeight + 26) * scale,
            child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: _passWidth,
                height: _passHeight + 26,
                child: AnimatedBuilder(
                  animation: Listenable.merge([_print, _pull, _fall]),
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
    // Out of the slot in small feeds, as a printer does.
    final p = _print.value;
    final feed = widget.still
        ? 1.0
        : Curves.easeOutCubic.transform(p) -
            math.sin(p * math.pi * 9) * 0.006 * (1 - p);
    final offset = (1 - feed) * -(_passHeight + 10);
    final pull = _pull.value.clamp(0.0, _tearAt + 30);
    final fall = _fall.value;
    final tearAngle = (pull / _tearAt) * 0.11 + fall * 0.5;
    final stubDrop = pull * 0.34 + fall * fall * 420;
    return Stack(clipBehavior: Clip.none, children: [
      // The slot it prints from.
      Positioned(
        left: -6,
        right: -6,
        top: 0,
        height: 6,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            color: const Color(0xFF060B12),
            boxShadow: [
              BoxShadow(
                  color:
                      Boarding.accent.withValues(alpha: 0.25 * (1 - p * 0.6)),
                  blurRadius: 12)
            ],
          ),
        ),
      ),
      Positioned(
        left: 0,
        right: 0,
        top: 3,
        bottom: -400,
        child: ClipRect(
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned(
              left: 0,
              top: offset + 3,
              width: _passWidth,
              height: _passHeight,
              child: Stack(clipBehavior: Clip.none, children: [
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
                  child: _Piece(top: true, child: _upper()),
                ),
              ]),
            ),
          ]),
        ),
      ),
    ]);
  }

  Widget _upper() {
    return Column(children: [
      // The header: dark, the wordmark, the airline line.
      Container(
        height: _headerHeight,
        padding: const EdgeInsets.fromLTRB(22, 15, 22, 11),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF30374E),
              Boarding.passHeaderTop,
              Boarding.passHeaderBottom
            ],
            stops: [0, 0.35, 1],
          ),
        ),
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned(
            right: -30,
            top: -8,
            child: Transform.rotate(
              angle: -0.49,
              child: const Opacity(
                opacity: 0.05,
                child: Lucide(LucideIcons.plane,
                    size: 104, color: Color(0xFFFFFFFF), strokeWidth: 0.7),
              ),
            ),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              FoorsaWordmark(height: 22, color: Boarding.paper),
              Spacer(),
              Text('BOARDING PASS',
                  style: TextStyle(
                      fontSize: 8.5,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w500,
                      color: Color(0xA8FCFBF7))),
            ]),
            const Spacer(),
            Row(children: [
              const Expanded(
                child: Text('Your journey to China',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Boarding.paper,
                        letterSpacing: 0.1)),
              ),
              const SizedBox(width: 8),
              Text('FS 2026',
                  style: Boarding.monoStyle(12,
                      color: Boarding.goldLight, weight: FontWeight.w500)),
            ]),
          ]),
        ]),
      ),
      // The body: paper.
      Expanded(
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
          // The paper, with the pass's soft shade from the top right.
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.topRight,
              radius: 1.3,
              colors: [Color(0xFFF0EFE9), Boarding.paper],
            ),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              _end('CMN', 'Casablanca', CrossAxisAlignment.start),
              const Expanded(child: _Airway()),
              _end('CHN', 'China', CrossAxisAlignment.end),
            ]),
            const SizedBox(height: 12),
            Container(height: 1, color: const Color(0x121B1F2E)),
            const SizedBox(height: 10),
            _field('PASSENGER', 'FOORSA STUDENT', size: 15, spacing: 0.6),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _field('GATE', 'SIGN IN')),
              Expanded(child: _field('SEAT', '1A')),
              Expanded(child: _field('CLASS', 'STUDENT')),
            ]),
            const SizedBox(height: 11),
            const Text('YOUR PHONE',
                style: TextStyle(
                    fontSize: 8,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w600,
                    color: Boarding.passLabel)),
            const SizedBox(height: 6),
            Row(children: [
              for (final access in const [
                BoardingAccess.notifications,
                BoardingAccess.camera,
                BoardingAccess.microphone,
                BoardingAccess.location,
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 7),
                  child: _Setting(
                      access: access, on: widget.settings[access] ?? false),
                ),
            ]),
          ]),
        ),
      ),
      // The upper half of the perforation band.
      Container(height: _tearHeight / 2, color: Boarding.paper),
    ]);
  }

  Widget _stub() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Boarding.paper, Boarding.paperShade],
        ),
      ),
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
            padding: const EdgeInsets.fromLTRB(22, 3, 22, 12),
            child: Stack(children: [
              Positioned(
                right: 0,
                bottom: 0,
                child: Opacity(
                    opacity: 0.08,
                    child: FoorsaMark(size: 34, color: Boarding.passInk)),
              ),
              Positioned.fill(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Expanded(
                          child: Text('BOARDING · 登机',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 8,
                                  letterSpacing: 1.3,
                                  fontWeight: FontWeight.w600,
                                  color: Boarding.passLabel)),
                        ),
                        if (!widget.still)
                          Opacity(
                            opacity: (1 - _pull.value / 40).clamp(0.0, 1.0) *
                                _print.value,
                            child: const Row(children: [
                              Text('Tear to board',
                                  style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w600,
                                      color: Boarding.gold)),
                              SizedBox(width: 3),
                              RotatedBox(
                                quarterTurns: 1,
                                child: Lucide(LucideIcons.chevronRight,
                                    size: 12,
                                    color: Boarding.gold,
                                    strokeWidth: 2.4),
                              ),
                            ]),
                          ),
                      ]),
                      const SizedBox(height: 7),
                      // The barcode takes what the stub has left.
                      const Expanded(
                        child: SizedBox(
                            width: double.infinity,
                            child: CustomPaint(painter: _BarcodePainter())),
                      ),
                      const SizedBox(height: 6),
                      Text('FS2026 · CMN · CHN · 0001',
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          style: Boarding.monoStyle(10.5,
                              color: const Color(0xFF363D51), spacing: 1.2)),
                    ]),
              ),
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
              fontSize: 40,
              height: 1.12,
              letterSpacing: -2.2,
              fontWeight: FontWeight.w600,
              color: Boarding.passInk,
              fontFeatures: [FontFeature.tabularFigures()],
            )),
        Text(city,
            style: const TextStyle(
                fontSize: 11, height: 1.4, color: Color(0xFF757981))),
      ]);

  Widget _field(String label, String value,
          {double size = 12, double spacing = 0.2}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 8,
                  letterSpacing: 1.0,
                  fontWeight: FontWeight.w600,
                  color: Boarding.passLabel)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: size,
                  fontWeight: FontWeight.w600,
                  letterSpacing: spacing,
                  color: Boarding.passInk)),
        ],
      );
}

/// A piece of the pass: the paper's rounded corners and its two notches.
class _Piece extends StatelessWidget {
  const _Piece({required this.top, required this.child});
  final bool top;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PieceShadowPainter(top),
      child: ClipPath(clipper: _PieceClipper(top), child: child),
    );
  }
}

Path _piecePath(Size size, bool top) {
  const r = 22.0, notch = 10.0;
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
  _PieceShadowPainter(this.top);
  final bool top;

  @override
  void paint(Canvas canvas, Size size) {
    final path = _piecePath(size, top);
    canvas.drawPath(
        path.shift(const Offset(0, 14)),
        Paint()
          ..color = const Color(0x5C000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18));
    canvas.drawPath(
        path.shift(const Offset(0, 2)),
        Paint()
          ..color = const Color(0x24000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
  }

  @override
  bool shouldRepaint(_PieceShadowPainter old) => old.top != top;
}

class _PerforationPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFC6C4BD)
      ..strokeWidth = 1;
    for (var x = 16.0; x < size.width - 16; x += 7) {
      canvas.drawLine(Offset(x, 0.5), Offset(x + 3.5, 0.5), paint);
    }
  }

  @override
  bool shouldRepaint(_PerforationPainter old) => false;
}

/// The route between the codes, the plane in the pass's gold.
class _Airway extends StatelessWidget {
  const _Airway();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 16),
      child: Row(children: [
        Expanded(child: Container(height: 1, color: const Color(0xFFB8B4A4))),
        const SizedBox(width: 6),
        Transform.rotate(
          angle: math.pi / 2,
          child: const SizedBox.square(
            dimension: 24,
            child:
                CustomPaint(painter: AirlinerSilhouettePainter(Boarding.gold)),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(child: Container(height: 1, color: const Color(0xFFB8B4A4))),
      ]),
    );
  }
}

class _Setting extends StatelessWidget {
  const _Setting({required this.access, required this.on});
  final BoardingAccess access;
  final bool on;

  static const _icons = {
    BoardingAccess.notifications: LucideIcons.bell,
    BoardingAccess.camera: LucideIcons.camera,
    BoardingAccess.microphone: LucideIcons.mic,
    BoardingAccess.location: LucideIcons.mapPin,
  };

  @override
  Widget build(BuildContext context) {
    // Its own item, so a screen reader says each one.
    return Semantics(
      container: true,
      label: '${accessName(access)} ${on ? 'on' : 'off'}',
      excludeSemantics: true,
      child: Container(
        height: 26,
        padding: const EdgeInsets.fromLTRB(7, 0, 8, 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: on ? const Color(0x1A0F7A4D) : const Color(0x0D1B1F2E),
          border: Border.all(
              color: on ? const Color(0x400F7A4D) : const Color(0x1F1B1F2E)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Lucide(_icons[access]!,
              size: 13,
              color: on ? const Color(0xFF0F7A4D) : Boarding.passSub,
              strokeWidth: 2.1),
          const SizedBox(width: 4),
          on
              ? const Lucide(LucideIcons.check,
                  size: 11, color: Color(0xFF0F7A4D), strokeWidth: 3)
              : Container(width: 7, height: 1.6, color: Boarding.passSub),
        ]),
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
    // A sheen across the ink, as paper catches light.
    canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..blendMode = BlendMode.srcATop
          ..shader = ui.Gradient.linear(Offset.zero, Offset(size.width, 0), [
            const Color(0x00FFFFFF),
            const Color(0x14FFFFFF),
            const Color(0x00FFFFFF)
          ], [
            0.3,
            0.5,
            0.7
          ]));
  }

  @override
  bool shouldRepaint(_BarcodePainter old) => false;
}
