import 'dart:convert';
import 'dart:io';

/// Reject empty files and login/error pages before invoking the native viewer.
/// A header check is not a full PDF parser; PDFKit handles document structure.
Future<bool> hasPdfHeader(File file) async {
  final handle = await file.open();
  try {
    final header = await handle.read(1024);
    return latin1.decode(header).contains('%PDF-');
  } finally {
    await handle.close();
  }
}
