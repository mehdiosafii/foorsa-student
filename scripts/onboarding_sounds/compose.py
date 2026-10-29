"""The onboarding's sounds: real instruments and real things, few and quiet.

The first versions were synthesized here with numpy: glass bells, mastered almost to full
scale, and nearly every touch rang. A tick on each press, a note on each step, a chime on each
yes and a ring on each dock, four seconds apiece, over a loop of bells: 25 sounds in 43 seconds,
and it sounded like a toy. Now:

- The music is played by sampled instruments (piano, harp, strings, celesta) from the MuseScore
  General soundfont (MIT licence), rendered by fluidsynth, all in E major (the key the portal's
  admission score resolves to), through one soft hall.
- What makes a sound in the story is a recording (CC0, foley/SOURCES.md): the departures
  board's flaps, the arrow's air, the camera, the boarding pass's stub.
- Few sounds, and quiet. A plain press and a step changing make no sound: the haptics carry
  them. The music sits under everything; the opening and the arrival are the two moments it
  speaks up. Nothing is squashed: each cue is brought to its loudness only as far as its peak
  allows, so it keeps its dynamics.

    apt-get install fluidsynth musescore-general-soundfont ffmpeg
    pip install numpy scipy soundfile mido pyloudnorm
    python3 scripts/onboarding_sounds/compose.py            # WAVs into build/onboarding_sounds
    python3 scripts/onboarding_sounds/compose.py --encode   # and the app's .m4a

The cues, and where the onboarding plays them (onboarding_page.dart):

  intro    the arrow catching the light, becoming the plane, its lights, its climb;
           started with the intro, timed to its beats (takeoff_intro.dart)
  flap     the departures board turning over
  swoop    the arrow's flight up into the picture, thrown or lifted
  dock     the arrow settling into the picture's arrow of light, or what is left of the
           boarding pass becoming the arrow
  granted  an access turned on
  shutter  the scanner taking the passport page
  tear     the stub coming off the boarding pass
  board    the arrival, as the sign-in opens
  bed      forty seconds of night music under the steps, looped by crossfading two players
           (onboarding_sound.dart): it starts and ends on the same open E, so the overlap
           of two copies is consonant
"""

import os
import random
import subprocess
import sys
import zlib

import mido
import numpy as np
import pyloudnorm as pyln
import scipy.signal as ss
import soundfile as sf
from scipy.ndimage import minimum_filter1d

SR = 48000
METER = pyln.Meter(SR)
SOUNDFONT = '/usr/share/sounds/sf3/MuseScore_General_Full.sf3'
TPB = 960  # MIDI at 120 bpm: one beat is 0.5 s

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
FOLEY = os.path.join(HERE, 'foley')
BUILD = os.path.join(ROOT, 'build', 'onboarding_sounds')
WORK = os.path.join(BUILD, 'work')
ASSETS = os.path.join(ROOT, 'assets', 'sounds', 'onboarding')

# The intro's beats, in seconds (takeoff_intro.dart).
WAKE = 0.16
SHINE = 0.30
MORPH_STARTS = 0.85
MORPH_ENDS = 1.60
LIGHTS_ON = 1.95
CLIMB_STARTS = 2.42

# The arrow's flight into the picture (onboarding_page.dart's FlightTimes.lifted.swoop).
SWOOP = 0.60

GM = dict(piano=0, celesta=8, harp=46, strings=48, strings_slow=49)

# Every note from C1 to B8; sharps are written with an underscore (G_4).
NAMES = ['C', 'C_', 'D', 'D_', 'E', 'F', 'F_', 'G', 'G_', 'A', 'A_', 'B']
N = {f'{name}{octave}': 12 * (octave + 1) + i for octave in range(1, 9) for i, name in enumerate(NAMES)}


# ── Instruments ───────────────────────────────────────────────────────────

def ticks(seconds):
    return int(round(seconds / 0.5 * TPB))


class Part:
    """One instrument's notes and controller moves, rendered on its own so it can be placed."""

    def __init__(self, name, program, pan=0.0, gain=1.0, send=0.4, humanize=0.0, tone=None):
        self.name, self.program = name, program
        self.pan, self.gain, self.send, self.humanize, self.tone = pan, gain, send, humanize, tone
        self.notes, self.cc = [], []

    def n(self, t, pitch, dur, vel):
        pitch = N[pitch] if isinstance(pitch, str) else pitch
        self.notes.append((max(0.0, t), pitch, dur, max(1, min(127, int(round(vel))))))
        return self

    def chord(self, t, pitches, dur, vel, roll=0.0):
        for i, p in enumerate(pitches):
            self.n(t + i * roll, p, dur, vel)
        return self

    def ramp(self, t0, t1, v0, v1, ctrl=11, step=0.02):
        steps = max(1, int((t1 - t0) / step))
        for i in range(steps + 1):
            k = i / steps
            self.cc.append((t0 + (t1 - t0) * k, ctrl, v0 + (v1 - v0) * k))
        return self


def write_midi(part, path, seed):
    rnd = random.Random(seed)
    mid = mido.MidiFile(ticks_per_beat=TPB)
    track = mido.MidiTrack()
    mid.tracks.append(track)
    track.append(mido.MetaMessage('set_tempo', tempo=500000, time=0))
    events = [(0, 0, mido.Message('program_change', program=part.program, channel=0)),
              (0, 1, mido.Message('control_change', control=7, value=110, channel=0)),
              (0, 1, mido.Message('control_change', control=11, value=127, channel=0))]
    for t, c, v in part.cc:
        events.append((ticks(t), 2, mido.Message('control_change', control=c,
                                                 value=int(max(0, min(127, round(v)))), channel=0)))
    for t, p, d, v in part.notes:
        jitter = rnd.uniform(-part.humanize, part.humanize) if part.humanize else 0.0
        vj = rnd.randint(-3, 3) if part.humanize else 0
        on = ticks(max(0.0, t + jitter))
        events.append((on, 3, mido.Message('note_on', note=p, velocity=max(1, min(127, v + vj)), channel=0)))
        events.append((max(on + 1, ticks(t + jitter + d)), 1, mido.Message('note_off', note=p, velocity=0, channel=0)))
    events.sort(key=lambda e: (e[0], e[1]))
    last = 0
    for tick, _, msg in events:
        msg.time = tick - last
        last = tick
        track.append(msg)
    mid.save(path)


def render(part, length, tag):
    mid = os.path.join(WORK, f'{tag}_{part.name}.mid')
    wav = os.path.join(WORK, f'{tag}_{part.name}.wav')
    write_midi(part, mid, seed=zlib.crc32(f'{tag}:{part.name}'.encode()))
    subprocess.run(['fluidsynth', '-ni', '-q', '-r', str(SR), '-g', '0.5',
                    '-o', 'synth.reverb.active=0', '-o', 'synth.chorus.active=0',
                    '-o', 'synth.polyphony=512', '-o', 'audio.file.format=float',
                    '-F', wav, SOUNDFONT, mid], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    x, sr = sf.read(wav, dtype='float64', always_2d=True)
    assert sr == SR
    if x.shape[1] == 1:
        x = np.repeat(x, 2, axis=1)
    x = fit(x, length)
    if part.tone:
        x = ss.sosfilt(ss.butter(2, part.tone, btype='low', fs=SR, output='sos'), x, axis=0)
    return x


# ── Space, placement, level ───────────────────────────────────────────────

def decaying_ir(seconds, bands, predelay, seed, build=0.045, reflections=12):
    """Diffuse noise whose highs die before its lows, after a few early reflections."""
    rng = np.random.default_rng(seed)
    n = int(seconds * SR)
    t = np.arange(n) / SR
    ir = np.zeros((n, 2))
    for ch in range(2):
        noise = rng.standard_normal(n)
        acc = np.zeros(n)
        for (lo, hi), rt in bands:
            if lo is None:
                sos = ss.butter(4, hi, btype='low', fs=SR, output='sos')
            elif hi is None:
                sos = ss.butter(4, lo, btype='high', fs=SR, output='sos')
            else:
                sos = ss.butter(4, [lo, hi], btype='band', fs=SR, output='sos')
            acc += ss.sosfilt(sos, noise) * np.exp(-6.91 * t / rt)
        acc *= np.minimum(1.0, t / build) ** 1.5
        ir[:, ch] = acc
    early = np.zeros((n, 2))
    for k in range(reflections):
        d = rng.uniform(0.006, 0.07)
        for ch in range(2):
            early[int((d + rng.uniform(0, 0.005)) * SR), ch] += 0.5 * np.exp(-k / 5) * rng.choice([-1, 1])
    ir = ir / np.sqrt((ir ** 2).sum(axis=0)).max() + early * 0.35
    pad = int(predelay * SR)
    ir = np.vstack([np.zeros((pad, 2)), ir])[:n]
    return ir / np.sqrt((ir ** 2).sum(axis=0)).max()


# A soft hall for the music, and a small quiet room for the things.
HALL = decaying_ir(3.0, [((None, 400), 2.6), ((400, 1800), 2.3), ((1800, 5500), 1.7),
                         ((5500, 12000), 1.1), ((12000, None), 0.6)], predelay=0.022, seed=11)
ROOM = decaying_ir(0.6, [((None, 800), 0.45), ((800, 4000), 0.36), ((4000, None), 0.22)],
                   predelay=0.004, seed=7, build=0.01, reflections=8)


def fit(x, length):
    n = int(round(length * SR))
    if len(x) < n:
        x = np.vstack([x, np.zeros((n - len(x), 2))])
    return x[:n]


def place(x, pan):
    """Equal-power pan; `pan` may be a number or one value per sample."""
    a = (np.asarray(pan) + 1) * np.pi / 4
    if np.ndim(a) == 0:
        return x * np.array([np.cos(a), np.sin(a)]) * np.sqrt(2)
    return x * np.stack([np.cos(a), np.sin(a)], axis=1) * np.sqrt(2)


def convolve(x, ir):
    return np.stack([ss.fftconvolve(x[:, ch], ir[:, ch])[:len(x)] for ch in range(2)], axis=1)


def mix(parts, length, tag, wet, things=(), room=0.0):
    """The instruments through the hall; `things` (stereo recordings, already placed) through
    the room, and a little of the hall."""
    dry = np.zeros((int(round(length * SR)), 2))
    hall = np.zeros_like(dry)
    near = np.zeros_like(dry)
    for part in parts:
        x = place(render(part, length, tag), part.pan) * part.gain
        dry += x
        hall += x * part.send
    for x, send in things:
        x = fit(x, length)
        dry += x
        near += x
        hall += x * send
    y = dry + convolve(hall, HALL) * wet
    if room:
        y = y + convolve(near, ROOM) * room
    return ss.sosfilt(ss.butter(2, 60, btype='high', fs=SR, output='sos'), y, axis=0)


def limit(x, ceiling_db, lookahead=0.003, release=0.12):
    ceiling = 10 ** (ceiling_db / 20)
    need = np.minimum(1.0, ceiling / np.maximum(np.abs(x).max(axis=1), 1e-12))
    need = minimum_filter1d(need, size=2 * int(lookahead * SR) + 1)
    rel = np.exp(-1.0 / (release * SR))
    g = np.empty_like(need)
    cur = 1.0
    for i, v in enumerate(need):
        cur = v if v < cur else rel * cur + (1 - rel) * v
        g[i] = cur
    return x * g[:, None]


def master(y, target_lufs, peak_db, fade_in=0.004, fade_out=0.5):
    """Up to `target_lufs`, but never past `peak_db`: a quiet cue stays a quiet cue rather than
    being squeezed into a loud one. Starts and ends in exact silence."""
    loud = METER.integrated_loudness(y)
    peak = 20 * np.log10(np.abs(y).max() + 1e-12)
    y = y * 10 ** (min(target_lufs - loud, peak_db - peak) / 20)
    y = limit(y, peak_db + 0.5)
    n_in, n_out = int(fade_in * SR), int(fade_out * SR)
    if n_in:
        y[:n_in] *= np.linspace(0, 1, n_in)[:, None]
    if n_out:
        y[-n_out:] *= (0.5 + 0.5 * np.cos(np.linspace(0, np.pi, n_out)))[:, None]
    y[0] = 0
    y[-1] = 0
    return y


# ── The recordings ────────────────────────────────────────────────────────

def recording(name):
    x, sr = sf.read(os.path.join(FOLEY, f'{name}.flac'), dtype='float64', always_2d=True)
    assert sr == SR, (name, sr)
    return np.repeat(x, 2, axis=1) if x.shape[1] == 1 else x


def band(x, lo=None, hi=None, order=2):
    if lo:
        x = ss.sosfilt(ss.butter(order, lo, btype='high', fs=SR, output='sos'), x, axis=0)
    if hi:
        x = ss.sosfilt(ss.butter(order, hi, btype='low', fs=SR, output='sos'), x, axis=0)
    return x


def peaking(x, freq, gain_db, q=1.0):
    """An RBJ peaking bell: a body for something that is only a click."""
    a = 10 ** (gain_db / 40)
    w = 2 * np.pi * freq / SR
    alpha = np.sin(w) / (2 * q)
    b = [1 + alpha * a, -2 * np.cos(w), 1 - alpha * a]
    d = [1 + alpha / a, -2 * np.cos(w), 1 - alpha / a]
    return ss.lfilter(np.array(b) / d[0], np.array(d) / d[0], x, axis=0)


def declick(x, t, width=0.008, cutoff=2500):
    """A tick in a recording at `t` s, smoothed into the sound around it."""
    lp = band(x, hi=cutoff, order=4)
    w = np.zeros(len(x))
    i, h = int(t * SR), int(width * SR)
    w[max(0, i - h):i + h] = np.hanning(min(len(x), i + h) - max(0, i - h))
    return x * (1 - w[:, None]) + lp * w[:, None]


def whoosh():
    """The rope, without the little tick its recording has at 0.229 s."""
    return declick(recording('rope-whoosh'), 0.229)


def stretch(x, factor):
    """Slower and lower by `factor` (above 1), or faster and higher (below 1), as a tape would."""
    up, down = int(round(factor * 100)), 100
    g = np.gcd(up, down)
    return ss.resample_poly(x, up // g, down // g, axis=0)


def cut(x, start, end, fade_in=0.004, fade_out=0.02):
    y = x[int(start * SR):int(end * SR)].copy()
    a, b = int(fade_in * SR), int(fade_out * SR)
    if a:
        y[:a] *= np.linspace(0, 1, a)[:, None]
    if b:
        y[-b:] *= np.linspace(1, 0, b)[:, None]
    return y


def at(x, start, length):
    """`x` placed `start` seconds into a buffer `length` long."""
    out = np.zeros((int(round(length * SR)), 2))
    i = int(round(start * SR))
    seg = x[:max(0, len(out) - i)]
    out[i:i + len(seg)] += seg
    return out


def clicks():
    """The ratchet's single teeth, each a few milliseconds of a real mechanical click."""
    x = recording('small-ratchet')
    m = x.mean(axis=1)
    env = np.convolve(np.abs(m), np.ones(48) / 48, 'same')
    peaks, _ = ss.find_peaks(env, height=env.max() * 0.2, distance=int(0.012 * SR))
    bank = []
    for p in peaks:
        s, e = p - int(0.002 * SR), p + int(0.03 * SR)
        if s < 0 or e > len(x):
            continue
        c = x[s:e].copy()
        c *= np.exp(-np.arange(len(c)) / (0.006 * SR))[:, None]  # a flap's slap, not a tooth's ring
        bank.append(c / np.abs(c).max())
    return bank


# ── The cues ──────────────────────────────────────────────────────────────

def cue_intro():
    """The arrow wakes, catches the light, flows into the plane, its lights come on, it climbs."""
    length = 6.2
    strings = Part('strings', GM['strings_slow'], pan=0.0, gain=0.7, send=0.55, tone=6500)
    strings.chord(WAKE, ['E2', 'B2', 'E3'], 4.6, 50).ramp(WAKE, 2.3, 18, 84).ramp(4.0, 5.2, 84, 28)
    strings.chord(CLIMB_STARTS, ['G_3', 'B3', 'E4'], 2.8, 46)
    celesta = Part('celesta', GM['celesta'], pan=0.3, gain=0.9, send=0.6)
    celesta.n(SHINE, 'B5', 1.8, 34)
    harp = Part('harp', GM['harp'], pan=-0.25, gain=1.0, send=0.5)
    gliss = ['E4', 'F_4', 'G_4', 'B4', 'C_5', 'E5', 'F_5', 'G_5', 'B5', 'C_6', 'E6']
    for i, p in enumerate(gliss):
        k = i / (len(gliss) - 1)
        eased = k * k * (3 - 2 * k)
        harp.n(MORPH_STARTS + (MORPH_ENDS - MORPH_STARTS) * eased, p, 2.2, 26 + 18 * k)
    piano = Part('piano', GM['piano'], pan=-0.1, gain=1.0, send=0.45, tone=6000)
    piano.n(LIGHTS_ON, 'G_5', 1.4, 30).n(LIGHTS_ON + 0.17, 'B5', 1.4, 28)
    piano.chord(CLIMB_STARTS, ['E4', 'B4', 'E5', 'G_5'], 3.2, 36, roll=0.06)
    # The climb's air: the rope, slower and lower, under the chord's bloom.
    air = band(stretch(whoosh(), 1.6), 220, 4500, order=4)
    sweep = np.linspace(-0.1, 0.5, len(air))
    air = place(air.mean(axis=1, keepdims=True).repeat(2, axis=1) * 0.5, sweep) * 0.14
    y = mix([strings, celesta, harp, piano], length, 'intro', wet=0.55,
            things=[(at(air, CLIMB_STARTS - 0.32, length), 0.35)])
    return master(y, -20, -6, fade_out=0.8)


def cue_flap():
    """A row of split flaps turning over and settling: the ratchet's teeth, slowed into card
    and given a body, re-timed column by column."""
    length = 1.2
    rnd = random.Random(2026)
    bank = clicks()
    out = np.zeros((int(length * SR), 2))
    columns = 9
    for col in range(columns):
        t = 0.014 * col + rnd.uniform(0.0, 0.03)
        flaps = rnd.randint(4, 7)
        gap = rnd.uniform(0.030, 0.038)
        for k in range(flaps):
            c = stretch(rnd.choice(bank), rnd.uniform(1.6, 2.0))  # card, not steel
            last = k == flaps - 1
            gain = rnd.uniform(0.45, 0.7) * (1.3 if last else 1.0)
            pan = -0.45 + 0.9 * col / (columns - 1) + rnd.uniform(-0.05, 0.05)
            out += at(place(c * gain, pan), t, length)
            t += gap * (1 + 0.2 * k)  # each flap a little slower: the row settles
    out = peaking(band(out, 300, 4500, order=4), 1600, 8, q=1.1)
    y = mix([], length, 'flap', wet=0.12, things=[(out, 0.25)], room=0.22)
    return master(y, -28, -15, fade_out=0.25)


def cue_swoop():
    """The arrow's air as it flies up into the picture."""
    length = 1.2
    x = band(stretch(whoosh(), 0.85), 300, 8000)
    m = x.mean(axis=1, keepdims=True).repeat(2, axis=1)
    peak = int(np.argmax(np.convolve(np.abs(m[:, 0]), np.ones(960) / 960, 'same')))
    start = 0.38 - peak / SR  # its swell where the flight is fastest
    sweep = np.linspace(-0.35, 0.35, len(m))
    y = mix([], length, 'swoop', wet=0.1, things=[(at(place(m, sweep), max(0.0, start), length), 0.3)], room=0.15)
    return master(y, -28, -16, fade_out=0.3)


def cue_dock():
    """It settles into place: one soft plucked E, a breath of piano above it."""
    length = 1.8
    harp = Part('harp', GM['harp'], pan=0.1, gain=1.0, send=0.5)
    harp.n(0.0, 'E5', 1.6, 34)
    piano = Part('piano', GM['piano'], pan=-0.1, gain=0.6, send=0.5, tone=5500)
    piano.n(0.01, 'B5', 1.4, 20)
    return master(mix([harp, piano], length, 'dock', wet=0.5), -28, -15, fade_out=0.5)


def cue_granted():
    """Yes: two soft notes up a fourth, piano doubled by the harp."""
    length = 2.0
    piano = Part('piano', GM['piano'], pan=-0.12, gain=1.0, send=0.45, tone=6000)
    piano.n(0.0, 'B4', 1.5, 38).n(0.14, 'E5', 1.5, 42)
    harp = Part('harp', GM['harp'], pan=0.2, gain=0.55, send=0.5)
    harp.n(0.0, 'B4', 1.4, 24).n(0.14, 'E5', 1.4, 28)
    return master(mix([piano, harp], length, 'granted', wet=0.45), -24, -11, fade_out=0.5)


def cue_shutter():
    """The page taken: a Kodak Instamatic's shutter, from its first click."""
    length = 0.7
    x = band(recording('instamatic-shutter'), 160, 12000)
    m = x.mean(axis=1)
    first = int(np.argmax(np.abs(m) > np.abs(m).max() * 0.08))
    x = cut(x, max(0.0, first / SR - 0.004), len(x) / SR, fade_out=0.04)
    y = mix([], length, 'shutter', wet=0.06, things=[(place(x, 0.0), 0.2)], room=0.12)
    return master(y, -26, -12, fade_out=0.15)


def cue_tear():
    """The stub coming off: the last, quickest part of a sheet torn off."""
    length = 0.8
    x = band(recording('paper-torn-off'), 180, 14000)
    x = cut(x, 0.36, 0.80, fade_in=0.012, fade_out=0.06)
    y = mix([], length, 'tear', wet=0.05, things=[(place(x, 0.05), 0.15)], room=0.1)
    return master(y, -24, -10, fade_out=0.12)


def cue_board():
    """The arrival: the E the night has been waiting on, opening over the sign-in."""
    length = 6.4
    piano = Part('piano', GM['piano'], pan=-0.1, gain=1.0, send=0.5, tone=6500)
    piano.chord(0.0, ['E3', 'B3', 'E4', 'G_4', 'B4'], 4.8, 40, roll=0.07).n(0.36, 'E5', 4.4, 44)
    strings = Part('strings', GM['strings_slow'], pan=0.0, gain=0.75, send=0.55, tone=6500)
    strings.chord(0.0, ['E2', 'B2', 'E3', 'G_3', 'B3'], 5.0, 46).ramp(0.0, 1.4, 30, 82).ramp(1.4, 5.0, 82, 34)
    harp = Part('harp', GM['harp'], pan=0.25, gain=0.7, send=0.55)
    for i, p in enumerate(['E5', 'G_5', 'B5', 'E6']):
        harp.n(0.4 + i * 0.08, p, 2.2, 30 - i * 2)
    celesta = Part('celesta', GM['celesta'], pan=0.3, gain=0.6, send=0.6)
    celesta.n(1.0, 'E6', 2.2, 26)
    y = mix([piano, strings, harp, celesta], length, 'board', wet=0.6)
    return master(y, -20, -6, fade_out=1.2)


def cue_bed():
    """Forty seconds of night: I, vi7, IV, Vsus4 to V, I, slow and spacious, no pulse."""
    length = 40.0
    strings = Part('strings', GM['strings_slow'], pan=0.0, gain=0.6, send=0.6, tone=4500)
    piano = Part('piano', GM['piano'], pan=-0.15, gain=1.0, send=0.55, humanize=0.012, tone=4800)
    harp = Part('harp', GM['harp'], pan=0.3, gain=0.6, send=0.6, humanize=0.008)
    chords = [  # start, strings, bass, harp's fragment
        (0.0, ['E2', 'B2', 'E3', 'B3'], 'E2', ['E4', 'G_4', 'B4', 'E5']),
        (8.0, ['C_3', 'G_3', 'B3', 'E4'], 'C_3', ['C_4', 'E4', 'G_4', 'C_5']),
        (16.0, ['A2', 'E3', 'B3', 'C_4'], 'A2', ['A3', 'C_4', 'E4', 'B4']),
        (24.0, ['B2', 'F_3', 'B3', 'E4'], 'B2', ['B3', 'E4', 'F_4', 'B4']),
        (32.0, ['E2', 'B2', 'E3', 'B3'], 'E3', None),
    ]
    for start, voicing, bass, fragment in chords:
        strings.chord(start, voicing, 8.6, 44).ramp(start, start + 3.0, 34, 72).ramp(start + 5.0, start + 8.4, 72, 40)
        piano.n(start + 0.4, bass, 6.0, 22)
        if fragment:
            for i, p in enumerate(fragment):
                harp.n(start + 4.2 + i * 0.16, p, 2.4, 26 - i)
    # The sus4 resolving: D# under the strings' E.
    strings.n(28.0, 'D_4', 4.4, 36)
    melody = [(1.0, 'B4', 3.0, 34), (3.6, 'G_4', 2.6, 30), (6.0, 'F_4', 2.2, 28),
              (8.6, 'E5', 3.0, 34), (11.2, 'G_4', 2.8, 30), (13.6, 'B4', 2.4, 28),
              (16.6, 'C_5', 3.0, 34), (19.2, 'E5', 2.8, 32), (21.6, 'B4', 2.4, 28),
              (24.6, 'E5', 2.6, 32), (27.0, 'F_5', 2.6, 30), (29.6, 'D_5', 2.6, 30),
              (32.6, 'E5', 3.6, 28), (35.4, 'B4', 3.6, 24)]
    for t, p, d, v in melody:
        piano.n(t, p, d, v)
    y = mix([strings, piano, harp], length, 'bed', wet=0.62)
    # A backdrop, well under the moments: the onboarding's sounds must stand out of it.
    y = master(y, -31, -16, fade_in=0.0, fade_out=0.0)
    fade = int(4.0 * SR)
    ramp = 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, fade))
    y[:fade] *= ramp[:, None]
    y[-fade:] *= ramp[::-1, None]
    y[0] = 0
    y[-1] = 0
    return y


CUES = {
    'intro': cue_intro,
    'flap': cue_flap,
    'swoop': cue_swoop,
    'dock': cue_dock,
    'granted': cue_granted,
    'shutter': cue_shutter,
    'tear': cue_tear,
    'board': cue_board,
    'bed': cue_bed,
}


def main():
    os.makedirs(WORK, exist_ok=True)
    only = [a for a in sys.argv[1:] if not a.startswith('--')]
    for name, make in CUES.items():
        if only and name not in only:
            continue
        y = make()
        sf.write(os.path.join(BUILD, f'{name}.wav'), y.astype(np.float32), SR, subtype='PCM_24')
        loud = METER.integrated_loudness(y) if len(y) > SR * 0.4 else float('nan')
        peak = 20 * np.log10(np.abs(y).max() + 1e-12)
        print(f'{name:8s} {len(y) / SR:5.2f} s  {loud:6.1f} LUFS  peak {peak:6.1f} dBFS')
    if '--encode' in sys.argv:
        os.makedirs(ASSETS, exist_ok=True)
        for name in CUES:
            subprocess.run([
                'ffmpeg', '-y', '-loglevel', 'error', '-i', os.path.join(BUILD, f'{name}.wav'),
                '-c:a', 'aac', '-b:a', '96k' if name == 'bed' else '128k',
                '-movflags', '+faststart',
                os.path.join(ASSETS, f'{name}.m4a'),
            ], check=True)
        print('encoded into', ASSETS)


if __name__ == '__main__':
    main()
