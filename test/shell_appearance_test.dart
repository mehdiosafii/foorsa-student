import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/shell_appearance.dart';

void main() {
  late Directory dir;
  late ShellAppearanceStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('appearance');
    store = ShellAppearanceStore(directory: () async => dir);
  });
  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('reads the portal\'s words, and anything else follows the phone', () {
    expect(ShellAppearanceStore.parse('dark'), ShellAppearance.dark);
    expect(ShellAppearanceStore.parse('light'), ShellAppearance.light);
    expect(ShellAppearanceStore.parse('system'), isNull);
    expect(ShellAppearanceStore.parse('purple'), isNull);
    expect(ShellAppearanceStore.parse(1), isNull);
    expect(ShellAppearanceStore.parse(null), isNull);
  });

  test('keeps the choice for the next start', () async {
    expect(await store.read(), isNull);
    await store.write(ShellAppearance.dark);
    expect(await ShellAppearanceStore(directory: () async => dir).read(), ShellAppearance.dark);
    await store.write(ShellAppearance.light);
    expect(await store.read(), ShellAppearance.light);
  });

  test('going back to the phone\'s theme forgets it', () async {
    await store.write(ShellAppearance.dark);
    await store.write(null);
    expect(await store.read(), isNull);
  });

  test('a folder it cannot read never stops the app', () async {
    final broken = ShellAppearanceStore(directory: () async => throw const FileSystemException('no'));
    expect(await broken.read(), isNull);
    await broken.write(ShellAppearance.dark);
  });
}
