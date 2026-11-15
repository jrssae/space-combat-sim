"""The station's detail tiles (M7-T24): seamless variants whose borders are seams, the high set's relief over the low set's mosaic,
neutral on average so they do not tint the paint, and deterministic."""

from __future__ import annotations

import unittest

import numpy as np

from tools.procgen.core import station_tiles as tiles

PX = 512  # 3 cm a texel: fine enough to see the seams


class StationTileTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.fine = tiles.fine_tiles(PX, seed=3, maze=True)
        cls.low = tiles.fine_tiles(PX, seed=3, maze=False)
        cls.panel = tiles.panel_tiles(PX // 2, seed=3)

    def test_four_variants_in_a_two_by_two_grid(self) -> None:
        for maps, px in ((self.fine, PX), (self.panel, PX // 2)):
            self.assertEqual(maps["colour"].shape, (2 * px, 2 * px, 3))
            self.assertEqual(maps["normal"].shape, (2 * px, 2 * px, 3))
            cells = [maps["colour"][r * px:(r + 1) * px, c * px:(c + 1) * px] for r in (0, 1) for c in (0, 1)]
            self.assertTrue(all(not np.array_equal(cells[0], other) for other in cells[1:]), "the variants differ")

    def test_every_variants_border_is_a_seam(self) -> None:
        # A turned or mirrored variant must meet its neighbour on a seam: each variant's outermost texels are seam-dark.
        for k in range(4):
            r, c = divmod(k, 2)
            cell = self.fine["colour"][r * PX:(r + 1) * PX, c * PX:(c + 1) * PX, 0].astype(float)
            border = np.concatenate([cell[0], cell[-1], cell[:, 0], cell[:, -1]])
            self.assertLess(float(border.mean()), float(cell.mean()) - 20.0, f"variant {k}")

    def test_the_high_set_adds_relief_to_the_mosaic(self) -> None:
        relief = lambda m: float(np.abs(m["normal"][..., :2].astype(float) - 128.0).mean())  # noqa: E731
        self.assertGreater(relief(self.fine), relief(self.low))

    def test_neutral_on_average(self) -> None:
        for maps in (self.fine, self.low, self.panel):
            colour = maps["colour"].astype(float) / 255.0
            self.assertGreater(float(colour[..., 0].mean()), 0.8, "darkens the paint only a little")
            self.assertAlmostEqual(float(colour[..., 1].mean()), 0.5, delta=0.06, msg="the roughness shift averages out")
            self.assertEqual(int(maps["normal"][..., 2].max()), 0, "the normal's blue is rebuilt by the shader")

    def test_deterministic(self) -> None:
        again = tiles.fine_tiles(PX, seed=3, maze=True)
        for key in ("colour", "normal"):
            self.assertTrue(np.array_equal(again[key], self.fine[key]))


if __name__ == "__main__":
    unittest.main()
