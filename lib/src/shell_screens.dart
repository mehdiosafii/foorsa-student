/// The app's own screens around the portal: the loader it shows from the
/// icon to the portal's first screen, and the one it shows with no connection.
/// Both follow the theme the student chose (shell_appearance.dart).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'config.dart';
import 'onboarding/flight_loader.dart';
import 'web_view_composition.dart';

/// Foorsa's arrow turning into the plane, on the theme's ground.
class ShellLoadingScreen extends StatelessWidget {
  const ShellLoadingScreen({super.key, required this.dark});
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Container(
        color: dark ? const Color(AppConfig.brandColorValue) : Colors.white,
        // Centred where the portal centres its own loader (the web page starts
        // under the status bar), so when it takes over nothing moves.
        child: SafeArea(
          bottom: false,
          child: Center(
            // The app's loading animation, nothing else: Foorsa's arrow
            // turning into the plane and flying off, in a loop
            // (onboarding/flight_loader.dart; the owner, 31 Oct 2026). Android
            // shows the branded logo splash (flutter_native_splash, same
            // #183250 ground) before Flutter's first frame: logo, then the
            // loader.
            child: FlightLoader(size: 64, dark: dark),
          ),
        ),
      ),
    );
  }
}

/// The loading screen over the web view, as the shell shows it: it fades out
/// in 220 ms when the portal is ready ([showing] false), and says so
/// ([onGone]) so the shell can take it away.
///
/// Under the first-launch onboarding ([covered]) it is out of sight for its
/// first seconds, the takeoff included: it is neither drawn nor animated
/// then. Its fade still runs, so a loader the portal let go of meanwhile is
/// gone by the time the onboarding fades onto the sign-in; one still needed
/// is drawn and animated again from that moment.
class ShellLoadingLayer extends StatelessWidget {
  const ShellLoadingLayer({
    super.key,
    required this.showing,
    required this.covered,
    required this.dark,
    required this.onGone,
  });

  final bool showing;
  final bool covered;
  final bool dark;
  final VoidCallback onGone;

  @override
  Widget build(BuildContext context) {
    return CoveredByOnboarding(
      covered: covered,
      child: IgnorePointer(
        ignoring: !showing,
        child: AnimatedOpacity(
          opacity: showing ? 1 : 0,
          // The portal's own loader fades in the same 220 ms.
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          onEnd: () {
            if (!showing) onGone();
          },
          child: TickerMode(
            enabled: !covered,
            child: ShellLoadingScreen(dark: dark),
          ),
        ),
      ),
    );
  }
}

/// No connection: in English like the rest of the app, with the Arabic under
/// it, in the theme the student chose. It retries on its own every 6 s.
class ShellOfflineScreen extends StatelessWidget {
  const ShellOfflineScreen({super.key, required this.onRetry, required this.dark});
  final VoidCallback onRetry;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final ink = dark ? Colors.white : const Color(0xFF14273B);
    final muted = dark ? const Color(0xFFB6C2D6) : const Color(0xFF526474);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: dark
                ? const [Color(0xFF0D1526), Color(0xFF17233F), Color(0xFF1F2F52)]
                : const [Color(0xFFF6F8FB), Color(0xFFEDF1F6), Color(0xFFE3EAF2)],
          ),
        ),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              dark
                  ? 'assets/images/intro_dark.png'
                  : 'assets/images/intro_light.png',
              width: 84,
            ),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              decoration: BoxDecoration(
                color: dark
                    ? Colors.white.withValues(alpha: 0.07)
                    : Colors.white.withValues(alpha: 0.82),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                    color: dark
                        ? Colors.white.withValues(alpha: 0.14)
                        : const Color(0xFFD7DFE8)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: dark
                          ? Colors.white.withValues(alpha: 0.10)
                          : const Color(0xFF224F78).withValues(alpha: 0.085),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.wifi_off_rounded,
                        color: dark ? Colors.white : const Color(0xFF224F78),
                        size: 30),
                  ),
                  const SizedBox(height: 18),
                  Text('No internet connection',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: ink,
                          fontSize: 18,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text('لا يوجد اتصال بالإنترنت',
                      textDirection: TextDirection.rtl,
                      style: TextStyle(color: muted, fontSize: 14)),
                  const SizedBox(height: 14),
                  Text(
                    'Check your Wi-Fi or mobile data.\nThe app reconnects by itself.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: muted, fontSize: 13, height: 1.5),
                  ),
                  const SizedBox(height: 22),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          dark ? Colors.white : const Color(0xFF224F78),
                      foregroundColor:
                          dark ? const Color(0xFF16223D) : Colors.white,
                      minimumSize: const Size(0, 48),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 26, vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Try again',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
