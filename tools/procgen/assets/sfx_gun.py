"""The Starfury's gun, our own (M10-T87, Q82): shaped noise that sounds very close to the show's shot, plus its pitched and
lengthened family for the other guns. Not yet in the game: ``pulse_fire`` stays until the maintainer's A/B (H) and the weapon
table are approved; then ``sfx_combat`` builds these sounds.

The shot is noise whose spectrum follows two level maps: ``LEVELS_DB`` per band (``BANDS_HZ``, 40 Hz to 1.9 kHz) and moment
(``TIMES_S``, over 1.08 s), and ``HIGH_LEVELS_DB``, the top 2.5-11 kHz in finer bands and moments, plus sparkle
(``GRAIN_*``) and a faint ping (``TONE_*``); synthesised by ``audio.spectral_noise`` from random phases. The maps were fitted with
``core.sound_match``, against the reference clip (references/starfurybolt.wav, never committed): a rumble under 130 Hz
held to 0.9 s, a bright band at 2.5-3 kHz over the first 0.45 s, hiss at 4-8 kHz to the end, mids that fade from 0.4 s. The
tables are level maps, not audio: no sample of the clip is in them, and the sound is built from our own noise.

A larger gun plays the same shot pitched down and lengthened (``WEAPONS``): every band moves by its semitones and every
moment stretches by its factor, so it stays the same sound, only bigger. The raiders' guns are it 3 semitones up, same length.
"""

from __future__ import annotations

from pathlib import Path

import numpy as np

from ..core import audio

DURATION_S = 1.08
BANDS_HZ = (40, 54, 72, 97, 130, 175, 236, 317, 426, 572, 769, 1033, 1389, 1867)
TIMES_S = (0.0, 0.02, 0.05, 0.09, 0.15, 0.23, 0.32, 0.42, 0.52, 0.64, 0.76, 0.86, 0.92, 0.97, 1.02, 1.08)
# dB per band (rows, BANDS_HZ) and moment (columns, TIMES_S), 0 at the loudest.
LEVELS_DB = np.array((
    (-10, -10, -15,  -4, -21, -36, -10,  -9, -23, -33, -16, -16, -45, -35, -47, -67),  # 40 Hz
    (-10, -10, -15,  -4, -21, -36, -10,  -9, -23, -33, -16, -16, -45, -35, -47, -67),  # 54 Hz
    (-10, -10, -15,  -4, -21, -36, -10,  -9, -23, -33, -16, -16, -45, -35, -47, -67),  # 72 Hz
    (-17, -17, -12, -31, -13,  -9, -42, -17, -28, -28, -21, -15, -24, -31, -27, -51),  # 97 Hz
    (-31, -31, -36, -40, -45,   0, -37,  -7, -23, -27, -47, -43, -19, -36, -21, -44),  # 130 Hz
    (-38, -38,  -6, -21, -26, -23, -14, -36, -38, -15, -31, -75, -90, -90, -90, -90),  # 175 Hz
    (-26, -26, -30, -59, -33, -27, -27, -26, -34, -48, -19, -46, -43, -55, -64, -90),  # 236 Hz
    (-47, -47, -32, -47, -17, -30, -31, -42, -50, -38, -40, -52, -65, -72, -90, -88),  # 317 Hz
    (-49, -49, -26, -44, -23, -39, -26, -35, -42, -44, -51, -58, -65, -78, -71, -88),  # 426 Hz
    (-38, -38, -35, -34, -30, -35, -33, -33, -38, -55, -49, -63, -70, -77, -69, -79),  # 572 Hz
    (-43, -43, -40, -39, -27, -40, -36, -20, -53, -38, -61, -67, -74, -74, -57, -89),  # 769 Hz
    (-42, -42, -44, -30, -34, -36, -34, -37, -46, -52, -62, -61, -56, -58, -80, -90),  # 1033 Hz
    (-44, -44, -49, -35, -37, -40, -41, -36, -53, -42, -52, -62, -61, -75, -78, -90),  # 1389 Hz
    (-34, -34, -43, -46, -42, -46, -34, -30, -46, -60, -52, -69, -58, -69, -69, -90),  # 1867 Hz
), dtype=float)  # fmt: skip
# The top (2.5-11 kHz) in finer detail, a band every eighth of an octave and a moment every 30 ms through the middle of the
# shot: the reference's brightness comes and goes there, and a coarser map loses it (the maintainer's A/B, round 2).
HIGH_BANDS_HZ = (2509, 2769, 3056, 3372, 3721, 4106, 4532, 5001, 5519, 6090, 6721, 7417, 8185, 9032, 9968, 11000)
HIGH_TIMES_S = (0, 0.02, 0.05, 0.09, 0.15, 0.18, 0.21, 0.24, 0.27, 0.3, 0.33, 0.36, 0.39, 0.42, 0.45, 0.48, 0.51, 0.54, 0.57, 0.6, 0.63, 0.66, 0.69, 0.72, 0.75, 0.78, 0.81, 0.84, 0.87, 0.9, 0.92, 0.97, 1.02, 1.08)
HIGH_LEVELS_DB = np.array((
    (-43, -43, -47, -14, -23, -17, -24, -21, -16, -22, -26, -28, -25, -33, -30, -43, -34, -41, -41, -57, -52, -31, -30, -48, -35, -52, -57, -48, -52, -50, -51, -56, -59, -76),  # 2509 Hz
    (-47, -47, -39, -23, -18, -25, -20, -25, -25, -22, -38, -35, -34, -34, -31, -41, -37, -45, -48, -42, -45, -48, -54, -26, -54, -43, -45, -46, -45, -42, -40, -55, -59, -84),  # 2769 Hz
    (-57, -57, -36, -38, -33, -27, -34, -36, -35, -33, -44, -30, -25, -33, -35, -50, -37, -32, -42, -51, -50, -38, -34, -39, -54, -45, -43, -54, -52, -54, -52, -57, -60, -80),  # 3056 Hz
    (-63, -63, -27, -32, -43, -40, -33, -37, -38, -29, -36, -36, -27, -41, -34, -50, -35, -44, -36, -42, -47, -26, -41, -31, -47, -40, -41, -37, -49, -45, -45, -56, -57, -77),  # 3372 Hz
    (-53, -53, -43, -38, -38, -43, -42, -24, -49, -31, -38, -35, -35, -27, -40, -45, -27, -34, -36, -40, -39, -47, -38, -32, -46, -36, -49, -43, -44, -26, -37, -53, -55, -81),  # 3721 Hz
    (-64, -64, -34, -41, -34, -38, -31, -37, -35, -32, -42, -28, -31, -43, -43, -45, -40, -25, -46, -40, -37, -29, -43, -35, -39, -41, -46, -42, -48, -40, -44, -48, -57, -80),  # 4106 Hz
    (-54, -54, -35, -36, -48, -49, -37, -41, -46, -42, -38, -47, -40, -41, -36, -51, -32, -34, -38, -39, -37, -51, -50, -35, -41, -39, -46, -42, -33, -40, -38, -57, -53, -74),  # 4532 Hz
    (-66, -66, -39, -42, -36, -40, -42, -40, -32, -36, -41, -41, -35, -46, -43, -44, -43, -45, -32, -48, -36, -50, -42, -46, -49, -41, -43, -41, -46, -32, -45, -44, -53, -81),  # 5001 Hz
    (-62, -62, -40, -40, -46, -34, -43, -32, -35, -35, -42, -38, -36, -35, -30, -38, -36, -32, -30, -32, -31, -44, -39, -42, -38, -31, -35, -35, -33, -32, -26, -31, -44, -69),  # 5519 Hz
    (-66, -66, -43, -42, -38, -41, -43, -37, -44, -33, -40, -33, -34, -33, -42, -47, -31, -33, -36, -41, -44, -32, -44, -37, -35, -39, -46, -36, -41, -35, -42, -46, -48, -68),  # 6090 Hz
    (-67, -67, -41, -42, -34, -41, -36, -30, -43, -32, -45, -38, -37, -34, -35, -40, -39, -38, -32, -29, -45, -30, -46, -36, -38, -36, -37, -40, -41, -36, -28, -45, -47, -69),  # 6721 Hz
    (-68, -68, -46, -49, -45, -48, -47, -45, -45, -43, -36, -39, -43, -44, -45, -46, -33, -33, -41, -47, -42, -36, -50, -46, -45, -46, -47, -46, -38, -41, -44, -59, -59, -78),  # 7417 Hz
    (-71, -71, -44, -49, -40, -43, -37, -39, -46, -42, -49, -46, -43, -41, -45, -49, -47, -42, -42, -47, -41, -52, -47, -47, -46, -43, -44, -45, -42, -42, -41, -43, -54, -79),  # 8185 Hz
    (-71, -71, -50, -50, -40, -42, -36, -41, -41, -39, -51, -50, -48, -49, -49, -51, -52, -46, -47, -58, -47, -57, -59, -49, -57, -50, -55, -51, -52, -45, -52, -54, -60, -80),  # 9032 Hz
    (-73, -73, -51, -53, -51, -54, -48, -49, -48, -47, -54, -59, -58, -61, -64, -68, -66, -66, -67, -66, -67, -70, -67, -68, -65, -68, -70, -69, -69, -69, -69, -74, -70, -81),  # 9968 Hz
    (-72, -72, -45, -59, -44, -36, -42, -42, -48, -48, -57, -57, -57, -61, -56, -68, -70, -67, -73, -68, -68, -72, -74, -72, -72, -72, -66, -73, -69, -70, -70, -67, -69, -76),  # 11000 Hz
), dtype=float)  # fmt: skip

# A faint ping near 1.25 kHz, the one tone in the shot: briefly at 0.56 s, then held through the end (0.86-0.99 s).
# dB against the noise's RMS; -90 is off.
TONE_TIMES_S = (0.0, 0.5, 0.555, 0.585, 0.63, 0.8, 0.86, 0.9, 0.95, 0.99, 1.03, 1.08)
TONE_HZ = (1290, 1290, 1295, 1280, 1280, 1240, 1250, 1230, 1220, 1240, 1210, 1210)
TONE_DB = (-90, -90, -9, -27, -90, -90, -19, -28, -31, -37, -90, -90)

# Sparkle: short sine grains scattered over the top, each at the map's level there plus GRAIN_DB. The reference is full of
# them, 15-40 ms blips at scattered pitches; plain noise lacks them and sounds duller in the middle (the A/B, round 2).
GRAIN_RATE_HZ = 600.0
GRAIN_DB = -42.0
GRAIN_HZ = (900.0, 10500.0)
GRAIN_S = (0.015, 0.04)

## The proposed family (M10-T87, for the maintainer's approval): (semitones, length factor, the guns it is for).
WEAPONS: dict[str, tuple[float, float, str]] = {
    "starfury": (0.0, 1.0, "the Starfury's pulse cannons (pulse_cannon_ef), the reference itself"),
    "raider": (3.0, 1.0, "the raiders' guns (Q82: +3 semitones, same length)"),
    "turret": (-2.0, 1.1, "defensive turrets on civilians and capitals (today's turret_fire)"),
    "bolt_light": (-3.0, 1.2, "light pulse cannons: capital bolt_light, the grid's light pulse turrets"),
    "bolt_medium": (-5.0, 1.4, "medium pulse and plasma cannons, fixed and swivel (bolt_medium, bolt_fixed)"),
    "railgun": (-7.0, 1.25, "railguns (ea_railgun): low, kept shorter for a fast slug"),
    "bolt_heavy": (-10.0, 1.8, "heavy plasma (bolt_heavy) and the grid's heavy cannon"),
}
FRAME = 1024  # synthesis frame at the reference pitch, samples
FADE_IN_S = 0.001
PEAK_DBFS = -6.0
FADE_OUT_S = 0.005


def semitones(n: float) -> float:
    return 2.0 ** (n / 12.0)


def level_map() -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Both tables as one map for ``audio.spectral_noise``: (band frequencies, moments, dB per band and moment)."""
    times = np.union1d(TIMES_S, HIGH_TIMES_S)
    low = np.array([np.interp(times, TIMES_S, row) for row in LEVELS_DB])
    high = np.array([np.interp(times, HIGH_TIMES_S, row) for row in HIGH_LEVELS_DB])
    return np.asarray(BANDS_HZ + HIGH_BANDS_HZ, dtype=float), times, np.vstack([low, high])


def _grains(rng: np.random.Generator, n: int, freqs: np.ndarray, times: np.ndarray, levels: np.ndarray, pitch: float,
            stretch: float) -> np.ndarray:
    """The sparkle layer, laid out on the table's clock and frequencies, then moved by the pitch and stretch."""
    out = np.zeros(n)
    log_f = np.log2(freqs)
    for _ in range(rng.poisson(GRAIN_RATE_HZ * DURATION_S)):
        at = rng.uniform(0.0, DURATION_S)
        hz = float(np.exp(rng.uniform(np.log(GRAIN_HZ[0]), np.log(GRAIN_HZ[1]))))
        length = int(rng.uniform(*GRAIN_S) * stretch * audio.SAMPLE_RATE)
        phase = rng.uniform(0.0, 2.0 * np.pi)
        column = np.array([np.interp(np.log2(hz), log_f, levels[:, j]) for j in range(len(times))])
        amp = 10.0 ** ((float(np.interp(at, times, column)) + GRAIN_DB) / 20.0)
        grain = amp * np.sin(2.0 * np.pi * hz * pitch * np.arange(length) / audio.SAMPLE_RATE + phase) * np.hanning(length)
        start = int(at * stretch * audio.SAMPLE_RATE) - length // 2
        lo, hi = max(start, 0), min(start + length, n)
        if hi > lo:
            out[lo:hi] += grain[lo - start : hi - start]
    return out


def gun_shot(rng: np.random.Generator, pitch: float = 1.0, stretch: float = 1.0) -> np.ndarray:
    """The shot with every frequency times ``pitch`` and every moment times ``stretch``."""
    freqs, times, levels = level_map()
    frame = 4 * int(round(FRAME / 4 / pitch))  # the frequency detail moves with the pitch, so a low rumble stays resolved
    shot = audio.spectral_noise(rng, DURATION_S * stretch, freqs * pitch, times * stretch, levels, frame=frame)
    shot = shot + _grains(rng, len(shot), freqs, times, levels, pitch, stretch) * np.sqrt(FRAME / frame)
    t = audio.time_axis(DURATION_S * stretch) / stretch  # on the table's clock
    hz = np.interp(t, TONE_TIMES_S, TONE_HZ) * pitch
    ping = audio.sine(audio.phase_from_frequency(hz)) * 10.0 ** (np.interp(t, TONE_TIMES_S, TONE_DB) / 20.0)
    shot = shot + ping * float(np.sqrt(np.mean(shot**2)))
    return audio.normalize_peak(audio.fade(shot, FADE_IN_S, FADE_OUT_S), PEAK_DBFS)  # well above the meter's gate


def weapon_shot(rng: np.random.Generator, weapon: str) -> np.ndarray:
    steps, stretch, _ = WEAPONS[weapon]
    return gun_shot(rng, semitones(steps), stretch)


def burst(rng: np.random.Generator, rate_hz: float, shots: int, fade_s: float) -> np.ndarray:
    """Rapid fire as the game plays it (``ShotTails``): each shot rings in full, and the next one fades its tail in ``fade_s``."""
    gap = int(round(audio.SAMPLE_RATE / rate_hz))
    shot_n = int(round(DURATION_S * audio.SAMPLE_RATE))
    out = np.zeros(gap * (shots - 1) + shot_n)
    fade_n = int(round(fade_s * audio.SAMPLE_RATE))
    for k in range(shots):
        shot = gun_shot(rng)
        if k < shots - 1:
            shot[gap : gap + fade_n] *= np.linspace(1.0, 0.0, fade_n)
            shot[gap + fade_n :] = 0.0
        out[k * gap : k * gap + shot_n] += shot
    return out


def render_samples(out_dir: Path, seed: int = 87, suffix: str = "", lufs: float = -20.0) -> list[Path]:
    """The listening set for the maintainer: one shot per weapon and an 8-a-second burst, all at ``lufs`` (the game's reference)."""
    from ..core import loudness

    out_dir.mkdir(parents=True, exist_ok=True)
    paths = []
    for weapon in WEAPONS:
        shot = loudness.normalize_loudness(weapon_shot(np.random.default_rng([seed, len(paths)]), weapon), lufs)
        paths.append(audio.write_wav(out_dir / f"ours_{weapon}{suffix}.wav", shot))
    rapid = burst(np.random.default_rng([seed, 99]), 8.0, 12, 0.04)
    paths.append(audio.write_wav(out_dir / f"ours_starfury_burst_8hz{suffix}.wav", loudness.normalize_loudness(rapid, lufs)))
    return paths


if __name__ == "__main__":
    import sys

    out = Path(sys.argv[1] if len(sys.argv) > 1 else "references/sounds/M10-T87")
    for path in render_samples(out, suffix=sys.argv[2] if len(sys.argv) > 2 else ""):
        print(path)
