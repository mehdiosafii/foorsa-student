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

  test('reads the portal\'s words, and anything else is no choice', () {
    expect(ShellAppearanceStore.parse('dark'), ShellAppearance.dark);
    expect(ShellAppearanceStore.parse('light'), ShellAppearance.light);
    expect(ShellAppearanceStore.parse('system'), ShellAppearance.system);
    expect(ShellAppearanceStore.parse('purple'), isNull);
    expect(ShellAppearanceStore.parse(1), isNull);
    expect(ShellAppearanceStore.parse(null), isNull);
  });

  // The owner, 31 Oct 2026: light is the app's default; System follows the phone.
  test('a student who never chose opens light, whatever the phone', () {
    expect(ShellAppearanceStore.isDark(null, phoneIsDark: true), isFalse);
    expect(ShellAppearanceStore.isDark(ShellAppearance.light, phoneIsDark: true), isFalse);
    expect(ShellAppearanceStore.isDark(ShellAppearance.dark, phoneIsDark: false), isTrue);
    expect(ShellAppearanceStore.isDark(ShellAppearance.system, phoneIsDark: true), isTrue);
    expect(ShellAppearanceStore.isDark(ShellAppearance.system, phoneIsDark: false), isFalse);
  });

  test('keeps the choice for the next start', () async {
    expect(await store.read(), isNull);
    await store.write(ShellAppearance.dark);
    expect(await ShellAppearanceStore(directory: () async => dir).read(), ShellAppearance.dark);
    await store.write(ShellAppearance.light);
    expect(await store.read(), ShellAppearance.light);
  });

  test('System is kept as a choice of its own', () async {
    await store.write(ShellAppearance.system);
    expect(await store.read(), ShellAppearance.system);
    await store.write(null);
    expect(await store.read(), isNull);
  });

  test('a folder it cannot read never stops the app', () async {
    final broken = ShellAppearanceStore(directory: () async => throw const FileSystemException('no'));
    expect(await broken.read(), isNull);
    await broken.write(ShellAppearance.dark);
  });
}
