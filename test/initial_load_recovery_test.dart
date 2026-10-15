import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/initial_load_recovery.dart';

void main() {
  testWidgets('slow startup reveals content at 45 seconds and stays recoverable',
      (tester) async {
    final recovery = InitialLoadRecovery();
    addTearDown(recovery.dispose);
    var notifications = 0;
    recovery.addListener(() => notifications++);
    recovery.start();

    await tester.pump(const Duration(seconds: 44));
    expect(recovery.blocksContent, isTrue);
    expect(recovery.problem, isNull);
    await tester.pump(const Duration(seconds: 1));
    expect(recovery.blocksContent, isFalse);
    expect(recovery.problem, InitialLoadProblem.slow);
    final count = notifications;
    await tester.pump(const Duration(minutes: 8));
    expect(notifications, count, reason: 'No periodic restart or timeout loop');
    expect(recovery.blocksContent, isFalse);

    recovery.finish();
    expect(recovery.problem, isNull, reason: 'A late success removes the notice');
    expect(recovery.blocksContent, isFalse);
  });

  testWidgets('success cancels deadline and later termination cannot restart it',
      (tester) async {
    final recovery = InitialLoadRecovery();
    addTearDown(recovery.dispose);
    recovery.start();
    await tester.pump(const Duration(seconds: 10));
    recovery.finish();
    recovery.interrupted();
    await tester.pump(const Duration(minutes: 2));
    expect(recovery.blocksContent, isFalse);
    expect(recovery.problem, isNull);
  });

  testWidgets('error completion cancels timeout until a retry starts',
      (tester) async {
    final recovery = InitialLoadRecovery();
    addTearDown(recovery.dispose);
    recovery.start();
    recovery.finish();
    await tester.pump(const Duration(minutes: 1));
    expect(recovery.problem, isNull);
    recovery.start();
    expect(recovery.blocksContent, isTrue);
    await tester.pump(const Duration(seconds: 45));
    expect(recovery.problem, InitialLoadProblem.slow);
  });

  testWidgets('retry gets a fresh deadline without retaining an earlier timer',
      (tester) async {
    final recovery = InitialLoadRecovery();
    addTearDown(recovery.dispose);
    recovery.start();
    await tester.pump(const Duration(seconds: 40));
    recovery.start();
    await tester.pump(const Duration(seconds: 5));
    expect(recovery.blocksContent, isTrue);
    await tester.pump(const Duration(seconds: 40));
    expect(recovery.problem, InitialLoadProblem.slow);
    recovery.start();
    expect(recovery.problem, isNull);
    expect(recovery.blocksContent, isTrue);
    recovery.finish();
    await tester.pump(const Duration(seconds: 45));
    expect(recovery.problem, isNull);
  });

  testWidgets('WebKit termination reveals manual recovery without waiting',
      (tester) async {
    final recovery = InitialLoadRecovery();
    addTearDown(recovery.dispose);
    recovery.start();
    recovery.interrupted();
    expect(recovery.blocksContent, isFalse);
    expect(recovery.problem, InitialLoadProblem.interrupted);
    await tester.pump(const Duration(seconds: 45));
    expect(recovery.problem, InitialLoadProblem.interrupted);
  });

  testWidgets('dispose cancels the pending deadline', (tester) async {
    final recovery = InitialLoadRecovery();
    var notifications = 0;
    recovery.addListener(() => notifications++);
    recovery.start();
    recovery.dispose();
    await tester.pump(const Duration(minutes: 1));
    expect(notifications, 1);
    expect(tester.takeException(), isNull);
  });
}
