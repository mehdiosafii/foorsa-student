/// The portal's sense of touch, played natively.
///
/// The web sends `FoorsaShellHaptic` with a texture name from the admission
/// reveal (`admissionFeedback.ts` in the portal) and, for the grain, how far
/// the letter has been pulled: a heartbeat while it waits, the seal pressed
/// and cracking, the flaps unfolding and landing, paper grain, the letter
/// slipping free and arriving. On Android each name becomes a strong
/// amplitude waveform (`ShellHaptics.kt`) played as media vibration, so the
/// touch-feedback switch that silences keyboard ticks cannot silence it. On
/// iOS it becomes a short sequence of Taptic impacts.
///
/// The web learns that this build plays textures from
/// `FoorsaShellCapabilities`; builds without it get their one light tick in
/// the pattern's rhythm instead. Anything else — the portal's ordinary buttons
/// send a number — keeps the light tick it has always had.
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

  /// What `FoorsaShellCapabilities` answers.
  static const Map<String, Object> capabilities = <String, Object>{
    'hapticTextures': 2,
  };

  /// The textures the reveal knows. Kept in step with `Touch` in
  /// admissionFeedback.ts; a name missing here plays as an ordinary tap.
  static const Set<String> textures = <String>{
    'heartbeat',
    'press',
    'crack',
    'detent',
    'unfold',
    'land',
    'grain',
    'release',
    'arrive',
  };

  /// The texture a bridge argument names; `select` for anything else.
  static String touchFrom(Object? arg) =>
      arg is String && textures.contains(arg) ? arg : 'select';

  /// How far along the pull is, 0–1; anything unreadable counts as full.
  static double levelFrom(Object? arg) =>
      arg is num ? arg.toDouble().clamp(0.0, 1.0) : 1.0;

  /// Plays one touch. Never throws: feedback must not break the page.
  Future<void> play(Object? arg, [Object? levelArg]) async {
    final touch = touchFrom(arg);
    if (touch == 'select') {
      await _impact(HapticFeedback.lightImpact);
      return;
    }
    final level = levelFrom(levelArg);
    if (_android && !_nativeMissing) {
      try {
        final played = await _channel.invokeMethod<bool>('play', {
          'touch': touch,
          'level': level,
        });
        if (played == true) return;
      } on MissingPluginException {
        _nativeMissing = true;
      } catch (_) {
        // Fall through to the system impacts.
      }
    }
    await _impacts(touch, level);
  }

  /// Taptic sequences for iOS, and Android's fallback. The gaps follow the
  /// music: the seal's two fractures, and the arrival's downbeat and the
  /// melody's first three notes (0, 625, 937 and 1250 ms).
  Future<void> _impacts(String touch, double level) async {
    switch (touch) {
      case 'heartbeat':
        await _impact(HapticFeedback.heavyImpact);
        await _after(175, HapticFeedback.mediumImpact);
      case 'press':
        await _impact(HapticFeedback.lightImpact);
      case 'crack':
        await _impact(HapticFeedback.heavyImpact);
        await _after(26, HapticFeedback.lightImpact);
      case 'detent':
        await _impact(HapticFeedback.selectionClick);
      case 'unfold':
        await _impact(HapticFeedback.lightImpact);
        await _after(90, HapticFeedback.lightImpact);
        await _after(90, HapticFeedback.mediumImpact);
      case 'land':
        await _impact(HapticFeedback.mediumImpact);
      case 'grain':
        await _impact(
          level < 0.5
              ? HapticFeedback.selectionClick
              : HapticFeedback.lightImpact,
        );
      case 'release':
        await _impact(HapticFeedback.lightImpact);
        await _after(60, HapticFeedback.mediumImpact);
      case 'arrive':
        await _impact(HapticFeedback.heavyImpact);
        await _after(625, HapticFeedback.lightImpact);
        await _after(312, HapticFeedback.lightImpact);
        await _after(313, HapticFeedback.mediumImpact);
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
