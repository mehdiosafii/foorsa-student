/// The welcome: a departures board flipping through the sixteen cities of the
/// portal's China voyage (PORTAL_EXPLORER_CITIES). It changes by itself every
/// few seconds, and a tap on it flips to the next one.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'boarding_style.dart';
import 'lucide.dart';
import 'split_flap.dart';

class _Departure {
  const _Departure(this.city, this.flight, this.gate);
  final String city;
  final String flight;
  final String gate;
}

const _departures = <_Departure>[
  _Departure('BEIJING', 'FS101', '04'),
  _Departure('SHANGHAI', 'FS214', '11'),
  _Departure('HANGZHOU', 'FS330', '07'),
  _Departure('NANJING', 'FS402', '02'),
  _Departure('WUHAN', 'FS518', '15'),
  _Departure('CHANGSHA', 'FS226', '09'),
  _Departure('GUANGZHOU', 'FS631', '12'),
  _Departure('SHENZHEN', 'FS705', '03'),
  _Departure('XIAMEN', 'FS812', '06'),
  _Departure('CHENGDU', 'FS109', '14'),
  _Departure('CHONGQING', 'FS927', '01'),
  _Departure('KUNMING', 'FS340', '08'),
  _Departure("XI'AN", 'FS455', '10'),
  _Departure('TIANJIN', 'FS263', '05'),
  _Departure('QINGDAO', 'FS586', '13'),
  _Departure('HARBIN', 'FS771', '16'),
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
  bool _tapped = false;
  late Timer _minute;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _schedule();
    _minute = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer.periodic(
        const Duration(milliseconds: 3600), (_) => _next(tapped: false));
  }

  void _next({required bool tapped}) {
    if (!mounted) return;
    setState(() {
      _index = (_index + 1) % _departures.length;
      _tapped = tapped;
    });
    if (tapped) {
      widget.feel('press');
      _schedule();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _minute.cancel();
    super.dispose();
  }

  String _clock(DateTime at) =>
      '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';

  String get _time => _clock(_now);

  /// The next departures down the board: the cities after this one, leaving
  /// every 25 minutes from the next five-minute mark.
  Widget _laterRow(int k, double inner) {
    final departure = _departures[(_index + k) % _departures.length];
    final base = _now.add(Duration(minutes: 5 - _now.minute % 5));
    final at = base.add(Duration(minutes: 25 * k + (_index % 3) * 5));
    const gap = 2.0, groupGap = 12.0;
    final cell = math.min(15.0, (inner - groupGap - 12 * gap - 70) / 14);
    return Opacity(
      opacity: 0.78,
      child: Row(children: [
        SplitFlapLine(
          text: _clock(at),
          length: 5,
          cellWidth: cell,
          cellHeight: cell * 1.42,
          gap: gap,
          still: widget.still,
          seed: _index * 7 + k * 13,
        ),
        const SizedBox(width: groupGap),
        SplitFlapLine(
          text: departure.city,
          length: 9,
          cellWidth: cell,
          cellHeight: cell * 1.42,
          gap: gap,
          still: widget.still,
          seed: _index * 11 + k * 17,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text('ON TIME',
                  style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                      color: Boarding.done.withValues(alpha: 0.85))),
            ),
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final departure = _departures[_index];
    // On a short screen the whole board scales down rather than spilling.
    return LayoutBuilder(
      builder: (context, outer) => Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(
            width: math.min(400.0, outer.maxWidth),
            child: Semantics(
              button: true,
              label:
                  'Departures board. Next departure to ${departure.city}. Tap for the next city.',
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _next(tapped: true),
                child: NightGlass(
                  deep: true,
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                  child: LayoutBuilder(builder: (context, constraints) {
                    final inner = constraints.maxWidth;
                    const big = 9, bigGap = 3.0;
                    final bigCell =
                        math.min(32.0, (inner - (big - 1) * bigGap) / big);
                    // FLIGHT (5) + GATE (2) + STATUS (8), two gaps between groups.
                    const smallGap = 2.0, groupGap = 14.0;
                    final smallCell = math.min(
                        16.5, (inner - 2 * groupGap - 12 * smallGap) / 15);
                    final smallHeight = smallCell * 1.46;
                    Widget label(String text) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(text,
                              style: const TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1.3,
                                  color: Boarding.faint)),
                        );
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(children: [
                          Transform.rotate(
                            angle: -math.pi / 5,
                            child: const Lucide(LucideIcons.plane,
                                size: 15, color: Boarding.accent),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text('DEPARTURES',
                                maxLines: 1,
                                overflow: TextOverflow.fade,
                                softWrap: false,
                                style: Boarding.eyebrow
                                    .copyWith(color: Boarding.ink)),
                          ),
                          const SizedBox(width: 8),
                          const Text('出发',
                              style: TextStyle(
                                  fontSize: 12.5, color: Boarding.faint)),
                          const Spacer(),
                          Text(_time,
                              style:
                                  Boarding.monoStyle(13, color: Boarding.ink)),
                        ]),
                        const SizedBox(height: 12),
                        Container(height: 1, color: const Color(0x1FFFFFFF)),
                        const SizedBox(height: 14),
                        label('DESTINATION'),
                        SplitFlapLine(
                          text: departure.city,
                          length: big,
                          cellWidth: bigCell,
                          cellHeight: bigCell * 1.42,
                          gap: bigGap,
                          still: widget.still,
                          seed: _index,
                          onSettled: () {
                            if (_tapped) widget.feel('detent');
                          },
                        ),
                        const SizedBox(height: 16),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      label('FLIGHT'),
                                      SplitFlapLine(
                                        text: departure.flight,
                                        length: 5,
                                        cellWidth: smallCell,
                                        cellHeight: smallHeight,
                                        gap: smallGap,
                                        still: widget.still,
                                        seed: _index + 31,
                                      ),
                                    ]),
                                const SizedBox(width: groupGap),
                                Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      label('GATE'),
                                      SplitFlapLine(
                                        text: departure.gate,
                                        length: 2,
                                        cellWidth: smallCell,
                                        cellHeight: smallHeight,
                                        gap: smallGap,
                                        still: widget.still,
                                        seed: _index + 57,
                                      ),
                                    ]),
                                const SizedBox(width: groupGap),
                                Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(children: [
                                        label('STATUS'),
                                        const SizedBox(width: 6),
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 6),
                                          child: _Blink(still: widget.still),
                                        ),
                                      ]),
                                      SplitFlapLine(
                                        text: 'BOARDING',
                                        length: 8,
                                        cellWidth: smallCell,
                                        cellHeight: smallHeight,
                                        gap: smallGap,
                                        color: Boarding.wait,
                                        still: widget.still,
                                        seed: 91,
                                      ),
                                    ]),
                              ]),
                        ),
                        const SizedBox(height: 16),
                        Container(height: 1, color: const Color(0x14FFFFFF)),
                        const SizedBox(height: 12),
                        label('LATER'),
                        for (var k = 1; k <= 2; k++) ...[
                          if (k == 2) const SizedBox(height: 7),
                          _laterRow(k, inner),
                        ],
                      ],
                    );
                  }),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The amber lamp beside a flight that is boarding.
class _Blink extends StatefulWidget {
  const _Blink({required this.still});
  final bool still;

  @override
  State<_Blink> createState() => _BlinkState();
}

class _BlinkState extends State<_Blink> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void initState() {
    super.initState();
    if (!widget.still) _c.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: widget.still
          ? const AlwaysStoppedAnimation(1)
          : Tween(begin: 0.25, end: 1.0).animate(_c),
      child: Container(
        width: 6,
        height: 6,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Boarding.wait,
          boxShadow: [BoxShadow(color: Color(0x99FCD34D), blurRadius: 6)],
        ),
      ),
    );
  }
}
