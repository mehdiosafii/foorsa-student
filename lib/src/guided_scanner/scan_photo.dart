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
