"""tool/gen_game_sounds.py — the game sound set, synthesized here (Games v3, owner decision 2026-11-22).

Every sound of the games is MADE by this script from sine tones, soft envelopes and a little filtered noise: nothing
is downloaded, sampled or taken from a stock library, so the set is the project's own and can be regenerated.

    py -3.12 -m pip install numpy soundfile
    py -3.12 tool/gen_game_sounds.py                 # writes assets/sounds/games/<name>.ogg + <name>.mp3
    py -3.12 tool/gen_game_sounds.py --out <dir> --wav   # also the WAV masters (to listen, never shipped)

The set (calm on purpose: a Quran / children context, so no melody that reads as music, no harsh buzzer):

    tap        a soft short blip                         pick / place
    correct    a rising two-note chime (D5 -> A5)
    wrong      a soft low thud                           never a buzzer
    combo      three quick rising notes                  3 right in a row
    snap       a small bright pluck                      a connector lands on its pair
    flip       a short airy whoosh                       a memory card turns
    finish     four rising notes                         the round ends
    champion   a slow rising arpeggio that rings out     the champion sheet (the only one over 600 ms)

Rules the script checks before it writes anything (it exits 1 otherwise):
  * every sound <= 600 ms, `champion` <= 2 s;
  * loudness: each sound is brought to the same active RMS (TARGET_RMS_DB, with a per-sound trim so a tap is quieter
    than a fanfare) and its peak is kept under PEAK_DB;
  * the encoded set (ogg + mp3 together) <= 150 KB.
The output is deterministic: the only noise (flip) uses a fixed seed. OGG Vorbis is for Android, desktop, Chrome and
Firefox; MP3 is the web-safe / iOS copy (Safari does not play Vorbis everywhere).
"""
from __future__ import annotations

import argparse
import sys
import wave
from pathlib import Path

import numpy as np

SR = 32_000                 # Hz, mono: plenty for tones under 4 kHz, half the bytes of 44.1 kHz stereo
TARGET_RMS_DB = -20.0       # active RMS every sound is brought to (before its trim)
PEAK_DB = -1.5              # no sample above this
MAX_MS, MAX_FANFARE_MS = 600, 2000
MAX_TOTAL_BYTES = 150_000
NAMES = ("tap", "correct", "wrong", "combo", "snap", "flip", "finish", "champion")
# how far under the target a sound sits (dB): small, frequent sounds are quieter than the rare ones
TRIM_DB = {"tap": -8.0, "snap": -5.0, "flip": -7.0, "wrong": -3.0, "correct": -2.0, "combo": -2.0, "finish": -1.0,
           "champion": 0.0}

# note frequencies (Hz), D major pentatonic
D4, A4, D5, E5, FS5, A5, B5, D6 = 293.66, 440.00, 587.33, 659.25, 739.99, 880.00, 987.77, 1174.66


# ── building blocks ───────────────────────────────────────────────────────────

def _t(ms: float) -> np.ndarray:
    return np.arange(int(SR * ms / 1000)) / SR


def _silence(ms: float) -> np.ndarray:
    return np.zeros(int(SR * ms / 1000))


def _env(n: int, attack_ms: float, decay_s: float) -> np.ndarray:
    """A linear attack then an exponential decay with time constant `decay_s`."""
    t = np.arange(n) / SR
    a = max(1, int(SR * attack_ms / 1000))
    e = np.exp(-t / decay_s)
    e[:a] *= np.linspace(0.0, 1.0, a)
    return e


def bell(freq: float, ms: float, decay_s: float = 0.12, attack_ms: float = 4.0) -> np.ndarray:
    """A soft bell: the tone, a quiet octave and a quieter twelfth, each fading faster than the one below."""
    t = _t(ms)
    n = len(t)
    return (np.sin(2 * np.pi * freq * t) * _env(n, attack_ms, decay_s)
            + 0.28 * np.sin(2 * np.pi * 2 * freq * t) * _env(n, attack_ms, decay_s * 0.6)
            + 0.10 * np.sin(2 * np.pi * 3 * freq * t) * _env(n, attack_ms, decay_s * 0.35))


def sweep(f0: float, f1: float, ms: float, decay_s: float, attack_ms: float = 3.0) -> np.ndarray:
    """A sine that glides from f0 to f1 (exponentially) while it fades."""
    t = _t(ms)
    k = np.log(f1 / f0) / (ms / 1000)
    phase = 2 * np.pi * f0 * (np.exp(k * t) - 1) / k
    return np.sin(phase) * _env(len(t), attack_ms, decay_s)


def mix(total_ms: float, *parts: tuple[float, np.ndarray]) -> np.ndarray:
    """Lay each (start_ms, samples) on a silent track of total_ms."""
    out = _silence(total_ms)
    for start_ms, x in parts:
        i = int(SR * start_ms / 1000)
        x = x[: max(0, len(out) - i)]
        out[i:i + len(x)] += x
    return out


def lowpass(x: np.ndarray, cutoff: np.ndarray | float) -> np.ndarray:
    """A one-pole low-pass; `cutoff` (Hz) may change over time (an array as long as x)."""
    c = np.broadcast_to(np.asarray(cutoff, dtype=float), x.shape)
    a = 1 - np.exp(-2 * np.pi * c / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc += a[i] * (x[i] - acc)
        y[i] = acc
    return y


# ── the sounds ────────────────────────────────────────────────────────────────

def tap() -> np.ndarray:
    return sweep(820, 640, 70, decay_s=0.018, attack_ms=2)


def correct() -> np.ndarray:
    return mix(430, (0, bell(D5, 300, 0.09)), (110, bell(A5, 320, 0.11)))


def wrong() -> np.ndarray:
    body = sweep(165, 92, 260, decay_s=0.07, attack_ms=6)
    return lowpass(body + 0.25 * sweep(330, 184, 260, decay_s=0.03, attack_ms=6), 900)


def combo() -> np.ndarray:
    return mix(460, (0, bell(A5, 200, 0.06)), (70, bell(B5, 200, 0.06)), (140, bell(D6, 320, 0.10)))


def snap() -> np.ndarray:
    return mix(130, (0, sweep(1250, 1560, 110, decay_s=0.022, attack_ms=1.5)), (0, 0.5 * bell(D6, 110, 0.03, 1.5)))


def flip() -> np.ndarray:
    n = len(_t(170))
    noise = np.random.default_rng(20261122).standard_normal(n)
    t = np.arange(n) / n
    air = lowpass(noise, 700 + 2600 * np.sin(np.pi * t) ** 2)      # the filter opens and closes: a soft whoosh
    return air * np.sin(np.pi * t) ** 1.5


def finish() -> np.ndarray:
    return mix(600, (0, bell(D5, 300, 0.08)), (85, bell(FS5, 300, 0.08)), (170, bell(A5, 320, 0.09)),
               (255, bell(D6, 345, 0.12)))


def champion() -> np.ndarray:
    notes = ((0, D4), (130, A4), (260, D5), (390, FS5), (520, A5), (680, D6))
    parts = [(at, (0.8 if f < D5 else 1.0) * bell(f, 1900 - at, 0.38, 8)) for at, f in notes]
    return mix(1900, *parts, (680, 0.35 * bell(D5, 1220, 0.45, 20)))      # the low note comes back under the top one


SOUNDS = {"tap": tap, "correct": correct, "wrong": wrong, "combo": combo, "snap": snap, "flip": flip,
          "finish": finish, "champion": champion}


# ── loudness, edges, checks ───────────────────────────────────────────────────

def _db(x: float) -> float:
    return 20 * np.log10(max(x, 1e-12))


def active_rms(x: np.ndarray) -> float:
    """RMS over the 20 ms windows that are not near-silent (so a long tail does not make a sound 'quiet')."""
    w = int(SR * 0.02)
    frames = [x[i:i + w] for i in range(0, max(1, len(x) - w + 1), w)]
    rms = np.array([np.sqrt(np.mean(f ** 2)) for f in frames])
    loud = rms[rms > rms.max() * 0.1]
    return float(np.sqrt(np.mean(loud ** 2)))


def finalize(name: str, x: np.ndarray) -> np.ndarray:
    x = x - np.mean(x)
    fade_in, fade_out = int(SR * 0.002), int(SR * 0.012)
    x[:fade_in] *= np.linspace(0, 1, fade_in)
    x[-fade_out:] *= np.linspace(1, 0, fade_out)
    x = x * 10 ** ((TARGET_RMS_DB + TRIM_DB[name] - _db(active_rms(x))) / 20)
    peak = float(np.max(np.abs(x)))
    ceiling = 10 ** (PEAK_DB / 20)
    if peak > ceiling:                         # keep the shape: scale down, never clip
        x = x * (ceiling / peak)
    return x


def write_wav(path: Path, x: np.ndarray) -> None:
    with wave.open(str(path), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SR)
        f.writeframes((np.clip(x, -1, 1) * 32767).astype("<i2").tobytes())


def main() -> int:
    ap = argparse.ArgumentParser(description="Synthesize the game sounds (no downloaded audio).")
    ap.add_argument("--out", default=str(Path(__file__).resolve().parent.parent / "assets" / "sounds" / "games"))
    ap.add_argument("--wav", action="store_true", help="also write the WAV masters")
    ap.add_argument("--wav-only", action="store_true", help="WAV only (no soundfile needed); not for shipping")
    args = ap.parse_args()

    sf = None
    if not args.wav_only:
        try:
            import soundfile as sf     # libsndfile: OGG Vorbis and MP3 encoders
        except ImportError:
            print("soundfile is missing: py -3.12 -m pip install soundfile   (or --wav-only to listen)")
            return 1
        missing = [f for f in ("OGG", "MP3") if f not in sf.available_formats()]
        if missing:
            print(f"this libsndfile cannot write {missing}: upgrade soundfile (>= 0.12)")
            return 1

    built = {}
    for name in NAMES:
        x = finalize(name, SOUNDS[name]())
        ms = len(x) * 1000 / SR
        limit = MAX_FANFARE_MS if name == "champion" else MAX_MS
        if ms > limit + 0.5:
            print(f"{name}: {ms:.0f} ms is over the {limit} ms limit")
            return 1
        built[name] = x

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    total = 0
    print(f"{'sound':<10}{'ms':>6}{'peak dB':>9}{'rms dB':>8}{'ogg B':>8}{'mp3 B':>8}")
    for name, x in built.items():
        sizes = []
        if sf is not None:
            for ext, fmt, sub in (("ogg", "OGG", "VORBIS"), ("mp3", "MP3", "MPEG_LAYER_III")):
                p = out / f"{name}.{ext}"
                sf.write(str(p), x.astype("float32"), SR, format=fmt, subtype=sub)
                sizes.append(p.stat().st_size)
            total += sum(sizes)
        if args.wav or args.wav_only:
            write_wav(out / f"{name}.wav", x)
        ms = len(x) * 1000 / SR
        cols = "".join(f"{s:>8}" for s in sizes) if sizes else f"{'-':>8}{'-':>8}"
        print(f"{name:<10}{ms:>6.0f}{_db(float(np.max(np.abs(x)))):>9.1f}{_db(active_rms(x)):>8.1f}{cols}")
    if sf is not None:
        print(f"total {total} bytes (limit {MAX_TOTAL_BYTES}) -> {out}")
        if total > MAX_TOTAL_BYTES:
            print("the set is over the size limit")
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
