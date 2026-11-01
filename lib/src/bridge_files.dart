/// A file handed to the portal over the JavaScript bridge (FoorsaShellPickFile,
/// FoorsaShellScanDocument): its name, its type and its bytes as a data URL.
///
/// A photo is several megabytes, and its base64 is a third larger. Encoding it
/// on the UI isolate held the app's frames for as long as it took (the owner,
/// 1 Nov 2026, on Android: "the app still freezes"), once per photo, ten
/// photos at a time from the library. Anything past [bridgeInlineLimit] is
/// encoded on a short-lived isolate, whose result comes back without a copy.
library;

import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

/// Bytes up to this many are encoded where they are: an isolate costs more
/// than the work.
const bridgeInlineLimit = 256 * 1024;

const _mimes = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'heic': 'image/heic',
  'pdf': 'application/pdf',
};

/// The type the portal expects for a file of this name.
String bridgeMime(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  return _mimes[ext] ?? 'application/octet-stream';
}

/// The data URL of [bytes], as the portal reads it.
String bridgeDataUrl(String mime, List<int> bytes) => 'data:$mime;base64,${base64Encode(bytes)}';

/// The entry the portal reads for one file. Large files are encoded off the
/// UI isolate; a phone that cannot start one encodes it here, as before.
Future<Map<String, dynamic>> bridgeFileEntry(String name, List<int> bytes) async {
  final mime = bridgeMime(name);
  String dataUrl;
  if (bytes.length <= bridgeInlineLimit) {
    dataUrl = bridgeDataUrl(mime, bytes);
  } else {
    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    try {
      dataUrl = await Isolate.run(() => bridgeDataUrl(mime, data), debugName: 'bridge-file');
    } catch (_) {
      dataUrl = bridgeDataUrl(mime, data);
    }
  }
  return {'name': name, 'mime': mime, 'dataUrl': dataUrl};
}
