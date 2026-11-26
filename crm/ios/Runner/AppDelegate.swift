import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "FoorsaCrmPush") {
      PushBridge.shared.attach(registrar.messenger())
    }
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    PushBridge.shared.registered(deviceToken)
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    PushBridge.shared.failed()
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }

  // While the app is on screen the CRM shows its own alerts (the chat's ping,
  // the office phone's ring), so the system banner would say it twice.
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([])
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    PushBridge.shared.tapped(response.notification.request.content.userInfo)
    completionHandler()
  }
}

/// Notifications for the Foorsa CRM app (lib/src/push.dart on the Dart side).
///
/// The token is Apple's own device token, sent to the CRM as `apns:<hex>`;
/// the CRM sends to it straight through Apple (apnsPush.service.ts), with the
/// app's bundle id as the topic. A tapped notification's `route` (a CRM path)
/// is handed to the page.
final class PushBridge: NSObject {
  static let shared = PushBridge()

  private var channel: FlutterMethodChannel?
  private var token: String?
  private var waiting: [FlutterResult] = []
  private var pendingRoute: String?
  private var dartReady = false

  func attach(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "foorsa_crm/push", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result)
    }
    self.channel = channel
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    switch call.method {
    case "ready":
      dartReady = true
      result(pendingRoute)
      pendingRoute = nil
    case "getToken":
      requestToken(result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func requestToken(_ result: @escaping FlutterResult) {
    if let token = token {
      result(token)
      return
    }
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
      DispatchQueue.main.async {
        guard granted else {
          result(nil)
          return
        }
        if let token = self.token {
          result(token)
          return
        }
        self.waiting.append(result)
        UIApplication.shared.registerForRemoteNotifications()
        // Apple usually answers within a second; never leave the page waiting.
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { self.flush(nil) }
      }
    }
  }

  func registered(_ deviceToken: Data) {
    let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
    token = "apns:" + hex
    flush(token)
  }

  func failed() {
    flush(nil)
  }

  private func flush(_ value: String?) {
    let pending = waiting
    waiting = []
    pending.forEach { $0(value) }
  }

  func tapped(_ userInfo: [AnyHashable: Any]) {
    guard let route = userInfo["route"] as? String, route.hasPrefix("/") else { return }
    if dartReady, let channel = channel {
      channel.invokeMethod("open", arguments: route)
    } else {
      pendingRoute = route
    }
  }
}
