# Generates a falling-bomb whistle WAV (44.1 kHz, 16-bit mono, ~1.4 s): a
# sine tone whose pitch sweeps exponentially downward with a light vibrato,
# for the moment the player drops into a pit.
#
# NOTE: the project's sound effects are meant to come from the HeartMula AI
# music generator (see specification.txt); this is a procedural stand-in
# that can be swapped for a HeartMula-generated clip.
#
# Run:  python tools/make_bomb_whistle.py
# Writes sounds/bomb_whistle.wav
import math
import os
import struct
import wave

RATE = 44100
DURATION = 1.4
F_START = 1500.0
F_END = 240.0


def main() -> None:
    os.makedirs("sounds", exist_ok=True)
    count = int(RATE * DURATION)
    samples = []
    phase = 0.0

    for i in range(count):
        t = i / RATE
        progress = t / DURATION
        # Exponential descending sweep reads as a falling object.
        freq = F_START * (F_END / F_START) ** progress
        vibrato = 1.0 + 0.02 * math.sin(math.tau * 6.0 * t)
        phase += math.tau * freq * vibrato / RATE
        # Sine plus a touch of second harmonic for an airier whistle.
        tone = math.sin(phase) + 0.15 * math.sin(2.0 * phase)
        # Quick attack, steady body, gentle fall-off at the very end.
        attack = min(t / 0.04, 1.0)
        release = 1.0 if progress < 0.9 else (1.0 - (progress - 0.9) / 0.1)
        samples.append(tone * attack * release)

    peak = max(abs(s) for s in samples)
    samples = [s / peak * 0.5 for s in samples]

    path = os.path.join("sounds", "bomb_whistle.wav")
    with wave.open(path, "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(b"".join(struct.pack("<h", int(s * 32767)) for s in samples))
    print("wrote", path)


main()
