/// What each analysed preview frame means for the screen and the shutter, on
/// the Android guided camera (guided_scan_page.dart): the steadiness hold,
/// the live reading and the automatic shutter, frame by frame. Pure and
/// clock-free, so the tests replay frames through exactly what the phone runs.
///
/// The automatic shutter's rule is shared with the iPhone
/// ([ScanAutoShutter], scan_text_reading.dart); what is Android's own is
/// what counts as a page in view. Before 31 Oct 2026 that was only an outline
/// found where the guide asked for one, so on the owner's Android phone the
/// camera waited for the button. It is now the outline wherever the page is
/// held (scan_page_segment.dart), or, with no outline at all (a white page on
/// a white desk, a page held in the hand), the page's printed text read whole
/// in the view by ML Kit: three rows of text, a passport's or a card's lines,
/// or a card's number, none of it running off the frame.
library;

import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'live_text_reader.dart';
import 'scan_coach.dart';
import 'scan_document_profile.dart';
import 'scan_frame_processor.dart';
import 'scan_guidance.dart';
import 'scan_text_reading.dart';

class GuidedFrameLoop {
  GuidedFrameLoop(this.profile, {required bool canReadText})
      : reading = ScanTextReadingSession.forProfile(profile) {
    if (!canReadText) reading.markReaderUnavailable();
  }

  final GuidedDocumentProfile profile;
  final ScanTextReadingSession reading;
  final _gate = ScanAutoCaptureGate();
  final _shutter = ScanAutoShutter();

  static const textInterval = Duration(milliseconds: 300);

  /// How long the page's text, read whole without an outline, keeps the
  /// page in view: a read takes up to a second on a cheap phone.
  static const textSightingHold = Duration(milliseconds: 1800);

  /// Frames this still, for this long, hold a page found by its text alone.
  static const quietMotion = 10.0;
  static const quietHold = Duration(milliseconds: 650);

  ScanFrameAnalysis? analysis;
  ScanTextGateStatus? readingStatus;
  double progress = 0;
  bool captureMatched = false;

  int _textEpoch = 0;
  bool _textBusy = false;
  bool _wholeViewInFlight = false;
  DateTime? _lastTextRead;
  Duration _lastTextDuration = Duration.zero;
  DateTime? _textWholeAt;
  DateTime? _quietSince;
  int _quietFrames = 0;
  Rect? _lastReadingPage;

  int get textEpoch => _textEpoch;
  bool get textBusy => _textBusy;

  /// The page was found by its text alone, the last time it was read.
  bool textSeenWhole(DateTime now) {
    final at = _textWholeAt;
    return at != null && now.difference(at) <= textSightingHold;
  }

  /// A read of the text is due on the next frame.
  bool textReadDue(DateTime now) {
    if (_textBusy || reading.readerUnavailable) return false;
    final last = _lastTextRead;
    if (last == null) return true;
    final backoff = _lastTextDuration * 1.5;
    final interval = backoff > textInterval ? backoff : textInterval;
    return now.difference(last) >= interval;
  }

  /// One analysed frame. True when the photo is to be taken now. `aspect`:
  /// the view's width over its height, for telling a page held at a slant.
  bool observe(ScanFrameAnalysis frame, DateTime now, {double aspect = 0.75}) {
    analysis = frame;
    final outline = frame.bounds;
    final textPage = outline == null && textSeenWhole(now);
    // The reading belongs to one page: it starts over when the page has been
    // gone a moment or another outline takes its place. A page found by its
    // text is the whole view, and so is one whose whole-view read is on its
    // way (on a slow phone that read alone outlasts the page-loss reset).
    // Between an outline and the whole view the page stays the one last
    // outlined: a page found by its text, which an outline sometimes frames
    // for a frame or two, is not another page.
    final viewMode = textPage || _wholeViewInFlight;
    final readingPage = outline ?? (viewMode ? _lastReadingPage ?? scanWholeViewRegion : null);
    if (readingPage != null) _lastReadingPage = readingPage;
    if (reading.observePage(readingPage, now)) restartReading();
    final bool steady;
    if (outline != null) {
      steady = _gate.observe(frame, now);
      _quietSince = null;
      _quietFrames = 0;
    } else {
      _gate.observe(frame, now);
      steady = textPage && _quiet(frame, now);
    }
    final status = reading.status(glare: frame.hint == ScanHint.reduceGlare);
    readingStatus = status;
    final hold = outline != null ? _gate.progress : _quietProgress(now);
    progress = status.allowsCapture ? hold : math.min(hold, 0.85);
    // Taken with no tap: steady and read, steady for a moment, or in view
    // long enough; shadow, glare, dim light or a phone held at a slant get a
    // moment to be fixed first, while the screen says how (scan_coach.dart);
    // the wrong paper, or the wrong side of a card, is never taken.
    final page = steady
        ? ScanShutterPage.steady
        : outline != null || textPage ? ScanShutterPage.inView : ScanShutterPage.missing;
    final lightingGood = frame.hint != ScanHint.brighten && frame.hint != ScanHint.reduceGlare &&
        !frame.shadow && scanPageHeldFlat(frame.corners, aspect);
    if (_shutter.observe(page, now, reading: status, kind: reading.kind, lightingGood: lightingGood)) {
      captureMatched = status.passed;
      return true;
    }
    return false;
  }

  bool _quiet(ScanFrameAnalysis frame, DateTime now) {
    if (!frame.motion.isFinite || frame.motion > quietMotion) {
      _quietSince = null;
      _quietFrames = 0;
      return false;
    }
    _quietSince ??= now;
    _quietFrames++;
    return _quietFrames >= 3 && now.difference(_quietSince!) >= quietHold;
  }

  double _quietProgress(DateTime now) {
    final since = _quietSince;
    if (since == null) return 0;
    return (now.difference(since).inMilliseconds / quietHold.inMilliseconds).clamp(0.0, 1.0);
  }

  /// A read has started on this frame's crop.
  void textStarted(DateTime now, {required bool wholeView}) {
    _textBusy = true;
    _wholeViewInFlight = wholeView;
    _lastTextRead = now;
  }

  /// What a read returned. Dropped when the reading started over since it
  /// began, or when the photo is already being taken.
  void textFinished(LiveTextReadResult result, LiveTextCrop crop, {
    required int epoch,
    required Duration took,
    required bool wholeView,
    required DateTime now,
    bool capturing = false,
  }) {
    _textBusy = false;
    _wholeViewInFlight = false;
    _lastTextDuration = took;
    if (capturing || epoch != _textEpoch) return;
    switch (result.status) {
      case LiveTextReadStatus.read:
        reading.ingest(crop.frame(result.lines));
        if (wholeView) _textWholeAt = _readsWhole(reading.latest) ? now : null;
      case LiveTextReadStatus.failed:
        reading.readFailed();
      case LiveTextReadStatus.unavailable:
        reading.markReaderUnavailable();
      case LiveTextReadStatus.busy:
        break;
    }
  }

  /// The whole view's read found a page's text, none of it cut by the frame.
  static bool _readsWhole(ScanTextFrameSummary? latest) {
    if (latest == null || latest.layout.cutRows > 0 || latest.machineRowsCut) return false;
    return latest.layout.textRows >= ScanTextReadingSession.minimumPaperRows ||
        latest.machineRows >= 2 || latest.cardNumbers.isNotEmpty;
  }

  /// The reading starts over, for another page.
  void restartReading() {
    reading.reset();
    _textEpoch++;
    _lastTextRead = null;
    _textWholeAt = null;
    _wholeViewInFlight = false;
    _lastReadingPage = null;
  }

  /// Everything starts over (the camera restarted, auto-capture turned off).
  void reset() {
    _gate.reset();
    _shutter.reset();
    _quietSince = null;
    _quietFrames = 0;
    restartReading();
    analysis = null;
    progress = 0;
  }

  /// What was read, for this capture; a photo taken by hand returns whatever
  /// had been read by then.
  Map<String, Object>? liveReading({required bool automatic, required int referenceYear}) {
    final matched = automatic ? captureMatched : reading.status(glare: false).passed;
    return sanitizeLiveReading(reading.liveReading(
        engine: 'mlkit_latin', matched: matched, referenceYear: referenceYear));
  }

  /// The region the page's text is read in when no outline is found.
  static Rect get wholeViewRegion => scanWholeViewRegion;
}
