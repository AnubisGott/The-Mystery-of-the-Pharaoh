# Generates spear whoosh WAVs (44.1 kHz, 16-bit mono, ~0.6 s): band-passed
# noise with a rise-and-fall sweep and envelope.
#
# Run:  python tools/make_whoosh.py
# Writes sounds/spear_whoosh_1.wav and _2.wav
import math
import os
import random
import struct
import wave

RATE = 44100
DURATION = 0.6
VARIANTS = 2


def generate(seed: int, path: str) -> None:
    rnd = random.Random(seed)
    count = int(RATE * DURATION)
    base_freq = rnd.uniform(300.0, 420.0)
    sweep = rnd.uniform(800.0, 1100.0)
    samples = []
    lp1 = 0.0
    lp2 = 0.0

    for i in range(count):
        t = i / RATE
        progress = t / DURATION

        envelope = math.sin(math.pi * progress) ** 2
        cutoff = base_freq + sweep * math.sin(math.pi * progress)
        alpha = 1.0 - math.exp(-math.tau * cutoff / RATE)

        white = rnd.uniform(-1.0, 1.0)
        lp1 += alpha * (white - lp1)
        lp2 += alpha * (lp1 - lp2)
        band = lp1 - lp2  # crude band-pass

        samples.append(band * envelope * 3.0)

    peak = max(abs(s) for s in samples)
    samples = [s / peak * 0.45 for s in samples]

    with wave.open(path, "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(b"".join(struct.pack("<h", int(s * 32767)) for s in samples))
    print("wrote", path)


def main() -> None:
    os.makedirs("sounds", exist_ok=True)
    for i in range(VARIANTS):
        generate(2000 + i, os.path.join("sounds", "spear_whoosh_%d.wav" % (i + 1)))


main()
