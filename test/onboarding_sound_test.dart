import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/onboarding/onboarding_sound.dart';

void main() {
  test('every cue the onboarding plays ships as a sound, and nothing else does',
      () {
    // scripts/onboarding_sounds/compose.py --encode writes these; a cue with
    // no file would only fail on the phone, silently.
    final shipped = Directory('assets/sounds/onboarding')
        .listSync()
        .whereType<File>()
        .map((file) => file.uri.pathSegments.last)
        .where((name) => name.endsWith('.m4a'))
        .map((name) => name.substring(0, name.length - '.m4a'.length))
        .toSet();
    expect(shipped, {...onboardingCues, 'bed'});
  });

  test('the cues timed to the picture start soonest on Android', () {
    // The media player starts a cue a tenth of a second or more late: the
    // dock's note came after the arrow had docked. The intro is sought into
    // when it loads late, which the low-latency player cannot do.
    expect(lowLatencyCues, containsAll(['swoop', 'dock', 'granted', 'tear']));
    expect(lowLatencyCues, isNot(contains('intro')));
    expect(lowLatencyCues, isNot(contains('board')));
    expect(onboardingCues, containsAll(lowLatencyCues));
    // Held decoded in memory: each a second or two, under 40 KB compressed.
    for (final cue in lowLatencyCues) {
      final bytes = File('assets/sounds/onboarding/$cue.m4a').lengthSync();
      expect(bytes, lessThan(40 * 1024), reason: cue);
    }
  });
}
