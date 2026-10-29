/// Where each step's object stands on the stage, as one shape: the board's
/// line, the front notification, the passport page, the mic, the map's lens,
/// the shield, the pass. The scenes draw their objects exactly here, and the
/// transitions morph between these shapes through the arrow, so one object
/// seems to become the next.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'brand_vectors.dart';
import 'onboarding_flow.dart';
import 'svg_path.dart';

/// An object's outline and colour, centred on the stage's middle.
class StageForm {
  const StageForm(this.shape, this.color);
  final RRect shape;
  final Color color;

  Path get path => Path()..addRRect(shape);
}

// The sizes the scenes are built to.

/// The departures board: nine cells, 4 pt apart.
const boardCells = 9;
const boardGap = 4.0;
double boardCell(double width) =>
    math.min(36.0, (width - (boardCells - 1) * boardGap) / boardCells);
double boardWidth(double width) =>
    boardCells * boardCell(width) + (boardCells - 1) * boardGap;

const cardHeight = 78.0;
double cardWidth(double width) => math.min(340.0, width);

double pageWidth(double width) => math.min(250.0, width * 0.78);

const micSide = 88.0;

/// The map is drawn in a square of up to 290 pt; its lens fades out over
/// the last fifth of its radius.
const lensBox = 290.0;
double lensRadius(Size stage) =>
    math.min(lensBox, math.min(stage.width, stage.height)) * 0.4;
const shieldSide = 96.0;

const passWidth = 300.0;
const passHeight = 352.0;
double passScale(Size stage) => math.min(1.0,
    math.min(stage.width / (passWidth + 8), stage.height / (passHeight + 24)));

StageForm formOf(BoardingStep step, Size stage) {
  RRect box(double w, double h, double r) => RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: w, height: h),
      Radius.circular(r));
  switch (step) {
    case BoardingStep.welcome:
      final cell = boardCell(stage.width);
      final h = cell * 1.44;
      return StageForm(
          box(boardWidth(stage.width), h, h * 0.13), const Color(0xFF182433));
    case BoardingStep.notifications:
      return StageForm(
          box(cardWidth(stage.width), cardHeight, 22), const Color(0xFF1A2633));
    case BoardingStep.camera:
      final w = pageWidth(stage.width);
      return StageForm(box(w, w * 0.704, w * 0.035), const Color(0xFFF2EFE7));
    case BoardingStep.microphone:
      return StageForm(
          box(micSide, micSide, micSide / 2), const Color(0xFF1F2E3E));
    case BoardingStep.location:
      final r = lensRadius(stage);
      return StageForm(box(r * 2, r * 2, r), const Color(0xFF111C28));
    case BoardingStep.tracking:
      return StageForm(
          box(shieldSide, shieldSide, shieldSide / 2), const Color(0xFF1F2E3E));
    case BoardingStep.boarding:
      final s = passScale(stage);
      return StageForm(
          box(passWidth * s, passHeight * s, 20 * s), const Color(0xFFFBFAF6));
  }
}

/// The arrow between objects: the F mark, [height] tall and centred, as its
/// three pieces: the arrow itself and its two trailing steps.
List<Path> arrowPieces(double height) {
  final mark = svgPath(foorsaMarkPath);
  final bounds = mark.getBounds();
  final scale = height / bounds.height;
  final place = Float64List.fromList([
    scale, 0, 0, 0, //
    0, scale, 0, 0,
    0, 0, 1, 0,
    -bounds.center.dx * scale, -bounds.center.dy * scale, 0, 1,
  ]);
  final pieces = [
    for (final m in mark.computeMetrics())
      m.extractPath(0, m.length).transform(place),
  ];
  // The arrow first, then the step nearest it, then the last.
  pieces.sort((a, b) => b
      .computeMetrics()
      .first
      .length
      .compareTo(a.computeMetrics().first.length));
  final arrow = pieces.first.getBounds().center;
  final steps = pieces.sublist(1)
    ..sort((a, b) => (a.getBounds().center - arrow)
        .distance
        .compareTo((b.getBounds().center - arrow).distance));
  return [pieces.first, ...steps];
}
