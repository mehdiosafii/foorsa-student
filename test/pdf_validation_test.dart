import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/pdf_validation.dart';

void main() {
  late Directory directory;
  late File file;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pdf-validation-');
    file = File('${directory.path}/document.pdf');
  });
  tearDown(() async => directory.delete(recursive: true));

  test('accepts PDF header including a leading byte order mark', () async {
    await file.writeAsBytes([0xef, 0xbb, 0xbf, ...'%PDF-1.7\n'.codeUnits]);
    expect(await hasPdfHeader(file), isTrue);
  });
  test('rejects an HTML login response saved as a PDF', () async {
    await file.writeAsString('<html><body>Please sign in</body></html>');
    expect(await hasPdfHeader(file), isFalse);
  });
  test('rejects an empty download', () async {
    await file.writeAsBytes([]);
    expect(await hasPdfHeader(file), isFalse);
  });
}
