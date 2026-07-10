# Generates the spear hit/death sound (44.1 kHz, 16-bit mono, ~0.35 s):
# a hard body thud (decaying sine sweep) with a short noise punch.
#
# Run:  python tools/make_hit.py
# Writes sounds/spear_hit.wav
import math
import os
import random
import struct
import wave

RATE = 44100
DURATION = 0.35


def main() -> None:
    rnd = random.Random(42)
    count = int(RATE * DURATION)
    samples = []
    low_pass = 0.0

    for i in range(count):
        t = i / RATE

        freq = 90.0 * max(0.45, 1.0 - t * 3.0)
        thump = math.sin(math.tau * freq * t) * math.exp(-t * 18.0)

        white = rnd.uniform(-1.0, 1.0)
        low_pass += 0.3 * (white - low_pass)
        punch = low_pass * math.exp(-t * 60.0) * 1.6

        samples.append(0.8 * thump + 0.5 * punch)

    peak = max(abs(s) for s in samples)
    samples = [s / peak * 0.6 for s in samples]

    os.makedirs("sounds", exist_ok=True)
    path = os.path.join("sounds", "spear_hit.wav")
    with wave.open(path, "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(b"".join(struct.pack("<h", int(s * 32767)) for s in samples))
    print("wrote", path)


main()
