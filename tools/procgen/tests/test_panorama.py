"""``core.panorama``: the equirectangular sky helpers (M4-T30c): directions, blob compositing, resize, PNG and sidecar."""

from __future__ import annotations

import math
import tempfile
import unittest
from pathlib import Path

import numpy as np

from tools.procgen.core import panorama
from tools.procgen.core.color import linear_to_srgb
from tools.procgen.core.image import read_png


def _pixel_of(direction: np.ndarray, width: int, height: int) -> tuple[int, int]:
    lon, lat = panorama.lonlat(np.asarray(direction, dtype=float))
    x = int((float(lon) / (2.0 * math.pi) + 0.5) * width)
    y = int((0.5 - float(lat) / math.pi) * height)
    return x, y


class DirectionTests(unittest.TestCase):
    def test_the_grid_is_unit_directions_in_godots_panorama_convention(self) -> None:
        grid = panorama.direction_grid(64, 32)
        self.assertEqual((grid.shape, grid.dtype), ((32, 64, 3), np.float32))
        np.testing.assert_allclose(np.linalg.norm(grid, axis=2), 1.0, atol=1e-6)
        # Centre of the image looks toward +Z; a quarter to the right is -X; the top row is near +Y.
        np.testing.assert_allclose(grid[16, 32], [0.0, 0.0, 1.0], atol=0.06)
        np.testing.assert_allclose(grid[16, 48], [-1.0, 0.0, 0.0], atol=0.06)
        np.testing.assert_allclose(grid[16, 0], [0.0, 0.0, -1.0], atol=0.06)
        self.assertGreater(float(grid[0, 10, 1]), 0.99)

    def test_lonlat_inverts_the_grid(self) -> None:
        grid = panorama.direction_grid(40, 20)
        lon, lat = panorama.lonlat(grid)
        expected_lon = ((np.arange(40) + 0.5) / 40 - 0.5) * 2.0 * math.pi
        expected_lat = (0.5 - (np.arange(20) + 0.5) / 20) * math.pi
        np.testing.assert_allclose(lon[5], expected_lon, atol=1e-5)
        np.testing.assert_allclose(lat[:, 7], expected_lat, atol=1e-5)


class CompositeTests(unittest.TestCase):
    def _one(self, direction: np.ndarray, sigma_rad: float, alpha: float = 0.5) -> tuple[np.ndarray, np.ndarray]:
        centre = np.asarray(direction, dtype=float)[None, :] * 1000.0
        rotation = np.eye(3)[None, :, :]
        scale = np.full((1, 3), sigma_rad * 1000.0)
        rgb = np.array([[1.0, 0.5, 0.25]])
        return panorama.composite_blobs(centre, rotation, scale, rgb, np.array([alpha]), 256, 128)

    def test_a_blob_lands_on_its_direction(self) -> None:
        direction = np.array([0.5, 0.3, -0.8])
        direction /= np.linalg.norm(direction)
        colour, coverage = self._one(direction, 0.05)
        self.assertEqual(colour.shape, (128, 256, 3))
        y, x = np.unravel_index(int(np.argmax(coverage)), coverage.shape)
        ex, ey = _pixel_of(direction, 256, 128)
        self.assertLessEqual(abs(int(x) - ex), 1)
        self.assertLessEqual(abs(int(y) - ey), 1)
        self.assertAlmostEqual(float(coverage.max()), 0.5, delta=0.02)
        # Premultiplied: the colour is the blob's colour times its coverage.
        np.testing.assert_allclose(colour[y, x], np.array([1.0, 0.5, 0.25]) * coverage[y, x], rtol=1e-5)

    def test_its_footprint_scales_with_its_angular_size(self) -> None:
        small = self._one(np.array([0.0, 0.0, 1.0]), 0.03)[1]
        large = self._one(np.array([0.0, 0.0, 1.0]), 0.06)[1]
        self.assertGreater(float(large.sum()), 3.0 * float(small.sum()))

    def test_a_blob_on_the_seam_wraps_round(self) -> None:
        coverage = self._one(np.array([0.0, 0.0, -1.0]), 0.05)[1]
        self.assertGreater(float(coverage[:, :3].sum()), 0.1)
        self.assertGreater(float(coverage[:, -3:].sum()), 0.1)

    def test_nearer_blobs_cover_farther_ones(self) -> None:
        d = np.array([0.0, 0.0, 1.0])
        centres = np.stack([d * 1000.0, d * 900.0])  # the second is nearer
        rotation = np.repeat(np.eye(3)[None], 2, axis=0)
        scale = np.stack([np.full(3, 50.0), np.full(3, 45.0)])
        rgb = np.array([[1.0, 0.0, 0.0], [0.0, 0.0, 1.0]])
        colour, _ = panorama.composite_blobs(centres, rotation, scale, rgb, np.array([0.9, 0.9]), 128, 64)
        y, x = _pixel_of(d, 128, 64)[::-1]
        self.assertGreater(float(colour[y, x, 2]), float(colour[y, x, 0]))


class ResizeAndWriteTests(unittest.TestCase):
    def test_resize_keeps_a_flat_layer_flat_and_wraps(self) -> None:
        flat = np.full((8, 16), 0.25, dtype=np.float32)
        np.testing.assert_allclose(panorama.resize_bilinear(flat, 16, 32), 0.25, atol=1e-6)
        edge = np.zeros((4, 8), dtype=np.float32)
        edge[:, 0] = 1.0
        wide = panorama.resize_bilinear(edge, 4, 16)
        self.assertGreater(float(wide[0, -1]), 0.0)  # the left column bleeds into the right edge

    def test_srgb8_is_monotonic_and_clamped(self) -> None:
        values = np.array([-1.0, 0.0, 0.001, 0.2, 0.5, 1.0, 3.0])
        encoded = panorama.to_srgb8(values)
        self.assertEqual(encoded.dtype, np.uint8)
        self.assertEqual((int(encoded[0]), int(encoded[1]), int(encoded[-1])), (0, 0, 255))
        self.assertTrue(np.all(np.diff(encoded.astype(int)) >= 0))

    def test_dither_keeps_a_dark_ramp_from_banding(self) -> None:
        # A ramp over two 8-bit levels: rounding gives two flat bands; the dither keeps each column's mean on the ramp.
        ramp = np.tile(np.linspace(0.0040, 0.00427, 64), (256, 1))
        plain = panorama.to_srgb8(ramp).astype(float)
        dithered = panorama.to_srgb8(ramp, np.random.default_rng(3)).astype(float)
        target = linear_to_srgb(ramp) * 255.0  # the exact sRGB value in levels
        self.assertLessEqual(len(np.unique(plain[0])), 2)
        plain_error = float(np.abs(plain.mean(axis=0) - target[0]).max())
        dithered_error = float(np.abs(dithered.mean(axis=0) - target[0]).max())
        self.assertGreater(plain_error, 0.25)
        self.assertLess(dithered_error, 0.12)
        black = panorama.to_srgb8(np.zeros((64, 64)), np.random.default_rng(3))
        self.assertEqual(int(black.max()), 0)  # empty sky stays black: no noise floor
        again = panorama.to_srgb8(ramp, np.random.default_rng(3))
        np.testing.assert_array_equal(again, dithered.astype(np.uint8))  # seeded: the same bytes every build

    def test_write_gives_a_png_and_a_vram_compressed_mipmapped_sidecar(self) -> None:
        image = (np.arange(16 * 32 * 3) % 251).astype(np.uint8).reshape(16, 32, 3)
        with tempfile.TemporaryDirectory() as tmp:
            paths = panorama.write_panorama(Path(tmp) / "sky.png", image)
            self.assertEqual([p.name for p in paths], ["sky.png", "sky.png.import"])
            np.testing.assert_array_equal(read_png(paths[0]), image)
            sidecar = paths[1].read_text()
        self.assertIn('importer="texture"', sidecar)
        self.assertIn("compress/mode=2", sidecar)
        self.assertIn("mipmaps/generate=true", sidecar)
        self.assertIn("compress/high_quality=true", sidecar)
        # The alpha is the nebula's opacity: the importer must not bleed colour into it.
        self.assertIn("process/fix_alpha_border=false", sidecar)


if __name__ == "__main__":
    unittest.main()
