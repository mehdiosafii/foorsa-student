import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/guided_scanner/scan_photo.dart';

import 'support/printed_page.dart';

void main() {
  final page = printedPage();
  double score(Uint8List luma) => scanStillSharpness(luma, page.width, page.height);

  test('crisp print reads sharp, soft or streaked print reads soft', () {
    final crisp = score(page.luma);
    final soft = score(gaussian(page.luma, page.width, page.height, 1.5));
    final missed = score(gaussian(page.luma, page.width, page.height, 3));
    final moved = score(streak(page.luma, page.width, page.height, 8));
    final movedDown = score(streak(page.luma, page.width, page.height, 8, vertical: true));
    final slight = score(gaussian(page.luma, page.width, page.height, 0.7));
    // ignore: avoid_print
    print('crisp $crisp slight $slight soft $soft missed $missed moved $moved down $movedDown');
    // The order is what picks the still.
    expect(crisp, greaterThan(slight));
    expect(slight, greaterThan(soft));
    expect(soft, greaterThan(missed));
    expect(moved, lessThan(soft));
    expect(movedDown, lessThan(soft));
    expect(crisp / moved, greaterThan(2), reason: 'a shaken still loses clearly');
  });

  test('a dim, noisy page is judged on its focus, not its light', () {
    final dim = printedPage(paper: 140, ink: 30, noise: 6);
    final dimScore = scanStillSharpness(dim.luma, dim.width, dim.height);
    final dimSoft = scanStillSharpness(gaussian(dim.luma, dim.width, dim.height, 1.5), dim.width, dim.height);
    final dimMoved = scanStillSharpness(streak(dim.luma, dim.width, dim.height, 8), dim.width, dim.height);
    expect(dimSoft, lessThan(dimScore));
    expect(dimMoved, lessThan(dimScore));
    // The same page, darker: its score moves far less than a shake does.
    final bright = scanStillSharpness(page.luma, page.width, page.height);
    expect((dimScore - bright).abs(), lessThan(bright - score(streak(page.luma, page.width, page.height, 8))));
  });

  test('two stills of every page, and only two', () {
    expect(wantsAnotherStill([]), isTrue);
    expect(wantsAnotherStill([3.0]), isTrue);
    expect(wantsAnotherStill([0.9]), isTrue, reason: 'a card scores low and is taken twice like any page');
    expect(wantsAnotherStill([3.0, 2.5]), isFalse);
    expect(wantsAnotherStill([0.9, 1.1]), isFalse);
    expect(wantsAnotherStill([null]), isFalse, reason: 'a phone that cannot measure keeps its first');
  });

  test('the sharpest still is kept, the first among equals', () {
    expect(bestStill([2.0, 3.0]), 1);
    expect(bestStill([3.0, 2.0]), 0);
    expect(bestStill([3.0, 3.03]), 0, reason: 'within 2% is a tie, and the first wins');
    expect(bestStill([1.0, 0.8, 1.5]), 2);
    expect(bestStill([null, 2.0]), 1);
    expect(bestStill([null]), 0);
    expect(bestStill([]), -1);
  });
}
