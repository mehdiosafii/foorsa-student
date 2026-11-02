/// What the guided camera draws to lead the student to a good photo (the
/// owner, 1 Nov 2026: "let's guide the student to take the perfect picture
/// while taking the picture so the work is easier for ai"): one instruction at
/// a time in a panel ([ScanGuidancePanel]), and an outline over the preview
/// ([ScanGuidePainter]) whose state shows in its pattern and in an icon, not
/// in its colour alone: dashed while the page is looked for or has something
/// to fix, solid while it is held for the photo, a check once the photo is in.
/// The words and their order are scan_coach.dart's; the iPhone's scanner
/// draws the same states (FoorsaScannerViewController.swift).
library;

import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import 'scan_coach.dart';
import 'scan_text_reading.dart';

/// The colour of a page held for the photo; everything else is white.
const scanHoldingColour = Color(0xFF3DE5B4);

/// The icon beside an instruction, by the outline's state.
IconData scanGuidanceIcon(ScanOutlineState state) => switch (state) {
      ScanOutlineState.searching => Icons.crop_free,
      ScanOutlineState.adjusting => Icons.open_with,
      ScanOutlineState.holding => Icons.center_focus_strong,
      ScanOutlineState.done => Icons.check_circle,
    };

/// The instruction panel: an icon, the instruction and what to do, and while
/// the page is held the time left before the photo. A screen reader hears a
/// new instruction once (a polite live region; the coach changes the words at
/// most once a second), never the progress.
class ScanGuidancePanel extends StatelessWidget {
  const ScanGuidancePanel({
    super.key,
    required this.copy,
    required this.state,
    this.progress,
    this.busy = false,
  });

  final ScanTextCopy copy;
  final ScanOutlineState state;

  /// How far the hold has come (0 to 1), shown only while [state] is holding.
  final double? progress;

  /// The photo is being taken: the bar runs without an end.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final holding = state == ScanOutlineState.holding || state == ScanOutlineState.done;
    final colour = holding ? scanHoldingColour : Colors.white;
    // At large text sizes the short form of the detail, as on the iPhone.
    final compact = MediaQuery.textScalerOf(context).scale(14) > 14 * 1.3;
    final detail = compact ? copy.compact : copy.detail;
    final still = MediaQuery.disableAnimationsOf(context);
    final showBar = busy || (state == ScanOutlineState.holding && progress != null);
    final words = Row(
      key: ValueKey(copy),
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(scanGuidanceIcon(state), color: colour, size: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                copy.title,
                style: TextStyle(color: colour, fontSize: 16, fontWeight: FontWeight.w700, height: 1.25),
              ),
              if (detail.isNotEmpty && detail != copy.title) ...[
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.3),
                ),
              ],
            ],
          ),
        ),
      ],
    );
    return Semantics(
      container: true,
      liveRegion: true,
      label: detail.isEmpty || detail == copy.title ? copy.title : '${copy.title}. $detail',
      child: ExcludeSemantics(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 14, 18, 14),
          decoration: BoxDecoration(
            color: const Color(0xE6151A22),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: holding ? scanHoldingColour.withValues(alpha: 0.55) : Colors.white24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // A new instruction fades in over the last, quickly: the words
              // change at most once a second, and never mid-sentence.
              AnimatedSwitcher(
                duration: still ? Duration.zero : const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeOut,
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.centerLeft,
                  children: [...previous, if (current != null) current],
                ),
                child: words,
              ),
              AnimatedOpacity(
                opacity: showBar ? 1 : 0,
                duration: still ? Duration.zero : const Duration(milliseconds: 150),
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: busy ? null : (showBar ? progress!.clamp(0.0, 1.0) : 0),
                      minHeight: 3,
                      backgroundColor: Colors.white24,
                      valueColor: const AlwaysStoppedAnimation<Color>(scanHoldingColour),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The veil, the outline and its corners over the preview, in the preview's
/// normalized coordinates (the frame analysis's): the guide while no page is
/// found, the page's own four corners once it is.
class ScanGuidePainter extends CustomPainter {
  const ScanGuidePainter({
    required this.guide,
    required this.state,
    this.corners,
    this.zones = const [],
  });

  /// Where the page is asked for (the guide, or the page's box when found).
  final Rect guide;
  final ScanOutlineState state;

  /// The page found, top-left first and clockwise, when it was.
  final List<Offset>? corners;
  final List<String> zones;

  static const dash = 10.0, gap = 7.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTRB(guide.left * size.width, guide.top * size.height,
        guide.right * size.width, guide.bottom * size.height);
    // Where the outline is follows each frame; how it is drawn follows the
    // instruction on screen, which the coach holds long enough to be read.
    final quad = corners != null && corners!.length == 4
        ? [for (final c in corners!) Offset(c.dx * size.width, c.dy * size.height)]
        : null;
    final outline = quad != null
        ? (Path()..addPolygon(quad, true))
        : (Path()..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(16))));
    final veil = Path()..fillType = PathFillType.evenOdd;
    veil.addRect(Offset.zero & size);
    veil.addPath(outline, Offset.zero);
    canvas.drawPath(veil, Paint()..color = const Color(0x99000000));

    final held = state == ScanOutlineState.holding || state == ScanOutlineState.done;
    final colour = held ? scanHoldingColour : Colors.white;
    final line = Paint()
      ..color = colour.withValues(alpha: held ? 0.95 : 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = held ? 3 : 2
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    // Dashed while looking or adjusting, solid once held: the state is in the
    // pattern, not only in the colour.
    canvas.drawPath(held ? outline : dashed(outline), line);

    final corner = Path();
    const segment = 28.0;
    if (quad != null) {
      for (var i = 0; i < 4; i++) {
        final at = quad[i], next = quad[(i + 1) % 4], previous = quad[(i + 3) % 4];
        Offset toward(Offset other) {
          final d = other - at;
          final length = d.distance;
          return length == 0 ? at : at + d * (math.min(segment, length / 2) / length);
        }
        corner
          ..moveTo(toward(previous).dx, toward(previous).dy)
          ..lineTo(at.dx, at.dy)
          ..lineTo(toward(next).dx, toward(next).dy);
      }
    } else {
      final l = rect.left, r = rect.right, t = rect.top, b = rect.bottom;
      corner
        ..moveTo(l, t + segment)..lineTo(l, t)..lineTo(l + segment, t)
        ..moveTo(r - segment, t)..lineTo(r, t)..lineTo(r, t + segment)
        ..moveTo(l, b - segment)..lineTo(l, b)..lineTo(l + segment, b)
        ..moveTo(r - segment, b)..lineTo(r, b)..lineTo(r, b - segment);
    }
    canvas.drawPath(
      corner,
      Paint()
        ..color = colour
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );

    if (state == ScanOutlineState.done) {
      final centre = quad != null ? quad.fold(Offset.zero, (sum, c) => sum + c) / 4 : rect.center;
      canvas.drawCircle(centre, 26, Paint()..color = scanHoldingColour);
      final tick = Path()
        ..moveTo(centre.dx - 11, centre.dy + 1)
        ..lineTo(centre.dx - 3, centre.dy + 9)
        ..lineTo(centre.dx + 12, centre.dy - 8);
      canvas.drawPath(
        tick,
        Paint()
          ..color = const Color(0xFF0B1A16)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // Visual hints only: the camera does not pretend to have read the
    // passport's photo or its lines from these. A passport is asked for open
    // at its photo page, both pages in one photo (the owner, 1 Nov 2026), so
    // a passport guide taller than it is wide is the open booklet: the page
    // facing the photo page above the fold, with the passport number punched
    // along its edge, and the photo page below it, with the photo and the two
    // lines (the portal's own guide draws it the same way, UploadGuide.tsx).
    final passport = zones.contains('passport_mrz') || zones.contains('passport_photo');
    final booklet = quad == null && passport && rect.height > rect.width;
    final photoPage = booklet ? Rect.fromLTRB(rect.left, rect.center.dy, rect.right, rect.bottom) : rect;
    if (booklet) {
      final hint = Paint()
        ..color = colour.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(
          dashed(Path()
            ..moveTo(rect.left + 12, rect.center.dy)
            ..lineTo(rect.right - 12, rect.center.dy)),
          hint);
      final number = Rect.fromLTWH(rect.right - rect.width * 0.15, rect.top + rect.height * 0.07,
          rect.width * 0.08, rect.height * 0.34);
      canvas.drawRRect(
        RRect.fromRectAndRadius(number, const Radius.circular(4)),
        Paint()
          ..color = colour.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
    }
    if (quad == null && zones.contains('passport_mrz')) {
      final zone = Rect.fromLTWH(photoPage.left + photoPage.width * 0.07, photoPage.top + photoPage.height * 0.77,
          photoPage.width * 0.86, photoPage.height * 0.17);
      canvas.drawRRect(
        RRect.fromRectAndRadius(zone, const Radius.circular(5)),
        Paint()
          ..color = colour.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3,
      );
    }
    // A card held long side across (ICAO's ID-1, the Moroccan CNIE): its photo
    // on the left of the front, its three machine-readable lines across the
    // bottom of the back.
    final cardGuide = quad == null && rect.width > rect.height;
    if (cardGuide && zones.contains('card_photo')) {
      final zone = Rect.fromLTWH(rect.left + rect.width * 0.05, rect.top + rect.height * 0.2,
          rect.width * 0.27, rect.height * 0.6);
      canvas.drawRRect(
        RRect.fromRectAndRadius(zone, const Radius.circular(4)),
        Paint()
          ..color = colour.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
    }
    if (cardGuide && zones.contains('card_mrz')) {
      final zone = Rect.fromLTWH(rect.left + rect.width * 0.05, rect.top + rect.height * 0.64,
          rect.width * 0.9, rect.height * 0.28);
      final hint = Paint()
        ..color = colour.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3;
      canvas.drawRRect(RRect.fromRectAndRadius(zone, const Radius.circular(5)), hint);
      // Its three lines, so the student knows which edge goes at the bottom.
      final lines = Paint()
        ..color = colour.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..strokeCap = StrokeCap.round;
      for (var row = 1; row <= 3; row++) {
        final y = zone.top + zone.height * row / 4;
        canvas.drawPath(dashed(Path()
          ..moveTo(zone.left + 8, y)
          ..lineTo(zone.right - 8, y)), lines);
      }
    }
    if (quad == null && zones.contains('passport_photo')) {
      final zone = Rect.fromLTWH(photoPage.left + photoPage.width * 0.08, photoPage.top + photoPage.height * 0.14,
          photoPage.width * 0.23, photoPage.height * 0.51);
      canvas.drawRRect(
        RRect.fromRectAndRadius(zone, const Radius.circular(4)),
        Paint()
          ..color = colour.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
    }
  }

  /// The path drawn as dashes along its length.
  static Path dashed(Path source) {
    final out = Path();
    for (final PathMetric metric in source.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = math.min(distance + dash, metric.length);
        out.addPath(metric.extractPath(distance, end), Offset.zero);
        distance = end + gap;
      }
    }
    return out;
  }

  @override
  bool shouldRepaint(covariant ScanGuidePainter oldDelegate) =>
      oldDelegate.guide != guide ||
      oldDelegate.state != state ||
      oldDelegate.corners != corners ||
      oldDelegate.zones != zones;
}
