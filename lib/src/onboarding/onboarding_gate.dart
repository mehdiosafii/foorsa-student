/// Puts the first-launch onboarding over the shell, once, and takes it away
/// for good when the student boards (onboarding_store.dart decides who sees
/// it). The shell underneath keeps loading the portal the whole time.
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../portal_handover.dart';
import '../shell_haptics.dart';
import 'onboarding_config.dart';
import 'onboarding_flow.dart';
import 'onboarding_page.dart';
import 'onboarding_permissions.dart';
import 'onboarding_sound.dart';
import 'onboarding_store.dart';

/// Whether the onboarding is over the shell: the shell then leaves the back
/// button and the status bar to it.
class OnboardingScope extends InheritedWidget {
  const OnboardingScope(
      {super.key, required this.active, required super.child});
  final bool active;

  static bool activeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<OnboardingScope>()?.active ??
      false;

  /// The same, read once without subscribing: for callbacks outside build.
  static bool isActive(BuildContext context) =>
      context.getInheritedWidgetOfExactType<OnboardingScope>()?.active ?? false;

  @override
  bool updateShouldNotify(OnboardingScope old) => old.active != active;
}

class FirstLaunchGate extends StatefulWidget {
  const FirstLaunchGate({
    super.key,
    required this.show,
    required this.child,
    this.store,
    this.permissions = const SystemBoardingPermissions(),
    this.haptics,
    this.asksToTrack = OnboardingConfig.asksToTrack,
    this.splash,
    this.sounds,
  });

  /// When the shell may make its WebView on a first launch: after the
  /// takeoff (takeoff_intro.dart), which a platform view's set-up would
  /// stall. The portal still has the whole onboarding to load.
  static const webViewDelay = Duration(milliseconds: 3600);

  /// The launch screen's roundel, decoded before the first frame.
  final ui.Image? splash;

  /// Its sounds; silent when none are given (tests).
  final OnboardingSounds? sounds;

  /// Decided before the first frame (OnboardingStore.shouldShow).
  final bool show;
  final Widget child;
  final OnboardingStore? store;
  final BoardingPermissions permissions;
  final ShellHaptics? haptics;
  final bool asksToTrack;

  @override
  State<FirstLaunchGate> createState() => _FirstLaunchGateState();
}

class _FirstLaunchGateState extends State<FirstLaunchGate> {
  late bool _showing = widget.show;
  final GlobalKey<FirstLaunchOnboardingState> _onboarding =
      GlobalKey<FirstLaunchOnboardingState>();
  late final ShellHaptics _haptics = widget.haptics ?? ShellHaptics();

  void _finish() {
    (widget.store ?? OnboardingStore()).markDone();
    widget.sounds?.release();
    if (mounted) setState(() => _showing = false);
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingScope(
      active: _showing,
      child: Stack(fit: StackFit.expand, children: [
        widget.child,
        if (_showing)
          PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) _onboarding.currentState?.back();
            },
            child: FirstLaunchOnboarding(
              key: _onboarding,
              permissions: widget.permissions,
              feel: (touch, [level = 1]) => _haptics.play(touch, level),
              sounds: widget.sounds ?? const SilentSounds(),
              findMark: PortalHandover.instance.markRect,
              onBoarded: PortalHandover.instance.boarded,
              onFinished: _finish,
              isIOS: defaultTargetPlatform == TargetPlatform.iOS,
              asksToTrack: widget.asksToTrack,
              splash: widget.splash,
            ),
          ),
      ]),
    );
  }
}
