"""Procedural sound synthesis (docs/architecture.md section 15.1 D29): WAV writing on the standard library's ``wave`` module,
envelopes, oscillators (FM among them) and filtered noise, all NumPy. Everything is deterministic: randomness comes from a
generator the caller passes in (``BuildContext.rng``), never from the clock.

Conventions: mono, float64 samples in [-1, 1] while building, 48 kHz, 16-bit PCM on disk. ``normalize_peak`` brings a sound to a
chosen peak level (dBFS) before it is written, so the game's mixer never clips on a single voice.
"""

from __future__ import annotations

import wave
from collections.abc import Callable, Sequence
from pathlib import Path

import numpy as np

SAMPLE_RATE = 48_000
INT16_MAX = 32767


def time_axis(duration_s: float, sample_rate: int = SAMPLE_RATE) -> np.ndarray:
    """Sample times in seconds for a sound of ``duration_s``."""
    return np.arange(int(round(duration_s * sample_rate))) / float(sample_rate)


# --- envelopes ----------------------------------------------------------------------------------
def exp_decay(t: np.ndarray, tau_s: float) -> np.ndarray:
    """``exp(-t / tau)``: 1 at t = 0, falling to 1/e after ``tau_s``."""
    return np.exp(-np.asarray(t, dtype=float) / tau_s)


def attack_decay(t: np.ndarray, attack_s: float, tau_s: float) -> np.ndarray:
    """A linear attack to 1 over ``attack_s``, then an exponential decay of time constant ``tau_s``."""
    t = np.asarray(t, dtype=float)
    rise = np.clip(t / max(attack_s, 1e-9), 0.0, 1.0)
    return rise * np.exp(-np.maximum(t - attack_s, 0.0) / tau_s)


def hold_and_cut(t: np.ndarray, attack_s: float, hold_s: float, cut_s: float) -> np.ndarray:
    """A held shot: a linear attack to 1, flat until ``hold_s``, then a half-cosine cut to silence over ``cut_s``."""
    t = np.asarray(t, dtype=float)
    rise = np.clip(t / max(attack_s, 1e-9), 0.0, 1.0)
    cut = np.clip((t - hold_s) / max(cut_s, 1e-9), 0.0, 1.0)
    return rise * 0.5 * (1.0 + np.cos(np.pi * cut))


def hold_and_release(t: np.ndarray, attack_s: float, hold_s: float, tau_s: float) -> np.ndarray:
    """A held shot with a softer end: like ``hold_and_cut``, but after ``hold_s`` it falls exponentially (time constant
    ``tau_s``)."""
    t = np.asarray(t, dtype=float)
    rise = np.clip(t / max(attack_s, 1e-9), 0.0, 1.0)
    return rise * np.exp(-np.maximum(t - hold_s, 0.0) / tau_s)


def fade(samples: np.ndarray, in_s: float, out_s: float, sample_rate: int = SAMPLE_RATE) -> np.ndarray:
    """Linear fade in and out (to avoid clicks at the ends of a one-shot)."""
    out = np.array(samples, dtype=float, copy=True)
    n_in, n_out = int(in_s * sample_rate), int(out_s * sample_rate)
    if n_in > 0:
        out[:n_in] *= np.linspace(0.0, 1.0, n_in, endpoint=False)
    if n_out > 0:
        out[-n_out:] *= np.linspace(1.0, 0.0, n_out)
    return out


# --- oscillators --------------------------------------------------------------------------------
def phase_from_frequency(freq_hz: np.ndarray, sample_rate: int = SAMPLE_RATE) -> np.ndarray:
    """Phase (radians) of an oscillator whose instantaneous frequency is ``freq_hz`` (an array, one value per sample)."""
    return 2.0 * np.pi * np.cumsum(np.asarray(freq_hz, dtype=float)) / sample_rate


def sweep(t: np.ndarray, start_hz: float, end_hz: float, duration_s: float) -> np.ndarray:
    """An exponential frequency sweep from ``start_hz`` at t = 0 to ``end_hz`` at ``duration_s`` (the frequency array)."""
    k = np.log(end_hz / start_hz) / duration_s
    return start_hz * np.exp(k * np.asarray(t, dtype=float))


def sine(phase: np.ndarray) -> np.ndarray:
    return np.sin(phase)


def saw(phase: np.ndarray) -> np.ndarray:
    """A naive sawtooth in [-1, 1) (buzzy on purpose)."""
    return 2.0 * (np.mod(phase / (2.0 * np.pi), 1.0)) - 1.0


def square(phase: np.ndarray) -> np.ndarray:
    return np.where(np.mod(phase / (2.0 * np.pi), 1.0) < 0.5, 1.0, -1.0)


def fm(t: np.ndarray, carrier_hz: float, modulators: Sequence[tuple[float, float | np.ndarray]]) -> np.ndarray:
    """Frequency modulation (as phase modulation): a sine at ``carrier_hz`` whose phase is pushed by each ``(freq_hz, index)``
    modulator. Its partials sit at the carrier plus whole multiples of every modulator, with Bessel-function amplitudes, so
    modulators that are not harmonics of each other give an inharmonic, metallic cluster. An index may be an array (one value
    per sample) to brighten or dull the sound over time. The amplitude stays 1."""
    t = np.asarray(t, dtype=float)
    phase = 2.0 * np.pi * carrier_hz * t
    for freq_hz, index in modulators:
        phase = phase + np.asarray(index, dtype=float) * np.sin(2.0 * np.pi * freq_hz * t)
    return np.sin(phase)


# --- noise and filters ------------------------------------------------------------------------------
def white_noise(rng: np.random.Generator, n: int) -> np.ndarray:
    return rng.uniform(-1.0, 1.0, n)


def filter_fft(samples: np.ndarray, response: np.ndarray, sample_rate: int = SAMPLE_RATE) -> np.ndarray:
    """Zero-phase filtering in the frequency domain: ``response`` is the gain at ``rfftfreq`` bins (a callable of Hz)."""
    spectrum = np.fft.rfft(samples)
    freqs = np.fft.rfftfreq(len(samples), 1.0 / sample_rate)
    return np.fft.irfft(spectrum * response(freqs), n=len(samples))


def lowpass(samples: np.ndarray, cutoff_hz: float, sample_rate: int = SAMPLE_RATE, order: int = 2) -> np.ndarray:
    return filter_fft(samples, lambda f: 1.0 / np.sqrt(1.0 + (f / cutoff_hz) ** (2 * order)), sample_rate)


def highpass(samples: np.ndarray, cutoff_hz: float, sample_rate: int = SAMPLE_RATE, order: int = 2) -> np.ndarray:
    return filter_fft(samples, lambda f: 1.0 / np.sqrt(1.0 + (cutoff_hz / np.maximum(f, 1e-9)) ** (2 * order)), sample_rate)


def bandpass(samples: np.ndarray, low_hz: float, high_hz: float, sample_rate: int = SAMPLE_RATE) -> np.ndarray:
    return highpass(lowpass(samples, high_hz, sample_rate), low_hz, sample_rate)


def periodic_noise(rng: np.random.Generator, n: int, low_bin: int, high_bin: int) -> np.ndarray:
    """Noise that repeats exactly every ``n`` samples: random phases on the integer frequency bins ``low_bin..high_bin``
    (bins are multiples of ``sample_rate / n`` Hz), so the end meets the start with no seam."""
    spectrum = np.zeros(n // 2 + 1, dtype=complex)
    bins = np.arange(low_bin, min(high_bin, n // 2) + 1)
    spectrum[bins] = np.exp(1j * rng.uniform(0.0, 2.0 * np.pi, len(bins)))
    out = np.fft.irfft(spectrum, n=n)
    return out / max(float(np.max(np.abs(out))), 1e-12)


def shaped_periodic_noise(
    rng: np.random.Generator, n: int, gain: Callable[[np.ndarray], np.ndarray], sample_rate: int = SAMPLE_RATE
) -> np.ndarray:
    """Seamless noise with a chosen spectrum: like ``periodic_noise``, but every bin above DC gets the amplitude ``gain(Hz)``
    (a callable of the bin frequencies), so a loop can carry an exact spectral shape. Peak 1."""
    freqs = np.fft.rfftfreq(n, 1.0 / sample_rate)
    spectrum = np.asarray(gain(freqs), dtype=float) * np.exp(1j * rng.uniform(0.0, 2.0 * np.pi, len(freqs)))
    spectrum[0] = 0.0
    if n % 2 == 0:
        spectrum[-1] = abs(spectrum[-1])  # the Nyquist bin is real, or irfft would drop part of its gain
    out = np.fft.irfft(spectrum, n=n)
    return out / max(float(np.max(np.abs(out))), 1e-12)


def spectral_noise(rng: np.random.Generator, duration_s: float, freqs_hz: Sequence[float], times_s: Sequence[float],
                   levels_db: np.ndarray, edge_db_per_octave: float = 24.0, frame: int = 1024,
                   sample_rate: int = SAMPLE_RATE) -> np.ndarray:
    """Noise whose spectrum changes over time by a table: ``levels_db[i, j]`` is the level at ``freqs_hz[i]`` and ``times_s[j]``,
    read between control points in log frequency and in time, falling ``edge_db_per_octave`` outside the table's frequencies.
    Random phases frame by frame, overlap-added (Hann windows a quarter frame apart), so it is noise with no grain of its own."""
    n = int(round(duration_s * sample_rate))
    hop = frame // 4
    window = np.hanning(frame + 1)[:-1]
    log_f = np.log2(np.maximum(np.fft.rfftfreq(frame, 1.0 / sample_rate), 1.0))
    log_cf = np.log2(np.asarray(freqs_hz, dtype=float))
    edge = -edge_db_per_octave * (np.maximum(log_cf[0] - log_f, 0.0) + np.maximum(log_f - log_cf[-1], 0.0))
    levels = np.asarray(levels_db, dtype=float)
    per_bin = np.array([np.interp(log_f, log_cf, levels[:, j]) for j in range(levels.shape[1])]) + edge  # times x bins
    starts = np.arange(0, n + hop, hop)  # frame k is centred on sample starts[k]
    centres = starts / sample_rate
    times = np.asarray(times_s, dtype=float)
    gains_db = np.array([np.interp(centres, times, per_bin[:, b]) for b in range(per_bin.shape[1])]).T
    spectra = 10.0 ** (gains_db / 20.0) * np.exp(2j * np.pi * rng.random(gains_db.shape))
    frames = np.fft.irfft(spectra, frame, axis=1) * window
    out = np.zeros(n + 2 * frame)
    for start, piece in zip(starts, frames):
        out[start : start + frame] += piece
    return out[frame // 2 : frame // 2 + n]


# --- levels and files -----------------------------------------------------------------------------------
def peak_dbfs(samples: np.ndarray) -> float:
    """Peak level in dB relative to full scale (1.0); -inf for silence."""
    peak = float(np.max(np.abs(samples))) if len(samples) else 0.0
    return -float("inf") if peak <= 0.0 else 20.0 * float(np.log10(peak))


def normalize_peak(samples: np.ndarray, target_dbfs: float) -> np.ndarray:
    """Scale so the peak sits at ``target_dbfs``."""
    peak = float(np.max(np.abs(samples)))
    if peak <= 0.0:
        return np.array(samples, dtype=float, copy=True)
    return np.asarray(samples, dtype=float) * (10.0 ** (target_dbfs / 20.0) / peak)


def to_int16(samples: np.ndarray) -> np.ndarray:
    return np.clip(np.round(np.asarray(samples, dtype=float) * INT16_MAX), -INT16_MAX, INT16_MAX).astype("<i2")


def write_wav(path: Path, samples: np.ndarray, sample_rate: int = SAMPLE_RATE) -> Path:
    """Write mono 16-bit PCM. The file contains only the samples (no timestamps), so equal input is byte-identical output."""
    pcm = to_int16(samples)
    with wave.open(str(path), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(sample_rate)
        f.writeframes(pcm.tobytes())
    return Path(path)


def read_wav(path: Path) -> tuple[np.ndarray, int]:
    """``(samples as float in [-1, 1], sample_rate)`` of a mono 16-bit WAV (tests and tools)."""
    with wave.open(str(path), "rb") as f:
        if f.getnchannels() != 1 or f.getsampwidth() != 2:
            raise ValueError(f"{path}: expected mono 16-bit PCM")
        raw = f.readframes(f.getnframes())
        rate = f.getframerate()
    return np.frombuffer(raw, dtype="<i2").astype(float) / INT16_MAX, rate
