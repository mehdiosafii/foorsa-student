/// Low-cost conversion from CameraX/AVFoundation preview to a 120x160
/// luminance grid. We never decode RGB frames or retain full-size buffers.
library;

import 'dart:typed_data';
import 'package:camera/camera.dart';

import 'scan_guidance.dart';

/// One plane of luminance from the camera's image stream, as the platform
/// lays it out: Android's Y plane (YUV_420_888, one byte a pixel) or the
/// iPhone's BGRA buffer, with its row and pixel strides. A plain value, so it
/// can be read on the UI isolate or handed to the frame worker.
class ScanLumaPlane {
  const ScanLumaPlane({
    required this.bytes,
    required this.width,
    required this.height,
    required this.rowStride,
    this.pixelStride = 1,
    this.bgra = false,
  });

  final Uint8List bytes;
  final int width;
  final int height;
  final int rowStride;
  final int pixelStride;

  /// Blue, green, red, alpha: luminance is computed from the first three.
  final bool bgra;

  /// The luminance plane of a stream frame. Null for a layout the scanner
  /// cannot read, which disables auto-capture but never the manual shutter.
  static ScanLumaPlane? fromCameraImage(CameraImage image) {
    final format = image.format.group;
    if (format != ImageFormatGroup.yuv420 && format != ImageFormatGroup.bgra8888) return null;
    if (image.width <= 0 || image.height <= 0 || image.planes.isEmpty) return null;
    final plane = image.planes.first;
    final bgra = format == ImageFormatGroup.bgra8888;
    final pixelStride = plane.bytesPerPixel ?? (bgra ? 4 : 1);
    if (plane.bytesPerRow <= 0 || pixelStride <= 0) return null;
    return ScanLumaPlane(
      bytes: plane.bytes,
      width: image.width,
      height: image.height,
      rowStride: plane.bytesPerRow,
      pixelStride: pixelStride,
      bgra: bgra,
    );
  }
}

/// The share of the upright camera image the preview shows, when the preview
/// is cropped to cover a screen of [viewportAspect] (width over height).
/// Without an aspect, or with the preview contained, all of it.
({double left, double top, double width, double height}) visiblePreviewRegion(
    int sensorWidth, int sensorHeight, double? viewportAspect) {
  final landscape = sensorWidth > sensorHeight;
  final portraitWidth = landscape ? sensorHeight : sensorWidth;
  final portraitHeight = landscape ? sensorWidth : sensorHeight;
  final sourceAspect = portraitWidth / portraitHeight;
  var left = 0.0, top = 0.0, width = 1.0, height = 1.0;
  if (viewportAspect != null && viewportAspect > 0 && viewportAspect.isFinite) {
    if (sourceAspect > viewportAspect) {
      width = viewportAspect / sourceAspect;
      left = (1 - width) / 2;
    } else {
      height = sourceAspect / viewportAspect;
      top = (1 - height) / 2;
    }
  }
  return (left: left, top: top, width: width, height: height);
}

/// Android normally supplies YUV420 Y plane; iOS normally supplies BGRA.
/// Unknown layouts disable auto-capture but never disable the manual shutter.
ScanLumaGrid? sampleCameraLuma(
  CameraImage image, {
  int targetWidth = 120,
  int targetHeight = 160,
  double? viewportAspect,
  int sensorOrientation = 90,
}) {
  final plane = ScanLumaPlane.fromCameraImage(image);
  if (plane == null) return null;
  return sampleScanLuma(plane,
      targetWidth: targetWidth, targetHeight: targetHeight,
      viewportAspect: viewportAspect, sensorOrientation: sensorOrientation);
}

/// The visible preview as a small upright grid, each cell the average of a
/// few pixels spread over it rather than one pixel. Before 31 Oct 2026 a cell
/// was a single pixel: on a cheap Android sensor its noise alone, and a hand's
/// tremor of one pixel over printed text, moved the grid more than the
/// steadiness check allows, so a page held still never read as steady.
///
/// Preview buffers are normally landscape on devices held portrait. The grid
/// is rotated, never the full-resolution camera image: a back camera's
/// buffer is the upright image turned a quarter counterclockwise
/// ([sensorOrientation] 90, nearly every phone), or clockwise (270, a few).
/// A BoxFit.cover preview also crops the image: [viewportAspect] analyses
/// exactly that visible center rather than asking for document edges in
/// pixels the user cannot see.
ScanLumaGrid? sampleScanLuma(
  ScanLumaPlane plane, {
  int targetWidth = 120,
  int targetHeight = 160,
  double? viewportAspect,
  int sensorOrientation = 90,
}) {
  if (plane.width <= 0 || plane.height <= 0 || targetWidth < 40 || targetHeight < 40 ||
      plane.rowStride <= 0 || plane.pixelStride <= 0) {
    return null;
  }
  if (plane.bgra && plane.pixelStride < 4) return null;
  final bytes = plane.bytes;
  final landscape = plane.width > plane.height;
  final region = visiblePreviewRegion(plane.width, plane.height, viewportAspect);
  final turnedBack = sensorOrientation == 270;
  // Pixels averaged a cell along each upright axis: about one every three
  // sensor pixels, at most four.
  final portraitWidth = landscape ? plane.height : plane.width;
  final portraitHeight = landscape ? plane.width : plane.height;
  int across(double span, int cells) =>
      (span / cells / 3).round().clamp(1, 4);
  final kx = across(region.width * portraitWidth, targetWidth);
  final ky = across(region.height * portraitHeight, targetHeight);
  // Byte offsets along each upright axis, precomputed: in a landscape buffer
  // the upright x runs along the sensor's rows and the upright y along its
  // columns, so a sample's offset is one from each list added together.
  final xOffsets = Int32List(targetWidth * kx);
  final yOffsets = Int32List(targetHeight * ky);
  for (var x = 0; x < targetWidth; x++) {
    for (var i = 0; i < kx; i++) {
      final nx = region.left + (x + (i + 0.5) / kx) * region.width / targetWidth;
      final int offset;
      if (landscape) {
        final sy = turnedBack ? (nx * plane.height).floor() : ((1 - nx) * plane.height).floor();
        offset = sy.clamp(0, plane.height - 1) * plane.rowStride;
      } else {
        offset = (nx * plane.width).floor().clamp(0, plane.width - 1) * plane.pixelStride;
      }
      xOffsets[x * kx + i] = offset;
    }
  }
  for (var y = 0; y < targetHeight; y++) {
    for (var j = 0; j < ky; j++) {
      final ny = region.top + (y + (j + 0.5) / ky) * region.height / targetHeight;
      final int offset;
      if (landscape) {
        final sx = turnedBack ? ((1 - ny) * plane.width).floor() : (ny * plane.width).floor();
        offset = sx.clamp(0, plane.width - 1) * plane.pixelStride;
      } else {
        offset = (ny * plane.height).floor().clamp(0, plane.height - 1) * plane.rowStride;
      }
      yOffsets[y * ky + j] = offset;
    }
  }
  // Every sample stays inside the plane, or the frame is not read at all.
  var maxX = 0, maxY = 0;
  for (final offset in xOffsets) {
    if (offset > maxX) maxX = offset;
  }
  for (final offset in yOffsets) {
    if (offset > maxY) maxY = offset;
  }
  if (maxX + maxY + (plane.bgra ? 2 : 0) >= bytes.length) return null;

  final data = Uint8List(targetWidth * targetHeight);
  final samples = kx * ky;
  for (var y = 0; y < targetHeight; y++) {
    for (var x = 0; x < targetWidth; x++) {
      var sum = 0;
      for (var j = 0; j < ky; j++) {
        final rowOffset = yOffsets[y * ky + j];
        for (var i = 0; i < kx; i++) {
          final index = rowOffset + xOffsets[x * kx + i];
          if (plane.bgra) {
            // Byte order is B, G, R, A. Preserve 8-bit luma without allocating RGB.
            sum += (bytes[index + 2] * 77 + bytes[index + 1] * 150 + bytes[index] * 29) >> 8;
          } else {
            sum += bytes[index];
          }
        }
      }
      data[y * targetWidth + x] = (sum + samples ~/ 2) ~/ samples;
    }
  }
  return ScanLumaGrid(targetWidth, targetHeight, data);
}
