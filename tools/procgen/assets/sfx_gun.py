"""The Starfury's gun, our own (M10-T87, Q82): shaped noise that sounds very close to the show's shot, plus its pitched and
lengthened family for the other guns. Not yet in the game: ``pulse_fire`` stays until the maintainer's A/B (H) and the weapon
table are approved; then ``sfx_combat`` builds these sounds.

The shot is noise whose spectrum follows ``LEVELS_DB``: a level per band (``BANDS_HZ``, 40 Hz to 11 kHz) and per moment
(``TIMES_S``, over 1.08 s), synthesised by ``audio.spectral_noise`` from random phases. The table was fitted with
``core.sound_match``, against the reference clip (references/starfurybolt.wav, never committed): a rumble under 130 Hz
held to 0.9 s, a bright band at 2.5-3 kHz over the first 0.45 s, hiss at 4-8 kHz to the end, mids that fade from 0.4 s. The
table is a coarse level map, not audio: no sample of the clip is in it, and the sound is built from our own noise.

A larger gun plays the same shot pitched down and lengthened (``WEAPONS``): every band moves by its semitones and every
moment stretches by its factor, so it stays the same sound, only bigger. The raiders' guns are it 3 semitones up, same length.
"""

from __future__ import annotations

from pathlib import Path

import numpy as np

from ..core import audio

DURATION_S = 1.08
BANDS_HZ = (40, 54, 72, 97, 130, 175, 236, 317, 426, 572, 769, 1033, 1389, 1867, 2509, 3372, 4531, 6090, 8185, 11000)
TIMES_S = (0.0, 0.02, 0.05, 0.09, 0.15, 0.23, 0.32, 0.42, 0.52, 0.64, 0.76, 0.86, 0.92, 0.97, 1.02, 1.08)
# dB per band (rows, BANDS_HZ) and moment (columns, TIMES_S), 0 at the loudest.
LEVELS_DB = np.array((
    ( -9,  -9, -14,  -4, -17, -30, -10,  -8, -21, -30, -15, -15, -40, -30, -40, -58),  # 40 Hz
    ( -9,  -9, -14,  -4, -17, -30, -10,  -8, -21, -30, -15, -15, -40, -30, -40, -58),  # 54 Hz
    ( -9,  -9, -14,  -4, -17, -30, -10,  -8, -21, -30, -15, -15, -40, -30, -40, -58),  # 72 Hz
    (-13, -13, -14, -23, -16,  -7, -28, -15, -24, -28, -20, -13, -24, -29, -28, -48),  # 97 Hz
    (-26, -26, -26, -34, -35,   0, -29,  -8, -24, -25, -36, -26, -23, -36, -26, -45),  # 130 Hz
    (-40, -40,  -7, -18, -30, -15, -16, -27, -35, -19, -29, -55, -71, -82, -78, -90),  # 175 Hz
    (-32, -32, -24, -43, -22, -28, -25, -25, -34, -40, -17, -49, -46, -54, -64, -90),  # 236 Hz
    (-37, -37, -34, -48, -19, -30, -26, -39, -45, -42, -34, -49, -60, -69, -82, -90),  # 317 Hz
    (-48, -48, -25, -40, -21, -30, -24, -29, -41, -41, -51, -57, -65, -73, -70, -90),  # 426 Hz
    (-34, -34, -38, -27, -26, -34, -30, -30, -38, -42, -46, -60, -67, -77, -68, -79),  # 572 Hz
    (-38, -38, -46, -35, -27, -39, -33, -19, -56, -37, -59, -68, -73, -68, -55, -90),  # 769 Hz
    (-36, -36, -47, -24, -29, -35, -30, -34, -40, -47, -49, -57, -53, -58, -80, -81),  # 1033 Hz
    (-38, -38, -44, -31, -35, -38, -36, -34, -46, -42, -50, -56, -58, -67, -76, -90),  # 1389 Hz
    (-32, -32, -39, -40, -37, -40, -31, -27, -46, -49, -49, -64, -54, -66, -67, -84),  # 1867 Hz
    (-38, -38, -42, -12, -16, -19, -21, -26, -35, -43, -39, -47, -47, -55, -58, -79),  # 2509 Hz
    (-63, -63, -27, -32, -39, -34, -30, -33, -37, -33, -40, -41, -41, -54, -57, -74),  # 3372 Hz
    (-40, -40, -36, -35, -46, -37, -38, -39, -32, -40, -38, -35, -37, -48, -51, -71),  # 4531 Hz
    (-52, -52, -41, -40, -37, -37, -35, -32, -32, -35, -34, -36, -35, -41, -46, -63),  # 6090 Hz
    (-56, -56, -44, -47, -40, -35, -44, -41, -41, -42, -44, -40, -40, -44, -53, -75),  # 8185 Hz
    (-58, -58, -49, -57, -43, -44, -50, -61, -71, -71, -72, -73, -73, -73, -71, -75),  # 11000 Hz
), dtype=float)  # fmt: skip

## The proposed family (M10-T87, for the maintainer's approval): (semitones, length factor, the guns it is for).
WEAPONS: dict[str, tuple[float, float, str]] = {
    "starfury": (0.0, 1.0, "the Starfury's pulse cannons (pulse_cannon_ef), the reference itself"),
    "raider": (3.0, 1.0, "the raiders' guns (Q82: +3 semitones, same length)"),
    "turret": (-2.0, 1.1, "defensive turrets on civilians and capitals (today's turret_fire)"),
    "bolt_light": (-3.0, 1.2, "light pulse cannons: capital bolt_light, the grid's light pulse turrets"),
    "bolt_medium": (-5.0, 1.4, "medium pulse and plasma cannons, fixed and swivel (bolt_medium, bolt_fixed)"),
    "railgun": (-7.0, 1.25, "railguns (ea_railgun): low, kept shorter for a fast slug"),
    "particle": (-8.0, 1.6, "particle cannons and arrays (ea_particle_cannon, ea_particle_array)"),
    "bolt_heavy": (-10.0, 1.8, "heavy plasma (bolt_heavy) and the grid's heavy cannon"),
    "particle_heavy": (-12.0, 2.0, "heavy particle cannon (ea_particle_cannon_heavy)"),
}
FRAME = 1024  # synthesis frame at the reference pitch, samples
FADE_IN_S = 0.001
FADE_OUT_S = 0.005


def semitones(n: float) -> float:
    return 2.0 ** (n / 12.0)


def gun_shot(rng: np.random.Generator, pitch: float = 1.0, stretch: float = 1.0) -> np.ndarray:
    """The shot with every frequency times ``pitch`` and every moment times ``stretch``."""
    freqs = np.asarray(BANDS_HZ, dtype=float) * pitch
    times = np.asarray(TIMES_S, dtype=float) * stretch
    frame = 4 * int(round(FRAME / 4 / pitch))  # the frequency detail moves with the pitch, so a low rumble stays resolved
    shot = audio.spectral_noise(rng, DURATION_S * stretch, freqs, times, LEVELS_DB, frame=frame)
    return audio.fade(shot, FADE_IN_S, FADE_OUT_S)


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


def render_samples(out_dir: Path, seed: int = 87) -> list[Path]:
    """The listening set for the maintainer: one shot per weapon and an 8-a-second burst, at the reference loudness."""
    from ..core import loudness

    out_dir.mkdir(parents=True, exist_ok=True)
    paths = []
    for weapon in WEAPONS:
        shot = loudness.normalize_loudness(weapon_shot(np.random.default_rng([seed, len(paths)]), weapon))
        paths.append(audio.write_wav(out_dir / f"ours_{weapon}.wav", shot))
    rapid = burst(np.random.default_rng([seed, 99]), 8.0, 12, 0.04)
    paths.append(audio.write_wav(out_dir / "ours_starfury_burst_8hz.wav", loudness.normalize_loudness(rapid)))
    return paths


if __name__ == "__main__":
    import sys

    for path in render_samples(Path(sys.argv[1] if len(sys.argv) > 1 else "references/sounds/M10-T87")):
        print(path)
