/// The first-launch onboarding: the takeoff, the welcome board, a step for
/// each phone access that can still be asked for, and the boarding pass.
///
/// One arrow tells it. It waits at the gate of the runway, the one control
/// at the foot of the screen; the student presses the runway and the arrow
/// taxis, lifts off and swoops up into the picture, which has folded into an
/// arrow of light for it to dock in, and unfolds as the next picture while
/// the next arrow rolls in to the gate. On the last screen it cuts the
/// boarding pass's stub off along the perforation, takes what is left of the
/// pass into itself and lands on the sign-in's own arrow, and the onboarding
/// fades onto the portal underneath.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'arrow_flight.dart';
import 'boarding_pass.dart';
import 'boarding_style.dart';
import 'brand_marks.dart';
import 'glass.dart';
import 'glass_arrow.dart';
import 'lucide.dart';
import 'night_sky.dart';
import 'onboarding_flow.dart';
import 'onboarding_sound.dart';
import 'route_progress.dart';
import 'runway.dart';
import 'scene_departures.dart';
import 'scene_location.dart';
import 'scene_notifications.dart';
import 'scene_scan.dart';
import 'scene_tracking.dart';
import 'scene_voice.dart';
import 'stage_forms.dart';
import 'stage_morph.dart';
import 'takeoff_intro.dart';

/// A step's flight, in seconds from the arrow leaving the runway: it swoops
/// in as the picture folds into an arrow of light, docks, shines, and the
/// picture unfolds as the next one while the next arrow rolls in.
const _swoopSeconds = 0.6;
const _foldFrom = 0.32;
const _beatTo = 0.72;
const _wordsFrom = 0.78;
const _arriveFrom = 0.84;
const _flightSeconds = 1.36;

/// Where the stage's morph is ([StageMorphPainter]'s progress) [s] seconds
/// into a flight.
double flightMorph(double s) {
  if (s <= _foldFrom) return 0;
  if (s < _swoopSeconds) {
    return arrowAt * (s - _foldFrom) / (_swoopSeconds - _foldFrom);
  }
  if (s < _beatTo) {
    return arrowAt +
        (arrowLeaves - arrowAt) * (s - _swoopSeconds) / (_beatTo - _swoopSeconds);
  }
  return math.min(1.0,
      arrowLeaves + (1 - arrowLeaves) * (s - _beatTo) / (_flightSeconds - _beatTo));
}

double _smooth(double x) {
  final t = x.clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// Boarding, in seconds: the arrow swoops to the perforation, cuts along it,
/// rises to the middle as the pass folds into it, shines, flies to the
/// sign-in's arrow and the onboarding fades onto it. Torn by hand, the stub
/// is already off and the arrow flies straight in.
class _BoardTimes {
  const _BoardTimes.zip()
      : toNotch = 0.46,
        zipEnd = 0.92,
        foldFrom = 1.02,
        dock = 1.4,
        shineEnd = 1.58,
        markEnd = 2.08,
        total = 2.48;
  const _BoardTimes.straight()
      : toNotch = 0,
        zipEnd = 0,
        foldFrom = 0.26,
        dock = 0.6,
        shineEnd = 0.78,
        markEnd = 1.28,
        total = 1.68;
  final double toNotch, zipEnd, foldFrom, dock, shineEnd, markEnd, total;
  bool get zips => zipEnd > 0;
}

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
  /// the new one. Driven by [_flight] going forward, by itself going back.
  late final AnimationController _shift = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1050));

  // The runway's arrow: rolling out, rolling in, held under a finger.
  late final AnimationController _depart = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 520));
  late final AnimationController _arrive = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 640), value: 1);
  late final AnimationController _press =
      AnimationController.unbounded(vsync: this);

  /// From the runway into the picture ([_flightSeconds]).
  late final AnimationController _flight = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: (_flightSeconds * 1000) ~/ 1));

  /// Boarding: the stub, the pass, the sign-in ([_BoardTimes]).
  late final AnimationController _exit = AnimationController(vsync: this);
  _BoardTimes _board = const _BoardTimes.zip();

  /// Seconds since the onboarding opened, for the arrow's idle breath and
  /// its hover while the phone asks.
  late final Ticker _ticker;
  final ValueNotifier<double> _clock = ValueNotifier<double>(0);

  RunwayPhase _runway = RunwayPhase.away;

  /// The arrow hovers over the runway while the phone's prompt is up.
  bool _holding = false;
  double _heldSince = 0;
  Swoop? _swoop;
  bool _ghost = false;
  final Set<String> _beats = {};

  final GlobalKey _overlayKey = GlobalKey();
  final GlobalKey _runwayKey = GlobalKey();
  final GlobalKey _stageKey = GlobalKey();

  BoardingStep? _previous;
  BoardingPlan? _plan;
  int _index = 0;
  bool _introDone = false;
  bool _busy = false;
  bool _leaving = false;
  final Map<BoardingAccess, bool> _answered = {};
  ValueNotifier<bool?> _outcome = ValueNotifier<bool?>(null);

  /// The words of the step come in a beat after it, on a flight.
  Duration _wordsDelay = Duration.zero;

  /// The student just said yes: a check on the runway for a moment.
  bool _done = false;
  final GlobalKey<BoardingPassSceneState> _passKey =
      GlobalKey<BoardingPassSceneState>();

  /// Boarding: where the sign-in's arrow is, in the overlay's points.
  Rect? _mark;
  Swoop? _boardSwoop;
  Swoop? _riseSwoop;
  Offset? _notchFrom, _notchTo;

  /// The progress, the words and the runway step aside as the student boards.
  late final Animation<double> _chromeFade = _exit.drive(_ChromeFade(this));
  bool _feltUnfold = false;
  bool _feltRelease = false;
  bool _feltLift = false;

  /// The welcome's board flips when it appears, not while the plane flies.
  bool _contentShown = false;
  bool _still = false;
  bool _introStarted = false;

  List<BoardingStep> get _steps =>
      _plan?.steps ?? const [BoardingStep.welcome, BoardingStep.boarding];
  BoardingStep get _step => _steps[_index];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _intro.addListener(_introTick);
    _flight.addListener(_flightTick);
    _exit.addListener(_exitTick);
    _depart.addListener(_departTick);
    _ticker = createTicker(
        (elapsed) => _clock.value = elapsed.inMicroseconds / 1e6);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.disableAnimationsOf(context);
    if (_still != still || !_introStarted) {
      _still = still;
      if (!_still && !_ticker.isActive) _ticker.start();
      if (_still && _ticker.isActive) _ticker.stop();
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
      _runway = RunwayPhase.parked;
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
    _rollIn(delay: const Duration(milliseconds: 260));
  }

  /// The next arrow rolls in to the gate.
  void _rollIn({Duration delay = Duration.zero}) {
    if (_still) {
      setState(() => _runway = RunwayPhase.parked);
      return;
    }
    Future<void>.delayed(delay, () {
      if (!mounted) return;
      setState(() => _runway = RunwayPhase.arriving);
      _arrive.forward(from: 0).whenComplete(() {
        if (!mounted || _runway != RunwayPhase.arriving) return;
        setState(() => _runway = RunwayPhase.parked);
        widget.feel('detent');
        widget.sounds.play('park');
      });
    });
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
    _ticker.dispose();
    _clock.dispose();
    _intro.dispose();
    _night.dispose();
    _drift.dispose();
    _route.dispose();
    _content.dispose();
    _shift.dispose();
    _depart.dispose();
    _arrive.dispose();
    _press.dispose();
    _flight.dispose();
    _exit.dispose();
    _outcome.dispose();
    super.dispose();
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

  Offset? _overlayPoint(GlobalKey key, Offset local) {
    final box = _box(key), overlay = _box(_overlayKey);
    if (box == null || overlay == null) return null;
    return overlay.globalToLocal(box.localToGlobal(local));
  }

  Offset? get _stageCentre {
    final stage = _box(_stageKey);
    if (stage == null) return null;
    return _overlayPoint(_stageKey, stage.size.center(Offset.zero));
  }

  /// The arrow over the runway's far end, as it lifted off; bobbing while the
  /// phone asks.
  ArrowPose? _liftPose() {
    final runway = _box(_runwayKey);
    if (runway == null) return null;
    final at = _overlayPoint(_runwayKey, runwayLiftOff(runway.size));
    if (at == null) return null;
    if (!_holding) {
      return ArrowPose(at, restHeading, liftArrowHeight, glow: 0.9);
    }
    final t = _clock.value - _heldSince;
    final settle = _smooth(t / 0.5);
    final bob = math.sin(t * 2 * math.pi / 2.4);
    return ArrowPose(at + Offset(0, 2.6 * bob * settle),
        restHeading + 0.05 * math.sin(t * 2 * math.pi / 2.4 + 0.9) * settle,
        liftArrowHeight,
        glow: 0.9 - 0.2 * settle);
  }

  void _departTick() {
    if (!_feltLift && departProgress(_depart.value) > 0.7) {
      _feltLift = true;
      widget.feel('release');
    }
  }

  void _pressDown() {
    widget.feel('press');
    widget.sounds.play('tap');
    if (_still) return;
    _press.animateTo(1,
        duration: const Duration(milliseconds: 100), curve: Curves.easeOut);
  }

  void _pressUp() {
    if (_still) {
      _press.value = 0;
      return;
    }
    _press.animateWith(SpringSimulation(
        foorsaSpring(damping: 0.72, response: 0.24),
        _press.value,
        0,
        _press.velocity));
  }

  /// The arrow taxis and lifts off. Completes once it is in the air.
  Future<void> _takeOff() async {
    _feltLift = false;
    setState(() => _runway = RunwayPhase.departing);
    widget.sounds.play('takeoff');
    await _depart.forward(from: 0);
    if (!mounted) return;
    setState(() {
      _runway = RunwayPhase.away;
      _holding = false;
    });
  }

  /// The runway, pressed.
  Future<void> _continue() async {
    if (_busy || _leaving || _runway != RunwayPhase.parked) return;
    if (_step == BoardingStep.boarding) {
      await _boardNow(zip: true);
      return;
    }
    final access = _step.access;
    final asks = access != null && !_answered.containsKey(access);
    setState(() => _busy = true);
    if (!_still) await _takeOff();
    if (!mounted) return;
    if (asks) {
      if (!_still) {
        setState(() {
          _holding = true;
          _heldSince = _clock.value;
        });
      }
      AccessState answer;
      try {
        answer = await widget.permissions.request(access);
      } catch (_) {
        answer = AccessState.unavailable;
      }
      if (!mounted) return;
      final on = answer == AccessState.granted;
      _answered[access] = on;
      _outcome.value = on;
      // A yes is felt and shown, a no simply moves on: nothing on the way
      // makes a student feel they answered wrong.
      if (on) {
        widget.feel('land');
        widget.sounds.play('granted');
        setState(() => _done = true);
        widget.onGranted?.call(access);
      }
      await Future<void>.delayed(Duration(milliseconds: on ? 760 : 260));
      if (!mounted) return;
    }
    if (_still) {
      _goTo(_index + 1);
      setState(() => _busy = false);
      return;
    }
    _fly(_index + 1, fromRun: !asks);
  }

  /// From the air over the runway into the picture, which becomes step
  /// [next].
  void _fly(int next, {required bool fromRun}) {
    final from = _liftPose();
    final to = _stageCentre;
    setState(() {
      _swoop = from == null || to == null
          ? null
          : Swoop.intoStage(
              from: from.at,
              fromHeading: from.heading,
              fromHeight: liftArrowHeight,
              to: to,
              // Straight on from the run, or off from a hover.
              speed: fromRun ? 1.5 : 0.2,
            );
      _holding = false;
      _ghost = _swoop != null;
      _previous = _step;
      _index = next;
      _done = false;
      _wordsDelay = const Duration(milliseconds: (_wordsFrom * 1000) ~/ 1);
      _outcome = ValueNotifier<bool?>(
          _step.access == null ? null : _answered[_step.access]);
    });
    _beats.clear();
    widget.sounds.play('swoop');
    _spring(_drift, _index.toDouble(), response: 1.1);
    _spring(_route, _steps.length <= 1 ? 0 : _index / (_steps.length - 1));
    _flight.forward(from: 0).whenComplete(() {
      if (!mounted || _flight.value < 1) return;
      setState(() {
        _previous = null;
        _swoop = null;
        _ghost = false;
        _busy = false;
      });
    });
  }

  void _flightTick() {
    final s = _flight.value * _flightSeconds;
    _shift.value = flightMorph(s);
    if (s >= _swoopSeconds && _beats.add('dock')) {
      // It docks: the picture has become the arrow.
      widget.feel('detent');
      widget.sounds.play('dock');
    }
    if (s >= _beatTo && _beats.add('unfold')) {
      widget.sounds.play('step-${_index.clamp(1, 6)}');
    }
    if (s >= _arriveFrom && _beats.add('arrive')) _rollIn();
  }

  /// Straight to step [index], the stage morphing on its own: going back,
  /// with Reduce Motion, and for the tests.
  void _goTo(int index) {
    if (index < 0 || index >= _steps.length || index == _index) return;
    final from = _step;
    setState(() {
      _previous = from;
      _index = index;
      _done = false;
      _busy = false;
      _ghost = false;
      _swoop = null;
      _wordsDelay = Duration.zero;
      _outcome = ValueNotifier<bool?>(
          _step.access == null ? null : _answered[_step.access]);
    });
    widget.sounds.play('step-${index.clamp(1, 6)}');
    _shift.duration = Duration(milliseconds: _still ? 240 : 1050);
    _shift.forward(from: 0).whenComplete(() {
      if (mounted && _shift.value >= 1) setState(() => _previous = null);
    });
    _spring(_drift, index.toDouble(), response: 0.9);
    _spring(_route, _steps.length <= 1 ? 0 : index / (_steps.length - 1));
  }

  // Boarding.

  /// The pass's two notches and the stage's middle, in the overlay's points.
  (Offset, Offset)? _notches() {
    final stage = _box(_stageKey);
    final centre = _stageCentre;
    if (stage == null || centre == null) return null;
    final s = passScale(stage.size);
    final y = centre.dy - passHeight * s / 2 + passTearY * s;
    final half = passWidth * s / 2;
    return (Offset(centre.dx - half + 16 * s, y), Offset(centre.dx + half - 16 * s, y));
  }

  /// The student boards: by the runway ([zip], the arrow cuts the stub off)
  /// or by tearing the stub off themselves.
  Future<void> _boardNow({required bool zip}) async {
    if (_leaving) return;
    setState(() {
      _leaving = true;
      _busy = true;
    });
    Rect? mark;
    Future<Rect?> find() async {
      try {
        return await widget.findMark?.call();
      } catch (_) {
        return null;
      }
    }

    final finding = _still
        ? Future<Rect?>.value()
        : find().timeout(const Duration(milliseconds: 600),
            onTimeout: () => null);
    if (!_still) {
      await _takeOff();
      if (!mounted) return;
      // It waits over the runway for as long as the page takes to answer.
      setState(() {
        _holding = true;
        _heldSince = _clock.value;
      });
    }
    try {
      mark = await finding;
    } catch (_) {}
    if (!mounted) return;
    widget.sounds.endBed();
    if (_still) {
      _passKey.currentState?.tearQuietly();
      widget.sounds.play('tear');
      widget.sounds.play('board');
      _exit.duration = const Duration(milliseconds: 320);
      _exit.forward().whenComplete(widget.onFinished);
      return;
    }
    final overlay = _box(_overlayKey);
    if (mark != null && overlay != null) {
      final topLeft = overlay.globalToLocal(mark.topLeft);
      // The page's arrow fills its 757 box; the mark itself is 712 of it.
      _mark = Rect.fromCenter(
          center: topLeft + mark.size.center(Offset.zero),
          width: mark.width * 712 / 757,
          height: mark.height * 712 / 757);
    }
    final lift = _liftPose();
    final centre = _stageCentre;
    final notches = _notches();
    _board = zip && notches != null
        ? const _BoardTimes.zip()
        : const _BoardTimes.straight();
    if (lift != null && centre != null) {
      if (_board.zips) {
        _notchFrom = notches!.$1;
        _notchTo = notches.$2;
        // Up and across under the pass, in at the left notch, levelling off
        // onto the perforation.
        _boardSwoop = Swoop(
            from: lift.at,
            fromHeading: lift.heading,
            fromHeight: liftArrowHeight,
            to: _notchFrom!,
            toHeading: 0,
            toHeight: 28,
            speed: 1.5,
            launch: const Offset(-0.45, -1),
            approach: const Offset(1, -1));
        // From the right notch, a short climb round into the middle.
        _riseSwoop = Swoop(
            from: _notchTo!,
            fromHeading: 0,
            fromHeight: 28,
            to: centre,
            toHeight: stageArrowHeight,
            speed: 1.2,
            launch: const Offset(0.35, -1),
            approach: const Offset(-0.6, -1));
      } else {
        _riseSwoop = Swoop.intoStage(
            from: lift.at,
            fromHeading: lift.heading,
            fromHeight: liftArrowHeight,
            to: centre,
            speed: 1.5);
      }
    }
    _beats.clear();
    setState(() => _holding = false);
    widget.sounds.play('swoop');
    _exit.duration = Duration(milliseconds: (_board.total * 1000).round());
    _exit.forward().whenComplete(widget.onFinished);
  }

  void _exitTick() {
    if (_still) {
      if (_exit.value >= 0 && _beats.add('boarded')) widget.onBoarded?.call();
      return;
    }
    final s = _exit.value * _board.total;
    final pass = _passKey.currentState;
    if (_board.zips) {
      if (s >= _board.toNotch && _beats.add('cut')) {
        widget.sounds.play('tear');
      }
      if (s >= _board.toNotch && s < _board.zipEnd) {
        // The stub comes away behind the arrow (and is felt doing so).
        final p = (s - _board.toNotch) / (_board.zipEnd - _board.toNotch);
        pass?.peel(Curves.easeInOut.transform(p));
      }
      if (s >= _board.zipEnd && _beats.add('drop')) {
        pass?.tearQuietly();
        widget.feel('release');
      }
    }
    if (s >= _board.dock && _beats.add('dock')) {
      widget.feel('detent');
      widget.sounds.play('dock');
    }
    if (s >= _board.shineEnd && _beats.add('board')) {
      widget.sounds.play('board');
    }
    // The arrow is on the sign-in's: the page may show itself.
    if (s >= _board.markEnd - 0.1 && _beats.add('boarded')) {
      widget.feel('land');
      widget.onBoarded?.call();
    }
  }

  /// Android's back: one step back, out of the app from the welcome.
  void back() {
    if (_leaving || _busy) return;
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

  void _toggleSound() {
    widget.feel('press');
    setState(() => widget.sounds.muted = !widget.sounds.muted);
  }

  Widget _scene(BoardingStep step) => switch (step) {
        BoardingStep.welcome => _contentShown
            ? DeparturesScene(
                still: _still,
                feel: widget.feel,
                onFlip: () => widget.sounds.play('flap'))
            : const SizedBox.shrink(),
        BoardingStep.notifications => NotificationsScene(
            still: _still, feel: widget.feel, outcome: _outcome),
        BoardingStep.camera => ScanScene(still: _still, feel: widget.feel),
        BoardingStep.microphone => VoiceScene(still: _still, feel: widget.feel),
        BoardingStep.location =>
          LocationScene(still: _still, feel: widget.feel),
        BoardingStep.tracking => TrackingScene(still: _still),
        BoardingStep.boarding => BoardingPassScene(
            key: _passKey,
            still: _still,
            feel: widget.feel,
            onTear: () => widget.sounds.play('tear'),
            onTorn: () => _boardNow(zip: false),
          ),
      };

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
                : ((_exit.value * _board.total - _board.markEnd) /
                        (_board.total - _board.markEnd))
                    .clamp(0.0, 1.0);
            if (fade <= 0) return child!;
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
                  animation: Listenable.merge([_flight, _exit, _clock]),
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

  /// What the overlay draws this frame: the arrow hovering, swooping, cutting
  /// along the pass or flying to the sign-in.
  _Pilot? _pilot() {
    if (_still) return null;
    if (_holding) {
      final pose = _liftPose();
      return pose == null ? null : _Pilot(pose);
    }
    if (_leaving && _exit.value > 0) return _boardingPilot();
    final swoop = _swoop;
    if (swoop != null && _flight.isAnimating) {
      final s = _flight.value * _flightSeconds;
      if (s >= _swoopSeconds) return null;
      final t = s / _swoopSeconds;
      final (pose, bank) = swoop.at(t, glowFrom: 0.9);
      return _Pilot(pose,
          bank: bank,
          trail: swoop.trail(t),
          trailStrength: 1 - _smooth((t - 0.7) / 0.3));
    }
    return null;
  }

  _Pilot? _boardingPilot() {
    final s = _exit.value * _board.total;
    final b = _board;
    if (b.zips && s < b.toNotch && _boardSwoop != null) {
      final t = s / b.toNotch;
      final (pose, bank) = _boardSwoop!.at(t, glowFrom: 0.9, glowTo: 0.9);
      return _Pilot(pose,
          bank: bank,
          trail: _boardSwoop!.trail(t),
          trailStrength: 1 - _smooth((t - 0.75) / 0.25));
    }
    if (b.zips && s < b.zipEnd && _notchFrom != null && _notchTo != null) {
      final p = Curves.easeInOut.transform((s - b.toNotch) / (b.zipEnd - b.toNotch));
      final at = Offset.lerp(_notchFrom, _notchTo, p)!;
      return _Pilot(ArrowPose(at, 0, 28, glow: 1), cut: (_notchFrom!, at));
    }
    if (s < b.dock && _riseSwoop != null) {
      final from = b.zips ? b.zipEnd : 0.0;
      final t = ((s - from) / (b.dock - from)).clamp(0.0, 1.0);
      final (pose, bank) = _riseSwoop!.at(t, glowFrom: 0.9);
      return _Pilot(pose,
          bank: bank,
          trail: _riseSwoop!.trail(t),
          trailStrength: 1 - _smooth((t - 0.7) / 0.3),
          cut: b.zips && _notchFrom != null && _notchTo != null
              ? (_notchFrom!, _notchTo!)
              : null,
          cutFade: 1 - _smooth(t / 0.5));
    }
    final centre = _riseSwoop?.to ?? _stageCentre;
    if (centre == null) return null;
    if (s < b.shineEnd) {
      final shine = (s - b.dock) / (b.shineEnd - b.dock);
      return _Pilot(
          ArrowPose(centre, restHeading, stageArrowHeight, glow: 0.8),
          shine: shine);
    }
    final mark = _mark;
    final go = Curves.easeInOutCubic
        .transform(((s - b.shineEnd) / (b.markEnd - b.shineEnd)).clamp(0.0, 1.0));
    final at = mark == null ? centre : Offset.lerp(centre, mark.center, go)!;
    final height = mark == null
        ? stageArrowHeight
        : ui.lerpDouble(stageArrowHeight, mark.height, go)!;
    return _Pilot(ArrowPose(at, restHeading, height, glow: 0.8 * (1 - go)));
  }

  /// The smallest a scene may be. Below it the screen scrolls instead.
  static const _minScene = 200.0;

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
              final gap = compact ? 20.0 : 28.0;
              final fixed =
                  8 + 36 + 12 + gap + copyHeight + gap + runwayHeight + 12;
              final room = constraints.maxHeight - fixed;

              final top = SizedBox(
                height: 36,
                child: Stack(alignment: Alignment.center, children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 420),
                    child: _step == BoardingStep.welcome
                        ? const FoorsaWordmark(
                            key: ValueKey('mark'),
                            height: 20,
                            color: Boarding.heading)
                        : RouteProgress(
                            key: const ValueKey('route'), progress: _route),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: _SoundToggle(
                        muted: widget.sounds.muted, onTap: _toggleSound),
                  ),
                ]),
              );

              // The scenes are illustrations at a fixed size: the words
              // under them follow the phone's text size.
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
                                ? _boardingStage(Size(box.maxWidth, box.maxHeight))
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
                    // Anchored to the runway, so the space above it is the
                    // same on every step.
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.bottomCenter,
                      children: [...previous, if (current != null) current],
                    ),
                    transitionBuilder: (child, animation) =>
                        child.key == ValueKey(_step)
                            ? child
                            : FadeTransition(opacity: animation, child: child),
                    child: _Copy(
                        key: ValueKey(_step),
                        copy: copy,
                        still: _still,
                        delay: _wordsDelay),
                  ),
                ),
              );

              final action = Runway(
                key: _runwayKey,
                label: copy.action,
                phase: _runway,
                depart: _depart,
                arrive: _arrive,
                press: _press,
                clock: _clock,
                done: _done,
                still: _still,
                onDown: _pressDown,
                onUp: _pressUp,
                onPressed: _plan == null ? null : _continue,
              );

              List<Widget> parts(Widget sceneSlot) => [
                    const SizedBox(height: 8),
                    FadeTransition(opacity: _chromeFade, child: top),
                    const SizedBox(height: 12),
                    sceneSlot,
                    SizedBox(height: gap),
                    FadeTransition(opacity: _chromeFade, child: words),
                    SizedBox(height: gap),
                    FadeTransition(opacity: _chromeFade, child: action),
                    const SizedBox(height: 12),
                  ];

              if (room >= _minScene) {
                return Column(children: parts(Expanded(child: scene)));
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

  /// Boarding on the stage: the pass, then what is left of it folding into
  /// an arrow of light for the flying arrow to dock in.
  Widget _boardingStage(Size stage) {
    final s = _exit.value * _board.total;
    final layers = <Widget>[];
    final fold = ((s - _board.foldFrom) / (_board.dock - _board.foldFrom));
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
            ghost: true,
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

  /// One height for the words on every step, so the scene above them never
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
      return painter.height;
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

/// The words, the progress and the runway leave as the student boards, once
/// the arrow has left the runway.
class _ChromeFade extends Animatable<double> {
  _ChromeFade(this.page);
  final FirstLaunchOnboardingState page;

  @override
  double transform(double t) {
    final total = page._board.total;
    final s = t * total;
    return 1 - Curves.easeOut.transform((s / 0.32).clamp(0.0, 1.0));
  }
}

/// The overlay's arrow for one frame.
class _Pilot {
  const _Pilot(this.pose,
      {this.bank = 0,
      this.trail = const [],
      this.trailStrength = 0,
      this.shine = -1,
      this.cut,
      this.cutFade = 1});
  final ArrowPose pose;
  final double bank;
  final List<Offset> trail;
  final double trailStrength;
  final double shine;

  /// The perforation, lit where the arrow has cut it.
  final (Offset, Offset)? cut;
  final double cutFade;
}

class _PilotPainter extends CustomPainter {
  _PilotPainter(this.pilot);
  final _Pilot? pilot;

  @override
  void paint(Canvas canvas, Size size) {
    final p = pilot;
    if (p == null) return;
    final cut = p.cut;
    if (cut != null && p.cutFade > 0) {
      final (from, to) = cut;
      canvas.drawLine(
          from,
          to,
          Paint()
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round
            ..shader = ui.Gradient.linear(from, to, [
              const Color(0x00EAF4FF),
              Color.fromRGBO(234, 244, 255, 0.9 * p.cutFade),
            ])
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5));
    }
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

/// The sound, in the corner: on unless the student turns it off.
class _SoundToggle extends StatelessWidget {
  const _SoundToggle({required this.muted, required this.onTap});
  final bool muted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: muted ? 'Sound off' : 'Sound on',
      hint: muted ? 'Turns the sound on' : 'Turns the sound off',
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        scale: 0.92,
        child: SizedBox.square(
          // A 44 pt target round a 34 pt glass button.
          dimension: 44,
          child: Center(
            child: SizedBox.square(
              dimension: 34,
              child: GlassPane(
                glass: Glass.tile,
                circle: true,
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Lucide(muted ? LucideIcons.volumeOff : LucideIcons.volume,
                        key: ValueKey(muted),
                        size: 16,
                        color: Boarding.ink.withValues(alpha: 0.9),
                        strokeWidth: 1.9),
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

  /// On a flight the words wait for the picture to unfold.
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
  RunwayPhase get runwayPhase => _runway;

  void debugJumpTo(BoardingStep step) {
    _skipIntro();
    final index = _steps.indexOf(step);
    if (index >= 0) _goTo(index);
  }
}
