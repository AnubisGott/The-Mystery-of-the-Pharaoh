# Generates soft sand-footstep WAVs (44.1 kHz, 16-bit mono, ~0.16 s).
# Each step is a low "thump" (decaying sine sweep) plus a filtered
# noise "scuff", normalized to a moderate level.
#
# Run:  python tools/make_footsteps.py
# Writes sounds/footstep_sand_1.wav ... _4.wav
import math
import os
import random
import struct
import wave

RATE = 44100
DURATION = 0.22
VARIANTS = 4


def generate(seed: int, path: str) -> None:
    # Dune sand: a soft muffled "shff" - heavily low-passed noise with a
    # slow attack and gentle decay, and only a hint of a thump.
    rnd = random.Random(seed)
    count = int(RATE * DURATION)
    thump_freq = rnd.uniform(55.0, 70.0)
    noise_cutoff = rnd.uniform(0.05, 0.08)
    samples = []
    low_pass = 0.0

    for i in range(count):
        t = i / RATE

        white = rnd.uniform(-1.0, 1.0)
        low_pass += noise_cutoff * (white - low_pass)
        scuff_env = math.exp(-t * 16.0) * min(1.0, t / 0.02)
        scuff = low_pass * scuff_env * 3.0

        thump = math.sin(math.tau * thump_freq * t) * math.exp(-t * 30.0)

        samples.append(0.85 * scuff + 0.12 * thump)

    peak = max(abs(s) for s in samples)
    samples = [s / peak * 0.35 for s in samples]

    with wave.open(path, "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(b"".join(struct.pack("<h", int(s * 32767)) for s in samples))
    print("wrote", path)


def main() -> None:
    os.makedirs("sounds", exist_ok=True)
    for i in range(VARIANTS):
        generate(1000 + i, os.path.join("sounds", "footstep_sand_%d.wav" % (i + 1)))


main()
