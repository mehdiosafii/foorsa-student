/// The launch screen's roundel, decoded before the first frame, so the
/// onboarding opens on exactly what the native splash shows: an image asset
/// decodes a frame or two later, and the roundel would blink out between the
/// two.
library;

import 'dart:ui' as ui;

import 'package:flutter/services.dart';

const splashLogoAsset = 'assets/images/splash_logo.png';

/// Drawn at 256 pt, as LaunchScreen.storyboard draws LaunchImage.
const splashLogoSide = 256.0;

/// The roundel at the screen's resolution; null if it cannot be read, and the
/// onboarding then loads the asset itself.
Future<ui.Image?> decodeSplashLogo() async {
  try {
    final views = ui.PlatformDispatcher.instance.views;
    final ratio = views.isEmpty ? 3.0 : views.first.devicePixelRatio;
    final data = await rootBundle.load(splashLogoAsset);
    final codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(),
      targetWidth: (splashLogoSide * ratio).round(),
    );
    return (await codec.getNextFrame()).image;
  } catch (_) {
    return null;
  }
}
