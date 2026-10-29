/// Notifications: the phone's lock screen, its real time and date, with
/// Foorsa's notifications arriving and stacking as iOS stacks them. The words
/// are the ones the app sends (student_push.dart), not promises.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'boarding_style.dart';
import 'lucide.dart';

class _Note {
  _Note(this.id, this.body, {this.confirm = false});
  final int id;
  final String body;
  final bool confirm;
  // Springs, stepped every frame: where it is, where it is going.
  double y = -34, vy = 0;
  double scale = 0.94, vs = 0;
  double alpha = 0, va = 0;
  int slot = 0;
}

const _bodies = <String>[
  'You have a new message from your adviser.',
  'An update is ready in your Foorsa app.',
  'Your class or calendar event is coming up.',
];

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday'
];
const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
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
  final DateTime _now = DateTime.now();

  static const _cardHeight = 84.0;
  static const _gap = 8.0;

  @override
  void initState() {
    super.initState();
    widget.outcome.addListener(_answered);
    if (widget.still) {
      for (var i = 0; i < 3; i++) {
        _add(_bodies[(2 - i) % _bodies.length], settle: true);
      }
      return;
    }
    _ticker.start();
    // The first lands soon after the screen does, the rest a beat apart.
    _timer = Timer(const Duration(milliseconds: 520), () {
      _arrive();
      _timer =
          Timer.periodic(const Duration(milliseconds: 1750), (_) => _arrive());
    });
  }

  void _arrive() {
    if (!mounted || widget.outcome.value != null) return;
    _add(_bodies[_next % _bodies.length]);
    _next++;
    // A notification is felt, but only the first two: a buzz every two
    // seconds would be a nuisance.
    if (_next <= 2) widget.feel('press');
  }

  void _add(String body, {bool settle = false, bool confirm = false}) {
    final note = _Note(_ids++, body, confirm: confirm);
    _notes.insert(0, note);
    for (var i = 0; i < _notes.length; i++) {
      _notes[i].slot = i;
    }
    if (_notes.length > 6) _notes.removeLast();
    // Without motion everything simply stands where it belongs.
    if (settle || widget.still) _notes.forEach(_snap);
    _frame.value++;
  }

  void _answered() {
    final on = widget.outcome.value;
    if (on == null || !mounted) return;
    _timer?.cancel();
    if (on) {
      _add('Notifications are on. We’ll let you know as soon as there’s news.',
          confirm: true);
    }
  }

  (double, double, double) _target(int slot) {
    if (slot < 3) return (slot * (_cardHeight + _gap), 1, 1);
    // Older ones tuck under the third, as a stack.
    final depth = (slot - 2).toDouble();
    return (
      2 * (_cardHeight + _gap) + depth * 7,
      1 - 0.05 * depth,
      math.max(0, 1 - 0.4 * depth)
    );
  }

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
    // A slightly bouncy spring (damping 0.82, response 0.5).
    const omega = 2 * math.pi / 0.5;
    const k = omega * omega, c = 2 * 0.82 * omega;
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

  String get _time {
    final use24 = MediaQuery.alwaysUse24HourFormatOf(context);
    final hour =
        use24 ? _now.hour : (_now.hour % 12 == 0 ? 12 : _now.hour % 12);
    return '${use24 ? hour.toString().padLeft(2, '0') : hour}:${_now.minute.toString().padLeft(2, '0')}';
  }

  String get _date =>
      '${_weekdays[_now.weekday - 1]} ${_now.day} ${_months[_now.month - 1]}';

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Foorsa notifications arriving on the lock screen',
      excludeSemantics: true,
      child: LayoutBuilder(builder: (context, constraints) {
        final width = math.min(constraints.maxWidth, 380.0);
        final clockSize = (constraints.maxHeight * 0.2).clamp(40.0, 82.0);
        return Center(
          child: SizedBox(
            width: width,
            child: Column(children: [
              SizedBox(height: constraints.maxHeight * 0.03),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Lucide(LucideIcons.lock,
                    size: 13, color: Color(0xD9E8EEF6), strokeWidth: 2.4),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(_date,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xE6E8EEF6),
                          letterSpacing: 0.1)),
                ),
              ]),
              Text(
                _time,
                style: TextStyle(
                  fontSize: clockSize,
                  fontWeight: FontWeight.w600,
                  height: 1.05,
                  letterSpacing: -clockSize * 0.035,
                  color: const Color(0xF0F2F6FB),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              SizedBox(height: constraints.maxHeight * 0.04),
              // Notifications that do not fit fade out at the bottom, as on
              // a lock screen.
              Expanded(
                child: ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (rect) => const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFFFFFFFF),
                      Color(0xFFFFFFFF),
                      Color(0x00FFFFFF)
                    ],
                    stops: [0, 0.84, 1],
                  ).createShader(rect),
                  child: ClipRect(
                    child: ValueListenableBuilder<int>(
                      valueListenable: _frame,
                      builder: (context, _, __) =>
                          Stack(clipBehavior: Clip.none, children: [
                        for (final note in _notes.reversed)
                          if (note.alpha > 0.01)
                            Positioned(
                              left: 0,
                              right: 0,
                              top: note.y,
                              child: Opacity(
                                opacity: note.alpha.clamp(0.0, 1.0),
                                child: Transform.scale(
                                  scale: note.scale,
                                  alignment: Alignment.topCenter,
                                  child: _NotificationCard(note: note),
                                ),
                              ),
                            ),
                      ]),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        );
      }),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.note});
  final _Note note;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _NotificationsSceneState._cardHeight,
      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
      decoration: BoxDecoration(
        // iOS's notification material on a dark wallpaper.
        color: const Color(0xC22A3746),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0x1AFFFFFF)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x40000000),
              blurRadius: 18,
              offset: Offset(0, 6),
              spreadRadius: -6)
        ],
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: SizedBox.square(
            dimension: 38,
            child: note.confirm
                ? const DecoratedBox(
                    decoration: BoxDecoration(color: Boarding.done),
                    child: Center(
                        child: Lucide(LucideIcons.bell,
                            size: 21,
                            color: Color(0xFF06281A),
                            strokeWidth: 2.3)),
                  )
                : Image.asset('assets/icons/app_icon_ios.png',
                    fit: BoxFit.cover, filterQuality: FilterQuality.medium),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Expanded(
                child: Text('Foorsa',
                    style: TextStyle(
                        fontSize: 14.5,
                        height: 1.15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFF3F6FA))),
              ),
              Text('now',
                  style: TextStyle(
                      fontSize: 12.5,
                      height: 1.15,
                      color: const Color(0xFFE6ECF3).withValues(alpha: 0.6))),
            ]),
            const SizedBox(height: 2),
            Text(note.body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 14, height: 1.25, color: Color(0xE6E6ECF3))),
          ]),
        ),
      ]),
    );
  }
}
