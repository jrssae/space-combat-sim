"""Colour helpers: blackbody star colours and sRGB transfer functions.

All splat colours in this package are **linear** RGB radiance (they may exceed 1.0 for bright
emitters; GDGS only clamps below at zero). The sRGB encode here is for PNG output only.
"""

from __future__ import annotations

import numpy as np

# Second radiation constant hc/k in nm*K.
_C2_NM_K = 1.4387769e7

_WAVELENGTHS_NM = np.arange(380.0, 781.0, 5.0)

# XYZ -> linear sRGB (D65).
_XYZ_TO_SRGB = np.array(
    [
        [3.2404542, -1.5371385, -0.4985314],
        [-0.9692660, 1.8760108, 0.0415560],
        [0.0556434, -0.2040259, 1.0572252],
    ]
)


def _lobe(lam: np.ndarray, mu: float, sigma_lo: float, sigma_hi: float) -> np.ndarray:
    sigma = np.where(lam < mu, sigma_lo, sigma_hi)
    return np.exp(-0.5 * ((lam - mu) / sigma) ** 2)


def _cie_xyz(lam: np.ndarray) -> np.ndarray:
    """CIE 1931 colour matching functions, multi-lobe fit (Wyman, Sloan, Shirley 2013)."""
    x = (
        1.056 * _lobe(lam, 599.8, 37.9, 31.0)
        + 0.362 * _lobe(lam, 442.0, 16.0, 26.7)
        - 0.065 * _lobe(lam, 501.1, 20.4, 26.2)
    )
    y = 0.821 * _lobe(lam, 568.8, 46.9, 40.5) + 0.286 * _lobe(lam, 530.9, 16.3, 31.1)
    z = 1.217 * _lobe(lam, 437.0, 11.8, 36.0) + 0.681 * _lobe(lam, 459.0, 26.0, 13.8)
    return np.stack([x, y, z], axis=-1)


def blackbody_rgb(temperature_k: np.ndarray | float) -> np.ndarray:
    """Linear sRGB chromaticity of a blackbody, scaled so the largest channel is 1.

    Accepts a scalar or an array of temperatures in kelvin (1000-40000 is sensible) and returns
    an array of shape ``(..., 3)``. Out-of-gamut (negative) components are clipped to zero.
    """
    temps = np.asarray(temperature_k, dtype=float)
    lam = _WAVELENGTHS_NM
    cmf = _cie_xyz(lam)  # (L, 3)
    x = _C2_NM_K / (lam[None, :] * np.maximum(temps.reshape(-1, 1), 1.0))
    planck = 1.0 / (lam[None, :] ** 5 * np.expm1(x))  # (T, L)
    xyz = planck @ cmf  # (T, 3)
    rgb = np.maximum(xyz @ _XYZ_TO_SRGB.T, 0.0)
    rgb /= np.maximum(rgb.max(axis=-1, keepdims=True), 1e-30)
    return rgb.reshape(temps.shape + (3,))


def srgb_to_linear(c: np.ndarray) -> np.ndarray:
    c = np.asarray(c, dtype=float)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def linear_to_srgb(c: np.ndarray) -> np.ndarray:
    c = np.clip(np.asarray(c, dtype=float), 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1.0 / 2.4) - 0.055)


def lerp(
    a: np.ndarray | float, b: np.ndarray | float, t: np.ndarray | float
) -> np.ndarray:
    return np.asarray(a) + (np.asarray(b) - np.asarray(a)) * np.asarray(t)
