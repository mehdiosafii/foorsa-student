import 'dart:io';

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/bridge_files.dart';

void main() {
  test('a file reaches the portal as the same data URL, small or large', () async {
    final small = Uint8List.fromList(List.generate(1000, (i) => i % 256));
    final large = Uint8List.fromList(List.generate(bridgeInlineLimit * 3, (i) => (i * 7) % 256));
    final a = await bridgeFileEntry('Scan.jpg', small);
    final b = await bridgeFileEntry('page.JPEG', large);
    expect(a, {'name': 'Scan.jpg', 'mime': 'image/jpeg', 'dataUrl': 'data:image/jpeg;base64,${base64Encode(small)}'});
    expect(b['mime'], 'image/jpeg');
    expect(b['dataUrl'], 'data:image/jpeg;base64,${base64Encode(large)}');
  });

  test('the portal reads the type from the name, as before', () {
    expect(bridgeMime('a.pdf'), 'application/pdf');
    expect(bridgeMime('a.PNG'), 'image/png');
    expect(bridgeMime('a.webp'), 'image/webp');
    expect(bridgeMime('a.heic'), 'image/heic');
    expect(bridgeMime('noextension'), 'application/octet-stream');
  });

  test('the shell builds every file entry here, never inline on the UI isolate', () {
    final shell = File('lib/src/shell_page.dart').readAsStringSync();
    expect(shell.contains('base64Encode(bytes)'), isFalse);
    expect(RegExp(r"'files': \[\s*_fileEntry").hasMatch(shell), isFalse,
        reason: 'every entry is awaited');
  });
}
