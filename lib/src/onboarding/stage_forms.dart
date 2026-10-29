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
import 'glass.dart';
import 'onboarding_flow.dart';
import 'svg_path.dart';

/// An object's outline and material, centred on the stage's middle.
class StageForm {
  StageForm(this.shape, this.glass);
  final RRect shape;
  final Glass glass;

  /// Its main colour, for a flat stand-in.
  Color get color => glass.fill[1];

  Path get path => Path()..addRRect(shape);
}


/// The passport page's paper, and the boarding pass's.
const pagePaper = Color(0xFFF2EFE7);
const passPaper = Color(0xFFFBFAF6);

/// The map's lens: dark glass over the city at night.
const lensGlass = Glass(
  fill: [Color(0xE6111C28), Color(0xE6111C28), Color(0xE6111C28)],
  rim: [Color(0xCCFFFFFF), Color(0x66D8E8F8), Color(0x29A4BCCF)],
  wall: Color(0x1FE4EFFA),
  highlight: GlassShadow(Color(0x33FFFFFF), dx: 1, dy: 2, blur: 3),
  glow: GlassShadow(Color(0x66CDE7FF), dx: -2, dy: -3, blur: 8),
  shadows: [
    GlassShadow.none,
    GlassShadow(Color(0x40000000), dy: 8, blur: 16, spread: -8),
    GlassShadow(Color(0x59000000), dy: 26, blur: 56, spread: -14),
  ],
);

// The sizes the scenes are built to.

/// The departures board: nine cells, 4 pt apart, in a glass case.
const boardCells = 9;
const boardGap = 4.0;
double boardCell(double width) => math.min(
    36.0, (width - 2 * boardCase - (boardCells - 1) * boardGap) / boardCells);
double boardWidth(double width) =>
    boardCells * boardCell(width) + (boardCells - 1) * boardGap;

/// The board's glass case, round the line of flaps.
const boardCase = 7.0;

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

/// The perforation, from the pass's top (the middle of its 20 pt band).
const passTearY = 246.0;
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
          box(boardWidth(stage.width) + boardCase * 2, h + boardCase * 2,
              h * 0.13 + boardCase),
          Glass.pane);
    case BoardingStep.notifications:
      return StageForm(box(cardWidth(stage.width), cardHeight, 22), Glass.pane);
    case BoardingStep.camera:
      final w = pageWidth(stage.width);
      return StageForm(box(w, w * 0.704, w * 0.035), Glass.solid(pagePaper));
    case BoardingStep.microphone:
      return StageForm(box(micSide, micSide, micSide / 2), Glass.tile);
    case BoardingStep.location:
      final r = lensRadius(stage);
      return StageForm(box(r * 2, r * 2, r), lensGlass);
    case BoardingStep.tracking:
      return StageForm(
          box(shieldSide, shieldSide, shieldSide / 2), Glass.tile);
    case BoardingStep.boarding:
      final s = passScale(stage);
      return StageForm(
          box(passWidth * s, passHeight * s, 20 * s), Glass.solid(passPaper));
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
