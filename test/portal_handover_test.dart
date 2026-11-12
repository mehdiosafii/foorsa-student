import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/boot_loader_gate.dart';
import 'package:foorsa_student/src/portal_handover.dart';

class _WebView extends Fake implements InAppWebViewController {}

void main() {
  // Making the web view holds the thread the app draws on, and the frame
  // that first shows it is drawn twice on Android: what would come in over
  // the shell as the app opens (the device access reminder) waits a moment
  // past it.
  testWidgets('says when the shell\'s first web view is made and settled, once',
      (tester) async {
    final handover = PortalHandover.instance;
    var settled = 0;
    handover.webViewSettled.then((_) => settled++);
    await tester.pump(const Duration(seconds: 2));
    expect(settled, 0, reason: 'no web view yet');

    // The shell forgets a dead web view before it makes another.
    handover.controller = null;
    await tester.pump(const Duration(seconds: 2));
    expect(settled, 0);

    final first = _WebView();
    handover.controller = first;
    expect(handover.controller, same(first));
    await tester.pump(BootLoaderGate.settle - const Duration(milliseconds: 1));
    expect(settled, 0, reason: 'not on the frames that first show it');
    await tester.pump(const Duration(milliseconds: 1));
    expect(settled, 1);

    // A web view made anew (Android, after its render process is gone)
    // starts no second wait.
    handover.controller = null;
    expect(handover.controller, isNull);
    handover.controller = _WebView();
    await tester.pump(BootLoaderGate.settle);
    expect(settled, 1);
    // Whoever asks later (the reminder, when the app comes back to the
    // front) is answered at once.
    var late = false;
    handover.webViewSettled.then((_) => late = true);
    await tester.pump();
    expect(late, isTrue);
    handover.controller = null;
  });

  test('the shell hands it over, and the reminder waits for it', () {
    // InAppWebView cannot be built in a test (it is a platform view), so the
    // sources are held to it.
    final shell = File('lib/src/shell_page.dart').readAsStringSync();
    final created = shell.indexOf('onWebViewCreated: (controller) {');
    final handlers = shell.indexOf('controller.addJavaScriptHandler(', created);
    expect(created, isNonNegative);
    expect(shell.substring(created, handlers),
        contains('PortalHandover.instance.controller = controller;'));
    expect(File('lib/main.dart').readAsStringSync(),
        contains('after: PortalHandover.instance.webViewSettled,'));
  });
}
