import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Only student-chat payloads may navigate the shell; remote URLs are never opened.
bool isStudentChatPush(Map<String, dynamic> data) =>
    data['type'] == 'student_chat' && data['route'] == '/contact/chat';

class StudentPush {
  StudentPush({required this.openChat, required this.chatIsVisible});
  final Future<void> Function() openChat;
  final Future<bool> Function() chatIsVisible;
  final _local = FlutterLocalNotificationsPlugin();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  bool _ready = false;
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
      await Firebase.initializeApp();
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
          if (response.payload == '/contact/chat') unawaited(openChat());
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
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
        alert: false,
        badge: false,
        sound: false,
      );
      if (_disposed) return;
      _subscriptions.add(FirebaseMessaging.onMessage.listen((message) async {
        if (!isStudentChatPush(message.data) ||
            await chatIsVisible() ||
            _disposed) {
          return;
        }
        await _local.show(
          id: (message.data['messageId'] ?? message.messageId ?? '').hashCode &
              0x7fffffff,
          title: 'Foorsa',
          body: 'You have a new message from your adviser.',
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
                'student_messages', 'Messages from Foorsa',
                importance: Importance.high,
                priority: Priority.high,
                icon: 'ic_stat_message'),
            iOS: DarwinNotificationDetails(
                presentAlert: true, presentSound: true),
          ),
          payload: '/contact/chat',
        );
      }));
      _subscriptions.add(FirebaseMessaging.onMessageOpenedApp.listen((message) {
        if (isStudentChatPush(message.data)) unawaited(openChat());
      }));
      // Our HTTP v1 sender requires FCM tokens; FIDs are not valid message.token values.
      // ignore: deprecated_member_use
      _subscriptions.add(FirebaseMessaging.instance.onTokenRefresh
          .listen((_) => onTokenChanged?.call()));
      _ready = true;
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null && isStudentChatPush(initial.data)) await openChat();
      final localLaunch = await _local.getNotificationAppLaunchDetails();
      if (localLaunch?.didNotificationLaunchApp == true &&
          localLaunch?.notificationResponse?.payload == '/contact/chat') {
        await openChat();
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
      'status': 'ready'
    };
  }

  Future<void> clear() => _serial(_clear);
  Future<void> _clear() async {
    await start();
    if (!_ready) return;
    await FirebaseMessaging.instance.setAutoInitEnabled(false);
    // ignore: deprecated_member_use
    await FirebaseMessaging.instance.deleteToken();
    await _local.cancelAll();
  }

  void dispose() {
    _disposed = true;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
  }
}
