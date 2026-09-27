import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/calendar_reminders.dart';
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  late Directory directory;
  setUp(() async {
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    calls.clear();directory=await Directory.systemTemp.createTemp('calendar-test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'),(call)async=>directory.path);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('dexterous.com/flutter/local_notifications'),(call)async{calls.add(call);if(call.method=='getNotificationAppLaunchDetails') return {'notificationLaunchedApp':false};return true;});
  });
  tearDown(() async {await directory.delete(recursive:true);});
  test('replaces OS schedules and clears reminders when owner changes',()async{
    final service=CalendarReminders();
    final enabled=await service.call({'action':'calendarEnable','owner':'1'});expect(enabled['enabled'],true);
    await service.call({'action':'calendarSync','owner':'1','reminders':[{'at':DateTime.now().toUtc().add(const Duration(hours:1)).toIso8601String(),'title':'Physics','body':'Room 2'}]});
    expect(calls.where((c)=>c.method=='zonedSchedule').length,1);
    final changed=await service.call({'action':'calendarStatus','owner':'2'});expect(changed['enabled'],false);
    expect(calls.last.method,'areNotificationsEnabled');
    expect(calls.where((c)=>c.method=='cancelAll').length,3);
  });
  test('rejects oversized replacement before cancelling current schedule',()async{
    final service=CalendarReminders();await service.call({'action':'calendarEnable','owner':'1'});calls.clear();
    await expectLater(service.call({'action':'calendarSync','owner':'1','reminders':List.filled(61,{})}),throwsFormatException);
    expect(calls.any((c)=>c.method=='cancelAll'),false);
  });
}
