"""The onboarding's sounds, composed from nothing.

One family, so the whole onboarding sounds like one object: glass bells in
E major (the key the portal's admission score resolves to), air, paper, and
one soft bed of music under it all. Every cue is synthesized here with numpy,
through one synthetic hall, so there is nothing to license and nothing
sampled. Each file starts and ends in exact silence.

Phones play these through a speaker the size of a fingernail, which gives
nothing below about 300 Hz and favours 1 to 5 kHz. So every cue lives above
180 Hz, its bells carry their upper partials, and it is mastered loud: its
peaks a decibel or two under full scale, its transients held down so the
body of the sound comes up (v1 peaked at -13 dBFS and could not be heard).

    python3 scripts/onboarding_sounds/compose.py            # WAVs into build/
    python3 scripts/onboarding_sounds/compose.py --encode   # and the app's .m4a

The cues, and where the onboarding plays them (onboarding_page.dart):

  intro      the arrow catching the light, becoming the plane, its lights,
             its climb; started with the intro, timed to its beats
  tap        the runway pressed: a glass tick
  takeoff    the arrow rolling down the runway and lifting off (0.52 s)
  swoop      its flight up into the picture (0.6 s)
  dock       the moment it docks in the picture's arrow of light
  step-1..6  the picture unfolding as the next one, one note higher a step
  park       the next arrow rolling in to the gate
  granted    two rising notes when an access is turned on
  flap       the departures board turning over
  tear       the arrow cutting the stub off along the perforation
  board      the arrival chord as the sign-in opens
  bed        forty seconds of night music under the steps, looped by
             crossfading two players (onboarding_sound.dart)
"""

import os
import subprocess
import sys
import wave

import numpy as np

try:
    from scipy.signal import lfilter
except ImportError:  # pragma: no cover - the slow path still works
    lfilter = None

SR = 48000
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
BUILD = os.path.join(ROOT, 'build', 'onboarding_sounds')
ASSETS = os.path.join(ROOT, 'assets', 'sounds', 'onboarding')

# The intro's beats, in seconds (takeoff_intro.dart).
WAKE = 0.16
SHINE = 0.30
MORPH_STARTS = 0.85
MORPH_ENDS = 1.60
LIGHTS_ON = 1.95
CLIMB_STARTS = 2.42
INTRO_SECONDS = 3.4

# The runway (runway.dart, onboarding_page.dart).
DEPART = 0.52
LIFT_OFF = 0.41
SWOOP = 0.60
ZIP = 0.46

rng = np.random.default_rng(2026)


def hz(note):
    """'E5' -> 659.26 Hz."""
    names = {'C': -9, 'D': -7, 'E': -5, 'F': -4, 'G': -2, 'A': 0, 'B': 2}
    sharp = 1 if '#' in note else 0
    octave = int(note[-1])
    semis = names[note[0]] + sharp + (octave - 4) * 12
    return 440.0 * 2 ** (semis / 12)


def silence(seconds):
    return np.zeros((int(round(seconds * SR)), 2))


def stereo(sound, pan=0.0):
    if sound.ndim == 2:
        return sound
    left = np.cos((pan + 1) * np.pi / 4)
    right = np.sin((pan + 1) * np.pi / 4)
    return np.stack([sound * left, sound * right], axis=1) * np.sqrt(2)


def place(track, sound, at, gain=1.0, pan=0.0):
    """Mixes [sound] (mono or stereo) into [track] at [at] seconds."""
    sound = stereo(sound, pan)
    start = int(round(at * SR))
    end = min(len(track), start + len(sound))
    if end > start:
        track[start:end] += sound[: end - start] * gain
    return track


def envelope(n, attack, decay):
    t = np.arange(n) / SR
    rise = np.clip(t / max(attack, 1e-4), 0, 1)
    rise = 0.5 - 0.5 * np.cos(np.pi * rise)
    return rise * np.exp(-t / decay)


def one_pole(x, cutoff, high=False):
    a = np.exp(-2 * np.pi * cutoff / SR)
    if lfilter is not None:
        y = lfilter([1 - a], [1, -a], x, axis=0)
    else:
        y = np.empty_like(x)
        acc = np.zeros(x.shape[1:]) if x.ndim > 1 else 0.0
        for i in range(len(x)):
            acc = (1 - a) * x[i] + a * acc
            y[i] = acc
    return x - y if high else y


def lowpass(x, cutoff):
    """A gentle low-pass, 12 dB an octave."""
    return one_pole(one_pole(x, cutoff), cutoff)


def highpass(x, cutoff):
    """What a phone's speaker cannot play anyway, out (12 dB an octave)."""
    return one_pole(one_pole(x, cutoff, high=True), cutoff, high=True)


def bell(note, seconds=2.2, soft=1.0, bright=1.0):
    """A glass bell: a fundamental, its upper partials (which a phone's speaker
    plays best, so they are kept), a breath of strike. One voice, the same in
    both ears: a phone sums the two sides, and two detuned sides would beat.
    The hall gives it its width."""
    f = hz(note) if isinstance(note, str) else note
    n = int(seconds * SR)
    t = np.arange(n) / SR
    partials = [
        (1.0, 1.0, 1.25),
        (2.0, 0.42 * bright, 0.66),
        (3.0, 0.2 * bright, 0.42),
        (4.07, 0.12 * bright, 0.27),
        (5.92, 0.06 * bright, 0.15),
        (8.1, 0.025 * bright, 0.08),
    ]
    voice = np.zeros(n)
    for ratio, amp, decay in partials:
        freq = f * ratio
        if freq > SR / 2.4:
            continue
        voice += amp * np.sin(2 * np.pi * freq * t) * envelope(
            n, 0.003 * soft + 0.0015 * ratio, decay)
    strike_n = int(0.014 * SR)
    strike = lowpass(rng.standard_normal(strike_n), 6500) * envelope(
        strike_n, 0.0006, 0.0028)
    voice[:strike_n] += strike * 0.09 * bright
    tail = int(0.08 * SR)
    voice[-tail:] *= 0.5 + 0.5 * np.cos(np.linspace(0, np.pi, tail))
    return voice


def shaped_noise(seconds, centre, width, level, stereo_out=True):
    """Noise whose band follows [centre](t) and [width](t) (Hz) and whose
    level follows [level](t), by shaping overlapping spectra."""
    n = int(seconds * SR)
    frame, hop = 2048, 512
    window = np.hanning(frame)
    freqs = np.fft.rfftfreq(frame, 1 / SR)
    out = np.zeros((n + frame, 2))
    norm = np.zeros(n + frame)
    for start in range(0, n, hop):
        t = (start + frame / 2) / SR
        c, w, lv = centre(t), width(t), level(t)
        mask = np.exp(-0.5 * ((freqs - c) / max(w, 1)) ** 2) * lv
        for side in range(2 if stereo_out else 1):
            spectrum = np.fft.rfft(rng.standard_normal(frame) * window)
            out[start:start + frame, side] += np.fft.irfft(spectrum * mask) * window
        norm[start:start + frame] += window ** 2
    if not stereo_out:
        out[:, 1] = out[:, 0]
    return out[:n] / np.maximum(norm[:n, None], 1e-3)


def pan_sweep(x, start, end):
    pan = np.linspace(start, end, len(x))
    x[:, 0] *= np.cos((pan + 1) * np.pi / 4) * np.sqrt(2)
    x[:, 1] *= np.sin((pan + 1) * np.pi / 4) * np.sqrt(2)
    return x


_halls = {}


def hall(x, seconds=2.2, wet=0.26, predelay=0.018, dark=4200):
    """A synthetic hall: early reflections, then decorrelated noise dying
    away, darker as it goes. Convolved by FFT."""
    key = (seconds, predelay, dark)
    if key not in _halls:
        n = int(seconds * SR)
        t = np.arange(n) / SR
        ir = np.zeros((n, 2))
        local = np.random.default_rng(7)
        for side in range(2):
            tail = local.standard_normal(n) * np.exp(-6.9 * t / seconds)
            ir[:, side] = lowpass(tail, dark)
            ir[:, side] *= np.clip(t / 0.03, 0, 1)
        for k, delay in enumerate((0.007, 0.013, 0.021, 0.029, 0.041)):
            i = int((predelay + delay) * SR)
            ir[i, k % 2] += 0.5 / (k + 1)
        ir /= np.sqrt(np.sum(ir ** 2, axis=0, keepdims=True))
        _halls[key] = ir
    ir = _halls[key]
    n = len(ir)
    size = len(x) + n
    fft = 1 << (size - 1).bit_length()
    out = np.zeros((size, 2))
    for side in range(2):
        out[:, side] = np.fft.irfft(
            np.fft.rfft(x[:, side], fft) * np.fft.rfft(ir[:, side], fft), fft)[:size]
    dry = np.zeros((size, 2))
    dry[: len(x)] = x
    return dry * (1 - wet) + out * wet * 2.2


def fade_out(x, seconds):
    n = min(len(x), int(seconds * SR))
    ramp = 0.5 + 0.5 * np.cos(np.linspace(0, np.pi, n))
    x[-n:] *= ramp[:, None]
    return x


def compress(x, threshold_db=-18, ratio=3.0, attack=0.002, release=0.12):
    """Holds the transients down so the body of the sound can come up: a
    phone's speaker is judged by loudness, not by peaks."""
    level = np.max(np.abs(x), axis=1)
    a_att = np.exp(-1 / (attack * SR))
    a_rel = np.exp(-1 / (release * SR))
    env = np.empty_like(level)
    acc = 0.0
    # A peak follower: quick to rise, slow to fall.
    for i, v in enumerate(level):
        coef = a_att if v > acc else a_rel
        acc = coef * acc + (1 - coef) * v
        env[i] = acc
    db = 20 * np.log10(np.maximum(env, 1e-9))
    over = np.maximum(db - threshold_db, 0)
    gain = 10 ** (-over * (1 - 1 / ratio) / 20)
    return x * gain[:, None]


def master(x, peak_db, squeeze=True):
    """Above the speaker's floor, transients held, starting and ending in
    exact silence, its peak set."""
    x = highpass(x, 180)
    if squeeze:
        x = x / max(np.max(np.abs(x)), 1e-9)
        x = compress(x)
    loud = np.max(np.abs(x), axis=1)
    keep = np.nonzero(loud > 10 ** (-66 / 20) * np.max(loud))[0]
    end = min(len(x), keep[-1] + int(0.02 * SR)) if len(keep) else len(x)
    x = x[:end].copy()
    x = fade_out(x, min(0.25, len(x) / SR / 4))
    ramp = min(len(x), int(0.002 * SR))
    x[:ramp] *= np.linspace(0, 1, ramp)[:, None]
    x *= 10 ** (peak_db / 20) / max(np.max(np.abs(x)), 1e-9)
    x[0] = 0
    x[-1] = 0
    return x


def pad(notes, seconds, brightness, level):
    """A soft chord: each note a few pure partials, slightly chorused, the
    upper ones brought in by [brightness](t), the whole by [level](t)."""
    n = int(seconds * SR)
    t = np.arange(n) / SR
    bright = brightness(t)
    out = np.zeros((n, 2))
    for k, note in enumerate(notes):
        f = hz(note)
        for side, detune in ((0, -0.0012), (1, 0.0012)):
            g = f * (1 + detune * (1 if k % 2 else -1))
            phase = 0.7 * k + side
            v = np.sin(2 * np.pi * g * t + phase)
            v += 0.34 * bright * np.sin(2 * np.pi * 2 * g * t + 0.4 + phase)
            v += 0.14 * bright * np.sin(2 * np.pi * 3 * g * t + 1.1 + phase)
            out[:, side] += v
    return out / len(notes) * level(t)[:, None]


# The cues.


def compose_intro():
    track = silence(INTRO_SECONDS + 2.6)
    # The arrow wakes: a shimmer comes up as the light does.
    for k, note in enumerate(['E6', 'B6', 'E7']):
        place(track, bell(note, 1.6, soft=6, bright=0.5), WAKE + 0.06 * k,
              0.12 - 0.025 * k, pan=-0.3 + 0.3 * k)
    glint = shaped_noise(
        0.7, lambda t: 2600 + 5200 * min(t / 0.55, 1), lambda t: 700 + 900 * t,
        lambda t: np.sin(np.pi * min(t / 0.7, 1)) ** 2)
    place(track, pan_sweep(glint, -0.5, 0.5), SHINE - 0.05, 0.16)
    # The arrow becoming the plane: a chord swelling and opening up.
    swell_len = MORPH_ENDS - MORPH_STARTS + 1.6
    chord = pad(['E4', 'B4', 'E5', 'G#5'], swell_len,
                lambda t: np.clip((t - 0.1) / 0.8, 0, 1) ** 1.5,
                lambda t: np.clip(t / 0.75, 0, 1) ** 2 * np.exp(-np.clip(t - 0.75, 0, None) / 0.6))
    place(track, chord, MORPH_STARTS, 0.32)
    rush = shaped_noise(
        0.8, lambda t: 1200 + 2400 * t, lambda t: 600 + 800 * t,
        lambda t: np.sin(np.pi * min(t / 0.8, 1)) ** 2)
    place(track, rush, MORPH_STARTS, 0.1)
    # The plane is there: its chime.
    place(track, bell('E6', 2.6), MORPH_ENDS, 0.8, pan=0.1)
    place(track, bell('B6', 2.2, bright=0.7), MORPH_ENDS + 0.012, 0.32, pan=0.25)
    place(track, bell('G#5', 2.4, bright=0.6), MORPH_ENDS + 0.02, 0.22, pan=-0.2)
    # Its strobes: two tiny ticks.
    for k, at in enumerate((LIGHTS_ON, LIGHTS_ON + 0.14)):
        tick = bell(hz('E7') * 1.5, 0.12, soft=0.3, bright=0.3)
        place(track, tick, at, 0.12 - 0.03 * k, pan=0.5 if k else -0.5)
    # The climb: air rising and passing to the right, faster and faster.
    climb = INTRO_SECONDS - CLIMB_STARTS + 1.1

    def whoosh_level(t):
        u = np.clip(t / (climb - 1.1), 0, 1)
        return (u ** 1.4) * np.exp(-np.clip(t - (climb - 1.1), 0, None) / 0.38)

    jet = shaped_noise(climb, lambda t: 520 + 2900 * np.clip(t / (climb - 0.9), 0, 1) ** 1.6,
                       lambda t: 320 + 1400 * np.clip(t / climb, 0, 1), whoosh_level)
    place(track, pan_sweep(jet, -0.15, 0.85), CLIMB_STARTS - 0.12, 0.42)
    # And a last high bell as it goes out of sight.
    place(track, bell('E7', 1.6, bright=0.4), INTRO_SECONDS - 0.12, 0.1, pan=0.7)
    return master(hall(track, 2.4, wet=0.3), -1.5)


def compose_tap():
    n = int(0.09 * SR)
    t = np.arange(n) / SR
    # A glass tick: two short partials and a breath of click.
    tick = (np.sin(2 * np.pi * 2350 * t) + 0.5 * np.sin(2 * np.pi * 3720 * t)) * envelope(
        n, 0.0004, 0.011)
    click = lowpass(rng.standard_normal(n), 7000) * envelope(n, 0.0002, 0.0015)
    x = stereo(tick + 0.4 * click)
    return master(hall(x, 0.4, wet=0.12), -9, squeeze=False)


def compose_takeoff():
    """The roll down the runway, faster and faster, and the lift."""
    track = silence(DEPART + 1.2)
    roll = shaped_noise(
        DEPART + 0.05,
        lambda t: 700 + 2600 * min(t / DEPART, 1) ** 2,
        lambda t: 300 + 900 * min(t / DEPART, 1),
        lambda t: min(t / DEPART, 1) ** 1.6 * (1 if t < DEPART else 0.4))
    place(track, pan_sweep(roll, -0.45, 0.55), 0.0, 0.5)
    # A soft whirr, rising with the speed.
    n = int((DEPART + 0.05) * SR)
    t = np.arange(n) / SR
    glide = 340 * (1 + 1.6 * np.clip(t / DEPART, 0, 1) ** 2)
    whirr = np.sin(2 * np.pi * np.cumsum(glide) / SR) * np.clip(t / DEPART, 0, 1) ** 2
    whirr *= np.exp(-np.clip(t - DEPART, 0, None) / 0.05)
    place(track, whirr, 0.0, 0.08, pan=0.2)
    # The lift: air flicked upwards, and a high glint.
    lift = shaped_noise(
        0.45, lambda t: 2400 + 6000 * min(t / 0.3, 1), lambda t: 900 + 1500 * t,
        lambda t: np.exp(-((t - 0.09) / 0.07) ** 2))
    place(track, lift, LIFT_OFF - 0.06, 0.55, pan=0.5)
    place(track, bell('B6', 1.2, bright=0.6), LIFT_OFF + 0.02, 0.22, pan=0.55)
    return master(hall(track, 1.4, wet=0.22), -3)


def compose_swoop():
    """Its flight into the picture: air passing, from the right to the middle."""
    track = silence(SWOOP + 1.0)
    air = shaped_noise(
        SWOOP + 0.2,
        lambda t: 1300 + 2600 * np.sin(np.pi * min(t / SWOOP, 1)) ** 1.2,
        lambda t: 700 + 900 * np.sin(np.pi * min(t / SWOOP, 1)),
        lambda t: np.sin(np.pi * min(t / (SWOOP + 0.1), 1)) ** 1.5)
    place(track, pan_sweep(air, 0.6, -0.05), 0.0, 0.6)
    return master(hall(track, 1.2, wet=0.24), -5)


def compose_dock():
    """It docks: the picture is the arrow, and it rings like glass."""
    track = silence(2.8)
    for k, note in enumerate(['E6', 'G#6', 'B6']):
        place(track, bell(note, 2.4, bright=1.2), k * 0.022, 0.62 - 0.12 * k,
              pan=-0.2 + 0.2 * k)
    # A sparkle on top.
    for k, note in enumerate(['E7', 'B7', 'G#7']):
        place(track, bell(note, 0.9, soft=0.5, bright=0.3), 0.05 + 0.045 * k,
              0.1, pan=0.4 - 0.4 * k)
    glint = shaped_noise(0.5, lambda t: 6200, lambda t: 1800,
                         lambda t: np.exp(-t / 0.08))
    place(track, glint, 0.0, 0.12)
    return master(hall(track, 2.2, wet=0.3), -1.5)


STEP_NOTES = ['E5', 'F#5', 'G#5', 'B5', 'C#6', 'E6']
STEP_CHORDS = [
    ['E4', 'B4', 'G#5'], ['F#4', 'C#5', 'A5'], ['G#4', 'B4', 'E5'],
    ['B4', 'D#5', 'F#5'], ['C#5', 'E5', 'A5'], ['E5', 'G#5', 'B5'],
]


def compose_step(index):
    """The picture unfolding as the next: its note, a breath of chord."""
    track = silence(2.6)
    note = STEP_NOTES[index - 1]
    place(track, bell(note, 2.2, bright=1.1), 0.0, 0.7)
    place(track, bell(hz(note) * 1.5, 1.2, bright=0.5), 0.03, 0.14, pan=0.35)
    chord = pad(STEP_CHORDS[index - 1], 2.0,
                lambda t: 0.3 + 0.3 * np.clip(t / 0.6, 0, 1),
                lambda t: np.clip(t / 0.35, 0, 1) * np.exp(-np.clip(t - 0.35, 0, None) / 0.55))
    place(track, chord, 0.0, 0.22)
    bloom = shaped_noise(0.6, lambda t: 2200 - 900 * t, lambda t: 900,
                         lambda t: np.sin(np.pi * min(t / 0.6, 1)) ** 2)
    place(track, bloom, 0.0, 0.06)
    return master(hall(track, 2.0, wet=0.28), -3)


def compose_park():
    """The next arrow comes to a stop at the gate: a soft glass tock."""
    track = silence(0.6)
    n = int(0.12 * SR)
    t = np.arange(n) / SR
    tock = (np.sin(2 * np.pi * 1180 * t) + 0.4 * np.sin(2 * np.pi * 2510 * t)) * envelope(
        n, 0.0006, 0.018)
    place(track, tock, 0.0, 1.0, pan=-0.4)
    return master(hall(track, 0.6, wet=0.18), -7, squeeze=False)


def compose_granted():
    track = silence(2.4)
    place(track, bell('B5', 1.6, bright=1.1), 0.0, 0.7, pan=-0.15)
    place(track, bell('E6', 2.0, bright=1.1), 0.11, 0.8, pan=0.15)
    place(track, bell('B6', 1.2, bright=0.5), 0.2, 0.18, pan=0.4)
    return master(hall(track, 1.8, wet=0.26), -1.5)


def compose_flap():
    """The board turning over: nine flaps, each falling through a few letters."""
    track = silence(1.2)
    grain_n = int(0.006 * SR)
    for cell in range(9):
        start = cell * 0.036 + rng.uniform(0, 0.05)
        steps = 5 + int(rng.integers(0, 6))
        step = 0.058 + rng.uniform(0, 0.018)
        for k in range(steps):
            tone = 2200 + rng.uniform(-500, 700)
            t = np.arange(grain_n) / SR
            grain = (np.sin(2 * np.pi * tone * t) * 0.4 + rng.standard_normal(grain_n)) * envelope(
                grain_n, 0.0002, 0.0011)
            grain = lowpass(grain, 6500)
            last = k == steps - 1
            place(track, grain, start + k * step, (0.6 if last else 0.32) * (0.85 + 0.3 * rng.uniform()),
                  pan=-0.6 + cell * 0.15)
    return master(hall(track, 0.9, wet=0.18), -2)


def compose_tear():
    """The arrow cutting along the perforation: a run of small rips that
    follow it across, and the stub's soft give."""
    track = silence(ZIP + 0.8)
    at = 0.0
    while at < ZIP:
        n = int(rng.uniform(0.004, 0.012) * SR)
        rip = rng.standard_normal(n) * envelope(n, 0.0005, n / SR / 3)
        rip = highpass(rip, 900)
        speed = np.sin(np.pi * min(at / ZIP, 1))
        place(track, rip, at, 0.35 + 0.45 * speed, pan=-0.6 + 1.2 * at / ZIP)
        at += rng.uniform(0.006, 0.016) / (0.6 + 0.6 * speed)
    give = shaped_noise(0.3, lambda t: 1000, lambda t: 600, lambda t: np.exp(-t / 0.07))
    place(track, give, ZIP - 0.02, 0.35, pan=0.5)
    return master(hall(track, 0.8, wet=0.14), -2)


def compose_board():
    """Welcome aboard: the arrival chord, rolled up, with a soft swell."""
    track = silence(4.4)
    notes = ['E4', 'B4', 'E5', 'F#5', 'G#5', 'B5', 'E6']
    for k, note in enumerate(notes):
        place(track, bell(note, 3.2, bright=1.0), k * 0.055, 0.42 if k < 3 else 0.36,
              pan=-0.5 + k / (len(notes) - 1))
    chord = pad(['E4', 'B4', 'E5', 'G#5', 'B5'], 3.8,
                lambda t: 0.3 + 0.4 * np.clip(t / 1.2, 0, 1),
                lambda t: np.clip(t / 0.5, 0, 1) * np.exp(-np.clip(t - 0.5, 0, None) / 1.2))
    place(track, chord, 0.05, 0.3)
    return master(hall(track, 2.8, wet=0.34), -1.5)


BED_SECONDS = 40.0
BED_FADE = 4.0


def compose_bed():
    """The night under the steps: a slow pad through E major's chords, and
    a glass note now and then. Voiced high enough for a phone to play, and
    kept well under the cues."""
    track = silence(BED_SECONDS)
    chords = [
        ['E4', 'B4', 'E5', 'G#5'],
        ['C#4', 'G#4', 'C#5', 'E5'],
        ['A3', 'E4', 'A4', 'C#5', 'E5'],
        ['B3', 'F#4', 'B4', 'D#5', 'F#5'],
    ]
    span = BED_SECONDS / len(chords)
    for k, chord in enumerate(chords):
        # Each chord breathes in over the last one's tail.
        length = span + 3.0
        voice = pad(chord, length,
                    lambda t: 0.25 + 0.2 * np.sin(2 * np.pi * t / length) ** 2,
                    lambda t, L=length: np.clip(t / 2.6, 0, 1) ** 1.5 * np.clip((L - t) / 2.6, 0, 1) ** 1.5)
        place(track, voice, max(0.0, k * span - 1.5), 0.5)
    # Glass notes from E major's pentatonic, unhurried.
    scale = ['E5', 'F#5', 'G#5', 'B5', 'C#6', 'E6', 'F#6', 'G#6', 'B6']
    at = 1.8
    while at < BED_SECONDS - 3.5:
        note = scale[int(rng.integers(0, len(scale)))]
        place(track, bell(note, 2.4, soft=3, bright=0.5), at, 0.18 + 0.08 * rng.uniform(),
              pan=float(rng.uniform(-0.6, 0.6)))
        at += float(rng.uniform(1.6, 3.4))
    air = shaped_noise(BED_SECONDS, lambda t: 2400 + 600 * np.sin(t / 3.1),
                       lambda t: 900, lambda t: 0.5 + 0.5 * np.sin(t / 4.7) ** 2)
    place(track, air, 0.0, 0.02)
    x = hall(track, 3.2, wet=0.4)[: int(BED_SECONDS * SR)]
    x = highpass(x, 180)
    # In and out over BED_FADE, equal power, so two copies crossfade into
    # one another at a steady loudness.
    fade = int(BED_FADE * SR)
    ramp = np.sin(np.linspace(0, np.pi / 2, fade))
    x[:fade] *= ramp[:, None]
    x[-fade:] *= ramp[::-1][:, None]
    x *= 10 ** (-13 / 20) / max(np.max(np.abs(x)), 1e-9)
    x[0] = 0
    x[-1] = 0
    return x


def write_wav(path, x):
    pcm = (np.clip(x, -1, 1) * 32767).astype('<i2')
    with wave.open(path, 'wb') as f:
        f.setnchannels(2)
        f.setsampwidth(2)
        f.setframerate(SR)
        f.writeframes(pcm.tobytes())


def loudness(path):
    """Integrated loudness, LUFS, by ffmpeg's EBU R128 meter."""
    out = subprocess.run(['ffmpeg', '-hide_banner', '-nostats', '-i', path, '-af',
                          'ebur128=peak=true', '-f', 'null', '-'],
                         capture_output=True, text=True).stderr
    for line in out.splitlines()[::-1]:
        line = line.strip()
        if line.startswith('I:'):
            return float(line.split()[1])
    return float('nan')


def main():
    os.makedirs(BUILD, exist_ok=True)
    cues = {
        'intro': compose_intro(),
        'tap': compose_tap(),
        'takeoff': compose_takeoff(),
        'swoop': compose_swoop(),
        'dock': compose_dock(),
        'park': compose_park(),
        'granted': compose_granted(),
        'flap': compose_flap(),
        'tear': compose_tear(),
        'board': compose_board(),
        'bed': compose_bed(),
    }
    for i in range(1, 7):
        cues[f'step-{i}'] = compose_step(i)
    for name, x in cues.items():
        path = os.path.join(BUILD, f'{name}.wav')
        write_wav(path, x)
        peak = 20 * np.log10(np.max(np.abs(x)) + 1e-12)
        print(f'{name:8s} {len(x) / SR:5.2f} s  peak {peak:6.1f} dBFS  '
              f'{loudness(path):6.1f} LUFS')
    if '--encode' in sys.argv:
        os.makedirs(ASSETS, exist_ok=True)
        for name in cues:
            subprocess.run([
                'ffmpeg', '-y', '-loglevel', 'error', '-i', os.path.join(BUILD, f'{name}.wav'),
                '-c:a', 'aac', '-b:a', '96k' if name == 'bed' else '128k',
                '-movflags', '+faststart',
                os.path.join(ASSETS, f'{name}.m4a'),
            ], check=True)
        print('encoded into', ASSETS)


if __name__ == '__main__':
    main()
