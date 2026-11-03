"""``sfx_ui``: the menu sounds (docs/architecture.md section 18, D57, M5-T02) and the comms squelches (D53, M5-T06),
synthesised with NumPy.

Five mono 16-bit 48 kHz WAVs, each peaking at -1.5 dBFS, from seeded generators (the same seed gives byte-identical files).
The menu sounds are plain sine tones with a soft attack and a quick decay, in the family of the HUD's ``target_blip``, so a
menu sounds like part of the cockpit:

* ``ui_move`` (0.045 s): a high, quiet tick when the focus moves. Short enough for a held D-pad to stay a patter.
* ``ui_accept`` (0.16 s): two notes rising a fifth (880 then 1320 Hz).
* ``ui_back`` (0.14 s): two notes falling (1100 then 660 Hz).

The squelches frame each comms line, so the voice band is all they use (about 600 Hz to 3.6 kHz, nothing below 400 Hz):

* ``radio_open`` (0.22 s): a burst of band-limited static that fades into a short rising key-up chirp (1.4 to 2.1 kHz).
* ``radio_close`` (0.16 s): a falling key-down chirp (2 to 1.2 kHz) with a short tail of static after it.

The manifest has ``kind`` ``audio`` and a ``sounds`` object (file, samples, sample rate, duration and peak level).
"""

from __future__ import annotations

from collections.abc import Callable
from pathlib import Path

import numpy as np

from ..core import audio
from ..core.context import AssetOutputs, BuildContext
from ..core.manifest import build_audio_manifest, sound_entry, write_manifest

ASSET_ID = "sfx_ui"
GENERATOR_VERSION = 2
PEAK_DBFS = -1.5


def _note(duration_s: float, freq_hz: float, tau_s: float) -> np.ndarray:
    """One soft note: a sine with a 4 ms attack and an exponential decay."""
    t = audio.time_axis(duration_s)
    tone = audio.sine(audio.phase_from_frequency(np.full_like(t, freq_hz)))
    return tone * audio.attack_decay(t, 0.004, tau_s)


def _two_notes(first_hz: float, second_hz: float, note_s: float, gap_s: float) -> np.ndarray:
    """Two notes one after the other, the second starting ``note_s + gap_s`` in."""
    start = int(round((note_s + gap_s) * audio.SAMPLE_RATE))
    second = _note(note_s, second_hz, 0.05)
    out = np.zeros(start + len(second))
    first = _note(note_s, first_hz, 0.04)
    out[: len(first)] += first
    out[start:] += second
    return out


def _chirp(duration_s: float, start_hz: float, end_hz: float, tau_s: float) -> np.ndarray:
    """A sine gliding linearly from ``start_hz`` to ``end_hz``, with a 4 ms attack and an exponential decay."""
    t = audio.time_axis(duration_s)
    tone = audio.sine(audio.phase_from_frequency(np.linspace(start_hz, end_hz, len(t))))
    return tone * audio.attack_decay(t, 0.004, tau_s)


def _static(rng: np.random.Generator, duration_s: float, band_hz: tuple[float, float], hold_s: float, tau_s: float) -> np.ndarray:
    """Band-limited noise (peak 1) that stays up for ``hold_s`` after a 3 ms attack, then falls away."""
    t = audio.time_axis(duration_s)
    noise = audio.bandpass(audio.white_noise(rng, len(t)), band_hz[0], band_hz[1])
    return noise / np.max(np.abs(noise)) * audio.hold_and_release(t, 0.003, hold_s, tau_s)


def _place(total_s: float, parts: list[tuple[float, np.ndarray]]) -> np.ndarray:
    """Mix ``parts`` (start time in seconds, samples) into one sound of ``total_s``."""
    out = np.zeros(int(round(total_s * audio.SAMPLE_RATE)))
    for start_s, samples in parts:
        start = int(round(start_s * audio.SAMPLE_RATE))
        end = min(start + len(samples), len(out))
        out[start:end] += samples[: end - start]
    return out


def ui_move(_rng: np.random.Generator) -> np.ndarray:
    t = audio.time_axis(0.045)
    tick = audio.sine(audio.phase_from_frequency(np.full_like(t, 1500.0)))
    return audio.fade(tick * audio.attack_decay(t, 0.002, 0.012), 0.002, 0.012) * 0.6


def ui_accept(_rng: np.random.Generator) -> np.ndarray:
    return audio.fade(_two_notes(880.0, 1320.0, 0.07, 0.02), 0.002, 0.03)


def ui_back(_rng: np.random.Generator) -> np.ndarray:
    return audio.fade(_two_notes(1100.0, 660.0, 0.06, 0.02), 0.002, 0.03)


def radio_open(rng: np.random.Generator) -> np.ndarray:
    """The channel opening: static first, the key-up chirp rising out of its tail."""
    static = _static(rng, 0.14, (700.0, 3600.0), 0.04, 0.03)
    chirp = _chirp(0.12, 1400.0, 2100.0, 0.07) * 0.5
    return audio.fade(_place(0.22, [(0.0, static), (0.10, chirp)]), 0.002, 0.02)


def radio_close(rng: np.random.Generator) -> np.ndarray:
    """The channel closing: the key-down chirp falling, a short tail of static after it."""
    chirp = _chirp(0.09, 2000.0, 1200.0, 0.05) * 0.5
    static = _static(rng, 0.12, (600.0, 3200.0), 0.03, 0.03)
    return audio.fade(_place(0.16, [(0.0, chirp), (0.05, static)]), 0.002, 0.02)


SOUNDS: dict[str, Callable[[np.random.Generator], np.ndarray]] = {
    "ui_move": ui_move,
    "ui_accept": ui_accept,
    "ui_back": ui_back,
    "radio_open": radio_open,
    "radio_close": radio_close,
}


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
        sounds[name] = sound_entry(path.name, len(samples), audio.SAMPLE_RATE, audio.peak_dbfs(written))
    manifest = build_audio_manifest(ASSET_ID, GENERATOR_VERSION, ctx.seed, sounds, extra={"peak_dbfs_target": peak})
    files.append(write_manifest(out_dir, manifest))
    return AssetOutputs(ASSET_ID, out_dir, manifest, tuple(files))
