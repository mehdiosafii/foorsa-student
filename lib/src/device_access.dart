import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'student_calls.dart';

const studentPermissions = [
  Permission.camera,
  Permission.microphone,
  Permission.locationWhenInUse,
];

/// Reminds once per opening, not on every inactive/resumed system prompt.
class DeviceAccess extends StatefulWidget {
  const DeviceAccess({super.key, required this.child, this.suppressed = false});
  final Widget child;

  /// The first-launch onboarding has just asked for the same access, so the
  /// reminder waits for the next opening.
  final bool suppressed;
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
  String? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  Future<void> _refresh() async {
    final values = await Future.wait(studentPermissions.map((p) => p.status));
    if (!mounted) return;
    setState(() => _statuses = Map.fromIterables(studentPermissions, values));
    if (values.every((s) => s.isGranted)) Navigator.of(context).pop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy) _refresh();
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
          setState(() => _error =
              'Open your phone Settings, then Foorsa Student, to allow access.');
        }
      } else if (!status.isRestricted) {
        final result = await permission.request();
        if (mounted) setState(() => _statuses[permission] = result);
        if (result.isPermanentlyDenied && mounted) {
          setState(
              () => _error = 'Access is blocked. Tap Settings to enable it.');
        }
      }
      // Preserve request results: some Android versions only expose permanent
      // denial from request(), not from status.
      if (mounted &&
          _statuses.length == 3 &&
          _statuses.values.every((s) => s.isGranted)) {
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Access is unavailable. You can continue and try again later.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _row(
      Permission permission, IconData icon, String title, String detail) {
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
          Text(restricted ? 'Restricted by your device settings.' : detail,
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
            child: Text(
                status?.isPermanentlyDenied == true ? 'Settings' : 'Allow'),
          ),
      ]),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Set up your device'),
        content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
              'Choose the access you want to enable. You can keep using Foorsa without it.'),
          _row(Permission.camera, Icons.camera_alt_outlined, 'Camera',
              'Scan documents and take photos.'),
          _row(Permission.microphone, Icons.mic_none, 'Microphone',
              'Calls, voice messages and videos.'),
          _row(
              Permission.locationWhenInUse,
              Icons.location_on_outlined,
              'Location while using the app',
              'Prayer times, local weather and nearby places such as supermarkets.'),
          if (_error != null)
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 8),
          const Text(
              'Missing access will be offered again next time you open the app.',
              style: TextStyle(fontSize: 12)),
        ])),
        actions: [
          TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              child: const Text('Continue'))
        ],
      );
}
