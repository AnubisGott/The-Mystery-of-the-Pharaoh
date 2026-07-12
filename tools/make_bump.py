# Generates the obstacle-bump WAV (44.1 kHz, 16-bit mono, ~0.22 s): a
# dull body blow — a fast-decaying low thump with a mid knock — for
# slamming into a stone block on the slide.
#
# NOTE: the project's sound effects are meant to come from the HeartMula AI
# music generator (see specification.txt); this is a procedural stand-in
# that can be swapped for a HeartMula-generated clip.
#
# Run:  python tools/make_bump.py
# Writes sounds/bump.wav
import math
import os
import random
import struct
import wave

RATE = 44100
DURATION = 0.22


def main() -> None:
    os.makedirs("sounds", exist_ok=True)
    random.seed(3)
    count = int(RATE * DURATION)
    samples = []
    phase_low = 0.0
    phase_mid = 0.0
    lp = 0.0
    for i in range(count):
        t = i / RATE
        phase_low += math.tau * (70.0 - 30.0 * min(t / DURATION, 1.0)) / RATE
        phase_mid += math.tau * 160.0 / RATE
        thump = math.sin(phase_low) * math.exp(-t * 22.0)
        knock = math.sin(phase_mid) * math.exp(-t * 45.0) * 0.5
        lp += 0.25 * (random.uniform(-1.0, 1.0) - lp)
        scuff = lp * math.exp(-t * 35.0) * 0.3
        samples.append(thump + knock + scuff)

    peak = max(abs(s) for s in samples)
    samples = [s / peak * 0.5 for s in samples]
    path = os.path.join("sounds", "bump.wav")
    with wave.open(path, "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(b"".join(struct.pack("<h", int(s * 32767)) for s in samples))
    print("wrote", path)


main()
