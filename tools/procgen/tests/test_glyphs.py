"""Hull lettering (M10-T21, redrawn in M10-T22; ``core/glyphs.py``): every letter and digit is drawn, a glyph stays inside its cell
with room for the mip chain, its edges are smooth, and the atlas is the layout and spacing the game reads."""

from __future__ import annotations

import unittest

import numpy as np

from tools.procgen.core import glyphs


class GlyphTests(unittest.TestCase):
    def test_every_character_is_drawn_and_the_layout_holds_them_all(self) -> None:
        self.assertEqual(set(glyphs.CHARS), set(glyphs.GLYPHS))
        self.assertLessEqual(len(glyphs.CHARS), glyphs.COLUMNS**2)
        for char in glyphs.CHARS:
            self.assertTrue(0.1 < glyphs.width(char) * glyphs.GLYPH_PX < glyphs.CELL_PX - 16, f"{char} fits its cell")

    def test_the_print_is_condensed_with_the_i_narrowest(self) -> None:
        widths = {c: glyphs.width(c) for c in glyphs.CHARS}
        self.assertEqual(min(widths, key=widths.get), "I")
        self.assertLess(sorted(widths.values())[len(widths) // 2], 0.65, "taller than wide, as the show's lettering")

    def test_edges_are_smooth_not_stepped(self) -> None:
        """Antialiased: a glyph's edge passes through partly covered texels, about one texel wide, all round the letter."""
        for char in "HYPERION21AGW":
            g = glyphs.glyph(char)
            partial = (g > 0.02) & (g < 0.98)
            edge = (g > 0.5) & ~np.roll(g > 0.5, 1, axis=0) | (g > 0.5) & ~np.roll(g > 0.5, 1, axis=1)
            self.assertGreater(int(partial.sum()), 0.5 * int(edge.sum()), f"{char} has soft edges")
            self.assertLess(int(partial.sum()), 4 * int(edge.sum()), f"{char} is not blurred")
        for char in "OGSW2":
            g = glyphs.glyph(char)
            levels = np.unique(np.round(g[(g > 0.02) & (g < 0.98)], 2))
            self.assertGreater(len(levels), 20, f"{char}'s curves and slants take many levels of coverage")

    def test_a_glyph_is_inked_and_keeps_clear_of_its_cell_edge(self) -> None:
        for char in glyphs.CHARS:
            g = glyphs.glyph(char)
            self.assertGreater(float((g > 0.5).mean()), 0.05, f"{char} has ink")
            self.assertEqual(float(g[:8].sum() + g[-8:].sum() + g[:, :8].sum() + g[:, -8:].sum()), 0.0, f"{char} leaves a margin")

    def test_letters_differ(self) -> None:
        cells = [glyphs.glyph(c) for c in glyphs.CHARS]
        for i in range(len(cells)):
            for j in range(i + 1, len(cells)):
                self.assertGreater(float(np.abs(cells[i] - cells[j]).mean()), 0.005, f"{glyphs.CHARS[i]} and {glyphs.CHARS[j]}")

    def test_the_atlas_entry_carries_the_spacing(self) -> None:
        import tempfile  # noqa: PLC0415
        from pathlib import Path  # noqa: PLC0415

        with tempfile.TemporaryDirectory() as d:
            files, entry = glyphs.write_atlas(Path(d), "x")
            self.assertEqual(len(files), 2)
        self.assertEqual(entry["widths"], [round(glyphs.width(c), 4) for c in glyphs.CHARS])
        self.assertEqual((entry["tracking"], entry["space"]), (glyphs.TRACKING, glyphs.SPACE))
        self.assertAlmostEqual(entry["glyph_height_share"], glyphs.GLYPH_PX / glyphs.CELL_PX)

    def test_the_atlas_puts_each_character_in_its_cell(self) -> None:
        a = glyphs.atlas()
        self.assertEqual(a.shape, (glyphs.COLUMNS * glyphs.CELL_PX,) * 2 + (4,))
        k = glyphs.CHARS.index("Q")
        row, col = divmod(k, glyphs.COLUMNS)
        cell = a[row * glyphs.CELL_PX:(row + 1) * glyphs.CELL_PX, col * glyphs.CELL_PX:(col + 1) * glyphs.CELL_PX, 3]
        self.assertTrue(np.array_equal(cell, np.round(glyphs.glyph("Q") * 255).astype(np.uint8)))

    def test_the_outlined_print_rims_each_letter_in_black(self) -> None:
        cover, value = glyphs.outlined_glyph("O")
        plain = glyphs.glyph("O")
        self.assertTrue(np.all(cover >= plain - 1e-9), "the outline only adds to the letter's coverage")
        ring = (cover > 0.99) & (plain < 0.01)
        self.assertGreater(int(ring.sum()), 0, "a rim round the letter")
        self.assertLess(float(value[ring].max()), 0.01, "black there")
        self.assertGreater(float(value[plain > 0.99].min()), 0.99, "the letter itself stays white, for the game's tint")
        width_px = glyphs.OUTLINE * glyphs.GLYPH_PX
        row = cover[glyphs.CELL_PX // 2]
        self.assertAlmostEqual(float(row.sum() - plain[glyphs.CELL_PX // 2].sum()), 4.0 * width_px, delta=2.0,
                               msg="the rim's width each side of both strokes")
        edge = row[(row > 0.0) & (row < 1.0)]
        self.assertGreater(len(edge), 0, "anti-aliased, not stepped")

    def test_the_outlined_atlas_is_written_only_when_asked(self) -> None:
        import tempfile  # noqa: PLC0415
        from pathlib import Path  # noqa: PLC0415

        with tempfile.TemporaryDirectory() as d:
            files, entry = glyphs.write_atlas(Path(d), "x", outlined=True)
            self.assertEqual(len(files), 4)
            self.assertEqual(entry["outlined_file"], glyphs.OUTLINED_NAME.format(asset="x"))
            self.assertTrue((Path(d) / entry["outlined_file"]).is_file())
            _, plain = glyphs.write_atlas(Path(d), "y")
        self.assertNotIn("outlined_file", plain)
        a = glyphs.atlas(outlined=True)
        self.assertEqual(int(a[..., :3][a[..., 3] == 0].max()), 0, "clear texels are black, so the rim's edge keeps its colour in the mips")

    def test_the_build_is_deterministic(self) -> None:
        self.assertTrue(np.array_equal(glyphs.atlas(), glyphs.atlas()))


if __name__ == "__main__":
    unittest.main()
