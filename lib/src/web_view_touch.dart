/// How the iPhone hands the web view its touches.
///
/// A platform view on iOS sits under a view of Flutter's that catches its
/// touches. By default (the "eager" policy) that view carries a recognizer
/// every other recognizer must wait for: a tap, a long press for the Paste
/// menu, a scroll, the tap that raises the keyboard, none of WebKit's own
/// gestures may start until Flutter has answered, over the platform channel,
/// that the touch is the web view's. Flutter's own documentation says what
/// that costs with some native views, WKWebView the known one: their
/// "internal gesture recognizers get stuck in a stale state", and the engine
/// carries a workaround per iOS release for it (links that could not be
/// tapped on iOS 18.2, then on iOS 26; flutter/flutter#158961, #175099). The
/// shell had already met it (30 Oct 2026: "a long press reached WebKit late or
/// not at all, and the Copy / Paste menu came and went") and answered by
/// winning Flutter's gesture arena at once, which still left every touch
/// waiting on that answer.
///
/// The owner, 12 Nov 2026: "when pasting the otp ... no paste button is there
/// it freezes, also many times the scrolling and keyboard are stuck".
///
/// Flutter now offers the remedy itself:
/// [UiKitViewGestureBlockingPolicy.doNotBlockGesture], "a workaround to
/// address a few bugs related to platform view's gesture recognizers being
/// stuck in a stale state". The waiting recognizer is not there at all, and
/// WebKit has its touches as any app's web view has them. What it gives up
/// is Flutter taking back a gesture that began on the web view, which this
/// app never asked for: the web view fills the screen, the shell already
/// tells Flutter the web view wins every such gesture, and what the app
/// draws over it (the loader, the offline screen, a call, a dialog, the
/// onboarding) covers it, which is decided by where the finger lands, under
/// every policy alike.
///
/// The web view plugin builds its [UiKitView] itself and has no setting for
/// this, so the app hands it a platform of its own that builds the same view
/// and adds the policy. Android has none of this, and is left alone.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview_ios/flutter_inappwebview_ios.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';

/// The policy the web view is made with on an iPhone.
const webViewGestureBlockingPolicy =
    UiKitViewGestureBlockingPolicy.doNotBlockGesture;

/// On an iPhone, makes every web view the app shows from now on take its
/// touches straight from iOS. Called once, before the first web view is
/// built (main.dart).
void useUnblockedWebViewTouches() {
  if (defaultTargetPlatform != TargetPlatform.iOS) return;
  InAppWebViewPlatform.instance = UnblockedIOSWebViewPlatform();
}

/// The plugin's iOS platform, with the web view's widget made here.
class UnblockedIOSWebViewPlatform extends IOSInAppWebViewPlatform {
  @override
  IOSInAppWebViewWidget createPlatformInAppWebViewWidget(
          PlatformInAppWebViewWidgetCreationParams params) =>
      UnblockedIOSInAppWebViewWidget(params);
}

/// The plugin's iOS web view, built as the plugin builds it, then given
/// [webViewGestureBlockingPolicy].
class UnblockedIOSInAppWebViewWidget extends IOSInAppWebViewWidget {
  UnblockedIOSInAppWebViewWidget(super.params);

  @override
  Widget build(BuildContext context) => unblockedWebView(super.build(context));
}

/// [built] with [webViewGestureBlockingPolicy] when it is the platform view
/// the plugin makes; anything else (another plugin version building it
/// another way) is left as it is, and the test fails.
Widget unblockedWebView(Widget built) {
  if (built is! UiKitView) return built;
  return UiKitView(
    key: built.key,
    viewType: built.viewType,
    gestureBlockingPolicy: webViewGestureBlockingPolicy,
    onPlatformViewCreated: built.onPlatformViewCreated,
    hitTestBehavior: built.hitTestBehavior,
    layoutDirection: built.layoutDirection,
    creationParams: built.creationParams,
    creationParamsCodec: built.creationParamsCodec,
    gestureRecognizers: built.gestureRecognizers,
  );
}
