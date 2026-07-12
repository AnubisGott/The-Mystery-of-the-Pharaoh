# Generates the crocodile-landing thud WAV (44.1 kHz, 16-bit mono,
# ~0.18 s): a soft low thump with a tiny wet tail, for the moment the
# player lands on a crocodile's back. Deliberately short and quiet —
# it plays on every hop across the river.
#
# NOTE: the project's sound effects are meant to come from the HeartMula AI
# music generator (see specification.txt); this is a procedural stand-in
# that can be swapped for a HeartMula-generated clip.
#
# Run:  python tools/make_croc_land.py
# Writes sounds/croc_land.wav
import math
import os
import random
import struct
import wave

RATE = 44100
DURATION = 0.18


def main() -> None:
    os.makedirs("sounds", exist_ok=True)
    random.seed(5)
    count = int(RATE * DURATION)
    samples = []
    phase = 0.0
    lp = 0.0
    for i in range(count):
        t = i / RATE
        # The thump: a quickly decaying low sine that droops in pitch.
        phase += math.tau * (95.0 - 60.0 * min(t / DURATION, 1.0)) / RATE
        thump = math.sin(phase) * math.exp(-t * 30.0)
        # The wet part: a little burst of low-passed noise right after.
        lp += 0.2 * (random.uniform(-1.0, 1.0) - lp)
        splash = lp * math.exp(-t * 12.0) * min(t / 0.02, 1.0)
        samples.append(thump + splash * 0.45)

    peak = max(abs(s) for s in samples)
    samples = [s / peak * 0.5 for s in samples]
    path = os.path.join("sounds", "croc_land.wav")
    with wave.open(path, "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(b"".join(struct.pack("<h", int(s * 32767)) for s in samples))
    print("wrote", path)


main()
