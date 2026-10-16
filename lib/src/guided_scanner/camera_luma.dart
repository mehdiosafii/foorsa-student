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
  double? viewportAspect,
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
  // a tiny grid, never the full-resolution camera image. A BoxFit.cover
  // preview also crops the image: analyse exactly that visible center rather
  // than asking for document edges in pixels the user cannot see.
  final landscapeBuffer = image.width > image.height;
  final portraitWidth = landscapeBuffer ? image.height : image.width;
  final portraitHeight = landscapeBuffer ? image.width : image.height;
  final sourceAspect = portraitWidth / portraitHeight;
  var cropLeft = 0.0, cropTop = 0.0, cropWidth = 1.0, cropHeight = 1.0;
  if (viewportAspect != null && viewportAspect > 0 &&
      viewportAspect.isFinite) {
    if (sourceAspect > viewportAspect) {
      cropWidth = viewportAspect / sourceAspect;
      cropLeft = (1 - cropWidth) / 2;
    } else {
      cropHeight = sourceAspect / viewportAspect;
      cropTop = (1 - cropHeight) / 2;
    }
  }
  for (var y = 0; y < targetHeight; y++) {
    for (var x = 0; x < targetWidth; x++) {
      final nx = cropLeft + (x + 0.5) * cropWidth / targetWidth;
      final ny = cropTop + (y + 0.5) * cropHeight / targetHeight;
      final int sx;
      final int sy;
      if (landscapeBuffer) {
        sx = (ny * image.width).floor();
        sy = ((1 - nx) * image.height).floor();
      } else {
        sx = (nx * image.width).floor();
        sy = (ny * image.height).floor();
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
