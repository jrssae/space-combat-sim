"""The capital style hook (M10-T05, D12.1; ``styles/capital.py``): the panel mosaic, the hexagonal grid (Q45) and the seamless
skin (Q46) each give a hull layout, a fitting layout and a near-field tile; the low texture set is the major breaks alone."""

from __future__ import annotations

import math
import unittest

import numpy as np

from tools.procgen.core.seams import MAJOR, Cut, Hexes, Plates
from tools.procgen.styles import REQUIRED_ROLES
from tools.procgen.styles.capital import FRAMEWORK_GREY, HEX_TILE_CELLS, CapitalStyle, HexGrid, PanelMosaic, Seamless

LO, HI = (-22.0, -11.0, 95.0), (22.0, 11.0, 140.0)


class CapitalStyleTests(unittest.TestCase):
    def test_the_framework_style_has_every_role_and_the_mosaic_by_default(self) -> None:
        for role in REQUIRED_ROLES:
            FRAMEWORK_GREY.style.material(role)
        self.assertIsInstance(FRAMEWORK_GREY.skin, PanelMosaic)
        self.assertEqual(CapitalStyle("x", FRAMEWORK_GREY.style, HexGrid()).skin.name, "hex_grid")

    def test_the_mosaic_draws_frames_plating_and_hatches(self) -> None:
        skin = PanelMosaic()
        layout = skin.hull_layout(LO, HI, 7)
        frames = [f for f in layout.features() if isinstance(f, Cut)]
        self.assertEqual([f.at for f in frames], [97.5, 105.0, 112.5, 120.0, 127.5, 135.0], "at whole multiples of the pitch inside the box")
        self.assertEqual([f.at for f in frames if f.level == MAJOR], [120.0], "every fourth frame is a major break")
        self.assertEqual({f.level for f in layout.features() if isinstance(f, Plates)}, {2, 3})
        low = layout.up_to(MAJOR)
        self.assertTrue(low and len(low.features()) < len(layout.features()), "the low set keeps the major breaks alone")

    def test_neighbouring_sections_frames_meet(self) -> None:
        skin = PanelMosaic()
        fore = {f.at for f in skin.hull_layout((-20, -11, 45), (20, 11, 95), 1).features() if isinstance(f, Cut)}
        aft = {f.at for f in skin.hull_layout((-22, -11, 90), (22, 11, 140), 2).features() if isinstance(f, Cut)}
        self.assertEqual(fore & aft, {90.0}, "the same stations where the boxes overlap")

    def test_a_fittings_plates_fit_its_size(self) -> None:
        layout = PanelMosaic().fitting_layout((0.0, 0.0, 0.0), (5.0, 3.2, 5.5), 3)
        plates = [f for f in layout.features() if isinstance(f, Plates) and f.scatter == 0.0]
        self.assertTrue(plates and all(f.cell[0] <= 2.5 and f.cell[1] <= 2.5 for f in plates))
        self.assertFalse([f for f in layout.features() if isinstance(f, Cut)], "no hull frames on a turret")

    def test_hexes_are_regular_and_their_seams_are_their_edges(self) -> None:
        grid = Hexes(cell_m=4.0)
        key, edge = grid.cells(np.array([0.0, 2.0, 4.0, 0.0, 2.0]), np.array([0.0, 0.0, 0.0, 4.0 * math.sqrt(3.0), 2.0 * math.sqrt(3.0)]))
        np.testing.assert_allclose(edge[[0, 2, 3, 4]], 2.0, atol=1e-9, err_msg="a cell's centre is half a cell from its edges")
        self.assertAlmostEqual(float(edge[1]), 0.0, places=9, msg="half way between two centres is an edge")
        self.assertEqual(len({int(k) for k in key[[0, 2, 3, 4]]}), 4, "four cells")
        rng = np.random.default_rng(5)
        u, v = rng.uniform(-50.0, 50.0, 4000), rng.uniform(-50.0, 50.0, 4000)
        key, edge = grid.cells(u, v)
        self.assertTrue(np.all((edge >= 0.0) & (edge <= 2.0 + 1e-9)))
        # A regular hexagon 4 m across its flats covers 13.86 m2: the points share out among cells of that size.
        self.assertAlmostEqual(100.0 * 100.0 / len(np.unique(key)), 0.5 * math.sqrt(3.0) * 16.0, delta=3.0)

    def test_the_hex_skin_draws_hexes_not_plates(self) -> None:
        layout = HexGrid(cell_m=6.0).hull_layout(LO, HI, 3)
        kinds = {type(f) for f in layout.features()}
        self.assertIn(Hexes, kinds)
        self.assertNotIn(Plates, kinds)
        self.assertTrue(layout.up_to(MAJOR), "its frames are the low set")
        relief = layout.evaluate(np.array([[22.0, 0.0, 100.0], [22.0, 0.0, 103.0]]), np.array([[1.0, 0.0, 0.0]] * 2), 0.2, 0.02)
        self.assertEqual(relief.height.shape, (2,))

    def test_both_tiles_wrap_and_have_seams(self) -> None:
        for skin in (PanelMosaic(), HexGrid()):
            maps = skin.detail_tile(128, 11)
            self.assertEqual((maps["albedo"].shape, maps["normal"].shape), ((128, 128, 4), (128, 128, 3)), skin.name)
            self.assertEqual(maps["albedo"].dtype, np.uint8)
            alpha = maps["albedo"][..., 3]
            self.assertGreater(int(alpha.max()), int(alpha.min()), f"{skin.name}: seams stand out of the plates")
            np.testing.assert_array_equal(skin.detail_tile(128, 11)["albedo"], maps["albedo"], err_msg="deterministic")
        nx, ny = HEX_TILE_CELLS
        skin = HexGrid()
        cell = skin.tile_m / nx
        grid = Hexes(cell_m=cell, stretch=(1.0, skin.tile_m / (ny * math.sqrt(3.0) * cell)))
        rng = np.random.default_rng(3)
        u, v = rng.uniform(0.0, skin.tile_m, 500), rng.uniform(0.0, skin.tile_m, 500)
        np.testing.assert_allclose(grid.cells(u, v)[1], grid.cells(u + skin.tile_m, v + skin.tile_m)[1], atol=1e-9,
                                   err_msg="the grid repeats with the tile")
        self.assertLess(abs(grid.stretch[1] - 1.0), 0.02, "its cells are squeezed by a hair only")

    def test_the_seamless_skin_draws_nothing(self) -> None:
        skin = Seamless()
        self.assertFalse(skin.hull_layout(LO, HI, 1))
        self.assertFalse(skin.fitting_layout(LO, HI, 1))
        self.assertIsNone(skin.detail_tile(64, 1))


if __name__ == "__main__":
    unittest.main()
