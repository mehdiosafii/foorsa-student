import 'dart:convert';
import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:timezone/data/latest.dart' as data;
import 'package:timezone/timezone.dart' as tz;

/// OS schedules survive app closure. The next 60 reminders fit the iOS limit.
class CalendarReminders {
  CalendarReminders({this.onOpen});
  final void Function()? onOpen;
  final plugin = FlutterLocalNotificationsPlugin();
  Future<void>? _ready;
  Future<void> _queue = Future.value();
  Map<String, dynamic> _state = {};
  Future<File> get _file async => File('${(await getApplicationSupportDirectory()).path}/calendar-reminders.json');
  Future<void> initialize() => _ready ??= _initialize();
  Future<void> _initialize() async {
    data.initializeTimeZones();
    await plugin.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
    ), onDidReceiveNotificationResponse: (response) { if(response.payload == '/calendar') onOpen?.call(); });
    final launch = await plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true && launch?.notificationResponse?.payload == '/calendar') onOpen?.call();
    try { _state = Map<String, dynamic>.from(jsonDecode(await (await _file).readAsString())); } catch (_) { _state = {}; }
  }
  Future<void> _persist() async => (await _file).writeAsString(jsonEncode(_state));
  Future<bool> _permission() async {
    if (Platform.isIOS) return (await plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()?.checkPermissions())?.isEnabled == true;
    return await plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.areNotificationsEnabled() == true;
  }
  Future<Map<String, dynamic>> call(Map<String, dynamic> request) async {
    // Serialize replacement/cancellation so older syncs cannot restore deleted events.
    final previous = _queue;
    final completer = () async { await previous; return _handle(request); }();
    _queue = completer.then<void>((_) {}, onError: (Object error, StackTrace stack) {});
    return completer;
  }
  Future<Map<String, dynamic>> _handle(Map<String, dynamic> request) async {
    await initialize();
    final action = request['action'];
    if (action == 'calendarClear') {
      await plugin.cancelAll(); _state = {}; await _persist(); return {'supported': true, 'enabled': false};
    }
    final owner = request['owner']?.toString() ?? '';
    if (owner.isEmpty || owner.length > 80) throw const FormatException('Invalid calendar owner');
    if (_state['owner'] != owner) { await plugin.cancelAll(); _state = {'owner': owner, 'enabled': false}; await _persist(); }
    if (action == 'calendarEnable') {
      final bool granted;
      if (Platform.isIOS) {
        granted = await plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()?.requestPermissions(alert: true, sound: true, badge: false) == true;
      } else {
        granted = await plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission() == true;
      }
      _state['enabled'] = granted; await _persist();
    }
    final allowed = await _permission();
    if (action == 'calendarSync' && _state['enabled'] == true && allowed) {
      final input = request['reminders'];
      if (input is! List || input.length > 60) throw const FormatException('At most 60 upcoming reminders');
      final now = DateTime.now().toUtc();
      final items = input.map((raw) {
        if (raw is! Map) throw const FormatException('Invalid reminder');
        final at = DateTime.tryParse(raw['at']?.toString() ?? '')?.toUtc();
        final title = raw['title']?.toString() ?? '';
        final body = raw['body']?.toString() ?? '';
        if (at == null || title.isEmpty || title.length > 160 || body.length > 300 || at.isAfter(now.add(const Duration(days: 740)))) throw const FormatException('Invalid reminder');
        return {'at': at, 'title': title, 'body': body};
      }).where((r) => (r['at'] as DateTime).isAfter(now)).toList();
      await plugin.cancelAll();
      try {
        for (var i = 0; i < items.length; i++) {
          final r = items[i];
          await plugin.zonedSchedule(20000 + i, r['title'] as String, r['body'] as String,
            tz.TZDateTime.from(r['at'] as DateTime, tz.UTC),
            const NotificationDetails(android: AndroidNotificationDetails('study_calendar', 'Study reminders', importance: Importance.high, priority: Priority.high), iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true)),
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle, payload: '/calendar');
        }
      } catch (_) { await plugin.cancelAll(); _state['count'] = 0; _state.remove('through'); await _persist(); rethrow; }
      _state['count'] = items.length;
      _state['through'] = items.isEmpty ? null : (items.last['at'] as DateTime).toIso8601String();
      await _persist();
    }
    return {'supported': true, 'enabled': _state['enabled'] == true && allowed, 'permission': allowed, 'count': _state['count'] ?? 0, 'through': _state['through']};
  }
}
