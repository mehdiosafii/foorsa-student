# Pinned iOS bridge hardening

Upstream: flutter_inappwebview_ios 1.1.2 from pub.dev, Apache 2.0 (LICENSE
retained). Upstream pub archive SHA-256:
5818cf9b26cf0cbb0f62ff50772217d41ea8d3d9cc00279c45f8aabaa1b4025d
(from the pre-existing pubspec.lock). Production ios/ and lib/ sources are vendored unchanged except for:

- ios/Classes/FoorsaBridgePolicy.swift: permits only the main frame at the exact
  HTTPS student.foorsa.ma origin, port 443 (or WebKit's default-port 0).
- ios/Classes/InAppWebView/InAppWebView.swift: checks WKScriptMessage.frameInfo
  and its native securityOrigin before dispatching any Foorsa-prefixed handler.
  JavaScript origin arguments are never trusted. Rejected messages do not invoke
  Dart or privileged actions. Upstream media and non-Foorsa bridge behavior stays
  unchanged, including scripts needed by embedded web players.

The root pubspec dependency override and lockfile select this directory. The
CocoaPods plugin symlink must resolve here, never to the shared package cache.
Keep this patch until an upstream replacement provides equivalent native sender
validation, with regression verification before removing it.

Policy test (from repository root):

    xcrun swiftc third_party/flutter_inappwebview_ios/ios/Classes/FoorsaBridgePolicy.swift test/native/main.swift -o /tmp/foorsa-bridge-policy-test
    /tmp/foorsa-bridge-policy-test

This tests the compiled policy. It does not substitute for device verification
of real WKScriptMessage sender metadata, camera/picker, learning frames or video.
Android's upstream bridge is unchanged by this iOS-scoped patch.
