"""The onboarding's sounds, composed from nothing.

One family, so the whole onboarding sounds like one object: soft glass bells
in E major (the key the portal's admission score resolves to), air, and paper.
Every cue is synthesized here with numpy, through one synthetic hall, so there
is nothing to license and nothing sampled. Each file starts and ends in exact
silence.

    python3 scripts/onboarding_sounds/compose.py            # WAVs into build/
    python3 scripts/onboarding_sounds/compose.py --encode   # and the app's .m4a

The cues, and where the onboarding plays them (onboarding_sound.dart):

  intro      the launch screen opening, the arrow becoming the plane, its
             lights, its climb; started with the intro, timed to its beats
  step-1..6  a breath of air and a glass note on the arrow between two steps,
             one note higher each step, so the onboarding plays a scale
  granted    two rising notes when an access is turned on
  tap        the button, barely there
  flap       the departures board turning over
  tear       the stub torn off
  board      the arrival chord as the sign-in opens
"""

import os
import subprocess
import sys
import wave

import numpy as np

SR = 48000
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
BUILD = os.path.join(ROOT, 'build', 'onboarding_sounds')
ASSETS = os.path.join(ROOT, 'assets', 'sounds', 'onboarding')

# The intro's beats, in seconds (takeoff_intro.dart).
IRIS = 0.30
MORPH_STARTS = 0.85
MORPH_ENDS = 1.60
LIGHTS_ON = 1.95
CLIMB_STARTS = 2.42
INTRO_SECONDS = 3.4

# When the arrow forms in a step transition (stage_morph.dart: arrowAt of
# the 1050 ms transition).
ARROW_AT = 0.46 * 1.05

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


def place(track, sound, at, gain=1.0, pan=0.0):
    """Mixes [sound] (mono or stereo) into [track] at [at] seconds."""
    if sound.ndim == 1:
        left = np.cos((pan + 1) * np.pi / 4)
        right = np.sin((pan + 1) * np.pi / 4)
        sound = np.stack([sound * left, sound * right], axis=1) * np.sqrt(2)
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


def bell(note, seconds=2.2, soft=1.0, bright=1.0):
    """A glass bell: a warm fundamental, a few quieter partials that die
    sooner, a breath of attack. One voice, the same in both ears: a phone's
    speakers sum the two sides, and two detuned sides would beat. The hall
    gives it its width."""
    f = hz(note) if isinstance(note, str) else note
    n = int(seconds * SR)
    t = np.arange(n) / SR
    partials = [
        (1.0, 1.0, 1.35),
        (2.0, 0.24 * bright, 0.62),
        (3.0, 0.09 * bright, 0.38),
        (4.07, 0.05 * bright, 0.24),
        (5.92, 0.022 * bright, 0.13),
    ]
    voice = np.zeros(n)
    for ratio, amp, decay in partials:
        freq = f * ratio
        if freq > SR / 2.2:
            continue
        voice += amp * np.sin(2 * np.pi * freq * t) * envelope(
            n, 0.004 * soft + 0.002 * ratio, decay)
    # The mallet: a whisper of filtered noise at the strike.
    strike_n = int(0.012 * SR)
    strike = lowpass(rng.standard_normal(strike_n), 5200) * envelope(
        strike_n, 0.0008, 0.0025)
    voice[:strike_n] += strike * 0.05 * bright
    return fade_out(np.stack([voice, voice], axis=1), 0.08)[:, 0]


def lowpass(x, cutoff):
    """A gentle one-pole low-pass, run twice (12 dB an octave)."""
    a = np.exp(-2 * np.pi * cutoff / SR)
    for _ in range(2):
        y = np.empty_like(x)
        acc = 0.0
        for i in range(len(x)):
            acc = (1 - a) * x[i] + a * acc
            y[i] = acc
        x = y
    return x


def shaped_noise(seconds, centre, width, level, stereo=True):
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
        c, w, l = centre(t), width(t), level(t)
        mask = np.exp(-0.5 * ((freqs - c) / max(w, 1)) ** 2) * l
        for side in range(2 if stereo else 1):
            spectrum = np.fft.rfft(rng.standard_normal(frame) * window)
            out[start:start + frame, side] += np.fft.irfft(spectrum * mask) * window
        norm[start:start + frame] += window ** 2
    if not stereo:
        out[:, 1] = out[:, 0]
    out = out[:n] / np.maximum(norm[:n, None], 1e-3)
    return out


def hall(x, seconds=2.2, wet=0.26, predelay=0.018, dark=4200):
    """A synthetic hall: early reflections, then decorrelated noise dying
    away, darker as it goes. Convolved by FFT."""
    n = int(seconds * SR)
    t = np.arange(n) / SR
    ir = np.zeros((n, 2))
    for side in range(2):
        tail = rng.standard_normal(n) * np.exp(-6.9 * t / seconds)
        ir[:, side] = lowpass(tail, dark)
        ir[:, side] *= np.clip(t / 0.03, 0, 1)
    for k, delay in enumerate((0.007, 0.013, 0.021, 0.029, 0.041)):
        i = int((predelay + delay) * SR)
        ir[i, k % 2] += 0.5 / (k + 1)
    ir /= np.sqrt(np.sum(ir ** 2, axis=0, keepdims=True))
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


def master(x, peak_db):
    """Starts and ends in exact silence, trims what is inaudible, and sets
    the peak."""
    loud = np.max(np.abs(x), axis=1)
    keep = np.nonzero(loud > 10 ** (-72 / 20) * np.max(loud))[0]
    end = min(len(x), keep[-1] + int(0.02 * SR)) if len(keep) else len(x)
    x = x[:end].copy()
    x = fade_out(x, min(0.25, len(x) / SR / 4))
    ramp = min(len(x), int(0.002 * SR))
    x[:ramp] *= np.linspace(0, 1, ramp)[:, None]
    x -= np.mean(x, axis=0, keepdims=True) * 0  # keep the zero
    x *= 10 ** (peak_db / 20) / max(np.max(np.abs(x)), 1e-9)
    x[0] = 0
    x[-1] = 0
    return x


def pad(notes, seconds, brightness, level):
    """A soft chord: each note a few pure partials, the upper ones brought
    in by [brightness](t), the whole by [level](t)."""
    n = int(seconds * SR)
    t = np.arange(n) / SR
    bright = brightness(t)
    voice = np.zeros(n)
    for note in notes:
        f = hz(note)
        voice += np.sin(2 * np.pi * f * t)
        voice += 0.3 * bright * np.sin(2 * np.pi * 2 * f * t + 0.4)
        voice += 0.1 * bright * np.sin(2 * np.pi * 3 * f * t + 1.1)
    return voice / len(notes) * level(t)


def compose_intro():
    track = silence(INTRO_SECONDS + 2.6)
    # The iris: a breath of air opening.
    air = shaped_noise(
        0.9, lambda t: 2400 + 2600 * t, lambda t: 900 + 900 * t,
        lambda t: np.sin(np.pi * min(t / 0.9, 1)) ** 2)
    place(track, air, IRIS - 0.05, 0.05)
    place(track, bell('B6', 1.4, soft=2.5, bright=0.5), IRIS + 0.18, 0.09, pan=-0.25)
    # The arrow becoming the plane: a chord swelling and opening up.
    swell_len = MORPH_ENDS - MORPH_STARTS + 1.4
    chord = pad(['E4', 'B4', 'E5', 'G#5'], swell_len,
                lambda t: np.clip((t - 0.1) / 0.8, 0, 1) ** 1.5,
                lambda t: np.clip(t / 0.75, 0, 1) ** 2 * np.exp(-np.clip(t - 0.75, 0, None) / 0.5))
    place(track, chord, MORPH_STARTS, 0.16)
    # The plane is there: its chime.
    place(track, bell('E6', 2.4), MORPH_ENDS, 0.5, pan=0.1)
    place(track, bell('B6', 2.0, bright=0.6), MORPH_ENDS + 0.012, 0.16, pan=0.25)
    # Its strobes: two tiny ticks.
    for k, at in enumerate((LIGHTS_ON, LIGHTS_ON + 0.14)):
        tick = bell(hz('E7') * 1.5, 0.12, soft=0.3, bright=0.2)
        place(track, tick, at, 0.05 - 0.015 * k, pan=0.5 if k else -0.5)
    # The climb: air rising and passing to the right, faster and faster.
    climb = INTRO_SECONDS - CLIMB_STARTS + 1.0

    def whoosh_level(t):
        u = np.clip(t / (climb - 1.0), 0, 1)
        return (u ** 1.6) * np.exp(-np.clip(t - (climb - 1.0), 0, None) / 0.32)

    jet = shaped_noise(climb, lambda t: 380 + 2400 * np.clip(t / (climb - 0.9), 0, 1) ** 1.7,
                       lambda t: 260 + 1200 * np.clip(t / climb, 0, 1), whoosh_level)
    # It leaves to the upper right: the sound moves right as it goes.
    pan = np.linspace(-0.15, 0.85, len(jet))
    jet[:, 0] *= np.cos((pan + 1) * np.pi / 4) * np.sqrt(2)
    jet[:, 1] *= np.sin((pan + 1) * np.pi / 4) * np.sqrt(2)
    place(track, jet, CLIMB_STARTS - 0.1, 0.2)
    return master(hall(track, 2.4, wet=0.3), -9)


STEP_NOTES = ['E5', 'F#5', 'G#5', 'B5', 'C#6', 'E6']


def compose_step(index):
    track = silence(ARROW_AT + 2.4)
    # The object melting: a short breath of air into the arrow.
    air = shaped_noise(
        ARROW_AT + 0.08, lambda t: 1800 + 2600 * t / ARROW_AT, lambda t: 700 + 500 * t,
        lambda t: (np.clip(t / ARROW_AT, 0, 1) ** 2) * (1 if t < ARROW_AT else 0.2))
    place(track, air, 0.0, 0.05)
    note = STEP_NOTES[index - 1]
    place(track, bell(note, 2.2), ARROW_AT, 0.5)
    # A fifth above, very soft: the glint.
    place(track, bell(hz(note) * 1.5, 1.2, bright=0.4), ARROW_AT + 0.03, 0.08, pan=0.35)
    return master(hall(track, 2.0, wet=0.28), -13)


def compose_granted():
    track = silence(2.4)
    place(track, bell('B5', 1.6), 0.0, 0.45, pan=-0.15)
    place(track, bell('E6', 2.0), 0.11, 0.5, pan=0.15)
    return master(hall(track, 1.8, wet=0.26), -12)


def compose_tap():
    n = int(0.05 * SR)
    t = np.arange(n) / SR
    # A soft, woody tock: a low body and a short click on top.
    body = np.sin(2 * np.pi * 420 * t) * envelope(n, 0.0006, 0.009)
    click = lowpass(rng.standard_normal(n), 3600) * envelope(n, 0.0002, 0.0018)
    x = np.stack([body + 0.35 * click] * 2, axis=1)
    return master(hall(x, 0.4, wet=0.12), -24)


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
    return master(hall(track, 0.9, wet=0.18), -21)


def compose_tear():
    """Paper torn along its perforation: a run of small rips, a soft give."""
    track = silence(1.0)
    at = 0.0
    while at < 0.36:
        n = int(rng.uniform(0.004, 0.014) * SR)
        rip = rng.standard_normal(n) * envelope(n, 0.0005, n / SR / 3)
        rip = rip - lowpass(rip, 900)
        place(track, rip, at, 0.5 * (1 - at / 0.5) + 0.1, pan=0.2 * np.sin(at * 30))
        at += rng.uniform(0.006, 0.02)
    give = shaped_noise(0.25, lambda t: 900, lambda t: 500, lambda t: np.exp(-t / 0.06))
    place(track, give, 0.33, 0.25)
    return master(hall(track, 0.8, wet=0.14), -15)


def compose_board():
    """Welcome aboard: the arrival chord, rolled up, with a soft swell."""
    track = silence(4.2)
    notes = ['E4', 'B4', 'E5', 'F#5', 'G#5', 'B5', 'E6']
    for k, note in enumerate(notes):
        place(track, bell(note, 3.2, bright=0.8), k * 0.055, 0.32 if k < 3 else 0.26,
              pan=-0.5 + k / (len(notes) - 1))
    chord = pad(['E3', 'B3', 'E4', 'G#4', 'B4'], 3.6,
                lambda t: 0.2 + 0.4 * np.clip(t / 1.2, 0, 1),
                lambda t: np.clip(t / 0.5, 0, 1) * np.exp(-np.clip(t - 0.5, 0, None) / 1.1))
    place(track, chord, 0.05, 0.14)
    return master(hall(track, 2.8, wet=0.34), -10)


def write_wav(path, x):
    pcm = (np.clip(x, -1, 1) * 32767).astype('<i2')
    with wave.open(path, 'wb') as f:
        f.setnchannels(2)
        f.setsampwidth(2)
        f.setframerate(SR)
        f.writeframes(pcm.tobytes())


def main():
    os.makedirs(BUILD, exist_ok=True)
    cues = {
        'intro': compose_intro(),
        'granted': compose_granted(),
        'tap': compose_tap(),
        'flap': compose_flap(),
        'tear': compose_tear(),
        'board': compose_board(),
    }
    for i in range(1, 7):
        cues[f'step-{i}'] = compose_step(i)
    for name, x in cues.items():
        write_wav(os.path.join(BUILD, f'{name}.wav'), x)
        peak = 20 * np.log10(np.max(np.abs(x)) + 1e-12)
        rms = 20 * np.log10(np.sqrt(np.mean(x ** 2)) + 1e-12)
        print(f'{name:8s} {len(x) / SR:5.2f} s  peak {peak:6.1f} dBFS  rms {rms:6.1f} dBFS')
    if '--encode' in sys.argv:
        os.makedirs(ASSETS, exist_ok=True)
        for name in cues:
            subprocess.run([
                'ffmpeg', '-y', '-loglevel', 'error', '-i', os.path.join(BUILD, f'{name}.wav'),
                '-c:a', 'aac', '-b:a', '128k', '-movflags', '+faststart',
                os.path.join(ASSETS, f'{name}.m4a'),
            ], check=True)
        print('encoded into', ASSETS)


if __name__ == '__main__':
    main()
