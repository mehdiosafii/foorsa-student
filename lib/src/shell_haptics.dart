/// The portal's sense of touch, played natively.
///
/// The web sends `FoorsaShellHaptic` with a texture name from the admission
/// reveal (`admissionFeedback.ts` in the portal): the seal pressed and
/// cracking, a flap standing up and landing, paper grain, the letter slipping
/// free and arriving. On Android each name becomes a crafted vibration
/// (`ShellHaptics.kt`: haptic primitives, the system's tuned effects, or an
/// amplitude waveform, whichever the phone supports). On iOS it becomes a
/// short sequence of Taptic impacts.
///
/// Anything else — the portal's ordinary buttons send a number — keeps the
/// light tick it has always had.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

class ShellHaptics {
  ShellHaptics({MethodChannel? channel, bool? android})
    : _channel = channel ?? const MethodChannel('foorsa/haptics'),
      _android = android ?? Platform.isAndroid;

  final MethodChannel _channel;
  final bool _android;
  bool _nativeMissing = false;

  /// The textures the reveal knows. Kept in step with `Touch` in
  /// admissionFeedback.ts; a name missing here plays as an ordinary tap.
  static const Set<String> textures = <String>{
    'press',
    'crack',
    'detent',
    'land',
    'grain',
    'release',
    'arrive',
  };

  /// The texture a bridge argument names; `select` for anything else.
  static String touchFrom(Object? arg) =>
      arg is String && textures.contains(arg) ? arg : 'select';

  /// Plays one touch. Never throws: feedback must not break the page.
  Future<void> play(Object? arg) async {
    final touch = touchFrom(arg);
    if (touch == 'select') {
      await _impact(HapticFeedback.lightImpact);
      return;
    }
    if (_android && !_nativeMissing) {
      try {
        if (await _channel.invokeMethod<bool>('play', touch) == true) return;
      } on MissingPluginException {
        _nativeMissing = true;
      } catch (_) {
        // Fall through to the system impacts.
      }
    }
    await _impacts(touch);
  }

  /// Taptic sequences for iOS, and Android's fallback. The gaps follow the
  /// sound: the seal's two fractures, the chime's two bells.
  Future<void> _impacts(String touch) async {
    switch (touch) {
      case 'press':
        await _impact(HapticFeedback.lightImpact);
      case 'crack':
        await _impact(HapticFeedback.heavyImpact);
        await _after(26, HapticFeedback.lightImpact);
      case 'detent':
      case 'grain':
        await _impact(HapticFeedback.selectionClick);
      case 'land':
        await _impact(HapticFeedback.mediumImpact);
      case 'release':
        await _impact(HapticFeedback.lightImpact);
        await _after(60, HapticFeedback.selectionClick);
      case 'arrive':
        await _impact(HapticFeedback.mediumImpact);
        await _after(130, HapticFeedback.heavyImpact);
    }
  }

  Future<void> _after(int ms, Future<void> Function() impact) async {
    await Future<void>.delayed(Duration(milliseconds: ms));
    await _impact(impact);
  }

  Future<void> _impact(Future<void> Function() impact) async {
    try {
      await impact();
    } catch (_) {
      // Best effort.
    }
  }
}
