import os, numpy as np, aud
HIS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "sounds", "his")
for f in sorted(os.listdir(HIS)):
    if not f.endswith(".mp3"): continue
    s = aud.Sound(os.path.join(HIS, f)); sr = int(s.specs[0])
    d = np.asarray(s.data(), dtype=np.float64)
    a = d.mean(axis=1) if d.ndim > 1 else d
    a = np.interp(np.arange(int(len(a) * 48000 / sr)) * sr / 48000, np.arange(len(a)), a)
    win = 480  # 10 ms
    env = np.sqrt(np.convolve(a * a, np.ones(win) / win, mode="same"))
    print(f"\n{f}: {len(a)/48000:.2f}s peak {np.abs(a).max():.2f}")
    # onsets = places where 10ms energy jumps a lot vs the 50ms before
    hop = 240; pts = []
    for i in range(2400, len(a) - hop, hop):
        prev = env[i - 2400:i - 240].mean() + 1e-4
        if env[i] > 0.08 and env[i] / prev > 3.0 and (not pts or i - pts[-1][0] > 4800):
            pts.append((i, env[i]))
    print("  onsets (s, level):", " ".join(f"{i/48000:.2f}/{v:.2f}" for i, v in pts[:40]))
    # loudness over time in 0.25 s blocks
    blk = 12000
    print("  rms/0.25s:", " ".join(f"{np.sqrt((a[i:i+blk]**2).mean()):.2f}" for i in range(0, len(a), blk))[:600])
