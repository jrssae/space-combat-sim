"""Baked "studio" lighting for unlit splats (docs/architecture.md section 7.3).

Splats carry static radiance, so the generator bakes a light rig in **asset-local** space into
the DC colour: a hemisphere ambient (sky above, darker ground below) plus a few directional
lights with wrap-around diffuse. Shading therefore rotates with the object, which is what we
want for a studio look; a real sun comes later with GDGS relighting.

No view-dependent terms (specular, Fresnel): a highlight baked for one camera is wrong for
every other, and SH degree 0 cannot represent it anyway.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from .geometry import unit


@dataclass(frozen=True)
class Light:
    """A directional light; ``direction`` points *towards* the light (Godot frame, asset-local)."""

    direction: tuple[float, float, float]
    color: tuple[float, float, float] = (1.0, 1.0, 1.0)
    intensity: float = 1.0
    wrap: float = 0.0  # 0 = Lambert, 0.5 = soft wrap-around (area-light feel)

    def shade(self, normals: np.ndarray) -> np.ndarray:
        """Diffuse factor per normal, ``(N, 3)`` (colour times intensity times wrapped cosine)."""
        l_dir = unit(np.asarray(self.direction, dtype=float))
        cos = np.asarray(normals, dtype=float) @ l_dir
        wrapped = np.clip((cos + self.wrap) / (1.0 + self.wrap), 0.0, 1.0)
        return wrapped[:, None] * (np.asarray(self.color, dtype=float) * self.intensity)[None, :]


@dataclass(frozen=True)
class StudioRig:
    """Hemisphere ambient plus directional lights; ``exposure`` scales the result."""

    sky: tuple[float, float, float]
    ground: tuple[float, float, float]
    lights: tuple[Light, ...]
    exposure: float = 1.0

    def ambient(self, normals: np.ndarray) -> np.ndarray:
        up = 0.5 + 0.5 * np.clip(np.asarray(normals, dtype=float)[:, 1], -1.0, 1.0)
        sky, ground = np.asarray(self.sky, dtype=float), np.asarray(self.ground, dtype=float)
        return ground[None, :] + (sky - ground)[None, :] * up[:, None]

    def irradiance(self, normals: np.ndarray) -> np.ndarray:
        """Total light arriving per unit albedo, ``(N, 3)``, before exposure."""
        total = self.ambient(normals)
        for light in self.lights:
            total = total + light.shade(normals)
        return total

    def shade(self, normals: np.ndarray, albedo: np.ndarray, metallic: np.ndarray | None = None) -> np.ndarray:
        """Linear RGB radiance for each sample: ``albedo * (ambient + sum of lights) * exposure``.

        ``metallic`` (0..1 per sample) damps the ambient term, so bare metal keeps its contrast.
        """
        normals = unit(np.asarray(normals, dtype=float))
        albedo = np.asarray(albedo, dtype=float).reshape(len(normals), 3)
        ambient = self.ambient(normals)
        if metallic is not None:
            ambient = ambient * (1.0 - 0.5 * np.asarray(metallic, dtype=float))[:, None]
        direct = np.zeros_like(ambient)
        for light in self.lights:
            direct += light.shade(normals)
        return np.maximum(albedo * (ambient + direct) * self.exposure, 0.0)


# Key from upper front right, soft fill from lower left rear, cool rim from above and behind:
# a hull facing up reads ~0.95 x albedo, the belly ~0.3 x albedo, nothing is pitch black, and
# the tints are mild (shadow sides stay near-neutral so the grey hull reads grey).
STUDIO_DEFAULT = StudioRig(
    sky=(0.30, 0.31, 0.34),
    ground=(0.10, 0.10, 0.11),
    lights=(
        Light(direction=(0.45, 0.75, -0.5), color=(1.0, 0.97, 0.93), intensity=0.72, wrap=0.15),
        Light(direction=(-0.7, -0.25, 0.3), color=(0.88, 0.92, 1.0), intensity=0.22, wrap=0.3),
        Light(direction=(0.1, 0.55, 0.83), color=(0.9, 0.93, 1.0), intensity=0.18, wrap=0.0),
    ),
    exposure=1.0,
)
