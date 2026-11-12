import 'dart:io';
import 'dart:ui' show AppLifecycleState;

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

  test('a slow load is left to finish, not cut off by the next retry', () {
    final start = DateTime.utc(2026, 11, 6, 12);
    expect(shouldRetryLoad(loadStartedAt: null, now: start), isTrue);
    // The retry ticks every six seconds; a load from China takes longer.
    expect(shouldRetryLoad(loadStartedAt: start, now: start.add(const Duration(seconds: 6))), isFalse);
    expect(shouldRetryLoad(loadStartedAt: start, now: start.add(const Duration(seconds: 30))), isFalse);
    // A load that never ends is given up on.
    expect(shouldRetryLoad(loadStartedAt: start, now: start.add(retryLoadPatience)), isTrue);
    final shell = File('lib/src/shell_page.dart').readAsStringSync();
    final retry = RegExp(r'void _retry\(\) \{[\s\S]*?\n  \}').firstMatch(shell)![0]!;
    expect(retry, contains('shouldRetryLoad('));
  });

  // ── The web view's start, timed only while the app is on screen ──────────
  // The crash board, 1 to 8 Nov 2026: thirteen `Web view stopped: not created
  // in time`, in pairs seconds apart, on every build from 1.2.34 to 1.2.40,
  // none with an error beside it. The fifteen seconds ran while the app drew
  // nothing (started unseen, or left at once), so no web view had even been
  // asked for; and a student who came back was shown "No internet connection".
  group('the web view start watch', () {
    late DateTime clock;
    late AppLifecycleState? lifecycle;
    late int stuck;
    late WebViewStartWatch watch;

    setUp(() {
      clock = DateTime.utc(2026, 11, 11, 20);
      lifecycle = AppLifecycleState.resumed;
      stuck = 0;
      watch = WebViewStartWatch(onStuck: () => stuck++, now: () => clock, lifecycle: () => lifecycle);
    });
    tearDown(() => watch.dispose());

    /// Time passes for the app and for the phone's clock alike.
    Future<void> pass(WidgetTester tester, Duration time) async {
      clock = clock.add(time);
      await tester.pump(time);
    }

    void turn(AppLifecycleState state) {
      lifecycle = state;
      watch.lifecycleChanged(state);
    }

    test('the app can draw when resumed, inactive or not yet told; not hidden, paused or detached', () {
      expect(appCanDraw(null), isTrue);
      expect(appCanDraw(AppLifecycleState.resumed), isTrue);
      expect(appCanDraw(AppLifecycleState.inactive), isTrue);
      expect(appCanDraw(AppLifecycleState.hidden), isFalse);
      expect(appCanDraw(AppLifecycleState.paused), isFalse);
      expect(appCanDraw(AppLifecycleState.detached), isFalse);
    });

    testWidgets('on screen and never created: stuck after the limit, once', (tester) async {
      watch.start();
      await pass(tester, webViewStartLimit - const Duration(seconds: 1));
      expect(stuck, 0);
      await pass(tester, const Duration(seconds: 1));
      expect(stuck, 1);
      await pass(tester, const Duration(minutes: 5));
      expect(stuck, 1);
    });

    testWidgets('created in time: never stuck', (tester) async {
      watch.start();
      await pass(tester, const Duration(seconds: 2));
      watch.created();
      await pass(tester, const Duration(minutes: 5));
      expect(stuck, 0);
      expect(watch.waiting, isFalse);
    });

    testWidgets('started unseen, the app is not timed until it is on screen', (tester) async {
      lifecycle = AppLifecycleState.paused;
      watch.start();
      await pass(tester, const Duration(hours: 2));
      expect(stuck, 0, reason: 'no frame was drawn, so no web view was asked for');
      expect(watch.startedAt, isNull);
      turn(AppLifecycleState.resumed);
      await pass(tester, const Duration(seconds: 3));
      watch.created(); // its first frames make the web view, as on any start
      await pass(tester, const Duration(minutes: 1));
      expect(stuck, 0);
    });

    testWidgets('left in its first seconds and reopened later: the time starts again', (tester) async {
      watch.start();
      await pass(tester, const Duration(seconds: 5));
      turn(AppLifecycleState.inactive); // still drawn
      turn(AppLifecycleState.hidden);
      turn(AppLifecycleState.paused);
      await pass(tester, const Duration(minutes: 10));
      expect(stuck, 0);
      turn(AppLifecycleState.resumed);
      await pass(tester, webViewStartLimit - const Duration(seconds: 1));
      expect(stuck, 0, reason: 'not the ten seconds left over from before it left');
      await pass(tester, const Duration(seconds: 1));
      expect(stuck, 1, reason: 'a web view that truly cannot be made is still caught');
    });

    testWidgets('a watch that ends late by the clock did not have its time', (tester) async {
      watch.start();
      // The phone suspends the app without telling it: no timer runs, the
      // clock goes on, and the timer ends as the app wakes.
      clock = clock.add(const Duration(minutes: 30));
      await tester.pump(webViewStartLimit);
      expect(stuck, 0);
      // Awake and on screen for the whole limit, with no web view: stuck.
      await pass(tester, webViewStartLimit);
      expect(stuck, 1);
    });

    testWidgets('the retry leaves a web view being made its time, and waits for the app to be on screen', (tester) async {
      expect(watch.mayRebuild(), isTrue, reason: 'none is being made');
      watch.start();
      // The offline screen's retry ticks every six seconds.
      await pass(tester, const Duration(seconds: 6));
      expect(watch.mayRebuild(), isFalse);
      await pass(tester, const Duration(seconds: 6));
      expect(watch.mayRebuild(), isFalse);
      await pass(tester, const Duration(seconds: 6));
      expect(stuck, 1);
      expect(watch.mayRebuild(), isTrue);
      // A new one, as the retry makes it: timed afresh.
      watch.start();
      await pass(tester, const Duration(seconds: 6));
      expect(watch.mayRebuild(), isFalse);
      turn(AppLifecycleState.paused);
      await pass(tester, const Duration(minutes: 3));
      expect(watch.mayRebuild(), isFalse, reason: 'no web view can be made while the app is away');
      turn(AppLifecycleState.resumed);
      expect(watch.mayRebuild(), isFalse, reason: 'the one put on screen as it left is being made now');
      watch.dispose();
    });

    test('the shell page times the start through the watch and tells it where the app is', () {
      final shell = File('lib/src/shell_page.dart').readAsStringSync();
      expect(shell, contains('with WidgetsBindingObserver'));
      expect(shell, contains('WidgetsBinding.instance.addObserver(this);'));
      expect(shell, contains('WidgetsBinding.instance.removeObserver(this);'));
      expect(shell, contains('_startWatch.lifecycleChanged(state)'));
      expect(shell, contains('_startWatch.created();'));
      final retry = RegExp(r'void _retry\(\) \{[\s\S]*?\n  \}').firstMatch(shell)![0]!;
      expect(retry, contains('if (!_startWatch.mayRebuild()) return;'));
      expect(retry.indexOf('_startWatch.mayRebuild()'), lessThan(retry.indexOf('_rebuildWebView();')));
    });
  });
}
