import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/config.dart';
import 'src/crash_reports.dart';
import 'src/device_access.dart';
import 'src/onboarding/onboarding_gate.dart';
import 'src/onboarding/onboarding_sound.dart';
import 'src/onboarding/onboarding_store.dart';
import 'src/student_calls.dart';
import 'src/shell_appearance.dart';
import 'src/shell_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The app's own failures reach the crash board (crash_reports.dart).
  reportUncaughtErrors();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
  ));
  // The theme the student chose, before the first frame: the loading screen
  // opens in it rather than in the phone's. One small file, a few ms.
  final appearance = await ShellAppearanceStore().read();
  // First-time downloaders board through the onboarding; an update does not.
  final firstLaunch = await OnboardingStore().shouldShow();
  // And its sounds, behind the native splash, so the intro's starts with its
  // first frame: the intro is loaded first and the rest load behind it. Never
  // more than a moment; a late intro joins the picture where it has got to.
  final sounds = firstLaunch ? OnboardingSounds() : null;
  if (sounds != null) {
    await sounds
        .prepare()
        .timeout(const Duration(milliseconds: 900), onTimeout: () {});
  }
  // Never what keeps the app on its launch screen (student_calls.dart).
  await startStudentCalls();
  runApp(FoorsaStudentApp(
      appearance: appearance,
      firstLaunch: firstLaunch,
      sounds: sounds));
}

class FoorsaStudentApp extends StatelessWidget {
  const FoorsaStudentApp(
      {super.key,
      this.appearance,
      this.firstLaunch = false,
      this.sounds});

  final ShellAppearance? appearance;

  /// Show the first-launch onboarding over the shell (onboarding_store.dart).
  final bool firstLaunch;

  /// The onboarding's sounds, loaded before its first frame.
  final OnboardingSounds? sounds;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Foorsa Student',
      builder: (context, child) =>
          StudentCallOverlay(child: child ?? const SizedBox.shrink()),
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(AppConfig.brandColorValue)),
      ),
      home: FirstLaunchGate(
        show: firstLaunch,
        sounds: sounds,
        // Android's GPUs draw the glass's blurs from pictures
        // (onboarding/glass.dart).
        bakeGlass: Platform.isAndroid,
        child: DeviceAccess(
          suppressed: firstLaunch,
          child: ShellPage(
            appearance: appearance,
            // After the takeoff, which a platform view's set-up would stall.
            webViewDelay: firstLaunch
                ? FirstLaunchGate.webViewDelay
                : const Duration(milliseconds: 300),
          ),
        ),
      ),
    );
  }
}
