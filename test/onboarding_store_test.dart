import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/onboarding/onboarding_store.dart';

void main() {
  late Directory root;
  late Directory files;
  late Directory webView;

  setUp(() {
    root = Directory.systemTemp.createTempSync('onboarding_store_');
    files = Directory('${root.path}/files')..createSync();
    webView = Directory('${root.path}/app_webview');
  });
  tearDown(() => root.deleteSync(recursive: true));

  OnboardingStore store() => OnboardingStore(
        directory: () async => files,
        webViewData: () async => [webView],
      );

  test('a first-time downloader sees the onboarding', () async {
    expect(await store().shouldShow(), isTrue);
    expect(await store().read(), OnboardingRecord.started);
  });

  test(
      'a first launch closed halfway opens on the onboarding again, though the portal has run',
      () async {
    expect(await store().shouldShow(), isTrue);
    // The portal loaded behind the onboarding.
    webView.createSync();
    expect(await store().shouldShow(), isTrue);
  });

  test('a student who has boarded never sees it again', () async {
    expect(await store().shouldShow(), isTrue);
    await store().markDone();
    expect(await store().shouldShow(), isFalse);
  });

  test('an update from an older build goes straight to the portal, as before',
      () async {
    webView.createSync();
    expect(await store().shouldShow(), isFalse);
    expect(await store().read(), OnboardingRecord.done);
  });

  test('a phone whose files cannot be read still opens the app', () async {
    final broken = OnboardingStore(
      directory: () async => throw const FileSystemException('no disk'),
      webViewData: () async => [webView],
    );
    expect(await broken.shouldShow(), isTrue);
    await broken.markDone();
  });
}
