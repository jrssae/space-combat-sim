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
* ``engine_loop`` (2.0 s, **seamless**): a low rumble, harmonics of 36 Hz (nothing above 180 Hz) and band-limited periodic noise
  below 260 Hz; every component repeats exactly within the 2 s, and the manifest gives the loop points (0 to the last sample).
  The game plays it at a pitch of 0.8 to 1.25 and ramps its level up and down with the thrust.
* ``thruster_loop`` (2.0 s, **seamless**): the attitude thrusters' hiss-rumble, periodic noise between 90 and 900 Hz, softer and
  brighter than the engine; the game ramps it with the RCS demand.
* ``warning_beep`` (0.3 s): two short 880 Hz beeps (hull below 25 %).
* ``target_blip`` (0.08 s): a short 1.2 kHz blip (a target selected).

The manifest has ``kind`` ``audio`` and a ``sounds`` object (file, samples, sample rate, duration, peak level and, for the engine
loop, ``loop_begin`` / ``loop_end``).
"""

from __future__ import annotations

from collections.abc import Callable
from pathlib import Path

import numpy as np

from ..core import audio
from ..core.context import AssetOutputs, BuildContext
from ..core.manifest import build_audio_manifest, sound_entry, write_manifest

ASSET_ID = "sfx_combat"
GENERATOR_VERSION = 4
PEAK_DBFS = -1.5
ENGINE_BASE_HZ = 36.0
ENGINE_SECONDS = 2.0
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


def engine_loop(rng: np.random.Generator) -> np.ndarray:
    n = int(round(ENGINE_SECONDS * audio.SAMPLE_RATE))
    t = audio.time_axis(ENGINE_SECONDS)
    out = np.zeros(n)
    for harmonic, gain in ((1, 1.0), (2, 0.8), (3, 0.5), (4, 0.3), (5, 0.15)):
        # Every frequency is a whole number of cycles in the loop, so the end meets the start.
        out += gain * np.sin(2.0 * np.pi * ENGINE_BASE_HZ * harmonic * t + rng.uniform(0.0, 6.28))
    out += 0.3 * np.sin(2.0 * np.pi * 0.5 * ENGINE_BASE_HZ * t)  # sub-harmonic, 18 Hz: 36 cycles in 2 s
    low_bin, high_bin = int(25.0 * ENGINE_SECONDS), int(260.0 * ENGINE_SECONDS)
    out += 0.5 * audio.periodic_noise(rng, n, low_bin, high_bin)
    return out


def thruster_loop(rng: np.random.Generator) -> np.ndarray:
    n = int(round(ENGINE_SECONDS * audio.SAMPLE_RATE))
    low_bin, high_bin = int(90.0 * ENGINE_SECONDS), int(900.0 * ENGINE_SECONDS)
    return audio.periodic_noise(rng, n, low_bin, high_bin)


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
    "engine_loop": engine_loop,
    "thruster_loop": thruster_loop,
    "warning_beep": warning_beep,
    "target_blip": target_blip,
}
LOOPS = {"engine_loop", "thruster_loop"}


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
