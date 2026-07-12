# Generates the burial-chamber stone sounds (44.1 kHz, 16-bit mono):
#   sounds/stone_turn.wav   (~0.18 s) a short dry crack as the dial
#                           clacks into its next notch
#   sounds/stone_rumble.wav (~1.8 s)  the pit floor dropping open
# The rumble is layered filtered noise with a gravelly modulation and a
# heavy boom at the start; the crack is two quick snappy noise bursts.
#
# NOTE: the project's sound effects are meant to come from the HeartMula AI
# music generator (see specification.txt); this is a procedural stand-in
# that can be swapped for a HeartMula-generated clip.
#
# Run:  python tools/make_stone_sounds.py
import math
import os
import random
import struct
import wave

RATE = 44100


def write_wav(name: str, samples: list, peak: float) -> None:
    top = max(abs(s) for s in samples)
    samples = [s / top * peak for s in samples]
    path = os.path.join("sounds", name)
    with wave.open(path, "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(b"".join(struct.pack("<h", int(s * 32767)) for s in samples))
    print("wrote", path)


def grind(duration: float, seed: int) -> list:
    random.seed(seed)
    count = int(RATE * duration)
    lp_slow = 0.0
    lp_mid = 0.0
    samples = []
    for i in range(count):
        t = i / RATE
        n = random.uniform(-1.0, 1.0)
        lp_slow += 0.04 * (n - lp_slow)
        lp_mid += 0.16 * (n - lp_mid)
        # Gravel: fast irregular judder over the scrape.
        judder = 1.0 + 0.5 * math.sin(math.tau * 23.0 * t) \
                * math.sin(math.tau * 7.3 * t + 1.2)
        attack = min(t / 0.06, 1.0)
        release = min((duration - t) / 0.15, 1.0)
        samples.append((lp_slow * 1.2 + (lp_mid - lp_slow) * 0.5)
                * judder * attack * release)
    return samples


# A snappy stone clack: an instant noise burst with a fast decay, plus
# a fainter echo-crack right after (the notch seating itself).
def crack(duration: float, seed: int) -> list:
    random.seed(seed)
    count = int(RATE * duration)
    hp_last = 0.0
    samples = []
    for i in range(count):
        t = i / RATE
        n = random.uniform(-1.0, 1.0)
        high = n - hp_last * 0.6   # crude high-pass: snappy, not rumbly
        hp_last = n
        hit = math.exp(-t * 90.0)
        echo = math.exp(-max(t - 0.06, 0.0) * 120.0) * (0.35 if t >= 0.06 else 0.0)
        samples.append(high * (hit + echo))
    return samples


def main() -> None:
    os.makedirs("sounds", exist_ok=True)

    write_wav("stone_turn.wav", crack(0.18, seed=11), 0.4)

    # The pitfall: a boom, then a long grinding decay.
    body = grind(1.8, seed=23)
    boom_phase = 0.0
    for i in range(len(body)):
        t = i / RATE
        boom_phase += math.tau * (55.0 - 20.0 * min(t / 1.8, 1.0)) / RATE
        boom = math.sin(boom_phase) * math.exp(-t * 3.0)
        decay = math.exp(-t * 1.4)
        body[i] = body[i] * (0.4 + 0.6 * decay) + boom * 0.9
    write_wav("stone_rumble.wav", body, 0.62)


main()
