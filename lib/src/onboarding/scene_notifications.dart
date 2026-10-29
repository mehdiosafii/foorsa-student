/// Notifications: one stack of Foorsa's notifications, as iOS stacks them.
/// A new one lands on top every few seconds and the others step back behind
/// it. The words are the ones the app sends (student_push.dart), not promises.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'boarding_style.dart';

class _Note {
  _Note(this.id, this.body);
  final int id;
  final String body;
  // Springs, stepped every frame: where it is, where it is going.
  double y = -46, vy = 0;
  double scale = 1.04, vs = 0;
  double alpha = 0, va = 0;
  int slot = 0;
}

const _bodies = <String>[
  'You have a new message from your adviser.',
  'An update is ready in your Foorsa app.',
  'Your class or calendar event is coming up.',
];

class NotificationsScene extends StatefulWidget {
  const NotificationsScene(
      {super.key,
      required this.still,
      required this.feel,
      required this.outcome});
  final bool still;
  final Feel feel;

  /// null until the student answers; then whether notifications are on.
  final ValueListenable<bool?> outcome;

  @override
  State<NotificationsScene> createState() => _NotificationsSceneState();
}

class _NotificationsSceneState extends State<NotificationsScene>
    with SingleTickerProviderStateMixin {
  final List<_Note> _notes = [];
  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;
  Timer? _timer;
  int _next = 0;
  int _ids = 0;
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    widget.outcome.addListener(_answered);
    if (widget.still) {
      for (var i = 0; i < 3; i++) {
        _add(_bodies[(2 - i) % _bodies.length]);
      }
      return;
    }
    _ticker.start();
    _timer = Timer(const Duration(milliseconds: 420), () {
      _arrive();
      _timer =
          Timer.periodic(const Duration(milliseconds: 2600), (_) => _arrive());
    });
  }

  void _arrive() {
    if (!mounted || widget.outcome.value != null) return;
    _add(_bodies[_next % _bodies.length]);
    _next++;
  }

  void _add(String body) {
    _notes.insert(0, _Note(_ids++, body));
    for (var i = 0; i < _notes.length; i++) {
      _notes[i].slot = i;
    }
    if (_notes.length > 4) _notes.removeLast();
    if (widget.still) _notes.forEach(_snap);
    _frame.value++;
  }

  void _answered() {
    final on = widget.outcome.value;
    if (on == null || !mounted) return;
    _timer?.cancel();
    if (on) _add('Notifications are on. We’ll let you know.');
  }

  /// Front card, then two plates peeking under it, then gone.
  (double, double, double) _target(int slot) => switch (slot) {
        0 => (0, 1, 1),
        1 => (11, 0.94, 0.62),
        2 => (20, 0.88, 0.3),
        _ => (26, 0.82, 0),
      };

  void _snap(_Note note) {
    final (y, s, a) = _target(note.slot);
    note
      ..y = y
      ..scale = s
      ..alpha = a;
  }

  void _tick(Duration elapsed) {
    final dt = math.min(1 / 30, (elapsed - _last).inMicroseconds / 1e6);
    _last = elapsed;
    if (dt <= 0) return;
    // Damping 0.8, response 0.55: it lands with the slightest give.
    const omega = 2 * math.pi / 0.55;
    const k = omega * omega, c = 2 * 0.8 * omega;
    for (final note in _notes) {
      final (y, s, a) = _target(note.slot);
      for (var i = 0; i < 4; i++) {
        final h = dt / 4;
        note.vy += (-k * (note.y - y) - c * note.vy) * h;
        note.y += note.vy * h;
        note.vs += (-k * (note.scale - s) - c * note.vs) * h;
        note.scale += note.vs * h;
        note.va += (-k * (note.alpha - a) - c * 1.4 * note.va) * h;
        note.alpha += note.va * h;
      }
    }
    _frame.value++;
  }

  @override
  void dispose() {
    widget.outcome.removeListener(_answered);
    _timer?.cancel();
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Foorsa notifications arriving: ${_bodies.join(' ')}',
      excludeSemantics: true,
      child: LayoutBuilder(builder: (context, constraints) {
        final width = math.min(340.0, constraints.maxWidth);
        return Center(
          child: SizedBox(
            width: width,
            height: 120,
            child: ValueListenableBuilder<int>(
              valueListenable: _frame,
              builder: (context, _, __) => Stack(
                clipBehavior: Clip.none,
                children: [
                  // Back to front, so the newest is drawn last.
                  for (final note in _notes.reversed)
                    if (note.alpha > 0.01)
                      Positioned(
                        key: ValueKey(note.id),
                        left: 0,
                        right: 0,
                        top: 12 + note.y,
                        child: Opacity(
                          opacity: note.alpha.clamp(0.0, 1.0),
                          child: Transform.scale(
                            scale: note.scale,
                            alignment: Alignment.bottomCenter,
                            child:
                                _Card(body: note.body, front: note.slot == 0),
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.body, required this.front});
  final String body;
  final bool front;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 78,
      padding: const EdgeInsets.fromLTRB(14, 0, 16, 0),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2633),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Boarding.slateEdge, width: 0.5),
        boxShadow: front
            ? const [
                BoxShadow(
                    color: Color(0x59000000),
                    blurRadius: 48,
                    offset: Offset(0, 24),
                    spreadRadius: -18),
              ]
            : null,
      ),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: Image.asset('assets/icons/app_icon_ios.png',
              width: 38, height: 38, filterQuality: FilterQuality.medium),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Expanded(
                  child: Text('Foorsa',
                      maxLines: 1,
                      style: TextStyle(
                          fontSize: 15,
                          height: 1.25,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                          color: Boarding.heading)),
                ),
                Text('now',
                    style: TextStyle(
                        fontSize: 13,
                        height: 1.25,
                        color: Boarding.muted.withValues(alpha: 0.85))),
              ]),
              const SizedBox(height: 2),
              BalancedText(body,
                  maxLines: 2,
                  textAlign: TextAlign.start,
                  style: const TextStyle(
                      fontSize: 14.5,
                      height: 1.3,
                      letterSpacing: -0.15,
                      color: Boarding.ink)),
            ],
          ),
        ),
      ]),
    );
  }
}
