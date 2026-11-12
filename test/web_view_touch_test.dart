// How the iPhone hands the web view its touches (lib/src/web_view_touch.dart).
//
// The owner, 12 Nov 2026: "when pasting the otp ... no paste button is there
// it freezes, also many times the scrolling and keyboard are stuck". By
// default every gesture of WebKit's waits on a recognizer of Flutter's until
// Flutter has answered over the platform channel; Flutter's own remedy for a
// WKWebView is the policy that leaves that recognizer out.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_inappwebview_ios/flutter_inappwebview_ios.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/web_view_touch.dart';

const _viewType = 'com.pichillilorenzo/flutter_inappwebview';

/// What the framework sends the engine to make a platform view, kept.
List<MethodCall> _watchPlatformViews(WidgetTester tester) {
  final calls = <MethodCall>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform_views, (call) async {
    calls.add(call);
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform_views, null));
  return calls;
}

Widget _webView() => Directionality(
      textDirection: TextDirection.ltr,
      child: InAppWebView(
        // As the shell builds it (shell_page.dart).
        gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
          Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
        },
        initialUrlRequest: URLRequest(url: WebUri('https://student.foorsa.ma/')),
        initialSettings: InAppWebViewSettings(disableInputAccessoryView: true),
      ),
    );

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets('on an iPhone the web view is made with no recognizer of Flutter\'s to wait for',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final calls = _watchPlatformViews(tester);
    useUnblockedWebViewTouches();
    expect(InAppWebViewPlatform.instance, isA<UnblockedIOSWebViewPlatform>());

    await tester.pumpWidget(_webView());
    await tester.pump();

    // The widget the app's platform built: the plugin's own view, and the policy.
    final view = tester.widget<UiKitView>(find.byType(UiKitView));
    expect(view.viewType, _viewType);
    expect(view.gestureBlockingPolicy, UiKitViewGestureBlockingPolicy.doNotBlockGesture);
    expect(view.gestureBlockingPolicy, webViewGestureBlockingPolicy);
    // Everything the plugin gave its view is still there.
    expect(view.onPlatformViewCreated, isNotNull);
    expect(view.gestureRecognizers, hasLength(1));
    expect(view.creationParamsCodec, isA<StandardMessageCodec>());
    final params = view.creationParams as Map<String, dynamic>;
    expect(params['initialUrlRequest'], isA<Map<dynamic, dynamic>>());
    expect((params['initialSettings'] as Map)['disableInputAccessoryView'], isTrue);

    // And what the engine is told, in the words it reads
    // (FlutterPlatformViewsController.mm: args[@"gestureBlockingPolicy"]).
    final create = calls.singleWhere((call) => call.method == 'create');
    final args = create.arguments as Map<dynamic, dynamic>;
    expect(args['viewType'], _viewType);
    expect(args['gestureBlockingPolicy'], 'doNotBlockGesture');
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('left to the plugin, the same web view waits on Flutter (what this replaces)',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final calls = _watchPlatformViews(tester);
    InAppWebViewPlatform.instance = IOSInAppWebViewPlatform();

    await tester.pumpWidget(_webView());
    await tester.pump();

    final view = tester.widget<UiKitView>(find.byType(UiKitView));
    expect(view.gestureBlockingPolicy, UiKitViewGestureBlockingPolicy.fallbackToPluginDefault);
    final args = calls.singleWhere((call) => call.method == 'create').arguments as Map<dynamic, dynamic>;
    // The plugin registers its view with no policy, which is the engine's "eager".
    expect(args['gestureBlockingPolicy'], 'fallbackToPluginDefault');
    debugDefaultTargetPlatformOverride = null;
  });

  test('Android keeps the plugin\'s own platform', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    // Whatever the plugin registered for the phone (a stand-in here).
    final registered = IOSInAppWebViewPlatform();
    InAppWebViewPlatform.instance = registered;
    useUnblockedWebViewTouches();
    expect(identical(InAppWebViewPlatform.instance, registered), isTrue);
    debugDefaultTargetPlatformOverride = null;
  });

  test('only the platform view the plugin makes is rebuilt', () {
    const other = SizedBox(width: 3);
    expect(identical(unblockedWebView(other), other), isTrue);
    final rebuilt = unblockedWebView(const UiKitView(
        key: ValueKey('web'),
        viewType: _viewType,
        layoutDirection: TextDirection.rtl,
        hitTestBehavior: PlatformViewHitTestBehavior.translucent)) as UiKitView;
    expect(rebuilt.key, const ValueKey('web'));
    expect(rebuilt.layoutDirection, TextDirection.rtl);
    expect(rebuilt.hitTestBehavior, PlatformViewHitTestBehavior.translucent);
    expect(rebuilt.gestureBlockingPolicy, UiKitViewGestureBlockingPolicy.doNotBlockGesture);
  });

  test('the app asks for it before its first web view is built', () {
    final main = File('lib/main.dart').readAsStringSync();
    final asked = main.indexOf('useUnblockedWebViewTouches();');
    expect(asked, isNonNegative);
    expect(asked, lessThan(main.indexOf('runApp(')));
    // The shell still wins Flutter's own arena at once, which Android needs.
    expect(File('lib/src/shell_page.dart').readAsStringSync(),
        contains('Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),'));
  });
}
