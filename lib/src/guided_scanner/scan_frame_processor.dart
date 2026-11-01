/// The pixel work on one preview frame, off the UI isolate (Android's guided
/// scanner, guided_scan_page.dart).
///
/// A frame's luminance is sampled into the small grid, the page is looked for
/// in it (scan_guidance.dart), and, when a read of the text is due, the page's
/// crop is copied out for ML Kit (live_text_reader.dart). Before 31 Oct 2026
/// all of it ran on the UI isolate, between the frames the preview had to
/// draw; on a cheap phone it now runs on a worker isolate, one frame at a
/// time, and a frame that arrives while one is still being worked on is not
/// read at all. [ScanFrameProcessor] is the work itself, the same inline and
/// on the worker, so the tests run exactly what the phone runs.
library;

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui';

import 'camera_luma.dart';
import 'live_text_reader.dart';
import 'scan_document_profile.dart';
import 'scan_guidance.dart';
import 'scan_text_reading.dart';

/// What the processor is asked about one frame.
class ScanFrameJob {
  const ScanFrameJob({
    required this.plane,
    required this.profile,
    this.viewportAspect,
    this.sensorOrientation = 90,
    this.readText = false,
    this.readWholeView = false,
    this.turns = const ScanTextTurnPolicy.fixed(0),
  });

  final ScanLumaPlane plane;
  final GuidedDocumentProfile profile;

  /// The preview's width over its height, upright. Null: the whole frame is
  /// on screen, at its own aspect.
  final double? viewportAspect;
  final int sensorOrientation;

  /// A read of the text is due: copy the page's crop out of this frame.
  final bool readText;

  /// With no outline found, read the whole view instead (the page's text is
  /// what finds a white page on a white desk).
  final bool readWholeView;
  final ScanTextTurnPolicy turns;
}

/// What came of one frame.
class ScanFrameWork {
  const ScanFrameWork({
    required this.analysis,
    required this.aspect,
    this.textCrop,
    this.textLuma,
    this.wholeView = false,
    required this.elapsed,
  });

  final ScanFrameAnalysis analysis;

  /// The aspect the frame was analysed at (the guide's).
  final double aspect;

  /// The crop to read, and its luminance, when a read was due and possible.
  final LiveTextCrop? textCrop;
  final Uint8List? textLuma;

  /// The crop is the whole view, read because no outline was found.
  final bool wholeView;

  /// How long the work took, for the tests and diagnostics.
  final Duration elapsed;
}

/// Too much movement between two frames for the whole view to be worth reading.
const _wholeViewMotionLimit = 14.0;

/// The region a page's text must lie in to be found without an outline: the
/// view less a margin for the page's own, so text that reaches the frame's
/// edge, from a page held so close its edges are out of view, counts as
/// running off it (the crop read is this region and 10% round it).
const scanWholeViewRegion = Rect.fromLTRB(0.06, 0.06, 0.94, 0.94);

class ScanFrameProcessor {
  final _analyzer = const ScanFrameAnalyzer();
  ScanLumaGrid? _previous;

  /// Forget the last frame (the camera restarted, the page changed hands).
  void forget() => _previous = null;

  /// The work on one frame. Null when the frame's layout cannot be read.
  ScanFrameWork? process(ScanFrameJob job) {
    final started = DateTime.now();
    final plane = job.plane;
    final grid = sampleScanLuma(plane,
        viewportAspect: job.viewportAspect, sensorOrientation: job.sensorOrientation);
    if (grid == null) return null;
    final landscape = plane.width > plane.height;
    final aspect = job.viewportAspect ??
        (landscape ? plane.height / plane.width : plane.width / plane.height);
    final kind = switch (job.profile.layout) {
      GuidedScanLayout.passport => GuidedDocumentKind.passport,
      GuidedScanLayout.card => GuidedDocumentKind.idCard,
      _ => GuidedDocumentKind.page,
    };
    final analysis = _analyzer.analyse(grid, kind,
        previous: _previous, profile: job.profile, viewportAspect: aspect);
    _previous = grid;
    LiveTextCrop? crop;
    Uint8List? luma;
    var wholeView = false;
    if (job.readText && !plane.bgra) {
      var region = analysis.bounds;
      if (region == null && job.readWholeView &&
          analysis.motion.isFinite && analysis.motion <= _wholeViewMotionLimit) {
        region = scanWholeViewRegion;
        wholeView = true;
      }
      if (region != null) {
        crop = LiveTextCrop.forPage(region,
            sensorWidth: plane.width, sensorHeight: plane.height,
            viewportAspect: job.viewportAspect, turns: job.turns,
            sensorOrientation: job.sensorOrientation);
        luma = crop?.extract(plane.bytes, rowStride: plane.rowStride, pixelStride: plane.pixelStride);
        if (luma == null) {
          crop = null;
          wholeView = false;
        }
      } else {
        wholeView = false;
      }
    }
    return ScanFrameWork(
      analysis: analysis, aspect: aspect,
      textCrop: crop, textLuma: luma, wholeView: wholeView,
      elapsed: DateTime.now().difference(started),
    );
  }
}

/// [ScanFrameProcessor] on its own isolate. One frame at a time: the page
/// sends the next only once this one is answered.
class ScanFrameWorker {
  ScanFrameWorker._(this._isolate, this._commands, this._replies);

  final Isolate _isolate;
  final SendPort _commands;
  final ReceivePort _replies;
  final _pending = <int, Completer<ScanFrameWork?>>{};
  int _next = 0;
  bool _closed = false;

  /// Null when an isolate cannot be started; the page then works inline.
  static Future<ScanFrameWorker?> start() async {
    final replies = ReceivePort();
    try {
      final isolate = await Isolate.spawn(_workerMain, replies.sendPort, debugName: 'scan-frames');
      final ready = Completer<SendPort>();
      ScanFrameWorker? worker;
      replies.listen((message) {
        if (message is SendPort && !ready.isCompleted) {
          ready.complete(message);
        } else if (message is (int, ScanFrameWork?)) {
          worker?._pending.remove(message.$1)?.complete(message.$2);
        } else if (message is (int, Object)) {
          worker?._pending.remove(message.$1)?.completeError(StateError('scan frame failed'));
        }
      });
      final commands = await ready.future.timeout(const Duration(seconds: 3));
      worker = ScanFrameWorker._(isolate, commands, replies);
      return worker;
    } catch (_) {
      replies.close();
      return null;
    }
  }

  Future<ScanFrameWork?> process(ScanFrameJob job) {
    if (_closed) return Future.error(StateError('closed'));
    final id = _next++;
    final completer = Completer<ScanFrameWork?>();
    _pending[id] = completer;
    _commands.send((id, job));
    return completer.future;
  }

  void forget() {
    if (!_closed) _commands.send('forget');
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _commands.send('close');
    _isolate.kill(priority: Isolate.beforeNextEvent);
    _replies.close();
    for (final pending in _pending.values) {
      pending.completeError(StateError('closed'));
    }
    _pending.clear();
  }
}

void _workerMain(SendPort replies) {
  final commands = ReceivePort();
  replies.send(commands.sendPort);
  final processor = ScanFrameProcessor();
  commands.listen((message) {
    if (message == 'forget') {
      processor.forget();
    } else if (message == 'close') {
      commands.close();
    } else if (message is (int, ScanFrameJob)) {
      try {
        replies.send((message.$1, processor.process(message.$2)));
      } catch (error) {
        replies.send((message.$1, error.toString()));
      }
    }
  });
}
