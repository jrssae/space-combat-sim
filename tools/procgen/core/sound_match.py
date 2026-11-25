"""How close one sound is to another (M10-T87, Q82): the measure behind "our own shot sounds like the reference".

Three numbers, on both sounds brought to 48 kHz and the candidate to the reference's loudness, compared from their first sample:

* ``mel``: the Pearson correlation of the two log-mel spectrograms (64 bands, 40 Hz to 11 kHz, 43 ms frames every 11 ms,
  in dB with an 80 dB floor under the reference's loudest cell), lightly smoothed over 3 frames so two noises with the same
  spectrum read as alike.
* ``envelope``: the Pearson correlation of the two K-weighted loudness envelopes (``loudness.block_powers``, 50 ms blocks every
  12.5 ms), in dB with a 60 dB floor under the reference's loudest block.
* ``length``: each sound's audible length (until its envelope last passes 50 dB under its own peak) and their ratio.

A shorter sound is padded with silence, so a missing tail costs on both correlations. NumPy only; the reference is only read.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import numpy as np

from . import loudness
from .audio import SAMPLE_RATE, read_wav

N_FFT = 2048
HOP = 512
MEL_BANDS = 64
MEL_LOW_HZ = 40.0
MEL_HIGH_HZ = 11000.0  # under the 22.05 kHz reference's Nyquist, so its missing top octave does not count
MEL_FLOOR_DB = 80.0
MEL_SMOOTH_FRAMES = 3
ENVELOPE_FLOOR_DB = 60.0
AUDIBLE_DB = 50.0


@dataclass(frozen=True)
class Match:
    mel: float
    envelope: float
    length_ref_s: float
    length_s: float

    @property
    def length_ratio(self) -> float:
        return self.length_s / self.length_ref_s if self.length_ref_s > 0.0 else float("inf")

    def passes(self, mel: float = 0.95, envelope: float = 0.95, length_tolerance: float = 0.05) -> bool:
        return self.mel >= mel and self.envelope >= envelope and abs(self.length_ratio - 1.0) <= length_tolerance


def resample(samples: np.ndarray, rate: int, target: int = SAMPLE_RATE) -> np.ndarray:
    """Band-limited resampling through the spectrum (for analysis; a one-shot, so the wrap-around is silence)."""
    x = np.asarray(samples, dtype=float)
    if rate == target:
        return x.copy()
    n_out = int(round(len(x) * target / rate))
    pad = len(x)  # room for the spectral wrap
    spectrum = np.fft.rfft(np.pad(x, (0, pad)))
    n_total = int(round((len(x) + pad) * target / rate))
    out_bins = n_total // 2 + 1
    resized = np.zeros(out_bins, dtype=complex)
    k = min(out_bins, len(spectrum))
    resized[:k] = spectrum[:k]
    return np.fft.irfft(resized, n_total)[:n_out] * (target / rate)


def _mel(hz: np.ndarray | float) -> np.ndarray:
    return 2595.0 * np.log10(1.0 + np.asarray(hz, dtype=float) / 700.0)


def _hz(mel: np.ndarray) -> np.ndarray:
    return 700.0 * (10.0 ** (mel / 2595.0) - 1.0)


def mel_filters(sample_rate: int = SAMPLE_RATE) -> np.ndarray:
    """Triangular mel filters, ``(MEL_BANDS, N_FFT // 2 + 1)``."""
    freqs = np.fft.rfftfreq(N_FFT, 1.0 / sample_rate)
    edges = _hz(np.linspace(_mel(MEL_LOW_HZ), _mel(MEL_HIGH_HZ), MEL_BANDS + 2))
    bank = np.zeros((MEL_BANDS, len(freqs)))
    for i in range(MEL_BANDS):
        lo, mid, hi = edges[i], edges[i + 1], edges[i + 2]
        rise = (freqs - lo) / (mid - lo)
        fall = (hi - freqs) / (hi - mid)
        bank[i] = np.clip(np.minimum(rise, fall), 0.0, None)
    return bank


def mel_power(samples: np.ndarray, frames: int) -> np.ndarray:
    """Mel band power per frame, ``(MEL_BANDS, frames)``, the signal padded with silence to cover them."""
    need = (frames - 1) * HOP + N_FFT
    x = np.pad(np.asarray(samples, dtype=float), (0, max(0, need - len(samples))))[:need]
    window = np.hanning(N_FFT)
    idx = np.arange(N_FFT)[None, :] + HOP * np.arange(frames)[:, None]
    power = np.abs(np.fft.rfft(x[idx] * window, axis=1)) ** 2
    return mel_filters() @ power.T


def _smooth(m: np.ndarray, width: int) -> np.ndarray:
    if width <= 1:
        return m
    kernel = np.ones(width) / width
    return np.apply_along_axis(lambda row: np.convolve(row, kernel, mode="same"), 1, m)


def _corr(a: np.ndarray, b: np.ndarray) -> float:
    a = a.ravel() - a.mean()
    b = b.ravel() - b.mean()
    denom = float(np.sqrt(np.sum(a * a) * np.sum(b * b)))
    return float(np.sum(a * b) / denom) if denom > 0.0 else 0.0


def _frames_for(n: int) -> int:
    return max(1, 1 + (n - 1) // HOP)


def mel_similarity(reference: np.ndarray, candidate: np.ndarray) -> float:
    frames = _frames_for(max(len(reference), len(candidate)))
    ref = _smooth(mel_power(reference, frames), MEL_SMOOTH_FRAMES)
    cand = _smooth(mel_power(candidate, frames), MEL_SMOOTH_FRAMES)
    floor = 10.0 * np.log10(max(float(ref.max()), 1e-20)) - MEL_FLOOR_DB
    to_db = lambda m: np.maximum(10.0 * np.log10(np.maximum(m, 1e-20)), floor)  # noqa: E731
    return _corr(to_db(ref), to_db(cand))


def envelope_db(samples: np.ndarray, blocks: int | None = None) -> np.ndarray:
    """K-weighted block power in dB, padded with silence to ``blocks`` blocks."""
    powers = loudness.block_powers(samples)
    if blocks is not None:
        powers = np.pad(powers, (0, max(0, blocks - len(powers))))[:blocks]
    return 10.0 * np.log10(np.maximum(powers, 1e-20))


def envelope_correlation(reference: np.ndarray, candidate: np.ndarray) -> float:
    n = max(len(loudness.block_powers(reference)), len(loudness.block_powers(candidate)))
    ref, cand = envelope_db(reference, n), envelope_db(candidate, n)
    floor = float(ref.max()) - ENVELOPE_FLOOR_DB
    return _corr(np.maximum(ref, floor), np.maximum(cand, floor))


def audible_length(samples: np.ndarray) -> float:
    """Seconds until the loudness envelope last passes ``AUDIBLE_DB`` under its peak (the end of that block)."""
    env = envelope_db(samples)
    loud = np.nonzero(env >= env.max() - AUDIBLE_DB)[0]
    if len(loud) == 0:
        return 0.0
    end = int(loud[-1] * round(loudness.HOP_S * SAMPLE_RATE) + round(loudness.BLOCK_S * SAMPLE_RATE))
    return min(len(samples), end) / SAMPLE_RATE


def compare(reference: np.ndarray, candidate: np.ndarray, reference_rate: int = SAMPLE_RATE,
            candidate_rate: int = SAMPLE_RATE) -> Match:
    ref = resample(reference, reference_rate)
    cand = loudness.normalize_loudness(resample(candidate, candidate_rate), loudness.loudness_lufs(ref), 60.0)
    return Match(mel_similarity(ref, cand), envelope_correlation(ref, cand), audible_length(ref), audible_length(cand))


def compare_files(reference: Path, candidate: Path) -> Match:
    ref, ref_rate = read_wav(reference)
    cand, cand_rate = read_wav(candidate)
    return compare(ref, cand, ref_rate, cand_rate)


if __name__ == "__main__":
    import sys

    if len(sys.argv) != 3:
        sys.exit("usage: python3 -m tools.procgen.core.sound_match REFERENCE.wav CANDIDATE.wav")
    m = compare_files(Path(sys.argv[1]), Path(sys.argv[2]))
    verdict = "PASS" if m.passes() else "FAIL"
    print(f"log-mel {m.mel:.4f}  envelope {m.envelope:.4f}  length {m.length_s:.3f} s vs {m.length_ref_s:.3f} s "
          f"({100.0 * (m.length_ratio - 1.0):+.1f} %)  {verdict}")
