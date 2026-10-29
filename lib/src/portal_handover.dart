/// Where the onboarding hands the student to the portal. The sign-in draws
/// Foorsa's arrow (`data-foorsa-mark`, NightStage.tsx in foorsa-reward) on
/// the same night the onboarding is told on; the onboarding asks here where
/// that arrow is on the screen, lands its own arrow exactly on it, and then
/// says `foorsa:boarded` so the sign-in's words rise in as the onboarding
/// fades away.
library;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class PortalHandover {
  PortalHandover._();
  static final PortalHandover instance = PortalHandover._();

  /// Set by the shell when its web view exists.
  InAppWebViewController? controller;

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
