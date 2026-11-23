"""tool/gen_game_sounds.py — the game sounds and the two background loops, synthesized here (Games v3 / v4).

Every sound of the games is MADE by this script from sine tones, soft envelopes and a little filtered noise: nothing
is downloaded, sampled or taken from a stock library, so the set is the project's own and can be regenerated.

    py -3.12 -m pip install numpy soundfile
    py -3.12 tool/gen_game_sounds.py                 # writes assets/sounds/games/<name>.mp3 (MP3 only, the default)
    py -3.12 tool/gen_game_sounds.py --out <dir> --wav   # also the WAV masters (to listen, never shipped)
    py -3.12 tool/gen_game_sounds.py --out <dir> --ogg   # also OGG Vorbis copies (not shipped: MP3 plays everywhere)

The effects (calm on purpose: a Quran / children context, so no melody that reads as music, no harsh buzzer):

    tap        a soft short blip                         pick / place
    correct    a rising two-note chime (D5 -> A5)
    wrong      a soft low thud                           never a buzzer
    combo      three quick rising notes                  3 right in a row
    snap       a small bright pluck                      a connector lands on its pair
    flip       a short airy whoosh                       a memory card turns
    finish     four rising notes                         the round ends
    champion   a slow rising arpeggio that rings out     the champion sheet (the only one over 1.5 s)
    pop        a soft bubble pop                         a bubble / a balloon
    splash     a short drop of water, three droplets     a thing sinks in
    whoosh     a longer airy swell                       a panel slides
    chime      a bell-like pair, a fifth apart           a constellation link
    coin       two bright quick notes                    a reward
    level_up   a rising arpeggio that rings (1.5 s)      a level up
    lane       a soft high swoosh                        a lane change
    boost      a quick rising glide                      a speed-up
    couple     two soft clacks and a low thump           a train wagon joins
    grow       a gentle rising tone                      something grows
    chest      a sparkle of rising notes                 a chest opens
    retry      a soft neutral two-note (E5 -> A5)        try again: never a buzzer

The two loops (background music, quieter than the effects):

    music_kids   12 s, 120 BPM, bright and playful: a bell melody over a plucked bass, six bars
    music_calm   16 s, slow and warm: four chords of soft pads with sparse bells

A loop is built by WRAPPING every note and pad that runs past the end back to the start, and every sine has a whole
number of cycles in the loop, so the last sample is the sample before the first: the loop joins onto itself.

Rules the script checks before it writes anything (it exits 1 otherwise):
  * every effect <= 800 ms, `level_up` <= 1.5 s, `champion` <= 2 s; each loop is exactly its length;
  * loudness: each sound is brought to the same active RMS (TARGET_RMS_DB, with a per-sound trim so a tap is quieter
    than a fanfare; the loops sit under the effects) and its peak is kept under PEAK_DB;
  * the encoded effects <= 150 KB and each effect MP3 <= 12 KB (test/ui/games_v3_motion_test.dart checks the files);
  * each loop MP3 <= 400 KB and <= 96 kbps (mono).
The output is deterministic: the only noise uses fixed seeds. Only MP3 ships (PLAN §11, D-1741): it plays on
Android, iOS and the web, so the app needs no per-platform switch.
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
MAX_MS = 800                # every effect, unless listed in LIMIT_MS
LIMIT_MS = {"level_up": 1500, "champion": 2000}
MAX_TOTAL_BYTES = 150_000
MAX_FILE_BYTES = 12_000
MAX_LOOP_BYTES = 400_000
MAX_LOOP_KBPS = 96
EFFECTS = ("tap", "correct", "wrong", "combo", "snap", "flip", "finish", "champion",
           "pop", "splash", "whoosh", "chime", "coin", "level_up", "lane", "boost", "couple", "grow", "chest", "retry")
LOOP_MS = {"music_kids": 12_000, "music_calm": 16_000}
NAMES = EFFECTS + tuple(LOOP_MS)
# how far under the target a sound sits (dB): small, frequent sounds are quieter than the rare ones
TRIM_DB = {"tap": -8.0, "snap": -5.0, "flip": -7.0, "wrong": -3.0, "correct": -2.0, "combo": -2.0, "finish": -1.0,
           "champion": 0.0, "pop": -6.0, "splash": -4.0, "whoosh": -6.0, "chime": -3.0, "coin": -3.0,
           "level_up": -1.0, "lane": -6.0, "boost": -3.0, "couple": -4.0, "grow": -4.0, "chest": -2.0, "retry": -4.0,
           "music_kids": -6.0, "music_calm": -7.0}

# note frequencies (Hz), D major pentatonic
D2, B1, G2, A2, E3, D3, A3, FS3, B2, G3 = 73.42, 61.74, 98.00, 110.00, 164.81, 146.83, 220.00, 185.00, 123.47, 196.00
D4, A4, D5, E5, FS5, A5, B5, D6 = 293.66, 440.00, 587.33, 659.25, 739.99, 880.00, 987.77, 1174.66
FS4, B3, CS4 = 369.99, 246.94, 277.18


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


def _noise(ms: float, seed: int) -> np.ndarray:
    return np.random.default_rng(seed).standard_normal(len(_t(ms)))


# ── the effects ───────────────────────────────────────────────────────────────

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


def pop() -> np.ndarray:
    return sweep(360, 780, 90, decay_s=0.022, attack_ms=2)


def splash() -> np.ndarray:
    n = len(_t(420))
    t = np.arange(n) / n
    hiss = lowpass(_noise(420, 20261123), 2400 * np.exp(-t * 6) + 300) * np.exp(-t * 7)   # the spray falls away
    drops = mix(420, *[(at, sweep(f0, f0 * 1.6, 70, decay_s=0.02, attack_ms=1))
                       for at, f0 in ((90, 1100), (170, 1400), (250, 900))])
    return 0.8 * hiss + drops


def whoosh() -> np.ndarray:
    n = len(_t(560))
    t = np.arange(n) / n
    air = lowpass(np.random.default_rng(20261124).standard_normal(n), 400 + 1800 * np.sin(np.pi * t) ** 2)
    return air * np.sin(np.pi * t) ** 1.8


def chime() -> np.ndarray:
    return mix(780, (0, bell(A5, 760, 0.22, 3)), (140, 0.7 * bell(E5 * 2, 620, 0.20, 3)))


def coin() -> np.ndarray:
    return mix(330, (0, bell(B5, 300, 0.07, 2)), (60, bell(FS5 * 2, 270, 0.09, 2)))


def level_up() -> np.ndarray:
    notes = ((0, D5), (110, FS5), (220, A5), (330, D6))
    parts = [(at, bell(f, 1300 - at, 0.16, 4)) for at, f in notes]
    return mix(1300, *parts, (560, bell(D6, 740, 0.40, 4)))      # the top note rings out


def lane() -> np.ndarray:
    n = len(_t(360))
    t = np.arange(n) / n
    air = lowpass(np.random.default_rng(20261125).standard_normal(n), 900 + 2200 * t)   # a soft swoosh, rising
    return air * np.sin(np.pi * t) ** 1.2 + 0.15 * sweep(520, 980, 360, decay_s=0.12, attack_ms=20)


def boost() -> np.ndarray:
    return sweep(260, 880, 480, decay_s=0.2, attack_ms=8) + 0.2 * sweep(520, 1760, 480, decay_s=0.12, attack_ms=8)


def _clack(seed: int, ms: float) -> np.ndarray:
    n = len(_t(ms))
    return lowpass(np.random.default_rng(seed).standard_normal(n), 3000) * np.exp(-np.arange(n) / SR / 0.012)


def couple() -> np.ndarray:
    thump = sweep(190, 110, 180, decay_s=0.05, attack_ms=3)
    return mix(420, (0, _clack(20261126, 60)), (0, 0.6 * thump),
               (170, _clack(20261127, 60)), (170, 0.5 * sweep(170, 100, 180, decay_s=0.05, attack_ms=3)))


def grow() -> np.ndarray:
    return sweep(330, 660, 620, decay_s=0.42, attack_ms=90) + 0.3 * sweep(495, 990, 620, decay_s=0.42, attack_ms=90)


def chest() -> np.ndarray:
    notes = ((0, A5), (80, D6), (160, FS5 * 2), (240, A5 * 2))
    parts = [(at, 0.8 * bell(f, 760 - at, 0.14, 3)) for at, f in notes]
    return mix(760, *parts, (300, 0.35 * bell(D6 * 2, 460, 0.08, 2)))


def retry() -> np.ndarray:
    return mix(330, (0, bell(E5, 300, 0.09)), (150, bell(A5, 300, 0.12)))


SOUNDS = {"tap": tap, "correct": correct, "wrong": wrong, "combo": combo, "snap": snap, "flip": flip,
          "finish": finish, "champion": champion, "pop": pop, "splash": splash, "whoosh": whoosh, "chime": chime,
          "coin": coin, "level_up": level_up, "lane": lane, "boost": boost, "couple": couple, "grow": grow,
          "chest": chest, "retry": retry}


# ── the two loops ─────────────────────────────────────────────────────────────

def _loop_buf(loop_ms: float) -> np.ndarray:
    return np.zeros(int(SR * loop_ms / 1000))


def _wrap_add(buf: np.ndarray, start_ms: float, x: np.ndarray) -> None:
    """Add x at start_ms; whatever runs past the end of the loop comes back at the start (the loop stays seamless)."""
    idx = (int(round(SR * start_ms / 1000)) + np.arange(len(x))) % len(buf)
    np.add.at(buf, idx, x)


def _whole_cycles(f: float, loop_ms: float) -> float:
    """f snapped to a whole number of cycles in the loop, so a sine ends exactly where it began."""
    return round(f * loop_ms / 1000) * 1000 / loop_ms


def _pad(buf: np.ndarray, loop_ms: float, chord: tuple[tuple[float, float], ...], start_ms: float,
         span_ms: float) -> None:
    """A soft pad: each (freq, level) sine, under a Hann window twice the chord length (neighbours cross-fade)."""
    m = int(SR * 2 * span_ms / 1000)
    n = int(SR * (start_ms - span_ms / 2) / 1000) + np.arange(m)     # absolute sample index, may wrap
    env = np.sin(np.pi * np.arange(m) / m) ** 2
    x = sum(level * np.sin(2 * np.pi * _whole_cycles(f, loop_ms) * n / SR) for f, level in chord) * env
    np.add.at(buf, n % len(buf), x)


def music_kids() -> np.ndarray:
    loop_ms = LOOP_MS["music_kids"]
    buf = _loop_buf(loop_ms)
    bar, beat = 2000, 500                                             # 120 BPM, 4/4: six bars of two seconds
    roots = (D2, B1, G2, A2, D2, A2)                                  # D, Bm, G, A, D, A
    melody = ((D5, FS5, A5, FS5, E5, D5, FS5, A5), (B5, A5, FS5, D5, FS5, A5, B5, FS5),
              (B5, A5, FS5, B5, D6, B5, A5, FS5), (A5, FS5, E5, A5, D6, A5, FS5, E5),
              (D6, B5, A5, FS5, A5, D5, FS5, A5), (E5, FS5, A5, E5, FS5, D5, E5, A5))
    tick_src = _noise(30, 20261128)
    tick = (tick_src - lowpass(tick_src, 2500)) * np.exp(-_t(30) / 0.008)     # a bright, soft hat
    for b, root in enumerate(roots):
        for at in (0, beat, 2 * beat, 3 * beat):                      # plucked bass on every beat
            _wrap_add(buf, b * bar + at, 0.9 * sweep(2 * root, root, 380, decay_s=0.12, attack_ms=2))
        for k, f in enumerate(melody[b]):                             # the bright bell melody, eighth notes
            _wrap_add(buf, b * bar + k * beat / 2, 0.55 * bell(f, 380, 0.11, 3))
        for k in range(8):                                            # a light hat on the off-beats
            _wrap_add(buf, b * bar + k * beat / 2 + beat / 4, 0.12 * tick)
    return buf


def music_calm() -> np.ndarray:
    loop_ms = LOOP_MS["music_calm"]
    buf = _loop_buf(loop_ms)
    chords = (((D3, 0.5), (A3, 0.4), (FS4, 0.35), (D3 * 2, 0.15)),          # D
              ((B2, 0.5), (FS3, 0.4), (A3, 0.35), (B2 * 2, 0.15)),          # Bm
              ((G2, 0.5), (D3, 0.4), (B3, 0.35), (G2 * 2, 0.15)),           # G
              ((A2, 0.5), (E3, 0.4), (A3, 0.35), (A2 * 2, 0.15)))           # A
    for i, chord in enumerate(chords):
        _pad(buf, loop_ms, chord, i * 4000, 4000)
    sparse = ((1000, FS5), (2500, A5), (5000, D5), (7000, E5), (9000, FS5), (11000, A5), (13000, D5), (14500, FS5))
    for at, f in sparse:                                              # a few soft bells over the pads
        _wrap_add(buf, at, 0.35 * bell(f, 1100, 0.45, 6))
    return buf


LOOPS = {"music_kids": music_kids, "music_calm": music_calm}


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


def finalize(name: str, x: np.ndarray, loop: bool = False) -> np.ndarray:
    x = x - np.mean(x)
    if not loop:                                # a loop has no edges: a fade there would dip at the seam
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
    ap = argparse.ArgumentParser(description="Synthesize the game sounds and loops (no downloaded audio).")
    ap.add_argument("--out", default=str(Path(__file__).resolve().parent.parent / "assets" / "sounds" / "games"))
    ap.add_argument("--wav", action="store_true", help="also write the WAV masters")
    ap.add_argument("--wav-only", action="store_true", help="WAV only (no soundfile needed); not for shipping")
    ap.add_argument("--ogg", action="store_true", help="also write OGG Vorbis copies (never shipped)")
    args = ap.parse_args()

    sf = None
    if not args.wav_only:
        try:
            import soundfile as sf     # libsndfile: OGG Vorbis and MP3 encoders
        except ImportError:
            print("soundfile is missing: py -3.12 -m pip install soundfile   (or --wav-only to listen)")
            return 1
        missing = [f for f in (("OGG", "MP3") if args.ogg else ("MP3",)) if f not in sf.available_formats()]
        if missing:
            print(f"this libsndfile cannot write {missing}: upgrade soundfile (>= 0.12)")
            return 1

    built = {}
    for name in EFFECTS:
        x = finalize(name, SOUNDS[name]())
        ms = len(x) * 1000 / SR
        limit = LIMIT_MS.get(name, MAX_MS)
        if ms > limit + 0.5:
            print(f"{name}: {ms:.0f} ms is over the {limit} ms limit")
            return 1
        built[name] = x
    for name, loop_ms in LOOP_MS.items():
        x = finalize(name, LOOPS[name](), loop=True)
        if len(x) != int(SR * loop_ms / 1000):
            print(f"{name}: {len(x) * 1000 / SR:.0f} ms, expected {loop_ms} ms")
            return 1
        built[name] = x

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    total = 0
    formats = ((("ogg", "OGG", "VORBIS"),) if args.ogg else ()) + (("mp3", "MP3", "MPEG_LAYER_III"),)
    print(f"{'sound':<12}{'ms':>6}{'peak dB':>9}{'rms dB':>8}" + "".join(f"{e + ' B':>8}" for e, _, _ in formats))
    for name, x in built.items():
        is_loop = name in LOOP_MS
        sizes = []
        if sf is not None:
            for ext, fmt, sub in formats:
                p = out / f"{name}.{ext}"
                sf.write(str(p), x.astype("float32"), SR, format=fmt, subtype=sub)
                size = p.stat().st_size
                sizes.append(size)
                if ext != "mp3":
                    continue
                if is_loop:
                    kbps = size * 8 / (len(x) / SR) / 1000
                    if size > MAX_LOOP_BYTES or kbps > MAX_LOOP_KBPS:
                        print(f"{name}.mp3: {size} bytes at {kbps:.0f} kbps is over the loop limit "
                              f"({MAX_LOOP_BYTES} B, {MAX_LOOP_KBPS} kbps)")
                        return 1
                elif size > MAX_FILE_BYTES:
                    print(f"{name}.mp3: {size} bytes is over the {MAX_FILE_BYTES} B limit")
                    return 1
            if not is_loop:
                total += sum(sizes)
        if args.wav or args.wav_only:
            write_wav(out / f"{name}.wav", x)
        ms = len(x) * 1000 / SR
        cols = "".join(f"{s:>8}" for s in sizes) if sizes else "".join(f"{'-':>8}" for _ in formats)
        print(f"{name:<12}{ms:>6.0f}{_db(float(np.max(np.abs(x)))):>9.1f}{_db(active_rms(x)):>8.1f}{cols}")
    if sf is not None:
        print(f"effects total {total} bytes (limit {MAX_TOTAL_BYTES}) -> {out}")
        if total > MAX_TOTAL_BYTES:
            print("the effects are over the size limit")
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
