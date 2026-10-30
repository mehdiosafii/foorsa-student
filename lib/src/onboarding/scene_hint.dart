/// The onboarding has no buttons: on each screen the student acts on the
/// object itself. So every scene says what to do and shows it
/// ([SceneGuide]): under the object, one clear line in the portal's accent
/// (Swipe the arrow up to begin, Tap the notification, Drag the page into
/// the frame), and on the object a touch that does the gesture where the
/// object really is (gesture_demo.dart), from the moment the object is ready,
/// calmly, every few seconds, until the student acts. A finger on the
/// picture sends the touch away at once; let go without having acted, and it
/// comes back a moment later. A student who has done nothing for a few
/// seconds is shown it more strongly: the touch larger and brighter, the
/// words white. With Reduce Motion the touch is a still chevron pointing the
/// gesture's way. None of it takes a touch or is read out: the object does,
/// and it tells a screen reader what to do itself ([ObjectControl]).
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'arrow_flight.dart';
import 'boarding_style.dart';
import 'gesture_demo.dart';

/// The student acted on the screen's object. A scene whose object is an
/// arrow says where that arrow is, so it can fly on from there, and how fast
/// it was going if it was thrown.
typedef SceneAct = void Function({ArrowPose? arrow, Offset? velocity});

/// The first demonstration starts this long after the object is ready.
const guideStartsAfter = 0.3;

/// After the student lets go without having acted, the next one starts this
/// long after.
const guideReturnsAfter = 1.4;

/// After this long with nothing done, the guide speaks up.
const guideInsistsAfter = 6.0;

/// The instruction, at its size before the phone's text size: larger than
/// the line under the headline, in the accent, and white once the guide
/// insists ([emphasis] 0 to 1).
TextStyle instructionStyle([double emphasis = 0]) => TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
      height: 1.2,
      color: Color.lerp(Boarding.accent, Boarding.heading, emphasis),
    );

/// The phone's text size, for what the scenes say. The scenes are drawn at a
/// fixed size (onboarding_page.dart puts them under
/// MediaQuery.withNoTextScaling), but what to do is read, so it follows the
/// phone, never below its own size and up to a quarter larger.
class InstructionScale extends InheritedWidget {
  const InstructionScale(
      {super.key, required this.scaler, required super.child});
  final TextScaler scaler;

  static TextScaler of(BuildContext context) =>
      (context.dependOnInheritedWidgetOfExactType<InstructionScale>()?.scaler ??
              MediaQuery.textScalerOf(context))
          .clamp(minScaleFactor: 1, maxScaleFactor: 1.25);

  @override
  bool updateShouldNotify(InstructionScale old) => old.scaler != scaler;
}

/// What to do, said and shown, over one scene ([child]).
class SceneGuide extends StatefulWidget {
  const SceneGuide({
    super.key,
    required this.instruction,
    required this.demo,
    required this.instructionTop,
    required this.clearOf,
    required this.active,
    required this.still,
    required this.child,
    this.response,
    this.firstAfter = guideStartsAfter,
  });

  /// What to do, said under the object.
  final String instruction;

  /// What to do, shown on the object, in the scene's points.
  final GestureDemo demo;

  /// Where the words go, from the scene's top. On a short stage they move up
  /// to stay on it, but never above [clearOf], the object's foot.
  final double instructionTop;
  final double clearOf;

  /// The object is waiting for the student. The guide shows from then on,
  /// and goes as soon as they have acted.
  final bool active;

  /// Reduce Motion: a still chevron instead of the moving touch.
  final bool still;

  /// Seconds from the object being ready to the first demonstration: a
  /// moment, or until an object that is still arriving has arrived.
  final double firstAfter;

  final Widget child;

  /// Written every frame with how much the object answers the touch (0 to
  /// 1), so the object can move with it; [responseOf] gives it to the
  /// widgets under the guide.
  final ValueNotifier<double>? response;

  /// The layer the touch is drawn on, for the tests.
  static const demoKey = ValueKey<String>('gesture-demo');

  /// How much the object under the nearest guide answers its touch.
  static ValueListenable<double> responseOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_GuideScope>()?.response ??
      kAlwaysDismissedAnimation;

  @override
  State<SceneGuide> createState() => SceneGuideState();
}

class SceneGuideState extends State<SceneGuide>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  late final ValueNotifier<double> _ownResponse = ValueNotifier<double>(0);
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);
  final ValueNotifier<double> _emphasis = ValueNotifier<double>(0);
  final Set<int> _pointers = {};
  Timer? _insist;

  /// Seconds on the guide's clock: when the demonstrations (re)start, and
  /// since when the student has done nothing.
  double _now = 0, _last = 0, _cycleFrom = 0, _idleFrom = 0;

  /// The touch's visibility, which a finger on the screen takes away at once.
  double _gate = 0;
  DemoPose _pose = DemoPose.none;
  bool _drawn = false;

  ValueNotifier<double> get _response => widget.response ?? _ownResponse;
  bool get _touching => _pointers.isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (widget.active) _start();
  }

  @override
  void didUpdateWidget(SceneGuide oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.response != widget.response) oldWidget.response?.value = 0;
    if (widget.active &&
        (!oldWidget.active || widget.still != oldWidget.still)) {
      _start();
    } else if (!widget.active && oldWidget.active) {
      _stop();
    }
  }

  @override
  void dispose() {
    _insist?.cancel();
    _ticker.dispose();
    _ownResponse.dispose();
    _frame.dispose();
    _emphasis.dispose();
    super.dispose();
  }

  /// The object is ready: the first demonstration in a moment.
  void _start() {
    _insist?.cancel();
    _ticker.stop();
    _now = _last = _idleFrom = 0;
    _cycleFrom = widget.firstAfter;
    _gate = 1;
    _pose = DemoPose.none;
    _emphasis.value = 0;
    if (widget.still) {
      _insistLater();
    } else {
      _ticker.start();
    }
    _frame.value++;
  }

  /// The student has acted: the guide goes.
  void _stop() {
    _insist?.cancel();
    if (widget.still || !_ticker.isActive) {
      _gate = 0;
      _pose = DemoPose.none;
      _response.value = 0;
      _frame.value++;
    }
    // Moving, the tick fades the touch out, then stops.
  }

  /// With Reduce Motion there is no clock: a timer makes the guide insist.
  void _insistLater() {
    _insist?.cancel();
    _insist =
        Timer(Duration(milliseconds: (guideInsistsAfter * 1000).round()), () {
      if (!mounted || !widget.active || _touching) return;
      _emphasis.value = 1;
      _frame.value++;
    });
  }

  void _down(PointerDownEvent event) {
    _pointers.add(event.pointer);
    _insist?.cancel();
    if (widget.still) {
      _emphasis.value = 0;
      _frame.value++;
    }
  }

  void _up(PointerEvent event) {
    if (!_pointers.remove(event.pointer) || _touching) return;
    // Let go without having acted: shown again in a moment, gently.
    _idleFrom = _now;
    _cycleFrom = _now + guideReturnsAfter;
    if (widget.still && widget.active) {
      _insistLater();
      _frame.value++;
    }
  }

  void _tick(Duration elapsed) {
    _now = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    final dt = (_now - _last).clamp(0.0, 0.1);
    _last = _now;
    final on = widget.active && !_touching;
    // Gone the moment a finger is on the screen; back with the next
    // demonstration, which brings itself in.
    _gate = on ? 1.0 : math.max(0.0, _gate - dt / 0.08);
    final insist = on
        ? ((_now - _idleFrom - guideInsistsAfter) / 0.8).clamp(0.0, 1.0)
        : 0.0;
    final e = _emphasis.value;
    _emphasis.value =
        e + (insist - e) * (1 - math.exp(-dt / (insist > e ? 0.22 : 0.1)));
    final cycle = _now - _cycleFrom;
    _pose = _gate > 0 && cycle >= 0
        ? demoAt(widget.demo, cycle % widget.demo.period)
        : DemoPose.none;
    // The object answers the touch, and lets go of it with the student's
    // finger on it, without a jump.
    final answer = on ? _pose.response : 0.0;
    final r = _response.value;
    _response.value =
        on ? answer : r + (answer - r) * (1 - math.exp(-dt / 0.08));
    // Painted only while there is something to see, or to clear.
    final drawn = _gate > 0 && (_pose.presence > 0.004 || _pose.ring >= 0);
    if (drawn || _drawn) _frame.value++;
    _drawn = drawn;
    if (!widget.active && _gate <= 0 && _response.value < 0.002) {
      _response.value = 0;
      _ticker.stop();
    }
  }

  /// For the tests: whether the touch (or, with Reduce Motion, the chevron)
  /// is on the screen now, and where.
  @visibleForTesting
  bool get showing => widget.still
      ? widget.active && !_touching
      : _gate > 0.001 && _pose.presence > 0.004;
  @visibleForTesting
  DemoPose get pose => _pose;
  @visibleForTesting
  double get emphasis => _emphasis.value;

  @override
  Widget build(BuildContext context) {
    final scaler = InstructionScale.of(context);
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _down,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: _GuideScope(
        response: _response,
        child: LayoutBuilder(builder: (context, box) {
          final line = scaler.scale(17) * 1.2;
          final top = math.max(widget.clearOf + 6,
              math.min(widget.instructionTop, box.maxHeight + 10 - line));
          return Stack(
              clipBehavior: Clip.none,
              fit: StackFit.expand,
              children: [
                widget.child,
                Positioned.fill(
                  child: IgnorePointer(
                    // Its own layer: it is drawn every frame it moves, the
                    // scene under it is not.
                    child: RepaintBoundary(
                      child: CustomPaint(
                          key: SceneGuide.demoKey,
                          painter: _GuidePainter(this)),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: top,
                  // Words only: a touch on them reaches the object under them,
                  // and the object tells a screen reader what to do.
                  child: IgnorePointer(
                    child: ExcludeSemantics(
                      child: AnimatedOpacity(
                        duration:
                            Duration(milliseconds: widget.active ? 320 : 200),
                        opacity: widget.active ? 1 : 0,
                        child: ValueListenableBuilder<double>(
                          valueListenable: _emphasis,
                          builder: (context, e, _) => Transform.scale(
                            scale: 1 + 0.04 * e,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                widget.instruction,
                                maxLines: 1,
                                softWrap: false,
                                textAlign: TextAlign.center,
                                textScaler: scaler,
                                style: instructionStyle(e),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ]);
        }),
      ),
    );
  }
}

class _GuideScope extends InheritedWidget {
  const _GuideScope({required this.response, required super.child});
  final ValueListenable<double> response;

  @override
  bool updateShouldNotify(_GuideScope old) => old.response != response;
}

class _GuidePainter extends CustomPainter {
  _GuidePainter(this.guide) : super(repaint: guide._frame);
  final SceneGuideState guide;

  @override
  void paint(Canvas canvas, Size size) {
    final demo = guide.widget.demo;
    final emphasis = guide._emphasis.value;
    if (guide.widget.still) {
      if (guide.showing) paintStillCue(canvas, demo, emphasis: emphasis);
      return;
    }
    paintDemo(canvas, demo, guide._pose, gate: guide._gate, emphasis: emphasis);
  }

  @override
  bool shouldRepaint(_GuidePainter old) => true;
}

/// An object that is the screen's control: pressed like the portal's
/// controls (in within 100 ms, back on a spring), felt as it is pressed, and
/// a button named [label] for a screen reader, which says what to do with it
/// ([hint]).
class ObjectControl extends StatelessWidget {
  const ObjectControl({
    super.key,
    required this.label,
    required this.armed,
    required this.feel,
    required this.onTap,
    required this.child,
    this.hint,
    this.scale = 0.96,
  });

  final String label;
  final String? hint;
  final bool armed;
  final Feel feel;
  final VoidCallback onTap;
  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: armed,
      label: label,
      hint: hint,
      excludeSemantics: true,
      onTap: armed ? onTap : null,
      child: Pressable(
        scale: scale,
        onDown: armed ? () => feel('press') : null,
        onTap: armed ? onTap : null,
        child: child,
      ),
    );
  }
}
