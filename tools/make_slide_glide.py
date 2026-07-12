# Generates the Level-5 gliding loop WAV (44.1 kHz, 16-bit mono, 2.0 s):
# layered filtered noise that reads as sliding down a stone chute — a deep
# rumble plus a lighter scrape, with a slow loop-periodic wobble. The tail
# is crossfaded into the head so the clip loops seamlessly.
#
# NOTE: the project's sound effects are meant to come from the HeartMula AI
# music generator (see specification.txt); this is a procedural stand-in
# that can be swapped for a HeartMula-generated clip.
#
# Run:  python tools/make_slide_glide.py
# Writes sounds/slide_glide.wav
import math
import os
import random
import struct
import wave

RATE = 44100
DURATION = 2.0
FADE = int(RATE * 0.08)   # loop-splice crossfade


def main() -> None:
    os.makedirs("sounds", exist_ok=True)
    random.seed(7)
    count = int(RATE * DURATION)

    # One-pole low-pass states: slow = rumble, fast - mid = scrape band.
    lp_slow = 0.0
    lp_mid = 0.0
    lp_fast = 0.0
    samples = []
    for i in range(count + FADE):
        t = i / RATE
        n = random.uniform(-1.0, 1.0)
        lp_slow += 0.05 * (n - lp_slow)
        lp_mid += 0.14 * (n - lp_mid)
        lp_fast += 0.45 * (n - lp_fast)
        # Wobble frequencies are whole cycles per loop (k / DURATION), so
        # the modulation is continuous across the loop point.
        wobble = 1.0 + 0.16 * math.sin(math.tau * 1.5 * t + 0.7) \
                + 0.10 * math.sin(math.tau * 3.5 * t + 2.1)
        samples.append((lp_slow * 1.0 + (lp_fast - lp_mid) * 0.4) * wobble)

    # Blend the extra tail over the head: the filter state carries on into
    # the tail, so the splice back to sample 0 is seamless.
    for i in range(FADE):
        k = i / FADE
        samples[i] = samples[i] * k + samples[count + i] * (1.0 - k)
    samples = samples[:count]

    peak = max(abs(s) for s in samples)
    samples = [s / peak * 0.4 for s in samples]

    path = os.path.join("sounds", "slide_glide.wav")
    with wave.open(path, "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(b"".join(struct.pack("<h", int(s * 32767)) for s in samples))
    print("wrote", path)


main()
