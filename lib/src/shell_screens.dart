/// The app's own screens around the portal: the loader it shows from the
/// icon to the portal's first screen, and the one it shows with no connection.
/// Both follow the theme the student chose (shell_appearance.dart).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_language.dart';
import 'config.dart';
import 'onboarding/flight_loader.dart';
import 'onboarding/glass.dart';
import 'web_view_composition.dart';

/// Foorsa's arrow turning into the plane, on the theme's ground.
class ShellLoadingScreen extends StatelessWidget {
  const ShellLoadingScreen({super.key, required this.dark, this.resting = false});
  final bool dark;

  /// The arrow alone, not yet moving ([FlightLoader.resting]).
  final bool resting;

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
            child: FlightLoader(size: 64, dark: dark, resting: resting),
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
///
/// It rests on its first picture while the web view is made ([resting],
/// boot_loader_gate.dart).
///
/// On Android its glass is drawn from pictures ([bakeGlass]). The loader is
/// over the web view from the app's icon to the portal's first screen, and
/// while an Android web view is in the window Flutter rasters every frame on
/// the phone's main thread, the one the page is loading on
/// (web_view_composition.dart). Each frame of the loop asked for two to six
/// blurs Impeller can only draw through an offscreen picture and two passes:
/// the arrow's and the plane's are now made once, as the onboarding's are
/// (GlassBake in onboarding/glass.dart), and let go with the loader. What
/// changes shape or fades from frame to frame (the arrow becoming the plane,
/// the next arrow coming up) is drawn as before, and so is a blur under a
/// pixel and a half wide, which on a 720p phone is the light along their
/// bevels (docs/shell-frame-cost.md has the counts).
class ShellLoadingLayer extends StatefulWidget {
  const ShellLoadingLayer({
    super.key,
    required this.showing,
    required this.covered,
    required this.dark,
    required this.onGone,
    this.resting = false,
    this.bakeGlass = false,
  });

  final bool showing;
  final bool covered;
  final bool dark;
  final VoidCallback onGone;
  final bool resting;
  final bool bakeGlass;

  @override
  State<ShellLoadingLayer> createState() => _ShellLoadingLayerState();
}

class _ShellLoadingLayerState extends State<ShellLoadingLayer> {
  bool _baking = false;

  void _bake(bool on) {
    if (on == _baking) return;
    _baking = on;
    if (on) {
      GlassBake.hold();
    } else {
      GlassBake.release();
    }
  }

  @override
  void initState() {
    super.initState();
    _bake(widget.bakeGlass);
  }

  @override
  void didUpdateWidget(ShellLoadingLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _bake(widget.bakeGlass);
  }

  @override
  void dispose() {
    _bake(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showing = widget.showing;
    return CoveredByOnboarding(
      covered: widget.covered,
      child: IgnorePointer(
        ignoring: !showing,
        child: AnimatedOpacity(
          opacity: showing ? 1 : 0,
          // The portal's own loader fades in the same 220 ms.
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          onEnd: () {
            if (!widget.showing) widget.onGone();
          },
          child: TickerMode(
            enabled: !widget.covered,
            child: ShellLoadingScreen(
                dark: widget.dark, resting: widget.resting),
          ),
        ),
      ),
    );
  }
}

/// What the offline screen says. In English it keeps the Arabic line under
/// its title, as it always had; in French and in Arabic it says it once, in
/// the student's language.
const offlineTitle = Words('No internet connection',
    'Pas de connexion Internet', 'لا يوجد اتصال بالإنترنت');
const offlineDetail = Words(
    'Check your Wi-Fi or mobile data.\nThe app reconnects by itself.',
    'Vérifiez votre Wi-Fi ou vos données mobiles.\n'
        'L’application se reconnecte toute seule.',
    'يرجى التحقق من شبكة Wi-Fi أو من بيانات الهاتف.\n'
        'سيعاود التطبيق الاتصال تلقائيًا.');
const offlineRetry = Words('Try again', 'Réessayer', 'إعادة المحاولة');

/// No connection, in the student's language (in English with the Arabic
/// under it), in the theme the student chose. It retries on its own every
/// 6 s.
class ShellOfflineScreen extends StatelessWidget {
  const ShellOfflineScreen(
      {super.key, required this.onRetry, required this.dark, this.language});
  final VoidCallback onRetry;
  final bool dark;

  /// The student's language; the app's (AppLanguageScope) when not given.
  final AppLanguage? language;

  @override
  Widget build(BuildContext context) {
    final language = this.language ?? AppLanguageScope.of(context);
    return Directionality(
      textDirection: language.direction,
      child: _screen(context, language),
    );
  }

  Widget _screen(BuildContext context, AppLanguage language) {
    final ink = dark ? Colors.white : const Color(0xFF14273B);
    final muted = dark ? const Color(0xFFB6C2D6) : const Color(0xFF526474);
    // The screen is as tall as what it says: on a phone on its side, or with
    // the phone's text set large, that is more than the phone has, and it
    // was cut off at both ends, Try again included (the owner's stress test,
    // 12 Nov 2026). It scrolls then. The room it leaves for the notch and the
    // home bar is the same on both sides, so a screen that fits stays
    // centred exactly where it always was.
    final insets = MediaQuery.viewPaddingOf(context);
    final across = math.max(28.0, math.max(insets.left, insets.right));
    final down = math.max(28.0, math.max(insets.top, insets.bottom));
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
        child: LayoutBuilder(builder: (context, box) {
          // A phone on its side has no room for the mark above the card:
          // the card alone, drawn closer, keeps Try again on the screen.
          final low = box.maxHeight < _lowScreen;
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  minWidth: box.maxWidth, minHeight: box.maxHeight),
              child: Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: across,
                    vertical: low
                        ? math.max(12.0, math.max(insets.top, insets.bottom))
                        : down),
                child: Center(child: _card(language, ink, muted, low: low)),
              ),
            ),
          );
        }),
      ),
    );
  }

  /// Under this height the screen is a phone on its side.
  static const _lowScreen = 480.0;

  Widget _card(AppLanguage language, Color ink, Color muted,
      {required bool low}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!low) ...[
          Image.asset(
            dark
                ? 'assets/images/intro_dark.png'
                : 'assets/images/intro_light.png',
            width: 84,
          ),
          const SizedBox(height: 28),
        ],
        Container(
          padding: low
              ? const EdgeInsets.fromLTRB(24, 16, 24, 16)
              : const EdgeInsets.fromLTRB(24, 28, 24, 24),
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
                width: low ? 44 : 64,
                height: low ? 44 : 64,
                decoration: BoxDecoration(
                  color: dark
                      ? Colors.white.withValues(alpha: 0.10)
                      : const Color(0xFF224F78).withValues(alpha: 0.085),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.wifi_off_rounded,
                    color: dark ? Colors.white : const Color(0xFF224F78),
                    size: low ? 22 : 30),
              ),
              SizedBox(height: low ? 10 : 18),
              Text(offlineTitle.of(language),
                  textAlign: TextAlign.center,
                  style: scriptStyle(
                      TextStyle(
                          color: ink,
                          fontSize: 18,
                          fontWeight: FontWeight.w700),
                      language)),
              if (language == AppLanguage.en) ...[
                const SizedBox(height: 6),
                Text(offlineTitle.ar,
                    textDirection: TextDirection.rtl,
                    style: TextStyle(color: muted, fontSize: 14)),
              ],
              SizedBox(height: low ? 8 : 14),
              Text(
                offlineDetail.of(language),
                textAlign: TextAlign.center,
                style: TextStyle(color: muted, fontSize: 13, height: 1.5),
              ),
              SizedBox(height: low ? 12 : 22),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor:
                      dark ? Colors.white : const Color(0xFF224F78),
                  foregroundColor:
                      dark ? const Color(0xFF16223D) : Colors.white,
                  minimumSize: const Size(0, 48),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 26, vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(offlineRetry.of(language),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
