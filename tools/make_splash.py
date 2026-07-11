# Generates sounds/splash_blub.wav: a water splash followed by three
# sinking "blub" bubbles. Run from the project root:
#   python tools/make_splash.py
import math
import random
import struct
import wave

RATE = 22050
DURATION = 1.15
OUT = "sounds/splash_blub.wav"

random.seed(7)

samples = []
for i in range(int(RATE * DURATION)):
    t = i / RATE
    s = 0.0

    # The initial splash: a short, decaying noise burst.
    if t < 0.18:
        s += random.uniform(-1.0, 1.0) * (1.0 - t / 0.18) ** 2 * 0.55

    # Three descending blubs, each a short warbling sine.
    for k, t0 in enumerate((0.22, 0.48, 0.74)):
        if t0 <= t < t0 + 0.13:
            tt = t - t0
            freq = 270.0 - 70.0 * k - 260.0 * tt
            wobble = 5.0 * math.sin(2.0 * math.pi * 28.0 * tt)
            amp = math.sin(math.pi * tt / 0.13) * (0.5 - 0.08 * k)
            s += math.sin(2.0 * math.pi * freq * tt + wobble) * amp

    samples.append(max(-1.0, min(1.0, s)))

with wave.open(OUT, "wb") as f:
    f.setnchannels(1)
    f.setsampwidth(2)
    f.setframerate(RATE)
    f.writeframes(b"".join(
        struct.pack("<h", int(s * 32000)) for s in samples))
print("wrote", OUT)
