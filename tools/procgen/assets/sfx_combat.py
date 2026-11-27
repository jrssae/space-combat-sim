"""``sfx_combat``: the combat sounds (docs/architecture.md section 15.1 D29, M2-T12), synthesised with NumPy.

Fourteen mono 16-bit 48 kHz WAVs, each at the reference loudness (-20 LUFS, 50 ms blocks, M8-T12) and peaking at most -1 dBFS, all from seeded generators (the same seed gives byte-identical files):

* ``pulse_fire`` (1.08 s): the Starfury's pulse cannon, our own match for the show's shot (M10-T87, Q82; ``sfx_gun``): shaped
  noise with a sparkle of short tones and a faint ping, approved by the maintainer's A/B.
* ``raider_fire`` (1.08 s): the same shot 3 semitones up, same length (the raiders, and every fighter not on Earth's side).
* ``turret_fire``, ``gun_light``, ``gun_medium``, ``gun_railgun``, ``gun_heavy``: the same shot pitched down and lengthened for
  the bigger guns, by ``sfx_gun.WEAPONS`` (turrets -2 semitones and x1.1, light pulse -3/x1.2, medium pulse and plasma -5/x1.4,
  railgun -7/x1.25, heavy plasma -10/x1.8). Particle cannons, beams, missiles and interceptors keep their own sounds.
* ``interceptor_fire`` (0.075 s): the interceptor batteries' pulse (M5-T21's light turret shot, D61, kept for them): a high,
  clean FM cluster (a = 2.70 kHz, b = 0.88 kHz at low modulation indices), held 60 ms and cut hard, with a small click.
* ``hit_hull`` (0.14 s): a bolt on a hull: a short metallic strike, FM at an inharmonic 1 : 1.414 ratio whose brightness
  dies faster than its level, and a click.

  These two sit two octaves down (``GUN_PITCH``, M3-T15, the maintainer's Q17): designed at the written reference's
  frequencies, every frequency in them then a quarter, their lengths and envelopes unchanged. Each is one attack.
* ``explosion`` (1.8 s): a boom (a falling sine), noise swept down through a low-pass, and a crackle of sparse impulses.
* ``main_burst`` (4.0 s, **seamless**): a main pod's roar, shaped on the reference's step roars (M5-T19, D60): noise from
  400 Hz to 16 kHz with the most energy of any octave at 4-8 kHz, a presence peak on a spectrum falling 6.5 dB per octave
  above 1 kHz (fitted over 1-16 kHz, about -5.6 dB per octave), and a slow 3 dB wander at 0.5-1.75 Hz. Nothing below 300 Hz
  (the maintainer's Q7: bright bursts only).
* ``rcs_burst`` (2.0 s, **seamless**): an attitude jet, shaped on the reference's swells: noise from 2 to 16 kHz, brightest at
  6-16 kHz, held flat. The game plays it up to an octave low while the jet spools, so its brightness follows the level.

  The game plays one burst per main pod and per cluster of RCS jets, at their place on the ship, and shapes each voice's
  attack and release from the reference's numbers (``EngineVoices``). Both loops are whole periods of their spectrum and
  wander, and the manifest gives their loop points (0 to the last sample).
* ``warning_beep`` (0.3 s): two short 880 Hz beeps (hull below 25 %).
* ``target_blip`` (0.08 s): a short 1.2 kHz blip (a target selected).

The manifest has ``kind`` ``audio`` and a ``sounds`` object (file, samples, sample rate, duration, peak level, loudness and, for the two
bursts, ``loop_begin`` / ``loop_end``).
"""

from __future__ import annotations

from collections.abc import Callable

import numpy as np

from ..core import audio, loudness
from . import sfx_gun
from ..core.context import AssetOutputs, BuildContext

ASSET_ID = "sfx_combat"
GENERATOR_VERSION = 8
MAIN_BURST_S = 4.0
RCS_BURST_S = 2.0
WANDER_CYCLES = (2, 3, 5, 7)  # the main burst's swells: whole cycles in its loop, 0.5 to 1.75 Hz
WANDER_DB = 3.0  # their peak-to-peak depth
GUN_PITCH = 0.25  # the gun and impact sounds' frequencies against their design: two octaves down
CLICK_BAND_HZ = (1000.0, 20000.0)  # the attack click's noise, before the register


def _click(rng: np.random.Generator, t: np.ndarray, pitch: float, tau_s: float) -> np.ndarray:
    """The broadband tick that opens a shot or a hit: band-passed noise at unit RMS with a fast decay."""
    noise = audio.bandpass(audio.white_noise(rng, len(t)), CLICK_BAND_HZ[0] * pitch, CLICK_BAND_HZ[1] * pitch)
    return noise / max(float(np.sqrt(np.mean(noise**2))), 1e-12) * audio.exp_decay(t, tau_s)


def _cluster(t: np.ndarray, a_hz: float, b_hz: float, index_a: float, index_b: float) -> np.ndarray:
    """The guns' metallic cluster: a carrier at 2a + b modulated by a and b, so its partials sit at 2a + b + k a + j b (the
    pattern the reference's six partials fit)."""
    return audio.fm(t, 2.0 * a_hz + b_hz, ((a_hz, index_a), (b_hz, index_b)))


def interceptor_fire(rng: np.random.Generator, pitch: float = GUN_PITCH) -> np.ndarray:
    t = audio.time_axis(0.075)
    tone = _cluster(t, 2700.0 * pitch, 880.0 * pitch, 0.5, 0.6) * audio.hold_and_cut(t, 0.0015, 0.060, 0.004)
    return audio.fade(tone + 0.4 * _click(rng, t, pitch, 0.001), 0.0003, 0.0)


def hit_hull(rng: np.random.Generator, pitch: float = GUN_PITCH) -> np.ndarray:
    t = audio.time_axis(0.14)
    detune = 1.0 + 0.03 * rng.uniform(-1.0, 1.0)  # no two hulls ring quite alike
    carrier = 3300.0 * pitch * detune
    index = 0.6 + 2.6 * audio.exp_decay(t, 0.02)  # bright at the strike, duller as it rings
    ring = audio.fm(t, carrier, ((1.414 * carrier, index), (530.0 * pitch * detune, 0.6)))
    ring *= audio.attack_decay(t, 0.001, 0.028)
    return audio.fade(ring + 0.4 * _click(rng, t, pitch, 0.002), 0.0003, 0.01)


def explosion(rng: np.random.Generator) -> np.ndarray:
    duration = 1.8
    t = audio.time_axis(duration)
    boom = audio.sine(audio.phase_from_frequency(audio.sweep(t, 90.0, 28.0, duration))) * audio.attack_decay(t, 0.01, 0.45)
    noise = audio.white_noise(rng, len(t))
    # Noise swept down: blend three low-passes by time, from bright to dull.
    bright, mid, dull = audio.lowpass(noise, 5000.0), audio.lowpass(noise, 900.0), audio.lowpass(noise, 200.0)
    w = np.clip(t / 0.9, 0.0, 1.0)
    rumble = ((1.0 - w) * bright + w * np.where(t < 0.9, mid, dull)) * audio.attack_decay(t, 0.004, 0.5)
    crackle = np.zeros_like(t)
    hits = rng.random(len(t)) < (30.0 / audio.SAMPLE_RATE) * np.exp(-t / 0.7)  # sparse impulses, thinning out
    crackle[hits] = rng.uniform(-1.0, 1.0, int(hits.sum()))
    crackle = audio.highpass(audio.lowpass(crackle, 7000.0), 600.0)
    crackle *= 0.5 / max(float(np.max(np.abs(crackle))), 1e-9)
    return audio.fade(0.9 * boom + 0.7 * rumble + 0.35 * crackle, 0.0, 0.2)


def _band_edges(f: np.ndarray, low_hz: float, high_hz: float) -> np.ndarray:
    """Steep (8th-order) high- and low-pass edges: the noise's band, with nothing to speak of outside it."""
    f = np.maximum(f, 1e-9)
    return 1.0 / np.sqrt((1.0 + (low_hz / f) ** 16) * (1.0 + (f / high_hz) ** 16))


def main_spectrum(f: np.ndarray) -> np.ndarray:
    """The roar's amplitude per hertz: rising 6 dB per octave to 1 kHz, falling 6.5 dB per octave above it, with a 10 dB
    presence peak at 5.7 kHz that makes 4-8 kHz the loudest octave."""
    octaves = np.log2(np.maximum(f, 1e-9) / 1000.0)
    tilt_db = np.where(octaves > 0.0, -6.5 * octaves, 6.0 * octaves)
    peak_db = 10.0 * np.exp(-0.5 * (np.log2(np.maximum(f, 1e-9) / 5657.0) / 0.6) ** 2)
    return 10.0 ** ((tilt_db + peak_db) / 20.0) * _band_edges(f, 400.0, 16000.0)


def rcs_spectrum(f: np.ndarray) -> np.ndarray:
    """The jet's amplitude per hertz: a 2-16 kHz band whose level climbs 9 dB from 2 to 6 kHz and stays up to the top edge
    (set at 14 kHz so the steep roll-off is spent by 16 kHz)."""
    climb = np.clip(np.log2(np.maximum(f, 1e-9) / 2000.0) / np.log2(3.0), 0.0, 1.0)
    return 10.0 ** (9.0 * (climb - 1.0) / 20.0) * _band_edges(f, 2000.0, 14000.0)


def wander_db(t: np.ndarray, phases: np.ndarray) -> np.ndarray:
    """The main burst's slow swells, in dB from 0 to ``WANDER_DB``. Every component is whole cycles of the loop, so the swell
    repeats with it."""

    def swing(x: np.ndarray) -> np.ndarray:
        return sum(np.sin(2.0 * np.pi * cycles / MAIN_BURST_S * x + phase) for cycles, phase in zip(WANDER_CYCLES, phases))

    period = swing(audio.time_axis(MAIN_BURST_S))  # one loop, for the depth
    return WANDER_DB * (swing(np.asarray(t, dtype=float)) - period.min()) / max(float(np.ptp(period)), 1e-12)


def main_burst(rng: np.random.Generator) -> np.ndarray:
    n = int(round(MAIN_BURST_S * audio.SAMPLE_RATE))
    noise = audio.shaped_periodic_noise(rng, n, main_spectrum)
    swell = wander_db(audio.time_axis(MAIN_BURST_S), rng.uniform(0.0, 2.0 * np.pi, len(WANDER_CYCLES)))
    return noise * 10.0 ** (swell / 20.0)


def rcs_burst(rng: np.random.Generator) -> np.ndarray:
    return audio.shaped_periodic_noise(rng, int(round(RCS_BURST_S * audio.SAMPLE_RATE)), rcs_spectrum)


def warning_beep(_rng: np.random.Generator) -> np.ndarray:
    t = audio.time_axis(0.3)
    beep = audio.sine(audio.phase_from_frequency(np.full_like(t, 880.0)))
    gate = ((t % 0.15) < 0.09).astype(float)  # two 90 ms beeps
    return audio.fade(beep * gate, 0.004, 0.004) * 0.9


def target_blip(_rng: np.random.Generator) -> np.ndarray:
    t = audio.time_axis(0.08)
    blip = audio.sine(audio.phase_from_frequency(np.full_like(t, 1200.0)))
    return audio.fade(blip * audio.exp_decay(t, 0.035), 0.003, 0.01)


def _gun(weapon: str) -> Callable[[np.random.Generator], np.ndarray]:
    return lambda rng: sfx_gun.weapon_shot(rng, weapon)


## Each gun sound and the row of ``sfx_gun.WEAPONS`` it plays.
GUNS: dict[str, str] = {
    "pulse_fire": "starfury",
    "raider_fire": "raider",
    "turret_fire": "turret",
    "gun_light": "bolt_light",
    "gun_medium": "bolt_medium",
    "gun_railgun": "railgun",
    "gun_heavy": "bolt_heavy",
}

SOUNDS: dict[str, Callable[[np.random.Generator], np.ndarray]] = {
    **{name: _gun(weapon) for name, weapon in GUNS.items()},
    "interceptor_fire": interceptor_fire,
    "hit_hull": hit_hull,
    "explosion": explosion,
    "main_burst": main_burst,
    "rcs_burst": rcs_burst,
    "warning_beep": warning_beep,
    "target_blip": target_blip,
}
LOOPS = {"main_burst", "rcs_burst"}


def build(ctx: BuildContext) -> AssetOutputs:
    """Generate every sound into ``ctx.out_dir`` at the reference loudness (``loudness.TARGET_LUFS``, M8-T12)."""
    return loudness.write_sound_set(ctx, ASSET_ID, GENERATOR_VERSION, SOUNDS, LOOPS)
