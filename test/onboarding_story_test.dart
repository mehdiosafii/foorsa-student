import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/onboarding/arrow_flight.dart';
import 'package:foorsa_student/src/onboarding/glass.dart';
import 'package:foorsa_student/src/onboarding/onboarding_flow.dart';
import 'package:foorsa_student/src/onboarding/onboarding_page.dart';
import 'package:foorsa_student/src/onboarding/runway.dart';
import 'package:foorsa_student/src/onboarding/shape_morph.dart';
import 'package:foorsa_student/src/onboarding/stage_forms.dart';
import 'package:foorsa_student/src/onboarding/stage_morph.dart';

void main() {
  test('an outline is walked at even steps, clockwise as seen', () {
    final square = Path()..addRect(const Rect.fromLTWH(0, 0, 10, 10));
    final points = outlineOf(square, count: 40);
    expect(points, hasLength(40));
    var area = 0.0;
    for (var i = 0; i < points.length; i++) {
      final a = points[i], b = points[(i + 1) % points.length];
      area += a.dx * b.dy - b.dx * a.dy;
    }
    expect(area, greaterThan(0));
    // Drawn the other way round, it still comes out clockwise.
    final backwards = Path()
      ..moveTo(0, 0)
      ..lineTo(0, 10)
      ..lineTo(10, 10)
      ..lineTo(10, 0)
      ..close();
    final again = outlineOf(backwards, count: 40);
    var area2 = 0.0;
    for (var i = 0; i < again.length; i++) {
      final a = again[i], b = again[(i + 1) % again.length];
      area2 += a.dx * b.dy - b.dx * a.dy;
    }
    expect(area2, greaterThan(0));
  });

  test('two outlines are lined up point for point before they morph', () {
    final from = outlineOf(Path()..addOval(const Rect.fromLTWH(0, 0, 100, 100)),
        count: 64);
    final turned = [for (var i = 0; i < 64; i++) from[(i + 21) % 64]];
    final aligned = alignTo(from, turned);
    for (var i = 0; i < 64; i++) {
      expect((aligned[i] - from[i]).distance, lessThan(0.001));
    }
    // Halfway, every point is halfway.
    final half = lerpOutline(from, aligned, 0.5).getBounds();
    expect(half.width, closeTo(100, 0.5));
  });

  for (final stage in const [Size(342, 430), Size(272, 200)]) {
    test(
        'every step\'s object stands inside a ${stage.width} x ${stage.height} stage',
        () {
      for (final step in BoardingStep.values) {
        final form = formOf(step, stage).shape.outerRect;
        expect(form.center.distance, lessThan(0.001), reason: step.name);
        expect(form.width, lessThanOrEqualTo(stage.width + 0.001),
            reason: step.name);
        expect(form.height, lessThanOrEqualTo(stage.height + 0.001),
            reason: step.name);
      }
    });
  }

  test('the arrow between objects is the F: the arrow, then its two steps', () {
    final pieces = arrowPieces(84);
    expect(pieces, hasLength(3));
    final all =
        pieces.map((p) => p.getBounds()).reduce((a, b) => a.expandToInclude(b));
    expect(all.height, closeTo(84, 0.5));
    expect(all.center.distance, lessThan(0.5));
    final arrow = pieces.first.getBounds();
    for (final step in pieces.skip(1)) {
      expect(step.getBounds().width, lessThan(arrow.width));
      // The steps trail below and to the left of the arrow.
      expect(step.getBounds().center.dx, lessThan(arrow.center.dx));
      expect(step.getBounds().center.dy, greaterThan(arrow.center.dy));
    }
  });

  test('the runway\'s arrow leaves the runway where the page flies it from',
      () {
    const size = Size(342, runwayHeight);
    final parked = runwayArrow(size, RunwayPhase.parked, still: true)!;
    expect(parked.at, runwayGate(size));
    expect(parked.heading, 0, reason: 'it waits pointing down the runway');
    final lifted = runwayArrow(size, RunwayPhase.departing, depart: 1)!;
    expect((lifted.at - runwayLiftOff(size)).distance, lessThan(0.001));
    expect(lifted.heading, closeTo(restHeading, 1e-9));
    expect(lifted.height, liftArrowHeight);
    // It rolls forward the whole way, never back.
    var x = -1.0;
    for (var t = 0.0; t <= 1.0; t += 0.05) {
      final pose = runwayArrow(size, RunwayPhase.departing, depart: t)!;
      expect(pose.at.dx, greaterThanOrEqualTo(x - 1e-9));
      x = pose.at.dx;
    }
    expect(runwayArrow(size, RunwayPhase.away), isNull);
    final arrived = runwayArrow(size, RunwayPhase.arriving, arrive: 1)!;
    expect(arrived.at, parked.at);
  });

  test('a swoop ends on the stage\'s arrow, the size and way round it is', () {
    final swoop = Swoop.intoStage(
        from: const Offset(336, 718),
        fromHeading: restHeading,
        fromHeight: liftArrowHeight,
        to: const Offset(195, 324),
        speed: 1.5);
    final (start, _) = swoop.at(0);
    expect((start.at - const Offset(336, 718)).distance, lessThan(0.001));
    expect(start.heading, closeTo(restHeading, 1e-6));
    final (end, bank) = swoop.at(1);
    expect((end.at - const Offset(195, 324)).distance, lessThan(0.001));
    expect(end.height, stageArrowHeight);
    expect(end.heading, closeTo(restHeading, 1e-6));
    expect(bank.abs(), lessThan(0.001), reason: 'level as it docks');
    // It stays on the phone's screen on its way.
    for (var t = 0.0; t <= 1.0; t += 0.02) {
      final (pose, _) = swoop.at(t);
      expect(pose.at.dx, inInclusiveRange(0, 390));
    }
  });

  test('the picture folds as the arrow arrives, and unfolds after', () {
    var last = -1.0;
    for (var s = 0.0; s <= 1.5; s += 0.01) {
      final m = flightMorph(s);
      expect(m, greaterThanOrEqualTo(last));
      last = m;
    }
    expect(flightMorph(0), 0);
    // Docked: the morph is exactly at the arrow when the swoop ends.
    expect(flightMorph(0.6), closeTo(arrowAt, 1e-9));
    expect(flightMorph(1.5), 1);
  });

  test('glass grows and shrinks along its outline for a shadow\'s spread', () {
    final disc = outlineOf(
        Path()..addOval(const Rect.fromLTWH(0, 0, 100, 100)),
        count: 160);
    for (final (d, r) in [(10.0, 60.0), (-10.0, 40.0)]) {
      for (final p in offsetOutline(disc, d)) {
        expect((p - const Offset(50, 50)).distance, closeTo(r, 0.2));
      }
    }
    // CSS's 180deg runs straight down the box.
    final (a, b) = cssGradientLine(const Rect.fromLTWH(0, 0, 50, 80), 180);
    expect(a.dx, closeTo(25, 1e-9));
    expect(b.dx, closeTo(25, 1e-9));
    expect(b.dy - a.dy, closeTo(80, 1e-9));
    final (c, d) = cssGradientLine(const Rect.fromLTWH(0, 0, 80, 80), 135);
    expect((d - c).direction, closeTo(math.pi / 4, 1e-9));
  });

  test('every glass mixes into every other, the paper ones too', () {
    final all = [Glass.pane, Glass.tile, Glass.pearl, lensGlass,
      Glass.solid(pagePaper)];
    for (final a in all) {
      for (final b in all) {
        final half = Glass.lerp(a, b, 0.5);
        expect(half.fill, hasLength(3));
        expect(half.shadows, hasLength(3));
      }
    }
  });
}
