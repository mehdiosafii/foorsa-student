/// Low-cost conversion from CameraX/AVFoundation preview to a 120x160
/// luminance grid. We never decode RGB frames or retain full-size buffers.
library;

import 'dart:typed_data';
import 'package:camera/camera.dart';

import 'scan_guidance.dart';

/// Android normally supplies YUV420 Y plane; iOS normally supplies BGRA.
/// Unknown layouts disable auto-capture but never disable the manual shutter.
ScanLumaGrid? sampleCameraLuma(
  CameraImage image, {
  int targetWidth = 120,
  int targetHeight = 160,
}) {
  if (image.width <= 0 || image.height <= 0 || image.planes.isEmpty
      || targetWidth < 40 || targetHeight < 40) {
    return null;
  }
  final format = image.format.group;
  if (format != ImageFormatGroup.yuv420 &&
      format != ImageFormatGroup.bgra8888) {
    return null;
  }
  final plane = image.planes.first;
  final bytes = plane.bytes;
  final rowStride = plane.bytesPerRow;
  final pixelStride = plane.bytesPerPixel ??
      (format == ImageFormatGroup.bgra8888 ? 4 : 1);
  if (rowStride <= 0 || pixelStride <= 0) return null;
  final data = Uint8List(targetWidth * targetHeight);
  // Preview buffers are normally landscape on devices held portrait. Rotate
  // this grid rather than allocate a rotated full-resolution camera frame.
  final landscapeBuffer = image.width > image.height;
  for (var y = 0; y < targetHeight; y++) {
    for (var x = 0; x < targetWidth; x++) {
      final int sx;
      final int sy;
      if (landscapeBuffer) {
        sx = ((y + 0.5) * image.width / targetHeight).floor();
        sy = ((targetWidth - x - 0.5) * image.height / targetWidth).floor();
      } else {
        sx = ((x + 0.5) * image.width / targetWidth).floor();
        sy = ((y + 0.5) * image.height / targetHeight).floor();
      }
      final index = sy * rowStride + sx * pixelStride;
      if (index < 0 || index >= bytes.length) return null;
      int luminance;
      if (format == ImageFormatGroup.bgra8888) {
        if (index + 2 >= bytes.length) return null;
        // Byte order is B, G, R, A. Preserve 8-bit luma without allocating RGB.
        luminance = ((bytes[index + 2] * 77
          + bytes[index + 1] * 150 + bytes[index] * 29) >> 8);
      } else {
        luminance = bytes[index];
      }
      data[y * targetWidth + x] = luminance;
    }
  }
  return ScanLumaGrid(targetWidth, targetHeight, data);
}
