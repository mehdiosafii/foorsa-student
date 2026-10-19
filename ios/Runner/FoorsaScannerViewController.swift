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
  private var shotTracker = ScannerStabilityTracker()
  private var smoother = ScannerOutlineSmoother()
  private var completionFlow = ScannerSinglePageCompletionFlow()
  private var lastAnalysisTime: TimeInterval = 0
  private var latestQuadrilateral: ScannerQuadrilateral?
  private var latestImageSize: CGSize?
  private var latestDetectionTime: TimeInterval = 0
  private var liveLighting: ScannerLiveLighting = .good
  private var readySince: TimeInterval?
  private var lastEvidenceTime: TimeInterval = 0
  private var lastEvidenceQuadrilateral: ScannerQuadrilateral?
  private var analysisStartedAt: TimeInterval = 0
  private var shutterIdleSince: TimeInterval = 0
  private var isAnalyzing = false
  private var isCapturing = false
  private var manualCapture = false
  private var capturePolicy: ScannerImagegenCapturePolicy?
  private var lightingAtFirstShot: ScannerLiveLighting = .good
  private var awaitingSteadyShot = false
  private var awaitingMovedShot: TimeInterval?
  private var lastShotQuadrilateral: ScannerQuadrilateral?
  private var lastPhotoFailure: ScannerImageProcessor.PhotoProcessingFailure?
  private var burstRemaining = 0
  private var photosTaken = 0
  private var burstCandidates: [ScannerProcessedCandidate] = []
  private var activePhotoIDs = Set<Int64>()
  private var originalPhotos = ScannerOriginalPhotoPool()
  private var capturedGeometry: [Int64: (quad: ScannerQuadrilateral, size: CGSize)] = [:]
  private var captureGeneration = 0
  private var captureCancellation: ScannerBurstCancellationToken?
  private var captureSettleEpoch = 0
  private var captureSettling = false
  private var captureSettlePolicy = ScannerCaptureSettlePolicy()
  private var captureSettleAnchor: ScannerQuadrilateral?
  private var captureSettleCameraType: String?
  private var lightingRetryAnchor: ScannerQuadrilateral?
  private var lightingRetryMissingSince: TimeInterval?
  private var lightingRetrySince: TimeInterval?
  private static let captureRetryMessage = "Reframe the page"
  private static let manualShutterDelay: TimeInterval = 7
  private static let lightingGrace: TimeInterval = 1.5
  private static let angleRequestLimit: TimeInterval = 4
  private var retryTitle = captureRetryMessage
  private var retryDetail = "Reframe the page, keep all four corners visible, and hold still."
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
  private let shutterButton = UIButton(type: .custom)

  init(profile: FoorsaScannerProfile, completion: @escaping Completion) {
    self.profile = profile
    self.completion = completion
    // The first hold tolerates one missed preview frame; later photos in the
    // same capture need only a short steady moment.
    tracker = ScannerStabilityTracker(requiredDuration: 0.6, minimumArea: profile.minimumCaptureArea,
      requiredObservations: 4, toleratedMisses: 1)
    shotTracker = ScannerStabilityTracker(requiredDuration: 0.25, minimumArea: profile.minimumCaptureArea,
      requiredObservations: 2, toleratedMisses: 1)
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
    warmUpVision()
    configureSession()
  }

  /// The first document-model request loads Vision's model, which used to
  /// delay the first outline. Running one request on a blank image while the
  /// camera session starts moves that cost off the first frame. Same serial
  /// queue as the frames, so it never runs alongside them.
  private func warmUpVision() {
    visionQueue.async {
      let blank = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
        .cropped(to: CGRect(x: 0, y: 0, width: 256, height: 256))
      _ = try? ScannerVisionFrameCache.observations(in: blank, purpose: .live, cache: nil)
    }
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
    renderQuadrilateral(smoother.current, imageSize: latestImageSize)
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
    let imageSize = latestImageSize ?? fallbackSize
    // A paper of unknown orientation gets corner marks shaped like the camera
    // view: a portrait page guide made students turn landscape diplomas.
    let guideAspect = profile.layout == .adaptive && imageSize.height > 0
      ? imageSize.width / imageSize.height : overlay.guideAspectRatio
    let geometry = ScannerPreviewGeometry(imageSize: imageSize,
      availableRect: available, guideAspectRatio: guideAspect)
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

    shutterButton.translatesAutoresizingMaskIntoConstraints = false
    shutterButton.isHidden = true
    shutterButton.backgroundColor = UIColor.white.withAlphaComponent(0.92)
    shutterButton.layer.cornerRadius = 32
    shutterButton.layer.borderWidth = 4
    shutterButton.layer.borderColor = UIColor.black.withAlphaComponent(0.35).cgColor
    shutterButton.setImage(UIImage(systemName: "camera.fill"), for: .normal)
    shutterButton.tintColor = .black
    shutterButton.accessibilityLabel = "Take the photo"
    shutterButton.accessibilityHint = "Takes the photo now if automatic capture has not started"
    shutterButton.addTarget(self, action: #selector(shutterPressed), for: .touchUpInside)
    view.addSubview(shutterButton)

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
      shutterButton.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
      shutterButton.bottomAnchor.constraint(equalTo: guidanceView.topAnchor, constant: -14),
    ]
    landscapeConstraints = [
      shutterButton.trailingAnchor.constraint(equalTo: guidanceView.leadingAnchor, constant: -16),
      shutterButton.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
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
      shutterButton.widthAnchor.constraint(equalToConstant: 64),
      shutterButton.heightAnchor.constraint(equalToConstant: 64),
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
        // Pages are always close: keeping autofocus on the near range stops it
        // hunting toward the background behind a hand-held page.
        if camera.isAutoFocusRangeRestrictionSupported { camera.autoFocusRangeRestriction = .near }
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

  // MARK: Capture (custom-live-v11)
  //
  // One hold, a few photos. Once the page is ready and steady the camera
  // settles focus and exposure and takes a photo; the next photo is taken as
  // soon as the previous one is delivered, while that one is still checked.
  // Two useful photos finish the page. There is no tilt sequence and no fixed
  // number of angles: a second angle is requested only after shadow or glare.

  private func beginCapture(manual: Bool = false) {
    guard !isCapturing, !finishing, configured, session.isRunning, !session.isInterrupted else { return }
#if SCANNER_DIAGNOSTICS
    diagnosticEvent?(["event": "capture_started", "manual": manual])
#endif
    let now = CACurrentMediaTime()
    isCapturing = true
    manualCapture = manual
    captureGeneration += 1
    captureCancellation = ScannerBurstCancellationToken()
    capturePolicy = ScannerImagegenCapturePolicy(startedAt: now)
    lightingAtFirstShot = manual ? .good : liveLighting
    awaitingSteadyShot = false
    awaitingMovedShot = nil
    lastShotQuadrilateral = nil
    lastPhotoFailure = nil
    burstRemaining = 0
    photosTaken = 0
    originalPhotos.reset()
    capturedGeometry.removeAll()
    burstCandidates.removeAll(keepingCapacity: true)
    activePhotoIDs.removeAll(keepingCapacity: true)
    tracker.reset()
    shotTracker.reset()
    readySince = nil
    lightingRetryAnchor = nil
    lastCaptureTime = now
    setCaptureControls(enabled: false)
    updateShutterVisibility(at: now)
    guidanceView.show(ScannerLiveGuidance.copy(framing: .ready, lighting: .good, layout: profile.layout), holding: true)
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    let generation = captureGeneration
    DispatchQueue.main.asyncAfter(deadline: .now() + ScannerImagegenCapturePolicy.totalDuration + 8) { [weak self] in
      guard let self, self.isCapturing, self.captureGeneration == generation else { return }
      self.retryCapture(title: "Try again", detail: "The camera took too long. Keep the page in view and hold still.")
    }
    advanceCapture()
  }

  /// The single decision point after every capture event.
  private func advanceCapture() {
    guard isCapturing, !finishing, let policy = capturePolicy else { return }
    switch policy.decision(at: CACurrentMediaTime()) {
    case .complete:
      completeCapture()
    case .giveUp:
      retryCapture(title: "Try again", detail: lastPhotoFailure == .documentBoundaryNotFound
        ? "The page edges weren’t clear. Fit the whole page in view and hold still."
        : burstCandidates.isEmpty
          ? "The photos weren’t sharp. Hold the phone steady with the whole page in view."
          : "Hold still a moment longer for one more clear photo.")
    case .waitForResults:
      break
    case .shootNext:
      guard !captureSettling, burstRemaining == 0, activePhotoIDs.isEmpty,
            !awaitingSteadyShot, awaitingMovedShot == nil else { return }
      // A second angle helps only when the first view had shadow or glare:
      // moving the phone moves both, so later views show what was hidden.
      if !manualCapture, policy.attempts == 1,
         lightingAtFirstShot == .shadow || lightingAtFirstShot == .glare {
        awaitingMovedShot = CACurrentMediaTime()
        shotTracker.reset()
        setCaptureAnalysisPaused(false)
        guidanceView.show(title: "Tilt the phone slightly",
          detail: lightingAtFirstShot == .glare
            ? "Move the reflection off the page, then hold still."
            : "Move the shadow off the page, then hold still.",
          compact: "Tilt slightly.", holding: false)
        UIAccessibility.post(notification: .announcement, argument: "Tilt the phone slightly, then hold still.")
        return
      }
      burstRemaining = 1
      beginCaptureSettling()
    }
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
    // Keep checking the page while focus settles: an outline accepted before
    // the student moved cannot authorize this photo.
    setCaptureAnalysisPaused(false)
    guidanceView.show(ScannerLiveGuidance.copy(framing: .ready, lighting: .good, layout: profile.layout), holding: true)
#if SCANNER_DIAGNOSTICS
    diagnosticEvent?(cameraDiagnosticFields(event: "capture_settle_started", elapsed: 0))
#endif
    pollCaptureSettling(epoch: epoch, generation: generation)
  }

  private func pollCaptureSettling(epoch: Int, generation: Int) {
    guard captureSettling, isCapturing, !finishing,
          captureSettleEpoch == epoch, captureGeneration == generation else { return }
    let now = CACurrentMediaTime()
    let camera = (session.inputs.first as? AVCaptureDeviceInput)?.device
    if captureSettleAnchor == nil { captureSettleAnchor = latestQuadrilateral }
    // A photo the student asked for by hand only waits for the lens.
    let documentIsStable = manualCapture || (latestQuadrilateral.flatMap { current in
      captureSettleAnchor.map { current.maximumCornerDistance(to: $0) <= 0.018 }
    } == true && latestDetectionTime >= (captureSettlePolicy.startedAt ?? now)
      && now - latestDetectionTime <= ScannerStabilityTracker.maximumObservationAge)
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
#if SCANNER_DIAGNOSTICS
      diagnosticEvent?(cameraDiagnosticFields(event: "capture_triggered",
        elapsed: captureSettlePolicy.startedAt.map { now - $0 } ?? 0))
#endif
      takePhoto(camera: camera)
    case .expired:
#if SCANNER_DIAGNOSTICS
      var expiry = cameraDiagnosticFields(event: "capture_settle_expired", elapsed: ScannerCaptureSettlePolicy.maximumWait)
      expiry["documentIsStable"] = documentIsStable
      diagnosticEvent?(expiry)
#endif
      if manualCapture {
        // A tap means now: take the photo even if the lens is still moving.
        takePhoto(camera: camera)
        return
      }
      captureSettling = false
      captureSettlePolicy.cancel()
      captureSettleAnchor = nil
      burstRemaining = 0
      // Wait for the page to be steady again instead of abandoning the hold.
      awaitingSteadyShot = true
      shotTracker.reset()
      overlay.progress = 0
      guidanceView.show(title: "Hold still", detail: documentIsStable
        ? "The camera is still focusing. Keep this position."
        : "Keep the whole page in view and hold the phone steady.", compact: "Hold still.", holding: false)
    case .waiting:
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
        self?.pollCaptureSettling(epoch: epoch, generation: generation)
      }
    case .inactive:
      captureSettling = false
    }
  }

  private func takePhoto(camera: AVCaptureDevice?) {
    let anchor = captureSettleAnchor
    captureSettling = false
    captureSettlePolicy.cancel()
    captureSettleAnchor = nil
    setCaptureAnalysisPaused(true)
    guard burstRemaining > 0 else { return }
    // Only count a photo once the still has actually been handed to AVFoundation.
    burstRemaining -= 1
    photosTaken += 1
    capturePolicy?.photoRequested()
    let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
    settings.photoQualityPrioritization = .quality
    if #available(iOS 16.0, *) {
      settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions
    } else {
      settings.isHighResolutionPhotoEnabled = true
    }
    if let camera, camera.isFlashAvailable { settings.flashMode = .off }
    if #available(iOS 18.0, *), !ScannerShutterSound.plays(photoNumber: photosTaken),
       photoOutput.isShutterSoundSuppressionSupported {
      settings.isShutterSoundSuppressionEnabled = true
    }
    activePhotoIDs.insert(settings.uniqueID)
    if let quad = latestQuadrilateral ?? anchor, let size = latestImageSize,
       quad.isComplete(minimumArea: profile.minimumCaptureArea) {
      capturedGeometry[settings.uniqueID] = (quad, size)
      lastShotQuadrilateral = quad
    }
    photoOutput.capturePhoto(with: settings, delegate: self)
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

  private func abortCapture() {
    guard isCapturing else { return }
#if SCANNER_DIAGNOSTICS
    diagnosticEvent?(["event": "capture_aborted", "candidates": burstCandidates.count])
#endif
    isCapturing = false
    manualCapture = false
    captureSettling = false
    captureSettleEpoch &+= 1
    captureSettlePolicy.cancel()
    captureSettleAnchor = nil
    capturePolicy = nil
    awaitingSteadyShot = false
    awaitingMovedShot = nil
    captureCancellation?.cancel()
    captureCancellation = nil
    setCaptureAnalysisPaused(false)
    captureGeneration += 1
    activePhotoIDs.removeAll()
    capturedGeometry.removeAll()
    originalPhotos.reset()
    burstRemaining = 0
    burstCandidates.removeAll()
    tracker.reset()
    shotTracker.reset()
    readySince = nil
    setCaptureControls(enabled: true)
    shutterIdleSince = CACurrentMediaTime()
    updateShutterVisibility(at: shutterIdleSince)
  }

  private func completeCapture() {
    let imagegen = profile.usesImagegen
    guard isCapturing, !finishing,
          !imagegen || originalPhotos.canComplete(usefulViews: burstCandidates.count) else { return }
    let originals = originalPhotos.photos
    let count = burstCandidates.count
    let attempts = photosTaken
    let manual = manualCapture
    switch completionFlow.resolve(burstCandidates) {
    case let .complete(page):
      finishing = true
      abortCapture()
      guidanceView.show(title: "Photos ready", detail: "Preparing your document…", compact: "Ready.", holding: false)
      UINotificationFeedbackGenerator().notificationOccurred(.success)
      UIAccessibility.post(notification: .announcement, argument: "Page captured. Preparing your document.")
      var capabilities = ["live_quadrilateral", "stable_auto_capture", "one_hold_capture",
        "perspective_correction", "automatic_single_page", "live_framing_guidance",
        "document_model_detection", "manual_fallback_shutter"]
      var processing: [String: Any] = ["mode": imagegen ? "imagegen" : "best_frame",
        "photosTaken": attempts, "retainedUsefulViews": count, "framesUsed": 1, "manual": manual]
      var response: [String: Any] = ["pages": [page], "engine": "avfoundation_vision",
        "scannerBuild": "custom-live-v11"]
      if imagegen {
        capabilities += ["original_camera_jpegs", "source_photo_ocr_preview", "async_crm_enhancement"]
        processing["originalPhotos"] = originals.count
        response["originals"] = originals
        response["processing"] = "imagegen"
      }
      response["capabilities"] = capabilities
      response["burstProcessing"] = processing
      completion(response)
    case let .retry(message):
      retryCapture(detail: message)
    case .ignored:
      break
    }
  }

  private func showPlacementGuide() {
    guidanceView.show(ScannerLiveGuidance.copy(framing: .searching, lighting: .good, layout: profile.layout),
      holding: false)
  }

  private func retryCapture(title: String = FoorsaScannerViewController.captureRetryMessage,
                            detail: String? = nil) {
    lightingRetryAnchor = latestQuadrilateral ?? lastShotQuadrilateral ?? tracker.anchor
    lightingRetryMissingSince = nil
    lightingRetrySince = CACurrentMediaTime()
    retryTitle = title
    retryDetail = detail ?? "Reframe the page, keep all four corners visible, and hold still."
    abortCapture()
    // Ask for a deliberate reframe (or a short pause) so an unchanged bad
    // view does not immediately restart the same failed capture.
    lastCaptureTime = CACurrentMediaTime()
    guidanceView.show(title: retryTitle, detail: retryDetail, compact: "Try again.", holding: false)
    UINotificationFeedbackGenerator().notificationOccurred(.warning)
    UIAccessibility.post(notification: .announcement, argument: retryDetail)
  }

  private func setCaptureControls(enabled: Bool) {
    torchButton.isEnabled = enabled
    torchButton.alpha = enabled ? 1 : 0.45
  }

  /// A quiet way out when automatic capture has not happened: the shutter
  /// appears only after a few seconds without a photo, never during capture.
  private func updateShutterVisibility(at time: TimeInterval) {
    let visible = !isCapturing && !finishing && analysisActive && time - shutterIdleSince >= Self.manualShutterDelay
    guard shutterButton.isHidden == visible else { return }
    if visible {
      shutterButton.alpha = 0
      shutterButton.isHidden = false
      UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.25) { self.shutterButton.alpha = 1 }
      UIAccessibility.post(notification: .layoutChanged, argument: nil)
    } else {
      shutterButton.isHidden = true
    }
  }

  @objc private func shutterPressed() {
    guard !isCapturing, !finishing else { return }
    lightingRetryAnchor = nil
    beginCapture(manual: true)
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

  /// Dim light is read from the camera itself: a very high ISO means the
  /// scene is dark even when auto exposure makes the preview look fine.
  private func cameraNeedsMoreLight() -> Bool {
    guard let camera = (session.inputs.first as? AVCaptureDeviceInput)?.device else { return false }
    let active = camera.activePrimaryConstituent ?? camera
    let maximum = active.activeFormat.maxISO
    return camera.torchMode != .on && maximum > 0 && active.iso >= max(1200, maximum * 0.6)
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
      smoother.reset()
      latestQuadrilateral = nil
      latestImageSize = nil
      overlay.quadrilateral = nil
      overlay.progress = 0
    }
  }

  private func setCaptureAnalysisPaused(_ paused: Bool) {
    // Keep the accepted outline visible during capture. Prevent new preview
    // inference while a still is being taken.
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
    if active {
      analysisStartedAt = CACurrentMediaTime()
      shutterIdleSince = analysisStartedAt
      lastEvidenceTime = 0
      lastEvidenceQuadrilateral = nil
      return
    }
    tracker.reset()
    smoother.reset()
    readySince = nil
    latestQuadrilateral = nil
    latestImageSize = nil
    overlay.quadrilateral = nil
    overlay.progress = 0
    shutterButton.isHidden = true
  }

  private func handleLiveObservation(
    _ incoming: ScannerLiveObservation,
    imageSize: CGSize,
    time: TimeInterval,
    processingDuration: TimeInterval,
    epoch: UInt
  ) {
    orientationLock.lock()
    let resultIsCurrent = analysisActive && !captureAnalysisPaused && analysisEpoch == epoch
    orientationLock.unlock()
    guard resultIsCurrent, !finishing else { return }
    let fresh = CACurrentMediaTime() - time <= ScannerStabilityTracker.maximumObservationAge
    var observation = fresh ? incoming : ScannerLiveObservation.none
    var countsTowardHold = observation.framing == .ready
    // Passports: the booklet-aware cascade decides first. A document-model
    // page drives capture only when it matches the confirmed photo page, or
    // once the cascade has had three seconds without finding one.
    if profile.layout == .passport, let quad = observation.quadrilateral {
      if observation.confirmedByEvidence {
        lastEvidenceTime = time
        lastEvidenceQuadrilateral = quad
      } else if observation.framing == .ready {
        let matchesEvidence = time - lastEvidenceTime < 1.5 && (lastEvidenceQuadrilateral.map {
          $0.maximumCornerDistance(to: quad) <= 0.035 } ?? false)
        let cascadeHadItsChance = time - max(lastEvidenceTime, analysisStartedAt) >= 3
        countsTowardHold = matchesEvidence || cascadeHadItsChance
      }
    }
    if observation.framing == .ready, observation.lighting == .good, cameraNeedsMoreLight() {
      observation = ScannerLiveObservation(quadrilateral: observation.quadrilateral, framing: .ready,
        lighting: .dim, confirmedByEvidence: observation.confirmedByEvidence)
    }
    let quad = observation.quadrilateral
    let readyQuad = observation.framing == .ready && countsTowardHold ? quad : nil
    liveLighting = observation.lighting
    // The capture geometry and the focus-settle check use complete pages
    // only; a soft frame keeps its outline so motion is still measured.
    latestQuadrilateral = readyQuad ?? (observation.framing == .blurry ? quad : nil)
    latestImageSize = imageSize
    latestDetectionTime = time
    updatePreviewGeometry()
    overlay.style = readyQuad != nil ? .tracking : .adjusting
    renderQuadrilateral(smoother.update(quad), imageSize: imageSize)
    updateShutterVisibility(at: time)
#if SCANNER_DIAGNOSTICS
    diagnosticEvent?(["event": "detection", "detected": incoming.quadrilateral != nil,
      "fresh": fresh, "framing": observation.framing.rawValue, "lighting": observation.lighting.rawValue,
      "evidence": observation.confirmedByEvidence, "countsTowardHold": countsTowardHold,
      "processingMilliseconds": processingDuration * 1000,
      "observationAgeMilliseconds": (CACurrentMediaTime() - time) * 1000,
      "capturing": isCapturing])
#endif
    if isCapturing {
      handleCaptureObservation(observation, readyQuad: readyQuad, imageSize: imageSize,
        time: time, processingDuration: processingDuration)
      return
    }
    if let retryAnchor = lightingRetryAnchor {
      tracker.reset()
      overlay.progress = 0
      if let quad {
        lightingRetryMissingSince = nil
        if quad.maximumCornerDistance(to: retryAnchor) >= 0.035 { lightingRetryAnchor = nil }
      } else {
        if lightingRetryMissingSince == nil { lightingRetryMissingSince = time }
        if time - (lightingRetryMissingSince ?? time) >= 1 { lightingRetryAnchor = nil }
      }
      // A short pause also counts as a fresh attempt.
      if time - (lightingRetrySince ?? time) >= 3 { lightingRetryAnchor = nil }
      if lightingRetryAnchor != nil {
        guidanceView.show(title: retryTitle, detail: retryDetail, compact: "Try again.", holding: false)
        return
      }
      lightingRetryMissingSince = nil
      lightingRetrySince = nil
    }
    let state = tracker.observe(readyQuad, at: time, processingDuration: processingDuration)
    overlay.progress = state.progress
    let shownFraming: ScannerLiveFraming = observation.framing == .ready && readyQuad == nil
      ? .blurry : observation.framing
    guidanceView.show(ScannerLiveGuidance.copy(framing: shownFraming, lighting: observation.lighting,
      layout: profile.layout), holding: readyQuad != nil)
    guard state.ready else {
      readySince = nil
      return
    }
    if readySince == nil { readySince = time }
    // Give the student a moment to fix shadow, glare or dim light, then
    // capture anyway: a slightly shadowed page beats no page.
    let lightingSettled = observation.lighting == .good || time - (readySince ?? time) >= Self.lightingGrace
    if lightingSettled && time - lastCaptureTime > 1.2 {
      beginCapture()
    }
  }

  private func handleCaptureObservation(_ observation: ScannerLiveObservation, readyQuad: ScannerQuadrilateral?,
                                        imageSize: CGSize, time: TimeInterval, processingDuration: TimeInterval) {
    if let requestedAt = awaitingMovedShot {
      let moved = readyQuad.map { quad in
        lastShotQuadrilateral.map {
          ScannerLightingAngleGuide.isDifferentAngle(quad, from: $0, imageSize: imageSize)
            || quad.maximumCornerDistance(to: $0) >= 0.05
        } ?? true
      } ?? false
      let state = shotTracker.observe(moved ? readyQuad : nil, at: time, processingDuration: processingDuration)
      overlay.progress = state.progress
      // Bounded: after a few seconds the next photo is taken where it is.
      guard state.ready || time - requestedAt >= Self.angleRequestLimit else { return }
      awaitingMovedShot = nil
      shotTracker.reset()
      burstRemaining = 1
      beginCaptureSettling()
      return
    }
    guard awaitingSteadyShot else { return }
    let state = shotTracker.observe(readyQuad, at: time, processingDuration: processingDuration)
    overlay.progress = state.progress
    guidanceView.show(ScannerLiveGuidance.copy(framing: readyQuad == nil ? observation.framing : .ready,
      lighting: .good, layout: profile.layout), holding: readyQuad != nil)
    guard state.ready else { return }
    awaitingSteadyShot = false
    shotTracker.reset()
    advanceCapture()
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
    guard !isAnalyzing, now - lastAnalysisTime >= 0.1,
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
    let observation: ScannerLiveObservation = autoreleasepool {
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
      return ScannerRectangleDetector.detectLive(in: upright, profile: profile)
    }
    isAnalyzing = false
    let processingDuration = CACurrentMediaTime() - now
    DispatchQueue.main.async { [weak self] in
      self?.handleLiveObservation(observation, imageSize: imageSize, time: now,
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
    let data = error == nil ? photo.fileDataRepresentation() : nil
#if SCANNER_DIAGNOSTICS
    let errorDomain = (error as NSError?)?.domain ?? "none"
    let errorCode = (error as NSError?)?.code ?? 0
#endif
    DispatchQueue.main.async { [weak self] in
      guard let self, self.activePhotoIDs.remove(photoID) != nil,
            self.isCapturing, !self.finishing else { return }
      let generation = self.captureGeneration
      let geometry = self.capturedGeometry.removeValue(forKey: photoID)
#if SCANNER_DIAGNOSTICS
      if let data { self.diagnosticCapturedPhoto?(data) }
#endif
      guard let data, let cancellation = self.captureCancellation else {
#if SCANNER_DIAGNOSTICS
        self.diagnosticEvent?(["event": "photo_unavailable", "errorDomain": errorDomain, "errorCode": errorCode])
#endif
        self.capturePolicy?.photoResolved(usefulViews: self.burstCandidates.count)
        self.advanceCapture()
        return
      }
      let manual = self.manualCapture
      self.processingQueue.async { [weak self] in
        guard let self, !cancellation.isCancelled else { return }
        let processingResult = self.processor.processCapture(photoData: data, profile: self.profile,
          liveQuadrilateral: geometry?.quad, liveImageSize: geometry?.size, allowFullFrame: manual)
        let candidate = try? processingResult.get()
        DispatchQueue.main.async { [weak self] in
          guard let self, self.isCapturing,
                self.captureGeneration == generation, !self.finishing else { return }
          let assessment = ScannerImageProcessor.assessViewQuality(accepted: self.burstCandidates, candidate: candidate)
          var useful = candidate != nil && (assessment == .accepted || assessment == .restartForEarlierSoftView)
          // Imagegen keeps the exact camera bytes of every useful view for the
          // CRM. A view that cannot be kept within the limits is not counted.
          if useful, self.profile.usesImagegen, !self.originalPhotos.append(data) { useful = false }
          if useful, let candidate {
            // v11 sends the JPEG it already made; the uncompressed page (about
            // 19 MB) is not needed once the view is judged, so it is dropped.
            let kept = ScannerProcessedCandidate(jpeg: candidate.jpeg, sharpness: candidate.sharpness,
              coverage: candidate.coverage, fingerprint: candidate.fingerprint)
            self.burstCandidates = ScannerImageProcessor.retainingUsefulViews(self.burstCandidates + [kept])
          } else if case let .failure(reason) = processingResult {
            self.lastPhotoFailure = reason
            // Say what to change while the next photo is taken.
            self.guidanceView.show(ScannerLiveGuidance.copy(
              framing: reason == .documentBoundaryNotFound ? .searching : .blurry,
              lighting: .good, layout: self.profile.layout), holding: false)
          }
#if SCANNER_DIAGNOSTICS
          let processingFailure: String
          if case let .failure(reason) = processingResult { processingFailure = reason.rawValue }
          else { processingFailure = "none" }
          self.diagnosticEvent?(["event": "view_processed", "accepted": useful,
            "qualityDecision": String(describing: assessment), "processingFailure": processingFailure,
            "photosTaken": self.photosTaken, "acceptedViews": self.burstCandidates.count, "manual": manual])
#endif
          self.capturePolicy?.photoResolved(usefulViews: self.burstCandidates.count)
          self.advanceCapture()
        }
      }
      // The next photo can be taken while this one is still being checked.
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
        guard let self, self.captureGeneration == generation else { return }
        self.advanceCapture()
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
  private var compactDetail: String?

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
    if compactInstructions, let compactDetail {
      detailLabel.text = compactDetail
    } else if compactInstructions {
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

  func show(_ copy: ScannerGuidanceCopy, holding: Bool) {
    apply(title: copy.title, detail: copy.detail, compact: copy.compact, holding: holding)
  }

  func show(title: String, detail: String, compact: String, holding: Bool) {
    apply(title: title, detail: detail, compact: compact, holding: holding)
  }

  func show(title: String, detail: String, stage: Int, accepted: Int, holding: Bool) {
    apply(title: title, detail: detail, compact: nil, holding: holding)
  }

  private func apply(title: String, detail: String, compact: String?, holding: Bool) {
    if fullTitle != title || fullDetail != detail || compactDetail != compact {
      fullTitle = title
      fullDetail = detail
      compactDetail = compact
      updateVisibleText()
    }
    accessibilityLabel = "\(title). \(detail)"
    accessibilityValue = nil
    let finished = title == "Scan ready" || title == "Photos ready"
    let image = finished ? "checkmark.circle"
      : title.hasPrefix("Tilt") ? "iphone.radiowaves.left.and.right"
      : title == "More light needed" ? "lightbulb"
      : holding ? "iphone" : "viewfinder"
    symbol.image = UIImage(systemName: image)
    symbol.tintColor = finished ? .systemGreen : .white
  }
}

private final class ScannerOverlayView: UIView {
  enum Style { case tracking, adjusting }
  private let outline = CAShapeLayer()
  var quadrilateral: [CGPoint]? { didSet { updateOutline(animated: true) } }
  var progress: CGFloat = 0 { didSet { if progress != oldValue { updateOutline(animated: false) } } }
  var style: Style = .tracking { didSet { if style != oldValue { updateOutline(animated: false) } } }
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
      // Corner marks say "fit the page here" without implying one orientation.
      path = UIBezierPath()
      let rect = guideRect
      if rect.width > 0, rect.height > 0 {
        let arm = min(rect.width, rect.height) * 0.12
        for (corner, dx, dy) in [(CGPoint(x: rect.minX, y: rect.minY), CGFloat(1), CGFloat(1)),
                                 (CGPoint(x: rect.maxX, y: rect.minY), -1, 1),
                                 (CGPoint(x: rect.maxX, y: rect.maxY), -1, -1),
                                 (CGPoint(x: rect.minX, y: rect.maxY), 1, -1)] {
          path.move(to: CGPoint(x: corner.x, y: corner.y + dy * arm))
          path.addLine(to: corner)
          path.addLine(to: CGPoint(x: corner.x + dx * arm, y: corner.y))
        }
      }
    }
    let previous = outline.presentation()?.path ?? outline.path
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    outline.path = path.cgPath
    outline.strokeColor = (detected
      ? (style == .adjusting ? UIColor.white.withAlphaComponent(0.85)
        : progress >= 1 ? UIColor.systemGreen : UIColor.systemBlue)
      : UIColor.white.withAlphaComponent(0.7)).cgColor
    outline.lineWidth = detected ? 2 : 3
    outline.lineDashPattern = nil
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
