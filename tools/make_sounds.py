"""LOPP FIGHT - every sound in the game, cut + remixed ONLY from Sixten's own recordings in assets/sounds/his/.
Nothing is synthesized: no noise, no sine waves. Only slicing, pitching (resampling), filtering, layering and gain.

  "C:/Program Files/Blender Foundation/Blender 5.1/blender.exe" -b --python tools/make_sounds.py

Writes assets/sounds/*.wav (48 kHz 16-bit mono).
"""
import os, wave
import numpy as np
import aud

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
HIS = os.path.join(ROOT, "assets", "sounds", "his")
OUT = os.path.join(ROOT, "assets", "sounds")
SR = 48000
_cache = {}


def load(name):
    if name not in _cache:
        s = aud.Sound(os.path.join(HIS, name)); sr = int(s.specs[0])
        d = np.asarray(s.data(), dtype=np.float64)
        a = d.mean(axis=1) if d.ndim > 1 else d
        _cache[name] = np.interp(np.arange(int(len(a) * SR / sr)) * sr / SR, np.arange(len(a)), a)
    return _cache[name]


def cut(name, start, length, pre=0.01):
    a = load(name); i = max(0, int((start - pre) * SR))
    return a[i:i + int(length * SR)].copy()


def pitch(a, factor):            # >1 = higher + shorter (like speeding up a tape)
    n = int(len(a) / factor)
    return np.interp(np.arange(n) * factor, np.arange(len(a)), a)


def lowpass(a, width):           # moving average = soft low-pass
    return np.convolve(a, np.ones(width) / width, mode="same")


def highpass(a, width):          # original minus its low part = only the crisp part
    return a - lowpass(a, width)


def fade(a, fin=0.004, fout=0.08):
    a = a.copy(); i, o = int(fin * SR), int(fout * SR)
    if i: a[:i] *= np.linspace(0, 1, i)
    if o: a[-o:] *= np.linspace(1, 0, o) ** 2
    return a


def mix(*parts):
    n = max(len(p) for p in parts); out = np.zeros(n)
    for p in parts: out[:len(p)] += p
    return out


def save(name, a, peak_db):
    a = a / (np.abs(a).max() + 1e-9) * 10 ** (peak_db / 20)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((np.clip(a, -1, 1) * 32767).astype(np.int16).tobytes())
    print("wrote", name, f"{len(a)/SR:.2f}s")


H, C, F = "paper_handling.mp3", "paper_crinkle.mp3", "paper_flutter.mp3"

# BITE: the jaws snapping shut = the sharpest clicks in paper_handling, a bit higher + crisper
for i, (t, p) in enumerate([(0.39, 1.12), (3.13, 1.0), (5.40, 1.2)]):
    save(f"snap_{i}", fade(highpass(pitch(cut(H, t, 0.22), p), 6), fout=0.07), -2)

# RIP: paper tearing = crinkle onsets pitched up, layered with a delayed second crackle so it "runs"
onsets = [0.47, 1.47, 1.81, 3.11, 5.38]
for i, t in enumerate(onsets):
    a = pitch(cut(C, t, 0.45), 1.35)
    b = pitch(cut(C, onsets[(i + 2) % 5], 0.35), 1.6)
    save(f"rip_{i}", fade(highpass(mix(a, np.concatenate([np.zeros(int(0.05 * SR)), b * 0.6])), 4), fout=0.12), -3)

# CRUMPLE: a smash squashing paper = longer crinkle bursts, slightly lower (heavier)
for i, t in enumerate([0.40, 1.40, 5.30]):
    save(f"crumple_{i}", fade(pitch(cut(C, t, 0.75), 0.88), fout=0.2), -2)

# THUMP: a lopp landing hard = the big handling hit pitched way down + low-passed (body, not crackle)
save("thump", fade(lowpass(pitch(cut(H, 3.13, 0.25), 0.45), 12), fout=0.15), -3)

# FLUTTER: torn bits falling = flutter onsets
for i, t in enumerate([0.23, 7.57, 17.98]):
    save(f"flutter_{i}", fade(cut(F, t, 0.7), fin=0.03, fout=0.3), -10)

# HOP: soft paper tap when a lopp hops/lands
for i, (t, p) in enumerate([(0.39, 0.8), (3.23, 0.75), (5.40, 0.85)]):
    save(f"hop_{i}", fade(lowpass(pitch(cut(H, t, 0.12), p), 3), fout=0.05), -12)

# OPEN: jaws pulling open (rustle) = quiet flutter slice, pitched up
for i, t in enumerate([14.57, 15.20, 23.20]):
    save(f"open_{i}", fade(pitch(cut(F, t, 0.35), 1.25), fin=0.02, fout=0.12), -12)
