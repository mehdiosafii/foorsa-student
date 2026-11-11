import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/boot_loader_gate.dart';

void main() {
  test('a portal from before this build: lifts once loaded and shown a moment', () {
    final gate = BootLoaderGate();
    gate.pageLoaded();
    expect(gate.showing, isTrue);
    gate.minimumPassed();
    expect(gate.showing, isFalse);
  });

  test('a portal that holds: stays until its first screen is up', () {
    final gate = BootLoaderGate();
    expect(gate.portalSays('hold'), isTrue);
    gate.minimumPassed();
    gate.pageLoaded();
    expect(gate.showing, isTrue);
    expect(gate.waitingForPortal, isTrue);
    gate.portalSays('ready');
    expect(gate.showing, isFalse);
  });

  test('ready before the page has finished loading still waits for the page', () {
    final gate = BootLoaderGate()..portalSays('hold');
    gate.portalSays('ready');
    gate.minimumPassed();
    expect(gate.showing, isTrue);
    gate.pageLoaded();
    expect(gate.showing, isFalse);
  });

  test('a portal that never says ready is let go', () {
    final gate = BootLoaderGate()..portalSays('hold');
    gate
      ..minimumPassed()
      ..pageLoaded();
    expect(gate.showing, isTrue);
    gate.holdExpired();
    expect(gate.showing, isFalse);
    expect(BootLoaderGate.holdLimit, const Duration(seconds: 10));
  });

  test('only the first hold starts the timer, and nothing else counts', () {
    final gate = BootLoaderGate();
    expect(gate.portalSays('hold'), isTrue);
    expect(gate.portalSays('hold'), isFalse);
    expect(gate.portalSays(42), isFalse);
    expect(gate.portalSays(null), isFalse);
  });

  test('once lifted it never comes back for a later page load', () {
    final gate = BootLoaderGate()
      ..minimumPassed()
      ..pageLoaded();
    expect(gate.showing, isFalse);
    expect(gate.portalSays('hold'), isFalse);
    expect(gate.showing, isFalse);
  });

  // Making the web view holds the thread the app draws on. Through 1.2.40 the
  // loader played from its first frame and the web view was made 300 ms
  // later, in the middle of the arrow's shine.
  group('the loader rests until the web view is made', () {
    test('it rests from the start, and plays once the web view exists', () {
      final gate = BootLoaderGate();
      expect(gate.resting, isTrue);
      gate.webViewMade();
      expect(gate.resting, isFalse);
    });

    test('a web view slow to come, or never made, does not leave it still', () {
      final gate = BootLoaderGate();
      gate.restExpired();
      expect(gate.resting, isFalse);
      // Inside the shortest time the loader shows, with room to play.
      expect(BootLoaderGate.restLimit, const Duration(seconds: 1));
    });

    test('resting is not what keeps the loader up, nor what lifts it', () {
      final gate = BootLoaderGate()
        ..minimumPassed()
        ..pageLoaded();
      expect(gate.showing, isFalse);
      expect(gate.resting, isTrue);
      final other = BootLoaderGate()..webViewMade();
      expect(other.showing, isTrue);
    });

    test('once it plays, a web view made anew does not stop it', () {
      final gate = BootLoaderGate()..restExpired();
      gate.webViewMade();
      expect(gate.resting, isFalse);
    });
  });

  group('when the web view is made', () {
    Future<bool> Function() turn(WidgetTester tester,
        {required Duration delay, required Future<void> firstFrame}) {
      var may = false;
      whenWebViewMayStart(delay: delay, firstFrame: firstFrame)
          .then((_) => may = true);
      return () async {
        // Lets what is due run, without moving the clock.
        await tester.pump();
        return may;
      };
    }

    testWidgets('an ordinary start: as soon as the first frame is drawn',
        (tester) async {
      final frame = Completer<void>();
      final may = turn(tester, delay: Duration.zero, firstFrame: frame.future);
      expect(await may(), isFalse, reason: 'the loader is seen first');
      await tester.pump(const Duration(milliseconds: 40));
      expect(await may(), isFalse);
      frame.complete();
      expect(await may(), isTrue, reason: 'no fixed wait after it');
    });

    testWidgets('never later than it was, should that frame not be reported',
        (tester) async {
      final may = turn(tester,
          delay: Duration.zero, firstFrame: Completer<void>().future);
      await tester.pump(const Duration(milliseconds: 299));
      expect(await may(), isFalse);
      await tester.pump(const Duration(milliseconds: 1));
      expect(await may(), isTrue);
      expect(BootLoaderGate.firstFrameLimit, const Duration(milliseconds: 300));
    });

    testWidgets('a first launch: after the takeoff, whatever was drawn',
        (tester) async {
      const takeoff = Duration(milliseconds: 3600);
      final may =
          turn(tester, delay: takeoff, firstFrame: Future<void>.value());
      await tester.pump(const Duration(milliseconds: 3599));
      expect(await may(), isFalse);
      await tester.pump(const Duration(milliseconds: 1));
      expect(await may(), isTrue);
    });
  });
}
