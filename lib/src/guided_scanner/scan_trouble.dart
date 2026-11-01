/// What the Android guided camera tells the crash board (Admin Portal ›
/// Student App › Crashes, through crash_reports.dart) when a scan loses its
/// automatic capture or its camera: what was lost, why, and the resolution
/// the camera opened at.
///
/// The owner, 1 Nov 2026, on an Android 17 phone: "In Android the scanning
/// didn't show the auto scanning interface". Nothing on the board said why: a
/// camera that streamed no frames, or frames in a layout the scanner cannot
/// read, quietly left the page with its shutter alone.
///
/// Nothing about the student is sent: no pixels, nothing read from the page,
/// no message or path from the camera. Only an exception's type and code, a
/// frame's format and size, and the camera's preset.
library;

import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';

enum ScanTrouble {
  /// The image stream failed at the sensor's full resolution before any
  /// frame came; the camera reopens once a step lower to keep auto-capture.
  streamRetried,

  /// No automatic capture for the rest of this camera: the shutter only.
  autoCaptureLost,

  /// The camera did not open.
  cameraFailed,

  /// The student left the scanner for the phone's own camera app.
  cameraApp,
}

/// The board's place for every report from the guided camera.
const scanTroubleWhere = 'Guided scanner';

/// The crash board's line for [trouble]. [camera] is how the camera opened
/// ([scanCameraNote]), for the troubles of an open camera.
String scanTroubleReport(ScanTrouble trouble, String reason, {String? camera}) {
  final opened = camera ?? 'not open';
  final line = switch (trouble) {
    ScanTrouble.streamRetried =>
      'Scanner: image stream failed at $opened ($reason); reopening at veryHigh '
          '(1080p stills) to keep auto-capture',
    ScanTrouble.autoCaptureLost =>
      'Scanner: no auto-capture, shutter only ($reason); camera $opened',
    ScanTrouble.cameraFailed => 'Scanner: camera did not open ($reason)',
    ScanTrouble.cameraApp =>
      'Scanner: student chose the phone camera app (camera did not open: $reason)',
  };
  return line.length > 300 ? line.substring(0, 300) : line;
}

/// An error as the board names it: its type, and the code of a camera or
/// platform error; never its message, which can carry a path.
String scanErrorName(Object error) {
  String code(String value) {
    final clean = value.replaceAll(RegExp(r'[^A-Za-z0-9 ._:-]'), '').trim();
    return clean.length > 60 ? clean.substring(0, 60) : clean;
  }

  return switch (error) {
    CameraException(code: final c) => 'CameraException ${code(c)}',
    PlatformException(code: final c) => 'PlatformException ${code(c)}',
    TimeoutException() => 'TimeoutException',
    // The page's own: "No rear camera", "Camera unavailable".
    StateError(message: final m) when RegExp(r'^[A-Za-z ]{1,40}$').hasMatch(m) => 'StateError: $m',
    _ => error.runtimeType.toString(),
  };
}

/// How the camera opened: its preset, the preview's size, and the presets
/// above it that did not open ("veryHigh, preview 1920x1080, after max:
/// CameraException IllegalArgumentException").
String scanCameraNote(ResolutionPreset preset, Size? preview,
    {List<(ResolutionPreset, String)> skipped = const []}) {
  final size = preview == null ? '' : ', preview ${preview.width.round()}x${preview.height.round()}';
  final after = skipped.isEmpty
      ? ''
      : ', after ${skipped.map((s) => '${s.$1.name}: ${s.$2}').join('; ')}';
  return '${preset.name}$size$after';
}

/// Why the camera did not open: each error with the presets it stopped, in
/// turn ("CameraException IllegalArgumentException at max, veryHigh, high"),
/// or [error] alone when none was tried.
String scanOpenFailure(Object error, List<(ResolutionPreset, String)> failed) {
  if (failed.isEmpty) return scanErrorName(error);
  final byError = <String, List<String>>{};
  for (final (preset, name) in failed) {
    byError.putIfAbsent(name, () => []).add(preset.name);
  }
  return byError.entries.map((e) => '${e.key} at ${e.value.join(', ')}').join('; ');
}
