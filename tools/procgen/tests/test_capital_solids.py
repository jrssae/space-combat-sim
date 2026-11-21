"""Plain solids for capital hulls (M10-T21, ``parts/capital_solids.py``): each is a closed module whose collision and burial
volume match its mesh; a round body's collision follows its profile (a waist is not filled, a nozzle's bore stays open) and
keeps every hull inside the point budget."""

from __future__ import annotations

import unittest

import numpy as np

from tools.procgen.core import collision as col
from tools.procgen.parts import capital as cp
from tools.procgen.parts import capital_solids as cs
from tools.procgen.styles.capital import FRAMEWORK_GREY

STYLE = FRAMEWORK_GREY.style


def surface(m: cp.Module) -> np.ndarray:
    mesh = m.part.mesh
    return mesh.vertices[mesh.faces].mean(axis=1)  # a point on every face


class SolidTests(unittest.TestCase):
    def test_flat_solids_are_their_corners(self) -> None:
        b = cs.box("b", (0.0, 0.0, 0.0), (4.0, 2.0, 6.0), STYLE)
        lo, hi = b.part.mesh.bounds()
        np.testing.assert_allclose(lo, (0.0, 0.0, 0.0))
        np.testing.assert_allclose(hi, (4.0, 2.0, 6.0))
        self.assertAlmostEqual(b.shapes[0].volume(), 48.0, places=6)
        self.assertTrue(b.solid.contains(np.array([[2.0, 1.0, 3.0]]))[0])
        self.assertFalse(b.solid.contains(np.array([[5.0, 1.0, 3.0]]))[0])
        plate = cs.slab("p", [(0.0, 0.0, 0.0), (10.0, 0.0, 0.0), (10.0, 0.0, 10.0), (0.0, 0.0, 10.0)], 2.0, (0.0, -1.0, 0.0), STYLE)
        self.assertAlmostEqual(float(plate.part.mesh.bounds()[0][1]), -2.0, places=6)
        with self.assertRaises(ValueError):
            cs.prism("bad", [(0.0, 0.0), (1.0, 0.0), (0.0, 1.0)], 5.0, 5.0, STYLE)

    def test_a_compound_is_its_parts_together(self) -> None:
        a, b = cs.box("a", (0, 0, 0), (1, 1, 1), STYLE), cs.box("b", (2, 0, 0), (3, 1, 1), STYLE)
        both = cs.compound("ab", [a, b])
        self.assertEqual([s.name for s in both.shapes], ["ab_0", "ab_1"])
        self.assertTrue(both.solid.contains(np.array([[2.5, 0.5, 0.5]]))[0])
        self.assertFalse(both.solid.contains(np.array([[1.5, 0.5, 0.5]]))[0], "the gap between the parts stays empty")


class RoundBodyTests(unittest.TestCase):
    # A nacelle: a drum, a narrow waist, a bell, and a bore 10 m deep from its mouth.
    PROFILE = [(0.0, 0.0), (0.0, 20.0), (40.0, 20.0), (42.0, 10.0), (60.0, 10.0), (62.0, 24.0), (100.0, 18.0), (100.0, 15.0),
               (90.0, 9.0), (90.0, 0.0)]

    def setUp(self) -> None:
        self.body = cs.round_body("n", (0.0, 0.0, 0.0), (0.0, 0.0, 100.0), self.PROFILE, STYLE, sides=20, hollow_from=7)

    def test_every_hull_keeps_inside_the_point_budget(self) -> None:
        self.assertGreater(len(self.body.shapes), 1)
        for s in self.body.shapes:
            self.assertLessEqual(len(s.points), col.MAX_HULL_POINTS, s.name)

    def test_the_collision_covers_the_surface_and_leaves_the_waist_and_the_bore_open(self) -> None:
        self.assertLessEqual(float(col.gaps(self.body.shapes, surface(self.body)).max()), 1.0, "every face within a metre")
        waist = np.array([[0.0, 15.0, 50.0]])  # outside the waist, inside the drum's and the bell's radius
        self.assertGreater(float(col.gaps(self.body.shapes, waist)[0]), 3.0)
        bore = np.array([[0.0, 0.0, 99.0]])  # on the axis just inside the mouth
        self.assertGreater(float(col.gaps(self.body.shapes, bore)[0]), 5.0)

    def test_a_wide_body_is_cut_into_wedges(self) -> None:
        disc = cs.round_body("d", (0.0, 0.0, 0.0), (0.0, 0.0, 40.0), [(0.0, 0.0), (0.0, 84.0), (40.0, 84.0), (40.0, 0.0)], STYLE, sides=24)
        self.assertGreater(len(disc.shapes), 1)
        rim = np.array([[84.0 * np.cos(a), 84.0 * np.sin(a), 20.0] for a in np.linspace(0.0, 2.0 * np.pi, 50)])
        self.assertLessEqual(float(col.gaps(disc.shapes, rim).max()), 0.01, "the rim is inside the wedges")


if __name__ == "__main__":
    unittest.main()
