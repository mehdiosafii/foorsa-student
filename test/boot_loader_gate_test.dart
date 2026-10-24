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
}
