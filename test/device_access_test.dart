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
}
