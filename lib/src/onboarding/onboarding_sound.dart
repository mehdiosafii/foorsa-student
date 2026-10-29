/// The onboarding's sounds (scripts/onboarding_sounds/compose.py): one family
/// of soft glass tones, air and paper, played the way a phone's own interface
/// sounds are. On an iPhone they use the ambient session, so the ring/silent
/// switch silences them and they never stop the student's music; on Android
/// they play as interface sounds and take no audio focus.
library;

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Plays a cue by name: `intro`, `step-1` … `step-6`, `granted`, `tap`,
/// `flap`, `tear`, `board`.
abstract class BoardingSounds {
  void play(String cue);
  void stop(String cue);
}

/// For tests, and for a phone the plugin cannot reach.
class SilentSounds implements BoardingSounds {
  const SilentSounds();
  @override
  void play(String cue) {}
  @override
  void stop(String cue) {}
}

const onboardingCues = <String>[
  'intro',
  'step-1',
  'step-2',
  'step-3',
  'step-4',
  'step-5',
  'step-6',
  'granted',
  'tap',
  'flap',
  'tear',
  'board',
];

/// The longest cue, so the last one is never cut off when the onboarding
/// lets go of its players.
const _longestCue = Duration(milliseconds: 6200);

class OnboardingSounds implements BoardingSounds {
  final Map<String, AudioPlayer> _players = {};
  Future<void>? _ready;
  bool _released = false;

  /// Loads every cue, the intro first, so the first one plays on time.
  Future<void> prepare() => _ready ??= _load();

  Future<void> _load() async {
    try {
      await AudioPlayer.global.setAudioContext(AudioContext(
        iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
        android: const AudioContextAndroid(
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.assistanceSonification,
          audioFocus: AndroidAudioFocus.none,
        ),
      ));
      for (final cue in onboardingCues) {
        final player = AudioPlayer(playerId: 'onboarding-$cue');
        // The long cues play on the media player, the short ones where
        // Android starts them soonest.
        final short = cue == 'tap' || cue == 'flap' || cue == 'tear';
        await player.setPlayerMode(
            short ? PlayerMode.lowLatency : PlayerMode.mediaPlayer);
        await player.setReleaseMode(ReleaseMode.stop);
        await player.setSource(AssetSource('sounds/onboarding/$cue.m4a'));
        _players[cue] = player;
      }
    } catch (error) {
      debugPrint('onboarding sounds unavailable: $error');
    }
  }

  @override
  void play(String cue) {
    if (_released) return;
    final player = _players[cue];
    if (player == null) {
      // Asked before it was loaded. The intro is timed to the picture, so
      // late it would be wrong; anything else plays as soon as it can.
      if (cue == 'intro') return;
      unawaited(prepare().then((_) {
        if (_players.containsKey(cue)) play(cue);
      }));
      return;
    }
    unawaited(() async {
      try {
        await player.stop();
        await player.resume();
      } catch (_) {}
    }());
  }

  @override
  void stop(String cue) {
    final player = _players[cue];
    if (player == null) return;
    unawaited(player.stop().catchError((_) {}));
  }

  /// Lets the players go once the last cue has had time to ring out, and
  /// gives the app back the session every iPhone app starts with.
  void release() {
    if (_released) return;
    _released = true;
    Timer(_longestCue, () async {
      for (final player in _players.values) {
        try {
          await player.dispose();
        } catch (_) {}
      }
      _players.clear();
      try {
        await AudioPlayer.global.setAudioContext(AudioContext(
          iOS: AudioContextIOS(category: AVAudioSessionCategory.soloAmbient),
          android: const AudioContextAndroid(),
        ));
      } catch (_) {}
    });
  }
}
