import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/config.dart';
import 'src/device_access.dart';
import 'src/onboarding/onboarding_gate.dart';
import 'src/onboarding/onboarding_store.dart';
import 'src/onboarding/splash_logo.dart';
import 'src/student_calls.dart';
import 'src/shell_appearance.dart';
import 'src/shell_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
  // Its first frame is the launch screen's: the roundel is decoded before it.
  final splash = firstLaunch ? await decodeSplashLogo() : null;
  await StudentCalls.instance.start();
  runApp(FoorsaStudentApp(
      appearance: appearance, firstLaunch: firstLaunch, splash: splash));
}

class FoorsaStudentApp extends StatelessWidget {
  const FoorsaStudentApp(
      {super.key, this.appearance, this.firstLaunch = false, this.splash});

  final ShellAppearance? appearance;

  /// Show the first-launch onboarding over the shell (onboarding_store.dart).
  final bool firstLaunch;

  /// The splash's roundel, decoded, for the onboarding's first frame.
  final ui.Image? splash;

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
        splash: splash,
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
