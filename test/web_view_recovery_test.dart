import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/web_view_recovery.dart';

void main() {
  final home = Uri.parse('https://student.foorsa.ma/');

  test('a reload goes back to the page the student was on, not Home', () {
    final recovery = WebViewRecovery(home);
    expect(recovery.pageToReload(), home);
    recovery.notePage(Uri.parse('https://student.foorsa.ma/documents?section=file&paper=passport'), trusted: true);
    expect(recovery.pageToReload().toString(), 'https://student.foorsa.ma/documents?section=file&paper=passport');
  });

  test('another site is never the page to come back to', () {
    final recovery = WebViewRecovery(home);
    recovery.notePage(Uri.parse('https://student.foorsa.ma/cv'), trusted: true);
    recovery.notePage(Uri.parse('https://www.youtube-nocookie.com/embed/x'), trusted: false);
    recovery.notePage(Uri.parse('about:blank'), trusted: true);
    expect(recovery.pageToReload().path, '/cv');
  });

  test('a one-time link is not replayed: its token and the fragment are dropped', () {
    final recovery = WebViewRecovery(home);
    recovery.notePage(Uri.parse('https://student.foorsa.ma/reset-password?token=abc123&x=1#top'), trusted: true);
    expect(recovery.pageToReload().toString(), 'https://student.foorsa.ma/reset-password?x=1');
    recovery.notePage(Uri.parse('https://student.foorsa.ma/login-link?token=abc123'), trusted: true);
    expect(recovery.pageToReload().toString(), 'https://student.foorsa.ma/login-link');
  });

  test('a page that keeps dying is reloaded three times in two minutes, then left to the retry', () {
    final recovery = WebViewRecovery(home);
    final start = DateTime(2026, 10, 31, 22);
    expect(recovery.mayRestart(start), isTrue);
    expect(recovery.mayRestart(start.add(const Duration(seconds: 20))), isTrue);
    expect(recovery.mayRestart(start.add(const Duration(seconds: 40))), isTrue);
    expect(recovery.mayRestart(start.add(const Duration(seconds: 60))), isFalse);
    expect(recovery.mayRestart(start.add(const Duration(minutes: 3))), isTrue);
  });

  test('a cancelled or handed-off load is not being offline', () {
    // iPhone: a newer navigation, a download the app took, a link handed to another app.
    expect(isLoadFailure(code: -999, description: 'cancelled', isIOS: true), isFalse);
    expect(isLoadFailure(code: 102, description: 'Frame load interrupted', isIOS: true), isFalse);
    expect(isLoadFailure(code: 204, description: 'Plug-in handled load', isIOS: true), isFalse);
    expect(isLoadFailure(code: -1009, description: 'The Internet connection appears to be offline.', isIOS: true), isTrue);
    expect(isLoadFailure(code: -1001, description: 'The request timed out.', isIOS: true), isTrue);
    // Android.
    expect(isLoadFailure(code: -1, description: 'net::ERR_ABORTED', isIOS: false), isFalse);
    expect(isLoadFailure(code: -2, description: 'net::ERR_INTERNET_DISCONNECTED', isIOS: false), isTrue);
  });

  test('the shell page recovers a dead page and never retries to Home', () {
    final shell = File('lib/src/shell_page.dart').readAsStringSync();
    // Without useOnRenderProcessGone a render process killed for memory takes
    // the whole Android app down.
    expect(shell, contains('useOnRenderProcessGone: true'));
    expect(shell, contains('onRenderProcessGone: (controller, detail)'));
    expect(shell, contains('onWebContentProcessDidTerminate: (controller)'));
    expect(shell, contains('key: ValueKey<int>(_webViewGeneration)'));
    expect(shell, contains('isLoadFailure('));
    final retry = RegExp(r'void _retry\(\) \{[\s\S]*?\n  \}').firstMatch(shell)![0]!;
    expect(retry, isNot(contains('AppConfig.baseUrl')));
    expect(retry, contains('_recovery.pageToReload()'));
    expect(File('lib/main.dart').readAsStringSync(), contains('reportUncaughtErrors();'));
  });
}
