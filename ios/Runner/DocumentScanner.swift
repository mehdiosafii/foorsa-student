import AVFoundation
import Flutter
import UIKit

/// Flutter entry point for Foorsa's live AVFoundation + Vision document camera.
/// The bridge returns only final perspective-corrected JPEGs; preview frames,
/// Vision observations, and document hints never leave the device.
final class DocumentScanner: NSObject, FlutterPlugin {
  private let registrar: FlutterPluginRegistrar
  private var pending: FlutterResult?
  private weak var scannerController: FoorsaScannerViewController?
  private var finishing = false

  private init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "foorsa/document_scanner",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(DocumentScanner(registrar: registrar), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "scan" else {
      result(FlutterMethodNotImplemented)
      return
    }
    // The student's language for this scan (ScannerWords); English when the app sends none.
    ScannerWords.use((call.arguments as? [String: Any])?["language"])
    guard pending == nil else {
      result(["error": ScannerWords.say("A scan is already open. Finish or cancel it first.")])
      return
    }
    guard AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil else {
      result(["unsupported": true])
      return
    }
    pending = result
    let profile = FoorsaScannerProfile(arguments: call.arguments)
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      presentScanner(profile: profile)
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
        DispatchQueue.main.async {
          guard let self else { return }
          if granted {
            self.presentScanner(profile: profile)
          } else {
            self.resolve(["error": ScannerWords.say("Allow camera access for Foorsa Student in Settings, then try again.")])
          }
        }
      }
    case .denied, .restricted:
      resolve(["error": ScannerWords.say("Allow camera access for Foorsa Student in Settings, then try again.")])
    @unknown default:
      resolve(["error": ScannerWords.say("The camera permission could not be checked. Please try again.")])
    }
  }

  private func presentScanner(profile: FoorsaScannerProfile) {
    guard let presenter = registrar.viewController,
          presenter.viewIfLoaded?.window != nil,
          presenter.presentedViewController == nil,
          presenter.view.window?.windowScene?.activationState == .foregroundActive else {
      resolve(["error": ScannerWords.say("The camera could not open. Return to your document and try again.")])
      return
    }
    let scanner = FoorsaScannerViewController(profile: profile) { [weak self] response in
      self?.finish(response)
    }
    scannerController = scanner
    presenter.present(scanner, animated: true)
  }

  private func finish(_ response: [String: Any]) {
    guard !finishing else { return }
    finishing = true
    var encoded = response
    if let pages = response["pages"] as? [Data] {
      encoded["pages"] = pages.map(FlutterStandardTypedData.init(bytes:))
    }
    guard let scanner = scannerController else {
      resolve(encoded)
      return
    }
    scanner.dismiss(animated: true) { [weak self] in
      self?.resolve(encoded)
    }
  }

  private func resolve(_ response: [String: Any]) {
    guard let callback = pending else { return }
    pending = nil
    scannerController = nil
    finishing = false
    callback(response)
  }
}
