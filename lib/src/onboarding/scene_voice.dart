/// Microphone: the live chat with an adviser (the portal's LiveChat, its
/// dark colours from liveChat.css). The adviser asks for a voice note, the
/// recording pill draws its waveform as iOS Messages does, the note goes and
/// is read, and the adviser answers. The student can hold the mic to try it:
/// nothing is recorded, the microphone is not open yet.
library;

import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
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

enum _Phase { asking, recording, sent, typing, answered }

class _VoiceSceneState extends State<VoiceScene>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  double _t = 0;
  double _clock = 0;
  Duration _last = Duration.zero;
  _Phase _phase = _Phase.asking;
  double _phaseAt = 0;

  /// The student's own hold, if they are holding.
  bool _holding = false;
  double _recordStart = 0;
  double _recordedFor = 0;
  final List<double> _levels = [];

  static const _askFor = 1.1;
  static const _autoRecord = 2.6;

  @override
  void initState() {
    super.initState();
    if (widget.still) {
      _phase = _Phase.answered;
      _recordedFor = 4;
      _phaseAt = -10;
    } else {
      _ticker.start();
    }
  }

  void _go(_Phase phase) {
    _phase = phase;
    _phaseAt = _clock;
  }

  double _level(double at) {
    // A voice: syllables with breaths between them.
    final syllable = 0.5 + 0.5 * math.sin(at * 9.1) * math.sin(at * 3.7 + 1.2);
    final breath = 0.55 + 0.45 * math.sin(at * 1.3);
    return (0.18 + 0.82 * syllable.abs() * breath).clamp(0.12, 1.0);
  }

  void _tick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    _clock += dt;
    final since = _clock - _phaseAt;
    switch (_phase) {
      case _Phase.asking:
        if (since > _askFor && !_holding) _startRecording(auto: true);
      case _Phase.recording:
        _recordedFor = _clock - _recordStart;
        _levels.add(_level(_clock) * (_holding ? 1 : 0.85));
        if (_levels.length > 80) _levels.removeAt(0);
        if (!_holding && _recordedFor > _autoRecord) _send();
      case _Phase.sent:
        if (since > 1.1) _go(_Phase.typing);
      case _Phase.typing:
        if (since > 1.3) {
          _go(_Phase.answered);
          widget.feel('press');
        }
      case _Phase.answered:
        if (since > 2.8) _restart();
    }
    setState(() => _t = _clock);
  }

  void _startRecording({required bool auto}) {
    _levels.clear();
    _recordStart = _clock;
    _recordedFor = 0;
    _go(_Phase.recording);
    if (!auto) widget.feel('press');
  }

  void _send() {
    _recordedFor = math.max(_recordedFor, 1);
    _go(_Phase.sent);
    widget.feel('land');
  }

  void _restart() {
    _levels.clear();
    _recordedFor = 0;
    _go(_Phase.asking);
  }

  void _holdStart() {
    if (widget.still) return;
    _holding = true;
    if (_phase != _Phase.recording) _startRecording(auto: false);
  }

  void _holdEnd() {
    if (!_holding) return;
    _holding = false;
    if (_phase == _Phase.recording) _send();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  double _appear(_Phase from, {double delay = 0}) {
    if (widget.still) return 1;
    if (_phase.index < from.index) return 0;
    final since = _phase == from ? _t - _phaseAt - delay : 9;
    final x = (since / 0.42).clamp(0.0, 1.0);
    return 1 - math.exp(-6 * x) * math.cos(7.5 * x) * (1 - x);
  }

  @override
  Widget build(BuildContext context) {
    final recording = _phase == _Phase.recording;
    final seconds = _recordedFor.clamp(0, 59).floor();
    return Semantics(
      label:
          'A chat with your adviser: a voice note sent and answered. Hold the microphone to try it.',
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF0E1720),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Boarding.glassEdge),
              ),
              child: Column(children: [
                _header(),
                // The conversation sits at the bottom and, on a short
                // screen, loses its oldest line at the top, as a chat does.
                Expanded(
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.bottomCenter,
                      maxHeight: double.infinity,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _bubble(
                              appear: widget.still
                                  ? 1
                                  : (_t - 0.25).clamp(0.0, 0.4) / 0.4,
                              mine: false,
                              child: const Text(
                                  'Hi! Can you send me a voice note about your diploma?',
                                  style: TextStyle(
                                      fontSize: 14,
                                      height: 1.32,
                                      color: Boarding.chatTeamInk)),
                            ),
                            _bubble(
                              appear: _appear(_Phase.sent),
                              mine: true,
                              child: _VoiceNote(
                                  seconds: math.max(1, seconds),
                                  seen: _phase.index >= _Phase.typing.index),
                            ),
                            _bubble(
                              appear: _phase == _Phase.typing
                                  ? _appear(_Phase.typing)
                                  : 0,
                              mine: false,
                              child: _Typing(t: _t),
                            ),
                            _bubble(
                              appear: _appear(_Phase.answered),
                              mine: false,
                              child: const Text(
                                  'Got it, thank you! I’ll add it to your file.',
                                  style: TextStyle(
                                      fontSize: 14,
                                      height: 1.32,
                                      color: Boarding.chatTeamInk)),
                            ),
                            const SizedBox(height: 10),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                  child: Row(children: [
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: recording
                            ? _RecordingPill(
                                key: const ValueKey('rec'),
                                levels: _levels,
                                seconds: seconds,
                                t: _t)
                            : Container(
                                key: const ValueKey('field'),
                                height: 46,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                alignment: Alignment.centerLeft,
                                decoration: BoxDecoration(
                                  color: const Color(0xB31D2833),
                                  borderRadius: BorderRadius.circular(23),
                                  border: Border.all(
                                      color: const Color(0x33FFFFFF)),
                                ),
                                child: const Text('Message',
                                    style: TextStyle(
                                        fontSize: 15, color: Boarding.faint)),
                              ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _MicButton(
                      recording: recording,
                      onDown: _holdStart,
                      onUp: _holdEnd,
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: const BoxDecoration(
        color: Color(0xB31D2833),
        border: Border(bottom: BorderSide(color: Color(0x1AFFFFFF))),
      ),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
              shape: BoxShape.circle, color: Color(0xFF2A4A6B)),
          child: const Text('N',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFDCE7F2))),
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Nadia',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Boarding.heading)),
                SizedBox(height: 1),
                Row(children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                        shape: BoxShape.circle, color: Boarding.done),
                    child: SizedBox.square(dimension: 7),
                  ),
                  SizedBox(width: 5),
                  Flexible(
                    child: Text('Your Foorsa adviser',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: Boarding.muted)),
                  ),
                ]),
              ]),
        ),
        _CallButton(t: _t, still: widget.still),
      ]),
    );
  }

  Widget _bubble(
      {required double appear, required bool mine, required Widget child}) {
    if (appear <= 0.001) return const SizedBox.shrink();
    final a = appear.clamp(0.0, 1.0);
    return ClipRect(
      child: Align(
        alignment: Alignment.bottomCenter,
        heightFactor: (appear * 1.15).clamp(0.0, 1.0),
        child: Opacity(
          opacity: a,
          child: Transform.translate(
            offset: Offset(0, (1 - appear) * 14),
            child: Transform.scale(
              scale: 0.94 + 0.06 * appear,
              alignment: mine ? Alignment.bottomRight : Alignment.bottomLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Align(
                  alignment:
                      mine ? Alignment.centerRight : Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 270),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(13, 9, 13, 9),
                      decoration: BoxDecoration(
                        color: mine ? null : Boarding.chatTeam,
                        gradient: mine
                            ? const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Boarding.chatMineTop,
                                  Boarding.chatMineBottom
                                ],
                              )
                            : null,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(18),
                          topRight: const Radius.circular(18),
                          bottomLeft: Radius.circular(mine ? 18 : 6),
                          bottomRight: Radius.circular(mine ? 6 : 18),
                        ),
                        border: mine
                            ? null
                            : Border.all(color: const Color(0x12FFFFFF)),
                      ),
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A sent voice note: play, its waveform, its length, and the ticks.
class _VoiceNote extends StatelessWidget {
  const _VoiceNote({required this.seconds, required this.seen});
  final int seconds;
  final bool seen;

  static final List<double> _peaks = List<double>.generate(26, (i) {
    final v = 0.5 + 0.5 * math.sin(i * 1.7) * math.sin(i * 0.63 + 0.4);
    return (0.22 + 0.78 * v.abs()).clamp(0.2, 1.0);
  });

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
            shape: BoxShape.circle, color: Color(0x33FFFFFF)),
        child: const Lucide(LucideIcons.play,
            size: 14, color: Color(0xFFFFFFFF), strokeWidth: 2.6),
      ),
      const SizedBox(width: 9),
      // The waveform gives way first on a narrow phone.
      Flexible(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 118),
          child: SizedBox(
            width: 118,
            height: 26,
            child: CustomPaint(
                painter: _BarsPainter(_peaks, const Color(0xE6FFFFFF),
                    fromRight: false)),
          ),
        ),
      ),
      const SizedBox(width: 9),
      Text('0:${seconds.toString().padLeft(2, '0')}',
          style: const TextStyle(
              fontSize: 12.5,
              color: Color(0xD9FFFFFF),
              fontFeatures: [FontFeature.tabularFigures()])),
      const SizedBox(width: 5),
      Lucide(LucideIcons.checkCheck,
          size: 15,
          color: seen ? const Color(0xFF8FD3FF) : const Color(0xB3FFFFFF),
          strokeWidth: 2.3),
    ]);
  }
}

/// Recording: one red-tinted pill, the waveform running in from the right,
/// the time in red (the portal's RecordingPill).
class _RecordingPill extends StatelessWidget {
  const _RecordingPill(
      {super.key,
      required this.levels,
      required this.seconds,
      required this.t});
  final List<double> levels;
  final int seconds;
  final double t;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0x29E0413B),
        borderRadius: BorderRadius.circular(23),
        border: Border.all(color: const Color(0x4DE0413B)),
      ),
      child: Row(children: [
        Opacity(
          opacity: 0.55 + 0.45 * (0.5 + 0.5 * math.sin(t * 5.6)),
          child: Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
                shape: BoxShape.circle, color: Boarding.recording),
          ),
        ),
        const SizedBox(width: 9),
        Text('0:${seconds.toString().padLeft(2, '0')}',
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFFFF8A84),
                fontFeatures: [FontFeature.tabularFigures()])),
        const SizedBox(width: 12),
        Expanded(
          child: SizedBox(
            height: 26,
            child: CustomPaint(
                painter: _BarsPainter(levels, const Color(0xFFFF8A84),
                    fromRight: true)),
          ),
        ),
      ]),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter(this.levels, this.color, {required this.fromRight});
  final List<double> levels;
  final Color color;
  final bool fromRight;

  @override
  void paint(Canvas canvas, Size size) {
    const bar = 2.6, gap = 2.0;
    final fits = (size.width / (bar + gap)).floor();
    final paint = Paint()
      ..color = color
      ..strokeWidth = bar
      ..strokeCap = StrokeCap.round;
    final dots = Paint()..color = color.withValues(alpha: 0.35);
    for (var i = 0; i < fits; i++) {
      final x = fromRight
          ? size.width - bar / 2 - i * (bar + gap)
          : bar / 2 + i * (bar + gap);
      final index = fromRight ? levels.length - 1 - i : i;
      if (index < 0 || index >= levels.length) {
        // The line of dots the waveform runs in over.
        canvas.drawCircle(Offset(x, size.height / 2), 1, dots);
        continue;
      }
      final h = math.max(3.0, levels[index] * size.height);
      canvas.drawLine(Offset(x, (size.height - h) / 2 + bar / 2),
          Offset(x, (size.height + h) / 2 - bar / 2), paint);
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => true;
}

class _Typing extends StatelessWidget {
  const _Typing({required this.t});
  final double t;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 34,
      height: 18,
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        for (var i = 0; i < 3; i++)
          Transform.translate(
            offset: Offset(0, -2.5 * math.max(0, math.sin(t * 7 - i * 0.7))),
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Boarding.muted.withValues(
                    alpha: 0.5 + 0.4 * math.max(0, math.sin(t * 7 - i * 0.7))),
              ),
            ),
          ),
      ]),
    );
  }
}

class _MicButton extends StatelessWidget {
  const _MicButton(
      {required this.recording, required this.onDown, required this.onUp});
  final bool recording;
  final VoidCallback onDown;
  final VoidCallback onUp;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Hold to try a voice note',
      child: Listener(
        onPointerDown: (_) => onDown(),
        onPointerUp: (_) => onUp(),
        onPointerCancel: (_) => onUp(),
        child: AnimatedScale(
          scale: recording ? 1.12 : 1,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutBack,
          child: Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: recording ? Boarding.recording : null,
              gradient: recording
                  ? null
                  : const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Boarding.pearlTop, Boarding.pearlBottom],
                    ),
              boxShadow: [
                BoxShadow(
                  color: recording
                      ? const Color(0x66E0413B)
                      : const Color(0x590A1E34),
                  blurRadius: recording ? 16 : 10,
                  offset: const Offset(0, 4),
                  spreadRadius: -4,
                ),
              ],
            ),
            child: Lucide(recording ? LucideIcons.square : LucideIcons.mic,
                size: recording ? 16 : 21,
                color: recording ? const Color(0xFFFFFFFF) : Boarding.pearlInk,
                strokeWidth: 2.3),
          ),
        ),
      ),
    );
  }
}

/// The call button, ringing now and then: adviser calls come in the app too.
class _CallButton extends StatelessWidget {
  const _CallButton({required this.t, required this.still});
  final double t;
  final bool still;

  @override
  Widget build(BuildContext context) {
    final ring = still ? 0.0 : (t % 8.4) / 1.4;
    return SizedBox.square(
      dimension: 40,
      child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            if (ring > 0 && ring < 1)
              for (final delay in [0.0, 0.35])
                if (ring - delay > 0)
                  Opacity(
                    opacity:
                        (1 - (ring - delay) / (1 - delay)).clamp(0.0, 1.0) *
                            0.5,
                    child: Container(
                      width: 40 + 26 * (ring - delay),
                      height: 40 + 26 * (ring - delay),
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Boarding.done, width: 1.5)),
                    ),
                  ),
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0x1FFFFFFF),
                border: Border.all(color: const Color(0x26FFFFFF)),
              ),
              child: Transform.rotate(
                angle: ring > 0 && ring < 1
                    ? math.sin(t * 38) * 0.18 * (1 - ring)
                    : 0,
                child: const Lucide(LucideIcons.phone,
                    size: 18, color: Boarding.ink),
              ),
            ),
          ]),
    );
  }
}
