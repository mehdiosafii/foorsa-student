/// Where the onboarding hands the student to the portal. The sign-in draws
/// Foorsa's arrow (`data-foorsa-mark`, NightStage.tsx in foorsa-reward) on
/// the same night the onboarding is told on; the onboarding asks here where
/// that arrow is on the screen, lands its own arrow exactly on it, and then
/// says `foorsa:boarded` so the sign-in's words rise in as the onboarding
/// fades away.
library;

import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'boot_loader_gate.dart';

class PortalHandover {
  PortalHandover._();
  static final PortalHandover instance = PortalHandover._();

  /// Set by the shell when its web view exists.
  InAppWebViewController? get controller => _controller;
  InAppWebViewController? _controller;
  set controller(InAppWebViewController? value) {
    _controller = value;
    if (value == null || _made) return;
    _made = true;
    Timer(BootLoaderGate.settle, _settled.complete);
  }

  /// Completes a moment ([BootLoaderGate.settle]) after the shell's first web
  /// view was made. Making one holds the thread the app draws on, and on
  /// Android the frame that first shows it is drawn twice
  /// (boot_loader_gate.dart): what would come in over the shell as the app
  /// opens, the device access reminder, waits for this.
  Future<void> get webViewSettled => _settled.future;
  final Completer<void> _settled = Completer<void>();
  bool _made = false;

  /// On the safe area the web view fills, so the page's points can be put
  /// on the screen.
  final GlobalKey webViewArea = GlobalKey(debugLabel: 'portal web view');

  /// The sign-in's arrow on the screen, or null when the page has none (not
  /// loaded yet, or already signed in).
  Future<Rect?> markRect() async {
    final web = controller;
    final area = webViewArea.currentContext?.findRenderObject();
    // The web view starts inside the safe area's padding.
    final box = area is RenderShiftedBox ? area.child : area;
    if (web == null || box is! RenderBox || !box.hasSize) return null;
    try {
      final found = await web.evaluateJavascript(
          source: "(() => { const r = document.querySelector('[data-foorsa-mark]')"
              '?.getBoundingClientRect(); '
              'return r && r.width > 0 ? [r.x, r.y, r.width, r.height] : null; })()');
      if (found is! List || found.length != 4) return null;
      final values = [for (final v in found) (v as num).toDouble()];
      final origin = box.localToGlobal(Offset.zero);
      return Rect.fromLTWH(
          origin.dx + values[0], origin.dy + values[1], values[2], values[3]);
    } catch (_) {
      return null;
    }
  }

  /// The onboarding is fading: the sign-in plays its entrance.
  Future<void> boarded() async {
    try {
      await controller?.evaluateJavascript(
          source: "window.dispatchEvent(new Event('foorsa:boarded'))");
    } catch (_) {}
  }
}
