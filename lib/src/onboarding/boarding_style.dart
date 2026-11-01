/// The onboarding's look. It is the portal's dark theme pared down to what a
/// first screen needs: one ground, one light behind one object, a headline
/// and one line over it, and the object itself as the control (portal.css
/// and portalMaterials.css in foorsa-reward: the dark ink, the muted text,
/// the glass; glass.dart has the material).
/// The onboarding is always the night the native splash opens on, so these are
/// the dark values only.
library;

import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

/// A touch by the shell's texture names (shell_haptics.dart): `press`,
/// `detent`, `land`, `grain` (with a level), `release`, `unfold`, `arrive`.
typedef Feel = void Function(String touch, [double level]);

class Boarding {
  Boarding._();

  /// The native splash's ground (flutter_native_splash, LaunchBackground).
  static const splashNavy = Color(0xFF183250);

  // The night: deep at the foot, a little bluer at the head.
  static const nightTop = Color(0xFF0E1A29);
  static const night = Color(0xFF0A131F);
  static const nightFoot = Color(0xFF060B13);

  /// The one light on the stage, behind the object.
  static const spotlight = Color(0xFF1D3552);

  static const heading = Color(0xFFF4F7FB);
  static const ink = Color(0xFFE0E5EC); // --portal-ink
  static const muted = Color(0xFF8E9BAB);
  static const faint = Color(0xFF5E6B7B);
  static const hairline = Color(0x1FE0E9F5);
  static const accent = Color(0xFFA9C8E6); // --portal-accent

  /// The phone's own location blue, toned to the night.
  static const here = Color(0xFF3D8BFF);

  /// The rim of an object on the stage.
  static const slateEdge = Color(0x1AFFFFFF);

  // The boarding pass (flightPass.css).
  static const paper = Color(0xFFFBFAF6);
  static const passInk = Color(0xFF16233A);
  static const passLabel = Color(0xFF8A8D94);
  static const passRule = Color(0xFFE4E1D8);

  /// The portal's content column.
  static const contentWidth = 448.0;

  static const mono = 'Menlo';
  static const monoFallback = <String>['Courier', 'RobotoMono', 'monospace'];

  static const headline = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.9,
    height: 1.12,
    color: heading,
  );

  static const body = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w400,
    height: 1.4,
    letterSpacing: -0.2,
    color: muted,
  );

  /// A small capital caption: the board's NEXT DEPARTURE, the pass's labels.
  static TextStyle caption(
          {Color color = faint, double size = 11, double spacing = 2.2}) =>
      TextStyle(
        fontSize: size,
        fontWeight: FontWeight.w600,
        letterSpacing: spacing,
        height: 1.2,
        color: color,
      );

  static TextStyle monoStyle(double size,
          {Color color = ink,
          FontWeight weight = FontWeight.w600,
          double spacing = 0.6}) =>
      TextStyle(
        fontFamily: mono,
        fontFamilyFallback: monoFallback,
        fontSize: size,
        fontWeight: weight,
        letterSpacing: spacing,
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
}

/// Apple's spring, by damping ratio and response (fluid.ts in the portal):
/// response is how quickly it gets there, not a duration.
SpringDescription foorsaSpring({double damping = 1, double response = 0.4}) {
  final omega = 2 * math.pi / response;
  return SpringDescription(
      mass: 1, stiffness: omega * omega, damping: 2 * damping * omega);
}

/// The portal's one press: in within 100 ms, back on a 240 ms spring.
class Pressable extends StatefulWidget {
  const Pressable(
      {super.key,
      required this.child,
      this.onTap,
      this.scale = 0.97,
      this.onDown});
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onDown;
  final double scale;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press =
      AnimationController.unbounded(vsync: this, value: 1);

  void _to(double target, {required bool down}) {
    if (down) {
      _press.animateTo(target,
          duration: const Duration(milliseconds: 100), curve: Curves.easeOut);
    } else {
      _press.animateWith(SpringSimulation(
          foorsaSpring(damping: 0.72, response: 0.24),
          _press.value,
          target,
          _press.velocity));
    }
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled
          ? (_) {
              widget.onDown?.call();
              _to(widget.scale, down: true);
            }
          : null,
      onTapUp: enabled ? (_) => _to(1, down: false) : null,
      onTapCancel: enabled ? () => _to(1, down: false) : null,
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _press,
        builder: (context, child) =>
            Transform.scale(scale: _press.value, child: child),
        child: widget.child,
      ),
    );
  }
}

/// Seconds since the first frame, for scenes that draw from a clock.
mixin SceneClock<T extends StatefulWidget> on State<T>, TickerProvider {
  final ValueNotifier<double> clock = ValueNotifier<double>(0);
  late final _ticker = createTicker((elapsed) =>
      clock.value = elapsed.inMicroseconds / Duration.microsecondsPerSecond);

  /// Starts the clock unless the student asked for still screens.
  void startClock({required bool still}) {
    if (!still) _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    clock.dispose();
    super.dispose();
  }
}

/// 0 to 1 over [from]–[to], eased in and out.
double ease(double x, double from, double to) {
  final t = ((x - from) / (to - from)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// 0 to 1 over [from]–[to], easing out (fast, then settling).
double easeOut(double x, double from, double to) {
  final t = ((x - from) / (to - from)).clamp(0.0, 1.0);
  return 1 - math.pow(1 - t, 3).toDouble();
}

/// Text broken into lines of even length, as CSS's `text-wrap: balance`
/// does: the same number of lines, never a word left alone on the last one.
class BalancedText extends StatelessWidget {
  const BalancedText(this.text,
      {super.key,
      required this.style,
      this.textAlign = TextAlign.center,
      this.maxLines});
  final String text;
  final TextStyle style;
  final TextAlign textAlign;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = balancedWidth(
        TextSpan(
            text: text, style: DefaultTextStyle.of(context).style.merge(style)),
        constraints.maxWidth,
        MediaQuery.textScalerOf(context),
        Directionality.of(context),
      );
      return Align(
        // Start and end follow the words' direction: an Arabic line starts
        // at the right.
        alignment: switch (textAlign) {
          TextAlign.left => Alignment.topLeft,
          TextAlign.right => Alignment.topRight,
          TextAlign.start => AlignmentDirectional.topStart,
          TextAlign.end => AlignmentDirectional.topEnd,
          _ => Alignment.topCenter,
        },
        widthFactor: 1,
        heightFactor: 1,
        child: SizedBox(
          width: width,
          child: Text(text,
              style: style,
              textAlign: textAlign,
              maxLines: maxLines,
              overflow: maxLines == null ? null : TextOverflow.ellipsis),
        ),
      );
    });
  }
}

/// The narrowest width at which [span] still takes as many lines as it does
/// at [maxWidth].
double balancedWidth(InlineSpan span, double maxWidth, TextScaler scaler,
    TextDirection direction) {
  if (!maxWidth.isFinite) return maxWidth;
  final painter =
      TextPainter(text: span, textDirection: direction, textScaler: scaler);
  int lines(double width) {
    painter.layout(maxWidth: width);
    return painter.computeLineMetrics().length;
  }

  final target = lines(maxWidth);
  if (target <= 1) {
    painter.dispose();
    return maxWidth;
  }
  var low = maxWidth / target, high = maxWidth;
  for (var i = 0; i < 12 && high - low > 1; i++) {
    final mid = (low + high) / 2;
    if (lines(mid) > target) {
      low = mid;
    } else {
      high = mid;
    }
  }
  painter.dispose();
  // A hair of room, so rounding never pushes a word down.
  return math.min(maxWidth, high + 1);
}
