"""``core/hull_decals`` (M10-T22, Q64): the Earth Alliance emblem drawn in code and a flood's pool of light."""

from __future__ import annotations

import unittest

import numpy as np

from tools.procgen.core import hull_decals as hd


def _grid(height_m: float, px: int = 191) -> tuple[np.ndarray, int, int]:
    w = int(round(px * hd.DESIGN_W / hd.DESIGN_H))
    yy, xx = np.mgrid[0:px, 0:w].astype(float) + 0.5
    unit = height_m / px
    uv = np.stack([(xx - 0.5 * w).ravel() * unit, (0.5 * px - yy).ravel() * unit], axis=1)
    return uv, px, w


class EmblemTests(unittest.TestCase):
    def setUp(self) -> None:
        self.uv, self.h, self.w = _grid(14.0)
        self.body, self.trim = hd.emblem(self.uv, 14.0, 14.0 / 191.0)

    def test_blue_and_yellow_never_overlap_and_fill_the_badge(self) -> None:
        total = self.body + self.trim
        self.assertLessEqual(float(total.max()), 1.0 + 1e-9)
        self.assertGreaterEqual(float(min(self.body.min(), self.trim.min())), -1e-9)
        share = float((total > 0.5).mean())
        self.assertTrue(0.6 < share < 0.8, f"the badge fills most of its box ({share:.2f})")
        self.assertTrue(1.2 < float((self.body > 0.5).sum() / (self.trim > 0.5).sum()) < 2.5, "more blue than yellow, as drawn")

    def test_the_bars_are_on_the_right_half(self) -> None:
        trim = self.trim.reshape(self.h, self.w) > 0.5
        row = trim[int(round(self.h * 93.0 / hd.DESIGN_H))]  # the upper bar's line
        right, left = row[self.w // 2 + 10 : int(self.w * 0.8)], row[int(self.w * 0.25) : self.w // 2 - 10]
        self.assertGreater(float(right.mean()), 0.9, "the bar runs across the right half")
        self.assertLess(float(left.mean()), 0.2, "and not the left")

    def test_nothing_is_painted_outside_its_box(self) -> None:
        far = np.array([[30.0, 0.0], [0.0, 10.0], [-30.0, -10.0]])
        body, trim = hd.emblem(far, 14.0, 0.05)
        self.assertEqual(float((body + trim).max()), 0.0)


class EmblemImageTests(unittest.TestCase):
    """The emblem as the game draws it (M10-T22): its own sharp image instead of the hull's texels."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.image = hd.emblem_image(600)

    def test_the_image_has_the_emblems_shape_and_colours(self) -> None:
        self.assertEqual(self.image.shape, (191, 600, 4))
        alpha = self.image[..., 3]
        self.assertEqual(int(alpha[0, 0]), 0, "clear outside")
        blue = self.image[(alpha == 255) & (self.image[..., 2] > 120) & (self.image[..., 0] < 40)]
        yellow = self.image[(alpha == 255) & (self.image[..., 0] > 240) & (self.image[..., 2] < 30)]
        self.assertGreater(len(blue), 1000, "the blue body")
        self.assertGreater(len(yellow), 1000, "the yellow border and bars")
        self.assertTrue(np.all(self.image[alpha == 0][:, :3] == hd.EMBLEM_YELLOW), "clear texels carry the border's colour")
        soft = (alpha > 0) & (alpha < 255)
        self.assertGreater(int(soft.sum()), 0, "anti-aliased edges")

    def test_its_flood_lights_it_from_below(self) -> None:
        glow = {"lamp": [0.0, -14.0, 2.8], "direction": [0.0, 0.99, -0.12], "outer_deg": 42.0, "inner_deg": 16.0, "range_m": 40.0,
                "colour": [0.9, 0.87, 0.81], "strength": 0.9}
        light = hd.glow_image(self.image, 42.0, 13.37, glow, 0.35)
        self.assertEqual(light.shape, (191, 600, 3))
        even = hd.glow_image(np.full_like(self.image, 160), 42.0, 13.37, glow, 0.35)
        self.assertGreater(int(even[170:, 290:310].sum()), int(even[:20, 290:310].sum()), "brighter low, nearer the lamp")
        yellow = (self.image[..., 3] == 255) & (self.image[..., 0] > 240)
        blue = (self.image[..., 3] == 255) & (self.image[..., 0] < 40)
        self.assertGreater(float(light[yellow][:, 0].mean()), float(light[blue][:, 0].mean()), "it takes the paint's colour")

    def test_writing_points_each_mark_at_its_files(self) -> None:
        import tempfile  # noqa: PLC0415
        from pathlib import Path  # noqa: PLC0415

        marks = [{"name": f"mark_{s}", "image": hd.EMBLEM, "width_m": 42.0, "height_m": 13.37,
                  "glow": {"lamp": [0.0, -14.0, 2.8], "direction": [0.0, 1.0, 0.0], "outer_deg": 42.0, "inner_deg": 16.0, "range_m": 40.0,
                           "colour": [1.0, 1.0, 1.0], "strength": 0.9}} for s in "rl"]
        with tempfile.TemporaryDirectory() as d:
            files = hd.write_images(Path(d), "x", marks, "[remap]\n", 0.35)
            self.assertEqual(len(files), 6, "one image for both, a light for each, and their sidecars")
            for m in marks:
                self.assertEqual(m["image"], "x_ea_emblem.png")
                self.assertTrue((Path(d) / m["glow"]["file"]).is_file())
                self.assertEqual(m["glow"]["energy"], 0.9)
        with self.assertRaises(ValueError):
            hd.write_images(Path("."), "x", [{"name": "m", "image": "nope"}], "", 0.35)


class FloodPoolTests(unittest.TestCase):
    def test_a_pool_is_bright_on_its_axis_and_dark_outside_the_cone_behind_or_past_its_reach(self) -> None:
        at, down = np.zeros(3), np.array([0.0, -1.0, 0.0])
        floor_up = np.tile([0.0, 1.0, 0.0], (4, 1))
        p = np.array([[0.0, -10.0, 0.0], [12.0, -10.0, 0.0], [0.0, 10.0, 0.0], [0.0, -60.0, 0.0]])
        glow = hd.flood_pool(p, floor_up, at, down, 30.0, 15.0, 50.0)
        self.assertGreater(float(glow[0]), 0.5, "on the axis")
        self.assertEqual(float(glow[1]), 0.0, "outside the cone (50 degrees off)")
        self.assertEqual(float(glow[2]), 0.0, "behind the lamp")
        self.assertEqual(float(glow[3]), 0.0, "past its reach")

    def test_a_face_turned_away_from_the_lamp_stays_dark(self) -> None:
        glow = hd.flood_pool(np.array([[0.0, -10.0, 0.0]]), np.array([[0.0, -1.0, 0.0]]), np.zeros(3), np.array([0.0, -1.0, 0.0]), 30.0, 15.0, 50.0)
        self.assertEqual(float(glow[0]), 0.0)


if __name__ == "__main__":
    unittest.main()
