/// The WebView shell around https://student.foorsa.ma.
///
/// Student edition: adviser-message push and incoming adviser calls, and no pull-to-refresh — the
/// portal refreshes itself quietly every 5 minutes, so the gesture would
/// only offer a jarring full reload. Uploads, downloads,
/// theme-matched status bar (via the FoorsaShellTheme bridge message), and
/// sensible back handling.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:url_launcher/url_launcher.dart' as launcher;

import 'boot_loader_gate.dart';
import 'config.dart';
import 'embedded_navigation.dart';
import 'flicker_spinner.dart';
import 'shell_appearance.dart';
import 'shell_capabilities.dart';
import 'shell_haptics.dart';
import 'shell_screens.dart';
import 'guided_scanner/guided_scan_page.dart';
import 'guided_scanner/native_document_scanner.dart';
import 'guided_scanner/scan_document_profile.dart';
import 'onboarding/onboarding_gate.dart';
import 'portal_handover.dart';
import 'trusted_portal.dart';
import 'student_push.dart';
import 'student_calls.dart';
import 'student_biometrics.dart';
import 'chat_viewport.dart';

class ShellPage extends StatefulWidget {
  const ShellPage({
    super.key,
    this.appearance,
    this.webViewDelay = const Duration(milliseconds: 300),
  });

  /// The theme the portal last said the student chose (read before the first
  /// frame, main.dart); null follows the phone.
  final ShellAppearance? appearance;

  /// When the WebView is created. Its platform-view set-up holds the UI
  /// thread for a moment, so a first launch waits until the onboarding's
  /// takeoff has flown (onboarding/onboarding_gate.dart).
  final Duration webViewDelay;

  @override
  State<ShellPage> createState() => _ShellPageState();
}


class _ShellPageState extends State<ShellPage> {
  String? _pushOpenPending;
  late final StudentPush _push = StudentPush(
    openChat: () async {
      _pushOpenPending = '/contact/chat';
      await _openPushChat();
    },
    openUpdate: (route) async { _pushOpenPending = route; await _openPushChat(); },
    openCalendar: () async { _pushOpenPending = '/calendar'; await _openPushChat(); },
    chatIsVisible: () async {
      final url = await _controller?.getUrl();
      return _isTrustedPortal(url) && url?.path == '/contact/chat';
    },
  );
  Future<void> _openPushChat() async {
    final controller = _controller;
    if (_pushOpenPending == null || controller == null || !mounted) return;
    final destination = _pushOpenPending!;
    _pushOpenPending = null;
    await controller.loadUrl(urlRequest: URLRequest(
      url: WebUri(Uri.parse(AppConfig.baseUrl).resolve(destination).toString()),
    ));
  }
  InAppWebViewController? _controller;
  PackageInfo? _packageInfo;
  /// When the loading screen gives way to the portal (boot_loader_gate.dart).
  final BootLoaderGate _loader = BootLoaderGate();
  Timer? _holdTimer;
  /// Gone from the tree once its fade has ended.
  bool _loaderRemoved = false;
  late ShellAppearance? _appearance = widget.appearance;
  final ShellAppearanceStore _appearanceStore = ShellAppearanceStore();
  final ShellHaptics _haptics = ShellHaptics();
  bool _bootWebView = false;
  late bool _chatUnderStatusBar = chatUsesStatusBarArea(
    Uri.parse(AppConfig.baseUrl), AppConfig.baseUrl, isIOS: Platform.isIOS,
  );
  bool _loadFailed = false;
  /// The CURRENT navigation reported a main-frame error. Android fires
  /// onLoadStop even for failed loads, so "finished" alone must never be
  /// trusted as success — this flag is what onLoadStop consults.
  bool _errorThisLoad = false;
  /// While offline: quiet retry loop behind the branded overlay.
  Timer? _retryTimer;
  DateTime? _lastBackPress;
  Color _chromeColor = const Color(0xFF0B1220);
  String _scannerNonce = _newScannerNonce();
  bool _scanInProgress = false;
  final StudentBiometrics _biometrics = StudentBiometrics(
    origin: Uri.parse(AppConfig.baseUrl).origin,
  );
  final String _biometricBoot = _newScannerNonce();
  String _biometricScript = '';
  bool _biometricWasEnabled = false;
  bool _biometricBusy = false;
  int _biometricGeneration = 0;

  Future<void> _prepareBiometrics() async {
    // Nothing here prompts or reads a credential. The first frame always draws.
    await Future<void>.delayed(widget.webViewDelay);
    try {
      _biometricScript = await rootBundle.loadString('assets/biometric_session.js');
      await _biometrics.initialize();
    } catch (_) {
      // Never let unavailable preferences prevent ordinary password sign-in.
    }
    if (!mounted) return;
    // The portal always opens. With quick sign-in saved, its sign-in screen
    // offers Face ID or the fingerprint (and opens the prompt by itself once a
    // launch); the password stays underneath it.
    setState(() {
      _biometricWasEnabled = _biometrics.enabled;
      _bootWebView = true;
    });
  }

  UserScript _sessionScript() => UserScript(
    groupName: 'foorsa-biometric-session',
    source: _biometricScript.replaceFirst('const config = FOORSA_CONFIG;',
      'const config = ${jsonEncode({
        'origin': Uri.parse(AppConfig.baseUrl).origin,
        'boot': _biometricBoot,
        'protected': _biometricWasEnabled || _biometrics.enabled,
        'token': null,
      })};'),
    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
    forMainFrameOnly: true,
  );

  /// Reloads after quick sign-in is turned off must not clear the session.
  Future<void> _refreshSessionScript() async {
    final controller = _controller;
    if (controller == null) return;
    await controller.removeUserScriptsByGroupName(groupName: 'foorsa-biometric-session');
    await controller.addUserScript(userScript: _sessionScript());
  }

  void _biometricNotice(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  static bool _isCancellation(PlatformException error) {
    final text = '${error.code} ${error.message ?? ''}'.toLowerCase();
    return text.contains('cancel') || text.contains('-128');
  }

  Future<bool> _biometricSessionIsCurrent(String token, String nonce) async {
    final controller = _controller;
    if (!mounted || controller == null || nonce != _scannerNonce ||
        !_isTrustedPortal(await controller.getUrl())) {
      return false;
    }
    return await controller.evaluateJavascript(source:
      'location.origin === ${jsonEncode(Uri.parse(AppConfig.baseUrl).origin)} && '
      'window.__foorsaBiometrics?.matches(${jsonEncode(token)}) === true') == true;
  }

  Future<bool> _protectWebSession(String token) async => await _controller?.evaluateJavascript(source:
      'location.origin === ${jsonEncode(Uri.parse(AppConfig.baseUrl).origin)} && '
      'window.__foorsaBiometrics?.protect(${jsonEncode(token)}) === true') == true;

  Future<Object?> _handleBiometrics(List<dynamic> args) async {
    if (args.isEmpty || args.first is! Map) return null;
    final data = args.first as Map;
    final nonce = data['nonce'];
    if (nonce is! String || nonce != _scannerNonce ||
        !_isTrustedPortal(await _controller?.getUrl())) {
      return null;
    }
    switch (data['operation']) {
      case 'forget':
        // An expired or rejected session, or a deleted account. Signing out
        // keeps quick sign-in and never sends this.
        _biometricGeneration++;
        try { await _biometrics.forget(); } catch (_) { /* No credential is returned. */ }
        _biometricWasEnabled = false;
        try { await _refreshSessionScript(); } catch (_) { /* The web view may have closed. */ }
        return null;
      case 'status':
        final available = await _biometrics.available();
        return {'available': available, 'enabled': _biometrics.enabled, 'kind': _biometrics.kind};
      case 'unlock':
        return _unlockForPortal();
      case 'enable':
        return _enableForPortal(data['token'], nonce);
      case 'disable':
        _biometricGeneration++;
        try { await _biometrics.forget(); } catch (_) { return {'ok': false, 'reason': 'failed'}; }
        _biometricWasEnabled = false;
        try { await _refreshSessionScript(); } catch (_) { /* The next launch reads the stored state. */ }
        return {'ok': true};
      case 'session':
        return _offerAfterSignIn(data['token'], nonce);
    }
    return null;
  }

  /// The sign-in screen's Face ID / fingerprint button. The OS prompt reads the
  /// saved session; the server confirms it before the portal is handed it.
  Future<Map<String, Object?>> _unlockForPortal() async {
    if (_biometricBusy) return {'ok': false, 'reason': 'busy'};
    if (!_biometrics.enabled) return {'ok': false, 'reason': 'unavailable'};
    _biometricBusy = true;
    try {
      final StudentSession? session;
      try {
        session = await _biometrics.unlock();
      } on PlatformException catch (error) {
        return {'ok': false, 'reason': _isCancellation(error) ? 'cancelled' : 'failed'};
      }
      if (session == null) {
        // Nothing usable is saved any more (a changed Face ID or fingerprint
        // set removes it): the password is the way back in.
        await _biometrics.forget();
        _biometricWasEnabled = false;
        return {'ok': false, 'reason': 'expired'};
      }
      switch (await _biometrics.validate(session)) {
        case SessionValidity.unavailable:
          return {'ok': false, 'reason': 'offline'};
        case SessionValidity.expired:
          await _biometrics.forget();
          _biometricWasEnabled = false;
          return {'ok': false, 'reason': 'expired'};
        case SessionValidity.valid:
          _biometricWasEnabled = true;
          return {'ok': true, 'token': session.token};
      }
    } catch (_) {
      return {'ok': false, 'reason': 'failed'};
    } finally {
      _biometricBusy = false;
    }
  }

  /// Profile › Settings turned it on for the session open now.
  Future<Map<String, Object?>> _enableForPortal(Object? token, String nonce) async {
    if (token is! String) return {'ok': false, 'reason': 'unavailable'};
    if (_biometricBusy) return {'ok': false, 'reason': 'busy'};
    final session = StudentSession.parse(token);
    if (session == null) return {'ok': false, 'reason': 'unavailable'};
    final generation = _biometricGeneration;
    _biometricBusy = true;
    try {
      if (!await _biometricSessionIsCurrent(session.token, nonce)) return {'ok': false, 'reason': 'unavailable'};
      if (!await _biometrics.available()) return {'ok': false, 'reason': 'not_set_up'};
      switch (await _biometrics.validate(session)) {
        case SessionValidity.unavailable:
          return {'ok': false, 'reason': 'offline'};
        case SessionValidity.expired:
          return {'ok': false, 'reason': 'expired'};
        case SessionValidity.valid:
          break;
      }
      // A different account must never inherit the previous student's vault.
      if (_biometrics.enabled && !_biometrics.hasSavedSession(session)) await _biometrics.forget();
      if (!await _biometrics.save(session)) return {'ok': false, 'reason': 'failed'};
      if (generation != _biometricGeneration || !await _biometricSessionIsCurrent(session.token, nonce) ||
          !await _protectWebSession(session.token)) {
        await _biometrics.forget();
        return {'ok': false, 'reason': 'failed'};
      }
      _biometricWasEnabled = true;
      return {'ok': true};
    } on PlatformException catch (error) {
      return {'ok': false, 'reason': _isCancellation(error) ? 'cancelled' : 'failed'};
    } catch (_) {
      return {'ok': false, 'reason': 'failed'};
    } finally {
      _biometricBusy = false;
    }
  }

  /// After a password sign-in, once the server has confirmed the session.
  Future<Object?> _offerAfterSignIn(Object? token, String nonce) async {
    if (token is! String) return null;
    if (_biometricBusy) return {'retry': true};
    final session = StudentSession.parse(token);
    if (session == null) return null;
    final generation = _biometricGeneration;
    _biometricBusy = true;
    try {
      if (!await _biometricSessionIsCurrent(session.token, nonce)) return null;
      // A different account must never inherit the previous student's vault.
      if (_biometrics.enabled && !_biometrics.hasSavedSession(session)) await _biometrics.forget();
      if (!_biometrics.shouldOffer(session.owner) || !await _biometrics.available() ||
          await _biometrics.validate(session) != SessionValidity.valid ||
          !await _biometricSessionIsCurrent(session.token, nonce) || !mounted) {
        return null;
      }
      final enable = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
        scrollable: true,
        icon: Icon(_biometrics.kind == 'face' ? Icons.face_retouching_natural : Icons.fingerprint, size: 42),
        title: const Text('Sign in faster next time'),
        content: Text('Use ${_biometrics.label} to sign in to Foorsa on this phone. '
          'Your login is saved securely on this device. Foorsa never sees your face or fingerprint. '
          'You can turn this off in Profile › Settings.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text('Use ${_biometrics.label}')),
        ],
      ));
      if (generation != _biometricGeneration || !await _biometricSessionIsCurrent(session.token, nonce)) return null;
      if (enable != true) { await _biometrics.defer(session.owner); return null; }
      if (!await _biometrics.save(session)) return null;
      if (generation != _biometricGeneration || !await _biometricSessionIsCurrent(session.token, nonce)) {
        await _biometrics.forget();
        return null;
      }
      if (!await _protectWebSession(session.token)) {
        await _biometrics.forget();
        throw StateError('The session changed before it could be protected');
      }
      _biometricWasEnabled = true;
      _biometricNotice('${_biometrics.label} sign-in is on for this phone.');
    } catch (_) {
      _biometricNotice('Quick sign-in could not be saved. You can keep using your password.');
    } finally {
      _biometricBusy = false;
    }
    return null;
  }


  void _updateChatViewport(Uri? url) {
    final enabled = chatUsesStatusBarArea(
      url, AppConfig.baseUrl, isIOS: Platform.isIOS,
    );
    if (mounted && enabled != _chatUnderStatusBar) {
      setState(() => _chatUnderStatusBar = enabled);
    }
  }

  static String _newScannerNonce() {
    final random = math.Random.secure();
    return base64UrlEncode(
      List<int>.generate(24, (_) => random.nextInt(256)),
    );
  }

  Future<void> _publishScannerNonce(InAppWebViewController controller) async {
    final current = await controller.getUrl();
    if (!_isTrustedPortal(current)) return;
    final nonce = _scannerNonce;
    // evaluateJavascript executes in the main frame. A cross-origin iframe
    // cannot read this token, so it cannot request an official-document
    // capture through the old List-arguments JS handler in WebView 6.1.5.
    await controller.evaluateJavascript(source:
      'if (location.origin === ${jsonEncode(Uri.parse(AppConfig.baseUrl).origin)}) {'
      'Object.defineProperty(window, "__foorsaScannerNonce", '
      '{value: ${jsonEncode(nonce)}, configurable: true, enumerable: false});'
      // Quick sign-in talks to the shell with the same nonce. Until 1.2.21 it
      // was handed over only before a scan, so the sign-in offer never showed.
      'window.__foorsaBiometrics?.ready(${jsonEncode(nonce)});}'
    );
  }

  @override
  void initState() {
    super.initState();
    _push.onTokenChanged = () async {
      final controller = _controller;
      if (controller != null && _isTrustedPortal(await controller.getUrl())) {
        await controller.evaluateJavascript(source: "window.dispatchEvent(new Event('foorsa-push-token-changed'))");
      }
    };
    unawaited(_push.start());
    // Minimum splash so a fast load can't flash it; the screen otherwise
    // lifts when the portal has its first screen (BootLoaderGate).
    Timer(BootLoaderGate.minimum, () {
      if (mounted) setState(_loader.minimumPassed);
    });
    // Let the loading screen paint its first frame before the WebView's
    // platform-view init grabs the UI thread.
    unawaited(_prepareBiometrics());
    PackageInfo.fromPlatform().then((v) => _packageInfo = v);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ));
    });
  }


  // ── Offline handling ──────────────────────────────────────────────────────
  void _enterOffline() {
    if (!_loadFailed) {
      setState(() {
        _loadFailed = true;
        _loader.pageLoaded();
      });
    }
    // Auto-recover: retry quietly until a load succeeds. The branded offline
    // screen stays on top the whole time, so a failed retry can never flash
    // the WebView's own error page.
    _retryTimer ??=
        Timer.periodic(const Duration(seconds: 6), (_) => _retry());
  }

  void _retry() {
    _controller?.loadUrl(
        urlRequest: URLRequest(url: WebUri(AppConfig.baseUrl)));
  }

  void _exitOffline() {
    _retryTimer?.cancel();
    _retryTimer = null;
    if (_loadFailed) setState(() => _loadFailed = false);
  }

  bool _isInternal(Uri uri) {
    if (uri.scheme != 'http' && uri.scheme != 'https') return false;
    final host = uri.host.toLowerCase();
    if (AppConfig.internalHosts.contains(host)) return true;
    return AppConfig.internalHostSuffixes.any((s) => host.endsWith(s));
  }

  bool _isTrustedPortal(Uri? uri) {
    return isTrustedPortalOrigin(uri, AppConfig.baseUrl);
  }

  Future<bool> _openExternally(Uri uri) async {
    try {
      return await launcher.launchUrl(uri,
          mode: launcher.LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }


  // ── Native pick for portal uploads (FoorsaShellPickFile) ─────────────────
  static const _pickMimes = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'heic': 'image/heic',
    'pdf': 'application/pdf',
  };

  Map<String, dynamic> _fileEntry(String name, List<int> bytes) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    final mime = _pickMimes[ext] ?? 'application/octet-stream';
    return {
      'name': name,
      'mime': mime,
      'dataUrl': 'data:$mime;base64,${base64Encode(bytes)}',
    };
  }

  Future<Map<String, dynamic>> _pickForWeb(String mode, bool multiple) async {
    try {
      if (mode == 'camera' || mode == 'photo') {
        if (mode == 'camera') await ph.Permission.camera.request();
        final shot = await ImagePicker().pickImage(
          source: mode == 'camera' ? ImageSource.camera : ImageSource.gallery,
          maxWidth: 2600,
          imageQuality: 92,
        );
        if (shot == null) return {'cancelled': true};
        final bytes = await shot.readAsBytes();
        return {
          'files': [_fileEntry(shot.name, bytes)]
        };
      }
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'heic', 'pdf'],
        allowMultiple: multiple,
        withData: true,
      );
      if (res == null || res.files.isEmpty) return {'cancelled': true};
      final out = <Map<String, dynamic>>[];
      for (final f in res.files) {
        if (f.bytes == null) continue;
        out.add(_fileEntry(f.name, f.bytes!));
      }
      if (out.isEmpty) return {'cancelled': true};
      return {'files': out};
    } catch (_) {
      return {'cancelled': true};
    }
  }


  // ── Guided document capture (new shells; old shells keep the picker) ──
  Future<Map<String, dynamic>> _guidedScanForWeb(
      Object? request, Object? callingNonce) async {
    if (!mounted || (!Platform.isIOS && !Platform.isAndroid)) {
      return {'unsupported': true};
    }
    if (_scanInProgress) {
      return {'error': 'A scan is already open. Finish or cancel it first.'};
    }
    _scanInProgress = true;
    try {
      // The shell can navigate to external/embedded hosts. Only the exact
      // configured student portal may invoke a scanner that returns sensitive
      // passport/ID pixels over the JS bridge. The broad _isInternal() host
      // whitelist used for navigation is NOT sufficient authorization here.
      final activeUrl = await _controller?.getUrl();
      if (!_isTrustedPortal(activeUrl)) {
        return {'error': 'Open your document in the student portal to scan it.'};
      }
      if (callingNonce is! String || callingNonce.isEmpty ||
          callingNonce != _scannerNonce) {
        return {'error': 'The scanner connection expired. Close and reopen your document to try again.'};
      }
      final status = await ph.Permission.camera.request();
      if (!status.isGranted) {
        return {'error': 'Allow camera access for Foorsa Student in Settings, then try again.'};
      }
      if (!mounted) return {'cancelled': true};
      final profile = GuidedDocumentProfile.fromPortal(request);
      if (Platform.isIOS) {
        final native = await NativeDocumentScanner().scan(profile: profile);
        final destination = await _controller?.getUrl();
        if (!mounted || !_isTrustedPortal(destination) || callingNonce != _scannerNonce) {
          return {'cancelled': true};
        }
        // Only unsupported hardware uses the framed Flutter camera. Errors
        // and cancellation never silently switch to an ordinary photo picker.
        if (native['unsupported'] != true) return native;
      }
      final result = await Navigator.of(context).push<GuidedScanResult>(
        MaterialPageRoute<GuidedScanResult>(
          fullscreenDialog: true,
          builder: (_) => GuidedScanPage(
            profile: profile,
          ),
        ),
      );
      if (result == null) return {'cancelled': true};
      if (result.useLegacyCamera) {
        final picked = await _pickForWeb('camera', false);
        final destination = await _controller?.getUrl();
        if (!mounted || !_isTrustedPortal(destination) || callingNonce != _scannerNonce) {
          return {'cancelled': true};
        }
        return picked;
      }
      final picture = result.file;
      if (picture == null) return {'cancelled': true};
      final bytes = await picture.readAsBytes();
      // Recheck the trusted origin after the modal closes: a WebView
      // navigation during camera use must not receive official-document
      // pixels, even if the original request was from the correct host.
      final destination = await _controller?.getUrl();
      final samePortal = _isTrustedPortal(destination);
      // This is an official-document photo. The portal receives its bytes
      // immediately; don't retain a second unencrypted copy in camera temp.
      try {
        await File(picture.path).delete();
      } catch (_) {
        // Device camera providers may manage the temporary file themselves.
      }
      if (!samePortal || callingNonce != _scannerNonce) {
        return {'cancelled': true};
      }
      return {'files': [_fileEntry(picture.name, bytes)]};
    } catch (_) {
      return {'error': 'The document camera could not open. Please try again.'};
    } finally {
      _scanInProgress = false;
    }
  }

  // ── Native download (FoorsaShellDownloadFile) ────────────────────────────
  static const MethodChannel _downloadsChannel = MethodChannel('foorsa/downloads');

  Future<Map<String, dynamic>> _downloadForWeb(
      String url, String filename, String mime) async {
    final uri = Uri.tryParse(url);
    if (uri == null || url.isEmpty) return {'ok': false, 'error': 'bad url'};
    final messenger = ScaffoldMessenger.maybeOf(context);
    var spinnerUp = false;
    if (mounted) {
      spinnerUp = true;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: FlickerSpinner(size: 44)),
      );
    }
    void dismissSpinner() {
      if (spinnerUp && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      spinnerUp = false;
    }

    try {
      var name = filename.trim().isEmpty ? 'document' : filename.trim();
      name = name.replaceAll(RegExp('[^A-Za-z0-9._ ()-]'), '_');
      final tmpDir = await getTemporaryDirectory();
      final tmp = File('${tmpDir.path}/dl_$name');

      // Same fetch as the preview: the URL is pre-authenticated (?t=) and
      // already carries Content-Disposition — no extra headers.
      final client = HttpClient();
      try {
        final response = await client.getUrl(uri).then((r) => r.close());
        if (response.statusCode >= 400) {
          throw HttpException('HTTP ${response.statusCode}');
        }
        await response.pipe(tmp.openWrite());
      } finally {
        client.close();
      }

      var openPath = tmp.path;
      if (Platform.isAndroid) {
        bool? savedViaStore;
        try {
          savedViaStore = await _downloadsChannel.invokeMethod<bool>(
            'saveToDownloads',
            {
              'path': tmp.path,
              'name': name,
              'mime': mime.isEmpty ? 'application/octet-stream' : mime,
            },
          );
        } catch (e) {
          // On API 29+ a MediaStore failure cannot be repaired with a
          // legacy storage permission. Let the web layer use its fallback.
          throw FileSystemException(
            'Could not save to Downloads',
            tmp.path,
            e is OSError ? e : null,
          );
        }
        if (savedViaStore == null) {
          throw const FileSystemException('Could not save to Downloads');
        }
        if (!savedViaStore) {
          // API <= 28: direct write to the public Downloads directory.
          final st = await ph.Permission.storage.request();
          if (!st.isGranted) {
            dismissSpinner();
            return {'ok': false, 'error': 'storage permission denied'};
          }
          final downloads = Directory('/storage/emulated/0/Download');
          if (!await downloads.exists()) {
            await downloads.create(recursive: true);
          }
          final dot = name.lastIndexOf('.');
          final stem = dot > 0 ? name.substring(0, dot) : name;
          final ext = dot > 0 ? name.substring(dot) : '';
          var target = File('${downloads.path}/$name');
          var n = 1;
          while (await target.exists()) {
            target = File('${downloads.path}/$stem ($n)$ext');
            n += 1;
          }
          await tmp.copy(target.path);
          openPath = target.path;
        }
      } else {
        // iOS: no public Downloads folder — keep the file in the app's
        // documents, shown in Files under "On My iPhone › Foorsa Student"
        // (UIFileSharingEnabled + LSSupportsOpeningDocumentsInPlace). The
        // share sheet ships with the iOS build milestone.
        final docs = await getApplicationDocumentsDirectory();
        final dot = name.lastIndexOf('.');
        final stem = dot > 0 ? name.substring(0, dot) : name;
        final ext = dot > 0 ? name.substring(dot) : '';
        var target = File('${docs.path}/$name');
        var n = 1;
        while (await target.exists()) {
          target = File('${docs.path}/$stem ($n)$ext');
          n += 1;
        }
        await tmp.copy(target.path);
        openPath = target.path;
      }

      dismissSpinner();
      final path = openPath;
      messenger?.showSnackBar(SnackBar(
        content: Text(Platform.isIOS
            ? 'Saved in Files › Foorsa Student'
            : 'Saved in Downloads'),
        action: SnackBarAction(
          label: 'Open',
          onPressed: () {
            OpenFilex.open(path, type: mime.isEmpty ? null : mime);
          },
        ),
      ));
      return {'ok': true};
    } catch (e) {
      dismissSpinner();
      var reason = e.toString();
      if (reason.length > 90) reason = reason.substring(0, 90);
      return {'ok': false, 'error': reason};
    }
  }


  // ── In-app file preview (FoorsaShellPreviewFile) ─────────────────────────
  bool _previewBusy = false;

  Future<void> _previewFile(String url, String filename, String mime) async {
    if (_previewBusy) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    _previewBusy = true;
    final messenger = ScaffoldMessenger.maybeOf(context);
    var spinnerUp = false;
    if (mounted) {
      spinnerUp = true;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: FlickerSpinner(size: 44)),
      );
    }
    void dismissSpinner() {
      if (spinnerUp && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      spinnerUp = false;
    }

    try {
      final dir = await getTemporaryDirectory();
      var name = filename.trim().isEmpty ? 'document' : filename.trim();
      name = name.replaceAll(RegExp('[^A-Za-z0-9._ -]'), '_');
      final file = File('${dir.path}/$name');

      final client = HttpClient();
      try {
        // Two different applicant documents can share a filename and size.
        // Fetch the authenticated URL every time so a prior preview never
        // appears in place of the document the student just opened.
        final response = await client.getUrl(uri).then((r) => r.close());
        if (response.statusCode >= 400) {
          throw HttpException('HTTP ${response.statusCode}');
        }
        await response.pipe(file.openWrite());
      } finally {
        client.close();
      }

      dismissSpinner();
      if (!mounted) return;
      final kind = mime.toLowerCase().trim();
      if (kind == 'application/pdf' || name.toLowerCase().endsWith('.pdf')) {
        await Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => _PdfPreviewPage(path: file.path, title: name)));
      } else if (kind.startsWith('image/')) {
        await Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => _ImagePreviewPage(path: file.path, title: name)));
      } else {
        final result =
            await OpenFilex.open(file.path, type: kind.isEmpty ? null : kind);
        if (result.type != ResultType.done) {
          messenger?.showSnackBar(const SnackBar(
              content: Text('This file could not be opened')));
        }
      }
    } catch (_) {
      dismissSpinner();
      messenger?.showSnackBar(
          const SnackBar(content: Text('This file could not be opened')));
    } finally {
      _previewBusy = false;
    }
  }

  Future<void> _download(DownloadStartRequest req) async {
    final uri = req.url;
    final segs = uri.pathSegments;
    final name = (req.suggestedFilename ??
            (segs.isEmpty ? 'download' : segs.last))
        .replaceAll(RegExp('[/\\\\]'), '_');
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(content: Text('Downloading $name…')));
    try {
      final cookies = await CookieManager.instance().getCookies(url: uri);
      final cookieHeader =
          cookies.map((c) => '${c.name}=${c.value}').join('; ');
      final client = HttpClient();
      final request = await client.getUrl(uri);
      if (cookieHeader.isNotEmpty) request.headers.set('Cookie', cookieHeader);
      request.headers.set(HttpHeaders.userAgentHeader,
          '${AppConfig.userAgentProduct}/${_packageInfo?.version ?? ''}');
      final response = await request.close();
      if (response.statusCode >= 400) {
        throw HttpException('HTTP ${response.statusCode}');
      }
      final dir = await getApplicationDocumentsDirectory();
      final downloads = Directory('${dir.path}/FoorsaDownloads');
      if (!await downloads.exists()) await downloads.create(recursive: true);
      final file = File('${downloads.path}/$name');
      await response.pipe(file.openWrite());
      client.close();
      messenger?.hideCurrentSnackBar();
      final result = await OpenFilex.open(file.path);
      if (result.type != ResultType.done) {
        messenger?.showSnackBar(SnackBar(content: Text('Saved: $name')));
      }
    } catch (_) {
      messenger?.hideCurrentSnackBar();
      await _openExternally(uri);
    }
  }


  /// Whether the loading and offline screens are dark: the student's choice
  /// in the portal, else the phone's.
  bool _isDark(BuildContext context) => _appearance == null
      ? MediaQuery.platformBrightnessOf(context) == Brightness.dark
      : _appearance == ShellAppearance.dark;

  void _applyAppearance(Object? value) {
    final next = ShellAppearanceStore.parse(value);
    if (next == _appearance || !mounted) return;
    setState(() => _appearance = next);
    _appearanceStore.write(next);
  }

  void _portalLoading(Object? message) {
    if (!mounted) return;
    var startHold = false;
    setState(() => startHold = _loader.portalSays(message));
    if (startHold) {
      _holdTimer ??= Timer(BootLoaderGate.holdLimit, () {
        if (mounted) setState(_loader.holdExpired);
      });
    }
  }

  void _applyChromeColor(String css) {
    final s = css.trim().toLowerCase();
    Color? c;
    if (s.startsWith('rgb')) {
      final open = s.indexOf('(');
      final close = s.indexOf(')');
      if (open > 0 && close > open) {
        final parts = s.substring(open + 1, close).split(',');
        if (parts.length >= 3) {
          final r = int.tryParse(parts[0].trim());
          final g = int.tryParse(parts[1].trim());
          final b = int.tryParse(parts[2].trim());
          double a = 1.0;
          if (parts.length >= 4) {
            a = double.tryParse(parts[3].trim()) ?? 1.0;
          }
          if (r != null && g != null && b != null && a >= 0.4) {
            c = Color.fromARGB(255, r, g, b);
          }
        }
      }
    } else if (s.startsWith('#') && s.length == 7) {
      final v = int.tryParse(s.substring(1), radix: 16);
      if (v != null) c = Color(0xFF000000 | v);
    }
    if (c == null || c == _chromeColor || !mounted) return;
    final picked = c;
    setState(() => _chromeColor = picked);
    _chromeReported = true;
    _applyStatusBar();
  }

  bool _chromeReported = false;

  /// The status bar for the page's colour. While the first-launch onboarding
  /// is over the portal its night owns the status bar, so the colour waits.
  void _applyStatusBar() {
    if (OnboardingScope.isActive(context)) return;
    final lightBg = _chromeColor.computeLuminance() > 0.5;
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: lightBg ? Brightness.dark : Brightness.light,
      statusBarBrightness: lightBg ? Brightness.light : Brightness.dark,
    ));
  }

  bool _onboardingShown = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final onboarding = OnboardingScope.activeOf(context);
    // The onboarding has just gone: the portal's colour takes the bar back.
    if (_onboardingShown && !onboarding && _chromeReported) _applyStatusBar();
    _onboardingShown = onboarding;
  }

  Future<Map<String, dynamic>> _handleBridgeCall(List<dynamic> args) async {
    String action = '';
    if (args.isNotEmpty && args[0] is Map) {
      action = ((args[0] as Map)['action'] ?? '').toString();
    }
    switch (action) {
      case 'incomingCall':
        if (!_isTrustedPortal(await _controller?.getUrl()) || (args[0] as Map)['nonce'] != _scannerNonce) return {'ok': false};
        final invite = Map<String, dynamic>.from(args[0] as Map);
        if (!validStudentCall(invite)) return {'ok': false};
        await showStudentCall(invite);
        return {'ok': true};
      case 'getPushToken':
        if (!_isTrustedPortal(await _controller?.getUrl()) || (args[0] as Map)['nonce'] != _scannerNonce) return {'token': null, 'status': 'pending'};
        return _push.token();
      case 'clearPushToken':
        if (!_isTrustedPortal(await _controller?.getUrl()) || (args[0] as Map)['nonce'] != _scannerNonce) return {'ok': false};
        await _push.clear();
        return {'ok': true};
      case 'calendarStatus':
      case 'calendarEnable':
      case 'calendarClear':
      case 'calendarSync':
        if (!_isTrustedPortal(await _controller?.getUrl()) || (args[0] as Map)['nonce'] != _scannerNonce) return {'supported': false};
        return _push.calendar(action, args[0] as Map);
      case 'appInfo':
        return {
          'platform': Platform.isIOS ? 'ios' : 'android',
          'version': _packageInfo?.version,
        };
      default:
        return {'error': 'unknown action'};
    }
  }

  /// Only the trusted portal may use camera/microphone after OS consent.
  Future<PermissionResponse> _onPermissionRequest(
      InAppWebViewController controller, PermissionRequest request) async {
    var granted = _isTrustedPortal(request.origin) &&
        _isTrustedPortal(await controller.getUrl()) &&
        request.resources.isNotEmpty &&
        request.resources.every((r) => r == PermissionResourceType.CAMERA ||
            r == PermissionResourceType.MICROPHONE);
    if (granted) {
      for (final resource in request.resources) {
        final permission = resource == PermissionResourceType.CAMERA
            ? ph.Permission.camera : ph.Permission.microphone;
        if (!(await permission.request()).isGranted) { granted = false; break; }
      }
    }
    return PermissionResponse(resources: request.resources,
      action: granted ? PermissionResponseAction.GRANT : PermissionResponseAction.DENY);
  }

  /// The portal's prayer times ask for the phone's location and compute the
  /// times on the phone. Only portal pages may ask (Android; iOS asks through
  /// WebKit with NSLocationWhenInUseUsageDescription).
  Future<GeolocationPermissionShowPromptResponse> _onGeolocationPrompt(
      InAppWebViewController controller, String origin) async {
    var allow = false;
    final uri = Uri.tryParse(origin);
    if (uri != null && _isInternal(uri)) {
      allow = (await ph.Permission.locationWhenInUse.request()).isGranted;
    }
    return GeolocationPermissionShowPromptResponse(
        origin: origin, allow: allow, retain: allow);
  }

  Future<void> _handleBack() async {
    final c = _controller;
    if (c != null && await c.canGoBack()) {
      await c.goBack();
      return;
    }
    if (!mounted) return;
    final now = DateTime.now();
    if (_lastBackPress != null &&
        now.difference(_lastBackPress!) < const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return;
    }
    _lastBackPress = now;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
          content: Text('Press back again to exit'),
          duration: Duration(seconds: 2)),
    );
  }

  @override
  void dispose() {
    _biometricGeneration++;
    _biometrics.dispose();
    _push.dispose();
    _retryTimer?.cancel();
    _holdTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        // The first-launch onboarding answers the back button while it is up.
        if (!didPop && !OnboardingScope.isActive(context)) _handleBack();
      },
      child: Scaffold(
        backgroundColor: _chromeColor,
        body: Stack(
          children: [
            SafeArea(
              // The onboarding finds the sign-in's arrow through it.
              key: PortalHandover.instance.webViewArea,
              // Chat owns its top inset through viewport-fit=cover and CSS
              // env(safe-area-inset-top), including the translucent backdrop.
              top: !_chatUnderStatusBar,
              bottom: false,
              child: !_bootWebView
                  ? const SizedBox.expand()
                  : InAppWebView(
                initialUserScripts: UnmodifiableListView([_sessionScript()]),
                initialUrlRequest: URLRequest(url: WebUri(AppConfig.baseUrl)),
                initialSettings: InAppWebViewSettings(
                  // The portal is remote; no file:// page is ever loaded, and
                  // uploads come back as data URLs from the native picker.
                  allowFileAccess: false,
                  geolocationEnabled: true,
                  javaScriptEnabled: true,
                  javaScriptCanOpenWindowsAutomatically: true,
                  supportMultipleWindows: true,
                  useShouldOverrideUrlLoading: true,
                  useOnDownloadStart: true,
                  mediaPlaybackRequiresUserGesture: false,
                  allowsInlineMediaPlayback: true,
                  allowsBackForwardNavigationGestures: true,
                  applicationNameForUserAgent: AppConfig.userAgentProduct,
                  transparentBackground: true,
                  // Heavy-animation support: keep the web content on the GPU
                  // path so CSS transforms/filters composite at the display's
                  // full rate (60/90/120Hz) instead of falling back to
                  // software rasterisation.
                  hardwareAcceleration: true,
                  useHybridComposition: true,
                  // Rasterise slightly beyond the viewport so fast scrolling
                  // and large moving surfaces don't reveal unpainted tiles.
                  offscreenPreRaster: true,
                  // iOS draws its form toolbar (previous, next, done) above the
                  // keyboard in a web view. The portal's fields carry their own
                  // controls, and in the live chat the bar sat between the
                  // composer and the keyboard (the owner, 25 Oct 2026).
                  disableInputAccessoryView: true,
                ),
                onWebViewCreated: (controller) {
                  _controller = controller;
                  PortalHandover.instance.controller = controller;
                  controller.addJavaScriptHandler(
                    handlerName: 'FoorsaStudentBiometrics',
                    callback: _handleBiometrics,
                  );
                  controller.addJavaScriptHandler(
                    handlerName: AppConfig.bridgeName,
                    callback: _handleBridgeCall,
                  );
                  controller.addJavaScriptHandler(
                    handlerName: 'FoorsaShellTheme',
                    callback: (args) {
                      if (args.isNotEmpty) {
                        _applyChromeColor(args[0].toString());
                      }
                      return null;
                    },
                  );
                  // The theme the student chose ('light', 'dark', 'system'),
                  // kept for the next start's loading screen.
                  controller.addJavaScriptHandler(
                    handlerName: 'FoorsaShellAppearance',
                    callback: (args) {
                      _applyAppearance(args.isNotEmpty ? args[0] : null);
                      return null;
                    },
                  );
                  // 'hold': the portal shows its own loader until its first
                  // screen; 'ready': it has one (BootLoaderGate).
                  controller.addJavaScriptHandler(
                    handlerName: 'FoorsaShellLoading',
                    callback: (args) {
                      _portalLoading(args.isNotEmpty ? args[0] : null);
                      return null;
                    },
                  );
                  // Opens a URL OUTSIDE the WebView, letting Android pick the
                  // native app (wa.me -> WhatsApp, ig.me -> Instagram, ...).
                  // Called by the portal's Contact button.
                  controller.addJavaScriptHandler(
                    handlerName: 'FoorsaShellOpenUrl',
                    callback: (args) async {
                      if (args.isNotEmpty) {
                        final uri = Uri.tryParse(args[0].toString());
                        if (uri != null && await _openExternally(uri)) {
                          return true;
                        }
                      }
                      // The portal falls back to same-frame navigation only
                      // when this bridge call rejects.
                      throw PlatformException(
                          code: 'external_open_failed',
                          message: 'Could not open external URL');
                    },
                  );
                  // Tactile tick for portal button presses —
                  // navigator.vibrate is unreliable inside the WebView.
                  // What this build can do, so the portal can tell it from
                  // older builds (shell_capabilities.dart).
                  controller.addJavaScriptHandler(
                    handlerName: 'FoorsaShellCapabilities',
                    callback: (args) => shellCapabilities(isIOS: Platform.isIOS),
                  );
                  // A texture by name (and the grain's level), or a number for
                  // an ordinary press: shell_haptics.dart.
                  controller.addJavaScriptHandler(
                    handlerName: 'FoorsaShellHaptic',
                    callback: (args) {
                      _haptics.play(
                        args.isNotEmpty ? args[0] : null,
                        args.length > 1 ? args[1] : null,
                      );
                      return null;
                    },
                  );
                  // In-app preview of an authenticated backend file:
                  // (url, filename, mime) -> PDF viewer / image viewer /
                  // system app chooser. Called from Mes Documents.
                  // Camera-capture support for <input type=file capture>:
                  // status = current grant (no prompt); ensure = lazy
                  // one-time runtime request on first Scanner tap.
                  // Native file/camera pick — bypasses the WebView's own
                  // file chooser entirely (it fails to launch on some
                  // devices). The web layer receives data URLs back.
                  controller.addJavaScriptHandler(
                    handlerName: 'FoorsaShellPickFile',
                    callback: (args) => _pickForWeb(
                      args.isNotEmpty ? args[0].toString() : 'file',
                      args.length > 1 && args[1] == true,
                    ),
                  );
                  // The guided scanner is opt-in and only called by the
                  // document workflow. Existing camera/file handlers remain
                  // unchanged for receipts, profile photos and old versions.
                  controller.addJavaScriptHandler(
                    handlerName: 'FoorsaShellScanDocument',
                    callback: (args) => _guidedScanForWeb(
                      args.isNotEmpty ? args[0] : 'page',
                      args.length > 1 ? args[1] : null,
                    ),
                  );
                  controller.addJavaScriptHandler(
                    handlerName: 'FoorsaShellScannerSession',
                    callback: (args) async {
                      // Publish into the trusted main frame, never return the
                      // capability to an iframe that requested this refresh.
                      await _publishScannerNonce(controller);
                      return {'ready': true};
                    },
                  );
                  controller.addJavaScriptHandler(
                    handlerName: 'FoorsaShellCameraStatus',
                    callback: (args) async {
                      final granted = await ph.Permission.camera.isGranted;
                      return {'granted': granted};
                    },
                  );
                  controller.addJavaScriptHandler(
                    handlerName: 'FoorsaShellEnsureCamera',
                    callback: (args) async {
                      try {
                        final status = await ph.Permission.camera.request();
                        return {'granted': status.isGranted};
                      } catch (_) {
                        return {'granted': false};
                      }
                    },
                  );
                  // Native save into the device's Downloads. Contract:
                  // {'ok': true} ONLY on a real save — anything else makes
                  // the portal fall back to the system browser.
                  controller.addJavaScriptHandler(
                    handlerName: 'FoorsaShellDownloadFile',
                    callback: (args) => _downloadForWeb(
                      args.isNotEmpty ? args[0].toString() : '',
                      args.length > 1 ? args[1].toString() : 'document',
                      args.length > 2 ? args[2].toString() : '',
                    ),
                  );
                  controller.addJavaScriptHandler(
                    handlerName: 'FoorsaShellPreviewFile',
                    callback: (args) {
                      if (args.isNotEmpty) {
                        _previewFile(
                          args[0].toString(),
                          args.length > 1 ? args[1].toString() : 'document',
                          args.length > 2 ? args[2].toString() : '',
                        );
                      }
                      return null;
                    },
                  );
                },
                onUpdateVisitedHistory: (controller, url, isReload) {
                  // React Router navigation does not trigger onLoadStart.
                  _updateChatViewport(url);
                },
                onLoadStart: (controller, url) {
                  _updateChatViewport(url);
                  _errorThisLoad = false;
                  _scannerNonce = _newScannerNonce();
                },
                onLoadStop: (controller, url) async {
                  await _openPushChat();
                  if (_loader.showing) setState(_loader.pageLoaded);
                  if (!_errorThisLoad) {
                    _exitOffline();
                    try {
                      await _publishScannerNonce(controller);
                    } catch (_) {
                      // The portal can request publication again just before
                      // scanning, without depending on page load timing.
                    }
                  }
                },
                onReceivedError: (controller, request, error) {
                  if (request.isForMainFrame ?? true) {
                    _errorThisLoad = true;
                    _enterOffline();
                  }
                },
                onPermissionRequest: _onPermissionRequest,
                onGeolocationPermissionsShowPrompt: _onGeolocationPrompt,
                onDownloadStartRequest: (controller, request) =>
                    _download(request),
                onCreateWindow: (controller, action) async {
                  final uri = action.request.url;
                  if (uri != null) {
                    if (_isInternal(uri)) {
                      controller.loadUrl(urlRequest: URLRequest(url: uri));
                    } else {
                      _openExternally(uri);
                    }
                  }
                  return false;
                },
                shouldOverrideUrlLoading: (controller, action) async {
                  final uri = action.request.url;
                  if (uri == null) return NavigationActionPolicy.ALLOW;
                  // An iframe loading its page (the YouTube player on a
                  // place's card) stays in its frame; only the page itself
                  // leaves the app for a non-Foorsa address.
                  if (isEmbeddedWebNavigation(uri,
                      isForMainFrame: action.isForMainFrame)) {
                    return NavigationActionPolicy.ALLOW;
                  }
                  if (_isInternal(uri)) {
                    return NavigationActionPolicy.ALLOW;
                  }
                  await _openExternally(uri);
                  return NavigationActionPolicy.CANCEL;
                },
              ),
            ),
            if (!_loaderRemoved)
              IgnorePointer(
                ignoring: !_loader.showing,
                child: AnimatedOpacity(
                  opacity: _loader.showing ? 1 : 0,
                  // The portal's own loader fades in the same 220 ms.
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  onEnd: () {
                    if (!_loader.showing && mounted) {
                      setState(() => _loaderRemoved = true);
                    }
                  },
                  child: ShellLoadingScreen(dark: _isDark(context)),
                ),
              ),
            if (_loadFailed)
              ShellOfflineScreen(onRetry: _retry, dark: _isDark(context)),
          ],
        ),
      ),
    );
  }
}

// ── full-screen viewers for FoorsaShellPreviewFile ─────────────────────────
class _PreviewScaffold extends StatelessWidget {
  const _PreviewScaffold({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF10192E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1526),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15)),
      ),
      body: child,
    );
  }
}

class _PdfPreviewPage extends StatefulWidget {
  const _PdfPreviewPage({required this.path, required this.title});
  final String path;
  final String title;

  @override
  State<_PdfPreviewPage> createState() => _PdfPreviewPageState();
}

class _PdfPreviewPageState extends State<_PdfPreviewPage> {
  bool _failed = false;

  @override
  Widget build(BuildContext context) {
    return _PreviewScaffold(
      title: widget.title,
      child: _failed
          ? const Center(
              child: Text('This file could not be opened',
                  style: TextStyle(color: Colors.white70)))
          : PDFView(
              filePath: widget.path,
              enableSwipe: true,
              autoSpacing: true,
              pageFling: false,
              onError: (_) {
                if (mounted) setState(() => _failed = true);
              },
              onPageError: (_, __) {
                if (mounted) setState(() => _failed = true);
              },
            ),
    );
  }
}

class _ImagePreviewPage extends StatefulWidget {
  const _ImagePreviewPage({required this.path, required this.title});
  final String path;
  final String title;

  @override
  State<_ImagePreviewPage> createState() => _ImagePreviewPageState();
}

class _ImagePreviewPageState extends State<_ImagePreviewPage> {
  final TransformationController _tc = TransformationController();

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _PreviewScaffold(
      title: widget.title,
      child: GestureDetector(
        onDoubleTap: () => _tc.value = Matrix4.identity(),
        child: InteractiveViewer(
          transformationController: _tc,
          maxScale: 6,
          child: Center(
            child: Image.file(
              File(widget.path),
              errorBuilder: (_, __, ___) => const Text(
                  'This file could not be opened',
                  style: TextStyle(color: Colors.white70)),
            ),
          ),
        ),
      ),
    );
  }
}
