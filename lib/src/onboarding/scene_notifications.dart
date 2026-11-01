/// Notifications: one stack of Foorsa's notifications, as iOS stacks them.
/// A new one lands on top every few seconds and the others step back behind
/// it. The words are the ones the app sends (student_push.dart), not promises.
/// The stack is the control: tapping a notification is how the student turns
/// them on, and once they are on the front one goes up to where the phone's
/// own first notification comes down.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../app_language.dart';
import 'boarding_style.dart';
import 'gesture_demo.dart';
import 'glass.dart';
import 'scene_hint.dart';
import 'stage_forms.dart';

class _Note {
  _Note(this.id, this.body);
  final int id;
  final Words body;
  // Springs, stepped every frame: where it is, where it is going.
  double y = -46, vy = 0;
  double scale = 1.04, vs = 0;
  double alpha = 0, va = 0;
  int slot = 0;

  /// Gone up to the top of the screen, as the phone's own banner.
  bool gone = false;

  /// Its card, made again only when it moves to the front or away from it:
  /// made every frame the stack moved, its words were laid out again every
  /// frame (BalancedText measures them to break them evenly).
  Widget card(AppLanguage language) {
    final front = slot == 0 || gone;
    if (front != _front || language != _language || _card == null) {
      _front = front;
      _language = language;
      _card = _Card(body: body.of(language), front: front, language: language);
    }
    return _card!;
  }

  Widget? _card;
  bool? _front;
  AppLanguage? _language;
}

/// The three the app sends (student_push.dart), in each language.
const notificationBodies = <Words>[
  Words(
      'You have a new message from your adviser.',
      'Vous avez un nouveau message de votre conseiller.',
      'لديك رسالة جديدة من مستشارك.'),
  Words(
      'An update is ready in your Foorsa app.',
      'Une mise à jour vous attend dans votre application Foorsa.',
      'تحديث جديد بانتظارك في تطبيق فرصة.'),
  Words(
      'Your class or calendar event is coming up.',
      'Votre cours ou un événement de votre calendrier approche.',
      'اقترب موعد حصتك أو حدث في تقويمك.'),
];

/// The card's title, the notification's own (onboarding_gate.dart), and
/// when it came.
const _title = Words('Foorsa', 'Foorsa', 'فرصة');
const _now = Words('now', 'maintenant', 'الآن');

/// The notifications' gesture: a tap on the front card, where a thumb would.
GestureDemo notificationsDemo(Size stage) {
  final card = RRect.fromRectAndRadius(
      Rect.fromCenter(
          center: stage.center(Offset.zero),
          width: cardWidth(stage.width),
          height: cardHeight),
      const Radius.circular(22));
  return GestureDemo.tap(card.center + Offset(card.width * 0.2, 4), card);
}

class NotificationsScene extends StatefulWidget {
  const NotificationsScene({
    super.key,
    required this.still,
    required this.feel,
    required this.outcome,
    required this.armed,
    required this.label,
    required this.hint,
    required this.onAct,
    this.spoken,
  });
  final bool still;
  final Feel feel;

  /// null until the student answers; then whether notifications are on.
  final ValueListenable<bool?> outcome;
  final bool armed;
  final String label;
  final String hint;
  final String? spoken;
  final SceneAct onAct;

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
        _add(notificationBodies[(2 - i) % notificationBodies.length]);
      }
      return;
    }
    // The first is already there: it is what the last object became.
    _add(notificationBodies[0]);
    _notes.forEach(_snap);
    _next = 1;
    _timer = Timer(const Duration(milliseconds: 1900), () {
      _arrive();
      _timer =
          Timer.periodic(const Duration(milliseconds: 2600), (_) => _arrive());
    });
  }

  @override
  void didUpdateWidget(NotificationsScene old) {
    super.didUpdateWidget(old);
    if (old.outcome != widget.outcome) {
      old.outcome.removeListener(_answered);
      widget.outcome.addListener(_answered);
    }
  }

  void _arrive() {
    if (!mounted || widget.outcome.value != null) return;
    _add(notificationBodies[_next % notificationBodies.length]);
    _next++;
  }

  void _add(Words body) {
    _notes.insert(0, _Note(_ids++, body));
    for (var i = 0; i < _notes.length; i++) {
      _notes[i].slot = i;
    }
    if (_notes.length > 4) _notes.removeLast();
    if (widget.still) _notes.forEach(_snap);
    _frame.value++;
    _wake();
  }

  /// The springs have somewhere to go: the clock runs until they are there.
  void _wake() {
    if (widget.still || _ticker.isActive || !mounted) return;
    _last = Duration.zero;
    _ticker.start();
  }

  void _answered() {
    final on = widget.outcome.value;
    if (on == null || !mounted) return;
    _timer?.cancel();
    if (!on || _notes.isEmpty) return;
    // Turned on: the front card goes up to the top of the screen, where the
    // phone's own first notification comes down (onboarding_gate.dart), and
    // the stack steps forward.
    final front = _notes.first..gone = true;
    var slot = 0;
    for (final note in _notes) {
      if (!identical(note, front)) note.slot = slot++;
    }
    widget.feel('release');
    if (widget.still) {
      _notes.remove(front);
      _notes.forEach(_snap);
    }
    _frame.value++;
    _wake();
  }

  /// Front card, then two plates peeking under it, then gone.
  (double, double, double) _target(_Note note) {
    if (note.gone) return (-320, 0.96, 0);
    return switch (note.slot) {
      0 => (0, 1, 1),
      1 => (11, 0.94, 0.62),
      2 => (20, 0.88, 0.3),
      _ => (26, 0.82, 0),
    };
  }

  void _snap(_Note note) {
    final (y, s, a) = _target(note);
    note
      ..y = y
      ..vy = 0
      ..scale = s
      ..vs = 0
      ..alpha = a
      ..va = 0;
  }

  void _tick(Duration elapsed) {
    final dt = math.min(1 / 30, (elapsed - _last).inMicroseconds / 1e6);
    _last = elapsed;
    if (dt <= 0) return;
    // Damping 0.8, response 0.55: it lands with the slightest give.
    const omega = 2 * math.pi / 0.55;
    const k = omega * omega, c = 2 * 0.8 * omega;
    for (final note in _notes) {
      final (y, s, a) = _target(note);
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
    _notes.removeWhere((note) => note.gone && note.y < -240);
    // At rest, the stack is put exactly where it was going and left alone:
    // redrawn every frame, its cards were laid out again every frame too.
    if (_notes.every(_atRest)) {
      _notes.forEach(_snap);
      _ticker.stop();
    }
    _frame.value++;
  }

  /// Within a hundredth of a point and still: nothing on the screen moves.
  bool _atRest(_Note note) {
    final (y, s, a) = _target(note);
    return !note.gone &&
        (note.y - y).abs() < 0.01 &&
        note.vy.abs() < 0.01 &&
        (note.scale - s).abs() < 1e-4 &&
        note.vs.abs() < 1e-4 &&
        (note.alpha - a).abs() < 1e-4 &&
        note.va.abs() < 1e-4;
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
    final language = AppLanguageScope.of(context);
    return LayoutBuilder(builder: (context, constraints) {
      final width = cardWidth(constraints.maxWidth);
      final middle = constraints.maxHeight / 2;
      return SceneGuide(
        instruction: widget.hint,
        demo: notificationsDemo(constraints.biggest),
        instructionTop: middle + _stackHeight / 2 + 18,
        clearOf: middle + _stackHeight / 2,
        active: widget.armed,
        still: widget.still,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned(
            left: (constraints.maxWidth - width) / 2,
            top: middle - _stackHeight / 2,
            width: width,
            height: _stackHeight,
            child: ObjectControl(
              label: widget.label,
              hint: widget.spoken,
              armed: widget.armed,
              feel: widget.feel,
              scale: 0.97,
              onTap: () => widget.onAct(),
              child: OwnFrame(
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
                            top: (_stackHeight - cardHeight) / 2 + note.y,
                            child: Opacity(
                              opacity: note.alpha.clamp(0.0, 1.0),
                              child: Transform.scale(
                                scale: note.scale,
                                alignment: Alignment.bottomCenter,
                                child: note.card(language),
                              ),
                            ),
                          ),
                    ],
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

/// The stack's box: the front card and the two plates peeking under it.
const _stackHeight = 120.0;

const _iconSide = 38.0;

/// The app's icon on the cards, decoded at the size it is shown: the file is
/// 1024 px square, and decoded whole it was a 4 MB texture, uploaded as the
/// first card arrived, for a 38 pt icon. The onboarding asks for it ahead
/// (onboarding_page.dart), so the first card has it.
ImageProvider notificationIcon(double devicePixelRatio) =>
    ResizeImage(const AssetImage('assets/icons/app_icon_ios.png'),
        width: (_iconSide * devicePixelRatio).round(),
        height: (_iconSide * devicePixelRatio).round());

class _Card extends StatelessWidget {
  const _Card(
      {required this.body, required this.front, required this.language});
  final String body;
  final AppLanguage language;
  final bool front;

  @override
  Widget build(BuildContext context) {
    // The portal's pane; only the front card casts its full shadow.
    return RepaintBoundary(
      child: SizedBox(
        height: cardHeight,
        child: GlassPane(
          glass: front ? Glass.pane : _behind,
          radius: 22,
          child: Padding(
            // The icon's side is the start: the right in Arabic, as the
            // phone draws its own notifications.
            padding: const EdgeInsetsDirectional.fromSTEB(14, 0, 16, 0),
            child: _content(context),
          ),
        ),
      ),
    );
  }

  /// A card stacked behind: the same glass, a lighter shadow.
  static final Glass _behind = Glass(
    fill: Glass.pane.fill,
    rim: Glass.pane.rim,
    wall: Glass.pane.wall,
    highlight: Glass.pane.highlight,
    glow: Glass.pane.glow,
    shadows: const [
      GlassShadow(Color(0x33000000), dy: 1, blur: 2),
      GlassShadow(Color(0x26000000), dy: 6, blur: 12, spread: -6),
      GlassShadow.none,
    ],
  );

  Widget _content(BuildContext context) {
    return Row(children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: Image(
            image: notificationIcon(MediaQuery.devicePixelRatioOf(context)),
            width: _iconSide,
            height: _iconSide,
            filterQuality: FilterQuality.medium),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(_title.of(language),
                    maxLines: 1,
                    style: scriptStyle(
                        const TextStyle(
                            fontSize: 15,
                            height: 1.25,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2,
                            color: Boarding.heading),
                        language)),
              ),
              Text(_now.of(language),
                  style: TextStyle(
                      fontSize: 13,
                      height: 1.25,
                      color: Boarding.muted.withValues(alpha: 0.85))),
            ]),
            const SizedBox(height: 2),
            BalancedText(body,
                maxLines: 2,
                textAlign: TextAlign.start,
                style: scriptStyle(
                    const TextStyle(
                        fontSize: 14.5,
                        height: 1.3,
                        letterSpacing: -0.15,
                        color: Boarding.ink),
                    language)),
          ],
        ),
      ),
    ]);
  }
}
