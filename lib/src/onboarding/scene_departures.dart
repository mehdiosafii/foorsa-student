/// The welcome: one line of a departures board, large, flipping through the
/// sixteen cities of the portal's China voyage (PORTAL_EXPLORER_CITIES), with
/// its reflection on the floor of the stage. It changes by itself every few
/// seconds, and a tap flips it to the next one.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'boarding_style.dart';
import 'glass.dart';
import 'split_flap.dart';
import 'stage_forms.dart';

const _cities = <String>[
  'BEIJING',
  'SHANGHAI',
  'HANGZHOU',
  'NANJING',
  'WUHAN',
  'CHANGSHA',
  'GUANGZHOU',
  'SHENZHEN',
  'XIAMEN',
  'CHENGDU',
  'CHONGQING',
  'KUNMING',
  "XI'AN",
  'TIANJIN',
  'QINGDAO',
  'HARBIN',
];

class DeparturesScene extends StatefulWidget {
  const DeparturesScene(
      {super.key, required this.still, required this.feel, this.onFlip});
  final bool still;
  final Feel feel;

  /// The board turns over by the student's hand (and once as it appears):
  /// its sound.
  final VoidCallback? onFlip;

  @override
  State<DeparturesScene> createState() => _DeparturesSceneState();
}

class _DeparturesSceneState extends State<DeparturesScene> {
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _schedule();
    widget.onFlip?.call();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 3800), (_) => _next());
  }

  void _next() {
    if (!mounted) return;
    setState(() => _index = (_index + 1) % _cities.length);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final cell = boardCell(constraints.maxWidth);
      final height = cell * 1.44;
      Widget line() => SplitFlapLine(
            text: _centred(_cities[_index], boardCells),
            length: boardCells,
            cellWidth: cell,
            cellHeight: height,
            gap: boardGap,
            fontSize: height * 0.56,
            weight: FontWeight.w600,
            color: Boarding.heading,
            tileTop: const Color(0xFF1A2737),
            tileBottom: const Color(0xFF162231),
            still: widget.still,
            seed: _index,
          );
      // The line sits in the stage's middle, where the transitions leave it;
      // its caption above it and its reflection below.
      return Semantics(
        button: true,
        label: 'Next departure, ${_cities[_index]}',
        hint: 'Tap for the next city',
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            widget.feel('press');
            widget.onFlip?.call();
            _next();
            _schedule();
          },
          child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                // The flaps sit in a glass case, the portal's pane.
                SizedBox(
                  width: boardWidth(constraints.maxWidth) + boardCase * 2,
                  height: height + boardCase * 2,
                  child: GlassPane(
                      glass: Glass.pane, radius: height * 0.13 + boardCase),
                ),
                line(),
                Transform.translate(
                  offset: Offset(0, -(height / 2 + boardCase + 24)),
                  child: Text('NEXT DEPARTURE', style: Boarding.caption()),
                ),
                Transform.translate(
                  offset: Offset(0, height / 2 + boardCase + 6 + height * 0.31),
                  // The floor of the stage: the board again, upside down,
                  // fading.
                  child: SizedBox(
                    height: height * 0.62,
                    child: ClipRect(
                      child: OverflowBox(
                        alignment: Alignment.topCenter,
                        maxHeight: height,
                        child: ShaderMask(
                          shaderCallback: (rect) => const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x2EFFFFFF), Color(0x00FFFFFF)],
                            stops: [0, 0.62],
                          ).createShader(rect),
                          blendMode: BlendMode.dstIn,
                          child: Transform.flip(flipY: true, child: line()),
                        ),
                      ),
                    ),
                  ),
                ),
              ]),
        ),
      );
    });
  }
}

/// A word in the middle of the board, the way a short city sits on a real one.
String _centred(String word, int length) {
  final pad = math.max(0, length - word.length) ~/ 2;
  return (' ' * pad + word).padRight(length);
}
