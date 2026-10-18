import AVFoundation
import ImageIO
import UIKit
import Vision

private final class ScannerBurstCancellationToken {
  private let lock = NSLock()
  private var cancelled = false

  var isCancelled: Bool {
    lock.lock()
    defer { lock.unlock() }
    return cancelled
  }

  func cancel() {
    lock.lock()
    cancelled = true
    lock.unlock()
  }
}

enum ScannerSinglePageCaptureResolution: Equatable {
  case retry(String)
  case complete(Data)
  case ignored
}

struct ScannerSinglePageCompletionFlow {
  private(set) var isFinished = false

  mutating func terminate() -> Bool {
    guard !isFinished else { return false }
    isFinished = true
    return true
  }

  mutating func resolve(_ candidates: [ScannerProcessedCandidate]) -> ScannerSinglePageCaptureResolution {
    guard !isFinished else { return .ignored }
    guard let best = ScannerCandidateSelector.best(candidates) else {
      return .retry("Could not get a sharp, complete page. Keep every corner visible, hold still, and try again.")
    }
    isFinished = true
    return .complete(best.jpeg)
  }
}

final class FoorsaScannerViewController: UIViewController {
#if SCANNER_DIAGNOSTICS
  // Only local diagnostic targets define this flag. Production has no raw-photo
  // observer or persistence path; the ordinary bridge still returns one page.
  private var diagnosticPreviewOnly = false
  var diagnosticCapturedPhoto: ((Data) -> Void)?
  var diagnosticEvent: (([String: Any]) -> Void)?
  var diagnosticPreviewFrame: ((Data) -> Void)?
  private let diagnosticPreviewContext = CIContext(options: [.cacheIntermediates: false])
  private var diagnosticPreviewCount = 0
  private var diagnosticLastPreviewTime: TimeInterval = 0
  func finishDiagnosticCapture() { cancelPressed() }
#endif
  typealias Completion = ([String: Any]) -> Void

  private let profile: FoorsaScannerProfile
  private let completion: Completion
  private let session = AVCaptureSession()
  private let sessionQueue = DispatchQueue(label: "ma.foorsa.scanner.session", qos: .userInitiated)
  private let visionQueue = DispatchQueue(label: "ma.foorsa.scanner.vision", qos: .userInitiated)
  private let processingQueue = DispatchQueue(
    label: "ma.foorsa.scanner.processing",
    qos: .userInitiated
  )
  private let orientationLock = NSLock()
  private let photoOutput = AVCapturePhotoOutput()
  private let videoOutput = AVCaptureVideoDataOutput()
  private let processor = ScannerImageProcessor()
  private var previewLayer: AVCaptureVideoPreviewLayer!
  private let overlay = ScannerOverlayView()
  private let guidanceView = ScannerGuidanceView()
  private let torchButton = UIButton(type: .system)
  private let interruptionView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
  private var tracker = ScannerStabilityTracker()
  private var completionFlow = ScannerSinglePageCompletionFlow()
  private var lastAnalysisTime: TimeInterval = 0
  private var latestQuadrilateral: ScannerQuadrilateral?
  private var latestImageSize: CGSize?
  private var latestDetectionTime: TimeInterval = 0
  private var isAnalyzing = false
  private var isCapturing = false
  private var burstRemaining = 0
  private var photosTaken = 0
  private var burstCandidates: [ScannerProcessedCandidate] = []
  private var activePhotoIDs = Set<Int64>()
  private var originalPhotos = ScannerOriginalPhotoPool()
  private var capturedGeometry: [Int64: (quad: ScannerQuadrilateral, size: CGSize)] = [:]
  private var pendingProcessingCount = 0
  private var captureGeneration = 0
  private var captureCancellation: ScannerBurstCancellationToken?
  private var lightingAngleGuide: ScannerAdaptiveCaptureGuide?
  private var nextViewDetail = "Tilt the phone slightly to reveal more detail. Keep the page flat."
  private var capturePhase = 0
  private var captureSettleEpoch = 0
  private var captureSettling = false
  private var captureSettlePolicy = ScannerCaptureSettlePolicy()
  private var captureSettleAnchor: ScannerQuadrilateral?
  private var captureSettleCameraType: String?
  private var lightingRetryAnchor: ScannerQuadrilateral?
  private var lightingRetryMissingSince: TimeInterval?
  private static let captureRetryMessage = "Reframe the page"
  private var retryTitle = captureRetryMessage
  private var retryDetail = "Keep the page flat and all four corners visible. Tilt slightly, then hold still."
  private var lastCaptureTime: TimeInterval = 0
  private var configured = false
  private var finishing = false
  private var imageOrientation: CGImagePropertyOrientation = .right
  private var analysisActive = false
  private var captureAnalysisPaused = false
  private var analysisEpoch: UInt = 0
  private var observers: [NSObjectProtocol] = []
  private var portraitConstraints: [NSLayoutConstraint] = []
  private var landscapeConstraints: [NSLayoutConstraint] = []
  private var usesLandscapeControls = false

  init(profile: FoorsaScannerProfile, completion: @escaping Completion) {
    self.profile = profile
    self.completion = completion
    tracker = ScannerStabilityTracker(minimumArea: profile.minimumCaptureArea)
    super.init(nibName: nil, bundle: nil)
    modalPresentationStyle = .fullScreen
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    configurePreview()
    configureInterface()
#if SCANNER_DIAGNOSTICS
    if diagnosticPreviewOnly { return }
#endif
    observeSession()
    configureSession()
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    setAnalysisActive(true)
    startSession()
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    abortCapture()
    setAnalysisActive(false)
    stopSession()
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    overlay.frame = view.bounds
    interruptionView.frame = view.bounds
    updateVideoOrientation()
    updatePreviewGeometry()
    renderQuadrilateral(latestQuadrilateral, imageSize: latestImageSize)
  }

  override func viewWillLayoutSubviews() {
    super.viewWillLayoutSubviews()
    guidanceView.updateTypography(compatibleWith: view.traitCollection)
    let landscape = view.bounds.width > view.bounds.height
    if landscape != usesLandscapeControls {
      NSLayoutConstraint.deactivate(usesLandscapeControls ? landscapeConstraints : portraitConstraints)
      usesLandscapeControls = landscape
      NSLayoutConstraint.activate(landscape ? landscapeConstraints : portraitConstraints)
    }
  }

  private func updatePreviewGeometry() {
    let safe = view.safeAreaLayoutGuide.layoutFrame
    let available: CGRect
    if usesLandscapeControls {
      available = CGRect(x: safe.minX + 12, y: safe.minY + 67,
        width: max(0, guidanceView.frame.minX - 24 - safe.minX),
        height: max(0, safe.height - 79))
    } else {
      available = CGRect(x: safe.minX + 12, y: safe.minY + 67,
        width: max(0, safe.width - 24),
        height: max(0, guidanceView.frame.minY - 12 - safe.minY - 67))
    }
    let fallbackSize = usesLandscapeControls
      ? CGSize(width: 4, height: 3) : CGSize(width: 3, height: 4)
    let geometry = ScannerPreviewGeometry(imageSize: latestImageSize ?? fallbackSize,
      availableRect: available, guideAspectRatio: overlay.guideAspectRatio)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    previewLayer.frame = geometry.previewRect
    CATransaction.commit()
    overlay.guideRect = geometry.guideRect
  }

  deinit {
    observers.forEach(NotificationCenter.default.removeObserver)
  }

  private func configurePreview() {
    previewLayer = AVCaptureVideoPreviewLayer(session: session)
    previewLayer.videoGravity = .resizeAspectFill
    view.layer.addSublayer(previewLayer)
    overlay.backgroundColor = .clear
    overlay.guideAspectRatio = switch profile.layout {
    case .passport: 1.42
    case .card: 1.585
    case .portrait: 0.71
    case .adaptive: 0.71
    }
    overlay.isUserInteractionEnabled = false
    view.addSubview(overlay)
  }

  private func configureInterface() {
    let chrome = UIView()
    chrome.translatesAutoresizingMaskIntoConstraints = false
    chrome.backgroundColor = UIColor.black.withAlphaComponent(0.48)
    view.addSubview(chrome)

    let cancel = UIButton(type: .system)
    cancel.translatesAutoresizingMaskIntoConstraints = false
    cancel.setTitle("Cancel", for: .normal)
    cancel.setTitleColor(.white, for: .normal)
    cancel.titleLabel?.font = .preferredFont(forTextStyle: .headline)
    cancel.addTarget(self, action: #selector(cancelPressed), for: .touchUpInside)
    cancel.accessibilityHint = "Closes the scanner without capturing the document"

    let titleLabel = UILabel()
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.text = profile.title
    titleLabel.textColor = .white
    titleLabel.font = .preferredFont(forTextStyle: .headline)
    titleLabel.textAlignment = .center
    titleLabel.adjustsFontForContentSizeCategory = true
    titleLabel.minimumScaleFactor = 0.72
    titleLabel.adjustsFontSizeToFitWidth = true

    chrome.addSubview(cancel)
    chrome.addSubview(titleLabel)

    guidanceView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(guidanceView)
    showPlacementGuide()

    torchButton.translatesAutoresizingMaskIntoConstraints = false
    torchButton.setImage(UIImage(systemName: "flashlight.off.fill"), for: .normal)
    torchButton.tintColor = .white
    torchButton.backgroundColor = UIColor.black.withAlphaComponent(0.58)
    torchButton.layer.cornerRadius = 24
    torchButton.addTarget(self, action: #selector(torchPressed), for: .touchUpInside)
    torchButton.accessibilityLabel = "Turn torch on"
    view.addSubview(torchButton)

    interruptionView.isHidden = true
    interruptionView.translatesAutoresizingMaskIntoConstraints = false
    let resume = UIButton(type: .system)
    resume.translatesAutoresizingMaskIntoConstraints = false
    var resumeConfiguration = UIButton.Configuration.filled()
    resumeConfiguration.title = "Resume scanning"
    resumeConfiguration.image = UIImage(systemName: "camera.fill")
    resumeConfiguration.imagePadding = 8
    resume.configuration = resumeConfiguration
    resume.addTarget(self, action: #selector(resumePressed), for: .touchUpInside)
    interruptionView.contentView.addSubview(resume)
    view.addSubview(interruptionView)

    portraitConstraints = [
      guidanceView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
      guidanceView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
      guidanceView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -18),
    ]
    landscapeConstraints = [
      guidanceView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
      guidanceView.widthAnchor.constraint(equalTo: view.safeAreaLayoutGuide.widthAnchor, multiplier: 0.34),
      guidanceView.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor, constant: 20),
      guidanceView.topAnchor.constraint(greaterThanOrEqualTo: chrome.bottomAnchor, constant: 8),
      guidanceView.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
    ]
    NSLayoutConstraint.activate(portraitConstraints)
    NSLayoutConstraint.activate([
      chrome.topAnchor.constraint(equalTo: view.topAnchor),
      chrome.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      chrome.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      chrome.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 55),
      cancel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 14),
      cancel.bottomAnchor.constraint(equalTo: chrome.bottomAnchor, constant: -10),
      cancel.widthAnchor.constraint(greaterThanOrEqualToConstant: 58),
      cancel.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
      titleLabel.leadingAnchor.constraint(equalTo: cancel.trailingAnchor, constant: 6),
      titleLabel.trailingAnchor.constraint(equalTo: torchButton.leadingAnchor, constant: -8),
      titleLabel.centerYAnchor.constraint(equalTo: cancel.centerYAnchor),
      torchButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -14),
      torchButton.centerYAnchor.constraint(equalTo: cancel.centerYAnchor),
      torchButton.widthAnchor.constraint(equalToConstant: 48),
      torchButton.heightAnchor.constraint(equalToConstant: 48),
      interruptionView.topAnchor.constraint(equalTo: view.topAnchor),
      interruptionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      interruptionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      interruptionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      resume.centerXAnchor.constraint(equalTo: interruptionView.contentView.centerXAnchor),
      resume.centerYAnchor.constraint(equalTo: interruptionView.contentView.centerYAnchor),
      resume.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
    ])
  }

  private func configureSession() {
    sessionQueue.async { [weak self] in
      guard let self else { return }
      self.session.beginConfiguration()
      self.session.sessionPreset = .photo
      defer { self.session.commitConfiguration() }
      // Use automatic macro switching only on devices whose close lens can
      // autofocus nearer than the ordinary wide camera. Older phones keep wide.
      let wide = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
      let close = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back)
      let supportsCloseFocus = close?.isFocusModeSupported(.continuousAutoFocus) == true
        && (close?.minimumFocusDistance ?? -1) > 0
        && (close?.minimumFocusDistance ?? 9999) < (wide?.minimumFocusDistance ?? 0)
      let automatic = supportsCloseFocus
        ? AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back) : nil
      guard let camera = automatic ?? wide,
            let input = try? AVCaptureDeviceInput(device: camera),
            self.session.canAddInput(input) else {
        DispatchQueue.main.async { self.fail("The back camera is unavailable.") }
        return
      }
      self.session.addInput(input)
      self.videoOutput.alwaysDiscardsLateVideoFrames = true
      self.videoOutput.videoSettings = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
      ]
      self.videoOutput.setSampleBufferDelegate(self, queue: self.visionQueue)
      guard self.session.canAddOutput(self.videoOutput), self.session.canAddOutput(self.photoOutput) else {
        DispatchQueue.main.async { self.fail("The camera could not start document capture.") }
        return
      }
      self.session.addOutput(self.videoOutput)
      self.session.addOutput(self.photoOutput)
      // A short document burst needs consistent latency. Twelve-megapixel
      // sources retain ample detail for the final 2600px page without three
      // simultaneous 48MP buffers on recent iPhones.
      self.photoOutput.maxPhotoQualityPrioritization = .quality
      if #available(iOS 16.0, *),
         let dimensions = camera.activeFormat.supportedMaxPhotoDimensions
          .filter({ Int64($0.width) * Int64($0.height) <= 12_500_000 })
          .max(by: { Int64($0.width) * Int64($0.height) < Int64($1.width) * Int64($1.height) })
          ?? camera.activeFormat.supportedMaxPhotoDimensions.first {
        self.photoOutput.maxPhotoDimensions = dimensions
      } else {
        self.photoOutput.isHighResolutionCaptureEnabled = true
      }
      do {
        try camera.lockForConfiguration()
        if camera.isVirtualDevice, let matchingWideZoom = camera.virtualDeviceSwitchOverVideoZoomFactors.first {
          camera.videoZoomFactor = max(camera.minAvailableVideoZoomFactor,
            min(camera.maxAvailableVideoZoomFactor, CGFloat(truncating: matchingWideZoom)))
          if camera.primaryConstituentDeviceSwitchingBehavior != .unsupported {
            camera.setPrimaryConstituentDeviceSwitchingBehavior(.auto, restrictedSwitchingBehaviorConditions: [])
          }
        }
        if camera.isFocusModeSupported(.continuousAutoFocus) { camera.focusMode = .continuousAutoFocus }
        if camera.isExposureModeSupported(.continuousAutoExposure) { camera.exposureMode = .continuousAutoExposure }
        camera.isSubjectAreaChangeMonitoringEnabled = true
        camera.unlockForConfiguration()
      } catch { /* Continuous defaults remain usable. */ }
      self.configured = true
      DispatchQueue.main.async { [weak self] in
        self?.updateVideoOrientation()
        self?.startSession()
      }
    }
  }

  private func observeSession() {
    let center = NotificationCenter.default
    observers.append(center.addObserver(
      forName: .AVCaptureSessionWasInterrupted,
      object: session,
      queue: .main
    ) { [weak self] _ in
      self?.setAnalysisActive(false)
      self?.abortCapture()
      self?.interruptionView.isHidden = false
      self?.guidanceView.show(title: "Camera paused", detail: "Resume when you’re ready.", stage: 0, accepted: 0, holding: false)
      UIAccessibility.post(notification: .announcement, argument: "Camera paused")
    })
    observers.append(center.addObserver(
      forName: .AVCaptureSessionInterruptionEnded,
      object: session,
      queue: .main
    ) { [weak self] _ in self?.resumeSession() })
    observers.append(center.addObserver(
      forName: .AVCaptureSessionRuntimeError,
      object: session,
      queue: .main
    ) { [weak self] notification in
      guard let self else { return }
      self.setAnalysisActive(false)
      let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError
      if error?.code == .mediaServicesWereReset {
        self.abortCapture()
        self.resumeSession()
      } else {
        self.abortCapture()
        self.interruptionView.isHidden = false
        self.guidanceView.show(title: "Camera unavailable", detail: "Tap Resume scanning.", stage: 0, accepted: 0, holding: false)
      }
    })
    observers.append(center.addObserver(
      forName: UIApplication.didEnterBackgroundNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.setAnalysisActive(false)
      self?.abortCapture()
      self?.stopSession()
    })
    observers.append(center.addObserver(
      forName: UIApplication.willEnterForegroundNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in self?.resumeSession() })
  }

  private func startSession() {
    sessionQueue.async { [weak self] in
      guard let self, self.configured, !self.finishing, !self.session.isRunning else { return }
      self.session.startRunning()
    }
  }

  private func stopSession() {
    sessionQueue.async { [weak self] in
      guard let self, self.session.isRunning else { return }
      self.session.stopRunning()
    }
  }

  private func resumeSession() {
    interruptionView.isHidden = true
    showPlacementGuide()
    if viewIfLoaded?.window != nil { setAnalysisActive(true) }
    startSession()
  }

  @objc private func resumePressed() { resumeSession() }

  @objc private func cancelPressed() {
    guard !finishing, completionFlow.terminate() else { return }
    finishing = true
    abortCapture()
    completion(["cancelled": true])
  }

  private func beginCapture() {
    guard !isCapturing, !finishing, configured, session.isRunning, !session.isInterrupted else { return }
#if SCANNER_DIAGNOSTICS
    diagnosticEvent?(["event": "capture_started"])
#endif
    isCapturing = true
    setCaptureAnalysisPaused(true)
    captureGeneration += 1
    captureCancellation = ScannerBurstCancellationToken()
    burstRemaining = 1
    photosTaken = 0
    lightingAngleGuide = latestQuadrilateral.flatMap { anchor in
      latestImageSize.map {
        ScannerAdaptiveCaptureGuide(anchor: anchor, imageSize: $0, minimumArea: profile.minimumCaptureArea, at: CACurrentMediaTime(), requiresNovelViews: profile.usesImagegen)
      }
    }
    nextViewDetail = "Tilt the phone slightly to reveal more detail. Keep the page flat."
    originalPhotos.reset()
    capturedGeometry.removeAll()
    burstCandidates.removeAll(keepingCapacity: true)
    activePhotoIDs.removeAll(keepingCapacity: true)
    pendingProcessingCount = 0
    tracker.reset()
    lastCaptureTime = CACurrentMediaTime()
    setCaptureControls(enabled: false)
    guidanceView.show(title: "Hold still", detail: "Capturing clear detail automatically.",
      stage: 0, accepted: 0, holding: true)
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    captureNextCandidate()
    armCaptureTimeout(seconds: 20, waitingForAngle: false)
    let generation = captureGeneration
    DispatchQueue.main.asyncAfter(deadline: .now() + ScannerAdaptiveCaptureGuide.totalCaptureDuration) { [weak self] in
      guard let self, self.isCapturing, self.captureGeneration == generation else { return }
      self.retryLightingCapture(detail: "Not enough clear views were captured. Keep the page flat, reframe, and try again.")
    }
  }

  private func armCaptureTimeout(seconds: TimeInterval, waitingForAngle: Bool,
                                 failureMessage: String = "The camera took too long. Keep the document visible and try again.") {
    capturePhase += 1
    let phase = capturePhase
    let generation = captureGeneration
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
      guard let self, self.isCapturing, self.captureGeneration == generation,
            self.capturePhase == phase else { return }
      if waitingForAngle {
        self.retryLightingCapture()
      } else {
        self.abortCapture()
        self.showMessage(failureMessage)
      }
    }
  }

  private func captureNextCandidate() {
    guard !finishing, isCapturing else { return }
    guard !captureSettling else { return }
    guard burstRemaining > 0 else {
      finishBurstIfReady()
      return
    }
    guard photosTaken < ScannerAdaptiveCaptureGuide.maximumAttempts,
          !profile.usesImagegen || !originalPhotos.isFull else {
      retryLightingCapture()
      return
    }
    beginCaptureSettling()
  }

  private func beginCaptureSettling() {
    guard !finishing, isCapturing, !captureSettling, burstRemaining > 0 else { return }
    captureSettling = true
    captureSettleEpoch &+= 1
    let epoch = captureSettleEpoch
    let generation = captureGeneration
    captureSettlePolicy.begin(at: CACurrentMediaTime())
    captureSettleAnchor = latestQuadrilateral
    captureSettleCameraType = nil
    // Keep checking the page while focus settles. The old accepted outline
    // cannot authorize a photo after the user moves to another angle.
    setCaptureAnalysisPaused(false)
    guidanceView.show(title: "Hold still", detail: "Focusing and balancing light…",
      stage: min(2, burstCandidates.count),
      accepted: burstCandidates.count, holding: true)
#if SCANNER_DIAGNOSTICS
    diagnosticEvent?(cameraDiagnosticFields(event: "capture_settle_started", elapsed: 0))
#endif
    pollCaptureSettling(epoch: epoch, generation: generation)
  }

  private func pollCaptureSettling(epoch: Int, generation: Int) {
    guard captureSettling, isCapturing, !finishing,
          captureSettleEpoch == epoch, captureGeneration == generation else { return }
    let now = CACurrentMediaTime()
    if lightingAngleGuide?.hasExpired(at: now) == true {
      retryLightingCapture()
      return
    }
    let camera = (session.inputs.first as? AVCaptureDeviceInput)?.device
    let documentIsStable = latestQuadrilateral.flatMap { current in
      captureSettleAnchor.map { current.maximumCornerDistance(to: $0) <= 0.018 }
    } == true && latestDetectionTime >= (captureSettlePolicy.startedAt ?? now)
      && now - latestDetectionTime <= ScannerStabilityTracker.maximumObservationAge
    let activeCamera = camera?.activePrimaryConstituent ?? camera
    let cameraType = activeCamera?.deviceType.rawValue
    let cameraIsStable = cameraType != nil && captureSettleCameraType == cameraType
    captureSettleCameraType = cameraType
    let observation = captureSettlePolicy.observe(
      at: now,
      isAdjustingFocus: activeCamera?.isAdjustingFocus ?? true,
      isAdjustingExposure: activeCamera?.isAdjustingExposure ?? true,
      lensPosition: activeCamera?.lensPosition ?? .nan,
      documentIsStable: documentIsStable && cameraIsStable
    )
    switch observation {
    case .ready:
      let settleElapsed = captureSettlePolicy.startedAt.map { now - $0 } ?? 0
      captureSettling = false
      captureSettlePolicy.cancel()
      captureSettleAnchor = nil
      setCaptureAnalysisPaused(true)
      guard burstRemaining > 0 else { return }
      // Only count a photo once the still has actually been handed to AVFoundation.
      burstRemaining -= 1
      photosTaken += 1
      let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
      settings.photoQualityPrioritization = .quality
      if #available(iOS 16.0, *) {
        settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions
      } else {
        settings.isHighResolutionPhotoEnabled = true
      }
      if let camera, camera.isFlashAvailable { settings.flashMode = .off }
      activePhotoIDs.insert(settings.uniqueID)
      if profile.usesImagegen, let quad = latestQuadrilateral, let size = latestImageSize,
         quad.isComplete(minimumArea: profile.minimumCaptureArea) {
        capturedGeometry[settings.uniqueID] = (quad, size)
      }
#if SCANNER_DIAGNOSTICS
      diagnosticEvent?(cameraDiagnosticFields(event: "capture_triggered",
        elapsed: settleElapsed))
#endif
      photoOutput.capturePhoto(with: settings, delegate: self)
    case .expired:
      captureSettling = false
      captureSettlePolicy.cancel()
#if SCANNER_DIAGNOSTICS
      var expiry = cameraDiagnosticFields(event: "capture_settle_expired", elapsed: ScannerCaptureSettlePolicy.maximumWait)
      expiry["documentIsStable"] = documentIsStable
      diagnosticEvent?(expiry)
#endif
      let detail = documentIsStable
        ? "The camera is still focusing. Hold this angle and try again."
        : "The page moved while the camera was settling. Keep all four corners visible and hold still."
      if lightingAngleGuide?.pendingCaptureView != nil {
        lightingAngleGuide?.resolveCapture(accepted: false)
        burstRemaining = 0
        nextViewDetail = detail
        beginNextAngle()
      } else {
        abortCapture()
        showMessage(detail)
      }
    case .waiting:
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
        self?.pollCaptureSettling(epoch: epoch, generation: generation)
      }
    case .inactive:
      captureSettling = false
    }
  }

#if SCANNER_DIAGNOSTICS
  private func cameraDiagnosticFields(event: String, elapsed: TimeInterval) -> [String: Any] {
    let camera = (session.inputs.first as? AVCaptureDeviceInput)?.device
    let activeCamera = camera?.activePrimaryConstituent ?? camera
    return [
      "event": event,
      "cameraType": camera?.deviceType.rawValue ?? "unknown",
      "activeCameraType": activeCamera?.deviceType.rawValue ?? "unknown",
      "minFocusDistance": activeCamera?.minimumFocusDistance ?? -1,
      "zoomFactor": Double(camera?.videoZoomFactor ?? 1),
      "lensPosition": activeCamera?.lensPosition ?? -1,
      "isAdjustingFocus": activeCamera?.isAdjustingFocus ?? true,
      "isAdjustingExposure": activeCamera?.isAdjustingExposure ?? true,
      "settleElapsedMilliseconds": elapsed * 1000,
    ]
  }
#endif

  private func finishBurstIfReady() {
    guard isCapturing, lightingAngleGuide?.isWaiting != true, burstRemaining == 0,
          activePhotoIDs.isEmpty, pendingProcessingCount == 0 else { return }
    if profile.usesImagegen {
      if originalPhotos.canComplete(usefulViews: burstCandidates.count) {
        completeImagegenCapture()
      } else if !originalPhotos.photos.isEmpty && !originalPhotos.isFull {
        beginNextAngle()
      } else {
        retryLightingCapture(title: "Try again",
          detail: "Keep the whole page visible and hold still for clear photos.")
      }
      return
    }
    guard !burstCandidates.isEmpty else {
      retryLightingCapture(title: "Try again",
        detail: "The camera couldn’t save a clear photo. Keep the whole page visible and reframe.")
      return
    }
    guard burstCandidates.count >= ScannerAdaptiveCaptureGuide.minimumFramesForEvaluation else {
      beginNextAngle()
      return
    }
    finishBurst()
  }

  private func beginNextAngle() {
    guard !profile.usesImagegen || !originalPhotos.isFull else {
      retryLightingCapture(detail: "More clear detail is needed. Reframe the page and hold still.")
      return
    }
    guard lightingAngleGuide?.beginWaiting(at: CACurrentMediaTime()) == true else {
      retryLightingCapture()
      return
    }
    tracker.reset()
    overlay.progress = 0
    setCaptureAnalysisPaused(false)
    showAngleGuide()
    UIAccessibility.post(notification: .announcement, argument: lightingAngleInstruction)
    armCaptureTimeout(seconds: ScannerAdaptiveCaptureGuide.waitDuration, waitingForAngle: true)
  }

  private func abortCapture() {
    guard isCapturing else { return }
#if SCANNER_DIAGNOSTICS
    diagnosticEvent?(["event": "capture_aborted", "candidates": burstCandidates.count])
#endif
    isCapturing = false
    captureSettling = false
    captureSettleEpoch &+= 1
    captureSettlePolicy.cancel()
    captureSettleAnchor = nil
    capturePhase += 1
    lightingAngleGuide?.cancel()
    lightingAngleGuide = nil
    captureCancellation?.cancel()
    captureCancellation = nil
    setCaptureAnalysisPaused(false)
    captureGeneration += 1
    activePhotoIDs.removeAll()
    capturedGeometry.removeAll()
    originalPhotos.reset()
    pendingProcessingCount = 0
    burstRemaining = 0
    burstCandidates.removeAll()
    tracker.reset()
    setCaptureControls(enabled: true)
  }

  private func completeImagegenCapture() {
    guard profile.usesImagegen, isCapturing, !finishing,
          lightingAngleGuide?.hasExpired(at: CACurrentMediaTime()) == false,
          originalPhotos.canComplete(usefulViews: burstCandidates.count) else { return }
    let originals = originalPhotos.photos
    let count = burstCandidates.count
    let attempts = photosTaken
    switch completionFlow.resolve(burstCandidates) {
    case let .complete(page):
      finishing = true
      abortCapture()
      guidanceView.show(title: "Photos ready", detail: "Preparing your fields for review.",
        stage: 2, accepted: count, holding: false)
      UINotificationFeedbackGenerator().notificationOccurred(.success)
      completion([
        "pages": [page], "originals": originals, "processing": "imagegen",
        "engine": "avfoundation_vision", "scannerBuild": "custom-live-v9",
        "capabilities": ["live_quadrilateral", "stable_auto_capture",
          "adaptive_multi_view_capture", "perspective_correction", "automatic_single_page",
          "bounded_adaptive_capture", "visual_capture_guide", "original_camera_jpegs",
          "source_photo_ocr_preview", "async_crm_enhancement"],
        "burstProcessing": ["mode": "imagegen", "photosTaken": attempts,
          "retainedUsefulViews": count, "originalPhotos": originals.count,
          "framesUsed": 1],
      ])
    case let .retry(message): retryLightingCapture(detail: message)
    case .ignored: break
    }
  }

  private func finishBurst() {
    guard let cancellation = captureCancellation else { return }
    let generation = captureGeneration
    let candidates = burstCandidates
    pendingProcessingCount = 1
    armCaptureTimeout(seconds: 20, waitingForAngle: false,
      failureMessage: "Combining the views took too long. Keep the page flat and try again.")
    guidanceView.show(title: "Checking the detail", detail: "Combining useful photos and checking what is still unclear.",
      stage: 2, accepted: burstCandidates.count, holding: false)
    processingQueue.async { [weak self] in
      guard let self, !cancellation.isCancelled else { return }
      let resolution = self.processor.resolveAdaptiveCapture(
        candidates,
        profile: self.profile,
        isCancelled: { cancellation.isCancelled }
      )
      DispatchQueue.main.async { [weak self] in
        guard let self, self.isCapturing,
              self.captureGeneration == generation, !self.finishing else { return }
        self.pendingProcessingCount = 0
        self.completeBurst(resolution)
      }
    }
  }

  private func completeBurst(_ resolution: ScannerBurstResolution?) {
    guard lightingAngleGuide?.hasExpired(at: CACurrentMediaTime()) == false else {
      retryLightingCapture()
      return
    }
#if SCANNER_DIAGNOSTICS
    diagnosticEvent?(["event": "burst_resolved", "candidates": burstCandidates.count,
      "resolved": resolution != nil,
      "mode": resolution?.mode.rawValue ?? "none",
      "fallbackReason": resolution?.fallbackReason?.rawValue ?? "none",
      "framesUsed": resolution?.framesUsed ?? 0,
      "needsDifferentAngle": resolution?.lighting?.needsDifferentAngle ?? false])
#endif
    guard burstCandidates.count >= ScannerAdaptiveCaptureGuide.minimumFramesForEvaluation else {
      beginNextAngle()
      return
    }
    // A failed comparison asks for another useful view while preserving earlier
    // clear photos. Only verified fusion can end adaptive capture.
    guard let resolution, resolution.mode != .bestFrameFallback,
          resolution.lighting?.needsDifferentAngle != true else {
      switch resolution?.fallbackReason {
      case .frameTooSoft:
        nextViewDetail = "Some detail is unclear. Hold still and keep shadows off the page."
      case .incompatibleGeometry, .registrationRejected, .frameContentMismatch:
        nextViewDetail = "Keep the page flat and tilt just a little. Earlier clear photos are saved."
      default:
        nextViewDetail = "Move the phone slightly until the reflection and phone shadow leave the page."
      }
      beginNextAngle()
      return
    }
    defer {
      capturePhase += 1
      captureSettling = false
      captureSettleEpoch &+= 1
      captureSettlePolicy.cancel()
      lightingAngleGuide?.cancel()
      lightingAngleGuide = nil
      isCapturing = false
      captureCancellation?.cancel()
      captureCancellation = nil
      setCaptureAnalysisPaused(false)
      setCaptureControls(enabled: true)
      tracker.reset()
      burstCandidates.removeAll()
    }
    switch completionFlow.resolve([resolution.candidate]) {
    case let .retry(message):
      showMessage(message)
    case let .complete(page):
      finishing = true
      guidanceView.show(title: "Scan ready", detail: "Preparing your fields for review.", stage: 2, accepted: burstCandidates.count, holding: false)
      UINotificationFeedbackGenerator().notificationOccurred(.success)
      UIAccessibility.post(notification: .announcement, argument: "Page captured. Preparing details.")
      var burstProcessing: [String: Any] = [
        "mode": resolution.mode.rawValue,
        "framesConsidered": resolution.framesConsidered,
        "framesUsed": resolution.framesUsed,
        "alignmentModels": resolution.alignmentModels.map(\.rawValue),
      ]
      if let fallbackReason = resolution.fallbackReason {
        burstProcessing["fallbackReason"] = fallbackReason.rawValue
      }
      if let lighting = resolution.lighting {
        burstProcessing["lighting"] = [
          "shadowCorrectionApplied": lighting.shadowCorrectionApplied,
          "glarePixelsReplacedFraction": lighting.glarePixelsReplacedFraction,
          "unresolvedGlareFraction": lighting.unresolvedGlareFraction,
          "needsDifferentAngle": lighting.needsDifferentAngle,
        ]
      }
      burstProcessing["guidedExtraCaptures"] = max(0, (lightingAngleGuide?.attemptsTaken ?? 1) - 1)
      burstProcessing["acceptedGuidedAngles"] = lightingAngleGuide?.acceptedAdditionalViews ?? 0
      burstProcessing["photosTaken"] = photosTaken
      burstProcessing["retainedUsefulViews"] = burstCandidates.count
      let fusionCapability: String
      switch resolution.mode {
      case .alignedMedianFusion: fusionCapability = "aligned_three_frame_median_fusion"
      case .alignedLightingFusion: fusionCapability = "aligned_lighting_fusion"
      case .bestFrameFallback: fusionCapability = "sharpest_frame_fallback"
      }
      completion([
        "pages": [page],
        "engine": "avfoundation_vision",
        "scannerBuild": "custom-live-v8",
        "capabilities": [
          "live_quadrilateral", "stable_auto_capture", "adaptive_multi_view_capture",
          "perspective_correction", "automatic_single_page",
          "bounded_adaptive_capture", "visual_capture_guide", "lighting_quality_gate", fusionCapability,
        ],
        "burstProcessing": burstProcessing,
      ])
    case .ignored:
      break
    }
  }

  private var lightingAngleInstruction: String { nextViewDetail }

  private func showPlacementGuide() {
    let detail = profile.layout == .passport
      ? "Lay the details page flat in soft light. Keep every corner uncovered."
      : "Lay the document flat in soft light. Keep every corner visible."
    guidanceView.show(title: "Point at the page", detail: detail, stage: 0, accepted: 0, holding: false)
  }

  private func showAngleGuide(holding: Bool = false, missingPage: Bool = false) {
    guidanceView.show(title: holding ? "Hold still" : "Tilt slightly",
      detail: missingPage ? "Bring all four corners back into view."
        : holding ? "Capturing the clear detail automatically."
        : nextViewDetail,
      stage: 1, accepted: burstCandidates.count, holding: holding)
  }

  private func retryLightingCapture(title: String = FoorsaScannerViewController.captureRetryMessage,
                                    detail: String? = nil) {
    lightingRetryAnchor = latestQuadrilateral ?? lightingAngleGuide?.mostRecentCapturedView ?? tracker.anchor
    lightingRetryMissingSince = nil
    retryTitle = title
    retryDetail = detail ?? "Keep the page flat and all four corners visible. Tilt slightly, then hold still."
    abortCapture()
    // Require a deliberate reframe after exhausted/expired guidance; an unchanged
    // shiny page must not automatically restart another forced sequence.
    lastCaptureTime = CACurrentMediaTime()
    guidanceView.show(title: retryTitle, detail: retryDetail,
      stage: 0, accepted: 0, holding: false)
    UINotificationFeedbackGenerator().notificationOccurred(.warning)
    UIAccessibility.post(notification: .announcement, argument: retryDetail)
  }

  private func handleLightingAngle(_ quadrilateral: ScannerQuadrilateral?,
                                  at time: TimeInterval, processingDuration: TimeInterval) {
    let observation = lightingAngleGuide?.observe(quadrilateral, at: time,
                                                  processingDuration: processingDuration) ?? .inactive
    switch observation {
    case .inactive: break
    case .move:
      overlay.progress = 0
      showAngleGuide(missingPage: quadrilateral == nil)
    case let .hold(progress):
      overlay.progress = progress
      showAngleGuide(holding: true)
    case .capture:
      setCaptureAnalysisPaused(true)
      overlay.progress = 1
      burstRemaining = 1
      showAngleGuide(holding: true)
      UIAccessibility.post(notification: .announcement, argument: "Hold still. Taking this view.")
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
      armCaptureTimeout(seconds: 20, waitingForAngle: false)
      captureNextCandidate()
    case .expired:
      retryLightingCapture()
    }
  }

  private func setCaptureControls(enabled: Bool) {
    torchButton.isEnabled = enabled
    torchButton.alpha = enabled ? 1 : 0.45
  }

  @objc private func torchPressed() {
    guard let camera = (session.inputs.first as? AVCaptureDeviceInput)?.device,
          camera.hasTorch else { return }
    do {
      try camera.lockForConfiguration()
      camera.torchMode = camera.torchMode == .on ? .off : .on
      let on = camera.torchMode == .on
      camera.unlockForConfiguration()
      torchButton.setImage(UIImage(systemName: on ? "flashlight.on.fill" : "flashlight.off.fill"), for: .normal)
      torchButton.accessibilityLabel = on ? "Turn torch off" : "Turn torch on"
      torchButton.accessibilityValue = on ? "On" : "Off"
    } catch {
      showMessage("The torch is unavailable right now.")
    }
  }

  private func fail(_ message: String) {
    guard !finishing, completionFlow.terminate() else { return }
    finishing = true
    completion(["error": message])
  }

  private func showMessage(_ message: String) {
    guidanceView.show(title: "Try again", detail: message, stage: 0, accepted: 0, holding: false)
    UINotificationFeedbackGenerator().notificationOccurred(.warning)
    UIAccessibility.post(notification: .announcement, argument: message)
  }

  private func updateVideoOrientation() {
    guard let orientation = view.window?.windowScene?.interfaceOrientation,
          let videoOrientation = AVCaptureVideoOrientation(interfaceOrientation: orientation) else { return }
    if previewLayer.connection?.isVideoOrientationSupported == true {
      previewLayer.connection?.videoOrientation = videoOrientation
    }
    if photoOutput.connection(with: .video)?.isVideoOrientationSupported == true {
      photoOutput.connection(with: .video)?.videoOrientation = videoOrientation
    }
    let orientationForVision: CGImagePropertyOrientation = switch orientation {
    case .landscapeLeft: .up
    case .landscapeRight: .down
    case .portraitUpsideDown: .left
    default: .right
    }
    orientationLock.lock()
    let changed = imageOrientation != orientationForVision
    imageOrientation = orientationForVision
    if changed { analysisEpoch &+= 1 }
    orientationLock.unlock()
    if changed {
      if isCapturing {
        abortCapture()
        showMessage("Keep the phone in this orientation and reframe the document.")
      }
      // A result captured before rotation belongs to the previous preview.
      // Revoke its hold progress before another orientation can auto-capture.
      tracker.reset()
      latestQuadrilateral = nil
      latestImageSize = nil
      overlay.quadrilateral = nil
      overlay.progress = 0
    }
  }

  private func setCaptureAnalysisPaused(_ paused: Bool) {
    // Keep the accepted outline visible during the burst. Prevent new preview
    // inference while a still or the final combined image is being processed.
    orientationLock.lock()
    captureAnalysisPaused = paused
    analysisEpoch &+= 1
    orientationLock.unlock()
  }

  private func setAnalysisActive(_ active: Bool) {
    orientationLock.lock()
    analysisEpoch &+= 1
    analysisActive = active
    orientationLock.unlock()
    guard !active else { return }
    tracker.reset()
    latestQuadrilateral = nil
    latestImageSize = nil
    overlay.quadrilateral = nil
    overlay.progress = 0
  }

  private func handleDetection(
    _ detectedQuadrilateral: ScannerQuadrilateral?,
    imageSize: CGSize,
    time: TimeInterval,
    processingDuration: TimeInterval,
    epoch: UInt
  ) {
    orientationLock.lock()
    let resultIsCurrent = analysisActive && !captureAnalysisPaused && analysisEpoch == epoch
    orientationLock.unlock()
    guard resultIsCurrent, !finishing else { return }
    let quadrilateral = CACurrentMediaTime() - time <= ScannerStabilityTracker.maximumObservationAge
      ? detectedQuadrilateral : nil
    latestQuadrilateral = quadrilateral
    latestImageSize = imageSize
    latestDetectionTime = time
    updatePreviewGeometry()
    renderQuadrilateral(quadrilateral, imageSize: imageSize)
    let shapeAccepted = quadrilateral.map {
      profile.accepts(aspectRatio: $0.estimatedAspectRatio(in: imageSize))
    } ?? false
#if SCANNER_DIAGNOSTICS
    diagnosticEvent?(["event": "detection", "detected": detectedQuadrilateral != nil,
      "fresh": quadrilateral != nil, "shapeAccepted": shapeAccepted,
      "processingMilliseconds": processingDuration * 1000,
      "observationAgeMilliseconds": (CACurrentMediaTime() - time) * 1000,
      "capturing": isCapturing, "waitingForAngle": lightingAngleGuide?.isWaiting ?? false])
#endif
    if isCapturing {
      if lightingAngleGuide?.isWaiting == true {
        handleLightingAngle(shapeAccepted ? quadrilateral : nil, at: time,
                            processingDuration: processingDuration)
      }
      return
    }
    if let retryAnchor = lightingRetryAnchor {
      tracker.reset()
      overlay.progress = 0
      if let quadrilateral {
        lightingRetryMissingSince = nil
        if ScannerLightingAngleGuide.isDifferentAngle(quadrilateral, from: retryAnchor, imageSize: imageSize) {
          lightingRetryAnchor = nil
        }
      } else {
        if lightingRetryMissingSince == nil { lightingRetryMissingSince = time }
        if time - (lightingRetryMissingSince ?? time) >= 1 {
          lightingRetryAnchor = nil
          lightingRetryMissingSince = nil
        }
      }
      guidanceView.show(title: retryTitle, detail: retryDetail,
        stage: 0, accepted: 0, holding: false)
      return
    }
    let state = tracker.observe(shapeAccepted ? quadrilateral : nil, at: time,
      processingDuration: processingDuration)
    overlay.progress = state.progress
    if quadrilateral == nil {
      showPlacementGuide()
      return
    }
    guard shapeAccepted else {
      guidanceView.show(title: "Fit the whole page", detail: "Rotate the document to match the guide.",
        stage: 0, accepted: 0, holding: false)
      return
    }
    if state.ready {
      guidanceView.show(title: "Hold still", detail: "Capturing clear detail automatically.",
        stage: 0, accepted: 0, holding: true)
      if time - lastCaptureTime > 2.2 {
        beginCapture()
      }
    } else {
      if state.progress > 0.15 {
        guidanceView.show(title: "Hold still", detail: "Clear detail will be captured automatically.",
          stage: 0, accepted: 0, holding: true)
      } else { showPlacementGuide() }
    }
  }


#if SCANNER_DIAGNOSTICS
  // Render the actual native guide at bounded phone sizes without starting the
  // camera. These synthetic UI checks never load or persist customer documents.
  static func diagnosticGuidePreviews(to directory: URL) throws -> [[String: Any]] {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var reports: [[String: Any]] = []
    for (name, size, category) in [
      ("portrait", CGSize(width: 393, height: 852), UIContentSizeCategory.large),
      ("small", CGSize(width: 320, height: 568), UIContentSizeCategory.large),
      ("landscape", CGSize(width: 852, height: 393), UIContentSizeCategory.large),
      ("large-text", CGSize(width: 393, height: 852), UIContentSizeCategory.accessibilityExtraExtraExtraLarge),
      ("small-large-text", CGSize(width: 320, height: 568), UIContentSizeCategory.accessibilityExtraExtraExtraLarge),
      ("landscape-large-text", CGSize(width: 852, height: 393), UIContentSizeCategory.accessibilityExtraExtraExtraLarge),
    ] {
      let scanner = FoorsaScannerViewController(profile: FoorsaScannerProfile(arguments:
        ["profile": ["documentKey": "identity", "title": "Scan passport"]])) { _ in }
      scanner.diagnosticPreviewOnly = true
      let parent = UIViewController()
      parent.view.frame = CGRect(origin: .zero, size: size)
      parent.addChild(scanner)
      parent.setOverrideTraitCollection(UITraitCollection(preferredContentSizeCategory: category), forChild: scanner)
      scanner.view.frame = parent.view.bounds
      scanner.additionalSafeAreaInsets = UIEdgeInsets(top: size.width > size.height ? 0 : 24, left: 0, bottom: 16, right: 0)
      parent.view.addSubview(scanner.view)
      scanner.didMove(toParent: parent)
      if #available(iOS 17.0, *) {
        scanner.view.traitOverrides.preferredContentSizeCategory = category
      }
      scanner.guidanceView.updateTypography(compatibleWith: scanner.view.traitCollection)
      for stage in 0..<8 {
        scanner.guidanceView.show(title: ["Point at the page", "Tilt slightly", "Hold still", "Checking the detail",
          Self.captureRetryMessage, "Try again", "Fit the whole page", "Try again"][stage],
          detail: stage == 0 ? "Lay the details page flat. Keep fingers away from all four corners."
            : stage == 3 ? "Combining useful photos and checking what is still unclear."
            : stage == 4 ? "Not enough clear views were captured. Keep the page flat, reframe, and try again."
            : stage == 5 ? "The camera is still focusing. Hold this angle and try again."
            : stage == 6 ? "The photo’s page edges weren’t clear. Keep all four corners visible and hold still."
            : stage == 7 ? "The camera couldn’t save this photo. Keep the page visible and reframe."
            : "Tilt the phone slightly to reveal more detail. Keep the page flat.",
          stage: min(stage, 2), accepted: stage, holding: false)
        parent.view.setNeedsLayout()
        parent.view.layoutIfNeeded()
        scanner.view.setNeedsLayout()
        scanner.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
          scanner.view.layer.render(in: context.cgContext)
        }
        let id = "\(name)-\(stage)"
        try image.pngData()?.write(to: directory.appendingPathComponent(id + ".png"))
        let preview = scanner.previewLayer.frame
        let guide = scanner.guidanceView.frame
        reports.append(["id": id, "preview": NSCoder.string(for: preview),
          "guidance": NSCoder.string(for: guide),
          "previewHasArea": preview.width >= 120 && preview.height >= 100,
          "guidanceInsideScreen": scanner.view.bounds.contains(guide),
          "textFitsBounds": scanner.guidanceView.diagnosticTextFitsBounds,
          "overlap": preview.intersects(guide),
          "accessibility": scanner.guidanceView.accessibilityLabel ?? "",
          "value": scanner.guidanceView.accessibilityValue ?? "",
          "fontSize": scanner.guidanceView.titleLabel.font.pointSize,
          "contentSize": scanner.view.traitCollection.preferredContentSizeCategory.rawValue])
      }
      scanner.willMove(toParent: nil)
      scanner.view.removeFromSuperview()
      scanner.removeFromParent()
    }
    return reports
  }
#endif

  private func renderQuadrilateral(_ quadrilateral: ScannerQuadrilateral?, imageSize: CGSize?) {
    guard let quadrilateral, let imageSize else {
      overlay.quadrilateral = nil
      return
    }
    func layerPoint(_ point: CGPoint) -> CGPoint {
      ScannerAspectFillMapper.layerPoint(
        fromVisionPoint: point,
        imageSize: imageSize,
        in: previewLayer.frame
      )
    }
    overlay.quadrilateral = [
      layerPoint(quadrilateral.topLeft),
      layerPoint(quadrilateral.topRight),
      layerPoint(quadrilateral.bottomRight),
      layerPoint(quadrilateral.bottomLeft),
    ]
  }
}

extension FoorsaScannerViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
  func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    let now = CACurrentMediaTime()
    guard !isAnalyzing, now - lastAnalysisTime >= 0.12,
          let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
    isAnalyzing = true
    lastAnalysisTime = now
    orientationLock.lock()
    let orientation = imageOrientation
    let epoch = analysisEpoch
    let shouldAnalyze = analysisActive && !captureAnalysisPaused
    orientationLock.unlock()
    guard shouldAnalyze else {
      isAnalyzing = false
      return
    }
    let rawSize = CGSize(
      width: CVPixelBufferGetWidth(imageBuffer),
      height: CVPixelBufferGetHeight(imageBuffer)
    )
    let imageSize = orientation.orientedImageSize(for: rawSize)
    // Keep live and still analysis on the same pixel-aware detection path.
    // CIImage applies the camera orientation before geometry is normalized.
    let quadrilateral: ScannerQuadrilateral? = autoreleasepool {
      let oriented = CIImage(cvPixelBuffer: imageBuffer).oriented(orientation)
      let upright = oriented.transformed(by: CGAffineTransform(
        translationX: -oriented.extent.minX, y: -oriented.extent.minY
      ))
#if SCANNER_DIAGNOSTICS
      // Capture the camera pixels before any guide/outline is drawn. Bounded,
      // lossless and local-only; ordinary app builds have no observer or writer.
      if diagnosticPreviewFrame != nil, diagnosticPreviewCount < 8,
         now - diagnosticLastPreviewTime >= 1.25 {
        diagnosticLastPreviewTime = now
        diagnosticPreviewCount += 1
        let scale = min(1, 1920 / max(upright.extent.width, upright.extent.height))
        let bounded = upright.transformed(by: CGAffineTransform(scaleX: scale, y: scale),
                                          highQualityDownsample: true)
        if let data = diagnosticPreviewContext.pngRepresentation(of: bounded, format: .RGBA8,
          colorSpace: CGColorSpaceCreateDeviceRGB()) {
          DispatchQueue.main.async { [weak self] in self?.diagnosticPreviewFrame?(data) }
        }
      }
#endif
      guard let best = try? ScannerRectangleDetector.detect(
        in: upright, profile: profile, purpose: .live
      ) else { return nil }
      return ScannerQuadrilateral(
        topLeft: best.topLeft,
        topRight: best.topRight,
        bottomRight: best.bottomRight,
        bottomLeft: best.bottomLeft
      )
    }
    isAnalyzing = false
    let processingDuration = CACurrentMediaTime() - now
    DispatchQueue.main.async { [weak self] in
      self?.handleDetection(quadrilateral, imageSize: imageSize, time: now,
        processingDuration: processingDuration, epoch: epoch)
    }
  }
}

extension FoorsaScannerViewController: AVCapturePhotoCaptureDelegate {
  func photoOutput(
    _ output: AVCapturePhotoOutput,
    didFinishProcessingPhoto photo: AVCapturePhoto,
    error: Error?
  ) {
    let photoID = photo.resolvedSettings.uniqueID
    DispatchQueue.main.async { [weak self] in
      guard let self, self.activePhotoIDs.remove(photoID) != nil,
            self.isCapturing, !self.finishing else { return }
      let generation = self.captureGeneration
      let data = error == nil ? photo.fileDataRepresentation() : nil
      let geometry = self.capturedGeometry.removeValue(forKey: photoID)
      if self.profile.usesImagegen {
        guard let data, geometry != nil, self.originalPhotos.append(data) else {
          self.retryLightingCapture(detail: "The photo could not be saved within the camera limit. Reframe and try again.")
          return
        }
      }
#if SCANNER_DIAGNOSTICS
      if let data { self.diagnosticCapturedPhoto?(data) }
#endif
      if let data, let cancellation = self.captureCancellation {
        self.pendingProcessingCount += 1
        self.processingQueue.async { [weak self] in
          guard let self, !cancellation.isCancelled else { return }
          let processingResult = self.processor.processCapture(photoData: data, profile: self.profile,
            liveQuadrilateral: geometry?.quad, liveImageSize: geometry?.size)
          let candidate = try? processingResult.get()
          DispatchQueue.main.async { [weak self] in
            guard let self, self.isCapturing,
                  self.captureGeneration == generation, !self.finishing else { return }
            self.pendingProcessingCount -= 1
            let assessment = ScannerImageProcessor.assessViewQuality(accepted: self.burstCandidates, candidate: candidate)
            let useful = assessment == .accepted || assessment == .restartForEarlierSoftView
            let wasGuided = self.lightingAngleGuide?.pendingCaptureView != nil
            let acceptedGuided = self.lightingAngleGuide?.resolveCapture(accepted: useful) ?? false
            if let candidate, useful, !wasGuided || acceptedGuided {
              self.burstCandidates = ScannerImageProcessor.retainingUsefulViews(self.burstCandidates + [candidate])
              self.nextViewDetail = "Tilt the phone slightly to reveal more detail. Keep the page flat."
            } else {
              self.nextViewDetail = candidate == nil
                ? "Keep every corner visible, then hold still. Earlier clear photos are saved."
                : "This view has less clear detail. Hold still and keep shadows off the page."
            }
#if SCANNER_DIAGNOSTICS
            let processingFailure: String
            if case let .failure(reason) = processingResult { processingFailure = reason.rawValue }
            else { processingFailure = "none" }
            self.diagnosticEvent?(["event": "view_processed", "accepted": useful && (!wasGuided || acceptedGuided),
              "qualityDecision": String(describing: assessment),
              "processingFailure": processingFailure,
              "photosTaken": self.photosTaken, "acceptedViews": self.burstCandidates.count,
              "acceptedGuidedAngles": self.lightingAngleGuide?.acceptedAdditionalViews ?? 0])
#endif
            if !self.profile.usesImagegen, self.burstCandidates.isEmpty, case let .failure(reason) = processingResult {
              self.retryLightingCapture(
                title: reason == .documentBoundaryNotFound ? "Fit the whole page" : "Try again",
                detail: reason == .documentBoundaryNotFound
                  ? "The photo’s page edges weren’t clear. Keep all four corners visible and hold still."
                  : "The camera couldn’t save this photo. Keep the page visible and reframe.")
              return
            }
            if !useful && (!self.burstCandidates.isEmpty || self.profile.usesImagegen) {
              // Rejected pixels provide no new evidence. Keep the useful pool
              // and ask for a retake without rerunning the same failed merge.
              self.beginNextAngle()
            } else {
              self.finishBurstIfReady()
            }
          }
        }
      } else {
#if SCANNER_DIAGNOSTICS
        self.diagnosticEvent?(["event": "photo_unavailable",
          "errorDomain": (error as NSError?)?.domain ?? "none",
          "errorCode": (error as NSError?)?.code ?? 0])
#endif
        self.lightingAngleGuide?.resolveCapture(accepted: false)
      }
      // Let the phase settle after the photo callback. A new angle is requested
      // only after correction accepts or rejects this view.
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
        guard let self, self.captureGeneration == generation else { return }
        self.captureNextCandidate()
      }
    }
  }
}

// One current instruction stays outside the camera pixels. There is no fixed
// photo count or progress percentage: the image checks decide when to finish.
private final class ScannerGuidanceView: UIView {
  let titleLabel = UILabel()
  private let detailLabel = UILabel()
  private let symbol = UIImageView(image: UIImage(systemName: "viewfinder"))
  private let activity = UIActivityIndicatorView(style: .medium)
  private var fontCategory: UIContentSizeCategory?
  private var compactInstructions = false
  private var fullTitle = ""
  private var fullDetail = ""

  override init(frame: CGRect) {
    super.init(frame: frame)
    titleLabel.font = .preferredFont(forTextStyle: .title3)
    titleLabel.textColor = .white
    titleLabel.numberOfLines = 0
    titleLabel.textAlignment = .center
    titleLabel.adjustsFontForContentSizeCategory = true
    detailLabel.font = .preferredFont(forTextStyle: .subheadline)
    detailLabel.textColor = UIColor.white.withAlphaComponent(0.82)
    detailLabel.numberOfLines = 0
    detailLabel.textAlignment = .center
    detailLabel.adjustsFontForContentSizeCategory = true
    symbol.contentMode = .scaleAspectFit
    symbol.tintColor = .white
    symbol.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 28, weight: .regular)
    activity.color = .white
    activity.hidesWhenStopped = true
    let stack = UIStackView(arrangedSubviews: [symbol, activity, titleLabel, detailLabel])
    stack.axis = .vertical
    stack.spacing = 8
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      symbol.heightAnchor.constraint(equalToConstant: 32),
      stack.topAnchor.constraint(equalTo: topAnchor),
      stack.leadingAnchor.constraint(equalTo: leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
    isAccessibilityElement = true
    accessibilityTraits = .staticText
    accessibilityHint = "Useful photos are captured automatically. You can cancel at any time."
    titleLabel.isAccessibilityElement = false
    detailLabel.isAccessibilityElement = false
    symbol.isAccessibilityElement = false
    activity.isAccessibilityElement = false
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func updateTypography(compatibleWith traits: UITraitCollection) {
    let category = traits.preferredContentSizeCategory
    guard category != fontCategory else { return }
    fontCategory = category
    compactInstructions = category.isAccessibilityCategory
    titleLabel.adjustsFontForContentSizeCategory = false
    detailLabel.adjustsFontForContentSizeCategory = false
    titleLabel.font = .preferredFont(forTextStyle: .title3, compatibleWith: traits)
    detailLabel.font = .preferredFont(forTextStyle: .subheadline, compatibleWith: traits)
    updateVisibleText()
  }

  private func updateVisibleText() {
    titleLabel.text = fullTitle
    if compactInstructions {
      if fullTitle == "Point at the page" { titleLabel.text = "Fit page" }
      if fullTitle == "Reframe the page" { titleLabel.text = "Try again" }
      if fullTitle == "Fit the whole page" { titleLabel.text = "Fit page" }
      detailLabel.text = fullTitle == "Point at the page" ? "Keep corners clear."
        : fullTitle == "Fit the whole page" ? "Keep corners visible."
        : fullTitle == "Tilt slightly" ? "Keep the page flat and in view."
        : fullTitle == "Hold still" ? "Capturing automatically."
        : fullTitle == "Checking the detail" ? "Please wait."
        : fullTitle == "Reframe the page" ? "Keep the page flat and in view."
        : fullTitle == "Try again" ? (fullDetail.contains("torch") ? "Torch unavailable."
          : fullDetail.contains("focusing") ? "Hold still." : "Keep corners visible.")
        : fullDetail
    } else { detailLabel.text = fullDetail }
    let checking = fullTitle == "Checking the detail"
    symbol.isHidden = compactInstructions || checking
    activity.isHidden = !checking
    if checking { activity.startAnimating() } else { activity.stopAnimating() }
  }

#if SCANNER_DIAGNOSTICS
  var diagnosticTextFitsBounds: Bool {
    [titleLabel, detailLabel].allSatisfy { label in
      let needed = label.sizeThatFits(CGSize(width: label.bounds.width, height: .greatestFiniteMagnitude))
      return needed.height <= label.bounds.height + 0.5 && needed.width <= label.bounds.width + 0.5
    }
  }
#endif

  func show(title: String, detail: String, stage: Int, accepted: Int, holding: Bool) {
    if fullTitle != title || fullDetail != detail {
      fullTitle = title
      fullDetail = detail
      updateVisibleText()
    }
    accessibilityLabel = "\(title). \(detail)"
    accessibilityValue = nil
    let image = title == "Scan ready" ? "checkmark.circle"
      : title == "Tilt slightly" ? "iphone.radiowaves.left.and.right"
      : holding ? "iphone" : "viewfinder"
    symbol.image = UIImage(systemName: image)
    symbol.tintColor = title == "Scan ready" ? .systemGreen : .white
  }
}

private final class ScannerOverlayView: UIView {
  private let outline = CAShapeLayer()
  var quadrilateral: [CGPoint]? { didSet { updateOutline(animated: true) } }
  var progress: CGFloat = 0 { didSet { updateOutline(animated: false) } }
  var guideAspectRatio: CGFloat = 0.71
  var guideRect: CGRect = .zero { didSet { updateOutline(animated: false) } }

  override init(frame: CGRect) {
    super.init(frame: frame)
    outline.fillColor = UIColor.clear.cgColor
    outline.lineJoin = .round
    outline.lineCap = .round
    layer.addSublayer(outline)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func layoutSubviews() {
    super.layoutSubviews()
    updateOutline(animated: false)
  }

  private func updateOutline(animated: Bool) {
    let path: UIBezierPath
    let detected = quadrilateral?.count == 4
    if let quadrilateral, detected {
      path = UIBezierPath()
      path.move(to: quadrilateral[0])
      quadrilateral.dropFirst().forEach(path.addLine)
      path.close()
    } else {
      path = UIBezierPath(rect: guideRect)
    }
    let previous = outline.presentation()?.path ?? outline.path
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    outline.path = path.cgPath
    outline.strokeColor = (detected
      ? (progress >= 1 ? UIColor.systemGreen : UIColor.systemBlue)
      : UIColor.white.withAlphaComponent(0.72)).cgColor
    outline.lineWidth = detected ? 2.5 : 1.5
    outline.lineDashPattern = detected ? nil : [8, 7]
    CATransaction.commit()
    if animated, detected, let previous, !UIAccessibility.isReduceMotionEnabled {
      let movement = CABasicAnimation(keyPath: "path")
      movement.fromValue = previous
      movement.toValue = path.cgPath
      movement.duration = 0.12
      movement.timingFunction = CAMediaTimingFunction(name: .easeOut)
      outline.add(movement, forKey: "documentEdges")
    }
  }
}

private extension AVCaptureVideoOrientation {
  init?(interfaceOrientation: UIInterfaceOrientation) {
    switch interfaceOrientation {
    case .portrait: self = .portrait
    case .portraitUpsideDown: self = .portraitUpsideDown
    case .landscapeLeft: self = .landscapeLeft
    case .landscapeRight: self = .landscapeRight
    default: return nil
    }
  }
}

private extension CGImagePropertyOrientation {
  func orientedImageSize(for rawSize: CGSize) -> CGSize {
    switch self {
    case .left, .leftMirrored, .right, .rightMirrored:
      return CGSize(width: rawSize.height, height: rawSize.width)
    default:
      return rawSize
    }
  }
}
