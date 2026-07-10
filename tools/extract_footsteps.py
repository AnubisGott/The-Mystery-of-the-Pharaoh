# Extracts single footsteps from a CC0 field recording of walking on dry
# desert sand (felix.blume, freesound.org sound 705743) and writes them
# as sounds/footstep_sand_1.wav ... _4.wav.
#
# Run:  python tools/extract_footsteps.py
# Needs ffmpeg on PATH. The source recording is public domain (CC0).
import array
import math
import os
import statistics
import struct
import subprocess
import tempfile
import urllib.request
import wave

SOURCE_URL = "https://cdn.freesound.org/previews/705/705743_1661766-hq.mp3"
RATE = 44100
WINDOW = 1024
PRE_SECONDS = 0.06
POST_SECONDS = 0.32
FADE_IN = 0.01
FADE_OUT = 0.10
VARIANTS = 4


def load_source() -> array.array:
    tmp_dir = tempfile.mkdtemp()
    mp3_path = os.path.join(tmp_dir, "source.mp3")
    wav_path = os.path.join(tmp_dir, "source.wav")
    print("downloading", SOURCE_URL)
    urllib.request.urlretrieve(SOURCE_URL, mp3_path)
    subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-i", mp3_path,
         "-ac", "1", "-ar", str(RATE), wav_path],
        check=True,
    )
    with wave.open(wav_path, "rb") as src:
        data = array.array("h")
        data.frombytes(src.readframes(src.getnframes()))
    return data


def rms_envelope(data: array.array) -> list:
    envelope = []
    for start in range(0, len(data) - WINDOW, WINDOW):
        total = 0
        for i in range(start, start + WINDOW):
            total += data[i] * data[i]
        envelope.append(math.sqrt(total / WINDOW))
    return envelope


def find_step_onsets(envelope: list) -> list:
    threshold = statistics.median(envelope) * 4.0
    min_gap = int(0.5 * RATE / WINDOW)
    onsets = []
    last = -min_gap
    for i in range(1, len(envelope)):
        if envelope[i] > threshold and envelope[i - 1] <= threshold and i - last >= min_gap:
            onsets.append(i)
            last = i
    return onsets


def cut_step(data: array.array, onset_window: int, path: str) -> None:
    onset = onset_window * WINDOW
    start = max(0, onset - int(PRE_SECONDS * RATE))
    end = min(len(data), onset + int(POST_SECONDS * RATE))
    samples = [s / 32768.0 for s in data[start:end]]

    fade_in = int(FADE_IN * RATE)
    fade_out = int(FADE_OUT * RATE)
    for i in range(min(fade_in, len(samples))):
        samples[i] *= i / fade_in
    for i in range(min(fade_out, len(samples))):
        samples[-1 - i] *= i / fade_out

    peak = max(abs(s) for s in samples) or 1.0
    samples = [s / peak * 0.4 for s in samples]

    with wave.open(path, "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(b"".join(struct.pack("<h", int(s * 32767)) for s in samples))
    print("wrote", path)


def main() -> None:
    data = load_source()
    envelope = rms_envelope(data)
    onsets = find_step_onsets(envelope)
    if len(onsets) < VARIANTS:
        raise SystemExit("only found %d step onsets" % len(onsets))

    # Skip the first steps (recorder handling) and spread picks out so the
    # variants do not come from one identical stretch.
    usable = onsets[4:-4] if len(onsets) > 12 else onsets
    stride = max(1, len(usable) // VARIANTS)
    os.makedirs("sounds", exist_ok=True)
    for i in range(VARIANTS):
        cut_step(data, usable[i * stride], os.path.join("sounds", "footstep_sand_%d.wav" % (i + 1)))


main()
