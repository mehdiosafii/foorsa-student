/// The microphone: the chat's mic, and a voice running out from it on both
/// sides as it speaks. The mic is the control: a tap turns it on, and the
/// voice comes up as it is pressed, as speaking closer would.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'boarding_style.dart';
import 'gesture_demo.dart';
import 'glass.dart';
import 'lucide.dart';
import 'scene_hint.dart';
import 'stage_forms.dart';

/// The microphone's gesture: a tap on the mic.
GestureDemo voiceDemo(Size stage) {
  final mic = stage.center(Offset.zero);
  return GestureDemo.tap(
      thumbOn(mic, micSide / 2),
      RRect.fromRectAndRadius(Rect.fromCircle(center: mic, radius: micSide / 2),
          const Radius.circular(micSide / 2)));
}

class VoiceScene extends StatefulWidget {
  const VoiceScene({
    super.key,
    required this.still,
    required this.feel,
    required this.armed,
    required this.label,
    required this.hint,
    required this.onAct,
    required this.outcome,
    this.spoken,
  });
  final bool still;
  final Feel feel;
  final bool armed;
  final String label;
  final String hint;
  final String? spoken;
  final SceneAct onAct;

  /// null until the student answers; then whether the mic is on.
  final ValueListenable<bool?> outcome;

  @override
  State<VoiceScene> createState() => _VoiceSceneState();
}

class _VoiceSceneState extends State<VoiceScene>
    with SingleTickerProviderStateMixin, SceneClock<VoiceScene> {
  /// How close the student is holding the mic, eased.
  final ValueNotifier<double> _held = ValueNotifier<double>(0);
  bool _down = false;
  double _last = 0;

  /// The mic is on: the voice comes up for a moment.
  double _onAt = -1;

  @override
  void initState() {
    super.initState();
    clock.addListener(_ease);
    widget.outcome.addListener(_answered);
    startClock(still: widget.still);
  }

  @override
  void didUpdateWidget(VoiceScene old) {
    super.didUpdateWidget(old);
    if (old.outcome != widget.outcome) {
      old.outcome.removeListener(_answered);
      widget.outcome.addListener(_answered);
    }
  }

  void _answered() {
    if (widget.outcome.value == true && mounted) _onAt = clock.value;
  }

  void _ease() {
    final t = clock.value;
    final dt = math.min(1 / 30, t - _last);
    _last = t;
    final on = _onAt >= 0 ? 1 - ease(t - _onAt, 0.9, 1.8) : 0.0;
    final target = math.max(_down ? 1.0 : 0.0, on);
    _held.value += (target - _held.value) * (1 - math.exp(-dt * 10));
  }

  @override
  void dispose() {
    clock.removeListener(_ease);
    widget.outcome.removeListener(_answered);
    _held.dispose();
    super.dispose();
  }

  void _press(bool down) => _down = down && widget.armed;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final middle = box.maxHeight / 2;
      return SceneGuide(
        instruction: widget.hint,
        demo: voiceDemo(box.biggest),
        instructionTop: middle + micSide / 2 + 34,
        clearOf: middle + micSide / 2,
        active: widget.armed,
        still: widget.still,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned(
            left: box.maxWidth / 2 - 160,
            top: middle - 100,
            width: 320,
            height: 200,
            // Its own layer: the voice moves every frame, the mic does not.
            child: RepaintBoundary(
              child: CustomPaint(
                  painter: _VoicePainter(clock, _held, still: widget.still)),
            ),
          ),
          Positioned(
            left: box.maxWidth / 2 - micSide / 2,
            top: middle - micSide / 2,
            width: micSide,
            height: micSide,
            // Raw pointers for the voice, so a long press still makes it
            // louder; the tap is the control's.
            child: Listener(
              onPointerDown: (_) => _press(true),
              onPointerUp: (_) => _press(false),
              onPointerCancel: (_) => _press(false),
              child: ObjectControl(
                label: widget.label,
                hint: widget.spoken,
                armed: widget.armed,
                feel: widget.feel,
                scale: 0.94,
                onTap: () => widget.onAct(),
                // The portal's lit glass, as its tiles are.
                child: const GlassPane(
                  glass: Glass.tile,
                  circle: true,
                  child: Center(
                    child: Lucide(LucideIcons.mic,
                        size: 32, color: Boarding.heading, strokeWidth: 1.9),
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
