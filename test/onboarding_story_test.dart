import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/onboarding/arrow_flight.dart';
import 'package:foorsa_student/src/onboarding/glass.dart';
import 'package:foorsa_student/src/onboarding/onboarding_flow.dart';
import 'package:foorsa_student/src/onboarding/onboarding_page.dart';
import 'package:foorsa_student/src/onboarding/scene_location.dart';
import 'package:foorsa_student/src/onboarding/scene_welcome.dart';
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

  test('a thrown arrow carries on into its flight, and never overshoots', () {
    // Faster throws carry on faster, up to what the curve takes without
    // going past the dock and back.
    expect(throwSpeed(const Offset(0, -300), 150),
        lessThan(throwSpeed(const Offset(0, -900), 150)));
    expect(throwSpeed(const Offset(0, -9000), 150), 2.4);
    expect(throwSpeed(Offset.zero, 150), 0);
    for (final v0 in [0.0, 1.0, 2.4]) {
      var last = -1.0;
      for (var t = 0.0; t <= 1.0001; t += 0.01) {
        final s = launchCurve(t, v0);
        expect(s, greaterThanOrEqualTo(last - 1e-9), reason: 'v0 $v0 at $t');
        expect(s, lessThanOrEqualTo(1 + 1e-9));
        last = s;
      }
    }
  });

  test('the map\'s arrow is on the lens\'s edge, low on the right', () {
    for (final r in [100.0, 116.0]) {
      final at = locateOffset(r);
      expect(at.distance, closeTo(r, 1e-9));
      expect(at.dx, greaterThan(0));
      expect(at.dy, greaterThan(0), reason: 'below the middle, near a thumb');
    }
  });

  test('a swoop ends on the stage\'s arrow, the size and way round it is', () {
    final swoop = Swoop.intoStage(
        from: const Offset(336, 718),
        fromHeading: restHeading,
        fromHeight: launchArrowHeight,
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
    for (final times in [FlightTimes.lifted, FlightTimes.thrown]) {
      var last = -1.0;
      for (var s = 0.0; s <= times.total + 0.1; s += 0.01) {
        final m = flightMorph(s, times);
        expect(m, greaterThanOrEqualTo(last));
        last = m;
      }
      expect(flightMorph(0, times), 0);
      // Docked: the morph is exactly at the arrow when the swoop ends.
      expect(flightMorph(times.swoop, times), closeTo(arrowAt, 1e-9));
      expect(flightMorph(times.total, times), 1);
      expect(times.wordsFrom, greaterThan(times.beatTo));
    }
    // Thrown, it is in the picture sooner than one lifted out of a button.
    expect(FlightTimes.thrown.swoop, lessThan(FlightTimes.lifted.swoop));
  });

  test('a lifted arrow glides in level, pointing its own way', () {
    final glide = Swoop(
        from: const Offset(277, 612),
        fromHeading: restHeading,
        fromHeight: 19,
        to: const Offset(195, 530),
        toHeight: stageArrowHeight,
        follow: false,
        launch: const Offset(0.2, -1),
        approach: const Offset(-0.5, -1));
    for (var t = 0.0; t <= 1.0; t += 0.05) {
      final (pose, bank) = glide.at(t);
      expect(pose.heading, closeTo(restHeading, 1e-9));
      expect(bank, 0);
    }
    final (end, _) = glide.at(1);
    expect((end.at - const Offset(195, 530)).distance, lessThan(0.001));
    expect(end.height, stageArrowHeight);
  });

  test('the welcome\'s arrow turns to the way it is drawn up', () {
    expect(launchAim(Offset.zero), restHeading);
    expect(launchAim(const Offset(0, 20)), restHeading);
    expect(launchAim(const Offset(0, -90)), closeTo(-math.pi / 2, 1e-9));
    final half = launchAim(const Offset(0, -45));
    expect(half, lessThan(restHeading));
    expect(half, greaterThan(-math.pi / 2));
  });

  test('glass grows and shrinks along its outline for a shadow\'s spread', () {
    final disc = outlineOf(Path()..addOval(const Rect.fromLTWH(0, 0, 100, 100)),
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
    final all = [
      Glass.pane,
      Glass.tile,
      Glass.pearl,
      lensGlass,
      Glass.solid(pagePaper)
    ];
    for (final a in all) {
      for (final b in all) {
        final half = Glass.lerp(a, b, 0.5);
        expect(half.fill, hasLength(3));
        expect(half.shadows, hasLength(3));
      }
    }
  });
}
