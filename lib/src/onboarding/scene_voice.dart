/// The microphone: the chat's mic, and a voice running out from it on both
/// sides as it speaks. Holding the mic makes the voice louder, as speaking
/// closer would.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'boarding_style.dart';
import 'lucide.dart';

class VoiceScene extends StatefulWidget {
  const VoiceScene({super.key, required this.still, required this.feel});
  final bool still;
  final Feel feel;

  @override
  State<VoiceScene> createState() => _VoiceSceneState();
}

class _VoiceSceneState extends State<VoiceScene>
    with SingleTickerProviderStateMixin, SceneClock<VoiceScene> {
  /// How close the student is holding the mic, eased.
  final ValueNotifier<double> _held = ValueNotifier<double>(0);
  bool _down = false;
  double _last = 0;

  @override
  void initState() {
    super.initState();
    clock.addListener(_ease);
    startClock(still: widget.still);
  }

  void _ease() {
    final t = clock.value;
    final dt = math.min(1 / 30, t - _last);
    _last = t;
    final target = _down ? 1.0 : 0.0;
    _held.value += (target - _held.value) * (1 - math.exp(-dt * 10));
  }

  @override
  void dispose() {
    clock.removeListener(_ease);
    _held.dispose();
    super.dispose();
  }

  void _press(bool down) {
    if (down && !_down) widget.feel('press');
    _down = down;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'A voice note being recorded',
      excludeSemantics: true,
      child: Center(
        child: SizedBox(
          width: 320,
          height: 200,
          child: Stack(alignment: Alignment.center, children: [
            Positioned.fill(
              child: CustomPaint(
                  painter: _VoicePainter(clock, _held, still: widget.still)),
            ),
            // Raw pointers, so a long hold is still a hold: a tap gesture
            // would give up on it after half a second.
            Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (_) => _press(true),
              onPointerUp: (_) => _press(false),
              onPointerCancel: (_) => _press(false),
              child: ValueListenableBuilder<double>(
                valueListenable: _held,
                builder: (context, held, child) =>
                    Transform.scale(scale: 1 - 0.05 * held, child: child),
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      center: Alignment(-0.3, -0.5),
                      radius: 1.1,
                      colors: [Color(0xFF263749), Color(0xFF17232F)],
                    ),
                    boxShadow: [
                      BoxShadow(
                          color: Color(0x66000000),
                          blurRadius: 30,
                          offset: Offset(0, 14),
                          spreadRadius: -10),
                    ],
                  ),
                  foregroundDecoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border:
                        Border.all(color: const Color(0x24FFFFFF), width: 0.8),
                  ),
                  alignment: Alignment.center,
                  child: const Lucide(LucideIcons.mic,
                      size: 32, color: Boarding.heading, strokeWidth: 1.9),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// A voice: syllables in phrases, with breaths between them.
double voiceLevel(double t) {
  final phrase = t % 3.4;
  final speaking = ease(phrase, 0.1, 0.3) * (1 - ease(phrase, 2.5, 2.8));
  final syllable = 0.5 + 0.5 * math.sin(t * 2 * math.pi * 3.7);
  final grain =
      0.55 + 0.25 * math.sin(t * 23.1) + 0.2 * math.sin(t * 37.7 + 1.3);
  return (speaking * (0.25 + 0.75 * syllable) * grain).clamp(0.0, 1.0);
}

class _VoicePainter extends CustomPainter {
  _VoicePainter(this.clock, this.held, {required this.still})
      : super(repaint: Listenable.merge([clock, held]));
  final ValueNotifier<double> clock;
  final ValueNotifier<double> held;
  final bool still;

  static const _bars = 13;
  static const _barWidth = 3.0;
  static const _step = 7.0;

  @override
  void paint(Canvas canvas, Size size) {
    final t = still ? 1.2 : clock.value;
    final centre = size.center(Offset.zero);
    final boost = 1 + 0.6 * held.value;

    // Rings off the mic while it hears something.
    if (!still) {
      for (var k = 0; k < 2; k++) {
        final phase = ((t + k * 0.9) % 1.8) / 1.8;
        final loud = voiceLevel(t - phase * 0.6);
        final r = 44 + 34 * Curves.easeOut.transform(phase);
        final a = (1 - phase) * 0.16 * loud * boost;
        if (a < 0.005) continue;
        canvas.drawCircle(
            centre,
            r,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1
              ..color = Boarding.accent.withValues(alpha: a.clamp(0.0, 1.0)));
      }
    }

    // The voice runs outwards on both sides: each bar shows the level a
    // moment earlier than the one inside it.
    final paint = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < _bars; i++) {
      final delay = i * 0.055;
      final level =
          still ? 0.35 + 0.3 * math.sin(i * 1.7).abs() : voiceLevel(t - delay);
      final fall = 1 - i / (_bars + 3);
      final h = 4 + 46 * level * fall * boost;
      final alpha = ui.lerpDouble(0.95, 0.25, i / (_bars - 1))!;
      paint
        ..strokeWidth = _barWidth
        ..color = Boarding.heading.withValues(alpha: alpha);
      for (final side in const [-1.0, 1.0]) {
        final x = centre.dx + side * (60 + i * _step);
        canvas.drawLine(
            Offset(x, centre.dy - h / 2), Offset(x, centre.dy + h / 2), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_VoicePainter old) => old.still != still;
}
