"""tools/refview section measure on open shells (M10-T62): a closed shape with faces missing fills as the closed shape does, so a
reference STL that is not watertight still gives a trustworthy per-part section IoU."""

from __future__ import annotations

import unittest

import numpy as np

from tools.refview.sections import SectionPlane, section_mask, section_score

PLANE = SectionPlane("z0", 2, 0.0, (-8.0, 8.0, -8.0, 8.0))
SIDES = 24
RADIUS = 5.0
PIXEL = 0.25


def _drum() -> tuple[np.ndarray, np.ndarray]:
    """A capped 24-sided drum along z (outward-wound triangles), and for each wall triangle the angle of its middle."""
    theta = np.arange(SIDES) * 2.0 * np.pi / SIDES
    ring = np.stack([RADIUS * np.cos(theta), RADIUS * np.sin(theta)], axis=1)
    lo, hi = np.full((SIDES, 1), -1.0), np.full((SIDES, 1), 1.0)
    a, b = np.roll(ring, 0, axis=0), np.roll(ring, -1, axis=0)
    a_lo, b_lo = np.hstack([a, lo]), np.hstack([b, lo])
    a_hi, b_hi = np.hstack([a, hi]), np.hstack([b, hi])
    walls = np.concatenate([np.stack([a_lo, b_lo, b_hi], axis=1), np.stack([a_lo, b_hi, a_hi], axis=1)])
    mid = np.concatenate([theta + np.pi / SIDES, theta + np.pi / SIDES])
    top = np.stack([np.tile([0.0, 0.0, 1.0], (SIDES, 1)), a_hi, b_hi], axis=1)
    bottom = np.stack([np.tile([0.0, 0.0, -1.0], (SIDES, 1)), b_lo, a_lo], axis=1)
    return np.concatenate([walls, top, bottom]), np.concatenate([mid, np.zeros(2 * SIDES)])


def _drum_mask() -> np.ndarray:
    """The drum's section by inside-the-polygon at each pixel centre (the answer, independent of the winding code)."""
    cols = int(16.0 / PIXEL)
    c = -8.0 + (np.arange(cols) + 0.5) * PIXEL
    x, y = np.meshgrid(c, c[::-1])
    apothem = RADIUS * np.cos(np.pi / SIDES)
    inside = np.ones_like(x, dtype=bool)
    for k in range(SIDES):
        phi = (k + 0.5) * 2.0 * np.pi / SIDES
        inside &= x * np.cos(phi) + y * np.sin(phi) <= apothem
    return inside


def _iou(a: np.ndarray, b: np.ndarray) -> float:
    return float((a & b).sum()) / float((a | b).sum())


def _without_walls(tris: np.ndarray, mid: np.ndarray, *gaps: tuple[float, float]) -> np.ndarray:
    """The drum with the wall faces whose middle lies within ``half_width`` radians of each ``(angle, half_width)`` taken away."""
    gone = np.zeros(len(tris), dtype=bool)
    for angle, half_width in gaps:
        gone |= np.abs(np.angle(np.exp(1j * (mid - angle)))) < half_width
    gone[2 * SIDES:] = False  # the caps stay
    return tris[~gone]


class OpenShellSectionTests(unittest.TestCase):
    def test_a_closed_shape_fills_as_the_polygon_does(self) -> None:
        tris, _ = _drum()
        self.assertGreater(_iou(section_mask(tris, PLANE, PIXEL), _drum_mask()), 0.995)

    def test_a_shell_with_wall_faces_missing_fills_as_the_closed_one(self) -> None:
        tris, mid = _drum()
        open_tris = _without_walls(tris, mid, (0.0, 0.25))
        self.assertLess(len(open_tris), len(tris))
        mask = section_mask(open_tris, PLANE, PIXEL)
        self.assertGreater(_iou(mask, _drum_mask()), 0.97, "no stripe of 'inside' beside the drum, no hollow where the wall is gone")
        self.assertFalse(mask[:, :4].any(), "the window's left edge, in line with the gap, stays empty")

    def test_a_shell_with_faces_missing_on_two_sides_fills_as_the_closed_one(self) -> None:
        tris, mid = _drum()
        open_tris = _without_walls(tris, mid, (np.pi / 12, 0.12), (np.pi / 2 + np.pi / 12, 0.12))
        self.assertGreater(_iou(section_mask(open_tris, PLANE, PIXEL), _drum_mask()), 0.97)

    def test_an_open_shell_scores_against_its_closed_self(self) -> None:
        tris, mid = _drum()
        open_tris = _without_walls(tris, mid, (0.0, 0.25))
        self.assertGreater(section_score(tris, open_tris, PLANE, PIXEL).iou, 0.97)


if __name__ == "__main__":
    unittest.main()
