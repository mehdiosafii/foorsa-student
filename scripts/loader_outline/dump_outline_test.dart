// Writes the arrow-to-plane morph's outlines for the portal's loader
// (foorsa-reward src/portal/flightLoaderOutline.ts), so the web and the app
// morph the same shapes point for point. The arrow is centred and 100 units
// tall; the plane rests on the same origin, turned up and to the right.
//
//   flutter test scripts/loader_outline/dump_outline_test.dart
//
// Not part of `flutter test`: it writes a file.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/onboarding/takeoff_intro.dart';

/// Every second point: the web draws the outline as a polygon and the
/// shapes are mostly straight edges, so half the points read the same.
List<double> _flat(List<Offset> points) => [
      for (var i = 0; i < points.length; i += 2) ...[
        (points[i].dx * 10).roundToDouble() / 10,
        (points[i].dy * 10).roundToDouble() / 10,
      ],
    ];

void main() {
  test('dumps the loader outlines', () {
    final morphs = [
      for (final m in takeoffMorphs) {'from': _flat(m.from), 'to': _flat(m.to)},
    ];
    File('build/loader_outline.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode(morphs));
  });
}
