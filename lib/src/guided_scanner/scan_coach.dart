/// What the guided camera tells the student, one instruction at a time, so the
/// photo is right before it is taken (the owner, 1 Nov 2026: "let's guide the
/// student to take the perfect picture while taking the picture so the work is
/// easier for ai").
///
/// The words are the iPhone's: [scanLiveGuidance] mirrors ScannerLiveGuidance
/// (ios/Runner/ScannerGeometry.swift) line for line, and
/// test/scan_coach_test.dart holds every string of both to the other's. The
/// order is the iPhone's too: the page first (found, whole, close enough, the
/// phone held flat), then the light (too dark, glare, shadow), then what the
/// live reading still needs (the photo page's two lines, the card's side),
/// then holding still. [ScanGuidanceCoach] keeps a line on screen long enough
/// to be read and changes it only for one that has lasted, so a page at the
/// edge of two states does not make the words flicker.
library;

import 'dart:math' as math;
import 'dart:ui';

import 'scan_document_profile.dart';
import 'scan_guidance.dart';
import 'scan_text_reading.dart';

/// What one preview frame shows (ScannerLiveFraming on the iPhone).
enum ScanFraming { searching, ready, tooSmall, clipped, wrongShape, blurry }

/// Coarse light on the page (ScannerLiveLighting).
enum ScanLighting { good, shadow, glare, dim }

/// The instruction for the page and its light. Cards name their side when the
/// step asks for one; a page held at a slant is asked to be held flat before
/// anything about the light.
ScanTextCopy scanLiveGuidance({
  required ScanFraming framing,
  required ScanLighting lighting,
  required GuidedScanLayout layout,
  String? side,
  bool flat = true,
}) {
  switch (framing) {
    case ScanFraming.searching:
      switch (layout) {
        case GuidedScanLayout.passport:
          return const ScanTextCopy('Show the photo page',
              'Show the photo page with the two lines at the bottom.', 'Two bottom lines.');
        case GuidedScanLayout.card:
          if (side == 'front') {
            return const ScanTextCopy('Front side', 'Show the side with the photo.', 'The photo side.');
          }
          if (side == 'back') {
            return const ScanTextCopy('Now the back', 'Turn the card over.', 'Turn it over.');
          }
          return const ScanTextCopy('Find the card', 'Fit the whole card in view.', 'Whole card in view.');
        case GuidedScanLayout.portrait:
        case GuidedScanLayout.adaptive:
          return const ScanTextCopy('Find the page', 'Fit the whole page in view.', 'Whole page in view.');
      }
    case ScanFraming.clipped:
      return const ScanTextCopy('Move back a little', 'Keep all four corners in view.', 'Show all corners.');
    case ScanFraming.tooSmall:
      return const ScanTextCopy('Move closer', 'Let the page fill more of the view.', 'Move closer.');
    case ScanFraming.wrongShape:
      return layout == GuidedScanLayout.passport
          ? const ScanTextCopy('Show only the photo page',
              'Keep the passport open on the page with your photo.', 'Photo page only.')
          : const ScanTextCopy('Show all four corners', 'Fit the whole page in view.', 'All four corners.');
    case ScanFraming.blurry:
      return const ScanTextCopy('Hold still', 'Keep the phone steady.', 'Hold still.');
    case ScanFraming.ready:
      if (!flat) {
        return const ScanTextCopy('Hold the phone flat', 'Keep it level above the page.', 'Hold it flat.');
      }
      switch (lighting) {
        case ScanLighting.dim:
          return const ScanTextCopy('Too dark', 'Move to a brighter place.', 'More light.');
        case ScanLighting.glare:
          return const ScanTextCopy('Glare on the page', 'Tilt the phone slightly.', 'Tilt slightly.');
        case ScanLighting.shadow:
          return const ScanTextCopy('Shadow on the page', 'Move your hand or the phone.', 'Avoid the shadow.');
        case ScanLighting.good:
          return const ScanTextCopy('Hold still', 'Taking the photo.', 'Taking the photo.');
      }
  }
}

/// The calm word once the camera has the photo.
const scanGotIt = ScanTextCopy('Got it', 'Preparing your page.', 'Got it.');

/// Whether a page is held about flat under the phone: every corner near a
/// right angle and the opposite sides about as long (a slanted phone makes the
/// far edge short). A page turned on the desk is flat; only the phone's slant
/// is asked about. Corners are normalized to the view, `aspect` its width
/// over its height.
bool scanPageHeldFlat(List<Offset>? corners, double aspect) {
  if (corners == null || corners.length != 4) return true;
  final p = [for (final c in corners) Offset(c.dx * aspect, c.dy)];
  double side(int i) => (p[(i + 1) % 4] - p[i]).distance;
  final top = side(0), right = side(1), bottom = side(2), left = side(3);
  if (math.min(top, bottom) < math.max(top, bottom) * 0.82 ||
      math.min(left, right) < math.max(left, right) * 0.82) {
    return false;
  }
  for (var i = 0; i < 4; i++) {
    final a = p[(i + 3) % 4] - p[i], b = p[(i + 1) % 4] - p[i];
    final lengths = a.distance * b.distance;
    if (lengths == 0) return false;
    final cosine = (a.dx * b.dx + a.dy * b.dy) / lengths;
    final angle = math.acos(cosine.clamp(-1.0, 1.0)) * 180 / math.pi;
    if (angle < 72 || angle > 108) return false;
  }
  return true;
}

/// The frame's framing, as the iPhone's classifier names it.
ScanFraming scanFramingOf(ScanFrameAnalysis analysis) {
  switch (analysis.hint) {
    case ScanHint.moveBack:
      return ScanFraming.clipped;
    case ScanHint.moveCloser:
      return ScanFraming.tooSmall;
    case ScanHint.position:
      return analysis.bounds == null ? ScanFraming.searching : ScanFraming.wrongShape;
    case ScanHint.focus:
    case ScanHint.holdSteady:
      return ScanFraming.blurry;
    case ScanHint.brighten:
    case ScanHint.reduceGlare:
    case ScanHint.ready:
      return ScanFraming.ready;
  }
}

/// The light on the page found in the frame.
ScanLighting scanLightingOf(ScanFrameAnalysis analysis) => switch (analysis.hint) {
      ScanHint.brighten => ScanLighting.dim,
      ScanHint.reduceGlare => ScanLighting.glare,
      _ => analysis.shadow ? ScanLighting.shadow : ScanLighting.good,
    };

/// What the outline says, besides its colour: dashed while the page is looked
/// for ([searching], the guide) or found with something to fix ([adjusting],
/// the page's own outline), solid while the page is held for the photo
/// ([holding]), and a check once the photo is in ([done]).
enum ScanOutlineState { searching, adjusting, holding, done }

/// One instruction and the state of the outline that goes with it.
class ScanGuidance {
  const ScanGuidance(this.copy, this.state);

  final ScanTextCopy copy;
  final ScanOutlineState state;

  @override
  bool operator ==(Object other) => other is ScanGuidance && other.copy == copy && other.state == state;

  @override
  int get hashCode => Object.hash(copy, state);

  @override
  String toString() => 'ScanGuidance(${copy.title}, ${state.name})';
}

/// What shows once the camera has the photo.
const scanGuidanceDone = ScanGuidance(scanGotIt, ScanOutlineState.done);

/// What shows while the photo is being taken.
const scanTakingPhoto = ScanTextCopy('Hold still', 'Taking the photo.', 'Taking the photo.');

/// The one instruction for this frame, in priority order: the page (found,
/// whole, close enough, the right shape, sharp), how the phone is held, the
/// light, what the live reading still needs, then holding still for the
/// photo. `textPage`: no outline, but the page's text was read whole in the
/// view, which finds a page as surely as an outline (scan_frame_loop.dart).
ScanGuidance scanGuidanceFor(
  ScanFrameAnalysis? analysis,
  ScanTextGateStatus? reading, {
  required GuidedDocumentProfile profile,
  required double aspect,
  bool textPage = false,
}) {
  final layout = profile.layout, side = profile.side;
  ScanGuidance adjusting(ScanTextCopy copy) => ScanGuidance(copy, ScanOutlineState.adjusting);
  if (analysis == null) {
    return ScanGuidance(
        scanLiveGuidance(framing: ScanFraming.searching, lighting: ScanLighting.good, layout: layout, side: side),
        ScanOutlineState.searching);
  }
  var framing = scanFramingOf(analysis);
  // A page found by its text alone is in view: what follows is the reading's.
  if (textPage && analysis.bounds == null) framing = ScanFraming.ready;
  if (framing == ScanFraming.searching) {
    return ScanGuidance(scanLiveGuidance(framing: framing, lighting: ScanLighting.good, layout: layout, side: side),
        ScanOutlineState.searching);
  }
  if (framing != ScanFraming.ready) {
    return adjusting(scanLiveGuidance(framing: framing, lighting: ScanLighting.good, layout: layout, side: side));
  }
  final lighting = scanLightingOf(analysis);
  final flat = scanPageHeldFlat(analysis.corners, aspect);
  if (!flat || lighting != ScanLighting.good) {
    return adjusting(scanLiveGuidance(framing: framing, lighting: lighting, layout: layout, side: side, flat: flat));
  }
  // Framing and light are right; what the reading still needs comes next.
  final guidance = reading?.guidance;
  if (reading != null && !reading.allowsCapture && guidance != null) {
    final copy = guidance.copy(profile.paperKind);
    // Still reading the page is holding still for it.
    return guidance.asksToHold ? ScanGuidance(copy, ScanOutlineState.holding) : adjusting(copy);
  }
  return ScanGuidance(
      scanLiveGuidance(framing: framing, lighting: lighting, layout: layout, side: side), ScanOutlineState.holding);
}

/// Shows one instruction at a time: a line stays at least [minimumDisplay],
/// and another takes its place only once it has been asked for [settle]
/// without a break, so a page at the edge of two states does not make the
/// words flicker. "Got it" shows at once, and so does anything [update] is
/// told is `immediate` (the photo being taken).
class ScanGuidanceCoach {
  static const minimumDisplay = Duration(milliseconds: 1000);
  static const settle = Duration(milliseconds: 350);

  ScanGuidance? _shown;
  DateTime? _shownAt;
  ScanGuidance? _pending;
  DateTime? _pendingSince;

  ScanGuidance? get shown => _shown;

  /// The line to show at [now], given what this frame asks for; `changed` is
  /// true when it is a new line, and `announce` when its words are new to a
  /// screen reader (a new title: "Hold still" reading the page, then taking
  /// the photo, is said once).
  ({ScanGuidance line, bool changed, bool announce}) update(ScanGuidance candidate, DateTime now,
      {bool immediate = false}) {
    final shown = _shown;
    if (shown == null || immediate || candidate.state == ScanOutlineState.done) {
      final changed = shown != candidate;
      _show(candidate, now);
      return (line: candidate, changed: changed, announce: changed && shown?.copy.title != candidate.copy.title);
    }
    if (candidate == shown) {
      _pending = null;
      _pendingSince = null;
      return (line: shown, changed: false, announce: false);
    }
    if (_pending != candidate) {
      _pending = candidate;
      _pendingSince = now;
    }
    if (now.difference(_pendingSince!) >= settle && now.difference(_shownAt!) >= minimumDisplay) {
      _show(candidate, now);
      return (line: candidate, changed: true, announce: shown.copy.title != candidate.copy.title);
    }
    return (line: shown, changed: false, announce: false);
  }

  void _show(ScanGuidance line, DateTime now) {
    _shown = line;
    _shownAt = now;
    _pending = null;
    _pendingSince = null;
  }

  void reset() {
    _shown = null;
    _shownAt = null;
    _pending = null;
    _pendingSince = null;
  }
}
