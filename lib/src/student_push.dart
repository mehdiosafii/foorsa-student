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
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import 'push_registration.dart';

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

/// The test the student sends themselves from the portal's Settings
/// (`POST /api/portal/push/test`): a banner even with the app open.
bool isStudentTestPush(Map<String, dynamic> data) => data['type'] == 'student_test';

/// What the banner says for each kind of push shown while the app is open.
String foregroundPushBody({required bool chat, required bool test}) => test
    ? 'This is a test notification from Foorsa.'
    : chat
        ? 'You have a new message from your adviser.'
        : 'An update is ready in your Foorsa app.';

/// A banner the app shows itself, presented while the app is open: on iOS
/// since 14 `presentAlert` alone shows nothing, a banner needs its own flag.
const foregroundBannerDetails = DarwinNotificationDetails(
    presentAlert: true, presentBanner: true, presentList: true, presentSound: true);

/// The real phone: Firebase, APNs through the app delegate (AppDelegate.swift,
/// channel `ma.foorsa.student/push`), PushKit through flutter_callkit_incoming.
class FirebasePushPlatform implements PushPlatform {
  static const _apns = MethodChannel('ma.foorsa.student/push');

  @override
  bool get isIOS => Platform.isIOS;

  @override
  Future<void> initialize() async {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(studentFirebaseBackground);
    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: false,
      sound: false,
    );
  }

  static PushPermission _of(AuthorizationStatus status) => switch (status) {
        AuthorizationStatus.authorized => PushPermission.granted,
        AuthorizationStatus.provisional => PushPermission.provisional,
        AuthorizationStatus.denied || AuthorizationStatus.deniedPermanently => PushPermission.denied,
        AuthorizationStatus.notDetermined => PushPermission.notDetermined,
      };

  @override
  Future<PushPermission> permission({required bool ask}) async {
    final messaging = FirebaseMessaging.instance;
    final settings = ask
        ? await messaging.requestPermission(alert: true, badge: true, sound: true)
        : await messaging.getNotificationSettings();
    return _of(settings.authorizationStatus);
  }

  @override
  Future<PushPermission> systemPermission() async {
    final status = await ph.Permission.notification.status;
    if (status.isGranted || status.isLimited) return PushPermission.granted;
    if (status.isProvisional) return PushPermission.provisional;
    if (status.isPermanentlyDenied || status.isRestricted) return PushPermission.denied;
    // iOS reports a permission never asked as denied: permanentlyDenied is the refusal.
    return Platform.isIOS ? PushPermission.notDetermined : PushPermission.denied;
  }

  @override
  Future<void> enableAutoInit() => FirebaseMessaging.instance.setAutoInitEnabled(true);

  @override
  Future<String?> apnsToken() => FirebaseMessaging.instance.getAPNSToken();

  // Our HTTP v1 sender requires FCM tokens; FIDs are not valid message.token values.
  @override
  // ignore: deprecated_member_use
  Future<String?> fcmToken() => FirebaseMessaging.instance.getToken();

  @override
  Future<String?> voipToken() async {
    if (!Platform.isIOS) return null;
    final value = await FlutterCallkitIncoming.getDevicePushTokenVoIP();
    return value is String && value.isNotEmpty ? value : null;
  }

  @override
  Future<String?> apnsError() async {
    if (!Platform.isIOS) return null;
    try {
      final state = await _apns.invokeMapMethod<String, Object?>('apnsState');
      final error = state?['error'];
      return error is String && error.trim().isNotEmpty ? error.trim() : null;
    } catch (_) {
      // An older build has no such channel.
      return null;
    }
  }
}

List<DateTime> validCalendarTimes(List<dynamic> reminders, DateTime now) => reminders
    .whereType<Map>().map((r) => DateTime.tryParse('${r['at']}'))
    .whereType<DateTime>().where((at) => at.isAfter(now) && at.isBefore(now.add(const Duration(days: 366))))
    .toList()..sort();

class StudentPush {
  StudentPush({
    required this.openChat,
    required this.chatIsVisible,
    required this.openUpdate,
    required this.openCalendar,
    PushPlatform? platform,
    PushProblems? problems,
  }) : _problems = problems ?? PushProblems() {
    _registration = PushRegistration(platform ?? FirebasePushPlatform(), _problems);
  }
  final Future<void> Function(String route) openUpdate;
  final Future<void> Function() openCalendar;
  final Future<void> Function() openChat;
  final Future<bool> Function() chatIsVisible;
  final PushProblems _problems;
  late final PushRegistration _registration;
  final _local = FlutterLocalNotificationsPlugin();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  bool _listening = false;
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

  /// Local notifications and Firebase, each on its own: a local notifications
  /// plugin that fails no longer keeps Firebase from starting, and a Firebase
  /// that fails is tried again by the next registration (push_registration.dart).
  Future<void> start() => _starting ??= _start();
  Future<void> _start() async {
    if (_disposed) return;
    await _startLocal();
    await _ensureMessaging();
  }

  Future<void> _startLocal() async {
    try {
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
      if (localLaunch?.didNotificationLaunchApp == true) unawaited(_openLocal(localLaunch?.notificationResponse?.payload));
    } catch (error) {
      unawaited(_problems.report('push: local notifications unavailable: ${describePushError(error)}'));
    }
  }

  /// Firebase, and once it runs, the handlers for what it delivers.
  Future<String?> _ensureMessaging() async {
    final error = await _registration.ensureReady();
    if (error == null && !_listening && !_disposed) {
      _listening = true;
      _listen();
      // Never awaited: on some launches the plugin is slow to say whether a
      // notification opened the app, and a registration must not wait on it.
      unawaited(_openInitialMessage());
    }
    return error;
  }

  void _listen() {
    try {
      StudentCalls.instance.onTokenChanged = () => onTokenChanged?.call();
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
        final test = isStudentTestPush(message.data);
        final update = studentUpdateRoute(message.data);
        if ((!chat && !test && update == null) || (chat && await chatIsVisible()) || _disposed || !_localReady) {
          return;
        }
        await _local.show(
          id: (message.data['eventId'] ?? message.data['messageId'] ?? message.messageId ?? '').hashCode &
              0x3fffffff,
          title: 'Foorsa',
          body: foregroundPushBody(chat: chat, test: test),
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
                chat ? 'student_messages' : 'student_updates', chat ? 'Messages from Foorsa' : 'Foorsa updates',
                importance: Importance.high,
                priority: Priority.high,
                icon: 'ic_stat_message'),
            iOS: foregroundBannerDetails,
          ),
          payload: chat ? '/contact/chat' : update,
        );
      }));
      _subscriptions.add(FirebaseMessaging.onMessageOpenedApp.listen((message) {
        if (isStudentChatPush(message.data)) unawaited(openChat());
        final route = studentUpdateRoute(message.data);
        if (route != null) unawaited(openUpdate(route));
      }));
      // A new token is registered again by the portal (foorsa-push-token-changed).
      // ignore: deprecated_member_use
      _subscriptions.add(FirebaseMessaging.instance.onTokenRefresh
          .listen((_) => onTokenChanged?.call()));
    } catch (error) {
      unawaited(_problems.report('push: listeners not started: ${describePushError(error)}'));
    }
  }

  Future<void> _openInitialMessage() async {
    try {
      final initial = await FirebaseMessaging.instance
          .getInitialMessage()
          .timeout(const Duration(seconds: 10));
      if (initial == null || _disposed) return;
      if (isStudentChatPush(initial.data)) await openChat();
      final route = studentUpdateRoute(initial.data);
      if (route != null) await openUpdate(route);
    } catch (_) {
      // No notification opened the app, or the plugin never said.
    }
  }

  /// What the portal registers (`getPushToken`), or why there is nothing to
  /// register (push_registration.dart names each reason).
  Future<Map<String, dynamic>> token({bool requestPermission = true}) =>
      _serial(() async {
        await start();
        await _ensureMessaging();
        return _registration.token(requestPermission: requestPermission, callsEnabled: nativeAdviserCalls);
      });

  /// Where this phone stands, without asking anything (`pushStatus`).
  Future<Map<String, dynamic>> status() => _serial(() async {
        await start();
        await _ensureMessaging();
        return _registration.status();
      });

  /// The app's own notification settings (`openNotificationSettings`): on an
  /// iPhone its Notifications page, else the app's page in Settings.
  Future<bool> openSettings() async {
    try {
      if (await _local.openAppNotificationSettings() == true) return true;
    } catch (_) {
      // Fall back to the app's page.
    }
    try {
      return await ph.openAppSettings();
    } catch (_) {
      return false;
    }
  }

  Future<void> clear() => _serial(_clear);
  Future<void> _clear() async {
    await start();
    if (_registration.ready) {
      try {
        await FirebaseMessaging.instance.setAutoInitEnabled(false);
        // ignore: deprecated_member_use
        await FirebaseMessaging.instance.deleteToken();
      } catch (_) {
        // Signed out all the same; the server forgot the token already.
      }
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
