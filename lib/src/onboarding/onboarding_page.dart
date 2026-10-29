/// The first-launch onboarding: the takeoff, the welcome board, a step for
/// each phone access that can still be asked for, and the boarding pass.
///
/// There are no buttons. On each screen the student acts on the object
/// itself, wherever it stands: throws the arrow up into the departures board,
/// taps the notification, puts the passport page in the scanner's frame,
/// taps the mic, taps the map's locate arrow, tears the boarding pass's stub.
/// What to do is said quietly under the object (scene_hint.dart).
///
/// One arrow tells the story. Where the object is itself an arrow (the one
/// under the board, the one in the map's button), it flies up into the
/// picture, which has folded into an arrow of light for it to dock in, and
/// unfolds as the next picture. Elsewhere the object folds into the arrow
/// and unfolds as the next one. Once the stub is off, what is left of the
/// pass folds into the arrow, which lands on the sign-in's own arrow, and the
/// onboarding fades onto the portal underneath.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import 'arrow_flight.dart';
import 'boarding_pass.dart';
import 'boarding_style.dart';
import 'brand_marks.dart';
import 'glass_arrow.dart';
import 'night_sky.dart';
import 'onboarding_flow.dart';
import 'onboarding_sound.dart';
import 'route_progress.dart';
import 'scene_location.dart';
import 'scene_notifications.dart';
import 'scene_scan.dart';
import 'scene_tracking.dart';
import 'scene_voice.dart';
import 'scene_welcome.dart';
import 'stage_forms.dart';
import 'stage_morph.dart';
import 'takeoff_intro.dart';

/// A step's flight, in seconds from the arrow leaving the student's hand: it
/// swoops in as the picture folds into an arrow of light, docks, shines, and
/// the picture unfolds as the next one.
class FlightTimes {
  const FlightTimes._(
      this.swoop, this.foldFrom, this.beatTo, this.wordsFrom, this.total);

  /// Lifted out of the map's button: it rises and glides into the middle
  /// while the map folds round it.
  static const lifted = FlightTimes._(0.6, 0.32, 0.72, 0.78, 1.36);

  /// Thrown: it is in the picture almost at once, so the picture folds to
  /// meet it as it goes.
  static const thrown = FlightTimes._(0.38, 0.04, 0.5, 0.56, 1.14);

  /// It docks at [swoop]; the picture starts to fold at [foldFrom], becomes
  /// the next at [beatTo], and has finished unfolding at [total]. The words
  /// come in at [wordsFrom].
  final double swoop, foldFrom, beatTo, wordsFrom, total;
}

/// Where the stage's morph is ([StageMorphPainter]'s progress) [s] seconds
/// into a flight.
double flightMorph(double s, [FlightTimes times = FlightTimes.lifted]) {
  if (s <= times.foldFrom) return 0;
  if (s < times.swoop) {
    return arrowAt * (s - times.foldFrom) / (times.swoop - times.foldFrom);
  }
  if (s < times.beatTo) {
    return arrowAt +
        (arrowLeaves - arrowAt) *
            (s - times.swoop) /
            (times.beatTo - times.swoop);
  }
  return math.min(
      1.0,
      arrowLeaves +
          (1 - arrowLeaves) *
              (s - times.beatTo) /
              (times.total - times.beatTo));
}

/// How fast a thrown arrow carries on into its flight ([launchCurve]'s v0):
/// its speed over the speed that crosses [reach] in a thrown swoop's time,
/// and never so fast that it would overshoot.
double throwSpeed(Offset velocity, double reach) =>
    (velocity.distance * FlightTimes.thrown.swoop / math.max(reach, 1))
        .clamp(0.0, 2.4)
        .toDouble();

double _smooth(double x) {
  final t = x.clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// Boarding, in seconds from the stub coming off: what is left of the pass
/// folds into the arrow, which shines, flies to the sign-in's arrow, and the
/// onboarding fades onto it.
const _boardFoldFrom = 0.2;
const _boardDock = 0.75;
const _boardShineEnd = 0.92;
const _boardMarkEnd = 1.42;
const _boardTotal = 1.82;

class FirstLaunchOnboarding extends StatefulWidget {
  const FirstLaunchOnboarding({
    super.key,
    required this.permissions,
    required this.feel,
    required this.onFinished,
    required this.isIOS,
    required this.asksToTrack,
    this.sounds = const SilentSounds(),
    this.findMark,
    this.onBoarded,
    this.onGranted,
  });

  final BoardingSounds sounds;

  /// Where the sign-in's arrow is on the screen (portal_handover.dart): the
  /// onboarding's own lands on it.
  final Future<Rect?> Function()? findMark;

  /// The onboarding is fading onto the sign-in.
  final VoidCallback? onBoarded;

  /// The student said yes to [BoardingAccess]: notifications send the first
  /// real one (onboarding_gate.dart).
  final void Function(BoardingAccess access)? onGranted;

  final BoardingPermissions permissions;
  final Feel feel;

  /// The arrow is on the sign-in's and the onboarding has faded: it can go.
  final VoidCallback onFinished;
  final bool isIOS;
  final bool asksToTrack;

  @override
  State<FirstLaunchOnboarding> createState() => FirstLaunchOnboardingState();
}

class FirstLaunchOnboardingState extends State<FirstLaunchOnboarding>
    with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: (takeoffSeconds * 1000) ~/ 1));
  late final Animation<double> _introSeconds =
      _intro.drive(Tween(begin: 0.0, end: takeoffSeconds));
  late final AnimationController _night = AnimationController(vsync: this);
  late final AnimationController _drift =
      AnimationController.unbounded(vsync: this);
  late final AnimationController _route =
      AnimationController.unbounded(vsync: this);
  late final AnimationController _content = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 700));

  /// The stage between two steps: the old object becomes the arrow, the arrow
  /// the new one. Driven by [_flight] when an arrow flies in, by itself
  /// otherwise.
  late final AnimationController _shift = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1050));

  /// From the student's hand into the picture ([FlightTimes]).
  late final AnimationController _flight = AnimationController(vsync: this);
  FlightTimes _times = FlightTimes.lifted;

  /// Boarding: the pass, the arrow, the sign-in ([_boardTotal]).
  late final AnimationController _exit = AnimationController(vsync: this);

  Swoop? _swoop;
  bool _ghost = false;

  /// The stage is morphing on its own (not driven by a flight).
  bool _morphing = false;
  final Set<String> _beats = {};

  final GlobalKey _overlayKey = GlobalKey();
  final GlobalKey _stageKey = GlobalKey();

  BoardingStep? _previous;
  BoardingPlan? _plan;
  int _index = 0;
  bool _introDone = false;
  bool _busy = false;
  bool _leaving = false;
  final Map<BoardingAccess, bool> _answered = {};

  /// Each step's answer, for its object to show (a notification going up,
  /// the blue dot on the map).
  final Map<BoardingStep, ValueNotifier<bool?>> _outcomes = {};

  /// The map's arrow has left its button: the page flies it.
  final ValueNotifier<bool> _away = ValueNotifier<bool>(false);

  /// The words of the step come in a beat after it.
  Duration _wordsDelay = Duration.zero;

  /// Pauses the page is waiting out, cancelled if it goes.
  final Set<Timer> _waits = {};

  /// Boarding: where the stage's middle is, and where the sign-in's arrow
  /// is, in the overlay's points.
  Offset? _boardCentre;
  Rect? _mark;
  bool _markKnown = false;
  bool _waitingForMark = false;

  /// The progress and the words step aside as the student boards.
  late final Animation<double> _chromeFade = _exit.drive(const _ChromeFade());
  bool _feltUnfold = false;
  bool _feltRelease = false;

  /// The welcome's board flips when it appears, not while the plane flies.
  bool _contentShown = false;
  bool _still = false;
  bool _introStarted = false;

  List<BoardingStep> get _steps =>
      _plan?.steps ?? const [BoardingStep.welcome, BoardingStep.boarding];
  BoardingStep get _step => _steps[_index];

  /// The student may act on the object: the takeoff is over, nothing is
  /// moving and nothing is being asked.
  bool get _armed =>
      _plan != null &&
      _introDone &&
      _contentShown &&
      !_busy &&
      !_leaving &&
      _previous == null;

  ValueNotifier<bool?> _outcomeOf(BoardingStep step) => _outcomes.putIfAbsent(
      step,
      () => ValueNotifier<bool?>(
          step.access == null ? null : _answered[step.access]));

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _intro.addListener(_introTick);
    _flight.addListener(_flightTick);
    _shift.addListener(_shiftTick);
    _exit.addListener(_exitTick);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.disableAnimationsOf(context);
    if (_still != still || !_introStarted) {
      _still = still;
      _startIntro();
    }
  }

  void _startIntro() {
    if (_introStarted) return;
    _introStarted = true;
    if (_still) {
      // Reduce Motion: no flight, the night is simply there.
      _night.value = 1;
      _introDone = true;
      _contentShown = true;
      _content.value = 1;
      return;
    }
    widget.sounds.play('intro');
    _intro.forward().whenComplete(() {
      if (mounted) setState(() => _introDone = true);
    });
  }

  void _showContent() {
    if (_contentShown) return;
    _contentShown = true;
    if (mounted) setState(() {});
    _content.forward();
    widget.sounds.startBed();
  }

  Future<void> _load() async {
    final plan = await planBoarding(widget.permissions,
        isIOS: widget.isIOS, asksToTrack: widget.asksToTrack);
    if (!mounted) return;
    setState(() => _plan = plan);
  }

  void _introTick() {
    final s = _introSeconds.value;
    _night.value = takeoffNight(s);
    if (!_feltUnfold && s > morphStarts + 0.05) {
      _feltUnfold = true;
      widget.feel('unfold');
    }
    if (!_feltRelease && s > climbStarts) {
      _feltRelease = true;
      widget.feel('release');
    }
    // The welcome comes once the plane has cleared it.
    if (s > takeoffSeconds - 0.2) _showContent();
  }

  void _skipIntro() {
    if (_introDone) return;
    widget.sounds.stop('intro');
    _intro.stop();
    _intro.value = 1;
    _night.animateTo(1, duration: const Duration(milliseconds: 300));
    _showContent();
    setState(() => _introDone = true);
  }

  @override
  void dispose() {
    _intro.dispose();
    _night.dispose();
    _drift.dispose();
    _route.dispose();
    _content.dispose();
    _shift.dispose();
    _flight.dispose();
    _exit.dispose();
    for (final outcome in _outcomes.values) {
      outcome.dispose();
    }
    _away.dispose();
    for (final wait in _waits) {
      wait.cancel();
    }
    super.dispose();
  }

  /// A pause that ends with the page: if it goes first, whatever waits on it
  /// simply never goes on.
  Future<void> _pause(Duration length) {
    final done = Completer<void>();
    late final Timer timer;
    timer = Timer(length, () {
      _waits.remove(timer);
      done.complete();
    });
    _waits.add(timer);
    return done.future;
  }

  void _spring(AnimationController c, double target,
      {double damping = 0.86, double response = 0.62}) {
    if (_still) {
      c.value = target;
      return;
    }
    c.animateWith(SpringSimulation(
        foorsaSpring(damping: damping, response: response),
        c.value,
        target,
        c.velocity));
  }

  // Where things are, in the overlay's points.

  RenderBox? _box(GlobalKey key) {
    final box = key.currentContext?.findRenderObject();
    return box is RenderBox && box.attached && box.hasSize ? box : null;
  }

  Offset? get _stageCentre {
    final stage = _box(_stageKey), overlay = _box(_overlayKey);
    if (stage == null || overlay == null) return null;
    return overlay
        .globalToLocal(stage.localToGlobal(stage.size.center(Offset.zero)));
  }

  /// Every press on an object is felt and heard alike.
  void _feel(String touch, [double level = 1]) {
    widget.feel(touch, level);
    if (touch == 'press') widget.sounds.play('tap');
  }

  /// The student acted on the object. A step that asks shows the phone's
  /// prompt at once; whatever the answer, the next step follows. A step whose
  /// object is an arrow sends that arrow on into the next picture.
  Future<void> _act({ArrowPose? arrow, Offset? velocity}) async {
    if (!_armed) return;
    final step = _step;
    final access = step.access;
    final asks = access != null && !_answered.containsKey(access);
    setState(() => _busy = true);
    // The scanner takes the page.
    if (step == BoardingStep.camera) widget.sounds.play('shutter');
    if (asks) {
      AccessState answer;
      try {
        answer = await widget.permissions.request(access);
      } catch (_) {
        answer = AccessState.unavailable;
      }
      if (!mounted) return;
      final on = answer == AccessState.granted;
      _answered[access] = on;
      _outcomeOf(step).value = on;
      // A yes is felt and seen on the object for a moment; a no simply moves
      // on: nothing on the way makes a student feel they answered wrong.
      if (on) {
        widget.feel('land');
        widget.sounds.play('granted');
        widget.onGranted?.call(access);
      }
      await _pause(Duration(milliseconds: on ? 900 : 320));
      if (!mounted) return;
    }
    if (_still || arrow == null) {
      _goTo(_index + 1);
      return;
    }
    _fly(_index + 1, arrow, velocity: velocity);
  }

  /// The arrow flies from where the student sent it (in the screen's
  /// points) into the picture, which becomes step [next].
  void _fly(int next, ArrowPose from, {Offset? velocity}) {
    final overlay = _box(_overlayKey);
    final to = _stageCentre;
    final thrown = velocity != null && velocity.distance > 60;
    _times = thrown ? FlightTimes.thrown : FlightTimes.lifted;
    Swoop? swoop;
    if (overlay != null && to != null) {
      final at = overlay.globalToLocal(from.at);
      swoop = thrown
          // Thrown, it carries on the way it was thrown, up into the board.
          ? Swoop(
              from: at,
              fromHeading: from.heading,
              fromHeight: from.height,
              to: to,
              toHeight: stageArrowHeight,
              speed: throwSpeed(velocity, (to - at).distance),
              launch: velocity / velocity.distance,
              approach: const Offset(0, -1),
            )
          // Lifted out of the map's button, it rises a little and glides
          // into the middle, still pointing its own way.
          : Swoop(
              from: at,
              fromHeading: from.heading,
              fromHeight: from.height,
              to: to,
              toHeight: stageArrowHeight,
              follow: false,
              launch: const Offset(0.2, -1),
              approach: const Offset(-0.5, -1),
            );
    }
    _away.value = true;
    setState(() {
      _swoop = swoop;
      _ghost = swoop != null;
      _previous = _step;
      _index = next;
      _wordsDelay = Duration(milliseconds: (_times.wordsFrom * 1000).round());
    });
    _beats.clear();
    _morphing = false;
    widget.sounds.play('swoop');
    _flight.duration = Duration(milliseconds: (_times.total * 1000).round());
    _spring(_drift, _index.toDouble(), response: 1.1);
    _spring(_route, _steps.length <= 1 ? 0 : _index / (_steps.length - 1));
    _flight.forward(from: 0).whenComplete(() {
      if (!mounted || _flight.value < 1) return;
      _away.value = false;
      setState(() {
        _previous = null;
        _swoop = null;
        _ghost = false;
        _busy = false;
      });
    });
  }

  void _flightTick() {
    final s = _flight.value * _times.total;
    _shift.value = flightMorph(s, _times);
    if (s >= _times.swoop && _beats.add('dock')) {
      // It docks: the picture has become the arrow.
      widget.feel('detent');
      widget.sounds.play('dock');
    }
    if (s >= _times.beatTo && _beats.add('unfold')) {
      widget.sounds.play('step-${_index.clamp(1, 6)}');
    }
  }

  /// To step [index], the stage morphing on its own: the object folds into
  /// the arrow and unfolds as the next. Forward from an object that is not
  /// an arrow, back, with Reduce Motion, and for the tests.
  void _goTo(int index) {
    if (index < 0 || index >= _steps.length || index == _index) return;
    final from = _step;
    _away.value = false;
    setState(() {
      _previous = from;
      _index = index;
      _busy = false;
      _ghost = false;
      _swoop = null;
      // The words follow the object as it changes.
      _wordsDelay = _still ? Duration.zero : const Duration(milliseconds: 460);
    });
    _beats.clear();
    _morphing = true;
    _shift.duration = Duration(milliseconds: _still ? 240 : 1050);
    _shift.forward(from: 0).whenComplete(() {
      _morphing = false;
      if (mounted && _shift.value >= 1) setState(() => _previous = null);
    });
    _spring(_drift, index.toDouble(), response: 0.9);
    _spring(_route, _steps.length <= 1 ? 0 : index / (_steps.length - 1));
  }

  void _shiftTick() {
    // As the arrow unfolds into the next object, the step's note.
    if (_morphing && _shift.value >= arrowLeaves && _beats.add('unfold')) {
      widget.sounds.play('step-${_index.clamp(1, 6)}');
    }
  }

  // Boarding.

  /// The stub is off: the student boards.
  void _boardNow() {
    if (_leaving) return;
    setState(() {
      _leaving = true;
      _busy = true;
    });
    widget.sounds.endBed();
    _beats.clear();
    _boardCentre = _stageCentre;
    if (_still) {
      widget.sounds.play('board');
      _exit.duration = const Duration(milliseconds: 320);
      _exit.forward();
      return;
    }
    unawaited(_findMark());
    _exit.duration = Duration(milliseconds: (_boardTotal * 1000).round());
    _exit.forward();
  }

  Future<void> _findMark() async {
    // Typed here: a Future<Rect> handed in as a Future<Rect?> would refuse a
    // null from its timeout.
    Future<Rect?> find() async => widget.findMark?.call();
    Rect? mark;
    try {
      mark = await find()
          .timeout(const Duration(milliseconds: 900), onTimeout: () => null);
    } catch (_) {}
    if (!mounted) return;
    final overlay = _box(_overlayKey);
    if (mark != null && overlay != null) {
      final topLeft = overlay.globalToLocal(mark.topLeft);
      // The page's arrow fills its 757 box; the mark itself is 712 of it.
      _mark = Rect.fromCenter(
          center: topLeft + mark.size.center(Offset.zero),
          width: mark.width * 712 / 757,
          height: mark.height * 712 / 757);
    }
    _markKnown = true;
    if (_waitingForMark) {
      _waitingForMark = false;
      _exit.forward();
    }
  }

  void _exitTick() {
    if (_still) {
      if (_beats.add('boarded')) widget.onBoarded?.call();
      if (_exit.value >= 1 && _beats.add('finished')) widget.onFinished();
      return;
    }
    final s = _exit.value * _boardTotal;
    if (s >= _boardDock && _beats.add('dock')) {
      // What is left of the pass is the arrow.
      widget.feel('detent');
      widget.sounds.play('dock');
    }
    if (s >= _boardShineEnd && !_markKnown) {
      // It shines on until the page says where its arrow is.
      _waitingForMark = true;
      _exit.stop();
      return;
    }
    if (s >= _boardShineEnd && _beats.add('board')) {
      widget.sounds.play('board');
    }
    // The arrow is on the sign-in's: the page may show itself.
    if (s >= _boardMarkEnd - 0.1 && _beats.add('boarded')) {
      widget.feel('land');
      widget.onBoarded?.call();
    }
    if (_exit.value >= 1 && _beats.add('finished')) widget.onFinished();
  }

  /// Android's back: one step back, out of the app from the welcome.
  void back() {
    if (_leaving || _busy || _previous != null) return;
    if (!_introDone) {
      _skipIntro();
      return;
    }
    if (_index == 0) {
      SystemNavigator.pop();
      return;
    }
    _goTo(_index - 1);
  }

  Widget _scene(BoardingStep step) {
    final copy = copyFor(step);
    final armed = _armed && step == _step;
    return switch (step) {
      BoardingStep.welcome => _contentShown
          ? WelcomeScene(
              still: _still,
              feel: _feel,
              armed: armed,
              hint: copy.hint,
              label: copy.action,
              onAct: _act,
              onFlip: () => widget.sounds.play('flap'))
          : const SizedBox.shrink(),
      BoardingStep.notifications => NotificationsScene(
          still: _still,
          feel: _feel,
          outcome: _outcomeOf(step),
          armed: armed,
          label: copy.action,
          hint: copy.hint,
          onAct: _act),
      BoardingStep.camera => ScanScene(
          still: _still,
          feel: _feel,
          outcome: _outcomeOf(step),
          armed: armed,
          label: copy.action,
          hint: copy.hint,
          onAct: _act),
      BoardingStep.microphone => VoiceScene(
          still: _still,
          feel: _feel,
          outcome: _outcomeOf(step),
          armed: armed,
          label: copy.action,
          hint: copy.hint,
          onAct: _act),
      BoardingStep.location => LocationScene(
          still: _still,
          feel: _feel,
          outcome: _outcomeOf(step),
          away: _away,
          armed: armed,
          label: copy.action,
          hint: copy.hint,
          onAct: _act),
      BoardingStep.tracking => TrackingScene(
          still: _still,
          feel: _feel,
          outcome: _outcomeOf(step),
          armed: armed,
          label: copy.action,
          hint: copy.hint,
          onAct: _act),
      BoardingStep.boarding => BoardingPassScene(
          still: _still,
          feel: _feel,
          armed: armed,
          label: copy.action,
          hint: copy.hint,
          onTear: () => widget.sounds.play('tear'),
          onTorn: _boardNow,
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final copy = copyFor(_step);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Material(
        type: MaterialType.transparency,
        child: AnimatedBuilder(
          animation: _exit,
          builder: (context, child) {
            // Once the arrow is on the sign-in's, the onboarding fades away
            // and the same night, with the same arrow, is the sign-in.
            final fade = _still
                ? _exit.value
                : ((_exit.value * _boardTotal - _boardMarkEnd) /
                        (_boardTotal - _boardMarkEnd))
                    .clamp(0.0, 1.0);
            // Always the same tree, so nothing under it is rebuilt as the
            // fade starts.
            return Opacity(
                opacity: 1 - Curves.easeInOut.transform(fade), child: child);
          },
          child: Stack(fit: StackFit.expand, children: [
            NightSky(night: _night, drift: _drift, still: _still),
            FadeTransition(
              opacity: CurvedAnimation(parent: _content, curve: Curves.easeOut),
              child: SlideTransition(
                position: Tween(begin: const Offset(0, 0.025), end: Offset.zero)
                    .animate(CurvedAnimation(
                        parent: _content, curve: Curves.easeOutCubic)),
                child: IgnorePointer(
                  ignoring: !_introDone || _leaving,
                  child: _layout(copy),
                ),
              ),
            ),
            // The arrow while it flies, over everything.
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  key: _overlayKey,
                  animation: Listenable.merge([_flight, _exit]),
                  builder: (context, _) => CustomPaint(
                    painter: _PilotPainter(_pilot()),
                  ),
                ),
              ),
            ),
            if (!_introDone)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _skipIntro,
                child: Semantics(
                  label: 'Foorsa is opening. Tap to skip.',
                  child: TakeoffIntro(time: _introSeconds),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  /// What the overlay draws this frame: the arrow swooping into the picture,
  /// or, boarding, shining and flying to the sign-in.
  _Pilot? _pilot() {
    if (_still) return null;
    if (_leaving && _exit.value > 0) return _boardingPilot();
    final swoop = _swoop;
    if (swoop != null && _flight.isAnimating) {
      final s = _flight.value * _times.total;
      if (s >= _times.swoop) return null;
      final t = s / _times.swoop;
      final (pose, bank) = swoop.at(t, glowFrom: 0.8);
      return _Pilot(pose,
          bank: bank,
          trail: swoop.trail(t),
          trailStrength: _smooth(t / 0.15) * (1 - _smooth((t - 0.7) / 0.3)));
    }
    return null;
  }

  _Pilot? _boardingPilot() {
    final s = _exit.value * _boardTotal;
    // Until then, the stage folds the pass into the arrow.
    if (s < _boardDock) return null;
    final centre = _boardCentre;
    if (centre == null) return null;
    if (s < _boardShineEnd || !_markKnown) {
      final shine =
          ((s - _boardDock) / (_boardShineEnd - _boardDock)).clamp(0.0, 0.999);
      return _Pilot(ArrowPose(centre, restHeading, stageArrowHeight, glow: 0.8),
          shine: shine);
    }
    final mark = _mark;
    final go = Curves.easeInOutCubic.transform(
        ((s - _boardShineEnd) / (_boardMarkEnd - _boardShineEnd))
            .clamp(0.0, 1.0));
    final at = mark == null ? centre : Offset.lerp(centre, mark.center, go)!;
    final height = mark == null
        ? stageArrowHeight
        : ui.lerpDouble(stageArrowHeight, mark.height, go)!;
    return _Pilot(ArrowPose(at, restHeading, height, glow: 0.8 * (1 - go)));
  }

  /// The smallest a scene may be. Below it the screen scrolls instead.
  static const _minScene = 220.0;

  /// The words never run wider than this, so they break like a headline.
  static const _measure = 340.0;

  Widget _layout(BoardingCopy copy) {
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Boarding.contentWidth),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: LayoutBuilder(builder: (context, constraints) {
              // A short screen (an iPhone SE, Android's small phones) gets
              // smaller words, so the scene keeps its room.
              final compact = constraints.maxHeight < 640;
              final media = MediaQuery.of(context);
              final scaler = compact
                  ? TextScaler.linear(media.textScaler.scale(1) * 0.88)
                  : media.textScaler;
              final measure = math.min(_measure, constraints.maxWidth);
              final copyHeight = _copyHeight(context, measure, scaler);
              final gap = compact ? 18.0 : 26.0;
              final fixed = 8 + 36 + gap + copyHeight + 12;
              final room = constraints.maxHeight - fixed;

              final top = SizedBox(
                height: 36,
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 420),
                    child: _step == BoardingStep.welcome
                        ? const FoorsaWordmark(
                            key: ValueKey('mark'),
                            height: 20,
                            color: Boarding.heading)
                        : RouteProgress(
                            key: const ValueKey('route'), progress: _route),
                  ),
                ),
              );

              // The scenes are illustrations at a fixed size: the words
              // above them follow the phone's text size.
              final scene = MediaQuery.withNoTextScaling(
                child: LayoutBuilder(builder: (context, box) {
                  final light = math.max(box.maxWidth, box.maxHeight) * 0.62;
                  return Stack(
                      key: _stageKey,
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          left: box.maxWidth / 2 - light,
                          top: box.maxHeight / 2 - light,
                          width: light * 2,
                          height: light * 2,
                          child: FadeTransition(
                              opacity: _night, child: Spotlight(radius: light)),
                        ),
                        Positioned.fill(
                          child: AnimatedBuilder(
                            animation: Listenable.merge([_shift, _exit]),
                            builder: (context, _) => _leaving
                                ? _boardingStage(
                                    Size(box.maxWidth, box.maxHeight))
                                : _stage(Size(box.maxWidth, box.maxHeight),
                                    _shift.value),
                          ),
                        ),
                      ]);
                }),
              );

              final words = MediaQuery(
                data: media.copyWith(textScaler: scaler),
                child: SizedBox(
                  width: measure,
                  height: copyHeight,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 520),
                    reverseDuration: const Duration(milliseconds: 200),
                    // Hung from the top, so the headline is in the same
                    // place on every step.
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.topCenter,
                      children: [...previous, if (current != null) current],
                    ),
                    // The same widget either way, so the words going out
                    // keep their state and simply fade; the words coming in
                    // bring themselves in.
                    transitionBuilder: (child, animation) => FadeTransition(
                        opacity: child.key == ValueKey(_step)
                            ? kAlwaysCompleteAnimation
                            : animation,
                        child: child),
                    child: _Copy(
                        key: ValueKey(_step),
                        copy: copy,
                        still: _still,
                        delay: _wordsDelay),
                  ),
                ),
              );

              List<Widget> parts(Widget sceneSlot) => [
                    const SizedBox(height: 8),
                    FadeTransition(opacity: _chromeFade, child: top),
                    SizedBox(height: gap),
                    FadeTransition(opacity: _chromeFade, child: words),
                    sceneSlot,
                    const SizedBox(height: 12),
                  ];

              if (room >= _minScene) {
                // On a tall phone the stage leaves some of the extra height
                // under it, so the object is not far below the words.
                final stage = room <= 460 ? room : 460 + (room - 460) * 0.4;
                return Column(children: [
                  ...parts(SizedBox(height: stage, child: scene)),
                  const Spacer(),
                ]);
              }
              // Too short for everything: the scene keeps its size and the
              // screen scrolls.
              return SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                    children: parts(SizedBox(height: _minScene, child: scene))),
              );
            }),
          ),
        ),
      ),
    );
  }

  /// The stage at [m] of a transition: the old object fading over its own
  /// outline, the outline becoming the arrow and the arrow the new object,
  /// the new object fading in over the outline it has become. Each object
  /// is keyed by its step, so it keeps running while it fades.
  Widget _stage(Size stage, double m) {
    final previous = _previous;
    final layers = <Widget>[];
    if (previous != null && !_still) {
      layers.add(Positioned.fill(
        key: const ValueKey('morph'),
        child: CustomPaint(
          painter: StageMorphPainter(
            from: formOf(previous, stage),
            to: formOf(_step, stage),
            progress: _shift,
            ghost: _ghost,
          ),
        ),
      ));
    }
    if (previous == null || _still || m >= 0.86) {
      final opacity = previous == null
          ? 1.0
          : _still
              ? m
              : _smooth((m - 0.86) / 0.11);
      layers.add(_SceneLayer(
          key: ValueKey(_step), opacity: opacity, child: _scene(_step)));
    }
    if (previous != null && (_still || m < 0.16)) {
      final opacity = _still ? 1 - m : 1 - _smooth(m / 0.14);
      layers.add(_SceneLayer(
          key: ValueKey(previous), opacity: opacity, child: _scene(previous)));
    }
    return Stack(children: layers);
  }

  /// Boarding on the stage: the pass, its stub falling away, then what is
  /// left of it folding into the arrow.
  Widget _boardingStage(Size stage) {
    final s = _exit.value * _boardTotal;
    final layers = <Widget>[];
    final fold = (s - _boardFoldFrom) / (_boardDock - _boardFoldFrom);
    if (!_still && fold > 0 && fold < 1) {
      final pass = formOf(BoardingStep.boarding, stage);
      final outer = pass.shape.outerRect;
      final scale = passScale(stage);
      // The stub has gone: the part above the perforation.
      final upper = StageForm(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(outer.left, outer.top, outer.width,
                  outer.height * passTearY / passHeight),
              Radius.circular(20 * scale)),
          pass.glass);
      layers.add(Positioned.fill(
        child: CustomPaint(
          painter: StageMorphPainter(
            from: upper,
            to: upper,
            progress: AlwaysStoppedAnimation(fold),
            toArrow: true,
          ),
        ),
      ));
    }
    final passOpacity = _still ? 1.0 : 1 - _smooth(fold / 0.18);
    if (passOpacity > 0) {
      layers.add(_SceneLayer(
          key: const ValueKey(BoardingStep.boarding),
          opacity: passOpacity,
          child: _scene(BoardingStep.boarding)));
    }
    return Stack(children: layers);
  }

  /// One height for the words on every step, so the scene under them never
  /// changes size between steps.
  double _copyHeight(BuildContext context, double width, TextScaler scaler) {
    final base = DefaultTextStyle.of(context).style;
    double measure(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: base.merge(style)),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
        textScaler: scaler,
      )..layout(maxWidth: width);
      final height = painter.height;
      painter.dispose();
      return height;
    }

    var tallest = 0.0;
    for (final step in _steps) {
      final c = copyFor(step);
      final h = measure(c.headline, Boarding.headline) +
          _Copy.gap +
          measure(c.body, Boarding.body);
      tallest = math.max(tallest, h);
    }
    return tallest + 2;
  }
}

/// The words and the progress leave as the student boards.
class _ChromeFade extends Animatable<double> {
  const _ChromeFade();

  @override
  double transform(double t) {
    final s = t * _boardTotal;
    return 1 - Curves.easeOut.transform((s / 0.32).clamp(0.0, 1.0));
  }
}

/// The overlay's arrow for one frame.
class _Pilot {
  const _Pilot(this.pose,
      {this.bank = 0,
      this.trail = const [],
      this.trailStrength = 0,
      this.shine = -1});
  final ArrowPose pose;
  final double bank;
  final List<Offset> trail;
  final double trailStrength;
  final double shine;
}

class _PilotPainter extends CustomPainter {
  _PilotPainter(this.pilot);
  final _Pilot? pilot;

  @override
  void paint(Canvas canvas, Size size) {
    final p = pilot;
    if (p == null) return;
    if (p.shine >= 0) {
      canvas.save();
      canvas.translate(p.pose.at.dx, p.pose.at.dy);
      paintGlassArrow(canvas,
          height: p.pose.height, glow: p.pose.glow, shine: p.shine);
      canvas.restore();
      return;
    }
    paintFlight(canvas, p.pose,
        bank: p.bank, trail: p.trail, trailStrength: p.trailStrength);
  }

  @override
  bool shouldRepaint(_PilotPainter old) => true;
}

/// One step's object on the stage, faded by [opacity].
class _SceneLayer extends StatelessWidget {
  const _SceneLayer({super.key, required this.opacity, required this.child});
  final double opacity;
  final Widget child;

  @override
  Widget build(BuildContext context) => Positioned.fill(
        child: IgnorePointer(
          ignoring: opacity < 1,
          child: Opacity(opacity: opacity.clamp(0.0, 1.0), child: child),
        ),
      );
}

/// A step's words: the headline, then the line under it a beat later.
class _Copy extends StatefulWidget {
  const _Copy(
      {super.key,
      required this.copy,
      required this.still,
      this.delay = Duration.zero});
  final BoardingCopy copy;
  final bool still;

  /// The words wait for the picture to change.
  final Duration delay;

  static const gap = 12.0;

  @override
  State<_Copy> createState() => _CopyState();
}

class _CopyState extends State<_Copy> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 760));
  Timer? _wait;

  @override
  void initState() {
    super.initState();
    if (widget.still) {
      _c.value = 1;
    } else if (widget.delay > Duration.zero) {
      _wait = Timer(widget.delay, () {
        if (mounted) _c.forward();
      });
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _wait?.cancel();
    _c.dispose();
    super.dispose();
  }

  Widget _line(int order, Widget child) {
    // After the last step's words have gone, one line at a time.
    final start = 0.2 + order * 0.1;
    final curve = CurvedAnimation(
        parent: _c,
        curve: Interval(start, math.min(1, start + 0.62),
            curve: Curves.easeOutCubic));
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.18), end: Offset.zero)
            .animate(curve),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final copy = widget.copy;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      _line(
          0,
          Semantics(
              header: true,
              child: BalancedText(copy.headline, style: Boarding.headline))),
      const SizedBox(height: _Copy.gap),
      _line(1, BalancedText(copy.body, style: Boarding.body)),
    ]);
  }
}

/// For the tests and the rehearsal: where the onboarding is, and a way to
/// put it on a step without walking there.
@visibleForTesting
extension OnboardingProbe on FirstLaunchOnboardingState {
  BoardingStep get currentStep => _step;
  List<BoardingStep> get plannedSteps => _steps;

  /// Whether the student may act on the object now.
  bool get armed => _armed;

  /// Where the flying arrow is, in the onboarding's points, while one flies.
  Offset? get pilotAt => _pilot()?.pose.at;

  void debugJumpTo(BoardingStep step) {
    _skipIntro();
    final index = _steps.indexOf(step);
    if (index >= 0) _goTo(index);
  }
}
