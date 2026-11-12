import 'dart:async';
import 'dart:io';
import 'app_language.dart';
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
import 'student_adhan.dart';

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

/// What the app's own notifications say, in the student's language, and
/// what the phone's settings call their channels.
const pushTitle = Words('Foorsa', 'Foorsa', 'فرصة');
const pushChatBody = Words(
    'You have a new message from your adviser.',
    'Vous avez un nouveau message de votre conseiller.',
    'لديك رسالة جديدة من مستشارك.');
const pushUpdateBody = Words(
    'An update is ready in your Foorsa app.',
    'Une mise à jour vous attend dans votre application Foorsa.',
    'تحديث جديد بانتظارك في تطبيق فرصة.');
const pushTestBody = Words(
    'This is a test notification from Foorsa.',
    'Ceci est une notification de test de Foorsa.',
    'هذا إشعار تجريبي من فرصة.');
const pushCalendarBody = Words(
    'Your class or calendar event is coming up.',
    'Votre cours ou un événement de votre calendrier approche.',
    'اقترب موعد حصتك أو حدث في تقويمك.');
const messagesChannelName = Words(
    'Messages from Foorsa', 'Messages de Foorsa', 'رسائل فرصة');
const messagesChannelDescription = Words(
    'New messages from your Foorsa adviser',
    'Nouveaux messages de votre conseiller Foorsa',
    'الرسائل الجديدة من مستشارك في فرصة');
const updatesChannel =
    Words('Foorsa updates', 'Actualités Foorsa', 'مستجدات فرصة');
const calendarChannel = Words('Your calendar reminders',
    'Rappels de votre calendrier', 'تذكيرات تقويمك');

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
String foregroundPushBody({required bool chat, required bool test, AppLanguage language = AppLanguage.en}) =>
    (test ? pushTestBody : chat ? pushChatBody : pushUpdateBody).of(language);

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
    Future<Directory> Function()? directory,
    Duration? fcmWait,
  })  : _problems = problems ?? PushProblems(),
        _directory = directory ?? getApplicationSupportDirectory {
    final phone = platform ?? FirebasePushPlatform();
    _registration = fcmWait == null
        ? PushRegistration(phone, _problems)
        : PushRegistration(phone, _problems, fcmWait: fcmWait);
  }

  /// Where the calendar's and the adhan's state is kept (tests name a folder).
  final Future<Directory> Function() _directory;
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
  Map<String, dynamic>? _adhanState;
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

  /// The student's language, for what the app says itself.
  AppLanguage get _language => ShellLanguage.instance.current;

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
      // The channels' names follow the student's language: Android renames a
      // channel created again with the same id.
      final language = _language;
      await _local
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(AndroidNotificationChannel(
            'student_messages',
            messagesChannelName.of(language),
            description: messagesChannelDescription.of(language),
            importance: Importance.high,
          ));
      await _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(AndroidNotificationChannel('student_updates', updatesChannel.of(language), importance: Importance.high));
      await _createAdhanChannels(language);
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
        final language = _language;
        await _local.show(
          id: (message.data['eventId'] ?? message.data['messageId'] ?? message.messageId ?? '').hashCode &
              0x3fffffff,
          title: pushTitle.of(language),
          body: foregroundPushBody(chat: chat, test: test, language: language),
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
                chat ? 'student_messages' : 'student_updates',
                (chat ? messagesChannelName : updatesChannel).of(language),
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

  /// Registrations wait on one another, not on the queue above: a
  /// registration can wait on the student (the notification prompt), on
  /// Apple (ten seconds) and on Google (twenty, and for good in mainland
  /// China). Run inside the queue, each `getPushToken` held the adhan, the
  /// calendar, the Settings row and sign-out behind it for that long (the
  /// stress test, 11 Nov 2026: `adhanStatus` answered after 20 s, each time).
  Future<void> _registrations = Future<void>.value();

  /// What the portal registers (`getPushToken`), or why there is nothing to
  /// register (push_registration.dart names each reason).
  Future<Map<String, dynamic>> token({bool requestPermission = true}) {
    final next = _registrations.then((_) async {
      // Starting touches the same plugins as the queue's work: in the queue.
      await _serial(() async {
        await start();
        await _ensureMessaging();
      });
      return _registration.token(requestPermission: requestPermission, callsEnabled: nativeAdviserCalls);
    });
    _registrations = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

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
        // Google's servers do not answer in mainland China: sign-out does not
        // wait on them, nor does anything queued behind it.
        // ignore: deprecated_member_use
        await FirebaseMessaging.instance.deleteToken().timeout(const Duration(seconds: 10));
      } catch (_) {
        // Signed out all the same; the server forgot the token already.
      }
    }
    if (_localReady) await _local.cancelAll();
    await StudentCalls.instance.end();
    await FlutterCallkitIncoming.endAllCalls();
    _calendarState = {'enabled': false};
    await _saveCalendarState();
    _adhanState = {'enabled': false};
    await _saveAdhanState();
  }

  Future<void> _openLocal(String? payload) async {
    if (payload == '/contact/chat') return openChat();
    if (payload == '/calendar') return openCalendar();
    // A call to prayer opens the portal's Prayer times (its adhan player and the day's times).
    if (payload == '/prayer') return openUpdate('/prayer');
    if (payload != null && payload.startsWith('/notifications?event=')) {
      final route = studentUpdateRoute({'type': 'student_update', 'route': '/notifications', 'eventId': payload.substring('/notifications?event='.length)});
      if (route != null) await openUpdate(route);
    }
  }

  Future<File> _calendarFile() async => File('${(await _directory()).path}/calendar-reminders.json');
  Future<void> _saveCalendarState() async {
    await (await _calendarFile()).writeAsString(jsonEncode(_calendarState));
  }
  Future<void> _cancelCalendar() async {
    for (var i = 0; i < 60; i++) { await _local.cancel(id: 1900000000 + i); }
  }
  Future<void> _clearCalendar() async {
    await _cancelCalendar();
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
    // Another student's reminders go. A phone with none (no owner kept) has
    // nothing to cancel: this used to cancel sixty notifications on every
    // call, each a write of Android's whole schedule, the adhan's included.
    final kept = _calendarState!['owner'];
    if (action == 'calendarClear') { await _clearCalendar(); return {'supported': true, 'enabled': false, 'count': 0}; }
    if (kept != owner && (kept != null || _calendarState!['enabled'] == true)) await _clearCalendar();
    if (action == 'calendarEnable') {
      final ios = await _local.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()?.requestPermissions(alert: true, badge: false, sound: true);
      final android = await _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
      _calendarState = {'owner': owner, 'enabled': (ios ?? android) == true};
      await _saveCalendarState();
    }
    if (action == 'calendarSync' && _calendarState!['enabled'] == true) {
      final raw = input['reminders'];
      if (raw is! List || raw.length > 60) return {'error': 'Invalid calendar reminders'};
      // The reminders are written in the student's language: a new language
      // writes them again (English keeps the fingerprint it always had).
      final language = _language;
      final fingerprint = language == AppLanguage.en
          ? jsonEncode(raw)
          : '${language.code}:${jsonEncode(raw)}';
      if (_calendarState!['fingerprint'] != fingerprint) {
        final enabled = _calendarState!['enabled'];
        // The old reminders go and the new ones are written; "off" is never
        // kept in between, and one reminder the phone refuses (its time came
        // while the others were being written) does not stop the rest. Through
        // 1.2.40 (71) either left the student's reminders off for good.
        await _cancelCalendar();
        final times = validCalendarTimes(raw, DateTime.now()).take(60).toList();
        final written = <DateTime>[];
        for (var i = 0; i < times.length; i++) {
          try {
            await _local.zonedSchedule(id: 1900000000 + i, title: pushTitle.of(language), body: pushCalendarBody.of(language),
              scheduledDate: tz.TZDateTime.from(times[i].toUtc(), tz.UTC),
              notificationDetails: NotificationDetails(android: AndroidNotificationDetails('student_calendar', calendarChannel.of(language), importance: Importance.high, icon: 'ic_stat_message'), iOS: const DarwinNotificationDetails()),
              androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle, payload: '/calendar');
            written.add(times[i]);
          } catch (error) {
            unawaited(_problems.report('push: calendar reminder not scheduled: ${describePushError(error)}'));
          }
        }
        // The fingerprint is kept only for a schedule written whole: one with
        // a reminder missing is written again at the next sync.
        _calendarState = {'owner': owner, 'enabled': enabled,
          'fingerprint': written.length == times.length ? fingerprint : null, 'count': written.length,
          'through': written.isEmpty ? null : written.last.toUtc().toIso8601String()};
        await _saveCalendarState();
      }
    }
    return {'supported': true, 'enabled': _calendarState!['enabled'] == true, 'permission': _calendarState!['enabled'] == true,
      'count': _calendarState!['count'] ?? 0, 'through': _calendarState!['through']};
  });

  // ── The adhan (student_adhan.dart) ──────────────────────────────────────
  /// One channel per sound: a channel's sound is fixed once Android has made it.
  Future<void> _createAdhanChannels(AppLanguage language) async {
    final android = _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;
    await android.createNotificationChannel(AndroidNotificationChannel(
      adhanChannelId, adhanChannelName.of(language),
      description: adhanChannelDescription.of(language),
      importance: Importance.high,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound(adhanAndroidSound),
    ));
    await android.createNotificationChannel(AndroidNotificationChannel(
      adhanFajrChannelId, adhanFajrChannelName.of(language),
      description: adhanChannelDescription.of(language),
      importance: Importance.high,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound(adhanAndroidFajrSound),
    ));
  }

  Future<File> _adhanFile() async => File('${(await _directory()).path}/adhan-calls.json');
  Future<void> _saveAdhanState() async {
    try {
      await (await _adhanFile()).writeAsString(jsonEncode(_adhanState));
    } catch (_) {
      // Kept for this run; the next sync writes it again.
    }
  }

  Future<void> _cancelAdhan() async {
    for (var i = 0; i < adhanMaxCalls; i++) {
      await _local.cancel(id: adhanNotificationBase + i);
    }
  }

  /// iOS plays a notification's sound only from the bundle or Library/Sounds: the recording is copied
  /// there once (again if its size changed with a new build).
  Future<bool> _installIosAdhanSound() async {
    if (!Platform.isIOS) return true;
    try {
      final bytes = (await rootBundle.load(adhanIosSoundAsset)).buffer.asUint8List();
      final sounds = Directory('${(await getLibraryDirectory()).path}/Sounds');
      await sounds.create(recursive: true);
      final file = File('${sounds.path}/$adhanIosSound');
      if (!await file.exists() || await file.length() != bytes.length) await file.writeAsBytes(bytes, flush: true);
      return true;
    } catch (error) {
      unawaited(_problems.report('push: adhan sound not installed: ${describePushError(error)}'));
      return false;
    }
  }

  Future<bool> _adhanPermission() async {
    try {
      if (Platform.isIOS) {
        final options = await _local.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()?.checkPermissions();
        return options?.isEnabled == true;
      }
      return await _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.areNotificationsEnabled() == true;
    } catch (_) {
      return false;
    }
  }

  /// Android 12 and later: whether a call can land on its minute ("Alarms and reminders").
  Future<bool?> _adhanExact() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.canScheduleExactNotifications();
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> _adhanStatus() async => {
        'supported': true,
        'enabled': (_adhanState?['count'] ?? 0) > 0,
        'permission': await _adhanPermission(),
        'count': _adhanState?['count'] ?? 0,
        'through': _adhanState?['through'],
        'exact': await _adhanExact(),
      };

  Future<void> _clearAdhan() async {
    await _cancelAdhan();
    _adhanState = {'enabled': false};
    await _saveAdhanState();
  }

  /// `adhanStatus`, `adhanEnable` (asks to notify, inside the student's tap), `adhanSync` (the calls,
  /// written again only when they change), `adhanClear`, `adhanExactAlarms` (Android's settings page).
  Future<Map<String, dynamic>> adhan(String action, Map<dynamic, dynamic> input) => _serial(() async {
    await start();
    if (!_localReady) return {'supported': false};
    final owner = '${input['owner']}';
    if (!RegExp(r'^[1-9][0-9]{0,14}$').hasMatch(owner)) return {'error': 'Invalid adhan account'};
    if (_adhanState == null) {
      try { _adhanState = Map<String, dynamic>.from(jsonDecode(await (await _adhanFile()).readAsString()) as Map); }
      catch (_) { _adhanState = {'enabled': false}; }
    }
    // Another student signed in on this phone: the previous one's calls go.
    if (_adhanState!['owner'] != null && _adhanState!['owner'] != owner) await _clearAdhan();
    switch (action) {
      case 'adhanClear':
        await _clearAdhan();
      case 'adhanEnable':
        await _local.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()?.requestPermissions(alert: true, badge: false, sound: true);
        await _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
      case 'adhanExactAlarms':
        await _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestExactAlarmsPermission();
      case 'adhanSync':
        final raw = input['calls'];
        if (raw is! List || raw.length > adhanMaxCalls) return {'error': 'Invalid adhan calls'};
        final calls = validAdhanCalls(raw, DateTime.now());
        // The schedule and how it is delivered: a language, a new phone setting or a new build writes it again.
        final exact = await _adhanExact() == true;
        final given = '${input['fingerprint']}';
        final fingerprint = '${given.length > 6000 ? given.substring(0, 6000) : given}|exact:$exact|v1';
        if (_adhanState!['fingerprint'] != fingerprint || _adhanState!['owner'] != owner) {
          await _cancelAdhan();
          final soundReady = await _installIosAdhanSound();
          final language = _language;
          // A call the phone refuses (its time came while the others were
          // being written) must not leave every later prayer silent.
          final written = <AdhanCall>[];
          for (var i = 0; i < calls.length; i++) {
            final call = calls[i];
            try {
            await _local.zonedSchedule(
              id: adhanNotificationBase + i,
              title: call.title,
              body: call.body,
              scheduledDate: tz.TZDateTime.from(call.at, tz.UTC),
              notificationDetails: NotificationDetails(
                android: AndroidNotificationDetails(
                  call.full ? adhanChannelId : adhanFajrChannelId,
                  (call.full ? adhanChannelName : adhanFajrChannelName).of(language),
                  channelDescription: adhanChannelDescription.of(language),
                  importance: Importance.high,
                  priority: Priority.high,
                  playSound: true,
                  sound: RawResourceAndroidNotificationSound(call.full ? adhanAndroidSound : adhanAndroidFajrSound),
                  category: AndroidNotificationCategory.reminder,
                  icon: 'ic_stat_message',
                ),
                // Presented with its sound even while the app is open.
                iOS: DarwinNotificationDetails(
                  presentAlert: true, presentBanner: true, presentList: true, presentSound: true,
                  sound: soundReady ? adhanIosSound : null,
                ),
              ),
              androidScheduleMode: exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle,
              payload: '/prayer',
            );
              written.add(call);
            } catch (error) {
              unawaited(_problems.report('push: adhan call not scheduled: ${describePushError(error)}'));
            }
          }
          _adhanState = {
            // Kept only for a schedule written whole: one with a call
            // missing is written again at the next sync.
            'owner': owner, 'enabled': written.isNotEmpty,
            'fingerprint': written.length == calls.length ? fingerprint : null, 'count': written.length,
            'through': written.isEmpty ? null : written.last.at.toIso8601String(),
          };
          await _saveAdhanState();
        }
    }
    return _adhanStatus();
  });

  void dispose() {
    _disposed = true;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
  }
}
