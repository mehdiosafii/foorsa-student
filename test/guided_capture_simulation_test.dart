// The Android guided camera, replayed on synthetic camera frames: a paper on
// a desk as the image stream hands it over (a landscape Y plane), with sensor
// noise and a hand's tremor, through exactly what the phone runs on each
// frame (ScanFrameProcessor, then GuidedFrameLoop), a frame every 250 ms.
//
// The owner, 31 Oct 2026, on an Android phone: "you still need to click the
// capture button". Replayed through the frame loop as it was then (box per
// cell: one pixel; outline: the guide's four straight borders only), a page
// turned by 8°, a page on a white desk and a page held close never fired, and
// one filling the screen fired after 8.5 s; with sensor noise and a hand's
// tremor the page never read as steady. These pin that each now fires within
// a few seconds, and that what must not fire (no page, a page running off the
// frame, the wrong paper) still does not.
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/guided_scanner/live_text_reader.dart';
import 'package:foorsa_student/src/guided_scanner/scan_document_profile.dart';
import 'package:foorsa_student/src/guided_scanner/scan_frame_loop.dart';
import 'package:foorsa_student/src/guided_scanner/scan_frame_processor.dart';
import 'package:foorsa_student/src/guided_scanner/scan_text_reading.dart';

import 'support/camera_scene.dart';

/// The 4:3 frame the camera streams at its maximum photo resolution, shown
/// whole: the view is the frame.
const sensorWidth = 1440;
const sensorHeight = 1080;
const viewAspect = sensorHeight / sensorWidth;

/// A reader that finds the page's printed lines inside the crop it is handed,
/// as ML Kit does when they are sharp enough; [machineLines] are added at the
/// bottom of the page (a passport's two lines).
LiveTextReadResult fakeRead(ScanFrameWork work, SensorFrames frames, {List<String> machineLines = const []}) {
  final crop = work.textCrop!;
  final region = work.wholeView ? scanWholeViewRegion : work.analysis.bounds!;
  final page = ScanTextGeometry.bounds(crop.page)!;
  Offset toCrop(double x, double y) => Offset(
        page.minX + (x - region.left) / region.width * page.width,
        page.minY + (region.bottom - y) / region.height * page.height,
      );
  final w = crop.readingWidth.toDouble(), h = crop.readingHeight.toDouble();
  final lines = <LiveTextLine>[];
  void add(Rect box, String text) {
    final a = toCrop(box.left, box.bottom), b = toCrop(box.right, box.top);
    final minX = a.dx.clamp(0.0, 1.0), maxX = b.dx.clamp(0.0, 1.0);
    final minY = a.dy.clamp(0.0, 1.0), maxY = b.dy.clamp(0.0, 1.0);
    if (maxX - minX < 0.01 || maxY - minY < 0.002) return;
    final p = ScanQuarterTurn.apply(crop.quarterTurns, math.Point(minX, minY));
    final q = ScanQuarterTurn.apply(crop.quarterTurns, math.Point(maxX, maxY));
    lines.add(LiveTextLine(text, math.min(p.x, q.x) * w, (1 - math.max(p.y, q.y)) * h,
        math.max(p.x, q.x) * w, (1 - math.min(p.y, q.y)) * h));
  }
  for (final line in frames.textLines()) {
    add(line, 'Releve de notes annee universitaire');
  }
  final scenePage = frames.scene.page;
  for (var i = 0; i < machineLines.length; i++) {
    final top = scenePage.top + scenePage.height * (0.80 + i * 0.07);
    add(Rect.fromLTRB(scenePage.left + scenePage.width * 0.05, top,
        scenePage.right - scenePage.width * 0.05, top + scenePage.height * 0.05), machineLines[i]);
  }
  return LiveTextReadResult(LiveTextReadStatus.read, lines);
}

class Run {
  Run(this.firedAt, this.outlined, this.frames);
  final Duration? firedAt;
  final int outlined;
  final int frames;
}

/// Frames every 250 ms for [seconds]; a read the loop asks for comes back
/// [readTakes] later (ML Kit on a cheap phone), or never with no reader.
Run replay(GuidedDocumentProfile profile, CameraScene scene, {
  double noise = 4,
  double tremor = 1.2,
  double seconds = 9,
  bool reader = true,
  Duration readTakes = const Duration(milliseconds: 700),
  List<String> machineLines = const [],
}) {
  final frames = SensorFrames(scene, noise: noise, tremor: tremor, viewportAspect: viewAspect,
      sensorWidth: sensorWidth, sensorHeight: sensorHeight);
  final processor = ScanFrameProcessor();
  final loop = GuidedFrameLoop(profile, canReadText: reader);
  final start = DateTime.utc(2026, 10, 31, 12);
  ({DateTime at, ScanFrameWork work, int epoch})? pending;
  var outlined = 0;
  final count = (seconds * 4).round();
  for (var i = 0; i < count; i++) {
    final now = start.add(Duration(milliseconds: 250 * i));
    final done = pending;
    if (done != null && !now.isBefore(done.at)) {
      loop.textFinished(fakeRead(done.work, frames, machineLines: machineLines), done.work.textCrop!,
          epoch: done.epoch, took: readTakes, wholeView: done.work.wholeView, now: now);
      pending = null;
    }
    final due = loop.textReadDue(now);
    final work = processor.process(ScanFrameJob(
      plane: frames.nextPlane(), profile: profile, viewportAspect: viewAspect,
      readText: due, readWholeView: due, turns: loop.reading.turnPolicy,
    ))!;
    if (work.analysis.bounds != null) outlined++;
    final fire = loop.observe(work.analysis, now);
    if (work.textCrop != null) {
      loop.textStarted(now, wholeView: work.wholeView);
      pending = (at: now.add(readTakes), work: work, epoch: loop.textEpoch);
    }
    if (fire) return Run(now.difference(start), outlined, i + 1);
  }
  return Run(null, outlined, count);
}

Rect around(Rect guide, double scale, {double dx = 0, double dy = 0}) => Rect.fromCenter(
    center: guide.center.translate(dx, dy), width: guide.width * scale, height: guide.height * scale);

void main() {
  final transcript = GuidedDocumentProfile.fromPortal({'documentKey': 'transcript'});
  final passport = GuidedDocumentProfile.fromPortal({'documentKey': 'identity'});
  final card = GuidedDocumentProfile.fromPortal({'documentKey': 'parent_id'});
  final a4 = transcript.guide(viewAspect);
  final dataPage = passport.guide(viewAspect);
  final cardGuide = card.guide(viewAspect);

  group('takes the page by itself, within a few seconds', () {
    final cases = <String, (GuidedDocumentProfile, CameraScene, double)>{
      'a page on the guide, held by a shaky hand on a noisy sensor': (transcript, CameraScene(page: a4), 3),
      'a page turned 8°': (transcript, CameraScene(page: a4, tiltDegrees: 8), 3.5),
      'a page turned 15°, off centre': (transcript, CameraScene(page: around(a4, 0.85, dx: 0.04, dy: 0.03), tiltDegrees: -15), 3.5),
      'a page held closer than the guide (90% of the frame\'s height)': (transcript, CameraScene(page: around(a4, 0.9 / a4.height, dy: 0.03)), 3.5),
      'a page at 60% of the width': (transcript, CameraScene(page: around(a4, 0.6 / a4.width)), 3.5),
      'a page on a light wooden desk': (transcript, CameraScene(page: a4, background: 170, backgroundTexture: 14), 3.5),
      'a page on a white desk (no outline: found by its text)': (transcript, CameraScene(page: around(a4, 0.9), background: 212), 4.5),
      'a page in a dim room': (transcript, CameraScene(page: a4, paper: 140, ink: 35, background: 45), 3.5),
      'a page under a hand\'s shadow': (transcript, CameraScene(page: a4, shadow: 0.4), 3.5),
      'a passport\'s photo page': (passport, CameraScene(page: dataPage), 4),
      // Both pages of the booklet in view, the photo page below the fold.
      'an open passport, turned 6°': (passport, CameraScene(
          page: Rect.fromCenter(center: const Offset(0.5, 0.5), width: 0.62, height: 0.62 * viewAspect / (88 / 125)),
          foldAt: 0.5, foldShade: 30, tiltDegrees: 6), 4),
      'an ID card on a light desk': (card, CameraScene(page: cardGuide, background: 175), 4),
    };
    cases.forEach((name, value) {
      test(name, () {
        final (profile, scene, within) = value;
        final run = replay(profile, scene, noise: name.contains('dim') ? 9 : 4);
        expect(run.firedAt, isNotNull, reason: '$name never fired in ${run.frames} frames (outlined ${run.outlined})');
        expect(run.firedAt!.inMilliseconds, lessThanOrEqualTo((within * 1000).round()), reason: name);
      });
    });
  });

  test('a phone without a text reader still takes a page it can outline', () {
    final run = replay(transcript, CameraScene(page: a4, tiltDegrees: 6), reader: false);
    expect(run.firedAt, isNotNull);
    expect(run.firedAt!.inMilliseconds, lessThanOrEqualTo(3500));
  });

  test('nothing is taken with no page in view', () {
    final run = replay(transcript, const CameraScene(page: Rect.fromLTWH(2, 2, 0.1, 0.1)));
    expect(run.firedAt, isNull);
    expect(run.outlined, 0);
  });

  test('a page running off the frame is not taken', () {
    final run = replay(transcript, CameraScene(page: Rect.fromCenter(center: const Offset(0.5, 0.5), width: 1.1, height: 1.0)));
    expect(run.firedAt, isNull);
  });

  test('a page held so close its text runs off the white desk\'s frame is not taken', () {
    final run = replay(transcript, CameraScene(
        page: Rect.fromCenter(center: const Offset(0.5, 0.5), width: 1.25, height: 0.95), background: 212));
    expect(run.firedAt, isNull);
  });

  test('a passport shown in a diploma\'s step is held for the student to act', () {
    final diploma = GuidedDocumentProfile.fromPortal({'documentKey': 'highest_degree'});
    final run = replay(diploma, CameraScene(page: diploma.guide(viewAspect)), machineLines: const [
      'P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<',
      'L898902C36UTO7408122F1204159ZE184226B<<<<<10',
    ]);
    expect(run.firedAt, isNull);
  });

  test('a passport whose two lines read is taken as soon as it is steady', () {
    final run = replay(passport, CameraScene(page: dataPage), machineLines: const [
      'P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<',
      'L898902C36UTO7408122F1204159ZE184226B<<<<<10',
    ], readTakes: const Duration(milliseconds: 300));
    expect(run.firedAt, isNotNull);
    expect(run.firedAt!.inMilliseconds, lessThanOrEqualTo(2500));
  });

  test('a cell is the average of its pixels, so noise and tremor leave a held page steady', () {
    final frames = SensorFrames(CameraScene(page: a4), noise: 6, tremor: 1.5, viewportAspect: viewAspect,
        sensorWidth: sensorWidth, sensorHeight: sensorHeight);
    final processor = ScanFrameProcessor();
    final motions = <double>[];
    for (var i = 0; i < 12; i++) {
      final work = processor.process(ScanFrameJob(plane: frames.nextPlane(), profile: transcript, viewportAspect: viewAspect))!;
      if (work.analysis.motion.isFinite) motions.add(work.analysis.motion);
    }
    motions.sort();
    // One pixel a cell, compared cell by cell, read 17.5 here: above the 10
    // under which a page is held, so a hand-held page never read as steady.
    expect(motions[motions.length ~/ 2], lessThan(10));
  });

  test('a frame\'s work stays small: the grid and the outline in a few milliseconds', () {
    final frames = SensorFrames(CameraScene(page: a4, tiltDegrees: 9), viewportAspect: viewAspect,
        sensorWidth: sensorWidth, sensorHeight: sensorHeight);
    final processor = ScanFrameProcessor();
    final plane = frames.nextPlane();
    for (var i = 0; i < 5; i++) {
      processor.process(ScanFrameJob(plane: plane, profile: transcript, viewportAspect: viewAspect));
    }
    final watch = Stopwatch()..start();
    for (var i = 0; i < 20; i++) {
      processor.process(ScanFrameJob(plane: plane, profile: transcript, viewportAspect: viewAspect));
    }
    final perFrame = watch.elapsedMicroseconds / 20 / 1000;
    // ignore: avoid_print
    print('frame work: ${perFrame.toStringAsFixed(2)} ms a frame');
    expect(perFrame, lessThan(40));
  });
}
