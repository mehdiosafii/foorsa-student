import Flutter
import UIKit
import UserNotifications
import PushKit
import CallKit
import AVFAudio
import WebRTC
import flutter_callkit_incoming

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, PKPushRegistryDelegate, CallkitIncomingAppDelegate {
  private var voipRegistry: PKPushRegistry?
  private var pendingAnswers: [String: CXAnswerCallAction] = [:]
  private var callChannel: FlutterMethodChannel?
  private var pushChannel: FlutterMethodChannel?
  /// What Apple answered when the app registered for remote notifications. A
  /// build signed without the push entitlement is refused here ("no valid
  /// aps-environment entitlement string found"), and nothing told anyone:
  /// student_push.dart now asks for it (`apnsState`) and reports it.
  private var apnsRegistered = false
  private var apnsError: String?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    RTCAudioSession.sharedInstance().useManualAudio = true
    RTCAudioSession.sharedInstance().isAudioEnabled = false
    // The notification centre's delegate is the app delegate, set before
    // launch ends as Apple requires, and Flutter hands what it hears to every
    // plugin: firebase_messaging and flutter_local_notifications both. Left
    // unset, firebase_messaging made itself the delegate and answered for the
    // local notifications too, with no banner: the app's own banners (a reply
    // while the app is open on another screen, the first notification of the
    // onboarding, a calendar reminder) never showed, and a tap on one never
    // reached the app.
    UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    let registry = PKPushRegistry(queue: .main)
    registry.delegate = self
    registry.desiredPushTypes = [.voIP]
    voipRegistry = registry
    return result
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "FoorsaStudentCalls") {
      let channel = FlutterMethodChannel(name: "ma.foorsa.student/calls", binaryMessenger: registrar.messenger())
      callChannel = channel
      channel.setMethodCallHandler { [weak self] call, result in
        if call.method == "answerReady", let id = call.arguments as? String {
          self?.pendingAnswers.removeValue(forKey: id.lowercased())?.fulfill()
          result(nil)
        } else { result(FlutterMethodNotImplemented) }
      }
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "FoorsaDocumentScanner") {
      DocumentScanner.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "FoorsaStudentPush") {
      let channel = FlutterMethodChannel(name: "ma.foorsa.student/push", binaryMessenger: registrar.messenger())
      pushChannel = channel
      channel.setMethodCallHandler { [weak self] call, result in
        if call.method == "apnsState" {
          var state: [String: Any] = [
            "registered": self?.apnsRegistered ?? false,
            "registeredForRemoteNotifications": UIApplication.shared.isRegisteredForRemoteNotifications,
          ]
          if let error = self?.apnsError { state["error"] = error }
          result(state)
        } else { result(FlutterMethodNotImplemented) }
      }
    }
  }

  override func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    apnsRegistered = true
    apnsError = nil
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    let refusal = error as NSError
    // Apple's words and code only: nothing about the student is in them.
    apnsError = String("\(refusal.domain) \(refusal.code): \(refusal.localizedDescription)".prefix(200))
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }

  func pushRegistry(_ registry: PKPushRegistry, didUpdate credentials: PKPushCredentials, for type: PKPushType) {
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP(credentials.token.map { String(format: "%02x", $0) }.joined())
  }
  func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP("")
  }
  func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
    guard type == .voIP else { completion(); return }
    let input = payload.dictionaryPayload
    // Every VoIP push is reported to CallKit immediately; stale calls are then ended.
    let id = (input["callId"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID()
    let data = flutter_callkit_incoming.Data(id: id.uuidString.lowercased(), nameCaller: String((input["callerName"] as? String ?? "Foorsa adviser").prefix(80)), handle: "Foorsa adviser", type: 0)
    data.duration = 45000
    data.supportsVideo = false
    data.supportsDTMF = false
    data.supportsHolding = false
    data.supportsGrouping = false
    data.supportsUngrouping = false
    data.includesCallsInRecents = false
    data.isShowCallback = false
    data.maximumCallGroups = 1
    data.maximumCallsPerCallGroup = 1
    data.audioSessionMode = "voiceChat"
    data.audioSessionActive = false
    data.extra = ["callId": id.uuidString.lowercased(), "callerName": data.nameCaller,
      "token": input["token"] as? String ?? "", "expiresAt": input["expiresAt"] as? String ?? "", "device": UUID().uuidString.lowercased()]
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.showCallkitIncoming(data, fromPushKit: true) { completion() }
  }
  func onAccept(_ call: Call, _ action: CXAnswerCallAction) {
    let id = call.data.uuid.lowercased()
    pendingAnswers[id] = action
    DispatchQueue.main.asyncAfter(deadline: .now()+25) { [weak self] in
      if let pending = self?.pendingAnswers.removeValue(forKey: id) {
        pending.fail()
        SwiftFlutterCallkitIncomingPlugin.sharedInstance?.endCall(call.data)
      }
    }
  }
  private func finish(_ call: Call, operation: String) {
    pendingAnswers.removeValue(forKey: call.data.uuid.lowercased())?.fail()
    let extra = call.data.extra
    guard let token = extra["token"] as? String, !token.isEmpty,
      let url = URL(string: "https://student.foorsa.ma/api/portal/chat/call/receive") else { return }
    var request = URLRequest(url: url, timeoutInterval: 8)
    request.httpMethod = "POST"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try? JSONSerialization.data(withJSONObject: ["operation": operation, "device": extra["device"] as? String ?? ""])
    URLSession.shared.dataTask(with: request).resume()
  }
  func onDecline(_ call: Call, _ action: CXEndCallAction) { finish(call, operation: "decline"); action.fulfill() }
  func onEnd(_ call: Call, _ action: CXEndCallAction) { finish(call, operation: "end"); action.fulfill() }
  func onTimeOut(_ call: Call) { finish(call, operation: "end") }
  func didActivateAudioSession(_ audioSession: AVAudioSession) {
    RTCAudioSession.sharedInstance().audioSessionDidActivate(audioSession)
    RTCAudioSession.sharedInstance().isAudioEnabled = true
  }
  func didDeactivateAudioSession(_ audioSession: AVAudioSession) {
    RTCAudioSession.sharedInstance().audioSessionDidDeactivate(audioSession)
    RTCAudioSession.sharedInstance().isAudioEnabled = false
  }
  func providerDidReset() {
    callChannel?.invokeMethod("reset", arguments: nil)
    pendingAnswers.values.forEach { $0.fail() }; pendingAnswers.removeAll()
    RTCAudioSession.sharedInstance().isAudioEnabled = false
  }
}
