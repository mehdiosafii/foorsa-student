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

final class FoorsaScannerViewController: UIViewController {
  typealias Completion = ([String: Any]) -> Void

  private struct Page {
    let data: Data
    let fingerprint: ScannerImageFingerprint
    let thumbnail: UIImage
  }

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
  private let statusLabel = UILabel()
  private let reviewButton = UIButton(type: .system)
  private let shutterButton = UIButton(type: .custom)
  private let torchButton = UIButton(type: .system)
  private let thumbnails = UIStackView()
  private let thumbnailScroll = UIScrollView()
  private let interruptionView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
  private var tracker = ScannerStabilityTracker()
  private var pages: [Page] = []
  private var totalBytes = 0
  private var lastAnalysisTime: TimeInterval = 0
  private var latestQuadrilateral: ScannerQuadrilateral?
  private var latestImageSize: CGSize?
  private var isAnalyzing = false
  private var isCapturing = false
  private var burstRemaining = 0
  private var burstCandidates: [ScannerProcessedCandidate] = []
  private var activePhotoIDs = Set<Int64>()
  private var pendingProcessingCount = 0
  private var captureGeneration = 0
  private var captureCancellation: ScannerBurstCancellationToken?
  private var captureWasAutomatic = false
  private var lastCaptureTime: TimeInterval = 0
  private var autoCaptureLocked = false
  private var documentMissingSince: TimeInterval?
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
        width: max(0, shutterButton.frame.minX - 24 - safe.minX),
        height: max(0, statusLabel.frame.minY - 12 - safe.minY - 67))
    } else {
      available = CGRect(x: safe.minX + 12, y: statusLabel.frame.maxY + 12,
        width: max(0, safe.width - 24),
        height: max(0, thumbnailScroll.frame.minY - 12 - statusLabel.frame.maxY - 12))
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
    cancel.accessibilityHint = "Closes the scanner without adding pages"

    let titleLabel = UILabel()
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.text = profile.title
    titleLabel.textColor = .white
    titleLabel.font = .preferredFont(forTextStyle: .headline)
    titleLabel.textAlignment = .center
    titleLabel.adjustsFontForContentSizeCategory = true
    titleLabel.minimumScaleFactor = 0.72
    titleLabel.adjustsFontSizeToFitWidth = true

    reviewButton.translatesAutoresizingMaskIntoConstraints = false
    var reviewConfiguration = UIButton.Configuration.filled()
    reviewConfiguration.title = "Review details (0)"
    reviewConfiguration.baseBackgroundColor = UIColor.systemBlue
    reviewConfiguration.cornerStyle = .capsule
    reviewConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 9, leading: 13, bottom: 9, trailing: 13)
    reviewButton.configuration = reviewConfiguration
    reviewButton.isEnabled = false
    reviewButton.addTarget(self, action: #selector(reviewPressed), for: .touchUpInside)
    reviewButton.accessibilityHint = "Returns all scanned pages to the application review"

    chrome.addSubview(cancel)
    chrome.addSubview(titleLabel)
    chrome.addSubview(reviewButton)

    statusLabel.translatesAutoresizingMaskIntoConstraints = false
    statusLabel.text = profile.instruction
    statusLabel.textColor = .white
    statusLabel.backgroundColor = UIColor.black.withAlphaComponent(0.58)
    statusLabel.font = .preferredFont(forTextStyle: .subheadline)
    statusLabel.textAlignment = .center
    statusLabel.numberOfLines = 2
    statusLabel.layer.cornerRadius = 13
    statusLabel.layer.masksToBounds = true
    statusLabel.adjustsFontForContentSizeCategory = true
    view.addSubview(statusLabel)

    shutterButton.translatesAutoresizingMaskIntoConstraints = false
    shutterButton.backgroundColor = .white
    shutterButton.layer.cornerRadius = 34
    shutterButton.layer.borderWidth = 5
    shutterButton.layer.borderColor = UIColor.white.withAlphaComponent(0.5).cgColor
    shutterButton.addTarget(self, action: #selector(shutterPressed), for: .touchUpInside)
    shutterButton.accessibilityLabel = "Capture page"
    shutterButton.accessibilityHint = "Takes several photos and keeps the clearest complete scan"
    view.addSubview(shutterButton)

    torchButton.translatesAutoresizingMaskIntoConstraints = false
    torchButton.setImage(UIImage(systemName: "flashlight.off.fill"), for: .normal)
    torchButton.tintColor = .white
    torchButton.backgroundColor = UIColor.black.withAlphaComponent(0.58)
    torchButton.layer.cornerRadius = 24
    torchButton.addTarget(self, action: #selector(torchPressed), for: .touchUpInside)
    torchButton.accessibilityLabel = "Turn torch on"
    view.addSubview(torchButton)

    thumbnailScroll.translatesAutoresizingMaskIntoConstraints = false
    thumbnailScroll.showsHorizontalScrollIndicator = false
    thumbnails.axis = .horizontal
    thumbnails.alignment = .center
    thumbnails.spacing = 10
    thumbnails.translatesAutoresizingMaskIntoConstraints = false
    thumbnailScroll.addSubview(thumbnails)
    view.addSubview(thumbnailScroll)

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
      statusLabel.topAnchor.constraint(equalTo: chrome.bottomAnchor, constant: 14),
      statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      statusLabel.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.88),
      statusLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
      shutterButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      shutterButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -18),
      torchButton.centerYAnchor.constraint(equalTo: shutterButton.centerYAnchor),
      torchButton.leadingAnchor.constraint(equalTo: shutterButton.trailingAnchor, constant: 38),
      thumbnailScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
      thumbnailScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
      thumbnailScroll.bottomAnchor.constraint(equalTo: shutterButton.topAnchor, constant: -14),
      thumbnailScroll.heightAnchor.constraint(equalToConstant: 78),
    ]
    landscapeConstraints = [
      statusLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
      statusLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
      statusLabel.trailingAnchor.constraint(equalTo: shutterButton.leadingAnchor, constant: -12),
      shutterButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
      shutterButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
      torchButton.centerXAnchor.constraint(equalTo: shutterButton.centerXAnchor),
      torchButton.topAnchor.constraint(equalTo: thumbnailScroll.bottomAnchor, constant: 8),
      thumbnailScroll.topAnchor.constraint(equalTo: chrome.bottomAnchor, constant: 8),
      thumbnailScroll.centerXAnchor.constraint(equalTo: shutterButton.centerXAnchor),
      thumbnailScroll.widthAnchor.constraint(equalToConstant: 78),
      thumbnailScroll.heightAnchor.constraint(equalToConstant: 78),
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
      reviewButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
      reviewButton.centerYAnchor.constraint(equalTo: cancel.centerYAnchor),
      reviewButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
      titleLabel.leadingAnchor.constraint(equalTo: cancel.trailingAnchor, constant: 6),
      titleLabel.trailingAnchor.constraint(equalTo: reviewButton.leadingAnchor, constant: -6),
      titleLabel.centerYAnchor.constraint(equalTo: cancel.centerYAnchor),
      statusLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
      shutterButton.widthAnchor.constraint(equalToConstant: 68),
      shutterButton.heightAnchor.constraint(equalToConstant: 68),
      torchButton.widthAnchor.constraint(equalToConstant: 48),
      torchButton.heightAnchor.constraint(equalToConstant: 48),
      thumbnails.leadingAnchor.constraint(equalTo: thumbnailScroll.contentLayoutGuide.leadingAnchor),
      thumbnails.trailingAnchor.constraint(equalTo: thumbnailScroll.contentLayoutGuide.trailingAnchor),
      thumbnails.topAnchor.constraint(equalTo: thumbnailScroll.contentLayoutGuide.topAnchor),
      thumbnails.bottomAnchor.constraint(equalTo: thumbnailScroll.contentLayoutGuide.bottomAnchor),
      thumbnails.heightAnchor.constraint(equalTo: thumbnailScroll.frameLayoutGuide.heightAnchor),
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
      guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
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
      self.photoOutput.maxPhotoQualityPrioritization = .balanced
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
      self?.statusLabel.text = "Camera paused"
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
        self.statusLabel.text = "Camera unavailable. Tap Resume scanning."
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
    statusLabel.text = profile.instruction
    if viewIfLoaded?.window != nil { setAnalysisActive(true) }
    startSession()
  }

  @objc private func resumePressed() { resumeSession() }

  @objc private func cancelPressed() {
    guard !finishing else { return }
    finishing = true
    abortCapture()
    completion(["cancelled": true])
  }

  @objc private func reviewPressed() {
    guard !finishing, !pages.isEmpty else { return }
    finishing = true
    abortCapture()
    completion([
      "pages": pages.map { $0.data },
      "engine": "avfoundation_vision",
      "scannerBuild": "custom-live-v3",
      "capabilities": [
        "live_quadrilateral", "stable_auto_capture", "best_of_three",
        "perspective_correction", "multi_page", "duplicate_guard", "manual_capture",
      ],
    ])
  }

  @objc private func shutterPressed() { beginCapture(automatic: false) }

  private func beginCapture(automatic: Bool) {
    guard !isCapturing, !finishing, configured, session.isRunning, !session.isInterrupted else { return }
    guard pages.count < 20 else {
      showMessage("You can scan up to 20 pages at once.")
      return
    }
    isCapturing = true
    setCaptureAnalysisPaused(true)
    captureWasAutomatic = automatic
    // In-flight capture is already guarded by isCapturing. Lock automatic
    // capture only after retaining a page (or rejecting a duplicate), so a
    // rejected/aborted burst can retry after a fresh steady hold.
    captureGeneration += 1
    captureCancellation = ScannerBurstCancellationToken()
    burstRemaining = 3
    burstCandidates.removeAll(keepingCapacity: true)
    activePhotoIDs.removeAll(keepingCapacity: true)
    pendingProcessingCount = 0
    tracker.reset()
    lastCaptureTime = CACurrentMediaTime()
    setCaptureControls(enabled: false)
    updateReviewButton()
    statusLabel.text = "Hold still — choosing the clearest shot…"
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    captureNextCandidate()
    let generation = captureGeneration
    DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
      guard let self, self.isCapturing, self.captureGeneration == generation else { return }
      self.abortCapture()
      self.showMessage("The camera took too long. Your earlier pages are safe; try this page again.")
    }
  }

  private func captureNextCandidate() {
    guard !finishing, isCapturing else { return }
    guard burstRemaining > 0 else {
      finishBurstIfReady()
      return
    }
    burstRemaining -= 1
    let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
    settings.photoQualityPrioritization = .balanced
    if #available(iOS 16.0, *) {
      settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions
    } else {
      settings.isHighResolutionPhotoEnabled = true
    }
    if let device = (session.inputs.first as? AVCaptureDeviceInput)?.device,
       device.isFlashAvailable {
      settings.flashMode = .off
    }
    activePhotoIDs.insert(settings.uniqueID)
    photoOutput.capturePhoto(with: settings, delegate: self)
  }

  private func finishBurstIfReady() {
    guard isCapturing, burstRemaining == 0,
          activePhotoIDs.isEmpty, pendingProcessingCount == 0 else { return }
    finishBurst()
  }

  private func abortCapture() {
    guard isCapturing else { return }
    isCapturing = false
    captureCancellation?.cancel()
    captureCancellation = nil
    setCaptureAnalysisPaused(false)
    captureGeneration += 1
    activePhotoIDs.removeAll()
    pendingProcessingCount = 0
    burstRemaining = 0
    burstCandidates.removeAll()
    tracker.reset()
    setCaptureControls(enabled: true)
    updateReviewButton()
  }

  private func finishBurst() {
    defer {
      isCapturing = false
      captureCancellation?.cancel()
      captureCancellation = nil
      setCaptureAnalysisPaused(false)
      captureWasAutomatic = false
      setCaptureControls(enabled: true)
      updateReviewButton()
      tracker.reset()
      burstCandidates.removeAll()
    }
    guard let best = ScannerCandidateSelector.best(burstCandidates) else {
      showMessage("Could not get a sharp, complete page. Keep every corner visible, hold still, and try again.")
      return
    }
    if ScannerDuplicatePolicy.shouldReject(
      candidate: best.fingerprint,
      previous: pages.last?.fingerprint,
      automatic: captureWasAutomatic
    ) {
      autoCaptureLocked = true
      documentMissingSince = nil
      showMessage("This looks like the same page. Turn to the next page, then capture again.")
      return
    }
    guard totalBytes + best.jpeg.count <= 24 * 1024 * 1024 else {
      autoCaptureLocked = true
      documentMissingSince = nil
      showMessage("These pages are over 24 MB. Review the current pages or remove one before continuing.")
      return
    }
    guard let image = UIImage(data: best.jpeg),
          let thumbnail = makeThumbnail(from: image) else {
      showMessage("The page could not be prepared. Please try again.")
      return
    }
    pages.append(Page(data: best.jpeg, fingerprint: best.fingerprint, thumbnail: thumbnail))
    // Keep automatic capture disabled until the current document leaves the
    // frame. The shutter remains available for an intentional override.
    autoCaptureLocked = true
    documentMissingSince = nil
    totalBytes += best.jpeg.count
    rebuildThumbnails()
    updateReviewButton()
    statusLabel.text = "Page \(pages.count) added. Turn to the next page or review details."
    UINotificationFeedbackGenerator().notificationOccurred(.success)
    UIAccessibility.post(notification: .announcement, argument: "Page \(pages.count) added")
  }

  private func makeThumbnail(from image: UIImage) -> UIImage? {
    let maximum = CGSize(width: 120, height: 160)
    let scale = min(maximum.width / max(image.size.width, 1),
                    maximum.height / max(image.size.height, 1))
    let size = CGSize(width: max(1, image.size.width * scale),
                      height: max(1, image.size.height * scale))
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    return UIGraphicsImageRenderer(size: size, format: format).image { context in
      UIColor.white.setFill()
      context.fill(CGRect(origin: .zero, size: size))
      image.draw(in: CGRect(origin: .zero, size: size))
    }
  }

  private func setCaptureControls(enabled: Bool) {
    shutterButton.isEnabled = enabled
    shutterButton.alpha = enabled ? 1 : 0.45
    torchButton.isEnabled = enabled
  }

  private func updateReviewButton() {
    reviewButton.isEnabled = !pages.isEmpty && !isCapturing
    reviewButton.configuration?.title = "Review details (\(pages.count))"
    reviewButton.accessibilityValue = "\(pages.count) pages"
  }

  private func rebuildThumbnails() {
    thumbnails.arrangedSubviews.forEach { view in
      thumbnails.removeArrangedSubview(view)
      view.removeFromSuperview()
    }
    for (index, page) in pages.enumerated() {
      let container = UIView()
      container.translatesAutoresizingMaskIntoConstraints = false
      container.widthAnchor.constraint(equalToConstant: 58).isActive = true
      container.heightAnchor.constraint(equalToConstant: 74).isActive = true
      let imageView = UIImageView(image: page.thumbnail)
      imageView.translatesAutoresizingMaskIntoConstraints = false
      imageView.contentMode = .scaleAspectFill
      imageView.clipsToBounds = true
      imageView.layer.cornerRadius = 7
      imageView.layer.borderWidth = 1
      imageView.layer.borderColor = UIColor.white.withAlphaComponent(0.75).cgColor
      imageView.isAccessibilityElement = true
      imageView.accessibilityLabel = "Scanned page \(index + 1)"
      let remove = UIButton(type: .system)
      remove.translatesAutoresizingMaskIntoConstraints = false
      remove.tag = index
      remove.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
      remove.tintColor = .white
      remove.backgroundColor = UIColor.black.withAlphaComponent(0.75)
      remove.layer.cornerRadius = 12
      remove.accessibilityLabel = "Remove page \(index + 1)"
      remove.addTarget(self, action: #selector(removePage(_:)), for: .touchUpInside)
      container.addSubview(imageView)
      container.addSubview(remove)
      NSLayoutConstraint.activate([
        imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
        imageView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        imageView.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
        imageView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        remove.widthAnchor.constraint(equalToConstant: 28),
        remove.heightAnchor.constraint(equalToConstant: 28),
        remove.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: 5),
        remove.topAnchor.constraint(equalTo: container.topAnchor, constant: -2),
      ])
      thumbnails.addArrangedSubview(container)
    }
    thumbnailScroll.isHidden = pages.isEmpty
  }

  @objc private func removePage(_ sender: UIButton) {
    guard pages.indices.contains(sender.tag), !isCapturing else { return }
    totalBytes -= pages[sender.tag].data.count
    pages.remove(at: sender.tag)
    rebuildThumbnails()
    updateReviewButton()
    statusLabel.text = pages.isEmpty ? profile.instruction : "Page removed. \(pages.count) pages remain."
    UIAccessibility.post(notification: .announcement, argument: "Page removed")
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
    guard !finishing else { return }
    finishing = true
    completion(["error": message])
  }

  private func showMessage(_ message: String) {
    statusLabel.text = message
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
    // inference while the three stills are processed one at a time.
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
    updatePreviewGeometry()
    renderQuadrilateral(quadrilateral, imageSize: imageSize)
    guard !isCapturing else { return }
    let shapeAccepted = quadrilateral.map {
      profile.accepts(aspectRatio: $0.estimatedAspectRatio(in: imageSize))
    } ?? false
    let state = tracker.observe(shapeAccepted ? quadrilateral : nil, at: time,
      processingDuration: processingDuration)
    overlay.progress = state.progress
    if quadrilateral == nil {
      if autoCaptureLocked {
        if let missingSince = documentMissingSince, time - missingSince >= 0.45 {
          autoCaptureLocked = false
          documentMissingSince = nil
        } else if documentMissingSince == nil {
          documentMissingSince = time
        }
      }
      statusLabel.text = "Keep every corner visible and hold still while the camera focuses."
      return
    }
    documentMissingSince = nil
    guard shapeAccepted else {
      statusLabel.text = "Rotate the document so its full shape fits the guide."
      return
    }
    if state.ready {
      statusLabel.text = "Page steady"
      if !autoCaptureLocked && time - lastCaptureTime > 2.2 {
        beginCapture(automatic: true)
      }
    } else {
      statusLabel.text = state.progress > 0.15 ? "Hold still…" : profile.instruction
    }
  }

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
      if let data, let cancellation = self.captureCancellation {
        self.pendingProcessingCount += 1
        self.processingQueue.async { [weak self] in
          guard let self, !cancellation.isCancelled else { return }
          let candidate = self.processor.process(photoData: data, profile: self.profile)
          DispatchQueue.main.async { [weak self] in
            guard let self, self.isCapturing,
                  self.captureGeneration == generation, !self.finishing else { return }
            self.pendingProcessingCount -= 1
            if let candidate { self.burstCandidates.append(candidate) }
            self.finishBurstIfReady()
          }
        }
      }
      // Start the next photo as soon as camera data arrives. Image correction
      // for the previous shot can run concurrently.
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
        guard let self, self.captureGeneration == generation else { return }
        self.captureNextCandidate()
      }
    }
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
