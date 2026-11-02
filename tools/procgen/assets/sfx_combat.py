"""``sfx_combat``: the combat sounds (docs/architecture.md section 15.1 D29, M2-T12), synthesised with NumPy.

Eight mono 16-bit 48 kHz WAVs, each peaking at -1.5 dBFS, all from seeded generators (the same seed gives byte-identical files):

* ``pulse_fire`` (0.105 s): the Starfury's pulse cannon, shaped on the reference measured in docs/design-references.md
  ("Combat sounds", M5-T18, D60): a noise click, then a metallic inharmonic cluster held flat for 100 ms and cut hard. The
  cluster is two-frequency FM, a carrier at 2a + b modulated by a and b, with our own a = 2.10 kHz and b = 0.66 kHz near the
  reference's 2.06 and 0.67 kHz. Constant pitch, no sweep, no thump.
* ``raider_fire`` (0.15 s): the raiders' gun, built the same way but another weapon: a lower cluster (a = 1.16 kHz,
  b = 0.43 kHz) at higher modulation indices and soft-clipped, so denser and buzzier, held 120 ms and ending in a softer
  exponential cut.
* ``hit_hull`` (0.14 s): a bolt on a hull: a short metallic strike, FM at an inharmonic 1 : 1.414 ratio whose brightness
  dies faster than its level, and a click.

  These three sit two octaves down (``GUN_PITCH``, M3-T15, the maintainer's Q17): they are designed at the reference's
  frequencies and every frequency in them (carriers, modulators, noise bands) is then a quarter, their lengths and envelopes
  unchanged (not a resample, which would stretch them four times). Each is one attack: the guns follow the cannon's own rate
  of fire.
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

The manifest has ``kind`` ``audio`` and a ``sounds`` object (file, samples, sample rate, duration, peak level and, for the two
bursts, ``loop_begin`` / ``loop_end``).
"""

from __future__ import annotations

from collections.abc import Callable
from pathlib import Path

import numpy as np

from ..core import audio
from ..core.context import AssetOutputs, BuildContext
from ..core.manifest import build_audio_manifest, sound_entry, write_manifest

ASSET_ID = "sfx_combat"
GENERATOR_VERSION = 5
PEAK_DBFS = -1.5
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


def pulse_fire(rng: np.random.Generator, pitch: float = GUN_PITCH) -> np.ndarray:
    t = audio.time_axis(0.105)
    tone = _cluster(t, 2100.0 * pitch, 660.0 * pitch, 0.8, 0.9) * audio.hold_and_cut(t, 0.0015, 0.100, 0.005)
    return audio.fade(tone + 0.5 * _click(rng, t, pitch, 0.0015), 0.0003, 0.0)


def raider_fire(rng: np.random.Generator, pitch: float = GUN_PITCH) -> np.ndarray:
    t = audio.time_axis(0.15)
    drive = 1.6  # soft clipping: more intermodulation, the buzz
    tone = np.tanh(drive * _cluster(t, 1160.0 * pitch, 430.0 * pitch, 1.4, 1.6)) / np.tanh(drive)
    tone *= audio.hold_and_release(t, 0.002, 0.120, 0.006)
    return audio.fade(tone + 0.6 * _click(rng, t, pitch, 0.0025), 0.0003, 0.004)


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


SOUNDS: dict[str, Callable[[np.random.Generator], np.ndarray]] = {
    "pulse_fire": pulse_fire,
    "raider_fire": raider_fire,
    "hit_hull": hit_hull,
    "explosion": explosion,
    "main_burst": main_burst,
    "rcs_burst": rcs_burst,
    "warning_beep": warning_beep,
    "target_blip": target_blip,
}
LOOPS = {"main_burst", "rcs_burst"}


def build(ctx: BuildContext) -> AssetOutputs:
    """Generate every sound into ``ctx.out_dir``. Option ``peak_dbfs`` (default -1.5) sets the level each is normalised to."""
    peak = float(ctx.option("peak_dbfs", PEAK_DBFS))
    if peak > -1.0:
        raise ValueError("peak_dbfs must not exceed -1 dBFS")
    out_dir = Path(ctx.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    files: list[Path] = []
    sounds: dict[str, dict] = {}
    for name, synth in SOUNDS.items():
        samples = audio.normalize_peak(synth(ctx.rng("sfx", name)), peak)
        path = audio.write_wav(out_dir / f"{name}.wav", samples)
        files.append(path)
        written, _ = audio.read_wav(path)  # the level on disk, after 16-bit rounding
        sounds[name] = sound_entry(
            path.name, len(samples), audio.SAMPLE_RATE, audio.peak_dbfs(written), loop=(0, len(samples)) if name in LOOPS else None
        )
    manifest = build_audio_manifest(ASSET_ID, GENERATOR_VERSION, ctx.seed, sounds, extra={"peak_dbfs_target": peak})
    files.append(write_manifest(out_dir, manifest))
    return AssetOutputs(ASSET_ID, out_dir, manifest, tuple(files))
