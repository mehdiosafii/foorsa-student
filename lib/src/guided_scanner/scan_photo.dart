/// The photo the Android guided camera hands the portal, made ready on the
/// phone (ScanPhoto.kt on the foorsa/scan_photo channel): upright, at most
/// [ScanPhotoChannel.maximumEdge] pixels on its long side, a JPEG at
/// [ScanPhotoChannel.quality], with no metadata.
///
/// The camera now takes the sensor's full 4:3 photo (12 MP on most phones;
/// before 31 Oct 2026 it took a 1920×1080 frame, which left a page the guide
/// framed about 700 pixels wide). 3264 pixels is an 8 MP photo: a page that
/// fills the guide keeps about 2000 pixels across, more than the portal keeps
/// of it (2400 on its long side), while the photo's data URL stays a few
/// megabytes and the web view of a cheap phone decodes it without running out
/// of memory. Nothing is sharpened, whitened or otherwise "enhanced" here.
library;

import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/services.dart';

class ScanPhoto {
  const ScanPhoto(this.bytes, {required this.width, required this.height, required this.reencoded});
  final Uint8List bytes;
  final int width;
  final int height;

  /// False when the camera's own file was already upright and small enough.
  final bool reencoded;
}

class ScanPhotoChannel {
  static const channel = MethodChannel('foorsa/scan_photo');
  static const maximumEdge = 3264;
  static const quality = 92;

  /// Making the photo ready never takes longer than this; past it, the
  /// camera's own file goes as it is.
  static const timeout = Duration(seconds: 12);

  /// The photo at [path], made ready; null when it cannot be (a build without
  /// the channel, an unreadable file, memory), and the caller then sends the
  /// camera's own file.
  Future<ScanPhoto?> prepare(String path) async {
    try {
      final reply = await channel.invokeMapMethod<String, Object?>('prepare', {
        'path': path,
        'maxEdge': maximumEdge,
        'quality': quality,
      }).timeout(timeout);
      return parse(reply);
    } catch (_) {
      return null;
    }
  }

  /// What came back over the channel, checked: a JPEG within bounds.
  static ScanPhoto? parse(Map<String, Object?>? reply) {
    if (reply == null || reply['error'] != null) return null;
    final bytes = reply['bytes'], width = reply['width'], height = reply['height'];
    if (bytes is! Uint8List || width is! int || height is! int) return null;
    if (bytes.length < 4 || bytes[0] != 0xff || bytes[1] != 0xd8) return null;
    if (width <= 0 || height <= 0) return null;
    return ScanPhoto(bytes, width: width, height: height, reencoded: reply['reencoded'] == true);
  }
}

/// The middle of a still as grey levels (ScanPhoto.kt `sample`), for telling
/// the sharpest of a few stills of the same page.
class ScanLumaSample {
  const ScanLumaSample(this.luma, {required this.width, required this.height});
  final Uint8List luma;
  final int width;
  final int height;
}

extension ScanPhotoSharpness on ScanPhotoChannel {
  /// The middle of the still at [path], about 900 pixels long; null when the
  /// phone cannot say (a build without the method, a file it cannot read).
  Future<ScanLumaSample?> sample(String path) async {
    try {
      final reply = await ScanPhotoChannel.channel.invokeMapMethod<String, Object?>('sample', {
        'path': path,
        'edge': 900,
      }).timeout(const Duration(seconds: 6));
      final luma = reply?['luma'], width = reply?['width'], height = reply?['height'];
      if (luma is! Uint8List || width is! int || height is! int) return null;
      if (width < 16 || height < 16 || luma.length != width * height) return null;
      return ScanLumaSample(luma, width: width, height: height);
    } catch (_) {
      return null;
    }
  }

  /// How sharp the still at [path] is ([scanStillSharpness]), worked off the
  /// UI isolate; null when it cannot be measured.
  Future<double?> sharpness(String path) async {
    final sampled = await sample(path);
    if (sampled == null) return null;
    try {
      return await Isolate.run(() => scanStillSharpness(sampled.luma, sampled.width, sampled.height),
          debugName: 'scan-sharpness');
    } catch (_) {
      return scanStillSharpness(sampled.luma, sampled.width, sampled.height);
    }
  }
}

/// How sharp a still is: the strongest edges in the middle of the page (the
/// mean horizontal and vertical Sobel strength of its sharpest 2% of pixels,
/// whichever is weaker), over its contrast, so a shot a touch darker or
/// brighter than the one beside it is judged on its focus alone. Focus that
/// missed softens every edge; a hand that moved streaks the print along one
/// direction, and only the edges across that direction lose their strength,
/// which is why the weaker direction decides. Only stills of one page are
/// compared with it; [scanStillSoft] is a floor for a page with print on it.
double scanStillSharpness(Uint8List luma, int width, int height) {
  if (width < 3 || height < 3 || luma.length < width * height) return 0;
  final histogram = List<int>.filled(256, 0);
  for (final value in luma) {
    histogram[value]++;
  }
  int quantile(double p) {
    final goal = math.max(1, (luma.length * p).ceil());
    var running = 0;
    for (var v = 0; v < 256; v++) {
      running += histogram[v];
      if (running >= goal) return v;
    }
    return 255;
  }
  final contrast = math.max(16, quantile(0.98) - quantile(0.02));
  // |gx| and |gy| of the Sobel operator: 0 to 1020 each.
  final across = List<int>.filled(1021, 0), down = List<int>.filled(1021, 0);
  var counted = 0;
  for (var y = 1; y < height - 1; y++) {
    final above = (y - 1) * width, row = y * width, below = (y + 1) * width;
    for (var x = 1; x < width - 1; x++) {
      final a = luma[above + x - 1], b = luma[above + x], c = luma[above + x + 1];
      final d = luma[row + x - 1], f = luma[row + x + 1];
      final g = luma[below + x - 1], h = luma[below + x], i = luma[below + x + 1];
      across[((c + 2 * f + i) - (a + 2 * d + g)).abs()]++;
      down[((g + 2 * h + i) - (a + 2 * b + c)).abs()]++;
      counted++;
    }
  }
  if (counted == 0) return 0;
  final top = math.max(1, (counted * 0.02).ceil());
  double strongest(List<int> strength) {
    var taken = 0;
    var sum = 0.0;
    for (var s = strength.length - 1; s >= 0 && taken < top; s--) {
      final n = math.min(strength[s], top - taken);
      sum += n * s;
      taken += n;
    }
    return sum / taken;
  }
  return math.min(strongest(across), strongest(down)) / contrast;
}

/// Below this, a page with print reads as soft (scan_still_sharpness_test.dart: crisp
/// print scores near 3.9, print blurred by a 1.5-pixel radius 2.2, a hand
/// that moved 8 pixels 1.0).
const scanStillSoft = 2.5;

/// The most stills the guided camera takes of one page.
const scanStillsAtMost = 3;

/// Whether to take another still of the page: always a second (a hand that
/// moved as the first was taken, a press of the shutter, focus that settled
/// a moment late), and a third only when neither is sharp.
bool wantsAnotherStill(List<double?> scores) {
  if (scores.isEmpty) return true;
  if (scores.length >= scanStillsAtMost) return false;
  // A phone that cannot measure keeps its first still, as before.
  if (scores.first == null) return false;
  if (scores.length == 1) return true;
  final best = bestStill(scores);
  final bestScore = best < 0 ? null : scores[best];
  return bestScore != null && bestScore < scanStillSoft;
}

/// The sharpest still (the first among equals); -1 when there is none.
int bestStill(List<double?> scores) {
  var best = -1;
  for (var i = 0; i < scores.length; i++) {
    final score = scores[i];
    if (score == null) continue;
    if (best < 0 || score > scores[best]! * 1.02) best = i;
  }
  return best < 0 && scores.isNotEmpty ? 0 : best;
}
