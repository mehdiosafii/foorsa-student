import 'dart:async';
import 'dart:io';

/// Fetch authenticated document URLs with both idle and total deadlines.
/// A failed transfer never replaces the destination with a partial document.
Future<void> transferDocument(
  Uri uri,
  File destination, {
  Map<String, String> headers = const {},
  Duration connectionTimeout = const Duration(seconds: 15),
  Duration responseTimeout = const Duration(seconds: 20),
  Duration bodyTimeout = const Duration(seconds: 20),
  Duration totalTimeout = const Duration(seconds: 60),
}) async {
  if (uri.scheme != 'https' && uri.scheme != 'http') {
    throw const FormatException('Unsupported document URL');
  }
  final staging = await destination.parent.createTemp('.foorsa-transfer-');
  final partial = File('${staging.path}/document');
  final client = HttpClient()..connectionTimeout = connectionTimeout;
  IOSink? sink;
  var expired = false;
  void checkDeadline() {
    if (expired) throw TimeoutException('Document transfer timed out');
  }

  try {
    await (() async {
      final request = await client.getUrl(uri).timeout(connectionTimeout);
      checkDeadline();
      headers.forEach(request.headers.set);
      final response = await request.close().timeout(responseTimeout);
      checkDeadline();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('HTTP ${response.statusCode}');
      }
      sink = partial.openWrite();
      await sink!.addStream(response.timeout(bodyTimeout));
      await sink!.close();
      sink = null;
    })()
        .timeout(totalTimeout, onTimeout: () {
      expired = true;
      client.close(force: true);
      throw TimeoutException('Document transfer timed out');
    });
    await partial.rename(destination.path);
  } finally {
    expired = true;
    client.close(force: true);
    // Aborting the client unblocks addStream. Bound cleanup too, so a failed
    // transfer cannot keep the modal progress indicator on screen.
    try {
      await sink?.close().timeout(const Duration(seconds: 1));
    } catch (_) {
      // Preserve the original transfer error.
    }
    try {
      await staging.delete(recursive: true);
    } on FileSystemException {
      // The OS can finish releasing an interrupted file asynchronously.
    }
  }
}
