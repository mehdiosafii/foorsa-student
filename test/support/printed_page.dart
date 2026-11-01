// Synthetic print for the scanner's sharpness tests: rows of glyph-like
// strokes in both directions, as a document's text has, and the two ways a
// still goes soft (focus that missed, a hand that moved). Nothing personal.
import 'dart:math' as math;
import 'dart:typed_data';

/// A page of print as the phone samples it (about 900 px across the middle of
/// a 12 MP still): rows of glyph-like strokes, 2 to 3 pixels wide, ink on
/// paper, with sensor noise. Synthetic, nothing personal.
({Uint8List luma, int width, int height}) printedPage({
  int width = 900, int height = 675, int paper = 228, int ink = 42, double noise = 3, int seed = 7,
}) {
  final random = math.Random(seed);
  final field = Float64List(width * height)..fillRange(0, width * height, paper.toDouble());
  for (var line = 40; line < height - 30; line += 26) {
    var x = 30;
    while (x < width - 40) {
      final glyph = 8 + random.nextInt(9);
      final stroke = 2 + random.nextInt(2);
      for (var k = 0; k < 3; k++) {
        final gx = x + random.nextInt(glyph);
        final vertical = random.nextBool();
        final length = 6 + random.nextInt(9);
        for (var t = 0; t < length; t++) {
          for (var w = 0; w < stroke; w++) {
            final px = vertical ? gx + w : gx + t;
            final py = vertical ? line + t : line + 6 + w;
            if (px >= 0 && py >= 0 && px < width && py < height) field[py * width + px] = ink.toDouble();
          }
        }
      }
      x += glyph + 3 + (random.nextInt(5) == 0 ? 10 : 0);
    }
  }
  final luma = Uint8List(width * height);
  for (var i = 0; i < field.length; i++) {
    final n = (random.nextDouble() + random.nextDouble() + random.nextDouble() - 1.5) * 2 * noise;
    luma[i] = (field[i] + n).round().clamp(0, 255);
  }
  return (luma: luma, width: width, height: height);
}

/// A Gaussian blur (focus that missed).
Uint8List gaussian(Uint8List src, int width, int height, double sigma) {
  final radius = (sigma * 3).ceil();
  final kernel = [for (var i = -radius; i <= radius; i++) math.exp(-(i * i) / (2 * sigma * sigma))];
  final total = kernel.reduce((a, b) => a + b);
  final pass = Float64List(width * height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      var sum = 0.0;
      for (var k = -radius; k <= radius; k++) {
        sum += src[y * width + (x + k).clamp(0, width - 1)] * kernel[k + radius];
      }
      pass[y * width + x] = sum / total;
    }
  }
  final out = Uint8List(width * height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      var sum = 0.0;
      for (var k = -radius; k <= radius; k++) {
        sum += pass[(y + k).clamp(0, height - 1) * width + x] * kernel[k + radius];
      }
      out[y * width + x] = (sum / total).round().clamp(0, 255);
    }
  }
  return out;
}

/// A hand that moved during the exposure: a streak [length] pixels long.
Uint8List streak(Uint8List src, int width, int height, int length, {bool vertical = false}) {
  final out = Uint8List(width * height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      var sum = 0;
      for (var k = 0; k < length; k++) {
        final px = vertical ? x : (x + k).clamp(0, width - 1);
        final py = vertical ? (y + k).clamp(0, height - 1) : y;
        sum += src[py * width + px];
      }
      out[y * width + x] = sum ~/ length;
    }
  }
  return out;
}

