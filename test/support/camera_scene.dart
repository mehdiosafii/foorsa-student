/// Synthetic camera frames for the guided scanner's tests: a document on a
/// table as the Android camera's image stream hands it over (a landscape YUV
/// buffer of a phone held upright), with sensor noise and a hand's tremor.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:foorsa_student/src/guided_scanner/camera_luma.dart';

/// What the student points the camera at, in the upright visible preview's
/// normalized coordinates (0..1 across, 0..1 down).
class CameraScene {
  const CameraScene({
    required this.page,
    this.tiltDegrees = 0,
    this.paper = 225,
    this.ink = 40,
    this.background = 60,
    this.backgroundTexture = 0,
    this.text = true,
    this.foldAt,
    this.foldShade = 0,
    this.shadow = 0,
    this.shade,
    this.shadeDepth = 0.5,
  });

  final Rect page;
  final double tiltDegrees;
  final int paper;
  final int ink;
  final int background;

  /// Amplitude of a wood-like grain on the table.
  final int backgroundTexture;
  final bool text;

  /// A passport booklet's fold: the share of the page's height where it
  /// runs, and how much darker it is.
  final double? foldAt;
  final int foldShade;

  /// How much a soft shadow darkens the page's left half (0..1).
  final double shadow;

  /// A hand's or a phone's shadow: the part of the page it covers, in the
  /// page's own normalized coordinates, and how much darker it is there.
  final Rect? shade;
  final double shadeDepth;
}

class SensorFrames {
  SensorFrames(this.scene, {
    this.sensorWidth = 1920,
    this.sensorHeight = 1080,
    this.viewportAspect = 0.49,
    this.noise = 3,
    this.tremor = 0,
    int seed = 7,
  }) : _random = math.Random(seed) {
    _render();
    _noise = Int8List(1 << 22);
    for (var i = 0; i < _noise.length; i++) {
      // Box-Muller, clamped to the int8 range.
      final u = math.max(1e-9, _random.nextDouble()), v = _random.nextDouble();
      final g = math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * v);
      _noise[i] = (g * noise).round().clamp(-127, 127);
    }
  }

  final CameraScene scene;
  final int sensorWidth;
  final int sensorHeight;
  final double viewportAspect;
  final double noise;

  /// Standard deviation of the hand's shake, in sensor pixels per frame.
  final double tremor;
  final math.Random _random;
  late final Uint8List _clean;
  late final Int8List _noise;
  int _frame = 0;

  /// The upright full-frame point (0..1) of a viewport point.
  Offset _fullFromViewport(double vx, double vy) {
    final portraitWidth = sensorHeight, portraitHeight = sensorWidth;
    final sourceAspect = portraitWidth / portraitHeight;
    var cropLeft = 0.0, cropTop = 0.0, cropWidth = 1.0, cropHeight = 1.0;
    if (sourceAspect > viewportAspect) {
      cropWidth = viewportAspect / sourceAspect;
      cropLeft = (1 - cropWidth) / 2;
    } else {
      cropHeight = sourceAspect / viewportAspect;
      cropTop = (1 - cropHeight) / 2;
    }
    return Offset(cropLeft + vx * cropWidth, cropTop + vy * cropHeight);
  }

  void _render() {
    final w = sensorWidth, h = sensorHeight;
    final out = Uint8List(w * h);
    final page = scene.page;
    // Work in a metric frame where the viewport's height is 1 and its width
    // is its aspect, so a tilt keeps right angles.
    final topLeft = _fullFromViewport(page.left, page.top);
    final bottomRight = _fullFromViewport(page.right, page.bottom);
    final portraitAspect = sensorHeight / sensorWidth;
    // In full-frame metric units (height 1, width portraitAspect).
    final left = topLeft.dx * portraitAspect, right = bottomRight.dx * portraitAspect;
    final top = topLeft.dy, bottom = bottomRight.dy;
    final cx = (left + right) / 2, cy = (top + bottom) / 2;
    final angle = scene.tiltDegrees * math.pi / 180;
    final cosA = math.cos(-angle), sinA = math.sin(-angle);
    final pageWidth = right - left, pageHeight = bottom - top;
    final linePitch = pageHeight / 46;
    final charPitch = pageWidth / 95;
    final wordSeeds = List.generate(64, (i) => math.Random(i * 31 + 5));
    final wordBreaks = [
      for (final r in wordSeeds) [for (var k = 0; k < 40; k++) r.nextDouble()],
    ];
    for (var sy = 0; sy < h; sy++) {
      final ux = (1 - (sy + 0.5) / h) * portraitAspect;
      for (var sx = 0; sx < w; sx++) {
        final uy = (sx + 0.5) / w;
        // Into the page's own frame.
        final dx = ux - cx, dy = uy - cy;
        final px = cx + dx * cosA - dy * sinA, py = cy + dx * sinA + dy * cosA;
        int value;
        if (px >= left && px <= right && py >= top && py <= bottom) {
          final nx = (px - left) / pageWidth, ny = (py - top) / pageHeight;
          value = scene.paper;
          if (scene.text && nx > 0.08 && nx < 0.92 && ny > 0.07 && ny < 0.93) {
            final line = ((py - top) / linePitch).floor();
            final within = ((py - top) / linePitch) - line;
            if (line % 6 != 5 && within > 0.3 && within < 0.72) {
              // Words of a few characters, then a space.
              final breaks = wordBreaks[line % wordBreaks.length];
              final pos = nx * 40;
              final word = pos.floor().clamp(0, 39);
              final inWord = (pos - word) < 0.55 + 0.4 * breaks[word];
              final glyph = ((px - left) / charPitch);
              if (inWord && (glyph - glyph.floor()) < 0.45) value = scene.ink;
            }
          }
          if (scene.foldAt != null) {
            final fold = (ny - scene.foldAt!).abs();
            if (fold < 0.012) value -= scene.foldShade;
          }
          if (scene.shadow > 0 && nx < 0.5) {
            value = (value * (1 - scene.shadow * (1 - nx * 2))).round();
          }
          if (scene.shade?.contains(Offset(nx, ny)) == true) {
            value = (value * (1 - scene.shadeDepth)).round();
          }
        } else {
          value = scene.background;
          if (scene.backgroundTexture > 0) {
            value += (math.sin(ux * 90 + math.sin(uy * 7) * 2) * scene.backgroundTexture).round();
          }
        }
        out[sy * w + sx] = value.clamp(0, 255);
      }
    }
    _clean = out;
  }

  /// The next frame's Y plane, landscape, row by row.
  Uint8List nextLuma() {
    final w = sensorWidth, h = sensorHeight;
    final shiftX = tremor == 0 ? 0 : (_gaussian() * tremor).round();
    final shiftY = tremor == 0 ? 0 : (_gaussian() * tremor).round();
    final y = Uint8List(w * h);
    final offset = (_frame * 7919 * 13) % (_noise.length - w * h - 1);
    for (var row = 0; row < h; row++) {
      final sourceRow = (row - shiftY).clamp(0, h - 1) * w;
      final target = row * w;
      for (var column = 0; column < w; column++) {
        final source = (column - shiftX).clamp(0, w - 1);
        y[target + column] = (_clean[sourceRow + source] + _noise[offset + target + column]).clamp(0, 255);
      }
    }
    _frame++;
    return y;
  }

  /// The next frame's luminance plane, as the scanner reads it.
  ScanLumaPlane nextPlane() => ScanLumaPlane(
        bytes: nextLuma(), width: sensorWidth, height: sensorHeight, rowStride: sensorWidth);

  /// The page's printed lines, in the upright view's normalized coordinates,
  /// as boxes (left, top, right, bottom): what a text reader can find.
  List<Rect> textLines() {
    if (!scene.text) return const [];
    final page = scene.page;
    final out = <Rect>[];
    final angle = scene.tiltDegrees * math.pi / 180;
    // Rotation about the page's centre in a metric frame (height 1, width
    // the viewport's aspect), back to normalized coordinates.
    Offset turn(double x, double y) {
      final cx = page.center.dx * viewportAspect, cy = page.center.dy;
      final mx = x * viewportAspect - cx, my = y - cy;
      final rx = cx + mx * math.cos(angle) - my * math.sin(angle);
      final ry = cy + mx * math.sin(angle) + my * math.cos(angle);
      return Offset(rx / viewportAspect, ry);
    }
    final pitch = page.height / 46;
    for (var line = 0; line < 46; line++) {
      if (line % 6 == 5) continue;
      final top = page.top + (line + 0.3) * pitch, bottom = page.top + (line + 0.72) * pitch;
      if ((top - page.top) / page.height < 0.07 || (bottom - page.top) / page.height > 0.93) continue;
      final left = page.left + page.width * 0.08, right = page.left + page.width * 0.92;
      final corners = [turn(left, top), turn(right, top), turn(right, bottom), turn(left, bottom)];
      final xs = corners.map((c) => c.dx), ys = corners.map((c) => c.dy);
      out.add(Rect.fromLTRB(xs.reduce(math.min), ys.reduce(math.min), xs.reduce(math.max), ys.reduce(math.max)));
    }
    return out;
  }

  /// The next frame of the image stream, as camera_android_camerax hands it
  /// over (YUV_420_888, Y plane first).
  CameraImage next() {
    final w = sensorWidth, h = sensorHeight;
    final y = nextLuma();
    final chroma = Uint8List(w * h ~/ 2)..fillRange(0, w * h ~/ 2, 128);
    // ignore: deprecated_member_use
    return CameraImage.fromPlatformData({
      'format': 35,
      'width': w,
      'height': h,
      'planes': [
        {'bytes': y, 'bytesPerRow': w, 'bytesPerPixel': 1},
        {'bytes': chroma, 'bytesPerRow': w, 'bytesPerPixel': 2},
        {'bytes': chroma, 'bytesPerRow': w, 'bytesPerPixel': 2},
      ],
    });
  }

  double _gaussian() {
    final u = math.max(1e-9, _random.nextDouble()), v = _random.nextDouble();
    return math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * v);
  }
}
