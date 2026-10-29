/// The onboarding's sounds (scripts/onboarding_sounds/compose.py): one family
/// of glass tones, air and paper, and a soft bed of night music under the
/// steps.
///
/// They are meant to be heard. The first version used iOS's ambient session,
/// which the ring/silent switch silences, and Android's interface-sound
/// stream, which most phones keep near zero, and students heard nothing. So
/// they play as media: on an iPhone the playback session, mixed with whatever
/// else is playing (never stopping the student's music), and on Android the
/// media stream. The speaker in the onboarding's corner turns them off, and
/// nothing plays while the app is in the background.
library;

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';

/// Plays a cue by name (see [onboardingCues]).
abstract class BoardingSounds {
  const BoardingSounds();

  void play(String cue);
  void stop(String cue);

  /// The night's music under the steps, from the welcome until boarding.
  void startBed() {}

  /// Boarding: the music fades as the onboarding does.
  void endBed() {}

  /// The student turned the sound off (the speaker in the corner).
  bool get muted => false;
  set muted(bool value) {}
}

/// For tests, and for a phone the plugin cannot reach.
class SilentSounds extends BoardingSounds {
  const SilentSounds();
  @override
  void play(String cue) {}
  @override
  void stop(String cue) {}
}

const onboardingCues = <String>[
  'intro',
  'tap',
  'takeoff',
  'swoop',
  'dock',
  'park',
  'granted',
  'flap',
  'tear',
  'board',
  'step-1',
  'step-2',
  'step-3',
  'step-4',
  'step-5',
  'step-6',
];

/// The short ones, where Android starts a sound soonest.
const _quick = {'tap', 'park', 'flap'};

/// The longest cue, so the last one is never cut off when the onboarding
/// lets go of its players.
const _longestCue = Duration(milliseconds: 6500);

/// The bed: a 40 s piece that fades in and out over its first and last 4 s,
/// so a second copy started 36 s in crossfades into the first.
const _bedLength = Duration(seconds: 40);
const _bedOverlap = Duration(seconds: 4);
const _bedVolume = 0.75;

/// The intro is timed to the picture: later than this it is not played.
const _introPatience = Duration(milliseconds: 1400);

class OnboardingSounds extends BoardingSounds with WidgetsBindingObserver {
  final Map<String, AudioPlayer> _players = {};
  final List<AudioPlayer> _beds = [];
  Future<void>? _loading;
  final Completer<void> _introReady = Completer<void>();
  bool _released = false;
  bool _muted = false;
  bool _away = false;

  /// Whether the bed should be playing (it may be held by mute or by the
  /// app being away).
  bool _bedWanted = false;
  int _bedTurn = 0;
  Timer? _bedCycle;
  Timer? _bedFade;
  Stopwatch? _introAsked;

  /// Starts loading, the intro first; completes once the intro can play (the
  /// rest keep loading behind it).
  Future<void> prepare() {
    _loading ??= _load();
    return _introReady.future;
  }

  Future<void> _load() async {
    try {
      WidgetsBinding.instance.addObserver(this);
      await AudioPlayer.global.setAudioContext(AudioContext(
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: const {AVAudioSessionOptions.mixWithOthers},
        ),
        android: const AudioContextAndroid(
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.media,
          audioFocus: AndroidAudioFocus.none,
        ),
      ));
      for (final cue in onboardingCues) {
        if (_released) break;
        final player = AudioPlayer(playerId: 'onboarding-$cue');
        await player.setPlayerMode(
            _quick.contains(cue) ? PlayerMode.lowLatency : PlayerMode.mediaPlayer);
        await player.setReleaseMode(ReleaseMode.stop);
        await player.setSource(AssetSource('sounds/onboarding/$cue.m4a'));
        _players[cue] = player;
        if (cue == 'intro') {
          if (!_introReady.isCompleted) _introReady.complete();
          _lateIntro(player);
        }
      }
      for (final side in ['a', 'b']) {
        if (_released) break;
        final bed = AudioPlayer(playerId: 'onboarding-bed-$side');
        await bed.setReleaseMode(ReleaseMode.stop);
        await bed.setSource(AssetSource('sounds/onboarding/bed.m4a'));
        _beds.add(bed);
      }
      if (_bedWanted) _resumeBed();
    } catch (error) {
      debugPrint('onboarding sounds unavailable: $error');
    } finally {
      if (!_introReady.isCompleted) _introReady.complete();
    }
  }

  /// The intro was asked for before it had loaded: it starts now, as far in
  /// as the picture already is, unless that is too late to mean anything.
  void _lateIntro(AudioPlayer player) {
    final asked = _introAsked;
    if (asked == null || _muted || _away) return;
    final late = asked.elapsed;
    if (late > _introPatience) return;
    unawaited(() async {
      try {
        await player.seek(late);
        await player.resume();
      } catch (_) {}
    }());
  }

  @override
  bool get muted => _muted;

  @override
  set muted(bool value) {
    if (_muted == value) return;
    _muted = value;
    if (value) {
      for (final player in _players.values) {
        unawaited(player.stop().catchError((_) {}));
      }
      _holdBed(fade: const Duration(milliseconds: 300));
    } else if (_bedWanted) {
      _resumeBed();
    }
  }

  @override
  void play(String cue) {
    if (_released || _muted || _away) return;
    final player = _players[cue];
    if (player == null) {
      if (cue == 'intro') {
        _introAsked = Stopwatch()..start();
        return;
      }
      // Asked before it was loaded: it plays as soon as it can.
      unawaited(prepare().then((_) => _loading).then((_) {
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
    if (cue == 'intro') _introAsked = null;
    final player = _players[cue];
    if (player == null) return;
    unawaited(player.stop().catchError((_) {}));
  }

  @override
  void startBed() {
    if (_released || _bedWanted) return;
    _bedWanted = true;
    _resumeBed();
  }

  @override
  void endBed() {
    _bedWanted = false;
    _holdBed(fade: const Duration(milliseconds: 1200));
  }

  /// Starts a copy of the bed, and the next one where this one starts to
  /// fade.
  void _resumeBed() {
    if (_beds.length < 2 || _muted || _away || _released || !_bedWanted) {
      return;
    }
    _bedCycle?.cancel();
    _bedFade?.cancel();
    void next() {
      if (!_bedWanted || _muted || _away) return;
      final bed = _beds[_bedTurn++ % 2];
      unawaited(() async {
        try {
          await bed.stop();
          await bed.setVolume(_bedVolume);
          await bed.resume();
        } catch (_) {}
      }());
    }

    next();
    _bedCycle = Timer.periodic(_bedLength - _bedOverlap, (_) => next());
  }

  /// Fades the bed out over [fade] and stops it.
  void _holdBed({required Duration fade}) {
    _bedCycle?.cancel();
    _bedCycle = null;
    _bedFade?.cancel();
    if (_beds.isEmpty) return;
    const step = Duration(milliseconds: 50);
    final steps = (fade.inMilliseconds / step.inMilliseconds).ceil();
    var k = 0;
    _bedFade = Timer.periodic(step, (timer) {
      k++;
      final v = _bedVolume * (1 - k / steps).clamp(0.0, 1.0);
      for (final bed in _beds) {
        unawaited(bed.setVolume(v).catchError((_) {}));
      }
      if (k >= steps) {
        timer.cancel();
        for (final bed in _beds) {
          unawaited(bed.stop().catchError((_) {}));
        }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The playback session would keep playing behind another app: it must
    // not. Only really away, though: a permission prompt makes the app
    // inactive (iOS) or paused-but-visible (Android's `inactive`), and the
    // music plays on under the prompt.
    final away = state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached;
    if (away == _away) return;
    _away = away;
    if (away) {
      for (final player in _players.values) {
        unawaited(player.stop().catchError((_) {}));
      }
      _holdBed(fade: const Duration(milliseconds: 100));
    } else if (_bedWanted) {
      _resumeBed();
    }
  }

  /// Lets the players go once the last cue has had time to ring out, and
  /// gives the app back the session every iPhone app starts with.
  void release() {
    if (_released) return;
    _released = true;
    _bedWanted = false;
    _holdBed(fade: const Duration(milliseconds: 1200));
    Timer(_longestCue, () async {
      WidgetsBinding.instance.removeObserver(this);
      _bedFade?.cancel();
      for (final player in [..._players.values, ..._beds]) {
        try {
          await player.dispose();
        } catch (_) {}
      }
      _players.clear();
      _beds.clear();
      try {
        await AudioPlayer.global.setAudioContext(AudioContext(
          iOS: AudioContextIOS(category: AVAudioSessionCategory.soloAmbient),
          android: const AudioContextAndroid(),
        ));
      } catch (_) {}
    });
  }
}
