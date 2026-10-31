// Renders the loader's loop as still frames, both themes, for checking by eye:
//
//   flutter test scripts/loader_outline/render_frames_test.dart
//
// Writes build/loader_frames/<theme>-<ms>.png. Not part of `flutter test`.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/onboarding/flight_loader.dart';

Future<void> _frame(bool dark, double seconds, {bool calm = false}) async {
  const size = 64.0, ratio = 3.0;
  final box = FlightLoader.boxFor(size);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(ratio);
  canvas.drawRect(Rect.fromLTWH(0, 0, box, box),
      Paint()..color = dark ? const Color(0xFF183250) : const Color(0xFFFFFFFF));
  final loop = calm ? flightLoaderCalmSeconds : flightLoaderSeconds;
  final clock = AlwaysStoppedAnimation<double>(seconds / loop);
  FlightLoaderPainter(clock, size: size, dark: dark, calm: calm)
      .paint(canvas, Size(box, box));
  final image = await recorder.endRecording().toImage((box * ratio).round(), (box * ratio).round());
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  final name = '${dark ? 'dark' : 'light'}${calm ? '-calm' : ''}-${(seconds * 1000).round().toString().padLeft(4, '0')}';
  File('build/loader_frames/$name.png')
    ..createSync(recursive: true)
    ..writeAsBytesSync(png!.buffer.asUint8List());
}

void main() {
  testWidgets('renders the loader frames', (tester) async {
    await tester.runAsync(() async {
      for (final dark in [true, false]) {
        for (var t = 0.0; t < flightLoaderSeconds; t += 0.2) {
          await _frame(dark, t);
        }
        await _frame(dark, 3.2, calm: true);
      }
    });
  });
}
