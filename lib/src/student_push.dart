import 'dart:async';
import 'dart:io';
import 'student_calls.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

@pragma('vm:entry-point')
Future<void> studentFirebaseBackground(RemoteMessage message) async {
  await Firebase.initializeApp();
  if (message.data['type'] == 'student_call_end') {
    await FlutterCallkitIncoming.endCall('${message.data['callId']}');
    return;
  }
  if (message.data['type'] == 'student_call') {
    await showStudentCall(message.data);
  }
}

/// Only student-chat payloads may navigate the shell; remote URLs are never opened.
bool isStudentChatPush(Map<String, dynamic> data) =>
    data['type'] == 'student_chat' && data['route'] == '/contact/chat';

String? studentUpdateRoute(Map<String, dynamic> data) {
  final id = data['eventId'];
  if (data['type'] != 'student_update' || data['route'] != '/notifications' || id is! String ||
      !RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(id)) { return null; }
  return '/notifications?event=$id';
}

List<DateTime> validCalendarTimes(List<dynamic> reminders, DateTime now) => reminders
    .whereType<Map>().map((r) => DateTime.tryParse('${r['at']}'))
    .whereType<DateTime>().where((at) => at.isAfter(now) && at.isBefore(now.add(const Duration(days: 366))))
    .toList()..sort();

class StudentPush {
  StudentPush({required this.openChat, required this.chatIsVisible, required this.openUpdate, required this.openCalendar});
  final Future<void> Function(String route) openUpdate;
  final Future<void> Function() openCalendar;
  final Future<void> Function() openChat;
  final Future<bool> Function() chatIsVisible;
  final _local = FlutterLocalNotificationsPlugin();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  bool _ready = false;
  bool _localReady = false;
  Map<String, dynamic>? _calendarState;
  bool _disposed = false;
  Future<void>? _starting;
  void Function()? onTokenChanged;
  Future<void> _operations = Future<void>.value();
  Future<T> _serial<T>(Future<T> Function() operation) {
    final next = _operations.then((_) => operation());
    _operations =
        next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  Future<void> start() => _starting ??= _start();
  Future<void> _start() async {
    try {
      // FlutterFire's native app configuration must be supplied for each platform.
      if (_disposed) return;
      await _local.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_message'),
          iOS: DarwinInitializationSettings(
              requestAlertPermission: false,
              requestBadgePermission: false,
              requestSoundPermission: false),
        ),
        onDidReceiveNotificationResponse: (response) {
          unawaited(_openLocal(response.payload));
        },
      );
      await _local
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(const AndroidNotificationChannel(
            'student_messages',
            'Messages from Foorsa',
            description: 'New messages from your Foorsa adviser',
            importance: Importance.high,
          ));
      await _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(const AndroidNotificationChannel('student_updates', 'Foorsa updates', importance: Importance.high));
      _localReady = true;
      tzdata.initializeTimeZones();
      final localLaunch = await _local.getNotificationAppLaunchDetails();
      if (localLaunch?.didNotificationLaunchApp == true) await _openLocal(localLaunch?.notificationResponse?.payload);
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(studentFirebaseBackground);
      StudentCalls.instance.onTokenChanged = () => onTokenChanged?.call();
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
        alert: false,
        badge: false,
        sound: false,
      );
      if (_disposed) return;
      _subscriptions.add(FirebaseMessaging.onMessage.listen((message) async {
        if (message.data['type'] == 'student_call_end') {
          if (StudentCalls.instance.invite?['callId'] ==
              message.data['callId']) {
            await StudentCalls.instance.end(notifyServer: false);
          }
          await FlutterCallkitIncoming.endCall('${message.data['callId']}');
          return;
        }
        if (message.data['type'] == 'student_call') {
          await showStudentCall(message.data);
          return;
        }
        final chat = isStudentChatPush(message.data);
        final update = studentUpdateRoute(message.data);
        if ((!chat && update == null) || (chat && await chatIsVisible()) || _disposed) {
          return;
        }
        await _local.show(
          id: (message.data['eventId'] ?? message.data['messageId'] ?? message.messageId ?? '').hashCode &
              0x3fffffff,
          title: 'Foorsa',
          body: chat ? 'You have a new message from your adviser.' : 'An update is ready in your Foorsa app.',
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
                chat ? 'student_messages' : 'student_updates', chat ? 'Messages from Foorsa' : 'Foorsa updates',
                importance: Importance.high,
                priority: Priority.high,
                icon: 'ic_stat_message'),
            iOS: const DarwinNotificationDetails(
                presentAlert: true, presentSound: true),
          ),
          payload: chat ? '/contact/chat' : update,
        );
      }));
      _subscriptions.add(FirebaseMessaging.onMessageOpenedApp.listen((message) {
        if (isStudentChatPush(message.data)) unawaited(openChat());
        final route = studentUpdateRoute(message.data);
        if (route != null) unawaited(openUpdate(route));
      }));
      // Our HTTP v1 sender requires FCM tokens; FIDs are not valid message.token values.
      // ignore: deprecated_member_use
      _subscriptions.add(FirebaseMessaging.instance.onTokenRefresh
          .listen((_) => onTokenChanged?.call()));
      _ready = true;
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        if (isStudentChatPush(initial.data)) await openChat();
        final route = studentUpdateRoute(initial.data);
        if (route != null) await openUpdate(route);
      }
    } catch (_) {
      // An unconfigured development build must still open the portal.
      _ready = false;
    }
  }

  Future<Map<String, dynamic>> token({bool requestPermission = true}) =>
      _serial(() => _token(requestPermission: requestPermission));
  Future<Map<String, dynamic>> _token({required bool requestPermission}) async {
    await start();
    if (!_ready) return {'token': null, 'status': 'unconfigured'};
    final messaging = FirebaseMessaging.instance;
    final settings = requestPermission
        ? await messaging.requestPermission(
            alert: true, badge: true, sound: true)
        : await messaging.getNotificationSettings();
    if (settings.authorizationStatus != AuthorizationStatus.authorized &&
        settings.authorizationStatus != AuthorizationStatus.provisional) {
      return {'token': null, 'status': 'denied'};
    }
    await messaging.setAutoInitEnabled(true);
    // APNs registration may finish after the user answers the permission prompt.
    if (Platform.isIOS) {
      for (var i = 0; i < 10 && await messaging.getAPNSToken() == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      if (await messaging.getAPNSToken() == null) {
        return {'token': null, 'status': 'pending'};
      }
    }
    // Keep the legacy FCM token until the server supports FID addressing.
    return {
      // ignore: deprecated_member_use
      'token': await messaging.getToken(),
      'platform': Platform.isIOS ? 'ios' : 'android',
      'status': 'ready',
      'notificationVersion': 2,
      // The server rings only devices that say so (nativeAdviserCalls).
      'callsEnabled': nativeAdviserCalls,
      'voipToken': Platform.isIOS ? await FlutterCallkitIncoming.getDevicePushTokenVoIP() : null
    };
  }

  Future<void> clear() => _serial(_clear);
  Future<void> _clear() async {
    await start();
    if (_ready) {
      await FirebaseMessaging.instance.setAutoInitEnabled(false);
      // ignore: deprecated_member_use
      await FirebaseMessaging.instance.deleteToken();
    }
    if (_localReady) await _local.cancelAll();
    await StudentCalls.instance.end();
    await FlutterCallkitIncoming.endAllCalls();
    _calendarState = {'enabled': false};
    await _saveCalendarState();
  }

  Future<void> _openLocal(String? payload) async {
    if (payload == '/contact/chat') return openChat();
    if (payload == '/calendar') return openCalendar();
    if (payload != null && payload.startsWith('/notifications?event=')) {
      final route = studentUpdateRoute({'type': 'student_update', 'route': '/notifications', 'eventId': payload.substring('/notifications?event='.length)});
      if (route != null) await openUpdate(route);
    }
  }

  Future<File> _calendarFile() async => File('${(await getApplicationSupportDirectory()).path}/calendar-reminders.json');
  Future<void> _saveCalendarState() async {
    await (await _calendarFile()).writeAsString(jsonEncode(_calendarState));
  }
  Future<void> _clearCalendar() async {
    for (var i = 0; i < 60; i++) { await _local.cancel(id: 1900000000 + i); }
    _calendarState = {'enabled': false};
    await _saveCalendarState();
  }

  Future<Map<String, dynamic>> calendar(String action, Map<dynamic, dynamic> input) => _serial(() async {
    await start();
    if (!_localReady) return {'supported': false};
    final owner = '${input['owner']}';
    if (!RegExp(r'^[1-9][0-9]{0,14}$').hasMatch(owner)) return {'error': 'Invalid calendar account'};
    if (_calendarState == null) {
      try { _calendarState = Map<String, dynamic>.from(jsonDecode(await (await _calendarFile()).readAsString()) as Map); }
      catch (_) { _calendarState = {'enabled': false}; }
    }
    if (_calendarState!['owner'] != owner) await _clearCalendar();
    if (action == 'calendarClear') { await _clearCalendar(); return {'supported': true, 'enabled': false, 'count': 0}; }
    if (action == 'calendarEnable') {
      final ios = await _local.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()?.requestPermissions(alert: true, badge: false, sound: true);
      final android = await _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
      _calendarState = {'owner': owner, 'enabled': (ios ?? android) == true};
      await _saveCalendarState();
    }
    if (action == 'calendarSync' && _calendarState!['enabled'] == true) {
      final raw = input['reminders'];
      if (raw is! List || raw.length > 60) return {'error': 'Invalid calendar reminders'};
      final fingerprint = jsonEncode(raw);
      if (_calendarState!['fingerprint'] != fingerprint) {
        final enabled = _calendarState!['enabled'];
        await _clearCalendar();
        final times = validCalendarTimes(raw, DateTime.now()).take(60).toList();
        for (var i = 0; i < times.length; i++) {
          await _local.zonedSchedule(id: 1900000000 + i, title: 'Foorsa', body: 'Your class or calendar event is coming up.',
            scheduledDate: tz.TZDateTime.from(times[i].toUtc(), tz.UTC),
            notificationDetails: const NotificationDetails(android: AndroidNotificationDetails('student_calendar', 'Your calendar reminders', importance: Importance.high, icon: 'ic_stat_message'), iOS: DarwinNotificationDetails()),
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle, payload: '/calendar');
        }
        _calendarState = {'owner': owner, 'enabled': enabled, 'fingerprint': fingerprint, 'count': times.length,
          'through': times.isEmpty ? null : times.last.toUtc().toIso8601String()};
        await _saveCalendarState();
      }
    }
    return {'supported': true, 'enabled': _calendarState!['enabled'] == true, 'permission': _calendarState!['enabled'] == true,
      'count': _calendarState!['count'] ?? 0, 'through': _calendarState!['through']};
  });

  void dispose() {
    _disposed = true;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
  }
}
