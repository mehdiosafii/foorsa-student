/// How the portal's web view is put on the screen with the app's own
/// drawing, and when it is not drawn at all.
///
/// On Android a web view is an Android view inside Flutter's picture, and
/// Flutter has two ways to show one (docs/platforms/android in the Flutter
/// SDK). Hybrid Composition (HC) puts the real view in the window: while it
/// is on the screen, everything Flutter draws over it is drawn into image
/// views, Flutter's frames are rastered on Android's main thread, and before
/// Android 10 every frame is copied out of the GPU and back. Texture Layer
/// Hybrid Composition (TLHC) also puts the view in the window, so touches,
/// the keyboard, text selection and accessibility reach it there, but
/// redirects its drawing into a texture Flutter draws like any other
/// picture, on its own raster thread. (In this mode flutter_inappwebview
/// passes the keyboard through a bridge kept from Flutter's older virtual
/// displays, InputAwareWebView, and draws its own copy and paste bar in place
/// of Android's: typing and pasting in the first session are what a phone
/// must confirm, docs/first-launch-onboarding.md.)
///
/// The portal has always used HC, and keeps it: its pages are the app, and
/// the shell draws little over them. The first-launch onboarding is the
/// exception. It is a full-screen animation drawn over the web view for half
/// a minute or more while the sign-in loads under it, which under HC put every
/// one of its frames through Android's image views and main thread: the
/// sluggish, uneven introduction on Android (31 Oct 2026). So a web view made
/// while the onboarding covers the shell uses TLHC, and is not drawn at all
/// until the onboarding starts to fade onto it (its texture is drawn from
/// then on, current, as the web view kept drawing into it). Web views made on
/// any other launch, or after the onboarding, use HC as before.
///
/// iOS has one way only, and ignores both.
library;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Whether a web view made now uses Hybrid Composition: on Android, every
/// time but while the first-launch onboarding covers the shell.
bool webViewUsesHybridComposition(
        {required bool android, required bool underOnboarding}) =>
    !(android && underOnboarding);

/// Whether the web view is left undrawn under the onboarding: only a web view
/// in a texture (TLHC) can be. One in the window (HC) is attached and laid
/// out by Android only once Flutter draws it, so it must be drawn from the
/// start, or the page would load at no size and the onboarding could not find
/// the sign-in's arrow on it.
bool webViewHiddenUnderOnboarding(
        {required bool android,
        required bool hybridComposition,
        required bool covered}) =>
    android && !hybridComposition && covered;

/// Lays [child] out as usual, keeps it running, and neither draws it nor
/// lets it take a touch while [covered]: for what the onboarding covers from
/// edge to edge (the web view, the app's loader), which nobody can see and
/// which cost every frame they are drawn.
class CoveredByOnboarding extends SingleChildRenderObjectWidget {
  const CoveredByOnboarding(
      {super.key, required this.covered, required Widget super.child});

  final bool covered;

  @override
  RenderCoveredByOnboarding createRenderObject(BuildContext context) =>
      RenderCoveredByOnboarding(covered);

  @override
  void updateRenderObject(
          BuildContext context, RenderCoveredByOnboarding renderObject) =>
      renderObject.covered = covered;
}

/// [CoveredByOnboarding]'s render object.
class RenderCoveredByOnboarding extends RenderProxyBox {
  RenderCoveredByOnboarding(this._covered);

  bool _covered;
  bool get covered => _covered;
  set covered(bool value) {
    if (value == _covered) return;
    _covered = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_covered) return;
    super.paint(context, offset);
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      !_covered && super.hitTest(result, position: position);
}
