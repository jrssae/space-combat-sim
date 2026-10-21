"""Procedural sound synthesis (docs/architecture.md section 15.1 D29): WAV writing on the standard library's ``wave`` module,
envelopes, oscillators and filtered noise, all NumPy. Everything is deterministic: randomness comes from a generator the
caller passes in (``BuildContext.rng``), never from the clock.

Conventions: mono, float64 samples in [-1, 1] while building, 48 kHz, 16-bit PCM on disk. ``normalize_peak`` brings a sound to a
chosen peak level (dBFS) before it is written, so the game's mixer never clips on a single voice.
"""

from __future__ import annotations

import wave
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
