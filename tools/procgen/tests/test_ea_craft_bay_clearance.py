"""The resized EA craft through Babylon 5's main docking bay (M10-T70): each hull's real collision boxes, swept along the
mouth's axis (the same x, y silhouette all the way), must stay clear of the mouth's outline with a margin to spare."""
from __future__ import annotations

import itertools
import json
import unittest
from pathlib import Path

import numpy as np

from tools.procgen.parts import station_detail as sd

ROOT = Path(__file__).resolve().parents[3] / "assets" / "generated"
# Craft id -> least clearance (m) wanted when flown level and centred, and when off by the offsets below.
CRAFT = {"ea_shuttle": (9.0, 7.0), "ea_atmo_shuttle": (5.0, 2.0), "ea_construction_tender": (12.0, 10.0)}
OFFSETS = [(dx, dy) for dx in (-2.0, 0.0, 2.0) for dy in (-2.0, 0.0, 2.0)]
ROLLS_DEG = (-2.0, 0.0, 2.0)


def box_shadows(path: Path) -> list[np.ndarray]:
    """Each collision box seen from ahead: its eight corners projected on x, y (the swept hull's outline pieces)."""
    shadows = []
    for c in json.loads(path.read_text())["collision"]:
        basis = np.array([c["basis"]["x"], c["basis"]["y"], c["basis"]["z"]]).T
        if c["type"] == "box":
            half = np.array(c["size"]) / 2.0
            corners = [np.array(c["position"]) + basis @ (half * np.array(s)) for s in itertools.product((-1, 1), repeat=3)]
            shadows.append(np.array(corners)[:, :2])
        elif c["type"] == "capsule":
            # Round caps seen from the side: a polygon just outside each end circle keeps the check on the safe side.
            axis = basis[:, "xyz".index(c["axis"])] * (c["height"] / 2.0 - c["radius"])
            ring = c["radius"] / np.cos(np.pi / 16) * np.array([[np.cos(t), np.sin(t)] for t in np.arange(16) * np.pi / 8 + np.pi / 16])
            centre = np.array(c["position"])
            shadows.append(np.concatenate([ring + (centre + axis)[:2], ring + (centre - axis)[:2]]))
        else:
            raise AssertionError(f"{c['name']}: {c['type']} is not handled")
    return shadows


def hull2d(points: np.ndarray) -> np.ndarray:
    """Convex hull (monotone chain), counter-clockwise."""
    p = sorted(map(tuple, points))
    def half(seq):
        h: list = []
        for q in seq:
            while len(h) >= 2 and (h[-1][0] - h[-2][0]) * (q[1] - h[-2][1]) - (h[-1][1] - h[-2][1]) * (q[0] - h[-2][0]) <= 0:
                h.pop()
            h.append(q)
        return h[:-1]
    return np.array(half(p) + half(p[::-1]))


def seg_dist(points: np.ndarray, a: np.ndarray, b: np.ndarray) -> np.ndarray:
    """Each point's distance to each segment a-b (rows: points, columns: segments)."""
    ab = b - a
    t = np.clip(((points[:, None, :] - a) * ab).sum(2) / (ab * ab).sum(1), 0.0, 1.0)
    return np.linalg.norm(points[:, None, :] - (a + t[..., None] * ab), axis=2)


def crossing(poly: np.ndarray, outline: np.ndarray) -> bool:
    """Whether any edge of the polygon crosses an edge of the outline."""
    a1, b1, a2, b2 = poly, np.roll(poly, -1, 0), outline, np.roll(outline, -1, 0)
    def side(p, q, r):
        return (q[..., 0] - p[..., 0]) * (r[..., 1] - p[..., 1]) - (q[..., 1] - p[..., 1]) * (r[..., 0] - p[..., 0])
    d1 = side(a2[None], b2[None], a1[:, None]); d2 = side(a2[None], b2[None], b1[:, None])
    d3 = side(a1[:, None], b1[:, None], a2[None]); d4 = side(a1[:, None], b1[:, None], b2[None])
    return bool(((d1 * d2 < 0) & (d3 * d4 < 0)).any())


def clearance(shadows: list[np.ndarray], outline: np.ndarray, dx: float = 0.0, dy: float = 0.0, roll_deg: float = 0.0) -> tuple[float, np.ndarray]:
    """Least gap (m) between the silhouette and the outline (negative: it touches or crosses) and where on the craft it is."""
    r = np.radians(roll_deg)
    rot = np.array([[np.cos(r), -np.sin(r)], [np.sin(r), np.cos(r)]])
    a, b = outline, np.roll(outline, -1, 0)
    best, where = np.inf, np.zeros(2)
    for pts in shadows:
        poly = hull2d(pts @ rot.T + [dx, dy])
        inside = [sd.contains(outline, float(x), float(y)) for x, y in poly]
        gaps = seg_dist(poly, a, b)
        gap = min(float(gaps.min()), float(seg_dist(outline, poly, np.roll(poly, -1, 0)).min()))
        if not all(inside) or crossing(poly, outline):
            gap = -gap
        if gap < best:
            best, where = gap, poly[int(np.argmin(gaps.min(1)))]
    return best, where


class TestEaCraftThroughTheMainBay(unittest.TestCase):
    def test_each_resized_craft_clears_the_mouth_with_a_margin(self) -> None:
        outline = np.array(sd.opening())
        for craft, (centred, shifted) in CRAFT.items():
            path = ROOT / craft / "hardpoints.json"
            if not path.exists():
                self.skipTest(f"{craft} is not built")
            shadows = box_shadows(path)
            level, _ = clearance(shadows, outline)
            self.assertGreaterEqual(level, centred, f"{craft} flown level and centred")
            worst = min(clearance(shadows, outline, dx, dy, roll)[0] for (dx, dy), roll in itertools.product(OFFSETS, ROLLS_DEG))
            self.assertGreaterEqual(worst, shifted, f"{craft} off by up to 2 m and 2 degrees of roll")


if __name__ == "__main__":
    unittest.main()
