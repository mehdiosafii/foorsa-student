/// A banking-app-style guided document camera for the Flutter shell.
///
/// The portal still owns cropping, enhancement, multi-page PDFs, upload, and
/// asynchronous OCR. This route only chooses WHEN to take the photograph: once
/// the page is steady AND the reading on the phone (ML Kit's bundled model,
/// live_text_reader.dart) says it is the paper the step asked for. It never
/// sends a preview frame or personal document to any server.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'camera_luma.dart';
import 'live_text_reader.dart';
import 'scan_guidance.dart';
import 'scan_document_profile.dart';
import 'scan_text_reading.dart';

class GuidedScanResult {
  const GuidedScanResult.captured(this.file, {this.liveReading})
      : useLegacyCamera = false;
  const GuidedScanResult.fallback()
      : file = null, useLegacyCamera = true, liveReading = null;

  final XFile? file;
  final bool useLegacyCamera;

  /// What was read on the phone while the page was in view, checked and
  /// bounded (scan_text_reading.dart), for this capture only. Null without a
  /// text reader.
  final Map<String, Object>? liveReading;
}

class GuidedScanPage extends StatefulWidget {
  const GuidedScanPage({super.key, required this.profile});

  final GuidedDocumentProfile profile;

  @override
  State<GuidedScanPage> createState() => _GuidedScanPageState();
}

class _GuidedScanPageState extends State<GuidedScanPage>
    with WidgetsBindingObserver {
  CameraController? _camera;
  Future<void>? _pendingDispose;
  Future<void>? _pendingStart;
  final _analyzer = const ScanFrameAnalyzer();
  final _gate = ScanAutoCaptureGate();
  // When the page is taken with no tap: steady and read, steady for a moment,
  // or in view long enough (ScanAutoShutter). A soft frame no longer starts
  // the wait over.
  final _shutter = ScanAutoShutter();
  // The live reading: steady is not enough, the page must also read as the
  // paper this step asked for before the camera takes it by itself, or have
  // been clear for a moment while the reading still looks.
  late final ScanTextReadingSession _reading =
      ScanTextReadingSession.forProfile(widget.profile);
  final _textChannel = LiveTextChannel();
  static const _textInterval = Duration(milliseconds: 300);
  ScanTextGateStatus? _readingStatus;
  bool _textBusy = false;
  DateTime? _lastTextRead;
  Duration _lastTextDuration = Duration.zero;
  int _textEpoch = 0;
  bool _captureMatched = false;

  ScanLumaGrid? _previous;
  ScanFrameAnalysis? _analysis;
  DateTime? _lastProcessed;
  int _cameraGeneration = 0;
  bool _initializing = false;
  bool _appActive = true;
  bool _closing = false;
  bool _busy = false;
  bool _cameraFailed = false;
  bool _streamSupported = false;
  bool _autoEnabled = true;
  bool _torch = false;
  String? _captureError;
  double _progress = 0;
  double? _viewportAspect;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Only the Android app carries a text model; an iPhone that falls back to
    // this camera captures on steadiness alone, as before.
    if (!Platform.isAndroid) _reading.markReaderUnavailable();
    _scheduleCameraStart();
  }

  void _restartReading() {
    _reading.reset();
    _textEpoch++;
    _lastTextRead = null;
  }

  void _scheduleCameraStart() {
    if (_initializing || _closing) return;
    final start = _startCamera();
    _pendingStart = start;
    unawaited(start.whenComplete(() {
      if (identical(_pendingStart, start)) _pendingStart = null;
    }));
  }

  Future<void> _disposeCamera(CameraController camera) async {
    try {
      await camera.dispose().timeout(const Duration(seconds: 3));
    } catch (_) {
      // Camera backends can already have released the device after a pause.
    }
  }

  Future<void> _discardLateCapture(Future<XFile> capture) async {
    try {
      final photo = await capture;
      await File(photo.path).delete();
    } catch (_) {
      // Disposing a timed-out controller normally completes capture in error.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_closing) return;
    if (state != AppLifecycleState.resumed) {
      _appActive = false;
      // Invalidate an initialize/start-stream still in flight as well.
      // Otherwise a permission dialog can leave a disposed preview alive.
      _cameraGeneration++;
      final previous = _camera;
      _camera = null;
      if (previous != null && !_busy) {
        _pendingDispose = _disposeCamera(previous);
      }
      _gate.reset();
      _shutter.reset();
      _restartReading();
      _previous = null;
      _lastProcessed = null;
      if (mounted) setState(() => _streamSupported = false);
    } else {
      _appActive = true;
      if (_camera == null && !_busy && !_initializing) {
        _scheduleCameraStart();
      }
    }
  }

  Future<void> _startCamera() async {
    if (_initializing || _closing) return;
    _initializing = true;
    final generation = ++_cameraGeneration;
    CameraController? opened;
    try {
      final pendingDispose = _pendingDispose;
      _pendingDispose = null;
      await pendingDispose;
      if (!mounted || _closing || !_appActive || generation != _cameraGeneration) return;
      final cameras = await availableCameras();
      final rearCameras = cameras.where(
        (camera) => camera.lensDirection == CameraLensDirection.back,
      );
      if (rearCameras.isEmpty) throw StateError('No rear camera');
      final description = rearCameras.first;
      Object? lastError;

      // 1080p is sufficient for the scan editor without forcing a 4K image
      // stream on low-memory phones. 720p initialization is an OS fallback.
      for (final preset in [
        ResolutionPreset.veryHigh, ResolutionPreset.high,
      ]) {
        opened = CameraController(
          description, preset,
          enableAudio: false,
          imageFormatGroup: Platform.isIOS
              ? ImageFormatGroup.bgra8888
              : ImageFormatGroup.yuv420,
        );
        try {
          await opened.initialize();
          break;
        } catch (error) {
          lastError = error;
          await _disposeCamera(opened);
          opened = null;
          if (error is CameraException &&
              error.code.toLowerCase().contains('access')) {
            rethrow;
          }
        }
      }

      if (opened == null) throw lastError ?? StateError('Camera unavailable');
      if (!mounted || _closing || !_appActive || generation != _cameraGeneration) {
        await _disposeCamera(opened);
        return;
      }
      _camera = opened;
      try {
        await opened.lockCaptureOrientation(DeviceOrientation.portraitUp);
      } catch (_) {
        // Rotation metadata still travels with the JPEG on older hardware.
      }
      if (_autoEnabled) {
        try {
          await opened.startImageStream(_checkFrame);
          _streamSupported = true;
        } catch (_) {
          // A few camera implementations support still photos but no image
          // stream. Keep the shutter usable; never fake "auto-ready".
          _streamSupported = false;
        }
      } else {
        // Auto-capture was disabled before a lifecycle restart. Do not resume
        // the expensive stream until the student turns it back on.
        _streamSupported = true;
      }
      if (!_appActive || generation != _cameraGeneration) {
        // An inactive event already owns disposal of this controller.
        return;
      }
      if (mounted && !_closing) {
        setState(() {
          _cameraFailed = false;
          _captureError = null;
          _torch = false;
        });
      }
    } catch (_) {
      if (opened != null && _camera != opened) {
        await _disposeCamera(opened);
      }
      if (mounted && !_closing) {
        setState(() {
          _cameraFailed = true;
          _streamSupported = false;
        });
      }
    } finally {
      _initializing = false;
      // A resume that arrived while initialize() was outstanding must
      // reopen the camera; otherwise the preview may remain blank.
      if (_appActive && !_closing && mounted && !_busy &&
          _camera == null && generation != _cameraGeneration) {
        _scheduleCameraStart();
      }
    }
  }

  void _checkFrame(CameraImage image) {
    if (_busy || _closing || !mounted ||
        !_autoEnabled || !_streamSupported) {
      return;
    }
    final now = DateTime.now();
    if (_lastProcessed != null &&
        now.difference(_lastProcessed!).inMilliseconds < 230) {
      return;
    }
    _lastProcessed = now;
    final grid = sampleCameraLuma(image, viewportAspect: _viewportAspect);
    if (grid == null) {
      // Unsupported preview formats must never auto-trigger.
      if (_streamSupported && mounted) {
        setState(() => _streamSupported = false);
        final camera = _camera;
        if (camera != null) unawaited(_stopImageStream(camera));
      }
      return;
    }
    final kind = switch (widget.profile.layout) {
      GuidedScanLayout.passport => GuidedDocumentKind.passport,
      GuidedScanLayout.card => GuidedDocumentKind.idCard,
      _ => GuidedDocumentKind.page,
    };
    final result = _analyzer.analyse(
      grid, kind,
      previous: _previous,
      profile: widget.profile,
      viewportAspect: _viewportAspect ?? 0.5,
    );
    _previous = grid;
    // The reading belongs to one page: it starts over when the page has been
    // gone a moment or another outline takes its place.
    if (_reading.observePage(result.bounds, now)) _restartReading();
    _readText(image, result, now);
    final steady = _gate.observe(result, now);
    final reading = _reading.status(glare: result.hint == ScanHint.reduceGlare);
    if (mounted) {
      setState(() {
        _analysis = result;
        _readingStatus = reading;
        _progress = reading.allowsCapture
            ? _gate.progress : math.min(_gate.progress, 0.85);
      });
    }
    // Taken with no tap: steady and read, steady for a moment, or in view long
    // enough; shadow, glare or dim light get a moment to be fixed first; the
    // wrong paper, or the wrong side of a card, is never taken.
    final page = steady ? ScanShutterPage.steady
        : result.bounds != null ? ScanShutterPage.inView : ScanShutterPage.missing;
    final lightingGood = result.hint != ScanHint.brighten && result.hint != ScanHint.reduceGlare;
    if (!_busy && _shutter.observe(page, now, reading: reading, kind: _reading.kind, lightingGood: lightingGood)) {
      _captureMatched = reading.passed;
      unawaited(_takePhoto(automatic: true));
    }
  }

  /// Hands the page to ML Kit a few times a second, one read at a time. The
  /// frame callback never waits for it.
  void _readText(CameraImage image, ScanFrameAnalysis analysis, DateTime now) {
    final bounds = analysis.bounds;
    if (bounds == null || _textBusy || _reading.readerUnavailable ||
        image.format.group != ImageFormatGroup.yuv420 || image.planes.isEmpty) {
      return;
    }
    final last = _lastTextRead;
    final backoff = _lastTextDuration * 1.5;
    final interval = backoff > _textInterval ? backoff : _textInterval;
    if (last != null && now.difference(last) < interval) return;
    final crop = LiveTextCrop.forPage(bounds,
        sensorWidth: image.width, sensorHeight: image.height,
        viewportAspect: _viewportAspect, turns: _reading.turnPolicy);
    final plane = image.planes.first;
    final luma = crop?.extract(plane.bytes,
        rowStride: plane.bytesPerRow, pixelStride: plane.bytesPerPixel ?? 1);
    if (crop == null || luma == null) return;
    _textBusy = true;
    _lastTextRead = now;
    final epoch = _textEpoch;
    final started = DateTime.now();
    unawaited(_textChannel.read(luma, crop).then((result) {
      _textBusy = false;
      _lastTextDuration = DateTime.now().difference(started);
      if (!mounted || _closing || _busy || epoch != _textEpoch) return;
      switch (result.status) {
        case LiveTextReadStatus.read:
          _reading.ingest(crop.frame(result.lines));
        case LiveTextReadStatus.failed:
          _reading.readFailed();
        case LiveTextReadStatus.unavailable:
          _reading.markReaderUnavailable();
        case LiveTextReadStatus.busy:
          break;
      }
    }));
  }

  /// What was read, for this capture. A photo taken by hand returns whatever
  /// had been read by then.
  Map<String, Object>? _liveReadingFor({required bool automatic}) {
    if (!Platform.isAndroid) return null;
    final matched = automatic
        ? _captureMatched : _reading.status(glare: false).passed;
    return sanitizeLiveReading(_reading.liveReading(engine: 'mlkit_latin',
        matched: matched, referenceYear: DateTime.now().year));
  }

  Future<void> _takePhoto({bool automatic = false}) async {
    final camera = _camera;
    if (_busy || camera == null || !camera.value.isInitialized) return;
    Future<XFile>? capture;
    XFile? capturedPhoto;
    var delivered = false;
    setState(() {
      _busy = true;
      _captureError = null;
    });
    try {
      // CameraX/AVFoundation cannot consistently take still photographs
      // concurrently with the preview stream. Stop it before takePicture.
      if (camera.value.isStreamingImages) {
        await camera.stopImageStream().timeout(const Duration(seconds: 3));
      }
      capture = camera.takePicture();
      final photo = await capture.timeout(
        const Duration(seconds: 15),
      );
      capturedPhoto = photo;
      if (!mounted || _closing) {
        await _disposeCamera(camera);
        return;
      }
      HapticFeedback.mediumImpact();
      _closing = true;
      _camera = null;
      _cameraGeneration++;
      await _disposeCamera(camera);
      if (!mounted) return;
      Navigator.of(context).pop(GuidedScanResult.captured(photo,
          liveReading: _liveReadingFor(automatic: automatic)));
      delivered = true;
    } catch (error) {
      final captureTimedOut = error is TimeoutException;
      if (captureTimedOut && capture != null) {
        unawaited(_discardLateCapture(capture));
      }
      if (!mounted || _closing) return;
      if (captureTimedOut && _camera == camera) {
        _camera = null;
        _cameraGeneration++;
      }
      _gate.reset();
      _shutter.reset();
      _previous = null;
      setState(() {
        _busy = false;
        _progress = 0;
        _captureError = 'Could not take the photo. Try again or use the regular camera.';
      });
      // A pause can detach the controller while takePicture is in flight.
      // If resume already happened, start a fresh controller now instead of
      // leaving the page permanently on "Opening camera…".
      if (captureTimedOut || _camera != camera || !_appActive) {
        await _disposeCamera(camera);
        if (_appActive && mounted && !_closing) _scheduleCameraStart();
      } else if (camera.value.isInitialized && _autoEnabled &&
          !camera.value.isStreamingImages && _streamSupported) {
        try {
          await camera.startImageStream(_checkFrame);
        } catch (_) {
          if (mounted) setState(() => _streamSupported = false);
        }
      }
    } finally {
      if (_camera != camera || _closing) await _disposeCamera(camera);
      if (!delivered && capturedPhoto != null) {
        try { await File(capturedPhoto.path).delete(); } catch (_) {
          // The capture may already have been removed during route disposal.
        }
      }
    }
  }

  Future<void> _useOtherCamera() async {
    if (_busy || _closing) return;
    _closing = true;
    _cameraGeneration++;
    // A low-end device may still be opening the guided camera. Wait for that
    // attempt to observe _closing and release its controller before launching
    // the OS camera, otherwise the fallback can fail with "camera in use".
    final pendingStart = _pendingStart;
    if (pendingStart != null) {
      try {
        await pendingStart.timeout(const Duration(seconds: 3));
      } catch (_) {
        // A wedged camera backend must not make the fallback button hang.
      }
    }
    final previous = _camera;
    _camera = null;
    if (previous != null) await _disposeCamera(previous);
    if (mounted) {
      Navigator.of(context).pop(const GuidedScanResult.fallback());
    }
  }

  Future<void> _toggleTorch() async {
    final camera = _camera;
    if (camera == null || _busy) return;
    try {
      final newState = !_torch;
      await camera.setFlashMode(newState ? FlashMode.torch : FlashMode.off);
      if (mounted) setState(() => _torch = newState);
    } catch (_) {
      // Not every rear camera provides a torch.
    }
  }

  Future<void> _stopImageStream(CameraController camera) async {
    try {
      if (camera.value.isInitialized && camera.value.isStreamingImages) {
        await camera.stopImageStream().timeout(const Duration(seconds: 3));
      }
    } catch (_) {
      // Manual capture remains available if stream shutdown is unsupported.
    }
  }

  Future<void> _toggleAuto() async {
    _gate.reset();
    _shutter.reset();
    _restartReading();
    _previous = null;
    _lastProcessed = null;
    final enabling = !_autoEnabled;
    setState(() {
      _autoEnabled = enabling;
      _progress = 0;
      _analysis = null;
    });
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) return;
    if (!enabling) {
      // Keeping a full camera image stream alive while auto-capture is off is
      // expensive on budget phones even though Dart ignores the callbacks.
      await _stopImageStream(camera);
      return;
    }
    if (!camera.value.isStreamingImages) {
      try {
        await camera.startImageStream(_checkFrame);
      } catch (_) {
        if (mounted && _camera == camera) {
          setState(() => _streamSupported = false);
        }
      }
    }
  }

  @override
  void dispose() {
    _closing = true;
    _cameraGeneration++;
    WidgetsBinding.instance.removeObserver(this);
    final camera = _camera;
    _camera = null;
    if (camera != null) unawaited(_disposeCamera(camera));
    unawaited(_textChannel.close());
    super.dispose();
  }

  Widget _cameraPreview(CameraController camera) {
    return LayoutBuilder(
      builder: (context, bounds) {
        if (bounds.maxWidth > 0 && bounds.maxHeight > 0) {
          _viewportAspect = bounds.maxWidth / bounds.maxHeight;
        }
        final size = camera.value.previewSize;
        if (size == null || size.width <= 0 || size.height <= 0) {
          return const SizedBox.expand();
        }
        // Camera buffer is landscape in portrait orientation. Cover, rather
        // than stretching, and clip outside the screen to preserve geometry.
        final width = size.height;
        final height = size.width;
        final scale = math.max(
          bounds.maxWidth / width, bounds.maxHeight / height,
        );
        return ClipRect(
          child: Center(
            child: SizedBox(
              width: width * scale,
              height: height * scale,
              child: CameraPreview(camera),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    final readingWaits = _readingStatus?.allowsCapture == false;
    final ready = _analysis?.autoReady == true && _streamSupported && !readingWaits;
    final cameraWorking = camera?.value.isInitialized == true;
    // Framing comes first; once the page is aligned, what the reading still
    // needs (the bottom lines, the other side, a different paper).
    final readingHint = _analysis?.autoReady == true && readingWaits
        ? _readingStatus?.guidance?.copy(_reading.kind).detail : null;
    final label = _captureError ??
        (_busy
          ? 'Capturing…'
          : _cameraFailed
            ? 'This camera is unavailable'
            : !cameraWorking
              ? 'Opening camera…'
              : !_autoEnabled || !_streamSupported
                ? 'Tap the shutter when ready'
                : readingHint ?? _analysis?.hint.label ?? 'Align all four edges');
    final accent = ready ? const Color(0xFF3DE5B4) : Colors.white;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (cameraWorking)
              _cameraPreview(camera!)
            else
              const Center(
                child: Icon(Icons.document_scanner_outlined,
                    size: 80, color: Colors.white30),
              ),
            // Painted in viewport coordinates using the same normalized
            // guide used by live frame analysis.
            CustomPaint(
              painter: _ScanGuidePainter(
                _analysis?.bounds ?? widget.profile.guide(_viewportAspect ?? 0.5),
                accent,
                zones: widget.profile.zones,
                detected: _analysis?.bounds != null,
              ),
            ),
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Close scanner',
                          onPressed: _busy ? null
                            : () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close, color: Colors.white),
                        ),
                        Expanded(
                          child: Text(
                            'Scan ${widget.profile.title}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white, fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: _torch ? 'Turn light off' : 'Turn light on',
                          onPressed: cameraWorking && !_busy ? _toggleTorch : null,
                          icon: Icon(
                            _torch ? Icons.flash_on : Icons.flash_off,
                            color: _torch ? const Color(0xFF3DE5B4) : Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.profile.instruction,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70, fontSize: 12, height: 1.4,
                      ),
                    ),
                    if (widget.profile.pagesHint.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        widget.profile.pagesHint,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFB8DDFF),
                          fontSize: 11, height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Positioned(
              left: 18,
              right: 18,
              bottom: 14,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    liveRegion: true,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xE6151A22),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            label,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: ready ? const Color(0xFF3DE5B4) : Colors.white,
                              fontSize: 15, fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: _autoEnabled && _streamSupported
                                  ? _progress : 0,
                              minHeight: 3,
                              backgroundColor: Colors.white24,
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                Color(0xFF3DE5B4),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        onPressed: cameraWorking && _streamSupported && !_busy
                            ? _toggleAuto : null,
                        icon: Icon(
                          _autoEnabled ? Icons.auto_awesome : Icons.touch_app,
                          size: 18,
                        ),
                        label: Text(_autoEnabled ? 'Auto on' : 'Auto off'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                        ),
                      ),
                      GestureDetector(
                        onTap: cameraWorking && !_busy ? _takePhoto : null,
                        child: Semantics(
                          button: true,
                          label: 'Take photo manually',
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white, width: 4,
                              ),
                              color: Colors.white24,
                            ),
                            child: Center(
                              child: Container(
                                width: 56, height: 56,
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _busy ? null : _useOtherCamera,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Other camera'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Automatic capture once the right paper is clear and steady · manual capture always available',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white60, fontSize: 11, height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanGuidePainter extends CustomPainter {
  const _ScanGuidePainter(this.normalizedGuide, this.color, {
    required this.zones,
    required this.detected,
  });

  final Rect normalizedGuide;
  final Color color;
  final List<String> zones;
  final bool detected;

  @override
  void paint(Canvas canvas, Size size) {
    // Dynamic border is the candidate's ACTUAL detected extent; the guide
    // is only displayed while no complete document is confidently located.
    final rect = Rect.fromLTRB(
      normalizedGuide.left * size.width,
      normalizedGuide.top * size.height,
      normalizedGuide.right * size.width,
      normalizedGuide.bottom * size.height,
    );
    final rounded = RRect.fromRectAndRadius(
      rect, const Radius.circular(16),
    );
    final veil = Path()..fillType = PathFillType.evenOdd;
    veil.addRect(Offset.zero & size);
    veil.addRRect(rounded);
    canvas.drawPath(
      veil, Paint()..color = const Color(0x99000000),
    );
    canvas.drawRRect(
      rounded,
      Paint()
        ..color = color.withValues(alpha: detected ? 0.48 : 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    final corners = Path();
    const segment = 28.0;
    final l = rect.left;
    final r = rect.right;
    final t = rect.top;
    final b = rect.bottom;
    corners
      ..moveTo(l, t + segment)..lineTo(l, t)..lineTo(l + segment, t)
      ..moveTo(r - segment, t)..lineTo(r, t)..lineTo(r, t + segment)
      ..moveTo(l, b - segment)..lineTo(l, b)..lineTo(l + segment, b)
      ..moveTo(r - segment, b)..lineTo(r, b)..lineTo(r, b - segment);
    canvas.drawPath(
      corners,
      Paint()
        ..color = color
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );

    // These zones are visual hints only. We DO NOT pretend the camera has
    // already recognized the passport photo/MRZ or verified a medical stamp.
    if (zones.contains('passport_mrz')) {
      final zone = Rect.fromLTWH(
        rect.left + rect.width * 0.07,
        rect.top + rect.height * 0.77,
        rect.width * 0.86,
        rect.height * 0.17,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(zone, const Radius.circular(5)),
        Paint()
          ..color = color.withValues(alpha: 0.50)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3,
      );
    }
    if (zones.contains('passport_photo')) {
      final zone = Rect.fromLTWH(
        rect.left + rect.width * 0.08,
        rect.top + rect.height * 0.14,
        rect.width * 0.23,
        rect.height * 0.51,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(zone, const Radius.circular(4)),
        Paint()
          ..color = color.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ScanGuidePainter oldDelegate) =>
      oldDelegate.normalizedGuide != normalizedGuide ||
      oldDelegate.color != color ||
      oldDelegate.detected != detected ||
      oldDelegate.zones != zones;
}
