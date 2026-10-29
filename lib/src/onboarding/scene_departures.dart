/// The welcome: one line of a departures board, large, flipping through the
/// sixteen cities of the portal's China voyage (PORTAL_EXPLORER_CITIES), with
/// its reflection on the floor of the stage. It changes by itself every few
/// seconds, and a tap flips it to the next one.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'boarding_style.dart';
import 'split_flap.dart';

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
  const DeparturesScene({super.key, required this.still, required this.feel});
  final bool still;
  final Feel feel;

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
    const length = 9;
    const gap = 4.0;
    return LayoutBuilder(builder: (context, constraints) {
      final cell =
          math.min(36.0, (constraints.maxWidth - (length - 1) * gap) / length);
      final height = cell * 1.44;
      Widget line() => SplitFlapLine(
            text: _centred(_cities[_index], length),
            length: length,
            cellWidth: cell,
            cellHeight: height,
            gap: gap,
            fontSize: height * 0.56,
            weight: FontWeight.w600,
            color: Boarding.heading,
            tileTop: const Color(0xFF1A2737),
            tileBottom: const Color(0xFF162231),
            still: widget.still,
            seed: _index,
          );
      return Semantics(
        button: true,
        label: 'Next departure, ${_cities[_index]}',
        hint: 'Tap for the next city',
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            widget.feel('press');
            _next();
            _schedule();
          },
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('NEXT DEPARTURE', style: Boarding.caption()),
              const SizedBox(height: 18),
              line(),
              const SizedBox(height: 3),
              // The floor of the stage: the board again, upside down, fading.
              SizedBox(
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
            ]),
          ),
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
