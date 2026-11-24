"""The capital hulls' shared paint helpers (M10-T67): the edge band round a plate's big faces, a paint that keeps its authored
frame when the hull is moved, the patches' shade tiers, and the check for same-facing faces that share a plane (flicker)."""

from __future__ import annotations

import unittest

import numpy as np

from tools.procgen.core.civilian import moved_marking
from tools.procgen.core.coplanar import coplanar_overlaps
from tools.procgen.core.textures import Marking
from tools.procgen.parts import capital_solids as cs
from tools.procgen.parts.capital_paint import EdgeBand, edge_band, flat_faces
from tools.procgen.parts.ea_omega import PLAIN
from tools.procgen.styles.ea_capital import ea_capital
from tools.procgen.styles.ea_hyperion import PatchPlates

STYLE = ea_capital(finish="soft").style
UP = np.array([[0.0, 1.0, 0.0]])


def _plate(name: str = "plate", lo: tuple[float, float, float] = (0.0, 0.0, 0.0), hi: tuple[float, float, float] = (40.0, 2.0, 30.0)):  # noqa: ANN202
    return cs.box(name, lo, hi, STYLE, PLAIN).part.mesh


class EdgeBandTests(unittest.TestCase):
    def test_only_the_wide_faces_carry_it(self) -> None:
        faces = flat_faces(_plate(), 12.0)
        self.assertEqual(sorted(round(float(f.normal[1])) for f in faces), [-1, 1], "the top and the bottom, not the 2 m edges")

    def test_the_band_runs_in_from_the_edge(self) -> None:
        band = EdgeBand(width_m=3.0, inset_m=0.5, soft_m=0.2)
        mark = edge_band("plate", _plate(), (0.1, 0.1, 0.1), band)
        cover = mark.params["cover"]
        at = lambda x: cover(np.array([[x, 2.0, 15.0]]), UP)[0]  # noqa: E731
        self.assertAlmostEqual(at(0.2), 0.0, "the rim at the very edge stays plain")
        self.assertAlmostEqual(at(2.0), 1.0, msg="inside the band")
        self.assertAlmostEqual(at(20.0), 0.0, msg="the plate's middle")
        self.assertAlmostEqual(cover(np.array([[2.0, 1.0, 15.0]]), UP)[0], 0.0, msg="off the face's plane")
        self.assertAlmostEqual(cover(np.array([[2.0, 2.0, 15.0]]), np.array([[1.0, 0.0, 0.0]]))[0], 0.0, msg="facing elsewhere")

    def test_a_placed_paint_keeps_its_frame_when_the_part_moves(self) -> None:
        mark = edge_band("plate", _plate(), (0.1, 0.1, 0.1), EdgeBand(width_m=3.0, inset_m=0.5, soft_m=0.2))
        moved = moved_marking(mark, (-5.0, 0.0, 0.0))
        self.assertEqual(moved.params["origin"], (-5.0, 0.0, 0.0))
        point = np.array([[2.0 - 5.0, 2.0, 15.0]])  # the band's point, moved with the part
        self.assertAlmostEqual(moved.params["cover"](point - np.asarray(moved.params["origin"]), UP)[0], 1.0)

    def test_a_plain_paint_is_unchanged(self) -> None:
        self.assertNotIn("origin", Marking.paint("p", (0.0, 0.0, 0.0), lambda p, n: np.zeros(len(p))).params)


class PatchTierTests(unittest.TestCase):
    def test_tiers_give_only_their_shades(self) -> None:
        base = dict(level=3, scatter=1.0, inset_m=0.1, dark=0.0, depth=0.0, wrap="sides", long_axis=2, cell=(18.0, 9.0), splits=2, min_m=1.2,
                    keep=0.3, seed=1)
        keys = np.arange(4000)
        tiered = PatchPlates(tiers=((0.75, 0.12), (0.25, 0.4)), **base)._shade(keys)
        self.assertEqual(set(np.round(tiered, 3)), {0.12, 0.4})
        self.assertAlmostEqual(float(np.mean(tiered == 0.4)), 0.25, delta=0.03)
        spread = PatchPlates(darkest=0.5, **base)._shade(keys)
        self.assertGreater(len(set(np.round(spread, 3))), 100, "no tiers: the Hyperion's even spread")


class CoplanarTests(unittest.TestCase):
    def test_overlapping_faces_in_one_plane_are_found(self) -> None:
        a, b = _plate("a"), _plate("b", (10.0, 0.0, 10.0), (20.0, 2.0, 20.0))
        found = coplanar_overlaps([("a", a), ("b", b)], (-1.0, -1.0, -1.0), (50.0, 5.0, 50.0))
        self.assertAlmostEqual(found[("a", "b")], 200.0, places=3, msg="their tops and bottoms, 100 m2 each")

    def test_abutting_and_back_to_back_faces_are_not(self) -> None:
        a, b, c = _plate("a"), _plate("b", (40.0, 0.0, 0.0), (60.0, 2.0, 30.0)), _plate("c", (0.0, 2.0, 0.0), (40.0, 4.0, 30.0))
        self.assertEqual(coplanar_overlaps([("a", a), ("b", b), ("c", c)], (-1.0, -1.0, -1.0), (70.0, 5.0, 50.0)), {})


if __name__ == "__main__":
    unittest.main()
