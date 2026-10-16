/// A banking-app-style guided document camera for the Flutter shell.
///
/// The portal still owns cropping, enhancement, multi-page PDFs, upload, and
/// asynchronous OCR. This route only chooses WHEN to take the photograph.
/// It never sends a preview frame or personal document to any server.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'camera_luma.dart';
import 'scan_guidance.dart';

class GuidedScanResult {
  const GuidedScanResult.captured(this.file) : useLegacyCamera = false;
  const GuidedScanResult.fallback()
      : file = null, useLegacyCamera = true;

  final XFile? file;
  final bool useLegacyCamera;
}

class GuidedScanPage extends StatefulWidget {
  const GuidedScanPage({super.key, required this.kind});

  final GuidedDocumentKind kind;

  @override
  State<GuidedScanPage> createState() => _GuidedScanPageState();
}

class _GuidedScanPageState extends State<GuidedScanPage>
    with WidgetsBindingObserver {
  CameraController? _camera;
  Future<void>? _pendingDispose;
  final _analyzer = const ScanFrameAnalyzer();
  final _gate = ScanAutoCaptureGate();

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
    unawaited(_startCamera());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_closing) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _appActive = false;
      // Invalidate an initialize/start-stream still in flight as well.
      // Otherwise a permission dialog can leave a disposed preview alive.
      _cameraGeneration++;
      final previous = _camera;
      _camera = null;
      if (previous != null && !_busy) {
        _pendingDispose = previous.dispose();
      }
      _gate.reset();
      _previous = null;
      if (mounted) setState(() => _streamSupported = false);
    } else if (state == AppLifecycleState.resumed) {
      _appActive = true;
      if (_camera == null && !_busy && !_initializing) {
        unawaited(_startCamera());
      }
    }
  }

  Future<void> _startCamera() async {
    if (_initializing || _closing) return;
    _initializing = true;
    final generation = ++_cameraGeneration;
    CameraController? opened;
    try {
      await _pendingDispose;
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
          await opened.dispose();
          opened = null;
          if (error is CameraException &&
              error.code.toLowerCase().contains('access')) {
            rethrow;
          }
        }
      }

      if (opened == null) throw lastError ?? StateError('Camera unavailable');
      if (!mounted || _closing || !_appActive || generation != _cameraGeneration) {
        await opened.dispose();
        return;
      }
      _camera = opened;
      try {
        await opened.lockCaptureOrientation(DeviceOrientation.portraitUp);
      } catch (_) {
        // Rotation metadata still travels with the JPEG on older hardware.
      }
      try {
        await opened.startImageStream(_checkFrame);
        _streamSupported = true;
      } catch (_) {
        // A few camera implementations support still photos but no image
        // stream. Keep the shutter usable; never fake "auto-ready".
        _streamSupported = false;
      }
      if (!_appActive || generation != _cameraGeneration) {
        // An inactive event already owns disposal of this controller.
        return;
      }
      if (mounted && !_closing) {
        setState(() {
          _cameraFailed = false;
          _captureError = null;
        });
      }
    } catch (_) {
      if (opened != null && _camera != opened) {
        await opened.dispose().catchError((Object _) {});
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
        unawaited(_startCamera());
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
      }
      return;
    }
    final result = _analyzer.analyse(
      grid, widget.kind, previous: _previous,
    );
    _previous = grid;
    final capture = _gate.consume(result, now);
    if (mounted) {
      setState(() {
        _analysis = result;
        _progress = _gate.progress;
      });
    }
    if (capture) unawaited(_takePhoto());
  }

  Future<void> _takePhoto() async {
    final camera = _camera;
    if (_busy || camera == null || !camera.value.isInitialized) return;
    setState(() {
      _busy = true;
      _captureError = null;
    });
    try {
      // CameraX/AVFoundation cannot consistently take still photographs
      // concurrently with the preview stream. Stop it before takePicture.
      if (camera.value.isStreamingImages) await camera.stopImageStream();
      final photo = await camera.takePicture();
      if (!mounted || _closing) return;
      HapticFeedback.mediumImpact();
      _closing = true;
      Navigator.of(context).pop(GuidedScanResult.captured(photo));
    } catch (_) {
      if (!mounted || _closing) return;
      _gate.reset();
      _previous = null;
      setState(() {
        _busy = false;
        _progress = 0;
        _captureError = 'Could not take the photo. Try again or use the regular camera.';
      });
      if (camera.value.isInitialized &&
          !camera.value.isStreamingImages && _streamSupported) {
        try {
          await camera.startImageStream(_checkFrame);
        } catch (_) {
          if (mounted) setState(() => _streamSupported = false);
        }
      }
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

  void _toggleAuto() {
    _gate.reset();
    _previous = null;
    setState(() {
      _autoEnabled = !_autoEnabled;
      _progress = 0;
      _analysis = null;
    });
  }

  @override
  void dispose() {
    _closing = true;
    _cameraGeneration++;
    WidgetsBinding.instance.removeObserver(this);
    final camera = _camera;
    _camera = null;
    if (camera != null) unawaited(camera.dispose());
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
    final ready = _analysis?.autoReady == true && _streamSupported;
    final cameraWorking = camera?.value.isInitialized == true;
    final label = _captureError ??
        (_busy
          ? 'Capturing…'
          : _cameraFailed
            ? 'This camera is unavailable'
            : !cameraWorking
              ? 'Opening camera…'
              : !_autoEnabled || !_streamSupported
                ? 'Tap the shutter when ready'
                : _analysis?.hint.label ?? 'Align all four edges');
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
              painter: _ScanGuidePainter(widget.kind.guide, accent),
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
                            'Scan ${widget.kind.label}',
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
                      widget.kind.instruction,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70, fontSize: 12, height: 1.4,
                      ),
                    ),
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
                        onPressed: _busy
                            ? null
                            : () => Navigator.of(context).pop(
                                const GuidedScanResult.fallback(),
                              ),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Other camera'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Automatic capture when clear and steady · manual capture always available',
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
  const _ScanGuidePainter(this.normalizedGuide, this.color);
  final Rect normalizedGuide;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
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
        ..color = color.withValues(alpha: 0.36)
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
  }

  @override
  bool shouldRepaint(covariant _ScanGuidePainter oldDelegate) =>
      oldDelegate.normalizedGuide != normalizedGuide ||
      oldDelegate.color != color;
}
