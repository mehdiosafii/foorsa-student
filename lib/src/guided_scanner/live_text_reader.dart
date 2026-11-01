/// Android's live text reading for the guided scanner.
///
/// The luminance of the page the analyzer found, cropped with a margin from
/// the camera's Y plane, goes to ML Kit's bundled Latin model through the
/// foorsa/live_text channel (MainActivity, LiveTextReader.kt). The model is
/// part of the app, so it reads offline and in China; nothing is downloaded,
/// and what it reads goes back to Dart and nowhere else.
library;

import 'dart:math' as math;

import 'package:flutter/services.dart';

import 'scan_text_reading.dart';

/// Where one read's pixels come from in the camera buffer, and how what was
/// read maps back onto the page the analyzer found.
class LiveTextCrop {
  const LiveTextCrop._({
    required this.x0,
    required this.y0,
    required this.width,
    required this.height,
    required this.rotation,
    required this.quarterTurns,
    required this.page,
  });

  /// The page's outline in `viewport` space (the luma analyzer's normalized
  /// preview, cropped to the viewport as camera_luma.dart crops it), widened
  /// by [ScanTextGeometry.cropExpansion] about its middle, in sensor pixels.
  /// Null when the crop would be too small to read.
  ///
  /// [sensorOrientation] is how the camera's buffer sits against the upright
  /// preview, as camera_luma.dart reads it: 90 for nearly every back camera
  /// (the buffer is the upright image turned a quarter counterclockwise), 270
  /// for the few mounted the other way round.
  static LiveTextCrop? forPage(
    Rect bounds, {
    required int sensorWidth,
    required int sensorHeight,
    double? viewportAspect,
    ScanTextTurnPolicy turns = const ScanTextTurnPolicy.fixed(0),
    int sensorOrientation = 90,
  }) {
    if (sensorWidth < 32 || sensorHeight < 32 || bounds.width <= 0 || bounds.height <= 0) return null;
    final landscape = sensorWidth > sensorHeight;
    final portraitWidth = landscape ? sensorHeight : sensorWidth;
    final portraitHeight = landscape ? sensorWidth : sensorHeight;
    final sourceAspect = portraitWidth / portraitHeight;
    var cropLeft = 0.0, cropTop = 0.0, cropWidth = 1.0, cropHeight = 1.0;
    if (viewportAspect != null && viewportAspect > 0 && viewportAspect.isFinite) {
      if (sourceAspect > viewportAspect) {
        cropWidth = viewportAspect / sourceAspect;
        cropLeft = (1 - cropWidth) / 2;
      } else {
        cropHeight = sourceAspect / viewportAspect;
        cropTop = (1 - cropHeight) / 2;
      }
    }
    // Upright, normalized over the whole camera image, y down.
    final left = cropLeft + bounds.left * cropWidth, right = cropLeft + bounds.right * cropWidth;
    final top = cropTop + bounds.top * cropHeight, bottom = cropTop + bounds.bottom * cropHeight;
    final centerX = (left + right) / 2, centerY = (top + bottom) / 2;
    const grow = 1 + ScanTextGeometry.cropExpansion;
    double clamp(double value) => value.clamp(0.0, 1.0);
    final upLeft = clamp(centerX - (right - left) / 2 * grow), upRight = clamp(centerX + (right - left) / 2 * grow);
    final upTop = clamp(centerY - (bottom - top) / 2 * grow), upBottom = clamp(centerY + (bottom - top) / 2 * grow);
    // In sensor pixels: a landscape buffer is the upright image turned a
    // quarter counterclockwise (camera_luma.dart reads it the same way), or
    // clockwise on a camera mounted the other way round.
    final turnedBack = landscape && sensorOrientation == 270;
    final double sx0, sx1, sy0, sy1;
    if (turnedBack) {
      sx0 = (1 - upBottom) * sensorWidth;
      sx1 = (1 - upTop) * sensorWidth;
      sy0 = upLeft * sensorHeight;
      sy1 = upRight * sensorHeight;
    } else if (landscape) {
      sx0 = upTop * sensorWidth;
      sx1 = upBottom * sensorWidth;
      sy0 = (1 - upRight) * sensorHeight;
      sy1 = (1 - upLeft) * sensorHeight;
    } else {
      sx0 = upLeft * sensorWidth;
      sx1 = upRight * sensorWidth;
      sy0 = upTop * sensorHeight;
      sy1 = upBottom * sensorHeight;
    }
    // NV21 halves the chroma both ways, so the crop starts and ends even.
    final x0 = (sx0 / 2).floor() * 2, y0 = (sy0 / 2).floor() * 2;
    final x1 = math.min((sx1 / 2).ceil() * 2, sensorWidth - sensorWidth % 2);
    final y1 = math.min((sy1 / 2).ceil() * 2, sensorHeight - sensorHeight % 2);
    final width = x1 - x0, height = y1 - y0;
    if (width < 32 || height < 32) return null;
    // The crop actually taken, back in upright normalized terms.
    final double cropUpLeft, cropUpRight, cropUpTop, cropUpBottom;
    if (turnedBack) {
      cropUpLeft = y0 / sensorHeight;
      cropUpRight = y1 / sensorHeight;
      cropUpTop = 1 - x1 / sensorWidth;
      cropUpBottom = 1 - x0 / sensorWidth;
    } else if (landscape) {
      cropUpLeft = 1 - y1 / sensorHeight;
      cropUpRight = 1 - y0 / sensorHeight;
      cropUpTop = x0 / sensorWidth;
      cropUpBottom = x1 / sensorWidth;
    } else {
      cropUpLeft = x0 / sensorWidth;
      cropUpRight = x1 / sensorWidth;
      cropUpTop = y0 / sensorHeight;
      cropUpBottom = y1 / sensorHeight;
    }
    final spanX = cropUpRight - cropUpLeft, spanY = cropUpBottom - cropUpTop;
    final pageMinX = (left - cropUpLeft) / spanX, pageMaxX = (right - cropUpLeft) / spanX;
    // y up, like Vision: the page's top is the larger value.
    final pageMaxY = 1 - (top - cropUpTop) / spanY, pageMinY = 1 - (bottom - cropUpTop) / spanY;
    final uprightWidth = landscape ? height : width, uprightHeight = landscape ? width : height;
    final quarterTurns = turns.quarterTurns(uprightWidth.toDouble(), uprightHeight.toDouble());
    // ML Kit turns the crop clockwise to read it: upright first, then the
    // reading's own counterclockwise quarter turns.
    final base = turnedBack ? 270 : landscape ? 90 : 0;
    final rotation = (base + 360 - 90 * quarterTurns) % 360;
    return LiveTextCrop._(
      x0: x0,
      y0: y0,
      width: width,
      height: height,
      rotation: rotation,
      quarterTurns: quarterTurns,
      page: [
        math.Point(pageMinX, pageMaxY), math.Point(pageMaxX, pageMaxY),
        math.Point(pageMaxX, pageMinY), math.Point(pageMinX, pageMinY),
      ],
    );
  }

  /// Top-left of the crop in the sensor buffer, and its size (even numbers).
  final int x0;
  final int y0;
  final int width;
  final int height;

  /// Clockwise degrees ML Kit turns the crop before reading it.
  final int rotation;

  /// The upright page crop was turned counterclockwise this many quarter turns to be read.
  final int quarterTurns;

  /// The page's corners in the upright crop, normalized, origin bottom-left.
  final List<math.Point<double>> page;

  /// The size of the image ML Kit reads.
  int get readingWidth => rotation == 90 || rotation == 270 ? height : width;
  int get readingHeight => rotation == 90 || rotation == 270 ? width : height;

  /// The crop's luminance, row by row from the Y plane. Null when the plane
  /// is smaller than its stride says.
  Uint8List? extract(Uint8List plane, {required int rowStride, int pixelStride = 1}) {
    if (rowStride <= 0 || pixelStride <= 0) return null;
    final out = Uint8List(width * height);
    for (var row = 0; row < height; row++) {
      final start = (y0 + row) * rowStride + x0 * pixelStride;
      if (pixelStride == 1) {
        if (start + width > plane.length) return null;
        out.setRange(row * width, row * width + width, plane, start);
      } else {
        for (var column = 0; column < width; column++) {
          final index = start + column * pixelStride;
          if (index >= plane.length) return null;
          out[row * width + column] = plane[index];
        }
      }
    }
    return out;
  }

  /// What ML Kit read, in the shared terms of scan_text_reading.dart. Its
  /// boxes are pixels with the origin at the top left of the image it read.
  ScanTextFrame frame(List<LiveTextLine> lines) {
    final w = readingWidth.toDouble(), h = readingHeight.toDouble();
    return ScanTextFrame(
      lines: [
        for (final line in lines)
          if (line.right > line.left && line.bottom > line.top)
            ScanTextObservation.turned(
              candidates: [line.text],
              box: TextBox(line.left / w, 1 - line.bottom / h, line.right / w, 1 - line.top / h),
              quarterTurns: quarterTurns,
            ),
      ],
      quarterTurns: quarterTurns,
      page: page,
      readingWidth: w,
      readingHeight: h,
    );
  }
}

/// One line ML Kit read, in pixels of the image it read.
class LiveTextLine {
  const LiveTextLine(this.text, this.left, this.top, this.right, this.bottom);
  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;
}

enum LiveTextReadStatus { read, busy, failed, unavailable }

class LiveTextReadResult {
  const LiveTextReadResult(this.status, [this.lines = const []]);
  final LiveTextReadStatus status;
  final List<LiveTextLine> lines;
}

/// The channel to ML Kit in MainActivity. One read at a time; the scanner
/// throttles it to a few a second.
class LiveTextChannel {
  static const channel = MethodChannel('foorsa/live_text');
  static const maximumLines = 120;
  static const maximumTextLength = 200;

  /// A read that never answers counts as failed, so the next one can start.
  static const readTimeout = Duration(seconds: 4);

  Future<LiveTextReadResult> read(Uint8List luma, LiveTextCrop crop) async {
    try {
      final response = await channel.invokeMapMethod<String, Object?>('read', {
        'luma': luma,
        'width': crop.width,
        'height': crop.height,
        'rotation': crop.rotation,
      }).timeout(readTimeout);
      return parse(response);
    } on MissingPluginException {
      return const LiveTextReadResult(LiveTextReadStatus.unavailable);
    } catch (_) {
      return const LiveTextReadResult(LiveTextReadStatus.failed);
    }
  }

  /// What came back over the channel, checked and bounded.
  static LiveTextReadResult parse(Map<String, Object?>? response) {
    if (response == null) return const LiveTextReadResult(LiveTextReadStatus.failed);
    if (response['busy'] == true) return const LiveTextReadResult(LiveTextReadStatus.busy);
    final raw = response['lines'];
    if (response['error'] != null || raw is! List) return const LiveTextReadResult(LiveTextReadStatus.failed);
    final lines = <LiveTextLine>[];
    for (final item in raw.take(maximumLines)) {
      if (item is! Map) continue;
      final text = item['text'];
      final left = item['left'], top = item['top'], right = item['right'], bottom = item['bottom'];
      if (text is! String || left is! num || top is! num || right is! num || bottom is! num) continue;
      lines.add(LiveTextLine(
        text.length > maximumTextLength ? text.substring(0, maximumTextLength) : text,
        left.toDouble(), top.toDouble(), right.toDouble(), bottom.toDouble(),
      ));
    }
    return LiveTextReadResult(LiveTextReadStatus.read, lines);
  }

  /// Frees the model when the scanner closes.
  Future<void> close() async {
    try {
      await channel.invokeMethod<void>('close');
    } catch (_) {
      // A build without the reader has nothing to free.
    }
  }
}
