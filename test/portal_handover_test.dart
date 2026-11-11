import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/portal_handover.dart';

class _WebView extends Fake implements InAppWebViewController {}

void main() {
  // Making the web view holds the thread the app draws on, so what would
  // come in as the app opens (the device access reminder) waits for it.
  test('says when the shell\'s first web view exists, once', () async {
    final handover = PortalHandover.instance;
    var made = 0;
    handover.webViewMade.then((_) => made++);
    await Future<void>.delayed(Duration.zero);
    expect(made, 0);

    // The shell forgets a dead web view before it makes another.
    handover.controller = null;
    await Future<void>.delayed(Duration.zero);
    expect(made, 0);

    final first = _WebView();
    handover.controller = first;
    expect(handover.controller, same(first));
    await Future<void>.delayed(Duration.zero);
    expect(made, 1);

    // A web view made anew (Android, after its render process is gone).
    handover.controller = null;
    expect(handover.controller, isNull);
    handover.controller = _WebView();
    await Future<void>.delayed(Duration.zero);
    expect(made, 1);
    // Whoever asks later is answered at once.
    await handover.webViewMade;
    handover.controller = null;
  });

  test('the shell hands it over, and the reminder waits for it', () {
    // InAppWebView cannot be built in a test (it is a platform view), so the
    // sources are held to it.
    final shell = File('lib/src/shell_page.dart').readAsStringSync();
    final created = shell.indexOf('onWebViewCreated: (controller) {');
    expect(shell.substring(created, created + 220),
        contains('PortalHandover.instance.controller = controller;'));
    expect(File('lib/main.dart').readAsStringSync(),
        contains('after: PortalHandover.instance.webViewMade,'));
  });
}
