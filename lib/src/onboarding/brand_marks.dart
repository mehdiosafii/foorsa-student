/// The wordmark and the F mark as widgets, painted from the portal's vectors
/// (brand_vectors.dart), sharp at every size and in any colour.
library;

import 'package:flutter/widgets.dart';

import 'brand_vectors.dart';
import 'svg_path.dart';

/// فرصة, [height] tall, in [color] (Foorsa navy on light, white on dark).
class FoorsaWordmark extends StatelessWidget {
  const FoorsaWordmark(
      {super.key,
      required this.height,
      this.color = const Color(foorsaNavyValue)});
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Foorsa',
      image: true,
      child: SizedBox(
        height: height,
        width: height * 2032 / 643,
        child: CustomPaint(
            painter: _VectorPainter(
                foorsaWordmarkPath, const Size(2032, 643), color)),
      ),
    );
  }
}

/// The F mark, [size] square.
class FoorsaMark extends StatelessWidget {
  const FoorsaMark(
      {super.key,
      required this.size,
      this.color = const Color(foorsaNavyValue)});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
          painter: _VectorPainter(foorsaMarkPath, const Size(757, 757), color)),
    );
  }
}

class _VectorPainter extends CustomPainter {
  _VectorPainter(this.data, this.box, this.color);
  final String data;
  final Size box;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / box.width, size.height / box.height);
    canvas.drawPath(svgPath(data), Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_VectorPainter old) =>
      old.data != data || old.color != color;
}
