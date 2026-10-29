/// Tracking (App Tracking Transparency): what allowing it would mean, drawn
/// plainly. An ad, Foorsa learning that the ad is how this student came, more
/// students like them reached; and what never happens. Shown only when the
/// build asks to track (onboarding_config.dart).
library;

import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'boarding_style.dart';
import 'lucide.dart';

class TrackingScene extends StatefulWidget {
  const TrackingScene({super.key, required this.still});
  final bool still;

  @override
  State<TrackingScene> createState() => _TrackingSceneState();
}

class _TrackingSceneState extends State<TrackingScene>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker =
      createTicker((e) => _t.value = e.inMicroseconds / 1e6);
  final ValueNotifier<double> _t = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    if (widget.still) {
      _t.value = 5;
    } else {
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _t.dispose();
    super.dispose();
  }

  double _in(double t, double at) =>
      (1 - math.exp(-7 * ((t - at) / 0.5).clamp(0.0, 1.0))).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          'An ad, then Foorsa, then more students. Your papers and messages are never part of it.',
      excludeSemantics: true,
      // On a short screen the diagram scales down rather than spilling.
      child: LayoutBuilder(
        builder: (context, outer) => Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: SizedBox(
              width: math.min(400.0, outer.maxWidth),
              child: ValueListenableBuilder<double>(
                valueListenable: _t,
                builder: (context, t, _) {
                  Widget step(double at, Widget child) {
                    final a = widget.still ? 1.0 : _in(t, at);
                    return Opacity(
                        opacity: a,
                        child: Transform.translate(
                            offset: Offset(0, 10 * (1 - a)), child: child));
                  }

                  return Column(mainAxisSize: MainAxisSize.min, children: [
                    step(0.1, const _AdCard()),
                    _Flow(t: t, still: widget.still, height: 30),
                    step(
                        0.45,
                        const _Node(
                          icon: null,
                          title: 'Foorsa sees which ad it was',
                          detail: 'Not who you are, not what you send.',
                        )),
                    _Flow(t: t + 0.6, still: widget.still, height: 30),
                    step(
                        0.8,
                        const _Node(
                          icon: LucideIcons.graduationCap,
                          title: 'More students like you',
                          detail: 'Foorsa reaches them where you were.',
                        )),
                    const SizedBox(height: 16),
                    step(
                        1.15,
                        NightGlass(
                          radius: 20,
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                          child: const Column(children: [
                            _Promise(
                                icon: LucideIcons.shieldCheck,
                                text:
                                    'Your papers and messages are never part of it.'),
                            SizedBox(height: 9),
                            _Promise(
                                icon: LucideIcons.lock,
                                text:
                                    'Foorsa never sells your personal information.'),
                          ]),
                        )),
                  ]);
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AdCard extends StatelessWidget {
  const _AdCard();

  @override
  Widget build(BuildContext context) {
    return NightGlass(
      deep: true,
      radius: 20,
      padding: const EdgeInsets.all(10),
      child: Row(children: [
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2B557D), Color(0xFF13263D)],
            ),
          ),
          alignment: Alignment.center,
          child: Transform.rotate(
            angle: -math.pi / 5,
            child: const Lucide(LucideIcons.plane,
                size: 26, color: Boarding.accent, strokeWidth: 1.6),
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  Lucide(LucideIcons.megaphone,
                      size: 13, color: Boarding.faint, strokeWidth: 2.2),
                  SizedBox(width: 5),
                  Text('An ad you saw',
                      style: TextStyle(
                          fontSize: 11,
                          color: Boarding.faint,
                          letterSpacing: 0.2)),
                ]),
                SizedBox(height: 3),
                Text('Study in China with Foorsa',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Boarding.heading)),
                SizedBox(height: 1),
                Text('On another app or website',
                    style: TextStyle(fontSize: 12, color: Boarding.muted)),
              ]),
        ),
      ]),
    );
  }
}

class _Node extends StatelessWidget {
  const _Node({required this.icon, required this.title, required this.detail});
  final LucideGlyph? icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Boarding.accentSoft,
          border: Border.all(color: const Color(0x29A9C8E6)),
        ),
        child: icon == null
            ? Image.asset('assets/icons/app_icon_ios.png',
                fit: BoxFit.cover, filterQuality: FilterQuality.medium)
            : Lucide(icon!, size: 21, color: Boarding.accent),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: Boarding.heading)),
          const SizedBox(height: 1),
          Text(detail,
              style: const TextStyle(fontSize: 12.5, color: Boarding.muted)),
        ]),
      ),
    ]);
  }
}

/// The dotted link between two steps, dots travelling down it.
class _Flow extends StatelessWidget {
  const _Flow({required this.t, required this.still, required this.height});
  final double t;
  final bool still;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: 21),
          child: CustomPaint(
              size: Size(2, height), painter: _FlowPainter(still ? 0 : t)),
        ),
      ),
    );
  }
}

class _FlowPainter extends CustomPainter {
  _FlowPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final dot = Paint()..color = const Color(0x40A9C8E6);
    for (var y = 3.0; y < size.height; y += 6) {
      canvas.drawCircle(Offset(1, y), 1, dot);
    }
    final travel = (t * 0.9) % 1;
    canvas.drawCircle(
        Offset(1, travel * size.height), 2.4, Paint()..color = Boarding.accent);
    canvas.drawCircle(
        Offset(1, travel * size.height),
        6,
        Paint()
          ..color = Boarding.accent.withValues(alpha: 0.2)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
  }

  @override
  bool shouldRepaint(_FlowPainter old) => old.t != t;
}

class _Promise extends StatelessWidget {
  const _Promise({required this.icon, required this.text});
  final LucideGlyph icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Lucide(icon, size: 17, color: Boarding.done, strokeWidth: 2.1),
      const SizedBox(width: 10),
      Expanded(
          child: Text(text,
              style: const TextStyle(
                  fontSize: 13, height: 1.3, color: Boarding.ink))),
    ]);
  }
}
