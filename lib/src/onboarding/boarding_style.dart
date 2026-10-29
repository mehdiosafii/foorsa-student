/// The onboarding's look, in the portal's own terms (portal.css and
/// portalMaterials.css in foorsa-reward): its dark theme's ink, muted text,
/// pale steel accent and pearl main button, its glass panels, and the boarding
/// pass's paper and ink (flightPass.css). The onboarding is always the night
/// scene the native splash opens on, so these are the dark values only.
library;

import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import 'lucide.dart';

/// A touch by the shell's texture names (shell_haptics.dart): `press`,
/// `detent`, `land`, `grain` (with a level), `release`, `unfold`, `arrive`.
typedef Feel = void Function(String touch, [double level]);

class Boarding {
  Boarding._();

  /// The native splash's ground (flutter_native_splash, LaunchBackground).
  static const splashNavy = Color(0xFF183250);

  /// The portal's dark page ground.
  static const night = Color(0xFF0C141D);
  static const nightMid = Color(0xFF101C2B);

  static const heading = Color(0xFFF5F8FC);
  static const ink = Color(0xFFE0E5EC); // --portal-ink
  static const muted = Color(0xFFB3BDC8); // --portal-muted
  static const faint = Color(0xFF8D9AAA);
  static const accent = Color(0xFFA9C8E6); // --portal-accent
  static const accentSoft = Color(0x1FA9C8E6); // --portal-accent-soft
  static const done = Color(0xFF6EE7B7); // --portal-mark-done
  static const doneSoft = Color(0x216EE7B7);
  static const wait = Color(0xFFFCD34D); // --portal-tone-wait
  static const recording = Color(0xFFE0413B); // the live chat's recording dot

  // Glass (portalMaterials.css, dark).
  static const glassFill = Color(0x7A1B2A38);
  static const glassDeep = Color(0xC2162331);
  static const glassEdge = Color(0x2EDCEEFF);
  static const glassHighlight = Color(0x5CE7F6FF);
  static const glassShadow = Color(0x66000510);

  // The pearl main button on dark (--portal-primary-fill).
  static const pearlTop = Color(0xFFF4F9FD);
  static const pearlBottom = Color(0xFFDBE8F3);
  static const pearlInk = Color(0xFF132A40);

  // The live chat, dark (liveChat.css).
  static const chatTeam = Color(0xFF1C2733);
  static const chatTeamInk = Color(0xFFE6EBF1);
  static const chatMineTop = Color(0xFF3A6896);
  static const chatMineBottom = Color(0xFF2A5079);

  // The boarding pass (flightPass.css).
  static const paper = Color(0xFFFCFBF7);
  static const paperShade = Color(0xFFF1EEE5);
  static const passInk = Color(0xFF1B1F2E);
  static const passSub = Color(0xFF697080);
  static const passLabel = Color(0xFF7B7E85);
  static const gold = Color(0xFFA09275);
  static const goldLight = Color(0xFFD1C4A8);
  static const passHeaderTop = Color(0xFF22283D);
  static const passHeaderBottom = Color(0xFF171A27);

  /// The portal's content column.
  static const contentWidth = 448.0;

  static const mono = 'Menlo';
  static const monoFallback = <String>['Courier', 'RobotoMono', 'monospace'];

  static TextStyle eyebrow = const TextStyle(
    fontSize: 11.5,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.5,
    height: 1.3,
    color: muted,
  );

  static TextStyle headline = const TextStyle(
    fontSize: 30,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.7,
    height: 1.12,
    color: heading,
  );

  static TextStyle arabic = const TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w500,
    height: 1.5,
    color: muted,
  );

  static TextStyle body = const TextStyle(
    fontSize: 15.5,
    height: 1.45,
    color: muted,
    letterSpacing: -0.1,
  );

  static TextStyle footnote = const TextStyle(
    fontSize: 12.5,
    height: 1.4,
    color: faint,
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

/// The portal's glass panel on dark: a sheen over a translucent fill, a
/// hairline rim, a top highlight and a soft drop, no blur (phones never blur
/// a whole card, portalMaterials.css).
class NightGlass extends StatelessWidget {
  const NightGlass({
    super.key,
    required this.child,
    this.radius = 26,
    this.padding = EdgeInsets.zero,
    this.deep = false,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final bool deep;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        color: deep ? Boarding.glassDeep : Boarding.glassFill,
        boxShadow: const [
          BoxShadow(
              color: Boarding.glassShadow,
              blurRadius: 24,
              offset: Offset(0, 8),
              spreadRadius: -14),
        ],
      ),
      child: Stack(children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: shape,
              border: Border.all(color: Boarding.glassEdge),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0x29CFE7FC),
                  Color(0x0495B9D8),
                  Color(0x1298C3E4)
                ],
                stops: [0, 0.47, 1],
              ),
            ),
          ),
        ),
        // The top highlight, an inset hairline of light.
        Positioned(
          left: radius * 0.7,
          right: radius * 0.7,
          top: 0.5,
          height: 1,
          child: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                Color(0x00E7F6FF),
                Boarding.glassHighlight,
                Color(0x00E7F6FF),
              ]),
            ),
          ),
        ),
        Padding(padding: padding, child: child),
      ]),
    );
  }
}

/// The portal's one press: in within 100 ms, back on a 240 ms spring.
class Pressable extends StatefulWidget {
  const Pressable(
      {super.key,
      required this.child,
      this.onTap,
      this.scale = 0.98,
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

/// The main action on dark: a pearl pill with navy ink (the journey's
/// "My universities" button), its label crossing over as the steps change.
class PearlButton extends StatelessWidget {
  const PearlButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.onDown,
    this.busy = false,
    this.trailing = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final VoidCallback? onDown;
  final bool busy;
  final bool trailing;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: Pressable(
        onTap: enabled ? onPressed : null,
        onDown: onDown,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: enabled ? 1 : 0.72,
          child: Container(
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Boarding.pearlTop, Boarding.pearlBottom],
              ),
              border: Border.all(color: const Color(0xC7FFFFFF)),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x290A1E34),
                    blurRadius: 2,
                    offset: Offset(0, 1)),
                BoxShadow(
                    color: Color(0x800A1E34),
                    blurRadius: 18,
                    offset: Offset(0, 8),
                    spreadRadius: -10),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(width: 28),
                Expanded(
                  // The old word leaves before the new one comes, so the two
                  // never sit on top of each other.
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 320),
                    switchInCurve:
                        const Interval(0.4, 1, curve: Curves.easeOutCubic),
                    switchOutCurve:
                        const Interval(0.6, 1, curve: Curves.easeInCubic),
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween(
                                begin: const Offset(0, 0.35), end: Offset.zero)
                            .animate(animation),
                        child: child,
                      ),
                    ),
                    child: Text(
                      label,
                      key: ValueKey(label),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                        color: Boarding.pearlInk,
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 28,
                  child: trailing
                      ? const Align(
                          alignment: Alignment.centerLeft,
                          child: Lucide(LucideIcons.chevronRight,
                              size: 20,
                              color: Boarding.pearlInk,
                              strokeWidth: 2.2),
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A small status line: what the student just chose, in words, never colour
/// alone (the portal's status words, portal-tone-done).
class OutcomeChip extends StatelessWidget {
  const OutcomeChip({super.key, required this.on, required this.label});
  final bool on;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 7, 14, 7),
      decoration: BoxDecoration(
        color: on ? Boarding.doneSoft : const Color(0x14FFFFFF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
            color: on ? const Color(0x406EE7B7) : const Color(0x24FFFFFF)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on ? Boarding.done : const Color(0x33FFFFFF),
          ),
          alignment: Alignment.center,
          child: on
              ? const Lucide(LucideIcons.check,
                  size: 13, color: Color(0xFF06281A), strokeWidth: 3.2)
              : Container(width: 8, height: 2, color: Boarding.ink),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: on ? Boarding.done : Boarding.ink,
              )),
        ),
      ]),
    );
  }
}
