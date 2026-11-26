/// The app: home.foorsa.ma in a web view, with what a phone adds to it.
///
/// - The CRM's own pages stay in the app; a page the CRM opens in a new tab
///   (another Foorsa site) opens over it with a Close button; anything else
///   (WhatsApp, Maps, a phone number, an email) goes to the app it belongs to.
/// - The camera, the microphone (office calls, voice notes) and the location
///   (supervised remote work) are given to the CRM once the phone allows them.
/// - Files the CRM hands over are saved and opened (downloads.dart).
/// - Google and passkey sign-in go through the phone's browser
///   (browser_sign_in.dart).
/// - Notifications open the page they are about (push.dart).
/// - The status bar takes the colour the CRM reports (FoorsaShellTheme).
library;

import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:url_launcher/url_launcher.dart';

import 'browser_sign_in.dart';
import 'config.dart';
import 'downloads.dart';
import 'push.dart';

/// A CRM path from a notification, as a full address; anything that is not
/// a path on the CRM is refused.
Uri? crmAddressFor(String route) {
  final trimmed = route.trim();
  if (!trimmed.startsWith('/') || trimmed.startsWith('//') || trimmed.contains('\\')) return null;
  final base = Uri.parse(CrmConfig.baseUrl);
  final target = base.resolve(trimmed);
  return target.host == base.host && target.scheme == base.scheme ? target : null;
}

/// How a navigation the web view did not start itself is handled.
enum LinkRoute { stay, external, block }

/// Foorsa stays, web and app links (tel:, mailto:, WhatsApp) leave, and
/// schemes nobody should be sent to (file:, javascript:) are refused.
LinkRoute routeFor(Uri uri) {
  if (CrmConfig.isFoorsa(uri)) return LinkRoute.stay;
  switch (uri.scheme) {
    case 'about':
    case 'blob':
    case 'data':
      return LinkRoute.stay;
    case 'file':
    case 'javascript':
    case 'content':
      return LinkRoute.block;
    default:
      return LinkRoute.external;
  }
}

/// A CSS colour the CRM reports (#rrggbb or rgb()/rgba()), or null.
Color? parseCssColor(String css) {
  final s = css.trim().toLowerCase();
  if (s.startsWith('#') && s.length == 7) {
    final v = int.tryParse(s.substring(1), radix: 16);
    return v == null ? null : Color(0xFF000000 | v);
  }
  if (s.startsWith('rgb')) {
    final open = s.indexOf('(');
    final close = s.indexOf(')');
    if (open < 0 || close <= open) return null;
    final parts = s.substring(open + 1, close).split(',').map((p) => p.trim()).toList();
    if (parts.length < 3) return null;
    final r = int.tryParse(parts[0]);
    final g = int.tryParse(parts[1]);
    final b = int.tryParse(parts[2]);
    final a = parts.length >= 4 ? (double.tryParse(parts[3]) ?? 1.0) : 1.0;
    if (r == null || g == null || b == null || a < 0.4) return null;
    return Color.fromARGB(255, r, g, b);
  }
  return null;
}

class CrmShell extends StatefulWidget {
  const CrmShell({super.key, this.initialRoute});

  /// The page a tapped notification launched the app on.
  final String? initialRoute;

  @override
  State<CrmShell> createState() => _CrmShellState();
}

class _CrmShellState extends State<CrmShell> with WidgetsBindingObserver {
  InAppWebViewController? _controller;
  Color _chrome = const Color(CrmConfig.signInTopColor);
  bool _firstLoadDone = false;
  bool _offline = false;
  int _generation = 0;
  PackageInfo? _package;
  Timer? _loaderLimit;
  bool _signingIn = false;

  String get _userAgent => '${CrmConfig.userAgentProduct}/${_package?.version ?? ''}';

  Uri get _startAddress =>
      (widget.initialRoute != null ? crmAddressFor(widget.initialRoute!) : null) ?? Uri.parse(CrmConfig.baseUrl);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PackageInfo.fromPlatform().then((p) {
      if (mounted) setState(() => _package = p);
    }).catchError((_) {});
    CrmPush.instance.onOpen = _openRoute;
    // Never more than this on the loading screen, whatever the network.
    _loaderLimit = Timer(const Duration(seconds: 12), () {
      if (mounted && !_firstLoadDone) setState(() => _firstLoadDone = true);
    });
    _applyStatusBar();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _loaderLimit?.cancel();
    CrmPush.instance.onOpen = null;
    super.dispose();
  }

  void _openRoute(String route) {
    final target = crmAddressFor(route);
    final c = _controller;
    if (target == null || c == null) return;
    c.loadUrl(urlRequest: URLRequest(url: WebUri(target.toString())));
  }

  void _applyStatusBar() {
    final light = _chrome.computeLuminance() > 0.5;
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: light ? Brightness.dark : Brightness.light,
      statusBarBrightness: light ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: _chrome,
      systemNavigationBarIconBrightness: light ? Brightness.dark : Brightness.light,
    ));
  }

  void _setChrome(Object? css) {
    final color = css == null ? null : parseCssColor(css.toString());
    if (color == null || color == _chrome || !mounted) return;
    setState(() => _chrome = color);
    _applyStatusBar();
  }

  void _say(String text) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 3)));
  }

  Future<void> _openExternally(Uri uri) async {
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) _say('No app on this phone can open that link.');
    } catch (_) {
      _say('No app on this phone can open that link.');
    }
  }

  /// The CRM's calls into the app (nativeBridge.ts, LoginPage.tsx,
  /// downloads.dart). Only the CRM's own pages are answered.
  Future<Object?> _bridge(InAppWebViewController controller, List<dynamic> args) async {
    if (!CrmConfig.isCrm(await controller.getUrl())) return {'error': 'not allowed'};
    final message = args.isNotEmpty && args.first is Map ? Map<String, dynamic>.from(args.first as Map) : <String, dynamic>{};
    switch (message['action']) {
      case 'appInfo':
        return {
          'platform': Platform.isIOS ? 'ios' : 'android',
          'app': 'crm',
          'version': _package?.version,
          'build': _package?.buildNumber,
          'features': ['signInInBrowser', 'saveFile', 'print', 'openExternal'],
        };
      case 'getPushToken':
        return {'token': await CrmPush.instance.token()};
      case 'signInInBrowser':
        if (_signingIn) return {'ok': false, 'reason': 'busy'};
        _signingIn = true;
        try {
          final result = await signInInBrowser(
            (url) async => controller.loadUrl(urlRequest: URLRequest(url: WebUri(url.toString()))),
            method: message['method']?.toString(),
          );
          if (result == BrowserSignInResult.failed) _say('Sign-in did not finish. Try again.');
          return {'ok': result == BrowserSignInResult.signedIn, 'result': result.name};
        } finally {
          _signingIn = false;
        }
      case 'saveFile':
        final data = message['data']?.toString() ?? '';
        try {
          final file = await saveDataUrl(data, message['name']?.toString(), message['mime']?.toString() ?? '');
          if (file == null) {
            _say('This file could not be saved.');
            return {'ok': false};
          }
          return {'ok': true};
        } catch (_) {
          _say('This file could not be saved.');
          return {'ok': false};
        }
      case 'print':
        try {
          await controller.printCurrentPage();
        } catch (_) {
          _say('Printing is not available on this device.');
        }
        return {'ok': true};
      case 'openExternal':
        final uri = Uri.tryParse(message['url']?.toString() ?? '');
        if (uri == null || routeFor(uri) == LinkRoute.block) return {'ok': false};
        await _openExternally(uri);
        return {'ok': true};
    }
    return {'error': 'unknown action'};
  }

  Future<void> _download(DownloadStartRequest request) async {
    _say('Downloading…');
    try {
      final file = await fetchDownload(request, _userAgent);
      if (file == null) {
        _say('The file could not be downloaded.');
      } else if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
      }
    } catch (_) {
      _say('The file could not be downloaded.');
    }
  }

  /// The camera and the microphone, once the phone allows them, for Foorsa's
  /// pages only. iOS asks the person itself when the page first uses them.
  Future<PermissionResponse> _onPermission(InAppWebViewController controller, PermissionRequest request) async {
    final origin = request.origin;
    if (!CrmConfig.isFoorsa(origin)) {
      return PermissionResponse(resources: request.resources, action: PermissionResponseAction.DENY);
    }
    if (Platform.isAndroid) {
      final wanted = <ph.Permission>{};
      for (final resource in request.resources) {
        if (resource == PermissionResourceType.CAMERA || resource == PermissionResourceType.CAMERA_AND_MICROPHONE) {
          wanted.add(ph.Permission.camera);
        }
        if (resource == PermissionResourceType.MICROPHONE || resource == PermissionResourceType.CAMERA_AND_MICROPHONE) {
          wanted.add(ph.Permission.microphone);
        }
      }
      for (final permission in wanted) {
        if (!(await permission.request()).isGranted) {
          return PermissionResponse(resources: request.resources, action: PermissionResponseAction.DENY);
        }
      }
    }
    return PermissionResponse(resources: request.resources, action: PermissionResponseAction.GRANT);
  }

  Future<GeolocationPermissionShowPromptResponse> _onGeolocation(InAppWebViewController controller, String origin) async {
    final uri = Uri.tryParse(origin);
    var allow = false;
    if (uri != null && CrmConfig.isFoorsa(uri)) {
      allow = (await ph.Permission.locationWhenInUse.request()).isGranted;
    }
    return GeolocationPermissionShowPromptResponse(origin: origin, allow: allow, retain: allow);
  }

  Future<bool> _onCreateWindow(InAppWebViewController controller, CreateWindowAction action) async {
    final uri = action.request.url;
    if (uri == null) return false;
    switch (routeFor(uri)) {
      case LinkRoute.stay:
        if (!mounted) return false;
        unawaited(Navigator.of(context).push(MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => _WindowPage(windowId: action.windowId, url: uri, userAgent: CrmConfig.userAgentProduct),
        )));
        return true;
      case LinkRoute.external:
        await _openExternally(uri);
        return false;
      case LinkRoute.block:
        return false;
    }
  }

  Future<NavigationActionPolicy> _shouldOverride(InAppWebViewController controller, NavigationAction action) async {
    final uri = action.request.url;
    if (uri == null) return NavigationActionPolicy.ALLOW;
    // A frame inside a page (a video, MFC) keeps its own address.
    if (!action.isForMainFrame && (uri.scheme == 'https' || uri.scheme == 'http' || uri.scheme == 'about')) {
      return NavigationActionPolicy.ALLOW;
    }
    switch (routeFor(uri)) {
      case LinkRoute.stay:
        return NavigationActionPolicy.ALLOW;
      case LinkRoute.external:
        await _openExternally(uri);
        return NavigationActionPolicy.CANCEL;
      case LinkRoute.block:
        return NavigationActionPolicy.CANCEL;
    }
  }

  void _loaded() {
    if (_firstLoadDone && !_offline) return;
    if (!mounted) return;
    setState(() {
      _firstLoadDone = true;
      _offline = false;
    });
  }

  Future<void> _retry() async {
    setState(() => _offline = false);
    final c = _controller;
    if (c == null) {
      setState(() => _generation++);
      return;
    }
    final current = await c.getUrl();
    final target = (current != null && CrmConfig.isCrm(current)) ? current : WebUri(_startAddress.toString());
    await c.loadUrl(urlRequest: URLRequest(url: target));
  }

  Future<void> _back() async {
    final c = _controller;
    if (c != null && await c.canGoBack()) {
      await c.goBack();
    } else {
      await SystemNavigator.pop();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Offline when the app went to the background: try again on return.
    if (state == AppLifecycleState.resumed && _offline) unawaited(_retry());
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_back());
      },
      child: Scaffold(
        backgroundColor: _chrome,
        body: Stack(
          children: [
            SafeArea(
              // The CRM pads its own bottom (env(safe-area-inset-bottom)).
              bottom: false,
              child: InAppWebView(
                key: ValueKey<int>(_generation),
                initialUrlRequest: URLRequest(url: WebUri(_startAddress.toString())),
                initialUserScripts: UnmodifiableListView<UserScript>([
                  UserScript(
                    source: downloadBridgeScript,
                    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                    forMainFrameOnly: true,
                  ),
                ]),
                initialSettings: InAppWebViewSettings(
                  applicationNameForUserAgent: CrmConfig.userAgentProduct,
                  javaScriptEnabled: true,
                  javaScriptCanOpenWindowsAutomatically: true,
                  supportMultipleWindows: true,
                  useShouldOverrideUrlLoading: true,
                  useOnDownloadStart: true,
                  mediaPlaybackRequiresUserGesture: false,
                  allowsInlineMediaPlayback: true,
                  allowsBackForwardNavigationGestures: true,
                  allowsLinkPreview: false,
                  geolocationEnabled: true,
                  allowFileAccess: false,
                  useHybridComposition: true,
                  useOnRenderProcessGone: true,
                  offscreenPreRaster: false,
                  isInspectable: false,
                ),
                onWebViewCreated: (controller) {
                  _controller = controller;
                  controller.addJavaScriptHandler(
                    handlerName: CrmConfig.bridgeName,
                    callback: (args) => _bridge(controller, args),
                  );
                  controller.addJavaScriptHandler(
                    handlerName: 'FoorsaShellTheme',
                    callback: (args) {
                      if (args.isNotEmpty) _setChrome(args.first);
                      return null;
                    },
                  );
                },
                onLoadStop: (controller, url) => _loaded(),
                onReceivedError: (controller, request, error) {
                  if (request.isForMainFrame != true) return;
                  // A navigation the app cancelled (a link it opened elsewhere)
                  // is not a failure.
                  if (error.type == WebResourceErrorType.CANCELLED) return;
                  if (!mounted) return;
                  setState(() {
                    _offline = true;
                    _firstLoadDone = true;
                  });
                },
                onPermissionRequest: _onPermission,
                onGeolocationPermissionsShowPrompt: _onGeolocation,
                onDownloadStartRequest: (controller, request) => _download(request),
                onCreateWindow: _onCreateWindow,
                shouldOverrideUrlLoading: _shouldOverride,
                // iPhone and iPad: the page's process was ended (memory); the
                // web view stays and loads the page again.
                onWebContentProcessDidTerminate: (controller) => controller.reload(),
                // Android: the page's process is gone, and this web view with it.
                onRenderProcessGone: (controller, detail) {
                  if (mounted) setState(() => _generation++);
                },
              ),
            ),
            if (!_firstLoadDone) const _LoadingScreen(),
            if (_offline) _OfflineScreen(onRetry: _retry),
          ],
        ),
      ),
    );
  }
}

/// A Foorsa page the CRM opened in a new tab, over the CRM.
class _WindowPage extends StatelessWidget {
  const _WindowPage({required this.windowId, required this.url, required this.userAgent});

  final int windowId;
  final Uri url;
  final String userAgent;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(CrmConfig.navy),
        foregroundColor: Colors.white,
        title: Text(url.host, style: const TextStyle(fontSize: 15)),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Close',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: InAppWebView(
        windowId: windowId,
        initialSettings: InAppWebViewSettings(
          applicationNameForUserAgent: userAgent,
          mediaPlaybackRequiresUserGesture: false,
          allowsInlineMediaPlayback: true,
          useHybridComposition: true,
          useShouldOverrideUrlLoading: true,
          allowFileAccess: false,
        ),
        shouldOverrideUrlLoading: (controller, action) async {
          final uri = action.request.url;
          if (uri == null || !action.isForMainFrame) return NavigationActionPolicy.ALLOW;
          switch (routeFor(uri)) {
            case LinkRoute.stay:
              return NavigationActionPolicy.ALLOW;
            case LinkRoute.external:
              await launchUrl(uri, mode: LaunchMode.externalApplication);
              return NavigationActionPolicy.CANCEL;
            case LinkRoute.block:
              return NavigationActionPolicy.CANCEL;
          }
        },
        onCloseWindow: (controller) {
          if (Navigator.of(context).canPop()) Navigator.of(context).pop();
        },
      ),
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(CrmConfig.navy),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/mark-white.png', width: 88, height: 88, semanticLabel: 'Foorsa'),
              const SizedBox(height: 28),
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OfflineScreen extends StatelessWidget {
  const _OfflineScreen({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(CrmConfig.navy),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset('assets/mark-white.png', width: 64, height: 64, excludeFromSemantics: true),
                  const SizedBox(height: 24),
                  const Text(
                    'Foorsa CRM is not reachable',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Check your internet connection, then try again.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 15, height: 1.4),
                  ),
                  const SizedBox(height: 28),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(CrmConfig.navy),
                      minimumSize: const Size(160, 48),
                      shape: const StadiumBorder(),
                    ),
                    onPressed: onRetry,
                    child: const Text('Try again', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
