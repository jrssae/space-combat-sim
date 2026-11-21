"""Class budgets (M10 Q38; ``core/budgets.py``): the approved table in docs/assets-capital.md and the generators' copy of it
agree, both texture sets' memory is the arithmetic of their maps, and a hull over either set is named."""

from __future__ import annotations

import unittest

from tools.procgen.core.budgets import CLASS_BUDGETS, LOW_SHRINK, low_set_mb, over_budget, texture_mb
from tools.procgen.tests.budget_table import read_budgets

CLASSES = ("fighter", "small_craft", "cruiser", "capital", "dreadnought")  # Q38's five


class BudgetTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.table = read_budgets()

    def test_the_document_has_the_five_classes(self) -> None:
        self.assertEqual(tuple(self.table), CLASSES)
        capitals = [self.table[name] for name in CLASSES[2:]]
        for small, big in zip(capitals[:-1], capitals[1:], strict=True):
            self.assertLess(small.triangles, big.triangles)
            self.assertLess(small.high_mb, big.high_mb)

    def test_the_generators_table_is_the_documents(self) -> None:
        self.assertEqual(tuple(CLASS_BUDGETS), tuple(self.table))
        for name, row in self.table.items():
            code = CLASS_BUDGETS[name]
            self.assertEqual((code.triangles, code.atlases, code.atlas_px, code.normal_px), (row.triangles, row.atlases, row.atlas_px, row.normal_px), name)
            self.assertEqual((code.texture_mb, code.texture_mb_low), (row.high_mb, row.low_mb), name)

    def test_each_rows_memory_is_its_maps_in_both_sets(self) -> None:
        for name, row in self.table.items():
            sizes = [row.atlas_px] * row.atlases
            self.assertAlmostEqual(row.high_mb, texture_mb(sizes, 1024, row.normal_px), delta=0.06, msg=f"{name} high")
            self.assertAlmostEqual(row.low_mb, low_set_mb(sizes, 1024, row.normal_px), delta=0.06, msg=f"{name} low")
            # A mip level down is a quarter of the atlases' memory; the shared tile is the same in both sets.
            tile = texture_mb([], 1024)
            self.assertAlmostEqual(row.low_mb - tile, (row.high_mb - tile) / 4.0, delta=0.06, msg=name)
            self.assertLess(row.low_mb, 0.4 * row.high_mb, name)

    def test_a_texture_sets_memory_is_its_compressed_maps_with_mipmaps(self) -> None:
        # 4 096 px: colour, ORM and glow at half a byte a texel, the normal map at one, a third more for the mipmaps.
        self.assertAlmostEqual(texture_mb([4096]), 16.0 * 2.5 * 4.0 / 3.0, places=6)
        self.assertAlmostEqual(texture_mb([2048]), 4.0 * 2.5 * 4.0 / 3.0, places=6)
        self.assertAlmostEqual(texture_mb([4096, 4096]), 2.0 * texture_mb([4096]), places=6)
        self.assertAlmostEqual(texture_mb([], 1024), 2.0 * 4.0 / 3.0, places=6)
        self.assertAlmostEqual(texture_mb([2048, 1024], 1024), texture_mb([2048]) + texture_mb([1024]) + texture_mb([], 1024), places=6)
        # A normal map twice the atlas adds twelve million texels at a byte each.
        self.assertAlmostEqual(texture_mb([2048], 0, 4096) - texture_mb([2048]), 16.0, places=6)

    def test_the_low_set_is_a_mip_level_down(self) -> None:
        self.assertEqual(LOW_SHRINK, 2)
        self.assertAlmostEqual(low_set_mb([4096]), texture_mb([2048]), places=6)
        self.assertAlmostEqual(low_set_mb([4096, 2048], 1024), texture_mb([2048, 1024], 1024), places=6)
        self.assertAlmostEqual(low_set_mb([2048], 0, 4096), texture_mb([1024], 0, 2048), places=6)

    def test_a_hull_over_its_class_is_named_for_either_set(self) -> None:
        row = self.table["cruiser"]
        self.assertEqual(over_budget("cruiser", row.triangles, row.high_mb, row.low_mb), [])
        self.assertRegex(over_budget("cruiser", row.triangles + 1, 1.0, 1.0)[0], "triangles")
        self.assertRegex(over_budget("cruiser", 10, row.high_mb + 1.0, 1.0)[0], "MB in the high texture set")
        # A hull whose low set is written at full size is over the low column though its high set fits.
        self.assertRegex(over_budget("cruiser", 10, row.high_mb, row.high_mb)[0], "MB in the low texture set")
        self.assertEqual(over_budget("frigate", 1, 1.0, 1.0), ["unknown class 'frigate'"])


if __name__ == "__main__":
    unittest.main()
