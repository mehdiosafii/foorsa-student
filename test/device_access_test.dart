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

  // The owner's stress test, 11 Nov 2026. Allow's answer and the resume that
  // follows the system prompt both found every access granted inside the
  // dialog's exit, and both popped: the second pop removed the app's page.
  testWidgets('granting the last access closes the reminder once and leaves the portal', (tester) async {
    // camera = 1, microphone = 7, locationWhenInUse = 5; 1 = granted, 0 = denied.
    final statuses = <int, int>{1: 1, 7: 1, 5: 0};
    final prompt = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'checkPermissionStatus') return statuses[call.arguments as int] ?? 0;
      if (call.method == 'requestPermissions') {
        await prompt.future; // the system prompt is up
        final ids = (call.arguments as List).cast<int>();
        for (final id in ids) {
          statuses[id] = 1;
        }
        return {for (final id in ids) id: 1};
      }
      return null;
    });
    final pops = _Pops();
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [pops],
      home: const DeviceAccess(child: Scaffold(body: Text('Portal'))),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Set up your device'), findsOneWidget);
    await tester.tap(find.text('Allow'));
    await tester.pump();
    // The prompt takes the focus, the student allows, the app is given its
    // answer and is then resumed, all inside the dialog's 150 ms exit.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    prompt.complete();
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pumpAndSettle();
    expect(pops.popped, ['DialogRoute<void>']);
    expect(find.text('Set up your device'), findsNothing);
    expect(find.text('Portal'), findsOneWidget);
  });

  // Android answers nothing when the prompt is interrupted (Home, then the
  // app again) or when another permission request is already open: the
  // reminder's buttons, Continue included, stayed off for good.
  testWidgets('a system prompt that never answers does not lock the reminder', (tester) async {
    final never = Completer<Object?>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'checkPermissionStatus') return 0;
      if (call.method == 'requestPermissions') return never.future;
      return null;
    });
    await open(tester);
    await tester.tap(find.text('Allow').first);
    await tester.pump();
    // Continue is never off.
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Continue')).onPressed, isNotNull);
    // Back in the app with no answer: a moment later the rows work again.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump();
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Allow').first).onPressed, isNotNull);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Set up your device'), findsNothing);
    expect(find.text('Portal'), findsOneWidget);
  });

  testWidgets('permanent denial offers Settings', (tester) async {
    await open(tester);
    await tester.tap(find.text('Allow').first);
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Access is blocked. Tap Settings to enable it.'), findsOneWidget);
  });
}

class _Pops extends NavigatorObserver {
  final List<String> popped = [];
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => popped.add('${route.runtimeType}');
}
