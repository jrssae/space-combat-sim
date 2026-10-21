"""``sfx_combat``: the combat sounds (docs/architecture.md section 15.1 D29, M2-T12), synthesised with NumPy.

Seven mono 16-bit 48 kHz WAVs, each peaking at -1.5 dBFS, all from seeded generators (the same seed gives byte-identical files):

* ``pulse_fire`` (0.18 s): the Starfury's pulse cannon: a falling sine sweep with a fast decay, a noise click and a low thump.
* ``raider_fire`` (0.22 s): the raiders' plasma gun: lower and buzzier (a detuned sawtooth pair, band-passed noise).
* ``hit_hull`` (0.35 s): a bolt on a hull: a clank of inharmonic partials with a fast decay and a short click.
* ``explosion`` (1.8 s): a boom (a falling sine), noise swept down through a low-pass, and a crackle of sparse impulses.
* ``engine_loop`` (2.0 s, **seamless**): a rumble of harmonics of 55 Hz and band-limited periodic noise; every component repeats
  exactly within the 2 s, and the manifest gives the loop points (0 to the last sample).
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
GENERATOR_VERSION = 1
PEAK_DBFS = -1.5
ENGINE_BASE_HZ = 55.0
ENGINE_SECONDS = 2.0
PARTIALS = (1.0, 2.76, 5.40, 8.93, 13.34)  # inharmonic partials of a struck plate


def pulse_fire(rng: np.random.Generator) -> np.ndarray:
    t = audio.time_axis(0.18)
    body = audio.sine(audio.phase_from_frequency(audio.sweep(t, 1500.0, 260.0, 0.18))) * audio.attack_decay(t, 0.002, 0.05)
    thump = audio.sine(audio.phase_from_frequency(audio.sweep(t, 140.0, 60.0, 0.18))) * audio.exp_decay(t, 0.06)
    click = audio.highpass(audio.white_noise(rng, len(t)), 2500.0) * audio.exp_decay(t, 0.004)
    return audio.fade(0.8 * body + 0.5 * thump + 0.35 * click, 0.0, 0.01)


def raider_fire(rng: np.random.Generator) -> np.ndarray:
    t = audio.time_axis(0.22)
    freq = audio.sweep(t, 520.0, 170.0, 0.22)
    buzz = 0.6 * audio.saw(audio.phase_from_frequency(freq)) + 0.5 * audio.saw(audio.phase_from_frequency(freq * 1.013))
    buzz = audio.lowpass(buzz, 2400.0) * audio.attack_decay(t, 0.003, 0.07)
    hiss = audio.bandpass(audio.white_noise(rng, len(t)), 800.0, 4000.0) * audio.attack_decay(t, 0.002, 0.04)
    thump = audio.sine(audio.phase_from_frequency(audio.sweep(t, 110.0, 45.0, 0.22))) * audio.exp_decay(t, 0.08)
    return audio.fade(0.7 * buzz + 0.35 * hiss + 0.5 * thump, 0.0, 0.015)


def hit_hull(rng: np.random.Generator) -> np.ndarray:
    t = audio.time_axis(0.35)
    ring = np.zeros_like(t)
    base = 310.0 * (1.0 + 0.08 * rng.uniform(-1.0, 1.0))
    for k, ratio in enumerate(PARTIALS):
        tau = 0.09 / (1.0 + 0.7 * k)  # the higher partials die first
        ring += audio.sine(audio.phase_from_frequency(np.full_like(t, base * ratio)) + rng.uniform(0.0, 6.28)) * audio.exp_decay(t, tau) / (1.0 + 0.4 * k)
    click = audio.highpass(audio.white_noise(rng, len(t)), 1800.0) * audio.exp_decay(t, 0.006)
    return audio.fade(0.7 * ring + 0.5 * click, 0.003, 0.02)


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
    for harmonic, gain in ((1, 1.0), (2, 0.7), (3, 0.5), (4, 0.3), (6, 0.18), (9, 0.1)):
        # Every frequency is a whole number of cycles in the loop, so the end meets the start.
        out += gain * np.sin(2.0 * np.pi * ENGINE_BASE_HZ * harmonic * t + rng.uniform(0.0, 6.28))
    out += 0.12 * np.sin(2.0 * np.pi * 0.5 * ENGINE_BASE_HZ * t)  # sub-harmonic, 27.5 Hz: 55 cycles in 2 s
    low_bin, high_bin = int(40.0 * ENGINE_SECONDS), int(1400.0 * ENGINE_SECONDS)
    out += 0.45 * audio.periodic_noise(rng, n, low_bin, high_bin)
    return out


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
    "warning_beep": warning_beep,
    "target_blip": target_blip,
}
LOOPS = {"engine_loop"}


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
