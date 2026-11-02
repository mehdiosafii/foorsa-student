// What the student sees while the guided camera leads them to a good photo:
// each state of the instruction panel and the outline, rendered with real
// fonts and pinned as a golden image (test/goldens/scan_guidance_states.png).
// The outline's state reads from its pattern and the panel's icon, not from
// its colour alone: dashed while the page is looked for or has something to
// fix, solid while it is held, a check once the photo is in.
//
// Update after a deliberate change with:
//   flutter test --update-goldens test/scan_guidance_golden_test.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foorsa_student/src/guided_scanner/scan_coach.dart';
import 'package:foorsa_student/src/guided_scanner/scan_document_profile.dart';
import 'package:foorsa_student/src/guided_scanner/scan_guidance.dart';
import 'package:foorsa_student/src/guided_scanner/scan_guidance_view.dart';
import 'package:foorsa_student/src/guided_scanner/scan_text_reading.dart';

/// The fonts the phone draws with, from the Flutter SDK's own cache.
Future<bool> loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return false;
  final dir = Directory('$root/bin/cache/artifacts/material_fonts');
  if (!dir.existsSync()) return false;
  Future<ByteData> bytes(String name) async => ByteData.sublistView(await File('${dir.path}/$name').readAsBytes());
  final roboto = FontLoader('Roboto')
    ..addFont(bytes('Roboto-Regular.ttf'))
    ..addFont(bytes('Roboto-Medium.ttf'))
    ..addFont(bytes('Roboto-Bold.ttf'));
  await roboto.load();
  await (FontLoader('MaterialIcons')..addFont(bytes('MaterialIcons-Regular.otf'))).load();
  return true;
}

/// A golden that tolerates the last few anti-aliased pixels differing
/// between machines.
class TolerantComparator extends LocalFileComparator {
  TolerantComparator(super.testFile);

  static const tolerance = 0.005;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(imageBytes, await getGoldenBytes(golden));
    if (result.passed || result.diffPercent <= tolerance) {
      result.dispose();
      return true;
    }
    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}

/// A page on a desk, as the camera shows it.
class PagePainter extends CustomPainter {
  const PagePainter(this.corners, {this.shade = false});

  final List<Offset>? corners;
  final bool shade;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF3B342E));
    final quad = corners;
    if (quad == null) return;
    final points = [for (final c in quad) Offset(c.dx * size.width, c.dy * size.height)];
    final outline = Path()..addPolygon(points, true);
    canvas.save();
    canvas.clipPath(outline);
    canvas.drawPath(outline, Paint()..color = const Color(0xFFF1EFEA));
    final bounds = outline.getBounds();
    final ink = Paint()..color = const Color(0xFF9A9AA0);
    for (var y = bounds.top + bounds.height * 0.1; y < bounds.bottom - bounds.height * 0.08; y += 9) {
      canvas.drawRect(Rect.fromLTWH(bounds.left + bounds.width * 0.12, y, bounds.width * 0.7, 3), ink);
    }
    if (shade) {
      canvas.drawRect(Rect.fromLTWH(bounds.left, bounds.top, bounds.width * 0.45, bounds.height * 0.6),
          Paint()..color = const Color(0x88000000));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant PagePainter oldDelegate) => true;
}

class GuidanceState {
  const GuidanceState(this.guidance, {this.corners, this.progress, this.shade = false, this.profile});

  final ScanGuidance guidance;
  final List<Offset>? corners;
  final double? progress;
  final bool shade;
  final GuidedDocumentProfile? profile;
}

/// One phone's screen: the 3:4 preview with the outline over it, the panel
/// under it, as the guided camera lays them out.
Widget phone(GuidanceState state, GuidedDocumentProfile fallback) {
  final profile = state.profile ?? fallback;
  return SizedBox(
    width: 270,
    height: 560,
    child: Column(
      children: [
        const SizedBox(height: 36),
        SizedBox(
          width: 270,
          height: 360,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(painter: PagePainter(state.corners, shade: state.shade)),
              CustomPaint(
                painter: ScanGuidePainter(
                  guide: profile.guide(0.75),
                  state: state.guidance.state,
                  corners: state.corners,
                  zones: profile.guideZones,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
          child: ScanGuidancePanel(
            copy: state.guidance.copy,
            state: state.guidance.state,
            progress: state.progress,
          ),
        ),
      ],
    ),
  );
}

void main() {
  testWidgets('every state of the guidance, as drawn', (tester) async {
    final loaded = await tester.runAsync(loadFonts);
    if (loaded != true) {
      markTestSkipped('The Flutter SDK\'s fonts are not here.');
      return;
    }
    final previous = goldenFileComparator;
    goldenFileComparator = TolerantComparator(Uri.parse('${Directory.current.path}/test/scan_guidance_golden_test.dart'));
    addTearDown(() => goldenFileComparator = previous);

    final transcript = GuidedDocumentProfile.fromPortal({'documentKey': 'transcript'});
    final passport = GuidedDocumentProfile.fromPortal({'documentKey': 'identity'});
    final back = GuidedDocumentProfile.fromPortal({'documentKey': 'parent_id', 'side': 'back'});
    const square = [Offset(0.12, 0.08), Offset(0.88, 0.08), Offset(0.88, 0.9), Offset(0.12, 0.9)];
    const far = [Offset(0.36, 0.3), Offset(0.64, 0.3), Offset(0.64, 0.66), Offset(0.36, 0.66)];
    const slanted = [Offset(0.28, 0.1), Offset(0.72, 0.1), Offset(0.92, 0.9), Offset(0.08, 0.9)];
    ScanGuidance guide(ScanFrameAnalysis? analysis, {GuidedDocumentProfile? of, ScanTextGateStatus? reading}) =>
        scanGuidanceFor(analysis, reading, profile: of ?? transcript, aspect: 0.75);
    ScanFrameAnalysis frame(ScanHint hint, List<Offset> corners, {bool shadow = false}) => ScanFrameAnalysis(
          hint: hint, bounds: Rect.fromPoints(corners[0], corners[2]), edgeSupport: 1, motion: 2,
          brightness: 180, sharpness: 400, contrast: 120, corners: corners, shadow: shadow);
    final states = [
      GuidanceState(guide(null)),
      GuidanceState(guide(null, of: passport), profile: passport),
      GuidanceState(guide(null, of: back), profile: back),
      GuidanceState(guide(frame(ScanHint.moveCloser, far)), corners: far),
      GuidanceState(guide(frame(ScanHint.ready, slanted)), corners: slanted),
      GuidanceState(guide(frame(ScanHint.ready, square, shadow: true)), corners: square, shade: true),
      GuidanceState(guide(frame(ScanHint.ready, square), reading: ScanTextGateStatus.passedReading),
          corners: square, progress: 0.6),
      const GuidanceState(scanGuidanceDone, corners: square),
    ];
    expect([for (final state in states) state.guidance.copy.title], [
      'Find the page', 'Open the passport flat', 'Now the back', 'Move closer', 'Hold the phone flat',
      'Shadow on the page', 'Hold still', 'Got it',
    ]);

    tester.view.physicalSize = const Size(1080, 1120);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Roboto'),
      home: MediaQuery(
        data: const MediaQueryData(size: Size(1080, 1120), disableAnimations: true),
        // The camera's page is a Scaffold: its text takes the theme's face.
        child: Material(
          color: Colors.black,
          child: Wrap(
            key: const ValueKey('sheet'),
            children: [for (final state in states) phone(state, transcript)],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await expectLater(find.byKey(const ValueKey('sheet')), matchesGoldenFile('goldens/scan_guidance_states.png'));
  }, skip: !Platform.isLinux);

  testWidgets('at the largest text the panel says the short form, on the smallest phone', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const copies = [
      ScanTextCopy('Show the photo page', 'Show the photo page with the two lines at the bottom.', 'Two bottom lines.'),
      ScanTextCopy('Shadow on the page', 'Move your hand or the phone.', 'Avoid the shadow.'),
      ScanTextCopy('This looks like a different paper', 'Show the paper this step asks for.', 'Different paper.'),
    ];
    for (final copy in copies) {
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(320, 568), textScaler: TextScaler.linear(2)),
          child: Material(
            color: Colors.black,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: ScanGuidancePanel(copy: copy, state: ScanOutlineState.adjusting),
              ),
            ),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
      expect(find.text(copy.compact), findsOneWidget);
      expect(find.text(copy.detail), findsNothing);
      // A screen reader still hears the whole instruction.
      expect(find.bySemanticsLabel('${copy.title}. ${copy.compact}'), findsOneWidget);
    }
  });
}
