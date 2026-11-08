"""Colour helpers: blackbody star colours and sRGB transfer functions.

All material colours in this package are **linear** RGB radiance (they may exceed 1.0 for bright
emitters). The sRGB encode here is for PNG output only.
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


# The civilian colour schemes were read off lit screen captures, so a scheme colour is what a lit face *shows*, not its paint.
# Measured in the game (2026-11-08, RX 6950 XT): a flat grey of albedo sRGB level A, lit by the key star (energy 1.5) at 45
# degrees with the default ambient (0.3) and the filmic tonemap, shows level D. Used backwards, it turns a capture colour into
# the albedo that shows it. Re-measure with reports/colour_probe if the key light, the ambient default or the tonemap change.
_SHOWN_LEVEL = np.array([0.0, 47.0, 57.0, 76.0, 102.0, 121.0, 140.0, 160.0, 184.0, 195.0, 209.0, 222.0, 238.0])
_ALBEDO_LEVEL = np.array([0.0, 16.0, 32.0, 48.0, 64.0, 80.0, 96.0, 112.0, 128.0, 144.0, 160.0, 176.0, 192.0])
# The maintainer judged the calibrated paint still too light against the show and picked half of it, with the ambient lowered
# to 0.1 (2026-11-08, M5-T39 option C).
PAINT_DARKEN = 0.5


def capture_albedo(hex_rgb: int, darken: float = PAINT_DARKEN) -> tuple[float, float, float]:
    """The linear albedo for a colour read off a screen capture: darkened by how much the game's light brightens it (so at
    ``darken`` 1 a lit face shows the capture's colour), then by ``darken``. Hue is kept; colours brighter than the table's top
    keep its strongest darkening."""
    srgb = np.array([(hex_rgb >> 16) & 255, (hex_rgb >> 8) & 255, hex_rgb & 255], dtype=float) / 255.0
    linear = srgb_to_linear(srgb)
    luminance = float(linear @ np.array([0.2126, 0.7152, 0.0722]))
    if luminance <= 0.0:
        return (0.0, 0.0, 0.0)
    shown = float(linear_to_srgb(np.array(luminance))) * 255.0
    if shown <= _SHOWN_LEVEL[-1]:
        albedo_level = float(np.interp(shown, _SHOWN_LEVEL, _ALBEDO_LEVEL))
        scale = float(srgb_to_linear(np.array(albedo_level / 255.0))) / luminance
    else:
        top = float(srgb_to_linear(np.array(_SHOWN_LEVEL[-1] / 255.0)))
        scale = float(srgb_to_linear(np.array(_ALBEDO_LEVEL[-1] / 255.0))) / top
    r, g, b = (float(v) for v in np.clip(linear * min(scale, 1.0) * darken, 0.0, 1.0))
    return (r, g, b)
