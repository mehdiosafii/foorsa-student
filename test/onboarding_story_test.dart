import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/onboarding/onboarding_flow.dart';
import 'package:foorsa_student/src/onboarding/shape_morph.dart';
import 'package:foorsa_student/src/onboarding/stage_forms.dart';

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
}
