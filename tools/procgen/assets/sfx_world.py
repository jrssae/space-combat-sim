"""``sfx_world``: sounds of the world itself rather than of a ship or the menus (docs/architecture.md section 18, D51, M5-T05),
synthesised with NumPy. Mono 16-bit 48 kHz WAVs, each at the reference loudness (-20 LUFS, 50 ms blocks, M8-T12) and peaking at most -1 dBFS, from seeded generators (the same seed gives
byte-identical files):

* ``jump_in`` (1.6 s): a jump point opening (Q12; a placeholder until M6's jumpgate vortex). Noise rises through four bands
  and a sine glides up three octaves for ``OPEN_S``, so the sound swells and brightens toward the moment the point opens;
  there it bursts (a bright two-modulator FM chord that dulls as it fades, over a short falling thump) and dies away.

The manifest has ``kind`` ``audio`` and a ``sounds`` object (file, samples, sample rate, duration, peak level, loudness).
"""

from __future__ import annotations

from collections.abc import Callable

import numpy as np

from ..core import audio, loudness
from ..core.context import AssetOutputs, BuildContext

ASSET_ID = "sfx_world"
GENERATOR_VERSION = 2
JUMP_S = 1.6
OPEN_S = 0.8  # when the point opens: the rise peaks and the burst starts
RISER_BANDS_HZ = ((200.0, 800.0), (600.0, 2400.0), (1800.0, 7000.0), (4000.0, 14000.0))


def jump_in(rng: np.random.Generator) -> np.ndarray:
    t = audio.time_axis(JUMP_S)
    after = np.maximum(t - OPEN_S, 0.0)
    opened = (t >= OPEN_S).astype(float)
    # The rise: noise handed from band to band as the point gathers, swelling to the opening, then cut short.
    noise = audio.white_noise(rng, len(t))
    bands = [audio.bandpass(noise, lo, hi) for lo, hi in RISER_BANDS_HZ]
    bands = [b / max(float(np.sqrt(np.mean(b**2))), 1e-12) for b in bands]
    where = np.clip(t / OPEN_S, 0.0, 1.0) * (len(bands) - 1)
    riser = sum(b * np.clip(1.0 - np.abs(where - i), 0.0, 1.0) for i, b in enumerate(bands))
    swell = np.where(t < OPEN_S, (t / OPEN_S) ** 2, np.exp(-after / 0.06))
    glide = audio.sine(audio.phase_from_frequency(220.0 * 8.0 ** np.clip(t / OPEN_S, 0.0, 1.0)))
    rise = (0.45 * riser + 0.5 * glide) * swell
    # The opening: a bright chord that dulls as it fades, over a short thump.
    index = 0.4 + 2.2 * np.exp(-after / 0.12)
    chord = audio.fm(t, 1320.0, ((1980.0, index), (470.0, 0.5 * index))) * np.exp(-after / 0.28) * opened
    thump = audio.sine(audio.phase_from_frequency(audio.sweep(after, 110.0, 45.0, 0.3))) * np.exp(-after / 0.12) * opened
    flash = audio.bandpass(audio.white_noise(rng, len(t)), 2000.0, 16000.0)
    flash = flash / max(float(np.sqrt(np.mean(flash**2))), 1e-12) * np.exp(-after / 0.05) * opened
    return audio.fade(rise + 1.0 * chord + 0.6 * thump + 0.35 * flash, 0.01, 0.3)


SOUNDS: dict[str, Callable[[np.random.Generator], np.ndarray]] = {
    "jump_in": jump_in,
}


def build(ctx: BuildContext) -> AssetOutputs:
    """Generate every sound into ``ctx.out_dir`` at the reference loudness (``loudness.TARGET_LUFS``, M8-T12)."""
    return loudness.write_sound_set(ctx, ASSET_ID, GENERATOR_VERSION, SOUNDS)
