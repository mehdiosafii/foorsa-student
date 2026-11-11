import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/device_access.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter.baseflow.com/permissions/methods');
  var status = 0;
  setUp(() {
    status = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'checkPermissionStatus') return status;
      if (call.method == 'requestPermissions') {
        return {for (final id in call.arguments as List) id: 4};
      }
      if (call.method == 'openAppSettings') return true;
      return null;
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: DeviceAccess(
      child: Scaffold(body: Text('Portal')),
    )));
    await tester.pumpAndSettle();
  }

  testWidgets('granted hardware does not show reminder', (tester) async {
    status = 1;
    await open(tester);
    expect(find.text('Set up your device'), findsNothing);
  });

  testWidgets('dismissal persists through system inactive but not next opening', (tester) async {
    await open(tester);
    expect(find.text('Set up your device'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Set up your device'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Set up your device'), findsOneWidget);
  });

  testWidgets('permanent denial offers Settings', (tester) async {
    await open(tester);
    await tester.tap(find.text('Allow').first);
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Access is blocked. Tap Settings to enable it.'), findsOneWidget);
  });

  // The shell makes its web view as the app opens, on the thread the reminder
  // comes in on (boot_loader_gate.dart): the reminder opens after it.
  group('the reminder and the web view', () {
    Future<void> openAfter(WidgetTester tester, Future<void> made) async {
      await tester.pumpWidget(MaterialApp(home: DeviceAccess(
        after: made,
        child: const Scaffold(body: Text('Portal')),
      )));
      await tester.pumpAndSettle();
    }

    testWidgets('it opens once the web view is made, not before', (tester) async {
      final made = Completer<void>();
      await openAfter(tester, made.future);
      expect(find.text('Set up your device'), findsNothing);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Set up your device'), findsNothing);
      made.complete();
      await tester.pumpAndSettle();
      expect(find.text('Set up your device'), findsOneWidget);
    });

    testWidgets('a web view that never comes does not keep it away', (tester) async {
      await tester.pumpWidget(MaterialApp(home: DeviceAccess(
        after: Completer<void>().future,
        child: const Scaffold(body: Text('Portal')),
      )));
      // The phone has answered what is allowed; the clock has not moved.
      await tester.pump();
      await tester.pump(DeviceAccess.patience - const Duration(milliseconds: 1));
      expect(find.text('Set up your device'), findsNothing);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('Set up your device'), findsOneWidget);
      // As long as the loader rests waiting for the same web view.
      expect(DeviceAccess.patience, const Duration(seconds: 1));
    });

    testWidgets('a web view already there keeps nothing waiting', (tester) async {
      await openAfter(tester, Future<void>.value());
      expect(find.text('Set up your device'), findsOneWidget);
    });

    testWidgets('with every access granted, nothing waits for anything', (tester) async {
      status = 1;
      await openAfter(tester, Completer<void>().future);
      await tester.pump(DeviceAccess.patience);
      expect(find.text('Set up your device'), findsNothing);
    });
  });
}
