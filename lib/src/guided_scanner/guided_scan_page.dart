/// A banking-app-style guided document camera for the Flutter shell.
///
/// The portal still owns cropping, multi-page PDFs, upload, and asynchronous
/// OCR. This route only chooses WHEN to take the photograph: once the page is
/// steady AND the reading on the phone (ML Kit's bundled model,
/// live_text_reader.dart) says it is the paper the step asked for. It never
/// sends a preview frame or personal document to any server.
///
/// What changed on 31 Oct 2026 (the owner, on an Android phone: "the image is
/// very very very bad ... and you still need to click the capture button"):
///
/// - The photo is the sensor's full 4:3 frame ([ResolutionPreset.max]; on
///   most phones 12 MP), focused on the page just before it is taken, then
///   made upright and bounded to 8 MP on the phone (scan_photo.dart). Before,
///   the camera was opened at 1080p for its image stream, and the plugin uses
///   that one resolution for the still photo too: a 1920×1080 frame, of which
///   a page in the guide kept about 700 pixels across.
/// - The preview shows the whole photo, so what the guide frames is what is
///   taken, at full width, and the preview is drawn at its own resolution.
/// - Frames are asked for one at a time, a few a second (the image stream
///   otherwise copies every frame, 30 a second, across the platform channel),
///   and their pixels are worked on a worker isolate (scan_frame_processor.dart).
/// - The page is found wherever it is held (scan_page_segment.dart), or by
///   its text when it has no visible outline (scan_frame_loop.dart).
///
/// And on 1 Nov 2026 (the owner: "guide the student to take the perfect
/// picture while taking the picture so the work is easier for ai"), the
/// screen says one thing at a time, in the iPhone's words and order
/// (scan_coach.dart): find the page, the whole page, closer, the phone flat,
/// the light, what the reading still needs, then hold still; the outline is
/// dashed until the page is held and solid while it is (scan_guidance_view.dart).
///
/// And later on 1 Nov 2026 (the owner, on an Android 17 phone: "In Android the
/// scanning didn't show the auto scanning interface"), the page says when it
/// loses automatic capture, and keeps it where it can:
///
/// - On Android the image stream's camera side runs after startImageStream
///   has returned, and its errors never reach the page: a stream that failed
///   sends no frame. A frame not in by [guidedScanFrameWait] counts as a
///   failure too, as a throw or a frame the scanner cannot read already did
///   (once frames have come, after one more ask: a busy phone, or a frame
///   lost between two asks).
/// - A stream that fails at [ResolutionPreset.max] before its first frame
///   reopens the camera once at [ResolutionPreset.veryHigh] (1080p stills, but
///   automatic capture) instead of leaving the shutter alone.
/// - Each such loss, a camera that does not open, and a student who leaves
///   for the phone's camera app are reported once a scan to the crash board,
///   with the reason and the preset (scan_trouble.dart).
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_language.dart';
import '../crash_reports.dart';
import 'camera_luma.dart';
import 'live_text_reader.dart';
import 'scan_coach.dart';
import 'scan_copy_language.dart';
import 'scan_document_profile.dart';
import 'scan_frame_loop.dart';
import 'scan_frame_processor.dart';
import 'scan_guidance_view.dart';
import 'scan_photo.dart';
import 'scan_text_reading.dart';
import 'scan_trouble.dart';

class GuidedScanResult {
  const GuidedScanResult.captured(this.file, {this.liveReading, this.bytes})
      : useLegacyCamera = false;
  const GuidedScanResult.fallback()
      : file = null, useLegacyCamera = true, liveReading = null, bytes = null;

  final XFile? file;
  final bool useLegacyCamera;

  /// The photo made ready for the portal (upright, bounded, no metadata),
  /// or null when the camera's own file is to be sent as it is.
  final Uint8List? bytes;

  /// What was read on the phone while the page was in view, checked and
  /// bounded (scan_text_reading.dart), for this capture only. Null without a
  /// text reader.
  final Map<String, Object>? liveReading;
}

/// Resolutions tried in turn when the Android camera opens. The still photo
/// is taken at the first that opens; CameraX keeps the preview and the image
/// stream at the screen's size or below while the photo is at the sensor's
/// maximum (a photo at its maximum is only guaranteed beside streams of
/// preview size).
const guidedScanResolutions = [
  ResolutionPreset.max, ResolutionPreset.veryHigh, ResolutionPreset.high,
];

/// An iPhone too old for the native scanner keeps 1080p: there the image
/// stream would follow the photo to the sensor's maximum.
const guidedScanIosResolutions = [ResolutionPreset.veryHigh, ResolutionPreset.high];

/// The presets the camera opens at, in turn. Once the Android image stream
/// has failed at [ResolutionPreset.max] in this scan, the next one down first:
/// its stills are 1080p, but its frames keep automatic capture; then the
/// maximum again, for the shutter alone, if it does not open.
List<ResolutionPreset> guidedScanPresets({required bool android, bool streamFailedAtMax = false}) {
  if (!android) return guidedScanIosResolutions;
  if (!streamFailedAtMax) return guidedScanResolutions;
  return const [ResolutionPreset.veryHigh, ResolutionPreset.max];
}

/// The longest a frame asked for may take to come before the image stream
/// counts as failed. A frame is normally in within a few hundred
/// milliseconds; Android's stream sends none at all when its camera side
/// failed (startImageStream has returned by then, and says nothing).
const guidedScanFrameWait = Duration(seconds: 4);

/// The longest a frame's work may take before it is done inline instead.
const guidedScanWorkerTimeout = Duration(seconds: 2);

/// How often a frame is asked for while the page is looked for.
const guidedScanFrameInterval = Duration(milliseconds: 250);

/// The longest the camera waits to focus on the page before the photo.
const guidedScanFocusWait = Duration(milliseconds: 1500);

/// The point to focus on, in the full camera image's upright normalized
/// coordinates: the middle of the page found, else the middle of the view.
Offset guidedScanFocusPoint(Rect? page, {required int sensorWidth, required int sensorHeight, double? viewportAspect}) {
  final region = visiblePreviewRegion(sensorWidth, sensorHeight, viewportAspect);
  final centre = page?.center ?? const Offset(0.5, 0.5);
  return Offset(
    (region.left + centre.dx.clamp(0.0, 1.0) * region.width).clamp(0.0, 1.0),
    (region.top + centre.dy.clamp(0.0, 1.0) * region.height).clamp(0.0, 1.0),
  );
}

class GuidedScanPage extends StatefulWidget {
  const GuidedScanPage({super.key, required this.profile,
      @visibleForTesting this.android, @visibleForTesting this.reportTrouble});

  final GuidedDocumentProfile profile;

  /// Whether this is the Android camera: the phone's own platform, unless a
  /// test runs the Android screen on another (guided_scan_page_test.dart).
  final bool? android;

  /// Where the scanner's troubles go (scan_trouble.dart): the crash board,
  /// unless a test listens instead.
  final void Function(String message)? reportTrouble;

  @override
  State<GuidedScanPage> createState() => _GuidedScanPageState();
}

class _GuidedScanPageState extends State<GuidedScanPage>
    with WidgetsBindingObserver {
  CameraController? _camera;
  Future<void>? _pendingDispose;
  Future<void>? _pendingStart;
  // Only the Android app carries a text model; an iPhone that falls back to
  // this camera captures on steadiness alone, as before.
  bool get _android => widget.android ?? Platform.isAndroid;
  late final GuidedFrameLoop _loop =
      GuidedFrameLoop(widget.profile, canReadText: _android);
  final _textChannel = LiveTextChannel();
  final _photos = ScanPhotoChannel();
  // One instruction at a time, held long enough to be read.
  final _coach = ScanGuidanceCoach();
  ScanGuidance? _guidance;
  final _inline = ScanFrameProcessor();
  ScanFrameWorker? _worker;
  bool _workerStarting = false;

  int _cameraGeneration = 0;
  bool _disposed = false;
  static const _previewLeaveWait = Duration(milliseconds: 150);
  int _sensorOrientation = 90;
  bool _initializing = false;
  bool _appActive = true;
  bool _closing = false;
  bool _busy = false;
  bool _preparing = false;
  bool _cameraFailed = false;
  bool _streamSupported = false;
  bool _autoEnabled = true;
  bool _torch = false;
  String? _captureError;
  double? _viewportAspect;

  // One frame at a time: asked for, received, worked on, then the next.
  bool _framePending = false;
  bool _frameInFlight = false;
  DateTime? _frameAskedAt;
  Timer? _nextFrame;
  Future<void>? _stopping;
  // Each ask is numbered, and watched until its frame is in.
  int _frameAsks = 0;
  Timer? _frameWatch;
  int _framesFromCamera = 0;
  // Asks in a row whose frame did not come, once frames have come.
  int _lateAsks = 0;

  // How the camera opened, for the crash board; once the image stream has
  // failed at the maximum, the camera opens a step lower for this scan.
  ResolutionPreset? _openedPreset;
  String? _openedNote;
  bool _streamFailedAtMax = false;
  String? _cameraFailure;
  final _reported = <ScanTrouble>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_startWorker());
    _scheduleCameraStart();
  }

  Future<void> _startWorker() async {
    if (_workerStarting || _worker != null) return;
    _workerStarting = true;
    final worker = await ScanFrameWorker.start();
    _workerStarting = false;
    if (!mounted || _closing) {
      worker?.close();
      return;
    }
    _worker = worker;
  }

  void _scheduleCameraStart() {
    if (_initializing || _closing) return;
    final start = _startCamera();
    _pendingStart = start;
    unawaited(start.whenComplete(() {
      if (identical(_pendingStart, start)) _pendingStart = null;
    }));
  }

  /// Disposes [camera] once its preview has left the screen. The preview
  /// rebuilds whenever the controller's value changes (a photo taken), and a
  /// frame drawn after the controller is disposed asks it for its preview and
  /// throws ("buildPreview() was called on a disposed CameraController": the
  /// guided_scan_page_test.dart run showed it right after the photo). So the
  /// page is drawn once without it first, for at most [_previewLeaveWait]; in
  /// the background no frame is drawn, and none waits.
  Future<void> _disposeCamera(CameraController camera, {bool redraw = true}) async {
    if (redraw && mounted && !_disposed) {
      setState(() {});
      try {
        await WidgetsBinding.instance.endOfFrame.timeout(_previewLeaveWait);
      } catch (_) {
        // No frame came (the app is in the background): nothing is drawn.
      }
    }
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

  /// The steadiness hold, the reading and the instruction all start over.
  void _resetGuidance() {
    _loop.reset();
    _coach.reset();
    _guidance = null;
  }

  void _forgetFrames() {
    _nextFrame?.cancel();
    _nextFrame = null;
    _frameWatch?.cancel();
    _frameWatch = null;
    _framePending = false;
    _worker?.forget();
    _inline.forget();
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
      _resetGuidance();
      _forgetFrames();
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
    // The presets that did not open, each with its error's name.
    final failed = <(ResolutionPreset, String)>[];
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
      ResolutionPreset? openedAt;

      // The still photo is taken at the resolution the camera opens at, so
      // the sensor's full 4:3 frame first. CameraX bounds the preview and
      // the image stream to the screen's size or below meanwhile.
      for (final preset in guidedScanPresets(android: _android, streamFailedAtMax: _streamFailedAtMax)) {
        opened = CameraController(
          description, preset,
          enableAudio: false,
          imageFormatGroup: _android
              ? ImageFormatGroup.yuv420
              : ImageFormatGroup.bgra8888,
        );
        try {
          await opened.initialize();
          openedAt = preset;
          break;
        } catch (error) {
          lastError = error;
          failed.add((preset, scanErrorName(error)));
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
      _openedPreset = openedAt;
      _openedNote = scanCameraNote(openedAt!, opened.value.previewSize, skipped: failed);
      _framesFromCamera = 0;
      _lateAsks = 0;
      _sensorOrientation = description.sensorOrientation == 270 ? 270 : 90;
      try {
        await opened.lockCaptureOrientation(DeviceOrientation.portraitUp);
      } catch (_) {
        // Rotation metadata still travels with the JPEG on older hardware.
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
          // Assumed until the first ask fails: a few camera implementations
          // take still photos but stream no frames.
          _streamSupported = true;
        });
      }
      _resetGuidance();
      _forgetFrames();
      if (_autoEnabled) unawaited(_askForFrame());
    } catch (error) {
      if (opened != null && _camera != opened) {
        await _disposeCamera(opened);
      }
      if (mounted && !_closing) {
        // Not a camera taken away by a pause: the next resume reopens it.
        if (_appActive && generation == _cameraGeneration) {
          final why = _cameraFailure = scanOpenFailure(error, failed);
          _report(ScanTrouble.cameraFailed, why);
        }
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

  bool get _wantsFrames => mounted && !_closing && !_busy && _appActive &&
      _autoEnabled && _streamSupported && _camera != null;

  /// One frame: the stream is started for it and stopped as soon as it is in.
  Future<void> _askForFrame() async {
    _nextFrame = null;
    await _stopping;
    final camera = _camera;
    if (!_wantsFrames || camera == null || !camera.value.isInitialized ||
        camera.value.isStreamingImages || _frameInFlight || _framePending) {
      return;
    }
    final generation = _cameraGeneration;
    final ask = ++_frameAsks;
    _framePending = true;
    _frameAskedAt = DateTime.now();
    // Watched from before the stream starts: a frame that comes at once must
    // not leave a watch behind for a later ask.
    _frameWatch?.cancel();
    _frameWatch = Timer(guidedScanFrameWait, () => _frameLate(ask, generation));
    try {
      await camera.startImageStream((image) => _onFrame(image, generation));
    } catch (error) {
      if (ask == _frameAsks) {
        _framePending = false;
        _frameWatch?.cancel();
        _frameWatch = null;
      }
      // Still photos without an image stream: keep the shutter usable and
      // never fake "auto-ready".
      if (mounted && generation == _cameraGeneration && !_closing) {
        _streamFailed('startImageStream threw ${scanErrorName(error)}', generation);
      }
    }
  }

  /// The frame [ask] wanted did not come in [guidedScanFrameWait].
  void _frameLate(int ask, int generation) {
    if (ask != _frameAsks || !_framePending || generation != _cameraGeneration || !_wantsFrames) {
      return;
    }
    _frameWatch = null;
    _framePending = false;
    // A camera that has streamed: one frame slow on a busy phone, or lost
    // between two asks, is asked for again before the stream counts as stopped.
    final camera = _camera;
    if (_framesFromCamera > 0 && ++_lateAsks < 2 && camera != null) {
      _stopping = _stopImageStream(camera);
      _askForNextFrame();
      return;
    }
    _streamFailed(
        _framesFromCamera == 0
            ? 'no frame in ${guidedScanFrameWait.inSeconds} s'
            : 'frames stopped after $_framesFromCamera',
        generation);
  }

  /// The image stream failed ([reason]). At the sensor's maximum, before any
  /// frame came, the camera reopens once a step lower to keep automatic
  /// capture; otherwise the shutter alone stays.
  void _streamFailed(String reason, int generation) {
    if (!mounted || _closing || generation != _cameraGeneration) return;
    final camera = _camera;
    if (_android && !_busy && camera != null && _openedPreset == ResolutionPreset.max &&
        _framesFromCamera == 0 && !_streamFailedAtMax) {
      _streamFailedAtMax = true;
      _report(ScanTrouble.streamRetried, reason);
      _camera = null;
      _cameraGeneration++;
      _resetGuidance();
      _forgetFrames();
      setState(() => _streamSupported = false);
      _pendingDispose = _stopImageStream(camera).then((_) => _disposeCamera(camera));
      _scheduleCameraStart();
      return;
    }
    _autoCaptureLost(reason);
  }

  /// No automatic capture for the rest of this camera: the shutter alone,
  /// never a faked "auto-ready", and the reason on the crash board.
  void _autoCaptureLost(String reason) {
    _forgetFrames();
    final camera = _camera;
    if (camera != null) _stopping = _stopImageStream(camera);
    _report(ScanTrouble.autoCaptureLost, reason);
    if (mounted) setState(() => _streamSupported = false);
  }

  /// Sends [trouble] to the crash board, at most once a scan.
  void _report(ScanTrouble trouble, String reason) {
    if (!_reported.add(trouble)) return;
    final message = scanTroubleReport(trouble, reason,
        camera: trouble == ScanTrouble.cameraFailed || trouble == ScanTrouble.cameraApp ? null : _openedNote);
    final listener = widget.reportTrouble;
    if (listener != null) {
      listener(message);
    } else {
      unawaited(CrashReports.instance.report(message, where: scanTroubleWhere));
    }
  }

  void _onFrame(CameraImage image, int generation) {
    // A frame from a camera since closed, or one nobody asked for.
    if (generation != _cameraGeneration || !_framePending || _frameInFlight) return;
    _framePending = false;
    _frameWatch?.cancel();
    _frameWatch = null;
    _framesFromCamera++;
    _lateAsks = 0;
    final camera = _camera;
    if (camera != null) _stopping = _stopImageStream(camera);
    if (!_wantsFrames) return;
    final plane = ScanLumaPlane.fromCameraImage(image);
    if (plane == null) {
      // Unsupported preview formats must never auto-trigger.
      _autoCaptureLost(ScanLumaPlane.whyUnreadable(image) ?? 'frame not readable');
      return;
    }
    _frameInFlight = true;
    final at = DateTime.now();
    unawaited(_workOn(plane, at, generation).whenComplete(() {
      _frameInFlight = false;
      _askForNextFrame();
    }));
  }

  void _askForNextFrame() {
    if (!_wantsFrames) return;
    final asked = _frameAskedAt ?? DateTime.now();
    final wait = guidedScanFrameInterval - DateTime.now().difference(asked);
    _nextFrame?.cancel();
    _nextFrame = Timer(wait.isNegative ? Duration.zero : wait, () => unawaited(_askForFrame()));
  }

  Future<void> _workOn(ScanLumaPlane plane, DateTime at, int generation) async {
    final readDue = _android && _loop.textReadDue(at);
    final job = ScanFrameJob(
      plane: plane,
      profile: widget.profile,
      viewportAspect: _viewportAspect,
      sensorOrientation: _sensorOrientation,
      readText: readDue,
      readWholeView: readDue,
      turns: _loop.reading.turnPolicy,
    );
    ScanFrameWork? work;
    final worker = _worker;
    try {
      work = worker != null
          ? await worker.process(job).timeout(guidedScanWorkerTimeout)
          : _inline.process(job);
    } catch (_) {
      // A worker that failed: this and later frames are worked inline.
      if (identical(_worker, worker)) {
        _worker = null;
        worker?.close();
      }
      work = _inline.process(job);
    }
    if (!mounted || _closing || _busy || generation != _cameraGeneration || !_autoEnabled) return;
    if (work == null) {
      _autoCaptureLost('frame not sampled (${plane.layout})');
      return;
    }
    final now = DateTime.now();
    final capture = _loop.observe(work.analysis, now, aspect: work.aspect);
    final crop = work.textCrop, luma = work.textLuma;
    if (crop != null && luma != null) _readText(crop, luma, wholeView: work.wholeView, now: now);
    _guidance = _coach.update(
      scanGuidanceFor(work.analysis, _loop.readingStatus,
          profile: widget.profile, aspect: work.aspect,
          textPage: work.analysis.bounds == null && _loop.textSeenWhole(now)),
      now,
    ).line;
    setState(() {});
    if (capture && !_busy) unawaited(_takePhoto(automatic: true));
  }

  /// Hands the page to ML Kit, one read at a time. The frames never wait
  /// for it.
  void _readText(LiveTextCrop crop, Uint8List luma, {required bool wholeView, required DateTime now}) {
    _loop.textStarted(now, wholeView: wholeView);
    final epoch = _loop.textEpoch;
    final started = DateTime.now();
    unawaited(_textChannel.read(luma, crop).then((result) {
      if (!mounted || _closing) return;
      _loop.textFinished(result, crop,
          epoch: epoch, took: DateTime.now().difference(started),
          wholeView: wholeView, now: DateTime.now(), capturing: _busy);
    }));
  }

  /// The camera focuses on the page before the photo, for at most
  /// [guidedScanFocusWait]. A camera that cannot focus on a point (a fixed
  /// lens) takes the photo where it is.
  Future<void> _focusOnPage(CameraController camera) async {
    final frame = camera.value.previewSize;
    if (frame == null) return;
    final point = guidedScanFocusPoint(_loop.analysis?.bounds,
        sensorWidth: frame.width.round(), sensorHeight: frame.height.round(),
        viewportAspect: _viewportAspect);
    try {
      await camera.setFocusPoint(point).timeout(guidedScanFocusWait);
    } catch (_) {
      // Not every camera focuses on a point; the photo is taken anyway.
    }
  }

  Future<void> _takePhoto({bool automatic = false}) async {
    final camera = _camera;
    if (_busy || camera == null || !camera.value.isInitialized) return;
    Future<XFile>? capture;
    XFile? capturedPhoto;
    var delivered = false;
    _nextFrame?.cancel();
    _nextFrame = null;
    _frameWatch?.cancel();
    _frameWatch = null;
    setState(() {
      _busy = true;
      _captureError = null;
      _guidance = _coach.update(const ScanGuidance(scanTakingPhoto, ScanOutlineState.holding),
          DateTime.now(), immediate: true).line;
    });
    try {
      // The photo is taken with no frames streaming.
      if (camera.value.isStreamingImages) {
        await camera.stopImageStream().timeout(const Duration(seconds: 3));
      }
      await _stopping?.timeout(const Duration(seconds: 3), onTimeout: () {});
      _framePending = false;
      await _focusOnPage(camera);
      if (!mounted || _closing || _camera != camera) return;
      capture = camera.takePicture();
      var photo = await capture.timeout(
        const Duration(seconds: 15),
      );
      capturedPhoto = photo;
      if (!mounted || _closing) {
        if (identical(_camera, camera)) _camera = null;
        await _disposeCamera(camera);
        return;
      }
      // Android: a second still while the page is still held, a third when
      // neither is sharp, and the sharpest is the one sent (scan_photo.dart).
      if (_android) {
        photo = await _sharpestStill(camera, photo);
        capturedPhoto = photo;
        if (!mounted || _closing) {
          if (identical(_camera, camera)) _camera = null;
          await _disposeCamera(camera);
          return;
        }
      }
      // One light touch as the shot is in (never during the exposure, where
      // the motor would shake the picture), and a calm word.
      HapticFeedback.lightImpact();
      _guidance = _coach.update(scanGuidanceDone, DateTime.now()).line;
      _closing = true;
      _camera = null;
      _cameraGeneration++;
      final liveReading = _android
          ? _loop.liveReading(automatic: automatic, referenceYear: DateTime.now().year)
          : null;
      await _disposeCamera(camera);
      if (!mounted) return;
      // Made upright and bounded on the phone; the camera's own file when
      // that cannot be done.
      setState(() => _preparing = true);
      final ready = _android ? await _photos.prepare(photo.path) : null;
      if (!mounted) return;
      Navigator.of(context).pop(GuidedScanResult.captured(photo,
          liveReading: liveReading, bytes: ready?.bytes));
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
      _resetGuidance();
      _forgetFrames();
      setState(() {
        _busy = false;
        _captureError = 'The photo was not taken. Hold still and try again.';
      });
      // A pause can detach the controller while takePicture is in flight.
      // If resume already happened, start a fresh controller now instead of
      // leaving the page permanently on "Opening camera…".
      if (captureTimedOut || _camera != camera || !_appActive) {
        await _disposeCamera(camera);
        if (_appActive && mounted && !_closing) _scheduleCameraStart();
      } else if (camera.value.isInitialized && _autoEnabled && _streamSupported) {
        unawaited(_askForFrame());
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

  /// The sharpest of up to [scanStillsAtMost] stills of the page, the first
  /// among them [first]: a hand that moved as the shutter went, the press of
  /// the shutter itself, or focus that settled a moment late each blur one
  /// still, rarely two in a row. The others are deleted. A phone that cannot
  /// measure a still, or whose camera fails on the next, keeps what it has.
  Future<XFile> _sharpestStill(CameraController camera, XFile first) async {
    final stills = <XFile>[first];
    final scores = <double?>[await _photos.sharpness(first.path)];
    while (wantsAnotherStill(scores) && mounted && !_closing && _camera == camera &&
        camera.value.isInitialized) {
      XFile next;
      try {
        next = await camera.takePicture().timeout(const Duration(seconds: 8));
      } catch (_) {
        break;
      }
      stills.add(next);
      scores.add(await _photos.sharpness(next.path));
    }
    final keep = bestStill(scores).clamp(0, stills.length - 1);
    for (var i = 0; i < stills.length; i++) {
      if (i == keep) continue;
      try {
        await File(stills[i].path).delete();
      } catch (_) {
        // The camera's cache directory is cleared with the app's.
      }
    }
    return stills[keep];
  }

  Future<void> _useOtherCamera() async {
    if (_busy || _closing) return;
    // The phone's camera app has no automatic capture: the board says why
    // the student is there.
    _report(ScanTrouble.cameraApp, _cameraFailure ?? 'not known');
    _closing = true;
    _cameraGeneration++;
    _forgetFrames();
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
    final enabling = !_autoEnabled;
    _resetGuidance();
    _forgetFrames();
    setState(() => _autoEnabled = enabling);
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) return;
    if (!enabling) {
      // No frames are asked for while auto-capture is off.
      await _stopImageStream(camera);
      return;
    }
    unawaited(_askForFrame());
  }

  @override
  void dispose() {
    _disposed = true;
    _closing = true;
    _cameraGeneration++;
    _nextFrame?.cancel();
    _frameWatch?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    final camera = _camera;
    _camera = null;
    if (camera != null) unawaited(_disposeCamera(camera, redraw: false));
    _worker?.close();
    unawaited(_textChannel.close());
    super.dispose();
  }

  /// The whole photo on screen, at its own aspect (letterboxed), with the
  /// guide drawn over it: what the guide frames is what is taken.
  Widget _cameraPreview(CameraController camera, ScanOutlineState state) {
    return LayoutBuilder(
      builder: (context, bounds) {
        final size = camera.value.previewSize;
        if (size == null || size.width <= 0 || size.height <= 0 ||
            bounds.maxWidth <= 0 || bounds.maxHeight <= 0) {
          return const SizedBox.expand();
        }
        // The camera buffer is landscape in portrait orientation.
        final width = math.min(size.width, size.height);
        final height = math.max(size.width, size.height);
        final scale = math.min(bounds.maxWidth / width, bounds.maxHeight / height);
        _viewportAspect = width / height;
        final analysis = _loop.analysis;
        return Center(
          child: SizedBox(
            width: width * scale,
            height: height * scale,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CameraPreview(camera),
                // Painted in the preview's normalized coordinates, the same
                // ones the frame analysis uses.
                CustomPaint(
                  painter: ScanGuidePainter(
                    guide: analysis?.bounds ?? widget.profile.guide(_viewportAspect ?? 0.75),
                    state: state,
                    zones: widget.profile.zones,
                    corners: analysis?.bounds != null ? analysis?.corners : null,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // What the scanner says, in the student's language.
  static const _close =
      Words('Close scanner', 'Fermer le scanner', 'إغلاق الماسح الضوئي');
  static const _scanTitle = Words(
      'Scan {title}', 'Scanner\u00A0: {title}', 'المسح الضوئي: {title}');
  static const _lightOff =
      Words('Turn light off', 'Éteindre la lampe', 'إطفاء الضوء');
  static const _lightOn =
      Words('Turn light on', 'Allumer la lampe', 'تشغيل الضوء');
  static const _autoOn = Words('Auto on', 'Auto activé', 'تلقائي: مفعّل');
  static const _autoOff =
      Words('Auto off', 'Auto désactivé', 'تلقائي: متوقف');
  static const _takePhotoLabel = Words('Take photo manually',
      'Prendre la photo manuellement', 'التقاط الصورة يدويًا');
  static const _footnote = Words(
      'Automatic capture once the right paper is clear and steady · manual '
          'capture always available',
      'Capture automatique dès que le bon document est net et stable · '
          'capture manuelle toujours possible',
      'التقاط تلقائي حين تكون الوثيقة الصحيحة واضحة وثابتة · الالتقاط اليدوي '
          'متاح دائمًا');
  static const _cameraApp =
      Words('Camera app', 'Appli Appareil photo', 'تطبيق الكاميرا');
  static const _cameraAppHint = Words(
      'Opens your phone\'s camera app instead of this scanner',
      'Ouvre l’application Appareil photo du téléphone à la place de ce scanner',
      'يفتح تطبيق الكاميرا في هاتفك بدل هذا الماسح');

  /// What the panel says now: the photo's own moments first, then the
  /// camera's, then the live guidance for the frame (scan_coach.dart).
  ScanGuidance _shownGuidance(bool cameraWorking) {
    const adjusting = ScanOutlineState.adjusting, searching = ScanOutlineState.searching;
    final error = _captureError;
    if (error != null) return ScanGuidance(ScanTextCopy('Try again', error, 'Try again.'), adjusting);
    if (_preparing) return scanGuidanceDone;
    if (_busy) return _guidance ?? const ScanGuidance(scanTakingPhoto, ScanOutlineState.holding);
    if (_cameraFailed) {
      return const ScanGuidance(
          ScanTextCopy('Camera unavailable', 'This camera could not open.', 'Camera unavailable.'), searching);
    }
    if (!cameraWorking) return const ScanGuidance(ScanTextCopy('Opening camera…', '', 'Opening camera…'), searching);
    if (!_autoEnabled || !_streamSupported) {
      return const ScanGuidance(
          ScanTextCopy('Tap the shutter', 'Take the photo when the whole page is clear.', 'Tap the shutter.'), searching);
    }
    return _guidance ??
        scanGuidanceFor(null, null, profile: widget.profile, aspect: _viewportAspect ?? 0.75);
  }

  @override
  Widget build(BuildContext context) {
    final language = AppLanguageScope.of(context);
    return Directionality(
      textDirection: language.direction,
      child: _page(context, language),
    );
  }

  Widget _page(BuildContext context, AppLanguage language) {
    final camera = _camera;
    final cameraWorking = camera?.value.isInitialized == true;
    final shown = _shownGuidance(cameraWorking);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (cameraWorking)
              _cameraPreview(camera!, shown.state)
            else
              const Center(
                child: Icon(Icons.document_scanner_outlined,
                    size: 80, color: Colors.white30),
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
                          tooltip: _close.of(language),
                          onPressed: _busy ? null
                            : () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close, color: Colors.white),
                        ),
                        Expanded(
                          child: Text(
                            _scanTitle
                                .of(language)
                                .replaceFirst('{title}', widget.profile.title),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white, fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: (_torch ? _lightOff : _lightOn).of(language),
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
                    if (widget.profile.pagesHintIn(language).isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        widget.profile.pagesHintIn(language),
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
                  ScanGuidancePanel(
                    copy: scanCopyIn(shown.copy, language),
                    state: shown.state,
                    progress: _autoEnabled && _streamSupported ? _loop.progress : null,
                    busy: _busy && !_preparing,
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
                        label: Text(
                            (_autoEnabled ? _autoOn : _autoOff).of(language)),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                        ),
                      ),
                      GestureDetector(
                        onTap: cameraWorking && !_busy ? _takePhoto : null,
                        child: Semantics(
                          button: true,
                          label: _takePhotoLabel.of(language),
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
                      // The phone's own camera app sounds its shutter and is
                      // not this scanner, so it is never opened by itself and
                      // never offered while this camera works: only when this
                      // camera cannot open, under a name that says what it is.
                      if (_cameraFailed)
                        Semantics(
                          hint: _cameraAppHint.of(language),
                          child: TextButton(
                            onPressed: _busy ? null : _useOtherCamera,
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white,
                            ),
                            child: Text(_cameraApp.of(language)),
                          ),
                        )
                      else
                        const SizedBox(width: 96),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _footnote.of(language),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
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
