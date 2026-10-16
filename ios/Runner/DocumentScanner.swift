import Flutter
import UIKit
import VisionKit

/// Uses the system document camera: live quadrilaterals, auto/manual capture,
/// perspective correction and the user's chosen colour treatment. No preview
/// frames or temporary passport files are written by the app.
final class DocumentScanner: NSObject, FlutterPlugin, VNDocumentCameraViewControllerDelegate {
  private let registrar: FlutterPluginRegistrar
  private var pending: FlutterResult?
  private var exporting = false
  private var finishing = false

  private init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "foorsa/document_scanner", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(DocumentScanner(registrar: registrar), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "scan" else { result(FlutterMethodNotImplemented); return }
    guard pending == nil else {
      result(["error": "A scan is already open. Finish or cancel it first."])
      return
    }
    guard VNDocumentCameraViewController.isSupported else {
      result(["unsupported": true])
      return
    }
    guard let presenter = registrar.viewController,
          presenter.viewIfLoaded?.window != nil,
          presenter.presentedViewController == nil,
          presenter.view.window?.windowScene?.activationState == .foregroundActive else {
      result(["error": "The camera could not open. Return to your document and try again."])
      return
    }
    let camera = VNDocumentCameraViewController()
    camera.delegate = self
    camera.modalPresentationStyle = .fullScreen
    pending = result
    presenter.present(camera, animated: true)
  }

  func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
    guard !exporting else { return }
    finish(controller, response: ["cancelled": true])
  }

  func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
    finish(controller, response: ["error": "The document camera stopped. Please open Scan document and try again."])
  }

  func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
    guard pending != nil, !exporting else { return }
    guard scan.pageCount > 0 else {
      finish(controller, response: ["cancelled": true])
      return
    }
    // Never truncate a scan. Leave the system review open so the student can
    // remove pages or cancel rather than silently losing part of a document.
    guard scan.pageCount <= 20 else {
      showExportError(controller, message: "Please keep up to 20 pages in one document. You can upload the remaining pages as another document.")
      return
    }
    exporting = true
    let overlay = UIView(frame: controller.view.bounds)
    overlay.backgroundColor = UIColor.black.withAlphaComponent(0.45)
    overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    let spinner = UIActivityIndicatorView(style: .large)
    spinner.color = .white
    spinner.center = CGPoint(x: overlay.bounds.midX, y: overlay.bounds.midY)
    spinner.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin, .flexibleTopMargin, .flexibleBottomMargin]
    spinner.accessibilityLabel = "Preparing scanned pages"
    spinner.startAnimating()
    overlay.addSubview(spinner)
    controller.view.addSubview(overlay)

    // Fetch one system image on the main thread, then resize/encode it off the
    // UI thread. Keeping at most one full-resolution page avoids an OOM on a
    // long scan. A total byte budget also bounds the subsequent WebView bridge.
    var pages = [FlutterStandardTypedData]()
    var totalBytes = 0
    func exportPage(_ index: Int) {
      guard self.pending != nil, !self.finishing else { overlay.removeFromSuperview(); return }
      if index == scan.pageCount {
        overlay.removeFromSuperview()
        self.finish(controller, response: ["pages": pages])
        return
      }
      let image = scan.imageOfPage(at: index)
      DispatchQueue.global(qos: .userInitiated).async {
        let bytes: Data? = autoreleasepool {
          let maxEdge: CGFloat = 2600
          let scale = min(1, maxEdge / max(image.size.width, image.size.height))
          let size = CGSize(width: max(1, (image.size.width * scale).rounded()),
                            height: max(1, (image.size.height * scale).rounded()))
          let format = UIGraphicsImageRendererFormat()
          format.scale = 1
          format.opaque = true
          let flattened = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
          }
          return flattened.jpegData(compressionQuality: 0.93)
        }
        DispatchQueue.main.async {
          guard self.pending != nil, !self.finishing else { overlay.removeFromSuperview(); return }
          guard let bytes = bytes, !bytes.isEmpty,
                totalBytes + bytes.count <= 24 * 1024 * 1024 else {
            pages.removeAll()
            overlay.removeFromSuperview()
            self.exporting = false
            self.showExportError(controller, message: "This scan is too large to prepare. Please remove some pages and save them as a separate document.")
            return
          }
          totalBytes += bytes.count
          pages.append(FlutterStandardTypedData(bytes: bytes))
          exportPage(index + 1)
        }
      }
    }
    exportPage(0)
  }

  private func showExportError(_ controller: UIViewController, message: String) {
    let alert = UIAlertController(title: "Review your scan", message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "Review pages", style: .default))
    controller.present(alert, animated: true)
  }

  private func finish(_ controller: UIViewController, response: [String: Any]) {
    guard let callback = pending, !finishing else { return }
    finishing = true
    // Keep the busy guard until dismissal completes, so a second bridge call
    // cannot present on a controller that is still disappearing.
    controller.dismiss(animated: true) {
      self.pending = nil
      self.exporting = false
      self.finishing = false
      callback(response)
    }
  }
}
