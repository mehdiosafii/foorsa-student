// Renders the launch images from the onboarding's own painter, so the native
// splash and the onboarding's first frame are the same picture: Foorsa's
// arrow alone, in pearl glass, 100 pt tall in the middle of the screen.
//
// iOS and Android before 12 draw the image at its own size: a 256 pt box.
// Android 12's splash shows its icon in a 288 dp box, so its image is drawn
// in one, the arrow the same 100 dp.
//
//   flutter test scripts/onboarding_splash/render_splash_test.dart
//   dart run flutter_native_splash:create
//
// Not part of `flutter test`: it writes assets.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/onboarding/glass_arrow.dart';

/// The source is drawn at 4x (xxxhdpi): flutter_native_splash scales it down.
const _ratio = 4.0;

Future<void> _render(String name, double box) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(_ratio);
  canvas.translate(box / 2, box / 2);
  paintGlassArrow(canvas, height: splashArrowHeight);
  final size = (box * _ratio).round();
  final image = await recorder.endRecording().toImage(size, size);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  File('assets/images/$name').writeAsBytesSync(png!.buffer.asUint8List());
}

void main() {
  testWidgets('renders the launch images', (tester) async {
    await tester.runAsync(() async {
      // LaunchScreen.storyboard, and launch_background.xml before Android 12.
      await _render('splash_logo.png', 256);
      // Android 12's splash icon, without an icon background.
      await _render('splash_logo_a12.png', 288);
    });
  });
}
