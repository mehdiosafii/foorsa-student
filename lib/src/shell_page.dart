/// The WebView shell around https://student.foorsa.ma.
///
/// Lean student edition: no push, no calls, and no pull-to-refresh — the
/// portal refreshes itself quietly every 5 minutes, so the gesture would
/// only offer a jarring full reload. Uploads, downloads,
/// theme-matched status bar (via the FoorsaShellTheme bridge message), and
/// sensible back handling.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

import 'config.dart';
import 'pdf_validation.dart';
import 'flicker_spinner.dart';

class ShellPage extends StatefulWidget {
  const ShellPage({super.key});

  @override
  State<ShellPage> createState() => _ShellPageState();
}


class _ShellPageState extends State<ShellPage> {
  InAppWebViewController? _controller;
  PackageInfo? _packageInfo;
  bool _firstLoadDone = false;
  bool _introDone = false;
  bool _bootWebView = false;
  bool _loadFailed = false;
  /// The CURRENT navigation reported a main-frame error. Android fires
  /// onLoadStop even for failed loads, so "finished" alone must never be
  /// trusted as success — this flag is what onLoadStop consults.
  bool _errorThisLoad = false;
  /// While offline: quiet retry loop behind the branded overlay.
  Timer? _retryTimer;
  DateTime? _lastBackPress;
  Color _chromeColor = const Color(0xFF0B1220);

  @override
  void initState() {
    super.initState();
    // Minimum splash so a fast load can't flash it; the screen otherwise
    // lifts the moment the portal's first load finishes.
    Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _introDone = true);
    });
    // Let the loading screen paint its first frame before the WebView's
    // platform-view init grabs the UI thread.
    Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _bootWebView = true);
    });
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
        _firstLoadDone = true;
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

  Future<void> _openExternally(Uri uri) async {
    try {
      await launcher.launchUrl(uri,
          mode: launcher.LaunchMode.externalApplication);
    } catch (_) {}
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
      if (mode == 'camera') {
        await ph.Permission.camera.request();
        final shot = await ImagePicker().pickImage(
          source: ImageSource.camera,
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
        var savedViaStore = false;
        try {
          final r = await _downloadsChannel.invokeMethod<bool>(
            'saveToDownloads',
            {
              'path': tmp.path,
              'name': name,
              'mime': mime.isEmpty ? 'application/octet-stream' : mime,
            },
          );
          savedViaStore = r == true;
        } catch (_) {
          savedViaStore = false;
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
        // documents (visible in Files via the app container). The share
        // sheet ships with the iOS build milestone.
        final docs = await getApplicationDocumentsDirectory();
        final target = File('${docs.path}/$name');
        await tmp.copy(target.path);
        openPath = target.path;
      }

      dismissSpinner();
      final path = openPath;
      messenger?.showSnackBar(SnackBar(
        content: const Text('Enregistré dans Téléchargements'),
        action: SnackBarAction(
          label: 'Ouvrir',
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
        // Same name + same size already in the temp dir -> reuse it.
        var needDownload = true;
        if (await file.exists()) {
          try {
            final head = await client.headUrl(uri).then((r) => r.close());
            if (head.contentLength > 0 &&
                head.contentLength == await file.length()) {
              needDownload = false;
            }
          } catch (_) {}
        }
        if (needDownload) {
          final response = await client.getUrl(uri).then((r) => r.close());
          if (response.statusCode < 200 || response.statusCode >= 300) {
            throw HttpException('HTTP ${response.statusCode}');
          }
          await response.pipe(file.openWrite());
        }
      } finally {
        client.close();
      }

      final kind = mime.toLowerCase().trim();
      final isPdf = kind == 'application/pdf' || name.toLowerCase().endsWith('.pdf');
      if (isPdf && !await hasPdfHeader(file)) {
        await file.delete();
        throw const FormatException('Downloaded document is not a PDF');
      }
      dismissSpinner();
      if (!mounted) return;
      if (isPdf) {
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
              content: Text("Impossible d'ouvrir le fichier")));
        }
      }
    } catch (_) {
      dismissSpinner();
      messenger?.showSnackBar(
          const SnackBar(content: Text("Impossible d'ouvrir le fichier")));
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
    final lightBg = picked.computeLuminance() > 0.5;
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: lightBg ? Brightness.dark : Brightness.light,
      statusBarBrightness: lightBg ? Brightness.light : Brightness.dark,
    ));
  }

  Future<Map<String, dynamic>> _handleBridgeCall(List<dynamic> args) async {
    String action = '';
    if (args.isNotEmpty && args[0] is Map) {
      action = ((args[0] as Map)['action'] ?? '').toString();
    }
    switch (action) {
      case 'getPushToken':
        return {'token': null}; // student app ships without push (yet)
      case 'appInfo':
        return {
          'platform': Platform.isIOS ? 'ios' : 'android',
          'version': _packageInfo?.version,
        };
      default:
        return {'error': 'unknown action'};
    }
  }

  Future<PermissionResponse> _onPermissionRequest(
      InAppWebViewController controller, PermissionRequest request) async {
    if (request.resources.contains(PermissionResourceType.CAMERA)) {
      await ph.Permission.camera.request();
    }
    return PermissionResponse(
      resources: request.resources,
      action: PermissionResponseAction.GRANT,
    );
  }

  Future<void> _handleBack() async {
    final c = _controller;
    if (c != null && await c.canGoBack()) {
      await c.goBack();
      return;
    }
    final now = DateTime.now();
    if (_lastBackPress != null &&
        now.difference(_lastBackPress!) < const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return;
    }
    if (!mounted) return;
    _lastBackPress = now;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
          content: Text('Press back again to exit'),
          duration: Duration(seconds: 2)),
    );
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        backgroundColor: _chromeColor,
        body: Stack(
          children: [
            SafeArea(
              bottom: false,
              child: !_bootWebView
                  ? const SizedBox.expand()
                  : InAppWebView(
                initialUrlRequest: URLRequest(url: WebUri(AppConfig.baseUrl)),
                initialSettings: InAppWebViewSettings(
                  allowFileAccess: true,
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
                ),
                onWebViewCreated: (controller) {
                  _controller = controller;
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
                  // Opens a URL OUTSIDE the WebView, letting Android pick the
                  // native app (wa.me -> WhatsApp, ig.me -> Instagram, ...).
                  // Called by the portal's Contact button.
                  controller.addJavaScriptHandler(
                    handlerName: 'FoorsaShellOpenUrl',
                    callback: (args) {
                      if (args.isNotEmpty) {
                        final uri = Uri.tryParse(args[0].toString());
                        if (uri != null) _openExternally(uri);
                      }
                      return null;
                    },
                  );
                  // Tactile tick for portal button presses —
                  // navigator.vibrate is unreliable inside the WebView.
                  controller.addJavaScriptHandler(
                    handlerName: 'FoorsaShellHaptic',
                    callback: (args) {
                      HapticFeedback.lightImpact();
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
                onLoadStart: (controller, url) {
                  _errorThisLoad = false;
                },
                onLoadStop: (controller, url) async {
                  if (!_firstLoadDone) setState(() => _firstLoadDone = true);
                  if (!_errorThisLoad) _exitOffline();
                },
                onReceivedError: (controller, request, error) {
                  if (request.isForMainFrame ?? true) {
                    _errorThisLoad = true;
                    _enterOffline();
                  }
                },
                onPermissionRequest: _onPermissionRequest,
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
                  if (_isInternal(uri)) return NavigationActionPolicy.ALLOW;
                  await _openExternally(uri);
                  return NavigationActionPolicy.CANCEL;
                },
              ),
            ),
            if (!_firstLoadDone || !_introDone) const _BrandLoading(),
            if (_loadFailed)
              _OfflineView(onRetry: _retry),
          ],
        ),
      ),
    );
  }
}

class _BrandLoading extends StatelessWidget {
  const _BrandLoading();

  @override
  Widget build(BuildContext context) {
    final dark =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Container(
        color: dark ? const Color(AppConfig.brandColorValue) : Colors.white,
        alignment: Alignment.center,
        // The app's loading animation — nothing else. Android already
        // shows the branded logo splash (flutter_native_splash, same
        // #183250 ground) before Flutter's first frame, so this reads as
        // one continuous screen: logo, then the loader.
        child: FlickerSpinner(
          size: 64,
          onColor: dark
              ? const Color(0xFFF5F5F5)
              : const Color(AppConfig.brandColorValue),
          offColor: dark ? const Color(0xFF404040) : const Color(0xFFDCE2EC),
        ),
      ),
    );
  }
}

class _OfflineView extends StatelessWidget {
  const _OfflineView({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0D1526), Color(0xFF17233F), Color(0xFF1F2F52)],
        ),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset('assets/images/splash_logo.png', width: 96),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                  ),
                  child: const Icon(Icons.wifi_off_rounded,
                      color: Colors.white, size: 30),
                ),
                const SizedBox(height: 18),
                const Text('Pas de connexion Internet',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                const Text('لا يوجد اتصال بالإنترنت',
                    textDirection: TextDirection.rtl,
                    style: TextStyle(color: Color(0xFFB6C2D6), fontSize: 14)),
                const SizedBox(height: 14),
                const Text(
                  'Vérifiez votre Wi-Fi ou vos données mobiles.\nLa page se rechargera automatiquement.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Color(0xFF9FB0C8), fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 22),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF16223D),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 26, vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Réessayer',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ],
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
              child: Text("Impossible d'ouvrir le fichier",
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
                  "Impossible d'ouvrir le fichier",
                  style: TextStyle(color: Colors.white70)),
            ),
          ),
        ),
      ),
    );
  }
}
