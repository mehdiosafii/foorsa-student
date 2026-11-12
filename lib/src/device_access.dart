import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'app_language.dart';
import 'student_calls.dart';

/// What the reminder says, in the student's language.
const _title = Words('Set up your device', 'Configurez votre appareil',
    'إعداد جهازك');
const _intro = Words(
    'Choose the access you want to enable. You can keep using Foorsa without it.',
    'Choisissez les accès à activer. Vous pouvez continuer à utiliser Foorsa '
        'sans eux.',
    'اختر الأذونات التي تريد تفعيلها. يمكنك مواصلة استخدام فرصة بدونها.');
const _camera = Words('Camera', 'Appareil photo', 'الكاميرا');
const _cameraDetail = Words('Scan documents and take photos.',
    'Scanner des documents et prendre des photos.',
    'المسح الضوئي للوثائق والتقاط الصور.');
const _microphone = Words('Microphone', 'Micro', 'الميكروفون');
const _microphoneDetail = Words('Calls, voice messages and videos.',
    'Appels, messages vocaux et vidéos.',
    'المكالمات والرسائل الصوتية والفيديوهات.');
const _location = Words('Location while using the app',
    'Position pendant l’utilisation de l’application',
    'الموقع أثناء استخدام التطبيق');
const _locationDetail = Words(
    'Prayer times, local weather and nearby places such as supermarkets.',
    'Heures de prière, météo locale et lieux proches, comme les '
        'supermarchés.',
    'أوقات الصلاة والطقس المحلي والأماكن القريبة مثل المتاجر الكبرى.');
const _restricted = Words('Restricted by your device settings.',
    'Limité par les réglages de votre appareil.',
    'مقيّد من إعدادات جهازك.');
const _settings = Words('Settings', 'Réglages', 'الإعدادات');
const _allowAccess = Words('Allow', 'Autoriser', 'السماح');
const _later = Words(
    'Missing access will be offered again next time you open the app.',
    'Les accès manquants vous seront proposés à la prochaine ouverture de '
        'l’application.',
    'ستُعرض عليك الأذونات الناقصة مجددًا عند فتح التطبيق في المرة القادمة.');
const _continue = Words('Continue', 'Continuer', 'متابعة');
const _openSettings = Words(
    'Open your phone Settings, then Foorsa Student, to allow access.',
    'Ouvrez les Réglages de votre téléphone, puis Foorsa Student, pour '
        'autoriser l’accès.',
    'افتح إعدادات هاتفك، ثم Foorsa Student، للسماح بالوصول.');
const _blocked = Words('Access is blocked. Tap Settings to enable it.',
    'L’accès est bloqué. Touchez Réglages pour l’activer.',
    'الوصول محظور. اضغط على الإعدادات لتفعيله.');
const _unavailable = Words(
    'Access is unavailable. You can continue and try again later.',
    'L’accès est indisponible. Vous pouvez continuer et réessayer plus tard.',
    'الوصول غير متاح. يمكنك المتابعة وإعادة المحاولة لاحقًا.');

const studentPermissions = [
  Permission.camera,
  Permission.microphone,
  Permission.locationWhenInUse,
];

/// Reminds once per opening, not on every inactive/resumed system prompt.
class DeviceAccess extends StatefulWidget {
  const DeviceAccess(
      {super.key, required this.child, this.suppressed = false, this.after});
  final Widget child;

  /// The first-launch onboarding has just asked for the same access, so the
  /// reminder waits for the next opening.
  final bool suppressed;

  /// What the reminder waits for before it opens, [patience] at most: the
  /// shell's web view, made and on the screen (portal_handover.dart). It is
  /// made as the app opens, on the thread the reminder comes in on, so one
  /// opening meanwhile would stop half-way in.
  final Future<void>? after;

  /// As long as the loader may wait for the web view, and the moment after
  /// it (BootLoaderGate.restLimit and settle).
  static const patience = Duration(milliseconds: 1300);
  @override
  State<DeviceAccess> createState() => _DeviceAccessState();
}

class _DeviceAccessState extends State<DeviceAccess>
    with WidgetsBindingObserver {
  bool _checking = false, _backgrounded = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && !_checking) {
      _backgrounded = true;
    }
    if (state == AppLifecycleState.resumed && _backgrounded) {
      _backgrounded = false;
      _check();
    }
  }

  Future<void> _check() async {
    if (widget.suppressed || _checking || !mounted ||
        StudentCalls.instance.invite != null) { return; }
    _checking = true;
    try {
      final statuses =
          await Future.wait(studentPermissions.map((p) => p.status));
      if (!mounted ||
          statuses.every((s) => s.isGranted) ||
          StudentCalls.instance.invite != null) { return; }
      final after = widget.after;
      if (after != null) {
        await after.timeout(DeviceAccess.patience, onTimeout: () {});
        if (!mounted || StudentCalls.instance.invite != null) return;
      }
      await showDialog<void>(
        context: context,
        builder: (_) => const _AccessDialog(),
      );
    } catch (_) {
      // Unavailable hardware/plugin must never prevent opening the portal.
    } finally {
      _checking = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _AccessDialog extends StatefulWidget {
  const _AccessDialog();
  @override
  State<_AccessDialog> createState() => _AccessDialogState();
}

class _AccessDialogState extends State<_AccessDialog>
    with WidgetsBindingObserver {
  Map<Permission, PermissionStatus> _statuses = {};
  bool _busy = false;
  Words? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  /// How long a system prompt's answer may follow the app's return before the
  /// request is taken for lost.
  static const _answerWait = Duration(seconds: 1);
  bool _closed = false;
  Timer? _lostAnswer;

  /// Closes the reminder, once. Allow's answer and the resume that follows
  /// the system prompt can both find every access granted while the dialog
  /// is still leaving (its State stays mounted for the exit); a second pop
  /// then took the app's own page off the screen and left it blank.
  void _close() {
    if (_closed || !mounted) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    _closed = true;
    Navigator.of(context).pop();
  }

  Future<void> _refresh() async {
    final values = await Future.wait(studentPermissions.map((p) => p.status));
    if (!mounted || _closed) return;
    setState(() => _statuses = Map.fromIterables(studentPermissions, values));
    if (values.every((s) => s.isGranted)) _close();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (!_busy) {
      _refresh();
      return;
    }
    // Back from a system prompt with its answer still owed. Android gives no
    // answer when the prompt was interrupted (Home, then the app again) or
    // when another request was already open: the buttons would stay off for
    // good. A moment later the phone is asked where things stand instead.
    _lostAnswer?.cancel();
    _lostAnswer = Timer(_answerWait, () {
      if (!mounted || !_busy) return;
      setState(() => _busy = false);
      _refresh();
    });
  }

  Future<void> _allow(Permission permission) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final status = _statuses[permission] ?? await permission.status;
      if (status.isPermanentlyDenied) {
        if (!await openAppSettings() && mounted) {
          setState(() => _error = _openSettings);
        }
      } else if (!status.isRestricted) {
        final result = await permission.request();
        if (mounted) setState(() => _statuses[permission] = result);
        if (result.isPermanentlyDenied && mounted) {
          setState(() => _error = _blocked);
        }
      }
      // Preserve request results: some Android versions only expose permanent
      // denial from request(), not from status.
      if (mounted &&
          _statuses.length == 3 &&
          _statuses.values.every((s) => s.isGranted)) {
        _close();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = _unavailable);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _row(Permission permission, IconData icon, String title,
      String detail, AppLanguage language) {
    final status = _statuses[permission];
    final granted = status?.isGranted == true;
    final restricted = status?.isRestricted == true;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Icon(icon, color: const Color(0xff183250)),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(restricted ? _restricted.of(language) : detail,
              style: Theme.of(context).textTheme.bodySmall),
        ])),
        const SizedBox(width: 8),
        if (granted)
          const Icon(Icons.check_circle, color: Colors.green)
        else
          TextButton(
            onPressed: _busy || restricted || status == null
                ? null
                : () => _allow(permission),
            child: Text((status?.isPermanentlyDenied == true
                    ? _settings
                    : _allowAccess)
                .of(language)),
          ),
      ]),
    );
  }

  @override
  void dispose() {
    _lostAnswer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final language = AppLanguageScope.of(context);
    return Directionality(
      textDirection: language.direction,
      child: AlertDialog(
        title: Text(_title.of(language)),
        content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_intro.of(language)),
          _row(Permission.camera, Icons.camera_alt_outlined,
              _camera.of(language), _cameraDetail.of(language), language),
          _row(Permission.microphone, Icons.mic_none, _microphone.of(language),
              _microphoneDetail.of(language), language),
          _row(Permission.locationWhenInUse, Icons.location_on_outlined,
              _location.of(language), _locationDetail.of(language), language),
          if (_error != null)
            Text(_error!.of(language),
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 8),
          Text(_later.of(language), style: const TextStyle(fontSize: 12)),
        ])),
        actions: [
          // Never off: the student can always go on without the access,
          // whatever a system prompt is doing.
          TextButton(
              onPressed: _close, child: Text(_continue.of(language)))
        ],
      ),
    );
  }
}
