"""Class budgets (M10 Q38; ``core/budgets.py``): the texture memory of a texture set as the game imports it, and the check a hull
is held to."""

from __future__ import annotations

import unittest

from tools.procgen.core.budgets import CLASS_BUDGETS, over_budget, texture_mb

CLASSES = ("fighter", "small_craft", "cruiser", "capital", "dreadnought")  # Q38's five


class BudgetTests(unittest.TestCase):
    def test_a_texture_sets_memory_is_its_compressed_maps_with_mipmaps(self) -> None:
        # 4 096 px: colour, ORM and glow at half a byte a texel, the normal map at one, a third more for the mipmaps.
        self.assertAlmostEqual(texture_mb([4096]), 16.0 * 2.5 * 4.0 / 3.0, places=6)
        self.assertAlmostEqual(texture_mb([2048]), 4.0 * 2.5 * 4.0 / 3.0, places=6)
        self.assertAlmostEqual(texture_mb([4096, 4096]), 2.0 * texture_mb([4096]), places=6)
        self.assertAlmostEqual(texture_mb([], 1024), 2.0 * 4.0 / 3.0, places=6)
        self.assertAlmostEqual(texture_mb([2048, 1024], 1024), texture_mb([2048]) + texture_mb([1024]) + texture_mb([], 1024), places=6)

    def test_the_five_classes_grow(self) -> None:
        self.assertEqual(tuple(CLASS_BUDGETS), CLASSES)
        capitals = [CLASS_BUDGETS[name] for name in CLASSES[2:]]
        for small, big in zip(capitals[:-1], capitals[1:], strict=True):
            self.assertLess(small.triangles, big.triangles)
            self.assertLessEqual(small.texture_mb, big.texture_mb)
        for budget in capitals:
            self.assertAlmostEqual(budget.texture_mb, texture_mb([budget.atlas_px] * budget.atlases, 1024), delta=0.06)
        # A fighter may carry a normal map twice its atlas, as the Starfury does: 12 million more texels at a byte each, with mipmaps.
        self.assertAlmostEqual(CLASS_BUDGETS["fighter"].texture_mb - CLASS_BUDGETS["small_craft"].texture_mb, 16.0, delta=0.06)

    def test_a_hull_over_its_class_is_named(self) -> None:
        cruiser = CLASS_BUDGETS["cruiser"]
        self.assertEqual(over_budget("cruiser", cruiser.triangles, cruiser.texture_mb), [])
        self.assertRegex(over_budget("cruiser", cruiser.triangles + 1, 1.0)[0], "triangles")
        self.assertRegex(over_budget("cruiser", 10, cruiser.texture_mb + 1.0)[0], "MB of textures")
        self.assertEqual(over_budget("frigate", 1, 1.0), ["unknown class 'frigate'"])


if __name__ == "__main__":
    unittest.main()
