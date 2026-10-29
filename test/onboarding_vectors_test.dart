import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/onboarding/brand_vectors.dart';
import 'package:foorsa_student/src/onboarding/svg_path.dart';

void main() {
  test('lucide’s check reads as lucide draws it', () {
    final bounds = parseSvgPath('M20 6 9 17l-5-5').getBounds();
    expect(bounds.left, closeTo(4, 0.01));
    expect(bounds.top, closeTo(6, 0.01));
    expect(bounds.right, closeTo(20, 0.01));
    expect(bounds.bottom, closeTo(17, 0.01));
  });

  test('relative moves, lines, curves and arcs land where SVG puts them', () {
    // A circle of radius 3 at (12, 13), drawn as two relative arcs.
    final circle =
        parseSvgPath('M9 13a3 3 0 1 0 6 0a3 3 0 1 0 -6 0').getBounds();
    expect(circle.center.dx, closeTo(12, 0.05));
    expect(circle.center.dy, closeTo(13, 0.05));
    expect(circle.width, closeTo(6, 0.05));
    final box = parseSvgPath('m2 2h10v10h-10z').getBounds();
    expect(box, const Rect.fromLTRB(2, 2, 12, 12));
    final curve = parseSvgPath('M0 0c0 10 10 10 10 0s10-10 10 0').getBounds();
    expect(curve.right, closeTo(20, 0.01));
  });

  test('a broken string draws what it can instead of throwing mid-frame', () {
    expect(() => parseSvgPath('M0 0L10 10L'), returnsNormally);
    expect(() => parseSvgPath('M0 0 Q'), returnsNormally);
    expect(parseSvgPath('M0 0L10 10L').getBounds().right, closeTo(10, 0.01));
  });

  test('the wordmark and the F mark fill their boxes, as the portal draws them',
      () {
    final word = svgPath(foorsaWordmarkPath).getBounds();
    expect(word.left, greaterThan(-1));
    expect(word.right, lessThan(2033));
    expect(word.width, greaterThan(1900));
    expect(word.bottom, lessThanOrEqualTo(643.5));
    final mark = svgPath(foorsaMarkPath).getBounds();
    expect(mark.width, greaterThan(700));
    expect(mark.right, lessThan(758));
  });
}
