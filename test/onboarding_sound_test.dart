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
}
