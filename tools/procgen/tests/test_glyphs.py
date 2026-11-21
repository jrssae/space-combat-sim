"""Hull lettering (M10-T21; ``core/glyphs.py``): every letter and digit has a bitmap, a glyph stays inside its cell with room for
the mip chain, and the atlas is the layout the game reads."""

from __future__ import annotations

import unittest

import numpy as np

from tools.procgen.core import glyphs


class GlyphTests(unittest.TestCase):
    def test_every_character_has_a_bitmap_and_the_layout_holds_them_all(self) -> None:
        self.assertEqual(set(glyphs.CHARS), set(glyphs._BITMAPS))
        self.assertLessEqual(len(glyphs.CHARS), glyphs.COLUMNS**2)
        for char, rows in glyphs._BITMAPS.items():
            self.assertEqual((len(rows), {len(r) for r in rows}), (7, {5}), char)

    def test_a_glyph_is_inked_and_keeps_clear_of_its_cell_edge(self) -> None:
        for char in glyphs.CHARS:
            g = glyphs.glyph(char)
            self.assertGreater(float((g > 0.5).mean()), 0.08, f"{char} has ink")
            self.assertEqual(float(g[:8].sum() + g[-8:].sum() + g[:, :8].sum() + g[:, -8:].sum()), 0.0, f"{char} leaves a margin")

    def test_letters_differ(self) -> None:
        cells = [glyphs.glyph(c) for c in glyphs.CHARS]
        for i in range(len(cells)):
            for j in range(i + 1, len(cells)):
                self.assertGreater(float(np.abs(cells[i] - cells[j]).mean()), 0.005, f"{glyphs.CHARS[i]} and {glyphs.CHARS[j]}")

    def test_the_atlas_puts_each_character_in_its_cell(self) -> None:
        a = glyphs.atlas()
        self.assertEqual(a.shape, (glyphs.COLUMNS * glyphs.CELL_PX,) * 2 + (4,))
        k = glyphs.CHARS.index("Q")
        row, col = divmod(k, glyphs.COLUMNS)
        cell = a[row * glyphs.CELL_PX:(row + 1) * glyphs.CELL_PX, col * glyphs.CELL_PX:(col + 1) * glyphs.CELL_PX, 3]
        self.assertTrue(np.array_equal(cell, np.round(glyphs.glyph("Q") * 255).astype(np.uint8)))

    def test_the_build_is_deterministic(self) -> None:
        self.assertTrue(np.array_equal(glyphs.atlas(), glyphs.atlas()))


if __name__ == "__main__":
    unittest.main()
