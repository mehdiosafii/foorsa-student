/// The onboarding has no buttons: on each screen the student acts on the
/// object itself. What to do is said quietly under it, a moment after the
/// object appears, and the object shows it can be acted on with a small
/// movement now and then until it is ([idleNudge]).
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'arrow_flight.dart';
import 'boarding_style.dart';

/// The student acted on the screen's object. A scene whose object is an
/// arrow says where that arrow is, so it can fly on from there, and how fast
/// it was going if it was thrown.
typedef SceneAct = void Function({ArrowPose? arrow, Offset? velocity});

/// A pulse, 0 to 1 and back, every [every] seconds once [after] seconds have
/// passed with the student doing nothing; 0 otherwise.
double idleNudge(double t,
    {double after = 2.4, double every = 4.2, double length = 0.9}) {
  if (t < after) return 0;
  final p = (t - after) % every;
  if (p > length) return 0;
  return math.sin(math.pi * p / length);
}

/// The gesture, under the object: it comes in a beat after the object,
/// breathes while it waits, and goes once the student has acted.
class GestureHint extends StatefulWidget {
  const GestureHint(this.text,
      {super.key, this.shown = true, this.still = false});
  final String text;
  final bool shown;
  final bool still;

  @override
  State<GestureHint> createState() => _GestureHintState();
}

class _GestureHintState extends State<GestureHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400));
  bool _arrived = false;
  Timer? _wait;

  @override
  void initState() {
    super.initState();
    if (widget.still) {
      _arrived = true;
      _breath.value = 1;
      return;
    }
    _wait = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      setState(() => _arrived = true);
      _breath.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _wait?.cancel();
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Words only: a touch on them reaches the object under them.
    return IgnorePointer(
      child: ExcludeSemantics(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 420),
          opacity: _arrived && widget.shown ? 1 : 0,
          child: FadeTransition(
            opacity: Tween(begin: 0.62, end: 1.0).animate(
                CurvedAnimation(parent: _breath, curve: Curves.easeInOut)),
            child: Text(
              widget.text,
              textAlign: TextAlign.center,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.1,
                height: 1.2,
                color: Boarding.muted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// An object that is the screen's control: pressed like the portal's
/// controls (in within 100 ms, back on a spring), felt as it is pressed, and
/// a button named [label] for a screen reader.
class ObjectControl extends StatelessWidget {
  const ObjectControl({
    super.key,
    required this.label,
    required this.armed,
    required this.feel,
    required this.onTap,
    required this.child,
    this.scale = 0.96,
  });

  final String label;
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
