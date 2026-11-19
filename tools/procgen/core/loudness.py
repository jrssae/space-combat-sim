"""The game's one loudness reference for sound effects (M8-T12, roadmap M7-5).

Every generated sound is measured the same way and brought to the same loudness before it is written, so the in-game mix
(``SoundMix`` in ``src/audio/sound_mix.gd``) is the only place one effect is set louder than another.

The measure is ITU-R BS.1770's K-weighted loudness, adapted to short one-shots: blocks of 50 ms (BS.1770 uses 400 ms, longer
than a gun shot) every 12.5 ms, an absolute gate at -70 LUFS and a relative gate 10 LU under the ungated level, so a sound's
quiet tail does not pull it down. A seamless loop is read as a loop (its blocks wrap around), so the result is its steady level.
NumPy only.
"""

from __future__ import annotations

from collections.abc import Callable, Collection, Mapping
from pathlib import Path

import numpy as np

from .audio import SAMPLE_RATE, peak_dbfs, read_wav as _read_pcm, write_wav
from .context import AssetOutputs, BuildContext
from .manifest import build_audio_manifest, sound_entry, write_manifest

## The reference: every effect's active part at this loudness (LUFS, 50 ms blocks).
TARGET_LUFS = -20.0
## Never above this peak, whatever the loudness; a sound that would need more is quieter than the target (reported).
PEAK_CEILING_DBFS = -1.0
## How far a written file may sit from the target (16-bit rounding and the peak ceiling aside).
TOLERANCE_LU = 0.5
BLOCK_S = 0.05
HOP_S = 0.0125
ABSOLUTE_GATE_LUFS = -70.0
RELATIVE_GATE_LU = 10.0

# BS.1770-4's two K-weighting biquads at 48 kHz: a high shelf (the head's effect) and a high-pass (RLB).
_SHELF_B = (1.53512485958697, -2.69169618940638, 1.19839281085285)
_SHELF_A = (1.0, -1.69065929318241, 0.73248077421585)
_RLB_B = (1.0, -2.0, 1.0)
_RLB_A = (1.0, -1.99004745483398, 0.99007225036621)


def _biquad_response(b: tuple[float, ...], a: tuple[float, ...], z_inv: np.ndarray) -> np.ndarray:
    return (b[0] + b[1] * z_inv + b[2] * z_inv**2) / (a[0] + a[1] * z_inv + a[2] * z_inv**2)


def k_weight(samples: np.ndarray, loop: bool = False, sample_rate: int = SAMPLE_RATE) -> np.ndarray:
    """The signal as the meter hears it. A one-shot is padded so the filters' ring-out is kept; a loop is filtered circularly."""
    if sample_rate != SAMPLE_RATE:
        raise ValueError("the K-weighting coefficients are for 48 kHz")
    x = np.asarray(samples, dtype=float)
    n = len(x) if loop else len(x) + sample_rate // 2
    spectrum = np.fft.rfft(x, n)
    z_inv = np.exp(-2j * np.pi * np.fft.rfftfreq(n))
    spectrum *= _biquad_response(_SHELF_B, _SHELF_A, z_inv) * _biquad_response(_RLB_B, _RLB_A, z_inv)
    return np.fft.irfft(spectrum, n)


def block_powers(samples: np.ndarray, loop: bool = False, sample_rate: int = SAMPLE_RATE) -> np.ndarray:
    """Mean square of the K-weighted signal per 50 ms block (12.5 ms apart)."""
    y = k_weight(samples, loop, sample_rate)
    block = int(round(BLOCK_S * sample_rate))
    hop = int(round(HOP_S * sample_rate))
    if loop:
        y = np.concatenate([y, y[:block]])
        starts = np.arange(0, len(samples), hop)
    else:
        if len(y) < block:
            y = np.pad(y, (0, block - len(y)))
        starts = np.arange(0, len(y) - block + 1, hop)
    csum = np.concatenate([[0.0], np.cumsum(y * y)])
    return (csum[starts + block] - csum[starts]) / block


def loudness_lufs(samples: np.ndarray, loop: bool = False, sample_rate: int = SAMPLE_RATE) -> float:
    """The sound's gated loudness, LUFS; -inf for silence."""
    powers = block_powers(samples, loop, sample_rate)
    with np.errstate(divide="ignore"):
        levels = -0.691 + 10.0 * np.log10(powers)
    gated = powers[levels > ABSOLUTE_GATE_LUFS]
    if len(gated) == 0:
        return -float("inf")
    relative = -0.691 + 10.0 * np.log10(np.mean(gated)) - RELATIVE_GATE_LU
    with np.errstate(divide="ignore"):
        gated = gated[-0.691 + 10.0 * np.log10(gated) > relative]
    return -0.691 + 10.0 * float(np.log10(np.mean(gated)))


def normalize_loudness(samples: np.ndarray, target_lufs: float = TARGET_LUFS, ceiling_dbfs: float = PEAK_CEILING_DBFS,
                       loop: bool = False) -> np.ndarray:
    """Scale to the target loudness, or less if the peak would pass the ceiling."""
    x = np.asarray(samples, dtype=float)
    level = loudness_lufs(x, loop)
    if not np.isfinite(level):
        return x.copy()
    gain_db = min(target_lufs - level, ceiling_dbfs - peak_dbfs(x))
    return x * 10.0 ** (gain_db / 20.0)


def write_sound_set(ctx: BuildContext, asset_id: str, generator_version: int,
                    synths: Mapping[str, Callable[[np.random.Generator], np.ndarray]],
                    loops: Collection[str] = ()) -> AssetOutputs:
    """Every sound of a set at the reference loudness, its WAVs and manifest. Option ``loudness_lufs`` moves the target."""
    target = float(ctx.option("loudness_lufs", TARGET_LUFS))
    out_dir = Path(ctx.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    files: list[Path] = []
    sounds: dict[str, dict] = {}
    for name, synth in synths.items():
        is_loop = name in loops
        samples = normalize_loudness(synth(ctx.rng("sfx", name)), target, PEAK_CEILING_DBFS, is_loop)
        path = write_wav(out_dir / f"{name}.wav", samples)
        files.append(path)
        written, _ = _read_pcm(path)  # the level on disk, after 16-bit rounding
        entry = sound_entry(path.name, len(samples), SAMPLE_RATE, peak_dbfs(written),
                            loop=(0, len(samples)) if is_loop else None)
        entry["loudness_lufs"] = round(loudness_lufs(written, is_loop), 3)
        sounds[name] = entry
    extra = {"loudness_target_lufs": target, "peak_ceiling_dbfs": PEAK_CEILING_DBFS}
    manifest = build_audio_manifest(asset_id, generator_version, ctx.seed, sounds, extra=extra)
    files.append(write_manifest(out_dir, manifest))
    return AssetOutputs(asset_id, out_dir, manifest, tuple(files))


def report(root: Path) -> list[tuple[str, float, float]]:
    """(set/name, loudness, peak) for every generated sound under ``root`` (``assets/generated``)."""
    import json

    rows: list[tuple[str, float, float]] = []
    for manifest_path in sorted(root.glob("sfx_*/manifest.json")):
        manifest = json.loads(manifest_path.read_text())
        for name, entry in sorted(manifest.get("sounds", {}).items()):
            samples, _ = _read_pcm(manifest_path.parent / entry["file"])
            rows.append((f"{manifest_path.parent.name}/{name}", loudness_lufs(samples, "loop_begin" in entry), peak_dbfs(samples)))
    return rows


if __name__ == "__main__":
    import sys

    for label, lufs, peak in report(Path(sys.argv[1] if len(sys.argv) > 1 else "assets/generated")):
        print(f"{label:28s} {lufs:7.2f} LUFS  peak {peak:6.2f} dBFS")
