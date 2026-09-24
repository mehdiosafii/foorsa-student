// Made with Flicker · flicker.laurie.fyi
//
// The Foorsa loading animation: a 7x7 pixel grid whose lit dots trace a
// looping path. Used wherever the shell waits on something (file preview
// fetch, native download). Frame-driven — no implicit animations — so it
// costs one setState every 150ms and nothing on the raster thread.
import 'dart:async';

import 'package:flutter/material.dart';

class FlickerSpinner extends StatefulWidget {
  final double size;

  /// Lit / unlit dot colours. Defaults match the original artwork; a light
  /// surface can override them without forking the widget.
  final Color onColor;
  final Color offColor;

  const FlickerSpinner({
    super.key,
    this.size = 28.0,
    this.onColor = const Color(0xFFF5F5F5),
    this.offColor = const Color(0xFF404040),
  });

  @override
  State<FlickerSpinner> createState() => _FlickerSpinnerState();
}

class _FlickerSpinnerState extends State<FlickerSpinner> {
  Timer? _timer;
  int _frame = 0;

  static const List<List<bool>> grids = [
    [false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, true, false, false, false, false, false, false],
    [false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, true, true, false, false, false, false, false, true, true, false, false, false, false, false],
    [false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, true, true, true, false, false, false, false, false, true, true, false, false, false, false, true, false, true, false, false, false, false],
    [false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, true, true, true, true, false, false, false, false, false, true, true, false, false, false, false, true, false, true, false, false, false, true, false, false, true, false, false, false],
    [false, false, false, false, false, false, false, false, false, false, false, false, false, false, true, true, true, true, true, false, false, false, false, false, true, true, false, false, false, false, true, false, true, false, false, false, true, false, false, true, false, false, true, false, false, false, true, false, false],
    [false, false, false, false, false, false, false, false, true, true, true, true, true, false, false, false, false, true, true, true, false, false, false, false, true, true, true, false, false, true, true, false, false, true, false, false, true, true, false, false, true, false, true, false, false, false, false, false, false],
    [false, false, true, true, true, true, true, false, false, false, false, true, true, true, false, false, false, false, true, true, true, false, false, true, true, false, false, true, false, false, true, true, false, false, true, true, true, false, false, false, false, false, true, true, false, false, false, false, false],
    [false, false, false, false, false, true, true, false, false, false, false, false, true, true, false, false, false, true, true, false, false, false, false, false, true, true, false, false, false, true, true, false, false, false, false, false, true, true, false, false, false, false, false, false, false, false, false, false, false],
    [false, false, false, false, false, true, true, false, false, false, false, true, true, true, false, false, false, false, true, true, false, false, false, true, true, false, false, false, false, false, true, true, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false],
    [false, false, false, false, false, true, true, false, false, false, false, true, true, true, false, false, false, true, true, true, false, false, false, false, true, true, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false],
    [false, false, false, false, true, true, true, false, false, false, false, true, true, true, false, false, false, false, true, true, true, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false],
    [false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, true, true, true, false, false, false, false, true, true, true, false, false, false, false, true, true, true, false, false, false, false, false, false, false, false, false, false, false, false, false, false],
    [false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, true, true, true, false, false, false, false, true, true, true, false, false, false, false, true, true, true],
    [false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, true, true, true, false, false, false, false, true, true, true, false, false, false, false, true, true, true, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false],
    [false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, true, true, true, false, false, false, false, true, true, true, false, false, false, false, true, true, true, false, false],
    [false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, true, true, true, false, false, false, false, true, true, true, false, false, false, false, true, true, true, false, false, false, false, false, false, false, false, false, false],
    [false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, true, true, false, false, false, false, false, true, true, false, false, false, false, false]
  ];

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(milliseconds: 150),
      (_) {
        if (!mounted) return;
        setState(() => _frame = (_frame + 1) % grids.length);
      },
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final grid = grids[MediaQuery.disableAnimationsOf(context) ? 0 : _frame];
    final spacing = widget.size / 20;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: GridView.count(
        crossAxisCount: 7,
        mainAxisSpacing: spacing,
        crossAxisSpacing: spacing,
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        children: List.generate(
          49,
          (i) => DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: grid[i] ? widget.onColor : widget.offColor,
            ),
          ),
        ),
      ),
    );
  }
}
