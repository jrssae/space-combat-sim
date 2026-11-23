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
