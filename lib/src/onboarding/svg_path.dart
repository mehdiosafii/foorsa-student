/// SVG path data as Flutter paths, so the shell draws the portal's own
/// vectors (the فرصة wordmark, the F mark, the journey's airliner and the
/// lucide icons) from the same strings instead of from pictures of them.
///
/// Covers what those strings use: M L H V C S Q T A Z, absolute and relative,
/// with implicit repeats. Parsed once and kept.
library;

import 'dart:ui';

final Map<String, Path> _cache = <String, Path>{};

/// The path [data] describes, parsed once per string.
Path svgPath(String data) => _cache.putIfAbsent(data, () => parseSvgPath(data));

/// Parses SVG path data. Unknown commands end the path where they start, so a
/// bad string draws less rather than throwing during a frame.
Path parseSvgPath(String data) {
  final path = Path();
  final tokens = _Tokens(data);
  try {
    _parse(path, tokens);
  } on FormatException {
    // Draw what was readable.
  }
  return path;
}

void _parse(Path path, _Tokens tokens) {
  var command = '';
  var current = Offset.zero;
  var start = Offset.zero;
  // The last control point, for the smooth curves (S, T).
  Offset? cubicControl;
  Offset? quadControl;

  while (tokens.more) {
    final next = tokens.command();
    if (next != null) {
      command = next;
    } else if (command.isEmpty) {
      break;
    }
    final relative = command == command.toLowerCase();
    final base = relative ? current : Offset.zero;
    Offset point() => Offset(tokens.number(), tokens.number()) + base;

    switch (command.toUpperCase()) {
      case 'M':
        current = point();
        start = current;
        path.moveTo(current.dx, current.dy);
        // Pairs after a moveto are linetos.
        command = relative ? 'l' : 'L';
        cubicControl = quadControl = null;
      case 'L':
        current = point();
        path.lineTo(current.dx, current.dy);
        cubicControl = quadControl = null;
      case 'H':
        current =
            Offset(tokens.number() + (relative ? current.dx : 0), current.dy);
        path.lineTo(current.dx, current.dy);
        cubicControl = quadControl = null;
      case 'V':
        current =
            Offset(current.dx, tokens.number() + (relative ? current.dy : 0));
        path.lineTo(current.dx, current.dy);
        cubicControl = quadControl = null;
      case 'C':
        final c1 = point();
        final c2 = point();
        final end = point();
        path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, end.dx, end.dy);
        cubicControl = c2;
        quadControl = null;
        current = end;
      case 'S':
        final c1 = cubicControl == null ? current : current * 2 - cubicControl;
        final c2 = point();
        final end = point();
        path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, end.dx, end.dy);
        cubicControl = c2;
        quadControl = null;
        current = end;
      case 'Q':
        final c = point();
        final end = point();
        path.quadraticBezierTo(c.dx, c.dy, end.dx, end.dy);
        quadControl = c;
        cubicControl = null;
        current = end;
      case 'T':
        final c = quadControl == null ? current : current * 2 - quadControl;
        final end = point();
        path.quadraticBezierTo(c.dx, c.dy, end.dx, end.dy);
        quadControl = c;
        cubicControl = null;
        current = end;
      case 'A':
        final rx = tokens.number().abs();
        final ry = tokens.number().abs();
        final rotation = tokens.number();
        final largeArc = tokens.flag();
        final sweep = tokens.flag();
        final end = point();
        if (rx == 0 || ry == 0) {
          path.lineTo(end.dx, end.dy);
        } else {
          path.arcToPoint(end,
              radius: Radius.elliptical(rx, ry),
              rotation: rotation,
              largeArc: largeArc,
              clockwise: sweep);
        }
        cubicControl = quadControl = null;
        current = end;
      case 'Z':
        path.close();
        current = start;
        cubicControl = quadControl = null;
        // Z takes no numbers; a number after it starts nothing.
        command = '';
      default:
        return;
    }
  }
}

class _Tokens {
  _Tokens(this._s);
  static const _commands = 'MmLlHhVvCcSsQqTtAaZz';
  final String _s;
  int _i = 0;

  bool get more {
    _skip();
    return _i < _s.length;
  }

  void _skip() {
    while (_i < _s.length) {
      final c = _s.codeUnitAt(_i);
      // space, tab, newline, carriage return, comma
      if (c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x2C) {
        _i++;
      } else {
        break;
      }
    }
  }

  String? command() {
    _skip();
    if (_i >= _s.length) return null;
    final c = _s[_i];
    if (_commands.contains(c)) {
      _i++;
      return c;
    }
    return null;
  }

  /// An arc flag: a single 0 or 1, which SVG lets touch the next number.
  bool flag() {
    _skip();
    if (_i >= _s.length) throw const FormatException('flag');
    final c = _s[_i];
    _i++;
    return c == '1';
  }

  double number() {
    _skip();
    final begin = _i;
    if (_i < _s.length && (_s[_i] == '-' || _s[_i] == '+')) _i++;
    var dot = false;
    var exponent = false;
    while (_i < _s.length) {
      final c = _s[_i];
      if (c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39) {
        _i++;
      } else if (c == '.' && !dot && !exponent) {
        dot = true;
        _i++;
      } else if ((c == 'e' || c == 'E') && !exponent) {
        exponent = true;
        _i++;
        if (_i < _s.length && (_s[_i] == '-' || _s[_i] == '+')) _i++;
      } else {
        break;
      }
    }
    final value = double.tryParse(_s.substring(begin, _i));
    if (value == null) throw const FormatException('number');
    return value;
  }
}
