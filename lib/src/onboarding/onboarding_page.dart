/// The first-launch onboarding: the takeoff, the welcome board, a step for
/// each phone access that can still be asked for, and the boarding pass. It
/// sits over the shell while the portal loads underneath, so when the student
/// boards, the sign-in is already there and opens through a widening circle.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import 'boarding_pass.dart';
import 'boarding_style.dart';
import 'brand_marks.dart';
import 'night_sky.dart';
import 'onboarding_flow.dart';
import 'route_progress.dart';
import 'scene_departures.dart';
import 'scene_location.dart';
import 'scene_notifications.dart';
import 'scene_scan.dart';
import 'scene_tracking.dart';
import 'scene_voice.dart';
import 'takeoff_intro.dart';

class FirstLaunchOnboarding extends StatefulWidget {
  const FirstLaunchOnboarding({
    super.key,
    required this.permissions,
    required this.feel,
    required this.onFinished,
    required this.isIOS,
    required this.asksToTrack,
    this.splash,
  });

  /// The launch screen's roundel, decoded before the first frame.
  final ui.Image? splash;

  final BoardingPermissions permissions;
  final Feel feel;

  /// The circle has opened on the portal: the onboarding can go.
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
  late final AnimationController _exit = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900));

  BoardingPlan? _plan;
  int _index = 0;
  bool _introDone = false;
  bool _busy = false;
  bool _leaving = false;
  final Map<BoardingAccess, bool> _answered = {};
  ValueNotifier<bool?> _outcome = ValueNotifier<bool?>(null);

  /// The student just said yes: the button shows a check for a moment.
  bool _done = false;
  Offset? _revealCentre;
  final GlobalKey<BoardingPassSceneState> _passKey =
      GlobalKey<BoardingPassSceneState>();
  final GlobalKey _buttonKey = GlobalKey();
  bool _feltUnfold = false;

  /// The welcome's board flips when it appears, not while the plane flies.
  bool _contentShown = false;

  void _showContent() {
    if (_contentShown) return;
    _contentShown = true;
    if (mounted) setState(() {});
    _content.forward();
  }

  bool _feltRelease = false;
  bool _still = false;

  List<BoardingStep> get _steps =>
      _plan?.steps ?? const [BoardingStep.welcome, BoardingStep.boarding];
  BoardingStep get _step => _steps[_index];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _intro.addListener(_introTick);
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

  bool _introStarted = false;

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
    _intro.forward().whenComplete(() {
      if (mounted) setState(() => _introDone = true);
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
    if (!_feltUnfold && s > 0.95) {
      _feltUnfold = true;
      widget.feel('unfold');
    }
    if (!_feltRelease && s > 2.2) {
      _feltRelease = true;
      widget.feel('release');
    }
    // The welcome comes once the plane has cleared it.
    if (s > 2.82) _showContent();
  }

  void _skipIntro() {
    if (_introDone) return;
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

  void _goTo(int index) {
    if (index < 0 || index >= _steps.length) return;
    setState(() {
      _index = index;
      _done = false;
      _busy = false;
      _outcome = ValueNotifier<bool?>(
          _step.access == null ? null : _answered[_step.access]);
    });
    _spring(_drift, index.toDouble(), response: 0.9);
    _spring(_route, _steps.length <= 1 ? 0 : index / (_steps.length - 1));
  }

  /// The one button.
  Future<void> _continue() async {
    if (_busy || _leaving) return;
    switch (_step) {
      case BoardingStep.welcome:
        _goTo(_index + 1);
      case BoardingStep.boarding:
        await _board();
      default:
        final access = _step.access!;
        if (_answered.containsKey(access)) {
          // Back here after answering: the prompt will not show again.
          _goTo(_index + 1);
          return;
        }
        setState(() => _busy = true);
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
          setState(() => _done = true);
        }
        final step = _index;
        await Future<void>.delayed(Duration(milliseconds: on ? 900 : 380));
        if (mounted && _index == step) _goTo(_index + 1);
    }
  }

  Future<void> _board() async {
    if (_leaving) return;
    final pass = _passKey.currentState;
    if (pass != null) {
      await pass.tear();
    } else {
      _leave();
    }
  }

  void _leave() {
    if (_leaving) return;
    _leaving = true;
    final box = _buttonKey.currentContext?.findRenderObject() as RenderBox?;
    final mine = context.findRenderObject() as RenderBox?;
    if (box != null && mine != null && box.hasSize) {
      _revealCentre =
          mine.globalToLocal(box.localToGlobal(box.size.center(Offset.zero)));
    }
    if (_still) {
      _exit.duration = const Duration(milliseconds: 260);
    }
    _exit.forward().whenComplete(widget.onFinished);
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

  Widget _scene(BoardingStep step) => switch (step) {
        BoardingStep.welcome => _contentShown
            ? DeparturesScene(still: _still, feel: widget.feel)
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
            onTorn: _leave,
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
            final e = Curves.easeInOutCubic.transform(_exit.value);
            if (e <= 0) return child!;
            return ClipPath(
              clipper: _RevealClipper(e, _revealCentre),
              child: Opacity(
                opacity: (1 - math.max(0.0, e - 0.75) * 4).clamp(0.0, 1.0),
                child: Transform.scale(scale: 1 + 0.05 * e, child: child),
              ),
            );
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
            if (!_introDone)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _skipIntro,
                child: Semantics(
                  label: 'Foorsa is opening. Tap to skip.',
                  child:
                      TakeoffIntro(time: _introSeconds, splash: widget.splash),
                ),
              ),
          ]),
        ),
      ),
    );
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
              final fixed = 8 + 32 + 12 + gap + copyHeight + gap + 56 + 12;
              final room = constraints.maxHeight - fixed;

              final top = SizedBox(
                height: 32,
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
              // under them follow the phone's text size.
              final scene = MediaQuery.withNoTextScaling(
                child: LayoutBuilder(builder: (context, box) {
                  final light = math.max(box.maxWidth, box.maxHeight) * 0.62;
                  return Stack(clipBehavior: Clip.none, children: [
                    Positioned(
                      left: box.maxWidth / 2 - light,
                      top: box.maxHeight / 2 - light,
                      width: light * 2,
                      height: light * 2,
                      child: FadeTransition(
                          opacity: _night, child: Spotlight(radius: light)),
                    ),
                    Positioned.fill(
                      child: AnimatedSwitcher(
                        duration: Duration(milliseconds: _still ? 200 : 700),
                        reverseDuration:
                            Duration(milliseconds: _still ? 200 : 260),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: _sceneTransition,
                        child: KeyedSubtree(
                            key: ValueKey(_step), child: _scene(_step)),
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
                    reverseDuration: const Duration(milliseconds: 160),
                    // Anchored to the button, so the space above it is the
                    // same on every step.
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.bottomCenter,
                      children: [...previous, if (current != null) current],
                    ),
                    transitionBuilder: (child, animation) =>
                        child.key == ValueKey(_step)
                            ? child
                            : FadeTransition(opacity: animation, child: child),
                    child:
                        _Copy(key: ValueKey(_step), copy: copy, still: _still),
                  ),
                ),
              );

              final action = PearlButton(
                key: _buttonKey,
                label: copy.action,
                busy: _busy,
                done: _done,
                onDown: () => widget.feel('press'),
                onPressed: _plan == null ? null : _continue,
              );

              List<Widget> parts(Widget sceneSlot) => [
                    const SizedBox(height: 8),
                    top,
                    const SizedBox(height: 12),
                    sceneSlot,
                    SizedBox(height: gap),
                    words,
                    SizedBox(height: gap),
                    action,
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

  Widget _sceneTransition(Widget child, Animation<double> animation) {
    final incoming = child.key == ValueKey(_step);
    if (_still) return FadeTransition(opacity: animation, child: child);
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final v = animation.value;
        // In: from a little smaller and lower, into place. Out: it simply
        // steps back and goes.
        final scale = incoming ? 0.94 + 0.06 * v : 0.97 + 0.03 * v;
        final rise = incoming ? (1 - v) * 14 : 0.0;
        return Opacity(
          opacity: v.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, rise),
            child: Transform.scale(scale: scale, child: child),
          ),
        );
      },
    );
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

/// A step's words: the headline, then the line under it a beat later.
class _Copy extends StatefulWidget {
  const _Copy({super.key, required this.copy, required this.still});
  final BoardingCopy copy;
  final bool still;

  static const gap = 12.0;

  @override
  State<_Copy> createState() => _CopyState();
}

class _CopyState extends State<_Copy> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 760));

  @override
  void initState() {
    super.initState();
    if (widget.still) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _line(int order, Widget child) {
    // After the last step's words have gone (160 ms), one line at a time.
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

/// The onboarding with a widening hole in it, the portal showing through.
class _RevealClipper extends CustomClipper<Path> {
  _RevealClipper(this.progress, this.centre);
  final double progress;
  final Offset? centre;

  @override
  Path getClip(Size size) {
    final c = centre ?? Offset(size.width / 2, size.height * 0.8);
    final far = [
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ].map((p) => (p - c).distance).reduce(math.max);
    return Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addOval(Rect.fromCircle(center: c, radius: far * progress * 1.02));
  }

  @override
  bool shouldReclip(_RevealClipper old) =>
      old.progress != progress || old.centre != centre;
}

/// For the tests and the rehearsal: where the onboarding is, and a way to
/// put it on a step without walking there.
@visibleForTesting
extension OnboardingProbe on FirstLaunchOnboardingState {
  BoardingStep get currentStep => _step;
  List<BoardingStep> get plannedSteps => _steps;

  void debugJumpTo(BoardingStep step) {
    _skipIntro();
    final index = _steps.indexOf(step);
    if (index >= 0) _goTo(index);
  }
}
